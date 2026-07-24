// =============================================================================
// File        : regression_test.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM Regression Test.
//               Master regression test that sequentially executes:
//                 Phase 1 — Directed smoke-style writes to all peripherals
//                 Phase 2 — Burst sequence (write+readback for each peripheral)
//                 Phase 3 — High-volume random sequence (1000 transactions)
//                 Phase 4 — Interrupt validation (timer + GPIO)
//               Designed to close functional coverage in a single run.
//               Used by the Python regression script (scripts/run.py).
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef REGRESSION_TEST_SV
`define REGRESSION_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "../env/env.sv"
`include "../sequences/base_sequence.sv"
`include "../sequences/random_sequence.sv"
`include "../sequences/burst_sequence.sv"

class regression_test extends uvm_test;

  `uvm_component_utils(regression_test)

  env m_env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_env = env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    base_sequence   smoke_seq;
    burst_sequence  burst_seq;
    random_sequence rand_seq;
    logic [31:0] rd;
    logic [1:0]  rs;

    phase.raise_objection(this, "regression_test running");
    `uvm_info(get_type_name(), "====== REGRESSION TEST START ======", UVM_NONE)

    // ------------------------------------------------------------------
    // Phase 1: Directed Initialisation
    // ------------------------------------------------------------------
    `uvm_info(get_type_name(), "Phase 1: Directed init", UVM_MEDIUM)
    smoke_seq = base_sequence::type_id::create("smoke");

    // UART init
    smoke_seq.do_write(UART_BASE + UART_CONTROL_OFF, 32'h03);
    smoke_seq.do_write(UART_BASE + UART_BAUD_OFF,    32'h01B2);
    // SPI init
    smoke_seq.do_write(SPI_BASE + SPI_CLKDIV_OFF,   32'h07);
    smoke_seq.do_write(SPI_BASE + SPI_CONTROL_OFF,  32'h01);
    // GPIO init — lower 16 outputs, upper 16 inputs
    smoke_seq.do_write(GPIO_BASE + GPIO_DIR_OFF,     32'h0000_FFFF);
    smoke_seq.do_write(GPIO_BASE + GPIO_OUT_OFF,     32'h0000_1234);
    smoke_seq.do_write(GPIO_BASE + GPIO_IE_OFF,      32'hFFFF_0000);
    // Timer: auto-reload at 1000
    smoke_seq.do_write(TIMER_BASE + TIMER_CMP_OFF,   32'h0000_03E8);
    smoke_seq.do_write(TIMER_BASE + TIMER_CTRL_OFF,  32'h0000_0003);

    // ------------------------------------------------------------------
    // Phase 2: Burst sequence (all modes, all peripherals)
    // ------------------------------------------------------------------
    `uvm_info(get_type_name(), "Phase 2: Burst sequence", UVM_MEDIUM)
    burst_seq = burst_sequence::type_id::create("burst");
    burst_seq.num_transactions = 20;
    burst_seq.start(m_env.m_agent.sequencer);

    // ------------------------------------------------------------------
    // Phase 3: Random high-volume
    // ------------------------------------------------------------------
    `uvm_info(get_type_name(), "Phase 3: Random (1000 txns)", UVM_MEDIUM)
    rand_seq = random_sequence::type_id::create("rand");
    rand_seq.num_transactions = 1000;
    rand_seq.start(m_env.m_agent.sequencer);

    // ------------------------------------------------------------------
    // Phase 4: Interrupt validation
    // ------------------------------------------------------------------
    `uvm_info(get_type_name(), "Phase 4: Interrupt check", UVM_MEDIUM)
    // Enable timer, wait for match, poll status
    smoke_seq.do_write(TIMER_BASE + TIMER_CNT_OFF,  32'h0000_03E0); // Near compare
    smoke_seq.do_write(TIMER_BASE + TIMER_CTRL_OFF, 32'h0000_0001); // Enable
    smoke_seq.poll_until(
      .addr     (TIMER_BASE + TIMER_STATUS_OFF),
      .mask     (32'h0000_0001),
      .expected (32'h0000_0001),
      .timeout  (500)
    );
    // Clear interrupt
    smoke_seq.do_write(TIMER_BASE + TIMER_STATUS_OFF, 32'h0000_0001);

    `uvm_info(get_type_name(), "====== REGRESSION TEST DONE  ======", UVM_NONE)
    phase.drop_objection(this, "regression_test done");
  endtask

endclass : regression_test

`endif // REGRESSION_TEST_SV
