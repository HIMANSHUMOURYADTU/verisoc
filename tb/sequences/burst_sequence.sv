// =============================================================================
// File        : burst_sequence.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM Burst Sequence.
//               Generates sequences of back-to-back AXI4-Lite transactions
//               targeting the same peripheral (address-contiguous burst).
//               Simulates register-dump and peripheral initialisation
//               patterns that are common in embedded firmware flows.
//
//               Burst modes:
//                 WRITE_BURST — write to N consecutive aligned addresses
//                 READ_BURST  — read  from N consecutive aligned addresses
//                 RW_BURST    — write then read-back for data integrity check
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef BURST_SEQUENCE_SV
`define BURST_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "base_sequence.sv"

class burst_sequence extends base_sequence;

  `uvm_object_utils(burst_sequence)

  // ---------------------------------------------------------------------------
  // Burst mode enum
  // ---------------------------------------------------------------------------
  typedef enum { WRITE_BURST, READ_BURST, RW_BURST } burst_mode_t;

  // Configurable parameters
  rand burst_mode_t   mode;
  rand logic [31:0]   start_addr; // Must be word-aligned, valid peripheral
  rand int unsigned   burst_len;  // Number of words in burst

  // Constraints
  constraint c_burst_mode  { mode dist { WRITE_BURST := 40, READ_BURST := 30, RW_BURST := 30 }; }
  constraint c_burst_len   { burst_len inside { [1:8] }; }
  constraint c_burst_addr  {
    start_addr inside {
      [32'h0000_0000 : 32'h0000_0000],  // UART base
      [32'h0000_1000 : 32'h0000_1000],  // SPI base
      [32'h0000_2000 : 32'h0000_2000],  // GPIO base
      [32'h0000_3000 : 32'h0000_3000]   // Timer base
    };
    start_addr[1:0] == 2'b00; // Word-aligned
  }

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name = "burst_sequence");
    super.new(name);
    num_transactions = 5; // Number of bursts
  endfunction

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------
  virtual task body();
    logic [31:0] wr_data;
    logic [31:0] rd_data;
    logic [1:0]  resp;

    `uvm_info(get_type_name(),
      $sformatf("Starting burst_sequence: %0d bursts", num_transactions), UVM_MEDIUM)

    repeat (num_transactions) begin
      // Randomize burst parameters
      if (!this.randomize()) begin
        `uvm_fatal(get_type_name(), "Burst parameter randomization failed")
      end

      `uvm_info(get_type_name(),
        $sformatf("Burst: mode=%s start=0x%08h len=%0d",
                   mode.name(), start_addr, burst_len), UVM_MEDIUM)

      case (mode)
        // Write N words starting from start_addr
        WRITE_BURST: begin
          for (int i = 0; i < int'(burst_len); i++) begin
            wr_data = $urandom();
            do_write(start_addr + 4*i, wr_data, 4'hF);
          end
        end

        // Read N words starting from start_addr
        READ_BURST: begin
          for (int i = 0; i < int'(burst_len); i++) begin
            do_read(start_addr + 4*i, rd_data, resp);
          end
        end

        // Write then read-back; log mismatches (expected data known)
        RW_BURST: begin
          logic [31:0] written_data [$];
          // Write phase
          for (int i = 0; i < int'(burst_len); i++) begin
            wr_data = $urandom();
            written_data.push_back(wr_data);
            do_write(start_addr + 4*i, wr_data, 4'hF);
          end
          // Read-back phase
          for (int i = 0; i < int'(burst_len); i++) begin
            do_read(start_addr + 4*i, rd_data, resp);
            `uvm_info(get_type_name(),
              $sformatf("RW_BURST readback[%0d]: addr=0x%08h rd=0x%08h",
                         i, start_addr + 4*i, rd_data), UVM_HIGH)
          end
        end
      endcase
    end

    `uvm_info(get_type_name(), "burst_sequence complete", UVM_MEDIUM)
  endtask

endclass : burst_sequence

`endif // BURST_SEQUENCE_SV
