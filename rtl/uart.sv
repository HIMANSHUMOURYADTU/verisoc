// =============================================================================
// File        : uart.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : Full-featured UART peripheral with APB slave interface.
//               Implements:
//               - Programmable baud-rate divisor
//               - 8N1 transmit state machine (IDLE → START → DATA → STOP)
//               - 8N1 receive  state machine with oversampling (16x)
//               - TX/RX 8-entry FIFOs
//               - Status register (TXFULL, TXEMPTY, RXFULL, RXEMPTY, RXERR)
//               - Interrupt output on RX data available
//               Registers (APB 32-bit word-addressed):
//                 0x000 TXDATA   [7:0]  — write to push TX FIFO
//                 0x004 RXDATA   [7:0]  — read  to pop  RX FIFO
//                 0x008 STATUS   [4:0]  — {RXERR,RXFULL,RXEMPTY,TXFULL,TXEMPTY}
//                 0x00C CONTROL  [1:0]  — {RX_EN, TX_EN}
//                 0x010 BAUD_DIV[15:0]  — baud divisor (clk_freq/baud_rate - 1)
// Standard    : IEEE 1800-2017
// =============================================================================

`include "pkg.sv"
import soc_pkg::*;

module uart #(
  parameter int unsigned FIFO_DEPTH   = 8,   // TX and RX FIFO depth (must be power-of-2)
  parameter int unsigned CLK_FREQ_HZ  = 50_000_000, // Default clock frequency
  parameter int unsigned DEFAULT_BAUD = 115200       // Default baud rate
) (
  // Clock and reset
  input  logic        pclk,
  input  logic        presetn,

  // APB Slave Interface
  input  logic [11:0] paddr,     // 12-bit peripheral offset
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,

  // Physical UART pins
  input  logic        rx,        // Serial receive line
  output logic        tx,        // Serial transmit line

  // Interrupt
  output logic        irq        // Asserted when RX FIFO non-empty
);

  // ---------------------------------------------------------------------------
  // Local parameters
  // ---------------------------------------------------------------------------
  localparam int unsigned FIFO_PTR_W = $clog2(FIFO_DEPTH);
  localparam int unsigned DEFAULT_DIV = CLK_FREQ_HZ / DEFAULT_BAUD - 1;

  // ---------------------------------------------------------------------------
  // Register file
  // ---------------------------------------------------------------------------
  logic [7:0]  ctrl_reg;          // [1]=RX_EN, [0]=TX_EN
  logic [15:0] baud_div;          // Baud divisor register
  // STATUS is read-only — assembled from FIFO flags

  // ---------------------------------------------------------------------------
  // TX FIFO
  // ---------------------------------------------------------------------------
  logic [7:0]  tx_fifo [0:FIFO_DEPTH-1];
  logic [FIFO_PTR_W:0] tx_wptr, tx_rptr; // Extra bit for full/empty detection
  wire  tx_empty = (tx_wptr == tx_rptr);
  wire  tx_full  = (tx_wptr[FIFO_PTR_W] != tx_rptr[FIFO_PTR_W]) &&
                   (tx_wptr[FIFO_PTR_W-1:0] == tx_rptr[FIFO_PTR_W-1:0]);

  // ---------------------------------------------------------------------------
  // RX FIFO
  // ---------------------------------------------------------------------------
  logic [7:0]  rx_fifo [0:FIFO_DEPTH-1];
  logic [FIFO_PTR_W:0] rx_wptr, rx_rptr;
  wire  rx_empty = (rx_wptr == rx_rptr);
  wire  rx_full  = (rx_wptr[FIFO_PTR_W] != rx_rptr[FIFO_PTR_W]) &&
                   (rx_wptr[FIFO_PTR_W-1:0] == rx_rptr[FIFO_PTR_W-1:0]);
  logic rx_err;    // Framing error flag

  // ---------------------------------------------------------------------------
  // Baud rate generator — shared 16x oversample clock enable
  // ---------------------------------------------------------------------------
  logic [15:0] baud_cnt;
  logic        baud_tick;         // 1-cycle pulse at baud rate

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      baud_cnt  <= '0;
      baud_tick <= 1'b0;
    end else if (baud_cnt == baud_div) begin
      baud_cnt  <= '0;
      baud_tick <= 1'b1;
    end else begin
      baud_cnt  <= baud_cnt + 16'd1;
      baud_tick <= 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // TX State Machine — 8N1
  // States: IDLE, START, D0..D7, STOP
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    TX_IDLE  = 3'd0,
    TX_START = 3'd1,
    TX_DATA  = 3'd2,
    TX_STOP  = 3'd3
  } tx_state_t;

  tx_state_t   tx_state;
  logic [7:0]  tx_shift;          // Shift register
  logic [2:0]  tx_bit_cnt;        // Bit counter 0..7
  logic        tx_en;
  assign tx_en = ctrl_reg[0];

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      tx_state   <= TX_IDLE;
      tx         <= 1'b1;         // UART idle = HIGH
      tx_shift   <= '0;
      tx_bit_cnt <= '0;
      tx_rptr    <= '0;
    end else if (baud_tick) begin
      case (tx_state)
        TX_IDLE: begin
          tx <= 1'b1;
          if (tx_en && !tx_empty) begin
            tx_shift   <= tx_fifo[tx_rptr[FIFO_PTR_W-1:0]];
            tx_rptr    <= tx_rptr + 1'b1;
            tx_state   <= TX_START;
          end
        end

        TX_START: begin
          tx         <= 1'b0;     // Start bit
          tx_bit_cnt <= 3'd0;
          tx_state   <= TX_DATA;
        end

        TX_DATA: begin
          tx         <= tx_shift[0];
          tx_shift   <= {1'b1, tx_shift[7:1]}; // LSB first, shift right
          tx_bit_cnt <= tx_bit_cnt + 3'd1;
          if (tx_bit_cnt == 3'd7) tx_state <= TX_STOP;
        end

        TX_STOP: begin
          tx       <= 1'b1;       // Stop bit
          tx_state <= TX_IDLE;
        end

        default: tx_state <= TX_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // TX FIFO write port — APB write to TXDATA register
  // ---------------------------------------------------------------------------
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      tx_wptr <= '0;
    end else if (psel && penable && pwrite && (paddr == UART_TXDATA_OFF) && !tx_full) begin
      tx_fifo[tx_wptr[FIFO_PTR_W-1:0]] <= pwdata[7:0];
      tx_wptr <= tx_wptr + 1'b1;
    end
  end

  // ---------------------------------------------------------------------------
  // RX State Machine — 8N1 with 16x oversampling
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    RX_IDLE  = 3'd0,
    RX_START = 3'd1,
    RX_DATA  = 3'd2,
    RX_STOP  = 3'd3
  } rx_state_t;

  rx_state_t   rx_state;
  logic [7:0]  rx_shift;
  logic [2:0]  rx_bit_cnt;
  logic [3:0]  rx_sample_cnt;  // 16x oversample counter
  logic [1:0]  rx_sync;        // 2-stage synchroniser for rx input
  logic        rx_en;
  assign rx_en = ctrl_reg[1];

  // Synchronise async RX input to pclk domain
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) rx_sync <= 2'b11;
    else          rx_sync <= {rx_sync[0], rx};
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      rx_state      <= RX_IDLE;
      rx_shift      <= '0;
      rx_bit_cnt    <= '0;
      rx_sample_cnt <= '0;
      rx_wptr       <= '0;
      rx_err        <= 1'b0;
    end else if (rx_en && baud_tick) begin
      case (rx_state)
        RX_IDLE: begin
          rx_err <= 1'b0;
          if (!rx_sync[1]) begin  // Falling edge = start bit
            rx_sample_cnt <= 4'd0;
            rx_state      <= RX_START;
          end
        end

        RX_START: begin
          rx_sample_cnt <= rx_sample_cnt + 4'd1;
          if (rx_sample_cnt == 4'd7) begin // Sample at mid-bit
            if (!rx_sync[1]) begin  // Valid start bit
              rx_bit_cnt    <= 3'd0;
              rx_sample_cnt <= 4'd0;
              rx_state      <= RX_DATA;
            end else begin
              rx_state <= RX_IDLE; // False start
            end
          end
        end

        RX_DATA: begin
          rx_sample_cnt <= rx_sample_cnt + 4'd1;
          if (rx_sample_cnt == 4'd15) begin // Sample at center of data bit
            rx_shift   <= {rx_sync[1], rx_shift[7:1]}; // LSB first
            rx_bit_cnt <= rx_bit_cnt + 3'd1;
            rx_sample_cnt <= 4'd0;
            if (rx_bit_cnt == 3'd7) rx_state <= RX_STOP;
          end
        end

        RX_STOP: begin
          rx_sample_cnt <= rx_sample_cnt + 4'd1;
          if (rx_sample_cnt == 4'd15) begin
            if (!rx_sync[1]) rx_err <= 1'b1; // Framing error: stop bit not HIGH
            if (!rx_full) begin
              rx_fifo[rx_wptr[FIFO_PTR_W-1:0]] <= rx_shift;
              rx_wptr <= rx_wptr + 1'b1;
            end
            rx_state <= RX_IDLE;
          end
        end

        default: rx_state <= RX_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // APB Read logic
  // ---------------------------------------------------------------------------
  always_comb begin
    prdata  = 32'd0;
    pslverr = 1'b0;
    case (paddr)
      UART_TXDATA_OFF  : prdata = 32'd0; // Write-only
      UART_RXDATA_OFF  : prdata = rx_empty ? 32'd0 : {24'd0, rx_fifo[rx_rptr[FIFO_PTR_W-1:0]]};
      UART_STATUS_OFF  : prdata = {27'd0, rx_err, rx_full, rx_empty, tx_full, tx_empty};
      UART_CONTROL_OFF : prdata = {24'd0, ctrl_reg};
      UART_BAUD_OFF    : prdata = {16'd0, baud_div};
      default          : begin prdata = 32'd0; pslverr = 1'b1; end
    endcase
  end

  // ---------------------------------------------------------------------------
  // APB Write logic & RX FIFO pop
  // ---------------------------------------------------------------------------
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      ctrl_reg <= 8'h03;           // TX and RX enabled by default
      baud_div <= DEFAULT_DIV[15:0];
      rx_rptr  <= '0;
    end else if (psel && penable && pwrite) begin
      case (paddr)
        UART_CONTROL_OFF : ctrl_reg <= pwdata[7:0];
        UART_BAUD_OFF    : baud_div <= pwdata[15:0];
        default          : ; // Ignore writes to read-only or invalid regs
      endcase
    end else if (psel && penable && !pwrite && (paddr == UART_RXDATA_OFF) && !rx_empty) begin
      rx_rptr <= rx_rptr + 1'b1;  // Pop RX FIFO on read
    end
  end

  // APB always completes in one cycle (combinational slave)
  assign pready = 1'b1;

  // Interrupt — asserted whenever RX FIFO is non-empty
  assign irq = !rx_empty;

endmodule : uart
