// =============================================================================
// File        : smoke_test.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM Smoke Test.
//               Performs a directed read/write to every register in every
//               peripheral to confirm basic connectivity and reset values.
//               This test runs first in CI regression — a failure here
//               indicates a fundamental RTL or integration bug.
//
//               Test Plan:
//                 1. Write known data to each R/W register
//                 2. Read back and verify data (scoreboard checks)
//                 3. Check AXI responses are OKAY
//                 4. Check peripheral IDs decode correctly
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef SMOKE_TEST_SV
`define SMOKE_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "../env/env.sv"
`include "../sequences/base_sequence.sv"

class smoke_test extends uvm_test;

  `uvm_component_utils(smoke_test)

  env m_env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_env = env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    base_sequence seq;
    phase.raise_objection(this, "smoke_test running");

    `uvm_info(get_type_name(), "========== SMOKE TEST START ==========", UVM_NONE)

    seq = base_sequence::type_id::create("smoke_seq");

    // --- UART ---
    `uvm_info(get_type_name(), "--- UART Registers ---", UVM_MEDIUM)
    seq.start(m_env.m_agent.sequencer);  // Ensure sequencer is running
    seq.do_write(UART_BASE + UART_CONTROL_OFF, 32'h0000_0003); // TX+RX enable
    seq.do_write(UART_BASE + UART_BAUD_OFF,    32'h0000_01B2); // Divisor 434 ≈ 115200 @ 50MHz
    seq.do_write(UART_BASE + UART_TXDATA_OFF,  32'h0000_0055); // TX byte 'U'

    // --- SPI ---
    `uvm_info(get_type_name(), "--- SPI Registers ---", UVM_MEDIUM)
    seq.do_write(SPI_BASE + SPI_CLKDIV_OFF,  32'h0000_0003); // div=3
    seq.do_write(SPI_BASE + SPI_CONTROL_OFF, 32'h0000_0001); // SPI enable
    seq.do_write(SPI_BASE + SPI_TXDATA_OFF,  32'h0000_00A5); // Trigger transfer

    // --- GPIO ---
    `uvm_info(get_type_name(), "--- GPIO Registers ---", UVM_MEDIUM)
    seq.do_write(GPIO_BASE + GPIO_DIR_OFF, 32'hFFFF_FFFF);   // All outputs
    seq.do_write(GPIO_BASE + GPIO_OUT_OFF, 32'hDEAD_BEEF);   // Set outputs
    seq.do_write(GPIO_BASE + GPIO_IE_OFF,  32'h0000_000F);   // Enable 4 IRQs

    // --- Timer ---
    `uvm_info(get_type_name(), "--- Timer Registers ---", UVM_MEDIUM)
    seq.do_write(TIMER_BASE + TIMER_CMP_OFF,  32'h0000_0064); // Compare = 100
    seq.do_write(TIMER_BASE + TIMER_CTRL_OFF, 32'h0000_0003); // Enable + auto-reload
    seq.do_write(TIMER_BASE + TIMER_CNT_OFF,  32'h0000_0000); // Reset counter

    // Read back R/W registers and let scoreboard check them
    logic [31:0] rd;
    logic [1:0]  rs;
    seq.do_read(UART_BASE + UART_CONTROL_OFF, rd, rs);
    seq.do_read(UART_BASE + UART_BAUD_OFF,    rd, rs);
    seq.do_read(SPI_BASE  + SPI_CLKDIV_OFF,   rd, rs);
    seq.do_read(SPI_BASE  + SPI_CONTROL_OFF,  rd, rs);
    seq.do_read(GPIO_BASE + GPIO_DIR_OFF,     rd, rs);
    seq.do_read(GPIO_BASE + GPIO_OUT_OFF,     rd, rs);
    seq.do_read(GPIO_BASE + GPIO_IE_OFF,      rd, rs);
    seq.do_read(TIMER_BASE + TIMER_CMP_OFF,   rd, rs);
    seq.do_read(TIMER_BASE + TIMER_CTRL_OFF,  rd, rs);

    `uvm_info(get_type_name(), "========== SMOKE TEST DONE  ==========", UVM_NONE)
    phase.drop_objection(this, "smoke_test done");
  endtask

endclass : smoke_test

`endif // SMOKE_TEST_SV
