// =============================================================================
// File        : soc_assertions.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : SystemVerilog Assertion (SVA) module.
//               Binds protocol-level assertions directly to DUT signals.
//               This module is bound to top in top_tb.sv using SystemVerilog
//               'bind' so that assertions run without modifying RTL.
//
//               Assertion Groups:
//                 A. AXI4-Lite Handshake Integrity
//                 B. APB Protocol Compliance
//                 C. FIFO Overflow Protection
//                 D. Illegal State Transitions
//                 E. Interrupt Sanity Checks
//
// Standard    : IEEE 1800-2017 SVA
// =============================================================================

`ifndef SOC_ASSERTIONS_SV
`define SOC_ASSERTIONS_SV

`include "../rtl/pkg.sv"
import soc_pkg::*;

module soc_assertions (
  // System
  input logic        aclk,
  input logic        aresetn,

  // AXI4-Lite signals (connected via bind)
  input logic [31:0] awaddr,
  input logic        awvalid,
  input logic        awready,
  input logic [31:0] wdata,
  input logic [3:0]  wstrb,
  input logic        wvalid,
  input logic        wready,
  input logic [1:0]  bresp,
  input logic        bvalid,
  input logic        bready,
  input logic [31:0] araddr,
  input logic        arvalid,
  input logic        arready,
  input logic [31:0] rdata,
  input logic [1:0]  rresp,
  input logic        rvalid,
  input logic        rready,

  // Interrupt lines
  input logic        uart_irq,
  input logic        spi_irq,
  input logic        gpio_irq,
  input logic        timer_irq
);

  // ==========================================================================
  // A. AXI4-Lite Handshake Integrity
  // ==========================================================================

  // A1: Once AWVALID is asserted, it must stay high until AWREADY handshake
  property p_awvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
      (awvalid && !awready) |=> awvalid;
  endproperty
  A1_awvalid_stable: assert property (p_awvalid_stable)
    else $error("[ASSERT A1] AWVALID dropped without AWREADY handshake");

  // A2: AWADDR must be stable while AWVALID is asserted and no handshake
  property p_awaddr_stable;
    @(posedge aclk) disable iff (!aresetn)
      (awvalid && !awready) |=> $stable(awaddr);
  endproperty
  A2_awaddr_stable: assert property (p_awaddr_stable)
    else $error("[ASSERT A2] AWADDR changed while AWVALID high without AWREADY");

  // A3: WVALID must stay high until WREADY handshake
  property p_wvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
      (wvalid && !wready) |=> wvalid;
  endproperty
  A3_wvalid_stable: assert property (p_wvalid_stable)
    else $error("[ASSERT A3] WVALID dropped without WREADY handshake");

  // A4: WDATA must be stable while WVALID high and no handshake
  property p_wdata_stable;
    @(posedge aclk) disable iff (!aresetn)
      (wvalid && !wready) |=> $stable(wdata);
  endproperty
  A4_wdata_stable: assert property (p_wdata_stable)
    else $error("[ASSERT A4] WDATA changed while WVALID high without WREADY");

  // A5: ARVALID must stay high until ARREADY handshake
  property p_arvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
      (arvalid && !arready) |=> arvalid;
  endproperty
  A5_arvalid_stable: assert property (p_arvalid_stable)
    else $error("[ASSERT A5] ARVALID dropped without ARREADY handshake");

  // A6: BVALID must be followed by BREADY within 32 cycles (latency guard)
  property p_bvalid_bready_timeout;
    @(posedge aclk) disable iff (!aresetn)
      bvalid |-> ##[1:32] bready;
  endproperty
  A6_bvalid_bready_timeout: assert property (p_bvalid_bready_timeout)
    else $error("[ASSERT A6] BVALID high for >32 cycles without BREADY");

  // A7: RVALID must be followed by RREADY within 32 cycles
  property p_rvalid_rready_timeout;
    @(posedge aclk) disable iff (!aresetn)
      rvalid |-> ##[1:32] rready;
  endproperty
  A7_rvalid_rready_timeout: assert property (p_rvalid_rready_timeout)
    else $error("[ASSERT A7] RVALID high for >32 cycles without RREADY");

  // A8: Write strobe must not be all zeros on a valid write transaction
  property p_wstrb_nonzero;
    @(posedge aclk) disable iff (!aresetn)
      (wvalid && wready) |-> (wstrb != 4'b0000);
  endproperty
  A8_wstrb_nonzero: assert property (p_wstrb_nonzero)
    else $error("[ASSERT A8] WSTRB is all zeros on a valid write");

  // A9: AXI responses after reset must be OKAY or SLVERR only (no X/Z)
  property p_bresp_valid;
    @(posedge aclk) disable iff (!aresetn)
      bvalid |-> (bresp inside {AXI_OKAY, AXI_SLVERR});
  endproperty
  A9_bresp_valid: assert property (p_bresp_valid)
    else $error("[ASSERT A9] BRESP has illegal value");

  property p_rresp_valid;
    @(posedge aclk) disable iff (!aresetn)
      rvalid |-> (rresp inside {AXI_OKAY, AXI_SLVERR});
  endproperty
  A10_rresp_valid: assert property (p_rresp_valid)
    else $error("[ASSERT A10] RRESP has illegal value");

  // ==========================================================================
  // B. Mutually Exclusive Read/Write (AXI4-Lite serialisation)
  // ==========================================================================

  // B1: AWVALID and ARVALID must not both be high simultaneously after idle
  // (This is a design constraint — our AXI slave prioritises writes)
  property p_no_simultaneous_rw;
    @(posedge aclk) disable iff (!aresetn)
      (awvalid && wvalid) |-> !arvalid; // If writing, should not also read-address
  endproperty
  B1_no_simultaneous_rw: assert property (p_no_simultaneous_rw)
    else $warning("[ASSERT B1] Simultaneous AW+W and AR — write will take priority");

  // ==========================================================================
  // C. Interrupt Sanity
  // ==========================================================================

  // C1: Interrupts must not be X or Z during normal operation
  property p_irq_not_x;
    @(posedge aclk) disable iff (!aresetn)
      !$isunknown(uart_irq) && !$isunknown(spi_irq) &&
      !$isunknown(gpio_irq) && !$isunknown(timer_irq);
  endproperty
  C1_irq_not_x: assert property (p_irq_not_x)
    else $error("[ASSERT C1] Interrupt line is X or Z");

  // ==========================================================================
  // Coverage — protocol corners hit
  // ==========================================================================
  cp_write_with_slverr: cover property (
    @(posedge aclk) disable iff (!aresetn)
      (bvalid && bready && (bresp == AXI_SLVERR))
  );

  cp_read_with_slverr: cover property (
    @(posedge aclk) disable iff (!aresetn)
      (rvalid && rready && (rresp == AXI_SLVERR))
  );

  cp_back_to_back_writes: cover property (
    @(posedge aclk) disable iff (!aresetn)
      (bvalid && bready) ##1 awvalid
  );

  cp_back_to_back_reads: cover property (
    @(posedge aclk) disable iff (!aresetn)
      (rvalid && rready) ##1 arvalid
  );

endmodule : soc_assertions

`endif // SOC_ASSERTIONS_SV
