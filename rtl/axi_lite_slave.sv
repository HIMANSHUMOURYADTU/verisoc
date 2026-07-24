// =============================================================================
// File        : axi_lite_slave.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : AXI4-Lite Slave.
//               Implements full AXI4-Lite handshake on all five channels:
//                 - Write Address (AW)
//                 - Write Data    (W)
//                 - Write Response(B)
//                 - Read Address  (AR)
//                 - Read Data     (R)
//
//               The slave decouples the AXI channels from the APB bridge
//               using internal registers so that AXI handshake latency is
//               independent of APB completion latency.
//
//               Priority: Reads and Writes are serialised (one at a time)
//               because the APB bridge is single-channel.
//               Write takes priority over read when both arrive simultaneously.
//
// Standard    : IEEE 1800-2017 / ARM IHI0022E AXI4-Lite spec
// =============================================================================

`include "pkg.sv"
import soc_pkg::*;

module axi_lite_slave #(
  parameter int unsigned DATA_W = DATA_WIDTH,
  parameter int unsigned ADDR_W = ADDR_WIDTH
) (
  input  logic              aclk,
  input  logic              aresetn,

  // ---- AXI4-Lite Write Address Channel ------------------------------------
  input  logic [ADDR_W-1:0] awaddr,
  input  logic              awvalid,
  output logic              awready,

  // ---- AXI4-Lite Write Data Channel ---------------------------------------
  input  logic [DATA_W-1:0] wdata,
  input  logic [DATA_W/8-1:0] wstrb,
  input  logic              wvalid,
  output logic              wready,

  // ---- AXI4-Lite Write Response Channel -----------------------------------
  output logic [1:0]        bresp,
  output logic              bvalid,
  input  logic              bready,

  // ---- AXI4-Lite Read Address Channel -------------------------------------
  input  logic [ADDR_W-1:0] araddr,
  input  logic              arvalid,
  output logic              arready,

  // ---- AXI4-Lite Read Data Channel ----------------------------------------
  output logic [DATA_W-1:0] rdata,
  output logic [1:0]        rresp,
  output logic              rvalid,
  input  logic              rready,

  // ---- APB Bridge Request Interface ---------------------------------------
  output logic              req_valid,   // Transaction request
  output logic              req_write,   // 1=write, 0=read
  output logic [ADDR_W-1:0] req_addr,
  output logic [DATA_W-1:0] req_wdata,
  output logic [DATA_W/8-1:0] req_wstrb,
  input  logic              req_ready,   // Bridge accepted

  input  logic [DATA_W-1:0] resp_rdata,
  input  logic              resp_valid,  // Bridge response available
  input  logic              resp_err     // Bridge error (PSLVERR / decode)
);

  // ---------------------------------------------------------------------------
  // AXI channel buffer registers
  // ---------------------------------------------------------------------------
  logic [ADDR_W-1:0] aw_addr_buf;
  logic              aw_valid_buf;

  logic [DATA_W-1:0]   w_data_buf;
  logic [DATA_W/8-1:0] w_strb_buf;
  logic                w_valid_buf;

  logic [ADDR_W-1:0] ar_addr_buf;
  logic              ar_valid_buf;

  // ---------------------------------------------------------------------------
  // FSM state
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    S_IDLE       = 3'd0, // Waiting for a transaction
    S_ISSUE_WR   = 3'd1, // Issuing write to APB bridge
    S_WAIT_WR    = 3'd2, // Waiting for APB write response
    S_WRITE_RESP = 3'd3, // Sending BRESP on B channel
    S_ISSUE_RD   = 3'd4, // Issuing read to APB bridge
    S_WAIT_RD    = 3'd5, // Waiting for APB read response
    S_READ_RESP  = 3'd6  // Sending RDATA on R channel
  } axi_state_t;

  axi_state_t state;

  // ---------------------------------------------------------------------------
  // AW channel — latch address when handshake completes
  // ---------------------------------------------------------------------------
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      aw_addr_buf  <= '0;
      aw_valid_buf <= 1'b0;
      awready      <= 1'b0;
    end else begin
      awready <= 1'b0; // Single-cycle pulse
      if (awvalid && awready) begin
        aw_addr_buf  <= awaddr;
        aw_valid_buf <= 1'b1;
      end else if (awvalid && !aw_valid_buf && (state == S_IDLE)) begin
        awready      <= 1'b1; // Accept address
      end
      // Clear buffer when we issue the request
      if (state == S_ISSUE_WR && req_ready) begin
        aw_valid_buf <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // W channel — latch write data
  // ---------------------------------------------------------------------------
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      w_data_buf  <= '0;
      w_strb_buf  <= '0;
      w_valid_buf <= 1'b0;
      wready      <= 1'b0;
    end else begin
      wready <= 1'b0;
      if (wvalid && wready) begin
        w_data_buf  <= wdata;
        w_strb_buf  <= wstrb;
        w_valid_buf <= 1'b1;
      end else if (wvalid && !w_valid_buf && (state == S_IDLE)) begin
        wready <= 1'b1;
      end
      if (state == S_ISSUE_WR && req_ready) begin
        w_valid_buf <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // AR channel — latch read address
  // ---------------------------------------------------------------------------
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      ar_addr_buf  <= '0;
      ar_valid_buf <= 1'b0;
      arready      <= 1'b0;
    end else begin
      arready <= 1'b0;
      if (arvalid && arready) begin
        ar_addr_buf  <= araddr;
        ar_valid_buf <= 1'b1;
      end else if (arvalid && !ar_valid_buf && (state == S_IDLE) && !aw_valid_buf) begin
        arready <= 1'b1; // Only accept read if no pending write
      end
      if (state == S_ISSUE_RD && req_ready) begin
        ar_valid_buf <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Main state machine
  // ---------------------------------------------------------------------------
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      state      <= S_IDLE;
      req_valid  <= 1'b0;
      req_write  <= 1'b0;
      req_addr   <= '0;
      req_wdata  <= '0;
      req_wstrb  <= '0;
      bvalid     <= 1'b0;
      bresp      <= AXI_OKAY;
      rvalid     <= 1'b0;
      rdata      <= '0;
      rresp      <= AXI_OKAY;
    end else begin
      // Default: clear pulses
      req_valid <= 1'b0;

      case (state)
        // -----------------------------------------------------------------
        S_IDLE: begin
          // Prioritise writes
          if (aw_valid_buf && w_valid_buf) begin
            state <= S_ISSUE_WR;
          end else if (ar_valid_buf && !aw_valid_buf) begin
            state <= S_ISSUE_RD;
          end
        end

        // -----------------------------------------------------------------
        S_ISSUE_WR: begin
          req_valid <= 1'b1;
          req_write <= 1'b1;
          req_addr  <= aw_addr_buf;
          req_wdata <= w_data_buf;
          req_wstrb <= w_strb_buf;
          if (req_ready) begin
            req_valid <= 1'b0;
            state     <= S_WAIT_WR;
          end
        end

        // -----------------------------------------------------------------
        S_WAIT_WR: begin
          if (resp_valid) begin
            bresp  <= resp_err ? AXI_SLVERR : AXI_OKAY;
            bvalid <= 1'b1;
            state  <= S_WRITE_RESP;
          end
        end

        // -----------------------------------------------------------------
        S_WRITE_RESP: begin
          if (bready) begin
            bvalid <= 1'b0;
            state  <= S_IDLE;
          end
        end

        // -----------------------------------------------------------------
        S_ISSUE_RD: begin
          req_valid <= 1'b1;
          req_write <= 1'b0;
          req_addr  <= ar_addr_buf;
          req_wdata <= '0;
          req_wstrb <= '0;
          if (req_ready) begin
            req_valid <= 1'b0;
            state     <= S_WAIT_RD;
          end
        end

        // -----------------------------------------------------------------
        S_WAIT_RD: begin
          if (resp_valid) begin
            rdata  <= resp_rdata;
            rresp  <= resp_err ? AXI_SLVERR : AXI_OKAY;
            rvalid <= 1'b1;
            state  <= S_READ_RESP;
          end
        end

        // -----------------------------------------------------------------
        S_READ_RESP: begin
          if (rready) begin
            rvalid <= 1'b0;
            state  <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule : axi_lite_slave
