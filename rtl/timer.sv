// =============================================================================
// File        : timer.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : Programmable Timer / Counter peripheral with APB slave interface.
//               Features:
//               - 32-bit free-running up-counter
//               - Compare register — generates interrupt when CNT == CMP
//               - Auto-reload mode — resets counter to 0 after match
//               - One-shot mode   — stops after first match
//               - Counter overflow interrupt (separate bit in STATUS)
//               - Software enable / disable via CTRL register
//               Registers:
//                 0x000 CNT    [31:0]  Current counter value (R/W — write resets)
//                 0x004 CMP    [31:0]  Compare / reload value
//                 0x008 CTRL   [2:0]  {ONE_SHOT, AUTO_RELOAD, ENABLE}
//                 0x00C STATUS [1:0]  {OVERFLOW_IRQ, MATCH_IRQ}  (W1C)
// Standard    : IEEE 1800-2017
// =============================================================================

`include "pkg.sv"
import soc_pkg::*;

module timer (
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

  // Interrupt
  output logic        irq     // Asserted on match or overflow
);

  // ---------------------------------------------------------------------------
  // Register file
  // ---------------------------------------------------------------------------
  logic [31:0] cnt_reg;    // Counter value
  logic [31:0] cmp_reg;    // Compare value
  logic [2:0]  ctrl_reg;   // {ONE_SHOT, AUTO_RELOAD, ENABLE}
  logic [1:0]  status_reg; // {OVERFLOW_IRQ, MATCH_IRQ}  (W1C)

  wire  timer_en    = ctrl_reg[0];
  wire  auto_reload = ctrl_reg[1];
  wire  one_shot    = ctrl_reg[2];

  // ---------------------------------------------------------------------------
  // Counter and interrupt logic
  // ---------------------------------------------------------------------------
  logic match;        // Counter equals compare register
  logic cnt_was_max;  // Counter was at maximum value (overflow detect)

  assign match = (cnt_reg == cmp_reg);

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      cnt_reg    <= 32'd0;
      cmp_reg    <= 32'hFFFF_FFFF;
      ctrl_reg   <= 3'd0;          // Disabled after reset
      status_reg <= 2'd0;
      cnt_was_max<= 1'b0;
    end else begin
      // Default: clear interrupt pulse
      // Status is sticky (W1C) — only cleared by software

      // APB write handling
      if (psel && penable && pwrite) begin
        case (paddr)
          TIMER_CNT_OFF    : cnt_reg    <= pwdata;         // Write resets counter
          TIMER_CMP_OFF    : cmp_reg    <= pwdata;
          TIMER_CTRL_OFF   : ctrl_reg   <= pwdata[2:0];
          TIMER_STATUS_OFF : status_reg <= status_reg & ~pwdata[1:0]; // W1C
          default          : ;
        endcase
      end

      // Counter operation (only when enabled and no simultaneous write to CNT)
      if (timer_en && !(psel && penable && pwrite && (paddr == TIMER_CNT_OFF))) begin
        cnt_was_max <= &cnt_reg; // All 1s = about to overflow

        if (match) begin
          status_reg[0] <= 1'b1; // Set MATCH_IRQ
          if (auto_reload) begin
            cnt_reg <= 32'd0;    // Reload on match
          end else if (one_shot) begin
            ctrl_reg[0] <= 1'b0; // Disable after match
          end else begin
            cnt_reg <= cnt_reg + 32'd1;
          end
        end else begin
          cnt_reg <= cnt_reg + 32'd1;
          if (cnt_was_max && !(match)) begin
            status_reg[1] <= 1'b1; // Set OVERFLOW_IRQ
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // APB Read
  // ---------------------------------------------------------------------------
  always_comb begin
    prdata  = 32'd0;
    pslverr = 1'b0;
    case (paddr)
      TIMER_CNT_OFF    : prdata = cnt_reg;
      TIMER_CMP_OFF    : prdata = cmp_reg;
      TIMER_CTRL_OFF   : prdata = {29'd0, ctrl_reg};
      TIMER_STATUS_OFF : prdata = {30'd0, status_reg};
      default          : begin prdata = 32'd0; pslverr = 1'b1; end
    endcase
  end

  assign pready = 1'b1;

  // Interrupt fires when any sticky interrupt bit is set
  assign irq = |status_reg;

endmodule : timer
