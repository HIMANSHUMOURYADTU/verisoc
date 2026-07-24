// =============================================================================
// File        : apb_bridge.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : AXI4-Lite to APB Bridge with integrated address decoder.
//               Converts AXI4-Lite transactions (from the AXI slave) into
//               APB transactions for the peripheral bus.
//
//               Protocol Flow (APB):
//                 SETUP  phase: PSEL=1, PENABLE=0
//                 ACCESS phase: PSEL=1, PENABLE=1
//                 If PREADY=0 in ACCESS, extend ACCESS (wait states)
//
//               AXI-Lite ↔ APB Mapping:
//                 AXI Write → APB write to decoded slave
//                 AXI Read  → APB read  from decoded slave
//                 Response (BRESP/RRESP) ← PSLVERR from slave
//
//               Slave Address Decode (see soc_pkg):
//                 Slave 0: UART   0x0000_0000 – 0x0000_0FFF
//                 Slave 1: SPI    0x0000_1000 – 0x0000_1FFF
//                 Slave 2: GPIO   0x0000_2000 – 0x0000_2FFF
//                 Slave 3: Timer  0x0000_3000 – 0x0000_3FFF
//
// Standard    : IEEE 1800-2017
// =============================================================================

`include "pkg.sv"
import soc_pkg::*;

module apb_bridge #(
  parameter int unsigned DATA_W    = DATA_WIDTH,
  parameter int unsigned ADDR_W    = ADDR_WIDTH,
  parameter int unsigned N_SLAVES  = NUM_SLAVES
) (
  input  logic              pclk,
  input  logic              presetn,

  // ---- AXI4-Lite Slave Port (from axi_lite_slave) -------------------------
  input  logic              axi_req_valid, // Pulse: AXI transaction request
  input  logic              axi_req_write, // 1=write, 0=read
  input  logic [ADDR_W-1:0] axi_req_addr,
  input  logic [DATA_W-1:0] axi_req_wdata,
  input  logic [DATA_W/8-1:0] axi_req_wstrb,
  output logic              axi_req_ready, // Bridge accepted request
  output logic [DATA_W-1:0] axi_resp_rdata,
  output logic              axi_resp_valid, // Response ready (1 cycle pulse)
  output logic              axi_resp_err,   // 1 = slave error

  // ---- APB Master Port (to peripherals) ------------------------------------
  output logic [ADDR_W-1:0] paddr,
  output logic [N_SLAVES-1:0] psel,
  output logic              penable,
  output logic              pwrite,
  output logic [DATA_W-1:0] pwdata,
  input  logic [DATA_W-1:0] prdata   [N_SLAVES-1:0],
  input  logic              pready   [N_SLAVES-1:0],
  input  logic              pslverr  [N_SLAVES-1:0]
);

  // ---------------------------------------------------------------------------
  // Address decoder — determine which slave is selected
  // ---------------------------------------------------------------------------
  logic [N_SLAVES-1:0] slave_sel;   // One-hot slave select

  always_comb begin
    slave_sel = '0;
    if (axi_req_valid || (bridge_state != APB_IDLE)) begin
      case (curr_addr & PERIPH_MASK)
        UART_BASE  : slave_sel = N_SLAVES'(1 << 0);
        SPI_BASE   : slave_sel = N_SLAVES'(1 << 1);
        GPIO_BASE  : slave_sel = N_SLAVES'(1 << 2);
        TIMER_BASE : slave_sel = N_SLAVES'(1 << 3);
        default    : slave_sel = '0; // Decode error
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // APB Bridge State Machine
  // ---------------------------------------------------------------------------
  apb_state_t  bridge_state;
  logic [ADDR_W-1:0]   curr_addr;
  logic [DATA_W-1:0]   curr_wdata;
  logic [DATA_W/8-1:0] curr_wstrb;
  logic                curr_write;
  logic [1:0]          sel_idx;      // Binary-encoded slave index

  // Convert one-hot slave_sel to binary index
  always_comb begin
    sel_idx = '0;
    for (int i = 0; i < N_SLAVES; i++) begin
      if (slave_sel[i]) sel_idx = 2'(i);
    end
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      bridge_state    <= APB_IDLE;
      psel            <= '0;
      penable         <= 1'b0;
      pwrite          <= 1'b0;
      paddr           <= '0;
      pwdata          <= '0;
      curr_addr       <= '0;
      curr_wdata      <= '0;
      curr_wstrb      <= '0;
      curr_write      <= 1'b0;
      axi_req_ready   <= 1'b0;
      axi_resp_valid  <= 1'b0;
      axi_resp_rdata  <= '0;
      axi_resp_err    <= 1'b0;
    end else begin
      // Default pulses
      axi_req_ready  <= 1'b0;
      axi_resp_valid <= 1'b0;

      case (bridge_state)
        // -----------------------------------------------------------------
        APB_IDLE: begin
          psel    <= '0;
          penable <= 1'b0;
          if (axi_req_valid) begin
            curr_addr  <= axi_req_addr;
            curr_wdata <= axi_req_wdata;
            curr_wstrb <= axi_req_wstrb;
            curr_write <= axi_req_write;
            axi_req_ready <= 1'b1;
            bridge_state  <= APB_SETUP;
          end
        end

        // -----------------------------------------------------------------
        APB_SETUP: begin
          axi_req_ready <= 1'b0;
          paddr   <= curr_addr;
          pwrite  <= curr_write;
          pwdata  <= curr_wdata;
          psel    <= slave_sel;
          penable <= 1'b0;
          if (|slave_sel) begin
            bridge_state <= APB_ACCESS;
          end else begin
            // Decode error — no slave selected
            axi_resp_err   <= 1'b1;
            axi_resp_rdata <= '0;
            axi_resp_valid <= 1'b1;
            bridge_state   <= APB_IDLE;
          end
        end

        // -----------------------------------------------------------------
        APB_ACCESS: begin
          penable <= 1'b1;
          // Wait for PREADY from the selected slave
          if (pready[sel_idx]) begin
            axi_resp_rdata <= prdata[sel_idx];
            axi_resp_err   <= pslverr[sel_idx];
            axi_resp_valid <= 1'b1;
            psel           <= '0;
            penable        <= 1'b0;
            bridge_state   <= APB_IDLE;
          end
        end

        default: bridge_state <= APB_IDLE;
      endcase
    end
  end

endmodule : apb_bridge
