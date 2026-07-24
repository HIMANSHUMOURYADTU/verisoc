// =============================================================================
// File        : coverage.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM Functional Coverage Collector.
//               Receives completed AXI4-Lite transactions from the monitor
//               analysis port and samples the following covergroups:
//
//               1. cg_direction       — Read vs Write distribution
//               2. cg_peripheral      — Coverage per peripheral (UART/SPI/GPIO/Timer)
//               3. cg_address         — Per-register address coverage
//               4. cg_response        — AXI response code coverage (OKAY/SLVERR)
//               5. cg_rw_x_peripheral — Cross: direction × peripheral
//               6. cg_wstrb           — Write strobe patterns
//               7. cg_data_corners    — Data corner cases (0, 0xFF, 0xFFFFFFFF, random)
//
// UVM Version : UVM 1.2
// =============================================================================

`ifndef COVERAGE_SV
`define COVERAGE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

`include "../sequence_item/axi_seq_item.sv"

class coverage extends uvm_subscriber #(axi_seq_item);

  `uvm_component_utils(coverage)

  // Current transaction being sampled
  axi_seq_item current_trans;

  // ---------------------------------------------------------------------------
  // Covergroup 1: Transaction Direction
  // ---------------------------------------------------------------------------
  covergroup cg_direction;
    cp_dir : coverpoint current_trans.direction {
      bins write_txn = { WRITE };
      bins read_txn  = { READ  };
    }
  endgroup

  // ---------------------------------------------------------------------------
  // Covergroup 2: Peripheral Coverage
  // ---------------------------------------------------------------------------
  covergroup cg_peripheral;
    cp_periph : coverpoint current_trans.periph_id {
      bins uart  = { PERIPH_UART  };
      bins spi   = { PERIPH_SPI   };
      bins gpio  = { PERIPH_GPIO  };
      bins timer = { PERIPH_TIMER };
    }
  endgroup

  // ---------------------------------------------------------------------------
  // Covergroup 3: Per-Register Address Coverage (12-bit peripheral offset)
  // ---------------------------------------------------------------------------
  covergroup cg_address;
    cp_uart_reg : coverpoint current_trans.addr[11:0]
        iff (current_trans.periph_id == PERIPH_UART) {
      bins txdata  = { UART_TXDATA_OFF  };
      bins rxdata  = { UART_RXDATA_OFF  };
      bins status  = { UART_STATUS_OFF  };
      bins control = { UART_CONTROL_OFF };
      bins baud    = { UART_BAUD_OFF    };
    }
    cp_spi_reg : coverpoint current_trans.addr[11:0]
        iff (current_trans.periph_id == PERIPH_SPI) {
      bins control = { SPI_CONTROL_OFF };
      bins status  = { SPI_STATUS_OFF  };
      bins txdata  = { SPI_TXDATA_OFF  };
      bins rxdata  = { SPI_RXDATA_OFF  };
      bins clkdiv  = { SPI_CLKDIV_OFF  };
    }
    cp_gpio_reg : coverpoint current_trans.addr[11:0]
        iff (current_trans.periph_id == PERIPH_GPIO) {
      bins dir = { GPIO_DIR_OFF };
      bins in  = { GPIO_IN_OFF  };
      bins out = { GPIO_OUT_OFF };
      bins ie  = { GPIO_IE_OFF  };
      bins is  = { GPIO_IS_OFF  };
    }
    cp_timer_reg : coverpoint current_trans.addr[11:0]
        iff (current_trans.periph_id == PERIPH_TIMER) {
      bins cnt    = { TIMER_CNT_OFF    };
      bins cmp    = { TIMER_CMP_OFF    };
      bins ctrl   = { TIMER_CTRL_OFF   };
      bins status = { TIMER_STATUS_OFF };
    }
  endgroup

  // ---------------------------------------------------------------------------
  // Covergroup 4: AXI Response Coverage
  // ---------------------------------------------------------------------------
  covergroup cg_response;
    cp_resp : coverpoint current_trans.resp {
      bins okay   = { AXI_OKAY   };
      bins slverr = { AXI_SLVERR };
      illegal_bins exokay = { AXI_EXOKAY };
      illegal_bins decerr = { AXI_DECERR };
    }
  endgroup

  // ---------------------------------------------------------------------------
  // Covergroup 5: Cross — Direction × Peripheral
  // ---------------------------------------------------------------------------
  covergroup cg_rw_x_peripheral;
    cp_dir    : coverpoint current_trans.direction;
    cp_periph : coverpoint current_trans.periph_id;
    cx_rw_periph : cross cp_dir, cp_periph;
  endgroup

  // ---------------------------------------------------------------------------
  // Covergroup 6: Write Strobe Patterns
  // ---------------------------------------------------------------------------
  covergroup cg_wstrb;
    cp_wstrb : coverpoint current_trans.wstrb
        iff (current_trans.direction == WRITE) {
      bins byte0   = { 4'b0001 };
      bins byte1   = { 4'b0010 };
      bins byte2   = { 4'b0100 };
      bins byte3   = { 4'b1000 };
      bins hw_lo   = { 4'b0011 };
      bins hw_hi   = { 4'b1100 };
      bins all_but = { 4'b0111, 4'b1110, 4'b1011, 4'b1101 };
      bins full    = { 4'b1111 };
    }
  endgroup

  // ---------------------------------------------------------------------------
  // Covergroup 7: Data Corner Cases
  // ---------------------------------------------------------------------------
  covergroup cg_data_corners;
    cp_data : coverpoint current_trans.data {
      bins zero      = { 32'h0000_0000 };
      bins all_ones  = { 32'hFFFF_FFFF };
      bins byte_ff   = { 32'h0000_00FF };
      bins half_ff   = { 32'h0000_FFFF };
      bins random    = default;
    }
  endgroup

  // ---------------------------------------------------------------------------
  // Constructor — create all covergroups
  // ---------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    current_trans  = null;
    cg_direction      = new();
    cg_peripheral     = new();
    cg_address        = new();
    cg_response       = new();
    cg_rw_x_peripheral= new();
    cg_wstrb          = new();
    cg_data_corners   = new();
  endfunction

  // ---------------------------------------------------------------------------
  // Write — called by analysis port (uvm_subscriber)
  // ---------------------------------------------------------------------------
  function void write(axi_seq_item trans);
    current_trans = trans;
    // Sample all covergroups
    cg_direction.sample();
    cg_peripheral.sample();
    cg_address.sample();
    cg_response.sample();
    cg_rw_x_peripheral.sample();
    if (trans.direction == WRITE) cg_wstrb.sample();
    cg_data_corners.sample();
  endfunction

  // ---------------------------------------------------------------------------
  // Report Phase — print coverage summary
  // ---------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf({
      "\n================================================================\n",
      "  FUNCTIONAL COVERAGE SUMMARY\n",
      "  Direction       : %.1f%%\n",
      "  Peripheral      : %.1f%%\n",
      "  Address         : %.1f%%\n",
      "  Response        : %.1f%%\n",
      "  RW x Peripheral : %.1f%%\n",
      "  Write Strobe    : %.1f%%\n",
      "  Data Corners    : %.1f%%\n",
      "================================================================"
    },
    cg_direction.get_coverage(),
    cg_peripheral.get_coverage(),
    cg_address.get_coverage(),
    cg_response.get_coverage(),
    cg_rw_x_peripheral.get_coverage(),
    cg_wstrb.get_coverage(),
    cg_data_corners.get_coverage()
    ), UVM_NONE)
  endfunction

endclass : coverage

`endif // COVERAGE_SV
