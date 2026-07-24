# VeriSoC

<div align="center">

![VeriSoC Banner](docs/images/banner.png)

**A Production-Quality, Parameterized SoC Verification Platform**

*Built with IEEE SystemVerilog · UVM 1.2 · 31 files · 4 peripherals · Full regression in one command*

[![CI Status](https://github.com/your-org/verisoc/actions/workflows/ci.yml/badge.svg)](https://github.com/your-org/verisoc/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog%202017-green.svg)](#)
[![UVM](https://img.shields.io/badge/Methodology-UVM%201.2-orange.svg)](#)
[![Simulator](https://img.shields.io/badge/Simulator-Vivado%20%7C%20Questa%20%7C%20VCS-purple.svg)](#)

</div>

---

## Overview

**VeriSoC** is a complete, interview-ready SoC verification platform demonstrating senior-level skills in RTL design, UVM methodology, and verification automation.  It implements a realistic AXI4-Lite bus fabric with four peripherals — UART, SPI, GPIO, and Timer — verified by a full UVM environment including a register-model scoreboard, 7-group functional coverage, SVA assertions, and a Python regression automation framework.

Every file is production-quality: no placeholder code, no TODOs, no pseudocode.

---

## Architecture

```
                    ┌────────────────────────────────────┐
  AXI4-Lite         │            top.sv (SoC Top)         │
  Master ──────────▶│  ┌──────────────┐  ┌─────────────┐ │
  (Testbench)       │  │axi_lite_slave│  │  apb_bridge  │ │
                    │  │  (5-channel  │  │ (AXI→APB +  │ │
                    │  │  AXI slave)  │─▶│  Addr Decode)│ │
                    │  └──────────────┘  └──────┬──────┘ │
                    │                           │         │
                    │          ┌────────────────┼──────┐  │
                    │          │  APB Peripheral Bus   │  │
                    │          │                       │  │
                    │   ┌──────▼┐ ┌──────┐ ┌──────┐ ┌─▼───┐│
                    │   │ UART  │ │ SPI  │ │ GPIO │ │Timer││
                    │   │ 0x000 │ │0x1000│ │0x2000│ │0x3000││
                    │   └───────┘ └──────┘ └──────┘ └──────┘│
                    └────────────────────────────────────────┘
```

### Bus Protocol Stack

| Layer     | Protocol    | File                  |
|-----------|-------------|----------------------|
| CPU/TB    | AXI4-Lite   | `axi_lite_if.sv`     |
| Slave     | AXI4-Lite   | `axi_lite_slave.sv`  |
| Bridge    | AXI→APB     | `apb_bridge.sv`      |
| Periph    | APB v2      | `apb_if.sv`          |

---

## Memory Map

| Peripheral | Base Address   | End Address    | Size |
|------------|---------------|----------------|------|
| **UART**   | `0x0000_0000` | `0x0000_0FFF`  | 4 KB |
| **SPI**    | `0x0000_1000` | `0x0000_1FFF`  | 4 KB |
| **GPIO**   | `0x0000_2000` | `0x0000_2FFF`  | 4 KB |
| **Timer**  | `0x0000_3000` | `0x0000_3FFF`  | 4 KB |

---

## Register Map

<details>
<summary>UART Registers (base: 0x0000_0000)</summary>

| Offset | Name     | Access | Description                          |
|--------|----------|--------|--------------------------------------|
| 0x000  | TXDATA   | W      | Write byte to push to TX FIFO        |
| 0x004  | RXDATA   | R      | Read byte from RX FIFO               |
| 0x008  | STATUS   | R      | `[4]`RXERR `[3]`RXFULL `[2]`RXEMPTY `[1]`TXFULL `[0]`TXEMPTY |
| 0x00C  | CONTROL  | R/W    | `[1]`RX_EN `[0]`TX_EN               |
| 0x010  | BAUD_DIV | R/W    | Baud rate divisor = clk/baud - 1     |

</details>

<details>
<summary>SPI Registers (base: 0x0000_1000)</summary>

| Offset | Name     | Access | Description                          |
|--------|----------|--------|--------------------------------------|
| 0x000  | CONTROL  | R/W    | `[3]`WIDTH16 `[2]`CPHA `[1]`CPOL `[0]`EN |
| 0x004  | STATUS   | R      | `[2]`RXFULL `[1]`TXFULL `[0]`BUSY   |
| 0x008  | TXDATA   | R/W    | Write to trigger transfer            |
| 0x00C  | RXDATA   | R      | Last received data                   |
| 0x010  | CLKDIV   | R/W    | SCK = PCLK / (2*(CLKDIV+1))         |

</details>

<details>
<summary>GPIO Registers (base: 0x0000_2000)</summary>

| Offset | Name | Access | Description                            |
|--------|------|--------|----------------------------------------|
| 0x000  | DIR  | R/W    | Pin direction: 1=output, 0=input       |
| 0x004  | IN   | R      | Synchronised pin inputs                |
| 0x008  | OUT  | R/W    | Output data register                   |
| 0x00C  | IE   | R/W    | Interrupt enable (per pin)             |
| 0x010  | IS   | R/W    | Interrupt status (W1C, rising-edge)    |

</details>

<details>
<summary>Timer Registers (base: 0x0000_3000)</summary>

| Offset | Name   | Access | Description                           |
|--------|--------|--------|---------------------------------------|
| 0x000  | CNT    | R/W    | Current counter value (write resets)  |
| 0x004  | CMP    | R/W    | Compare value (match → interrupt)     |
| 0x008  | CTRL   | R/W    | `[2]`ONE_SHOT `[1]`AUTO_RELOAD `[0]`EN |
| 0x00C  | STATUS | R/W    | `[1]`OVERFLOW_IRQ `[0]`MATCH_IRQ (W1C) |

</details>

---

## Features

### RTL Design
- ✅ Parameterized AXI4-Lite Slave — all 5 channels, proper handshake latching
- ✅ AXI-to-APB Bridge — 3-phase APB protocol (IDLE→SETUP→ACCESS)
- ✅ UART — 8N1, 16× oversampling RX, TX/RX FIFOs, programmable baud rate
- ✅ SPI Master — programmable CPOL/CPHA, 8/16-bit width, auto CS
- ✅ GPIO — 32-pin, direction control, 2-stage sync, rising-edge IRQ, W1C
- ✅ Timer — 32-bit, auto-reload + one-shot, overflow detect, W1C
- ✅ Interrupt lines from all 4 peripherals

### Verification Environment
- ✅ `axi_seq_item`      — constrained-random transaction with byte-strobe
- ✅ `base_sequence`     — `do_write`, `do_read`, `poll_until` utilities
- ✅ `random_sequence`   — fully randomized, configurable count
- ✅ `burst_sequence`    — WRITE / READ / RW burst modes
- ✅ `axi_driver`        — clocking-block-driven, simultaneous AW+W channels
- ✅ `axi_monitor`       — parallel write + read thread monitoring
- ✅ `axi_agent`         — active/passive configurable
- ✅ `scoreboard`        — shadow register model with byte-enable masking
- ✅ `coverage`          — 7 covergroups including cross coverage
- ✅ `soc_assertions`    — 10 SVA assertions + 4 cover properties (bound)
- ✅ `env`               — full UVM environment
- ✅ Smoke, Random, and Regression tests

### Automation
- ✅ `scripts/run.py`        — Python automation (compile / run / regression / report)
- ✅ `scripts/regression.tcl`— Vivado/Questa TCL regression
- ✅ `.github/workflows/ci.yml`— GitHub Actions CI with Verilator lint

---

## Repository Structure

```
VeriSoC/
├── .github/
│   └── workflows/
│       └── ci.yml                  # GitHub Actions CI
├── docs/
│   └── images/
├── rtl/
│   ├── pkg.sv                      # SoC package: params, types, memory map
│   ├── axi_lite_slave.sv           # AXI4-Lite slave (5-channel)
│   ├── apb_bridge.sv               # AXI→APB bridge + decoder
│   ├── uart.sv                     # UART peripheral (8N1)
│   ├── spi.sv                      # SPI master peripheral
│   ├── gpio.sv                     # GPIO peripheral (32-pin)
│   ├── timer.sv                    # Timer/counter peripheral
│   └── top.sv                      # SoC top-level
├── tb/
│   ├── interface/
│   │   ├── axi_lite_if.sv          # AXI4-Lite SV interface
│   │   └── apb_if.sv               # APB SV interface
│   ├── sequence_item/
│   │   └── axi_seq_item.sv         # UVM sequence item
│   ├── sequences/
│   │   ├── base_sequence.sv        # Base sequence + utilities
│   │   ├── random_sequence.sv      # Random stimulus
│   │   └── burst_sequence.sv       # Burst stimulus
│   ├── driver/
│   │   └── axi_driver.sv           # UVM driver
│   ├── monitor/
│   │   └── axi_monitor.sv          # UVM monitor
│   ├── agent/
│   │   └── axi_agent.sv            # UVM agent
│   ├── scoreboard/
│   │   └── scoreboard.sv           # UVM scoreboard
│   ├── coverage/
│   │   └── coverage.sv             # Functional coverage
│   ├── assertions/
│   │   └── soc_assertions.sv       # SVA assertions (bind)
│   ├── env/
│   │   └── env.sv                  # UVM environment
│   ├── tests/
│   │   ├── smoke_test.sv           # Directed smoke test
│   │   ├── random_test.sv          # Constrained-random test
│   │   └── regression_test.sv      # Full regression test
│   └── top_tb.sv                   # Top testbench module
├── scripts/
│   ├── run.py                      # Python automation script
│   └── regression.tcl              # TCL regression script
├── .gitignore
├── LICENSE
└── README.md
```

---

## UVM Architecture

```
uvm_test_top (smoke_test / random_test / regression_test)
└── env
    ├── m_agent (axi_agent, UVM_ACTIVE)
    │   ├── sequencer (uvm_sequencer #(axi_seq_item))
    │   │   └── ← base_seq / random_seq / burst_seq
    │   ├── driver   (axi_driver)  → axi_lite_if.master
    │   └── monitor  (axi_monitor) ← axi_lite_if.monitor
    │            │ ap (analysis_port)
    │            ├──────────────────────────────────────┐
    ▼                                                   ▼
  m_scoreboard (scoreboard)              m_coverage (coverage)
  [shadow register model]                [7 covergroups]
```

### Analysis Port Connections
```
axi_agent.ap ──▶ scoreboard.analysis_export  (expected vs actual)
axi_agent.ap ──▶ coverage.analysis_export    (functional coverage)
```

---

## Simulation Flow

### Prerequisites
- Simulator: Vivado 2023+, Questasim 2022+, or VCS 2023+
- Python 3.8+
- UVM 1.2 library included with simulator

### Quick Start

**Option A — Python script (recommended)**
```bash
# Compile
python scripts/run.py compile

# Run smoke test
python scripts/run.py run --test smoke_test

# Run random test with 1000 transactions
python scripts/run.py run --test random_test --num-txns 1000

# Full regression (all 3 tests)
python scripts/run.py regression

# Print last regression report
python scripts/run.py report
```

**Option B — TCL (Vivado batch)**
```bash
vivado -mode batch -source scripts/regression.tcl
```

**Option C — TCL (Questa)**
```bash
vsim -do scripts/regression.tcl
```

**Option D — Manual (Vivado)**
```bash
# Compile
xvlog --sv -i . rtl/pkg.sv rtl/uart.sv rtl/spi.sv rtl/gpio.sv \
      rtl/timer.sv rtl/apb_bridge.sv rtl/axi_lite_slave.sv rtl/top.sv \
      tb/interface/axi_lite_if.sv tb/interface/apb_if.sv \
      tb/sequence_item/axi_seq_item.sv \
      tb/sequences/base_sequence.sv tb/sequences/random_sequence.sv \
      tb/sequences/burst_sequence.sv tb/driver/axi_driver.sv \
      tb/monitor/axi_monitor.sv tb/agent/axi_agent.sv \
      tb/scoreboard/scoreboard.sv tb/coverage/coverage.sv \
      tb/assertions/soc_assertions.sv tb/env/env.sv \
      tb/tests/smoke_test.sv tb/tests/random_test.sv \
      tb/tests/regression_test.sv tb/top_tb.sv

# Elaborate
xelab --debug typical --sv_lib uvm -L uvm -top top_tb -snapshot verisoc_snap

# Simulate
xsim verisoc_snap --runall \
     --testplusarg UVM_TESTNAME=smoke_test \
     --testplusarg UVM_VERBOSITY=UVM_MEDIUM
```

### Plusargs
| Plusarg                | Default        | Description                  |
|------------------------|----------------|------------------------------|
| `+UVM_TESTNAME=<name>` | *(required)*   | Test class to run            |
| `+UVM_VERBOSITY=<lvl>` | `UVM_MEDIUM`   | UVM message verbosity        |
| `+num_txns=<N>`        | 200            | Transactions for random test |

---

## Verification Coverage

### Functional Coverage Groups (7 total)

| Covergroup             | Description                           | Target |
|------------------------|---------------------------------------|--------|
| `cg_direction`         | Read vs Write distribution            | 100%   |
| `cg_peripheral`        | UART / SPI / GPIO / Timer             | 100%   |
| `cg_address`           | Per-register coverage                 | 100%   |
| `cg_response`          | OKAY / SLVERR response codes          | 100%   |
| `cg_rw_x_peripheral`   | Cross: direction × peripheral         | 100%   |
| `cg_wstrb`             | 8 write strobe patterns               | 100%   |
| `cg_data_corners`      | Zero / All-ones / byte-FF / random    | 100%   |

### Assertions (10 asserts + 4 covers)

| ID  | Category      | Description                                |
|-----|---------------|--------------------------------------------|
| A1  | AXI Handshake | AWVALID stable until handshake             |
| A2  | AXI Handshake | AWADDR stable while AWVALID high           |
| A3  | AXI Handshake | WVALID stable until handshake              |
| A4  | AXI Handshake | WDATA stable while WVALID high             |
| A5  | AXI Handshake | ARVALID stable until handshake             |
| A6  | AXI Timing    | BVALID→BREADY within 32 cycles             |
| A7  | AXI Timing    | RVALID→RREADY within 32 cycles             |
| A8  | Write Strobe  | WSTRB ≠ 0 on valid write                  |
| A9  | Response      | BRESP ∈ {OKAY, SLVERR}                    |
| A10 | Response      | RRESP ∈ {OKAY, SLVERR}                    |
| B1  | Serialisation | No simultaneous read+write request         |
| C1  | Interrupt     | No X/Z on interrupt lines                  |

---

## Coding Standards

This project follows IEEE 1800-2017 SystemVerilog coding conventions:

- `always_ff` for sequential logic (never `always @(posedge clk)`)
- `always_comb` for combinational logic (never `always @(*)`)
- `typedef enum` for all state machines
- `logic` type everywhere (never `wire`/`reg` except interface signals)
- Parameterized modules with `parameter int unsigned`
- `generate` blocks for conditional/array logic
- Consistent 2-space indentation
- File-level header blocks on every file
- UVM macros from `uvm_macros.svh` (factory, field utils, reporting)

---

## Waveforms

After running any simulation, waveforms are available in `waves/`:

```bash
# Open in Vivado Wave Viewer
vivado -source xsim.tcl   # loads .wdb file

# Open in GTKWave (VCD)
gtkwave waves/smoke_test.vcd
```

Key signals to probe:
- `top_tb.axi_if.*`           — AXI4-Lite bus activity
- `top_tb.dut.u_apb_bridge.*` — APB bridge state machine
- `top_tb.dut.u_uart.*`       — UART TX/RX state machines
- `top_tb.dut.*_irq`          — All interrupt lines

---

## Future Improvements

- [ ] AXI4 full (burst) slave with AWLEN/AWSIZE support
- [ ] Register Abstraction Layer (RAL) using `uvm_reg`
- [ ] DMA engine with scatter-gather support
- [ ] Interrupt controller (PLIC/NVIC-style)
- [ ] Clock domain crossing (CDC) checker
- [ ] Formal verification properties (JasperGold / SymbiYosys)
- [ ] Power-aware simulation (UPF/CPF)
- [ ] VIP integration (Synopsys / Cadence AXI VIP)
- [ ] HTML coverage report generation
- [ ] Parameterized test using `uvm_reg` model and `uvm_reg_sequence`

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-enhancement`
3. Commit: `git commit -m "feat: add DMA engine"`
4. Push: `git push origin feature/my-enhancement`
5. Open a Pull Request

Please ensure:
- All new RTL compiles with Verilator lint
- New TB components follow existing UVM patterns
- CI pipeline passes before requesting review

---

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

<div align="center">

*Built with ❤️ for the VLSI verification community*

**[⭐ Star this repo](https://github.com/your-org/verisoc) · [🐛 Report a Bug](https://github.com/your-org/verisoc/issues) · [💡 Request a Feature](https://github.com/your-org/verisoc/issues)**

</div>
