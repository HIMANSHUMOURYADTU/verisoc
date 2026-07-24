// =============================================================================
// File        : base_sequence.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM Base Sequence.
//               All VeriSoC sequences extend this class.
//               Provides:
//                 - Common utility tasks (write, read, poll_ready)
//                 - Configurable transaction count
//                 - Sequence-level verbosity control
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef BASE_SEQUENCE_SV
`define BASE_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "../sequence_item/axi_seq_item.sv"

class base_sequence extends uvm_sequence #(axi_seq_item);

  `uvm_object_utils(base_sequence)

  // Number of transactions to generate (overridable via plusarg)
  int unsigned num_transactions = 10;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name = "base_sequence");
    super.new(name);
  endfunction

  // ---------------------------------------------------------------------------
  // Body — overridden by child sequences
  // ---------------------------------------------------------------------------
  virtual task body();
    `uvm_info(get_type_name(), "base_sequence::body() — override in child class", UVM_MEDIUM)
  endtask

  // ---------------------------------------------------------------------------
  // Utility: Send a write transaction
  // addr  — full 32-bit AXI address
  // data  — 32-bit write data
  // wstrb — byte enables (default: all bytes)
  // ---------------------------------------------------------------------------
  task do_write(
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [3:0]  wstrb = 4'hF
  );
    axi_seq_item item;
    item             = axi_seq_item::type_id::create("wr_item");
    item.direction   = WRITE;
    item.addr        = addr;
    item.data        = data;
    item.wstrb       = wstrb;
    item.delay_cycles= 0;
    start_item(item);
    // No randomize — use the directed values set above
    finish_item(item);
    `uvm_info(get_type_name(),
      $sformatf("WRITE addr=0x%08h data=0x%08h strb=%04b resp=%0d",
                 addr, data, wstrb, item.resp), UVM_HIGH)
  endtask

  // ---------------------------------------------------------------------------
  // Utility: Send a read transaction, returns read data via ref argument
  // ---------------------------------------------------------------------------
  task do_read(
    input  logic [31:0] addr,
    output logic [31:0] rdata,
    output logic [1:0]  resp
  );
    axi_seq_item item;
    item             = axi_seq_item::type_id::create("rd_item");
    item.direction   = READ;
    item.addr        = addr;
    item.wstrb       = 4'hF;
    item.delay_cycles= 0;
    start_item(item);
    finish_item(item);
    rdata = item.data;
    resp  = item.resp;
    `uvm_info(get_type_name(),
      $sformatf("READ  addr=0x%08h data=0x%08h resp=%0d",
                 addr, rdata, resp), UVM_HIGH)
  endtask

  // ---------------------------------------------------------------------------
  // Utility: Poll a register field until condition met (timeout after N tries)
  // ---------------------------------------------------------------------------
  task poll_until(
    input  logic [31:0] addr,
    input  logic [31:0] mask,
    input  logic [31:0] expected,
    input  int unsigned timeout = 1000
  );
    logic [31:0] rd_data;
    logic [1:0]  resp;
    int          tries = 0;
    do begin
      do_read(addr, rd_data, resp);
      tries++;
      if (tries >= timeout) begin
        `uvm_error(get_type_name(),
          $sformatf("poll_until TIMEOUT: addr=0x%08h mask=0x%08h expected=0x%08h got=0x%08h",
                     addr, mask, expected, rd_data))
        return;
      end
    end while ((rd_data & mask) !== expected);
    `uvm_info(get_type_name(),
      $sformatf("poll_until DONE after %0d tries: addr=0x%08h val=0x%08h", tries, addr, rd_data),
      UVM_MEDIUM)
  endtask

endclass : base_sequence

`endif // BASE_SEQUENCE_SV
