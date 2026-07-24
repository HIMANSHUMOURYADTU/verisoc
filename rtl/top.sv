// =============================================================================
// File        : top.sv
// Project     : VeriSoC — Parameterized SoC Verification Platform
// Author      : VeriSoC Contributors
// Description : SoC Top-Level Module.
//               Instantiates and connects:
//                 1. axi_lite_slave  — AXI4-Lite register interface
//                 2. apb_bridge      — AXI → APB protocol conversion + decode
//                 3. uart            — UART peripheral (APB slave 0)
//                 4. spi             — SPI  peripheral (APB slave 1)
//                 5. gpio            — GPIO peripheral (APB slave 2)
//                 6. timer           — Timer peripheral(APB slave 3)
//
//               Memory Map (4KB per peripheral):
//                 0x0000_0000 – 0x0000_0FFF  UART
//                 0x0000_1000 – 0x0000_1FFF  SPI
//                 0x0000_2000 – 0x0000_2FFF  GPIO
//                 0x0000_3000 – 0x0000_3FFF  Timer
//
// Standard    : IEEE 1800-2017
// =============================================================================

`include "pkg.sv"
import soc_pkg::*;

module top #(
  parameter int unsigned DATA_W     = DATA_WIDTH,
  parameter int unsigned ADDR_W     = ADDR_WIDTH,
  parameter int unsigned GPIO_W     = 32,
  parameter int unsigned UART_FIFO  = 8
) (
  // System clock and reset
  input  logic              aclk,        // AXI clock (also used as PCLK)
  input  logic              aresetn,     // Async active-low reset

  // ---- AXI4-Lite Master Port (driven by testbench / DMA / CPU) -----------
  // Write Address
  input  logic [ADDR_W-1:0] awaddr,
  input  logic              awvalid,
  output logic              awready,
  // Write Data
  input  logic [DATA_W-1:0] wdata,
  input  logic [DATA_W/8-1:0] wstrb,
  input  logic              wvalid,
  output logic              wready,
  // Write Response
  output logic [1:0]        bresp,
  output logic              bvalid,
  input  logic              bready,
  // Read Address
  input  logic [ADDR_W-1:0] araddr,
  input  logic              arvalid,
  output logic              arready,
  // Read Data
  output logic [DATA_W-1:0] rdata,
  output logic [1:0]        rresp,
  output logic              rvalid,
  input  logic              rready,

  // ---- UART Pins ----------------------------------------------------------
  input  logic              uart_rx,
  output logic              uart_tx,

  // ---- SPI Pins -----------------------------------------------------------
  output logic              spi_sck,
  output logic              spi_mosi,
  input  logic              spi_miso,
  output logic              spi_cs_n,

  // ---- GPIO Pins ----------------------------------------------------------
  input  logic [GPIO_W-1:0] gpio_in,
  output logic [GPIO_W-1:0] gpio_out,
  output logic [GPIO_W-1:0] gpio_oe,

  // ---- Interrupt Lines ----------------------------------------------------
  output logic              uart_irq,
  output logic              spi_irq,
  output logic              gpio_irq,
  output logic              timer_irq
);

  // ===========================================================================
  // Internal wires — AXI slave ↔ APB bridge
  // ===========================================================================
  logic              req_valid;
  logic              req_write;
  logic [ADDR_W-1:0] req_addr;
  logic [DATA_W-1:0] req_wdata;
  logic [DATA_W/8-1:0] req_wstrb;
  logic              req_ready;

  logic [DATA_W-1:0] resp_rdata;
  logic              resp_valid;
  logic              resp_err;

  // ===========================================================================
  // Internal wires — APB bridge ↔ peripherals
  // ===========================================================================
  logic [ADDR_W-1:0]       apb_addr;
  logic [NUM_SLAVES-1:0]   apb_psel;
  logic                    apb_penable;
  logic                    apb_pwrite;
  logic [DATA_W-1:0]       apb_pwdata;

  // Per-slave read data, ready, error
  logic [DATA_W-1:0] apb_prdata  [NUM_SLAVES-1:0];
  logic              apb_pready  [NUM_SLAVES-1:0];
  logic              apb_pslverr [NUM_SLAVES-1:0];

  // Per-peripheral APB address (bottom 12 bits, peripheral-local offset)
  wire  [11:0] periph_offset = apb_addr[11:0];

  // ===========================================================================
  // Instance: AXI4-Lite Slave
  // ===========================================================================
  axi_lite_slave #(
    .DATA_W  (DATA_W),
    .ADDR_W  (ADDR_W)
  ) u_axi_slave (
    .aclk       (aclk),
    .aresetn    (aresetn),
    // AW
    .awaddr     (awaddr),
    .awvalid    (awvalid),
    .awready    (awready),
    // W
    .wdata      (wdata),
    .wstrb      (wstrb),
    .wvalid     (wvalid),
    .wready     (wready),
    // B
    .bresp      (bresp),
    .bvalid     (bvalid),
    .bready     (bready),
    // AR
    .araddr     (araddr),
    .arvalid    (arvalid),
    .arready    (arready),
    // R
    .rdata      (rdata),
    .rresp      (rresp),
    .rvalid     (rvalid),
    .rready     (rready),
    // Bridge interface
    .req_valid  (req_valid),
    .req_write  (req_write),
    .req_addr   (req_addr),
    .req_wdata  (req_wdata),
    .req_wstrb  (req_wstrb),
    .req_ready  (req_ready),
    .resp_rdata (resp_rdata),
    .resp_valid (resp_valid),
    .resp_err   (resp_err)
  );

  // ===========================================================================
  // Instance: APB Bridge
  // ===========================================================================
  apb_bridge #(
    .DATA_W   (DATA_W),
    .ADDR_W   (ADDR_W),
    .N_SLAVES (NUM_SLAVES)
  ) u_apb_bridge (
    .pclk           (aclk),
    .presetn        (aresetn),
    // AXI interface
    .axi_req_valid  (req_valid),
    .axi_req_write  (req_write),
    .axi_req_addr   (req_addr),
    .axi_req_wdata  (req_wdata),
    .axi_req_wstrb  (req_wstrb),
    .axi_req_ready  (req_ready),
    .axi_resp_rdata (resp_rdata),
    .axi_resp_valid (resp_valid),
    .axi_resp_err   (resp_err),
    // APB interface
    .paddr          (apb_addr),
    .psel           (apb_psel),
    .penable        (apb_penable),
    .pwrite         (apb_pwrite),
    .pwdata         (apb_pwdata),
    .prdata         (apb_prdata),
    .pready         (apb_pready),
    .pslverr        (apb_pslverr)
  );

  // ===========================================================================
  // Instance: UART (APB slave 0)
  // ===========================================================================
  uart #(
    .FIFO_DEPTH   (UART_FIFO)
  ) u_uart (
    .pclk     (aclk),
    .presetn  (aresetn),
    .paddr    (periph_offset),
    .psel     (apb_psel[0]),
    .penable  (apb_penable),
    .pwrite   (apb_pwrite),
    .pwdata   (apb_pwdata),
    .prdata   (apb_prdata[0]),
    .pready   (apb_pready[0]),
    .pslverr  (apb_pslverr[0]),
    .rx       (uart_rx),
    .tx       (uart_tx),
    .irq      (uart_irq)
  );

  // ===========================================================================
  // Instance: SPI (APB slave 1)
  // ===========================================================================
  spi u_spi (
    .pclk     (aclk),
    .presetn  (aresetn),
    .paddr    (periph_offset),
    .psel     (apb_psel[1]),
    .penable  (apb_penable),
    .pwrite   (apb_pwrite),
    .pwdata   (apb_pwdata),
    .prdata   (apb_prdata[1]),
    .pready   (apb_pready[1]),
    .pslverr  (apb_pslverr[1]),
    .sck      (spi_sck),
    .mosi     (spi_mosi),
    .miso     (spi_miso),
    .cs_n     (spi_cs_n),
    .irq      (spi_irq)
  );

  // ===========================================================================
  // Instance: GPIO (APB slave 2)
  // ===========================================================================
  gpio #(
    .GPIO_WIDTH (GPIO_W)
  ) u_gpio (
    .pclk     (aclk),
    .presetn  (aresetn),
    .paddr    (periph_offset),
    .psel     (apb_psel[2]),
    .penable  (apb_penable),
    .pwrite   (apb_pwrite),
    .pwdata   (apb_pwdata),
    .prdata   (apb_prdata[2]),
    .pready   (apb_pready[2]),
    .pslverr  (apb_pslverr[2]),
    .gpio_in  (gpio_in),
    .gpio_out (gpio_out),
    .gpio_oe  (gpio_oe),
    .irq      (gpio_irq)
  );

  // ===========================================================================
  // Instance: Timer (APB slave 3)
  // ===========================================================================
  timer u_timer (
    .pclk     (aclk),
    .presetn  (aresetn),
    .paddr    (periph_offset),
    .psel     (apb_psel[3]),
    .penable  (apb_penable),
    .pwrite   (apb_pwrite),
    .pwdata   (apb_pwdata),
    .prdata   (apb_prdata[3]),
    .pready   (apb_pready[3]),
    .pslverr  (apb_pslverr[3]),
    .irq      (timer_irq)
  );

endmodule : top
