// =============================================================================
// File        : axi_monitor.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM AXI4-Lite Monitor.
//               Passively observes the AXI4-Lite bus and reconstructs
//               complete transactions from channel-level handshakes.
//               Publishes completed transactions on the analysis port for:
//                 - Scoreboard (expected vs actual comparison)
//                 - Coverage collector
//
//               Monitoring strategy:
//                 - Detects AW handshake, W handshake, B handshake → WRITE
//                 - Detects AR handshake, R handshake → READ
//                 - Transactions are buffered per-channel and assembled when
//                   all phases complete
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "../sequence_item/axi_seq_item.sv"

class axi_monitor extends uvm_monitor;

  `uvm_component_utils(axi_monitor)

  // Analysis port — publishes completed transactions
  uvm_analysis_port #(axi_seq_item) ap;

  // Virtual interface handle
  virtual axi_lite_if.monitor vif;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // ---------------------------------------------------------------------------
  // Build Phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual axi_lite_if.monitor)::get(
        this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), "Cannot get virtual interface 'vif' from config_db")
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Run Phase — spawn parallel threads for write and read monitoring
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    // Wait for reset de-assertion before monitoring
    @(posedge vif.aclk iff vif.aresetn === 1'b1);

    fork
      monitor_writes();
      monitor_reads();
    join_none
  endtask

  // ---------------------------------------------------------------------------
  // Monitor Write Transactions
  // Three phases must be observed: AW handshake, W handshake, B handshake
  // ---------------------------------------------------------------------------
  task monitor_writes();
    axi_seq_item trans;
    logic [31:0] cap_addr;
    logic [31:0] cap_data;
    logic [3:0]  cap_strb;
    logic [1:0]  cap_resp;
    logic        aw_done, w_done;

    forever begin
      // Wait for AW handshake and W handshake (may arrive in any order)
      aw_done = 1'b0;
      w_done  = 1'b0;

      fork
        begin : aw_thread
          @(posedge vif.aclk iff
            (vif.monitor_cb.awvalid && vif.monitor_cb.awready));
          cap_addr = vif.monitor_cb.awaddr;
          aw_done  = 1'b1;
        end
        begin : w_thread
          @(posedge vif.aclk iff
            (vif.monitor_cb.wvalid && vif.monitor_cb.wready));
          cap_data = vif.monitor_cb.wdata;
          cap_strb = vif.monitor_cb.wstrb;
          w_done   = 1'b1;
        end
      join

      // Wait for B channel response
      @(posedge vif.aclk iff
        (vif.monitor_cb.bvalid && vif.monitor_cb.bready));
      cap_resp = vif.monitor_cb.bresp;

      // Assemble and publish the transaction
      trans           = axi_seq_item::type_id::create("mon_wr");
      trans.direction = WRITE;
      trans.addr      = cap_addr;
      trans.data      = cap_data;
      trans.wstrb     = cap_strb;
      trans.resp      = cap_resp;
      trans.periph_id = addr_to_periph(cap_addr);

      `uvm_info(get_type_name(),
        $sformatf("Observed WRITE: %s", trans.convert2string()), UVM_HIGH)
      ap.write(trans);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Monitor Read Transactions
  // Two phases: AR handshake, R handshake
  // ---------------------------------------------------------------------------
  task monitor_reads();
    axi_seq_item trans;
    logic [31:0] cap_addr;
    logic [31:0] cap_data;
    logic [1:0]  cap_resp;

    forever begin
      // Wait for AR handshake
      @(posedge vif.aclk iff
        (vif.monitor_cb.arvalid && vif.monitor_cb.arready));
      cap_addr = vif.monitor_cb.araddr;

      // Wait for R channel data
      @(posedge vif.aclk iff
        (vif.monitor_cb.rvalid && vif.monitor_cb.rready));
      cap_data = vif.monitor_cb.rdata;
      cap_resp = vif.monitor_cb.rresp;

      // Assemble and publish
      trans           = axi_seq_item::type_id::create("mon_rd");
      trans.direction = READ;
      trans.addr      = cap_addr;
      trans.data      = cap_data;
      trans.wstrb     = 4'hF;
      trans.resp      = cap_resp;
      trans.periph_id = addr_to_periph(cap_addr);

      `uvm_info(get_type_name(),
        $sformatf("Observed READ:  %s", trans.convert2string()), UVM_HIGH)
      ap.write(trans);
    end
  endtask

endclass : axi_monitor

`endif // AXI_MONITOR_SV
