// =============================================================================
// File        : random_test.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM Random Test.
//               Runs a fully randomized sequence of AXI4-Lite transactions
//               using all constraints defined in axi_seq_item.
//               Transaction count is configurable via +num_txns=<N> plusarg.
//               Coverage and scoreboard are active throughout.
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef RANDOM_TEST_SV
`define RANDOM_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "../env/env.sv"
`include "../sequences/random_sequence.sv"

class random_test extends uvm_test;

  `uvm_component_utils(random_test)

  env m_env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_env = env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    random_sequence seq;
    int unsigned n_txns;
    phase.raise_objection(this, "random_test running");

    // Allow overriding transaction count via plusarg
    if ($value$plusargs("num_txns=%0d", n_txns))
      `uvm_info(get_type_name(),
        $sformatf("Overriding num_transactions to %0d via plusarg", n_txns), UVM_MEDIUM)
    else
      n_txns = 200; // Default

    `uvm_info(get_type_name(),
      $sformatf("========== RANDOM TEST START (%0d txns) ==========", n_txns), UVM_NONE)

    seq = random_sequence::type_id::create("rand_seq");
    seq.num_transactions = n_txns;
    seq.start(m_env.m_agent.sequencer);

    `uvm_info(get_type_name(), "========== RANDOM TEST DONE  ==========", UVM_NONE)
    phase.drop_objection(this, "random_test done");
  endtask

endclass : random_test

`endif // RANDOM_TEST_SV
