// =============================================================================
// File        : env.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM Environment.
//               Top-level UVM verification environment that instantiates and
//               connects all sub-components:
//                 - axi_agent    (active, drives and monitors AXI4-Lite bus)
//                 - scoreboard   (expected-vs-actual comparison)
//                 - coverage     (functional coverage collection)
//
//               Analysis port connections:
//                 axi_agent.ap  ──▶  scoreboard.analysis_export
//                 axi_agent.ap  ──▶  coverage.analysis_export  (subscriber)
//
//               Virtual interface is retrieved from config_db and forwarded
//               to child components.
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef ENV_SV
`define ENV_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "../agent/axi_agent.sv"
`include "../scoreboard/scoreboard.sv"
`include "../coverage/coverage.sv"

class env extends uvm_env;

  `uvm_component_utils(env)

  // ---------------------------------------------------------------------------
  // Sub-components
  // ---------------------------------------------------------------------------
  axi_agent   m_agent;     // Active AXI4-Lite agent
  scoreboard  m_scoreboard;
  coverage    m_coverage;

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

    // Create sub-components
    m_agent      = axi_agent::type_id::create("m_agent",      this);
    m_scoreboard = scoreboard::type_id::create("m_scoreboard", this);
    m_coverage   = coverage::type_id::create("m_coverage",    this);

    // Configure agent as active (drives DUT)
    uvm_config_db #(uvm_active_passive_enum)::set(
      this, "m_agent", "is_active", UVM_ACTIVE);

    `uvm_info(get_type_name(), "Environment built successfully", UVM_MEDIUM)
  endfunction

  // ---------------------------------------------------------------------------
  // Connect Phase — wire analysis ports
  // ---------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    // Agent monitor → scoreboard
    m_agent.ap.connect(m_scoreboard.analysis_export);

    // Agent monitor → coverage collector
    m_agent.ap.connect(m_coverage.analysis_export);

    `uvm_info(get_type_name(), "Environment connected", UVM_MEDIUM)
  endfunction

  // ---------------------------------------------------------------------------
  // End-of-Elaboration — print component tree
  // ---------------------------------------------------------------------------
  function void end_of_elaboration_phase(uvm_phase phase);
    `uvm_info(get_type_name(), "UVM component hierarchy:", UVM_MEDIUM)
    uvm_top.print_topology();
  endfunction

endclass : env

`endif // ENV_SV
