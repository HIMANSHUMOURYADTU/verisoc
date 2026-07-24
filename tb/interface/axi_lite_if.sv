// =============================================================================
// File        : axi_lite_if.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : SystemVerilog interface for AXI4-Lite bus.
//               Provides modports for:
//                 - master  (TB driver drives signals, DUT responds)
//                 - slave   (DUT drives outputs, TB monitors)
//                 - monitor (all signals visible, read-only)
//
//               Includes clocking block for synchronous stimulus and sampling.
//               The interface is parameterized to match soc_pkg widths.
//
// Standard    : IEEE 1800-2017
// =============================================================================

`include "../rtl/pkg.sv"
import soc_pkg::*;

interface axi_lite_if #(
  parameter int unsigned DATA_W = soc_pkg::DATA_WIDTH,
  parameter int unsigned ADDR_W = soc_pkg::ADDR_WIDTH
) (
  input logic aclk,
  input logic aresetn
);

  // ---------------------------------------------------------------------------
  // AXI4-Lite Signal Declarations
  // ---------------------------------------------------------------------------

  // Write Address Channel
  logic [ADDR_W-1:0] awaddr;
  logic              awvalid;
  logic              awready;

  // Write Data Channel
  logic [DATA_W-1:0]   wdata;
  logic [DATA_W/8-1:0] wstrb;
  logic                wvalid;
  logic                wready;

  // Write Response Channel
  logic [1:0] bresp;
  logic       bvalid;
  logic       bready;

  // Read Address Channel
  logic [ADDR_W-1:0] araddr;
  logic              arvalid;
  logic              arready;

  // Read Data Channel
  logic [DATA_W-1:0] rdata;
  logic [1:0]        rresp;
  logic              rvalid;
  logic              rready;

  // ---------------------------------------------------------------------------
  // Clocking Block for Master (Driver) — synchronises stimulus to clock
  // ---------------------------------------------------------------------------
  clocking master_cb @(posedge aclk);
    default input  #1step output #1;

    // Write Address Channel
    output awaddr;
    output awvalid;
    input  awready;

    // Write Data Channel
    output wdata;
    output wstrb;
    output wvalid;
    input  wready;

    // Write Response Channel
    input  bresp;
    input  bvalid;
    output bready;

    // Read Address Channel
    output araddr;
    output arvalid;
    input  arready;

    // Read Data Channel
    input  rdata;
    input  rresp;
    input  rvalid;
    output rready;
  endclocking

  // ---------------------------------------------------------------------------
  // Clocking Block for Monitor — all signals are inputs (read-only)
  // ---------------------------------------------------------------------------
  clocking monitor_cb @(posedge aclk);
    default input #1step;

    input awaddr;
    input awvalid;
    input awready;
    input wdata;
    input wstrb;
    input wvalid;
    input wready;
    input bresp;
    input bvalid;
    input bready;
    input araddr;
    input arvalid;
    input arready;
    input rdata;
    input rresp;
    input rvalid;
    input rready;
  endclocking

  // ---------------------------------------------------------------------------
  // Modport: Master (used by AXI driver)
  // ---------------------------------------------------------------------------
  modport master (
    clocking master_cb,
    input    aclk,
    input    aresetn
  );

  // ---------------------------------------------------------------------------
  // Modport: Monitor (used by AXI monitor)
  // ---------------------------------------------------------------------------
  modport monitor (
    clocking monitor_cb,
    input    aclk,
    input    aresetn
  );

  // ---------------------------------------------------------------------------
  // Modport: DUT connection (used in top_tb.sv)
  // ---------------------------------------------------------------------------
  modport dut (
    // Write Address
    output awaddr, awvalid, input awready,
    // Write Data
    output wdata, wstrb, wvalid, input wready,
    // Write Response
    input  bresp, bvalid, output bready,
    // Read Address
    output araddr, arvalid, input arready,
    // Read Data
    input  rdata, rresp, rvalid, output rready,
    input  aclk, aresetn
  );

  // ---------------------------------------------------------------------------
  // Protocol Assertions (static, always active in simulation)
  // ---------------------------------------------------------------------------

  // AXI4-Lite: AWVALID must not deassert without a handshake
  property p_awvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
      (awvalid && !awready) |=> awvalid;
  endproperty
  a_awvalid_stable: assert property (p_awvalid_stable)
    else $error("AXI4-Lite violation: AWVALID deasserted without AWREADY");

  // AXI4-Lite: WVALID must not deassert without a handshake
  property p_wvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
      (wvalid && !wready) |=> wvalid;
  endproperty
  a_wvalid_stable: assert property (p_wvalid_stable)
    else $error("AXI4-Lite violation: WVALID deasserted without WREADY");

  // AXI4-Lite: ARVALID must not deassert without a handshake
  property p_arvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
      (arvalid && !arready) |=> arvalid;
  endproperty
  a_arvalid_stable: assert property (p_arvalid_stable)
    else $error("AXI4-Lite violation: ARVALID deasserted without ARREADY");

  // AXI4-Lite: AWADDR must be stable while AWVALID is high
  property p_awaddr_stable;
    @(posedge aclk) disable iff (!aresetn)
      (awvalid && !awready) |=> $stable(awaddr);
  endproperty
  a_awaddr_stable: assert property (p_awaddr_stable)
    else $error("AXI4-Lite violation: AWADDR changed while AWVALID high");

  // AXI4-Lite: After reset deasserts, VALID signals must be low
  property p_valid_after_reset;
    @(posedge aclk)
      $rose(aresetn) |-> (!awvalid && !wvalid && !arvalid);
  endproperty
  a_valid_after_reset: assert property (p_valid_after_reset)
    else $warning("AXI4-Lite: VALID signals should be low after reset release");

endinterface : axi_lite_if
