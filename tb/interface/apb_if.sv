// =============================================================================
// File        : apb_if.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : SystemVerilog interface for the APB (AMBA Peripheral Bus).
//               Provides modports for:
//                 - master  (APB bridge drives signals)
//                 - slave   (peripheral drives PRDATA/PREADY/PSLVERR)
//                 - monitor (passive observation)
//
//               The interface is primarily used by the monitor and assertion
//               modules to observe APB bus activity without driving it.
//
// Standard    : IEEE 1800-2017 / ARM IHI0024C APB spec
// =============================================================================

`include "../rtl/pkg.sv"
import soc_pkg::*;

interface apb_if #(
  parameter int unsigned DATA_W    = soc_pkg::DATA_WIDTH,
  parameter int unsigned ADDR_W    = soc_pkg::ADDR_WIDTH,
  parameter int unsigned N_SLAVES  = soc_pkg::NUM_SLAVES
) (
  input logic pclk,
  input logic presetn
);

  // ---------------------------------------------------------------------------
  // APB Signal Declarations
  // ---------------------------------------------------------------------------
  logic [ADDR_W-1:0]     paddr;
  logic [N_SLAVES-1:0]   psel;
  logic                  penable;
  logic                  pwrite;
  logic [DATA_W-1:0]     pwdata;
  logic [DATA_W-1:0]     prdata [N_SLAVES-1:0]; // One per slave
  logic                  pready [N_SLAVES-1:0];
  logic                  pslverr[N_SLAVES-1:0];

  // ---------------------------------------------------------------------------
  // Clocking block for monitor
  // ---------------------------------------------------------------------------
  clocking monitor_cb @(posedge pclk);
    default input #1step;
    input paddr;
    input psel;
    input penable;
    input pwrite;
    input pwdata;
    input prdata;
    input pready;
    input pslverr;
  endclocking

  // ---------------------------------------------------------------------------
  // Modport: Master (APB bridge drives these)
  // ---------------------------------------------------------------------------
  modport master (
    output paddr, psel, penable, pwrite, pwdata,
    input  prdata, pready, pslverr,
    input  pclk, presetn
  );

  // ---------------------------------------------------------------------------
  // Modport: Slave (Peripherals drive these)
  // ---------------------------------------------------------------------------
  modport slave (
    input  paddr, psel, penable, pwrite, pwdata,
    output prdata, pready, pslverr,
    input  pclk, presetn
  );

  // ---------------------------------------------------------------------------
  // Modport: Monitor (passive, read-only)
  // ---------------------------------------------------------------------------
  modport monitor (
    clocking monitor_cb,
    input pclk, presetn
  );

  // ---------------------------------------------------------------------------
  // APB Protocol Assertions
  // ---------------------------------------------------------------------------

  // PENABLE must only be high for one cycle when PREADY is high (transfer done)
  property p_apb_penable_seq;
    @(posedge pclk) disable iff (!presetn)
      (|psel && !penable) |=> (|psel && penable);
  endproperty
  a_apb_penable_seq: assert property (p_apb_penable_seq)
    else $error("APB violation: PENABLE did not follow PSEL");

  // PADDR must be stable during ACCESS phase
  property p_apb_paddr_stable;
    @(posedge pclk) disable iff (!presetn)
      (|psel && penable) |-> $stable(paddr);
  endproperty
  a_apb_paddr_stable: assert property (p_apb_paddr_stable)
    else $error("APB violation: PADDR changed during ACCESS phase");

  // PWRITE must be stable during ACCESS phase
  property p_apb_pwrite_stable;
    @(posedge pclk) disable iff (!presetn)
      (|psel && penable) |-> $stable(pwrite);
  endproperty
  a_apb_pwrite_stable: assert property (p_apb_pwrite_stable)
    else $error("APB violation: PWRITE changed during ACCESS phase");

endinterface : apb_if
