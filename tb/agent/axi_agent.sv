// =============================================================================
// File        : axi_agent.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM AXI4-Lite Agent.
//               Composes the driver, monitor, and sequencer into a reusable
//               agent component.  Supports active and passive modes:
//                 - Active  (UVM_ACTIVE)  : driver + sequencer + monitor
//                 - Passive (UVM_PASSIVE) : monitor only
//
//               The agent's analysis port is connected directly to the
//               monitor's analysis port, allowing the environment to subscribe.
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef AXI_AGENT_SV
`define AXI_AGENT_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "../driver/axi_driver.sv"
`include "../monitor/axi_monitor.sv"

class axi_agent extends uvm_agent;

  `uvm_component_utils(axi_agent)

  // ---------------------------------------------------------------------------
  // Sub-components
  // ---------------------------------------------------------------------------
  axi_driver                   driver;
  axi_monitor                  monitor;
  uvm_sequencer #(axi_seq_item) sequencer;

  // Analysis port (pass-through from monitor)
  uvm_analysis_port #(axi_seq_item) ap;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // ---------------------------------------------------------------------------
  // Build Phase — instantiate sub-components based on mode
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    ap      = new("ap", this);
    monitor = axi_monitor::type_id::create("monitor", this);

    if (get_is_active() == UVM_ACTIVE) begin
      driver    = axi_driver::type_id::create("driver", this);
      sequencer = uvm_sequencer #(axi_seq_item)::type_id::create("sequencer", this);
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Connect Phase — wire driver→sequencer and monitor→agent analysis port
  // ---------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    // Connect monitor analysis port upward
    monitor.ap.connect(ap);

    if (get_is_active() == UVM_ACTIVE) begin
      // Connect driver to sequencer
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass : axi_agent

`endif // AXI_AGENT_SV
