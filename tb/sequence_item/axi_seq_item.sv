// =============================================================================
// File        : axi_seq_item.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : UVM Sequence Item for AXI4-Lite transactions.
//               Represents a single AXI4-Lite read or write transaction.
//               Fields are randomized subject to constraints that enforce:
//                 - Valid peripheral address ranges
//                 - Word-aligned addresses (byte addr [1:0] == 0)
//                 - Legal write strobe combinations
//                 - Weighted distribution toward valid addresses
//
// UVM Version : UVM 1.2 / IEEE 1800.2
// =============================================================================

`ifndef AXI_SEQ_ITEM_SV
`define AXI_SEQ_ITEM_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import soc_pkg::*;

class axi_seq_item extends uvm_sequence_item;

  // Register with UVM factory for override capability
  `uvm_object_utils_begin(axi_seq_item)
    `uvm_field_enum  (direction_t, direction,  UVM_ALL_ON)
    `uvm_field_int   (addr,                    UVM_ALL_ON | UVM_HEX)
    `uvm_field_int   (data,                    UVM_ALL_ON | UVM_HEX)
    `uvm_field_int   (wstrb,                   UVM_ALL_ON | UVM_BIN)
    `uvm_field_int   (resp,                    UVM_ALL_ON | UVM_DEC)
    `uvm_field_enum  (periph_id_t, periph_id,  UVM_ALL_ON)
    `uvm_field_int   (delay_cycles,            UVM_ALL_ON)
  `uvm_object_utils_end

  // ---------------------------------------------------------------------------
  // Randomized Fields
  // ---------------------------------------------------------------------------
  rand direction_t  direction;    // READ or WRITE
  rand logic [31:0] addr;         // Transaction address
  rand logic [31:0] data;         // Write data (or expected read data)
  rand logic [3:0]  wstrb;        // Write byte strobes

  // Non-randomized response fields (filled by driver/monitor)
  logic [1:0]       resp;         // BRESP or RRESP
  periph_id_t       periph_id;    // Decoded peripheral (set post-randomize)
  int unsigned      delay_cycles; // Optional inter-transaction gap

  // ---------------------------------------------------------------------------
  // Constraints
  // ---------------------------------------------------------------------------

  // Address must target one of the four valid peripherals
  constraint c_addr_valid {
    addr inside {
      // UART region: 0x0000_0000 – 0x0000_0FFF (5 registers × 4 bytes)
      [32'h0000_0000 : 32'h0000_0010],
      // SPI region:  0x0000_1000 – 0x0000_1010
      [32'h0000_1000 : 32'h0000_1010],
      // GPIO region: 0x0000_2000 – 0x0000_2010
      [32'h0000_2000 : 32'h0000_2010],
      // Timer region:0x0000_3000 – 0x0000_300C
      [32'h0000_3000 : 32'h0000_300C]
    };
  }

  // Address must be word-aligned (bottom 2 bits = 0)
  constraint c_addr_aligned {
    addr[1:0] == 2'b00;
  }

  // Write strobe must be valid (at least 1 byte enabled for writes)
  constraint c_wstrb {
    if (direction == WRITE) wstrb inside {4'b0001, 4'b0011, 4'b1111,
                                          4'b0010, 4'b0100, 4'b1000,
                                          4'b0111, 4'b1110};
    else                    wstrb == 4'hF; // Don't-care for reads, set to F
  }

  // Soft constraint: bias toward writes 60%, reads 40%
  constraint c_dir_dist {
    direction dist { WRITE := 60, READ := 40 };
  }

  // Soft delay constraint: 0–4 idle cycles between transactions
  constraint c_delay {
    delay_cycles dist { 0 := 50, 1 := 20, 2 := 15, [3:4] := 15 };
  }

  // ---------------------------------------------------------------------------
  // Post-randomize — fill derived fields
  // ---------------------------------------------------------------------------
  function void post_randomize();
    periph_id = addr_to_periph(addr);
  endfunction

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name = "axi_seq_item");
    super.new(name);
    resp         = '0;
    delay_cycles = 0;
    periph_id    = PERIPH_UART;
  endfunction

  // ---------------------------------------------------------------------------
  // Convert to string — used by UVM printer and $display
  // ---------------------------------------------------------------------------
  function string convert2string();
    return $sformatf(
      "AXI_SEQ_ITEM: %s addr=0x%08h data=0x%08h strb=0b%04b resp=%0b periph=%s delay=%0d",
      direction.name(), addr, data, wstrb, resp, periph_id.name(), delay_cycles
    );
  endfunction

endclass : axi_seq_item

`endif // AXI_SEQ_ITEM_SV
