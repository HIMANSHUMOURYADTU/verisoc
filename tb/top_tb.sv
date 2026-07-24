// =============================================================================
// File        : top_tb.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : Top-Level Testbench Module.
//               - Instantiates the DUT (rtl/top.sv)
//               - Instantiates the AXI4-Lite interface
//               - Connects interface to DUT
//               - Binds assertion module (soc_assertions) to DUT
//               - Generates clock and reset
//               - Starts UVM test via run_test()
//               - Configures virtual interface in UVM config_db
//               - Dumps VCD/FSDB waveform
//
// Usage:
//   Pass +UVM_TESTNAME=<test_class> on simulator command line:
//     +UVM_TESTNAME=smoke_test
//     +UVM_TESTNAME=random_test
//     +UVM_TESTNAME=regression_test
//
// Standard    : IEEE 1800-2017
// =============================================================================

`timescale 1ns/1ps

`include "rtl/pkg.sv"
import soc_pkg::*;

// UVM
`include "uvm_macros.svh"
import uvm_pkg::*;

// Interfaces
`include "tb/interface/axi_lite_if.sv"
`include "tb/interface/apb_if.sv"

// Assertions
`include "tb/assertions/soc_assertions.sv"

// Tests (all test types included — selected via +UVM_TESTNAME)
`include "tb/tests/smoke_test.sv"
`include "tb/tests/random_test.sv"
`include "tb/tests/regression_test.sv"

module top_tb;

  // ---------------------------------------------------------------------------
  // Clock and Reset generation
  // ---------------------------------------------------------------------------
  localparam int CLK_PERIOD_NS = 20; // 50 MHz clock

  logic aclk    = 1'b0;
  logic aresetn = 1'b0;

  // Clock: toggle every half period
  always #(CLK_PERIOD_NS/2) aclk = ~aclk;

  // Reset: assert for 10 cycles then deassert
  initial begin
    aresetn = 1'b0;
    repeat (10) @(posedge aclk);
    aresetn = 1'b1;
    `uvm_info("TOP_TB", "Reset deasserted", UVM_MEDIUM)
  end

  // ---------------------------------------------------------------------------
  // AXI4-Lite Interface instantiation
  // ---------------------------------------------------------------------------
  axi_lite_if #(
    .DATA_W (soc_pkg::DATA_WIDTH),
    .ADDR_W (soc_pkg::ADDR_WIDTH)
  ) axi_if (
    .aclk    (aclk),
    .aresetn (aresetn)
  );

  // ---------------------------------------------------------------------------
  // GPIO loopback — connect GPIO output back to input for testing
  // ---------------------------------------------------------------------------
  logic [31:0] gpio_out_sig;
  logic [31:0] gpio_oe_sig;
  logic [31:0] gpio_in_sig;

  // Loopback: when pin is output, feed output back as input
  assign gpio_in_sig = gpio_out_sig & gpio_oe_sig;

  // ---------------------------------------------------------------------------
  // SPI loopback — MOSI looped to MISO for self-check
  // ---------------------------------------------------------------------------
  logic spi_mosi_sig;
  wire  spi_miso_sig = spi_mosi_sig; // Loopback

  // ---------------------------------------------------------------------------
  // UART loopback — TX tied to RX for echo test
  // ---------------------------------------------------------------------------
  logic uart_tx_sig;
  wire  uart_rx_sig = uart_tx_sig;

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  top #(
    .DATA_W    (soc_pkg::DATA_WIDTH),
    .ADDR_W    (soc_pkg::ADDR_WIDTH),
    .GPIO_W    (32),
    .UART_FIFO (8)
  ) dut (
    // Clocks
    .aclk     (aclk),
    .aresetn  (aresetn),

    // AXI4-Lite — driven by interface
    .awaddr   (axi_if.awaddr),
    .awvalid  (axi_if.awvalid),
    .awready  (axi_if.awready),
    .wdata    (axi_if.wdata),
    .wstrb    (axi_if.wstrb),
    .wvalid   (axi_if.wvalid),
    .wready   (axi_if.wready),
    .bresp    (axi_if.bresp),
    .bvalid   (axi_if.bvalid),
    .bready   (axi_if.bready),
    .araddr   (axi_if.araddr),
    .arvalid  (axi_if.arvalid),
    .arready  (axi_if.arready),
    .rdata    (axi_if.rdata),
    .rresp    (axi_if.rresp),
    .rvalid   (axi_if.rvalid),
    .rready   (axi_if.rready),

    // UART
    .uart_rx  (uart_rx_sig),
    .uart_tx  (uart_tx_sig),

    // SPI
    .spi_sck  (),           // Not monitored in TB (observable on waveform)
    .spi_mosi (spi_mosi_sig),
    .spi_miso (spi_miso_sig),
    .spi_cs_n (),

    // GPIO
    .gpio_in  (gpio_in_sig),
    .gpio_out (gpio_out_sig),
    .gpio_oe  (gpio_oe_sig),

    // Interrupts (visible in waveform)
    .uart_irq (),
    .spi_irq  (),
    .gpio_irq (),
    .timer_irq()
  );

  // ---------------------------------------------------------------------------
  // Bind assertion module to DUT top
  // ---------------------------------------------------------------------------
  bind top soc_assertions u_assertions (
    .aclk      (aclk),
    .aresetn   (aresetn),
    .awaddr    (awaddr),
    .awvalid   (awvalid),
    .awready   (awready),
    .wdata     (wdata),
    .wstrb     (wstrb),
    .wvalid    (wvalid),
    .wready    (wready),
    .bresp     (bresp),
    .bvalid    (bvalid),
    .bready    (bready),
    .araddr    (araddr),
    .arvalid   (arvalid),
    .arready   (arready),
    .rdata     (rdata),
    .rresp     (rresp),
    .rvalid    (rvalid),
    .rready    (rready),
    .uart_irq  (uart_irq),
    .spi_irq   (spi_irq),
    .gpio_irq  (gpio_irq),
    .timer_irq (timer_irq)
  );

  // ---------------------------------------------------------------------------
  // UVM config_db — provide virtual interface to environment
  // ---------------------------------------------------------------------------
  initial begin
    // Set master VIF for driver
    uvm_config_db #(virtual axi_lite_if.master)::set(
      null, "uvm_test_top.m_env.m_agent.driver", "vif", axi_if.master);
    // Set monitor VIF for monitor
    uvm_config_db #(virtual axi_lite_if.monitor)::set(
      null, "uvm_test_top.m_env.m_agent.monitor", "vif", axi_if.monitor);
  end

  // ---------------------------------------------------------------------------
  // Waveform dump
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("verisoc_waves.vcd");
    $dumpvars(0, top_tb);
    `uvm_info("TOP_TB", "Waveform dump enabled: verisoc_waves.vcd", UVM_MEDIUM)
  end

  // ---------------------------------------------------------------------------
  // Simulation timeout guard (prevent runaway simulations)
  // ---------------------------------------------------------------------------
  initial begin
    #5_000_000; // 5 ms timeout at 1ns timescale
    `uvm_fatal("TOP_TB", "Simulation timeout — test took too long")
  end

  // ---------------------------------------------------------------------------
  // Start UVM test
  // ---------------------------------------------------------------------------
  initial begin
    run_test(); // Test name passed via +UVM_TESTNAME=<name>
  end

endmodule : top_tb
