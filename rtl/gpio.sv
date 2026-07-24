// =============================================================================
// File        : gpio.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : General-Purpose I/O peripheral with APB slave interface.
//               Features:
//               - Parameterized pin width (default 32 bits)
//               - Per-pin direction control (1=output, 0=input)
//               - Output data register
//               - Input data register (synchronized to pclk)
//               - Per-pin interrupt enable
//               - Per-pin interrupt status (rising edge triggered)
//               - Interrupt clear on write-1-to-clear
//               Registers:
//                 0x000 DIR  [N-1:0]  direction (1=output)
//                 0x004 IN   [N-1:0]  input data (read-only)
//                 0x008 OUT  [N-1:0]  output data
//                 0x00C IE   [N-1:0]  interrupt enable
//                 0x010 IS   [N-1:0]  interrupt status (W1C)
// Standard    : IEEE 1800-2017
// =============================================================================

`include "pkg.sv"
import soc_pkg::*;

module gpio #(
  parameter int unsigned GPIO_WIDTH = 32  // Number of GPIO pins
) (
  // Clock and reset
  input  logic              pclk,
  input  logic              presetn,

  // APB Slave Interface
  input  logic [11:0]       paddr,
  input  logic              psel,
  input  logic              penable,
  input  logic              pwrite,
  input  logic [31:0]       pwdata,
  output logic [31:0]       prdata,
  output logic              pready,
  output logic              pslverr,

  // GPIO Pins (tri-state resolved externally)
  input  logic [GPIO_WIDTH-1:0] gpio_in,   // Sampled pin inputs
  output logic [GPIO_WIDTH-1:0] gpio_out,  // Pin output values
  output logic [GPIO_WIDTH-1:0] gpio_oe,   // Output enable (1=driving)

  // Interrupt
  output logic              irq            // Any enabled interrupt pending
);

  // ---------------------------------------------------------------------------
  // Register file
  // ---------------------------------------------------------------------------
  logic [GPIO_WIDTH-1:0] dir_reg;   // Direction: 1=output
  logic [GPIO_WIDTH-1:0] out_reg;   // Output data
  logic [GPIO_WIDTH-1:0] ie_reg;    // Interrupt enable
  logic [GPIO_WIDTH-1:0] is_reg;    // Interrupt status

  // ---------------------------------------------------------------------------
  // Input synchroniser — 2-stage to prevent metastability
  // ---------------------------------------------------------------------------
  logic [GPIO_WIDTH-1:0] sync_s1, sync_s2, sync_prev;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      sync_s1   <= '0;
      sync_s2   <= '0;
      sync_prev <= '0;
    end else begin
      sync_s1   <= gpio_in;
      sync_s2   <= sync_s1;
      sync_prev <= sync_s2;
    end
  end

  // ---------------------------------------------------------------------------
  // Rising-edge detection for interrupt generation
  // ---------------------------------------------------------------------------
  logic [GPIO_WIDTH-1:0] rising_edge;
  assign rising_edge = sync_s2 & ~sync_prev; // 1 where rising edge occurred

  // ---------------------------------------------------------------------------
  // Interrupt status register — set on rising edge, cleared W1C via APB
  // ---------------------------------------------------------------------------
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      is_reg <= '0;
    end else begin
      // Set bits where rising edge and interrupt enabled
      is_reg <= is_reg | (rising_edge & ie_reg);
      // Clear bits where APB writes 1 (W1C)
      if (psel && penable && pwrite && (paddr == GPIO_IS_OFF)) begin
        is_reg <= is_reg & ~pwdata[GPIO_WIDTH-1:0];
        // Re-apply any new edges that occurred this same cycle
        is_reg <= (is_reg & ~pwdata[GPIO_WIDTH-1:0]) | (rising_edge & ie_reg);
      end
    end
  end

  // ---------------------------------------------------------------------------
  // APB Write (direction, output, interrupt enable)
  // ---------------------------------------------------------------------------
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      dir_reg <= '0;     // All pins input after reset
      out_reg <= '0;
      ie_reg  <= '0;
    end else if (psel && penable && pwrite) begin
      case (paddr)
        GPIO_DIR_OFF : dir_reg <= pwdata[GPIO_WIDTH-1:0];
        GPIO_OUT_OFF : out_reg <= pwdata[GPIO_WIDTH-1:0];
        GPIO_IE_OFF  : ie_reg  <= pwdata[GPIO_WIDTH-1:0];
        GPIO_IS_OFF  : ; // Handled in always_ff above (W1C)
        default      : ; // GPIO_IN is read-only; ignore
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // APB Read
  // ---------------------------------------------------------------------------
  always_comb begin
    prdata  = 32'd0;
    pslverr = 1'b0;
    case (paddr)
      GPIO_DIR_OFF : prdata = {{(32-GPIO_WIDTH){1'b0}}, dir_reg};
      GPIO_IN_OFF  : prdata = {{(32-GPIO_WIDTH){1'b0}}, sync_s2};
      GPIO_OUT_OFF : prdata = {{(32-GPIO_WIDTH){1'b0}}, out_reg};
      GPIO_IE_OFF  : prdata = {{(32-GPIO_WIDTH){1'b0}}, ie_reg};
      GPIO_IS_OFF  : prdata = {{(32-GPIO_WIDTH){1'b0}}, is_reg};
      default      : begin prdata = 32'd0; pslverr = 1'b1; end
    endcase
  end

  assign pready  = 1'b1;

  // ---------------------------------------------------------------------------
  // Output pin drive
  // ---------------------------------------------------------------------------
  assign gpio_out = out_reg;
  assign gpio_oe  = dir_reg;

  // ---------------------------------------------------------------------------
  // Interrupt — any enabled pending interrupt
  // ---------------------------------------------------------------------------
  assign irq = |(is_reg & ie_reg);

endmodule : gpio
