// =============================================================================
// File        : pkg.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : SoC-wide package.  All RTL and TB files import this package.
//               Contains parameters, typedefs, enums, and address constants
//               that are shared across the entire design hierarchy.
// Standard    : IEEE 1800-2017 (SystemVerilog)
// =============================================================================

/* verilator lint_off DECLFILENAME UNUSEDPARAM */

package soc_pkg;

  // ---------------------------------------------------------------------------
  // Bus width parameters
  // ---------------------------------------------------------------------------
  parameter int unsigned DATA_WIDTH  = 32;   // AXI/APB data bus width (bits)
  parameter int unsigned ADDR_WIDTH  = 32;   // AXI/APB address bus width (bits)
  parameter int unsigned STRB_WIDTH  = DATA_WIDTH / 8; // Write-strobe width

  // ---------------------------------------------------------------------------
  // Number of APB slaves on the peripheral bus
  // ---------------------------------------------------------------------------
  parameter int unsigned NUM_SLAVES  = 4;

  // ---------------------------------------------------------------------------
  // Memory map — base addresses for each peripheral
  // Each peripheral occupies a 4 KB region (12-bit offset space)
  // ---------------------------------------------------------------------------
  parameter logic [ADDR_WIDTH-1:0] UART_BASE  = 32'h0000_0000;
  parameter logic [ADDR_WIDTH-1:0] SPI_BASE   = 32'h0000_1000;
  parameter logic [ADDR_WIDTH-1:0] GPIO_BASE  = 32'h0000_2000;
  parameter logic [ADDR_WIDTH-1:0] TIMER_BASE = 32'h0000_3000;
  parameter logic [ADDR_WIDTH-1:0] PERIPH_MASK= 32'hFFFF_F000; // top 20-bit comparison mask

  // ---------------------------------------------------------------------------
  // UART register offsets (from UART_BASE)
  // ---------------------------------------------------------------------------
  parameter logic [11:0] UART_TXDATA_OFF  = 12'h000; // Transmit data register
  parameter logic [11:0] UART_RXDATA_OFF  = 12'h004; // Receive data register
  parameter logic [11:0] UART_STATUS_OFF  = 12'h008; // Status register
  parameter logic [11:0] UART_CONTROL_OFF = 12'h00C; // Control register
  parameter logic [11:0] UART_BAUD_OFF    = 12'h010; // Baud rate divisor

  // ---------------------------------------------------------------------------
  // SPI register offsets (from SPI_BASE)
  // ---------------------------------------------------------------------------
  parameter logic [11:0] SPI_CONTROL_OFF  = 12'h000; // Control register
  parameter logic [11:0] SPI_STATUS_OFF   = 12'h004; // Status register
  parameter logic [11:0] SPI_TXDATA_OFF   = 12'h008; // Transmit data register
  parameter logic [11:0] SPI_RXDATA_OFF   = 12'h00C; // Receive data register
  parameter logic [11:0] SPI_CLKDIV_OFF   = 12'h010; // Clock divider register

  // ---------------------------------------------------------------------------
  // GPIO register offsets (from GPIO_BASE)
  // ---------------------------------------------------------------------------
  parameter logic [11:0] GPIO_DIR_OFF     = 12'h000; // Direction register (1=output)
  parameter logic [11:0] GPIO_IN_OFF      = 12'h004; // Input data register
  parameter logic [11:0] GPIO_OUT_OFF     = 12'h008; // Output data register
  parameter logic [11:0] GPIO_IE_OFF      = 12'h00C; // Interrupt enable register
  parameter logic [11:0] GPIO_IS_OFF      = 12'h010; // Interrupt status register

  // ---------------------------------------------------------------------------
  // Timer register offsets (from TIMER_BASE)
  // ---------------------------------------------------------------------------
  parameter logic [11:0] TIMER_CNT_OFF    = 12'h000; // Counter value register
  parameter logic [11:0] TIMER_CMP_OFF    = 12'h004; // Compare / reload register
  parameter logic [11:0] TIMER_CTRL_OFF   = 12'h008; // Control (enable/mode) register
  parameter logic [11:0] TIMER_STATUS_OFF = 12'h00C; // Status / interrupt register

  // ---------------------------------------------------------------------------
  // AXI4-Lite response codes (BRESP / RRESP)
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    AXI_OKAY   = 2'b00,  // Normal access success
    AXI_EXOKAY = 2'b01,  // Exclusive access success
    AXI_SLVERR = 2'b10,  // Slave error
    AXI_DECERR = 2'b11   // Decode error (unmapped address)
  } axi_resp_t;

  // ---------------------------------------------------------------------------
  // APB state encoding
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    APB_IDLE    = 2'b00, // No transfer
    APB_SETUP   = 2'b01, // PSEL asserted, PENABLE deasserted
    APB_ACCESS  = 2'b10  // PSEL + PENABLE asserted
  } apb_state_t;

  // ---------------------------------------------------------------------------
  // Transaction direction — used in UVM sequence items
  // ---------------------------------------------------------------------------
  typedef enum logic {
    READ  = 1'b0,
    WRITE = 1'b1
  } direction_t;

  // ---------------------------------------------------------------------------
  // Peripheral identifier — used in coverage and scoreboard
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    PERIPH_UART  = 2'd0,
    PERIPH_SPI   = 2'd1,
    PERIPH_GPIO  = 2'd2,
    PERIPH_TIMER = 2'd3
  } periph_id_t;

  // ---------------------------------------------------------------------------
  // Helper function — decode base address to peripheral id
  // Returns PERIPH_UART on unmapped addresses (safe default)
  // ---------------------------------------------------------------------------
  function automatic periph_id_t addr_to_periph(input logic [ADDR_WIDTH-1:0] addr);
    case (addr & PERIPH_MASK)
      UART_BASE  : return PERIPH_UART;
      SPI_BASE   : return PERIPH_SPI;
      GPIO_BASE  : return PERIPH_GPIO;
      TIMER_BASE : return PERIPH_TIMER;
      default    : return PERIPH_UART;
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // Helper function — check if address is in valid peripheral range
  // ---------------------------------------------------------------------------
  function automatic logic addr_is_valid(input logic [ADDR_WIDTH-1:0] addr);
    case (addr & PERIPH_MASK)
      UART_BASE, SPI_BASE, GPIO_BASE, TIMER_BASE : return 1'b1;
      default                                    : return 1'b0;
    endcase
  endfunction

endpackage : soc_pkg
/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on DECLFILENAME */
