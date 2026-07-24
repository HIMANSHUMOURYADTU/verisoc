// =============================================================================
// File        : random_sequence.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM Random Sequence.
//               Generates fully randomized AXI4-Lite transactions using the
//               constraints defined in axi_seq_item.  The number of
//               transactions is configurable via num_transactions.
//               Used by: random_test, regression_test
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef RANDOM_SEQUENCE_SV
`define RANDOM_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "base_sequence.sv"

class random_sequence extends base_sequence;

  `uvm_object_utils(random_sequence)

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name = "random_sequence");
    super.new(name);
    num_transactions = 100; // Default: 100 random transactions
  endfunction

  // ---------------------------------------------------------------------------
  // Body — generate randomized transactions
  // ---------------------------------------------------------------------------
  virtual task body();
    axi_seq_item item;
    `uvm_info(get_type_name(),
      $sformatf("Starting random_sequence: %0d transactions", num_transactions), UVM_MEDIUM)

    repeat (num_transactions) begin
      item = axi_seq_item::type_id::create("rand_item");
      start_item(item);
      if (!item.randomize()) begin
        `uvm_fatal(get_type_name(), "Randomization failed for axi_seq_item")
      end
      finish_item(item);

      `uvm_info(get_type_name(), item.convert2string(), UVM_HIGH)

      // Optional inter-transaction idle gap
      if (item.delay_cycles > 0) begin
        repeat (item.delay_cycles) @(sequencer.get_sequencer_time);
      end
    end

    `uvm_info(get_type_name(), "random_sequence complete", UVM_MEDIUM)
  endtask

endclass : random_sequence

`endif // RANDOM_SEQUENCE_SV
