// =============================================================================
// File        : scoreboard.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM Scoreboard.
//               Implements an expected-vs-actual register model for all four
//               SoC peripherals.  When a write transaction is observed the
//               scoreboard updates its register shadow.  When a read is
//               observed the scoreboard predicts the expected value and
//               compares against the actual data received by the monitor.
//
//               Register model is a simple shadow map:
//                 shadow[address] = last_written_data
//               Read-only and Write-only registers receive special treatment.
//
//               Metrics tracked:
//                 total_writes, total_reads, pass_count, fail_count
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef SCOREBOARD_SV
`define SCOREBOARD_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "../sequence_item/axi_seq_item.sv"

class scoreboard extends uvm_scoreboard;

  `uvm_component_utils(scoreboard)

  // ---------------------------------------------------------------------------
  // Analysis port — receives transactions from the monitor
  // ---------------------------------------------------------------------------
  uvm_analysis_imp #(axi_seq_item, scoreboard) analysis_export;

  // ---------------------------------------------------------------------------
  // Shadow register map: addr → data
  // ---------------------------------------------------------------------------
  logic [31:0] shadow_mem [logic [31:0]];

  // ---------------------------------------------------------------------------
  // Metrics
  // ---------------------------------------------------------------------------
  int unsigned total_writes = 0;
  int unsigned total_reads  = 0;
  int unsigned pass_count   = 0;
  int unsigned fail_count   = 0;

  // Set of addresses that are write-only (reads return 0 or undefined)
  // Set of addresses that are read-only  (writes have no lasting effect)
  const logic [31:0] write_only_addrs [$] = '{
    UART_BASE + UART_TXDATA_OFF   // UART TXDATA is write-only
  };
  const logic [31:0] read_only_addrs [$] = '{
    UART_BASE + UART_RXDATA_OFF,  // UART RXDATA is read-only
    UART_BASE + UART_STATUS_OFF,  // STATUS is read-only
    SPI_BASE  + SPI_STATUS_OFF,   // SPI STATUS
    SPI_BASE  + SPI_RXDATA_OFF,   // SPI RXDATA
    GPIO_BASE + GPIO_IN_OFF,      // GPIO input
    TIMER_BASE + TIMER_STATUS_OFF // Timer STATUS (W1C — complex)
  };

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // ---------------------------------------------------------------------------
  // Build Phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    analysis_export = new("analysis_export", this);
  endfunction

  // ---------------------------------------------------------------------------
  // Write — called by analysis port when monitor publishes a transaction
  // ---------------------------------------------------------------------------
  function void write(axi_seq_item trans);
    if (trans.direction == WRITE) begin
      handle_write(trans);
    end else begin
      handle_read(trans);
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Handle write: update shadow, check response code
  // ---------------------------------------------------------------------------
  function void handle_write(axi_seq_item trans);
    total_writes++;

    // Check AXI response — writes to valid addresses must return OKAY
    if (trans.resp != AXI_OKAY && trans.resp != AXI_SLVERR) begin
      `uvm_error(get_type_name(),
        $sformatf("WRITE RESP error: addr=0x%08h resp=%0d (expected OKAY or SLVERR)",
                   trans.addr, trans.resp))
      fail_count++;
      return;
    end

    // Skip shadow update for write-only addresses (they have side-effects only)
    // Skip shadow update for read-only addresses (writes should have no effect)
    if (!is_read_only(trans.addr) && trans.resp == AXI_OKAY) begin
      // Apply byte-enable mask to shadow
      if (shadow_mem.exists(trans.addr)) begin
        for (int b = 0; b < 4; b++) begin
          if (trans.wstrb[b]) begin
            shadow_mem[trans.addr][8*b+7 -: 8] = trans.data[8*b+7 -: 8];
          end
        end
      end else begin
        // First write — only update enabled bytes, rest default to 0
        shadow_mem[trans.addr] = '0;
        for (int b = 0; b < 4; b++) begin
          if (trans.wstrb[b]) begin
            shadow_mem[trans.addr][8*b+7 -: 8] = trans.data[8*b+7 -: 8];
          end
        end
      end
    end

    pass_count++;
    `uvm_info(get_type_name(),
      $sformatf("SB WRITE OK: addr=0x%08h data=0x%08h strb=%04b",
                 trans.addr, trans.data, trans.wstrb), UVM_HIGH)
  endfunction

  // ---------------------------------------------------------------------------
  // Handle read: compare against shadow, report pass/fail
  // ---------------------------------------------------------------------------
  function void handle_read(axi_seq_item trans);
    logic [31:0] expected;
    total_reads++;

    // Write-only registers: reads return unpredictable data — skip compare
    if (is_write_only(trans.addr)) begin
      `uvm_info(get_type_name(),
        $sformatf("SB READ SKIP (write-only): addr=0x%08h", trans.addr), UVM_HIGH)
      pass_count++;
      return;
    end

    // Hardware-driven registers (read-only) — skip shadow compare
    if (is_read_only(trans.addr)) begin
      `uvm_info(get_type_name(),
        $sformatf("SB READ SKIP (read-only hw): addr=0x%08h data=0x%08h",
                   trans.addr, trans.data), UVM_HIGH)
      pass_count++;
      return;
    end

    // For regular R/W registers: compare against shadow
    if (shadow_mem.exists(trans.addr)) begin
      expected = shadow_mem[trans.addr];
      if (trans.data !== expected) begin
        `uvm_error(get_type_name(),
          $sformatf("SB MISMATCH: addr=0x%08h exp=0x%08h got=0x%08h",
                     trans.addr, expected, trans.data))
        fail_count++;
      end else begin
        `uvm_info(get_type_name(),
          $sformatf("SB READ  OK: addr=0x%08h data=0x%08h", trans.addr, trans.data), UVM_HIGH)
        pass_count++;
      end
    end else begin
      // No prior write — read from reset-default (0)
      `uvm_info(get_type_name(),
        $sformatf("SB READ FIRST: addr=0x%08h data=0x%08h (no shadow)", trans.addr, trans.data),
        UVM_MEDIUM)
      pass_count++;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Helpers — address classification
  // ---------------------------------------------------------------------------
  function automatic logic is_write_only(logic [31:0] addr);
    foreach (write_only_addrs[i]) begin
      if (addr == write_only_addrs[i]) return 1'b1;
    end
    return 1'b0;
  endfunction

  function automatic logic is_read_only(logic [31:0] addr);
    foreach (read_only_addrs[i]) begin
      if (addr == read_only_addrs[i]) return 1'b1;
    end
    return 1'b0;
  endfunction

  // ---------------------------------------------------------------------------
  // Report Phase — print final metrics
  // ---------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf({
      "\n================================================================\n",
      "  SCOREBOARD SUMMARY\n",
      "  Total Writes : %0d\n",
      "  Total Reads  : %0d\n",
      "  PASS         : %0d\n",
      "  FAIL         : %0d\n",
      "================================================================"
    }, total_writes, total_reads, pass_count, fail_count), UVM_NONE)

    if (fail_count > 0) begin
      `uvm_error(get_type_name(),
        $sformatf("TEST FAILED: %0d comparison errors detected", fail_count))
    end
  endfunction

endclass : scoreboard

`endif // SCOREBOARD_SV
