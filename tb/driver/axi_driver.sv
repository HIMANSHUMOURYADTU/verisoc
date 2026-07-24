// =============================================================================
// File        : axi_driver.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM AXI4-Lite Driver.
//               Receives axi_seq_item transactions from the sequencer and
//               drives them onto the AXI4-Lite interface using the master
//               clocking block (all timing referenced to posedge aclk).
//
//               Write flow:
//                 1. Drive AW channel (AWADDR, AWVALID) → wait AWREADY
//                 2. Drive W  channel (WDATA, WSTRB, WVALID) → wait WREADY
//                    (AW and W channels driven simultaneously per spec)
//                 3. Wait BVALID → assert BREADY → capture BRESP
//
//               Read flow:
//                 1. Drive AR channel (ARADDR, ARVALID) → wait ARREADY
//                 2. Wait RVALID → assert RREADY → capture RDATA, RRESP
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef AXI_DRIVER_SV
`define AXI_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "../sequence_item/axi_seq_item.sv"

class axi_driver extends uvm_driver #(axi_seq_item);

  `uvm_component_utils(axi_driver)

  // Virtual interface handle — connected in connect_phase
  virtual axi_lite_if.master vif;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // ---------------------------------------------------------------------------
  // Build Phase — get VIF from config DB
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi_lite_if.master)::get(
        this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), "Cannot get virtual interface 'vif' from config_db")
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Run Phase — main driver loop
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    axi_seq_item item;

    // Initialise all AXI outputs to safe idle state
    drive_idle();
    @(posedge vif.aclk);

    // Wait for reset de-assertion
    @(posedge vif.aresetn);
    repeat (2) @(posedge vif.aclk);

    forever begin
      seq_item_port.get_next_item(item);
      `uvm_info(get_type_name(),
        $sformatf("Driving: %s", item.convert2string()), UVM_HIGH)

      // Optional idle delay before transaction
      repeat (item.delay_cycles) @(posedge vif.aclk);

      if (item.direction == WRITE)
        drive_write(item);
      else
        drive_read(item);

      seq_item_port.item_done();
    end
  endtask

  // ---------------------------------------------------------------------------
  // Drive AXI to idle (all VALID low, READY high for max throughput)
  // ---------------------------------------------------------------------------
  task drive_idle();
    vif.master_cb.awvalid <= 1'b0;
    vif.master_cb.awaddr  <= '0;
    vif.master_cb.wvalid  <= 1'b0;
    vif.master_cb.wdata   <= '0;
    vif.master_cb.wstrb   <= 4'hF;
    vif.master_cb.bready  <= 1'b1; // Always ready to accept response
    vif.master_cb.arvalid <= 1'b0;
    vif.master_cb.araddr  <= '0;
    vif.master_cb.rready  <= 1'b1; // Always ready to accept read data
  endtask

  // ---------------------------------------------------------------------------
  // Drive a write transaction
  // ---------------------------------------------------------------------------
  task drive_write(axi_seq_item item);
    // Drive AW and W channels simultaneously (legal in AXI4-Lite)
    vif.master_cb.awvalid <= 1'b1;
    vif.master_cb.awaddr  <= item.addr;
    vif.master_cb.wvalid  <= 1'b1;
    vif.master_cb.wdata   <= item.data;
    vif.master_cb.wstrb   <= item.wstrb;

    // Wait for both AW and W handshakes (may complete on different cycles)
    fork
      begin
        @(posedge vif.aclk);
        while (!vif.master_cb.awready) @(posedge vif.aclk);
        vif.master_cb.awvalid <= 1'b0;
      end
      begin
        @(posedge vif.aclk);
        while (!vif.master_cb.wready) @(posedge vif.aclk);
        vif.master_cb.wvalid <= 1'b0;
      end
    join

    // Wait for write response on B channel
    vif.master_cb.bready <= 1'b1;
    @(posedge vif.aclk);
    while (!vif.master_cb.bvalid) @(posedge vif.aclk);
    item.resp = vif.master_cb.bresp;   // Capture response
    @(posedge vif.aclk);
    drive_idle();
  endtask

  // ---------------------------------------------------------------------------
  // Drive a read transaction
  // ---------------------------------------------------------------------------
  task drive_read(axi_seq_item item);
    vif.master_cb.arvalid <= 1'b1;
    vif.master_cb.araddr  <= item.addr;
    vif.master_cb.rready  <= 1'b1;

    @(posedge vif.aclk);
    while (!vif.master_cb.arready) @(posedge vif.aclk);
    vif.master_cb.arvalid <= 1'b0;

    // Wait for read data on R channel
    @(posedge vif.aclk);
    while (!vif.master_cb.rvalid) @(posedge vif.aclk);
    item.data = vif.master_cb.rdata;  // Capture data
    item.resp = vif.master_cb.rresp;  // Capture response
    @(posedge vif.aclk);
    drive_idle();
  endtask

endclass : axi_driver

`endif // AXI_DRIVER_SV
