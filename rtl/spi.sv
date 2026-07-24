// =============================================================================
// File        : spi.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : SPI Master peripheral with APB slave interface.
//               Implements SPI Mode 0 (CPOL=0, CPHA=0) by default;
//               mode is programmable via CONTROL register.
//               Features:
//               - Programmable clock divider (APB_CLK / (2*(CLKDIV+1)))
//               - 8-bit or 16-bit transfer width (CONTROL[1])
//               - Single Master — chip select (CS_N) managed automatically
//               - TX/RX data registers for single-word transfers
//               - Status register (BUSY, TXFULL, RXFULL)
//               Registers:
//                 0x000 CONTROL  [3:0]  {WIDTH,CPHA,CPOL,ENABLE}
//                 0x004 STATUS   [2:0]  {RXFULL,TXFULL,BUSY}
//                 0x008 TXDATA  [15:0]  data to send (write starts transfer)
//                 0x00C RXDATA  [15:0]  received data
//                 0x010 CLKDIV  [15:0]  clock divider
// Standard    : IEEE 1800-2017
// =============================================================================

`include "pkg.sv"
import soc_pkg::*;

module spi #(
  parameter int unsigned DEFAULT_CLKDIV = 3  // Default divisor → sck = pclk/8
) (
  // Clock and reset
  input  logic        pclk,
  input  logic        presetn,

  // APB Slave Interface
  input  logic [11:0] paddr,
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,

  // SPI Master Pins
  output logic        sck,    // SPI clock
  output logic        mosi,   // Master Out Slave In
  input  logic        miso,   // Master In Slave Out
  output logic        cs_n,   // Chip Select (active-low)

  // Interrupt
  output logic        irq     // Transfer complete interrupt
);

  // ---------------------------------------------------------------------------
  // Register file
  // ---------------------------------------------------------------------------
  logic [3:0]  ctrl_reg;     // {WIDTH16, CPHA, CPOL, ENABLE}
  logic [15:0] clkdiv_reg;   // Clock divider
  logic [15:0] txdata_reg;   // TX data
  logic [15:0] rxdata_reg;   // RX data (captured after transfer)

  wire  spi_en    = ctrl_reg[0];
  wire  cpol      = ctrl_reg[1];
  wire  cpha      = ctrl_reg[2];
  wire  width16   = ctrl_reg[3];

  // ---------------------------------------------------------------------------
  // Clock divider — generates SCK enable pulse
  // ---------------------------------------------------------------------------
  logic [15:0] clk_cnt;
  logic        sck_en;   // SCK toggle enable

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      clk_cnt <= '0;
      sck_en  <= 1'b0;
    end else if (clk_cnt == clkdiv_reg) begin
      clk_cnt <= '0;
      sck_en  <= 1'b1;
    end else begin
      clk_cnt <= clk_cnt + 16'd1;
      sck_en  <= 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // SPI State Machine
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    SPI_IDLE     = 2'd0,
    SPI_TRANSFER = 2'd1,
    SPI_DONE     = 2'd2
  } spi_state_t;

  spi_state_t  spi_state;
  logic [15:0] shift_out;  // TX shift register
  logic [15:0] shift_in;   // RX shift register
  logic [4:0]  bit_cnt;    // Bit counter (0..15)
  logic [4:0]  total_bits; // 8 or 16 based on WIDTH16
  logic        sck_r;      // Registered SCK value
  logic        busy;
  logic        rx_full;    // RX data valid flag
  logic        tx_full;    // TX data pending flag

  assign total_bits = width16 ? 5'd15 : 5'd7;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      spi_state <= SPI_IDLE;
      shift_out <= '0;
      shift_in  <= '0;
      bit_cnt   <= '0;
      sck_r     <= 1'b0;
      cs_n      <= 1'b1;
      mosi      <= 1'b0;
      busy      <= 1'b0;
      rx_full   <= 1'b0;
      tx_full   <= 1'b0;
      irq       <= 1'b0;
    end else begin
      irq <= 1'b0; // Default: no interrupt

      case (spi_state)
        SPI_IDLE: begin
          sck_r   <= cpol; // SCK idle level
          cs_n    <= 1'b1;
          busy    <= 1'b0;
          if (spi_en && tx_full) begin
            shift_out  <= txdata_reg;
            bit_cnt    <= '0;
            cs_n       <= 1'b0;
            busy       <= 1'b1;
            tx_full    <= 1'b0;
            rx_full    <= 1'b0;
            spi_state  <= SPI_TRANSFER;
          end
        end

        SPI_TRANSFER: begin
          if (sck_en) begin
            if (!sck_r) begin
              // Rising edge (for CPOL=0, CPHA=0 — sample on rising)
              if (!cpha) shift_in <= {shift_in[14:0], miso}; // Sample
              sck_r <= 1'b1;
            end else begin
              // Falling edge — shift out next bit
              if (cpha) shift_in <= {shift_in[14:0], miso};  // Sample on falling (CPHA=1)
              mosi  <= shift_out[15]; // MSB first
              shift_out <= {shift_out[14:0], 1'b0};
              sck_r <= 1'b0;
              if (bit_cnt == total_bits) begin
                spi_state <= SPI_DONE;
              end else begin
                bit_cnt <= bit_cnt + 5'd1;
              end
            end
          end
        end

        SPI_DONE: begin
          if (sck_en) begin
            sck_r     <= cpol;
            cs_n      <= 1'b1;
            rxdata_reg<= shift_in;
            rx_full   <= 1'b1;
            busy      <= 1'b0;
            irq       <= 1'b1;
            spi_state <= SPI_IDLE;
          end
        end

        default: spi_state <= SPI_IDLE;
      endcase
    end
  end

  // Drive SCK from registered value
  assign sck = sck_r;

  // Drive MOSI — output MSB of shift register during transfer
  always_comb begin
    if (!busy) mosi = 1'b0;
  end

  // ---------------------------------------------------------------------------
  // APB Read
  // ---------------------------------------------------------------------------
  always_comb begin
    prdata  = 32'd0;
    pslverr = 1'b0;
    case (paddr)
      SPI_CONTROL_OFF : prdata = {28'd0, ctrl_reg};
      SPI_STATUS_OFF  : prdata = {29'd0, rx_full, tx_full, busy};
      SPI_TXDATA_OFF  : prdata = {16'd0, txdata_reg}; // Reflect last write
      SPI_RXDATA_OFF  : prdata = {16'd0, rxdata_reg};
      SPI_CLKDIV_OFF  : prdata = {16'd0, clkdiv_reg};
      default         : begin prdata = 32'd0; pslverr = 1'b1; end
    endcase
  end

  // ---------------------------------------------------------------------------
  // APB Write
  // ---------------------------------------------------------------------------
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      ctrl_reg   <= 4'h1;              // SPI enabled, mode 0, 8-bit
      clkdiv_reg <= DEFAULT_CLKDIV[15:0];
      txdata_reg <= '0;
    end else if (psel && penable && pwrite) begin
      case (paddr)
        SPI_CONTROL_OFF : ctrl_reg   <= pwdata[3:0];
        SPI_CLKDIV_OFF  : clkdiv_reg <= pwdata[15:0];
        SPI_TXDATA_OFF  : begin
          txdata_reg <= pwdata[15:0];
          tx_full    <= 1'b1; // Writing TXDATA triggers a transfer
        end
        default : ; // Ignore writes to STATUS and RXDATA
      endcase
    end
  end

  assign pready = 1'b1;

endmodule : spi
