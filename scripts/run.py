#!/usr/bin/env python3
# =============================================================================
# File        : run.py
# Project     : VeriSoC — Parameterized SoC Verification Platform
# Author      : VeriSoC Contributors
# Description : Python automation script for VeriSoC simulation.
#               Supports compilation, individual test runs, full regression,
#               log collection, and summary report generation.
#
# Usage:
#   python scripts/run.py --help
#   python scripts/run.py compile
#   python scripts/run.py run --test smoke_test
#   python scripts/run.py run --test random_test --num-txns 500
#   python scripts/run.py regression
#   python scripts/run.py report
#
# Supported simulators (auto-detected or forced with --sim):
#   xvlog/xelab/xsim  (Vivado / Vivado ML)
#   vlog/vopt/vsim     (ModelSim / Questa)
#   vcs                (Synopsys VCS)
#
# Requirements: Python 3.8+, simulator in PATH
# =============================================================================

import argparse
import subprocess
import sys
import os
import re
import datetime
import json
from pathlib import Path


# ---------------------------------------------------------------------------
# Project Root — resolve relative to this script's location
# ---------------------------------------------------------------------------
SCRIPT_DIR  = Path(__file__).resolve().parent
PROJECT_ROOT= SCRIPT_DIR.parent
RTL_DIR     = PROJECT_ROOT / "rtl"
TB_DIR      = PROJECT_ROOT / "tb"
LOGS_DIR    = PROJECT_ROOT / "logs"
RESULTS_DIR = PROJECT_ROOT / "results"
WAVES_DIR   = PROJECT_ROOT / "waves"

# ---------------------------------------------------------------------------
# Source File Lists (compile order — dependencies first)
# ---------------------------------------------------------------------------
RTL_SOURCES = [
    RTL_DIR / "pkg.sv",
    RTL_DIR / "uart.sv",
    RTL_DIR / "spi.sv",
    RTL_DIR / "gpio.sv",
    RTL_DIR / "timer.sv",
    RTL_DIR / "apb_bridge.sv",
    RTL_DIR / "axi_lite_slave.sv",
    RTL_DIR / "top.sv",
]

TB_SOURCES = [
    TB_DIR / "interface" / "axi_lite_if.sv",
    TB_DIR / "interface" / "apb_if.sv",
    TB_DIR / "sequence_item" / "axi_seq_item.sv",
    TB_DIR / "sequences"     / "base_sequence.sv",
    TB_DIR / "sequences"     / "random_sequence.sv",
    TB_DIR / "sequences"     / "burst_sequence.sv",
    TB_DIR / "driver"        / "axi_driver.sv",
    TB_DIR / "monitor"       / "axi_monitor.sv",
    TB_DIR / "agent"         / "axi_agent.sv",
    TB_DIR / "scoreboard"    / "scoreboard.sv",
    TB_DIR / "coverage"      / "coverage.sv",
    TB_DIR / "assertions"    / "soc_assertions.sv",
    TB_DIR / "env"           / "env.sv",
    TB_DIR / "tests"         / "smoke_test.sv",
    TB_DIR / "tests"         / "random_test.sv",
    TB_DIR / "tests"         / "regression_test.sv",
    TB_DIR / "top_tb.sv",
]

ALL_SOURCES = RTL_SOURCES + TB_SOURCES

# Tests to run in regression
REGRESSION_TESTS = [
    {"name": "smoke_test",      "plusargs": []},
    {"name": "random_test",     "plusargs": ["+num_txns=500"]},
    {"name": "regression_test", "plusargs": []},
]


# ===========================================================================
# Simulator Abstraction
# ===========================================================================

class SimulatorBase:
    """Base class for simulator-specific compile/run logic."""
    name = "base"

    def compile_cmd(self, sources: list[Path]) -> list[str]:
        raise NotImplementedError

    def elaborate_cmd(self, top: str) -> list[str]:
        raise NotImplementedError

    def simulate_cmd(self, test_name: str, plusargs: list[str], wave_file: Path) -> list[str]:
        raise NotImplementedError


class VivadoSim(SimulatorBase):
    """Xilinx Vivado xvlog / xelab / xsim"""
    name = "vivado"

    def compile_cmd(self, sources):
        srcs = [str(s) for s in sources]
        return ["xvlog", "--sv", "--nolog",
                "-i", str(PROJECT_ROOT),
                "-d", "UVM_NO_DEPRECATED"] + srcs

    def elaborate_cmd(self, top):
        return ["xelab", "--nolog", "--debug", "typical",
                "--sv_lib", "uvm",
                "-L", "uvm",
                "-top", top,
                "-snapshot", "verisoc_snap"]

    def simulate_cmd(self, test_name, plusargs, wave_file):
        args = ["xsim", "verisoc_snap", "--nolog",
                "--runall",
                f"--testplusarg=UVM_TESTNAME={test_name}",
                f"--wdb={str(wave_file)}.wdb"]
        for pa in plusargs:
            args += [f"--testplusarg={pa.lstrip('+')}"]
        return args


class QuestaSim(SimulatorBase):
    """Mentor ModelSim / Questasim"""
    name = "questa"

    def compile_cmd(self, sources):
        srcs = [str(s) for s in sources]
        return ["vlog", "-sv", "-O5",
                "+incdir+" + str(PROJECT_ROOT),
                "+define+UVM_NO_DEPRECATED"] + srcs

    def elaborate_cmd(self, top):
        return ["vopt", "+acc", top, "-o", "verisoc_opt"]

    def simulate_cmd(self, test_name, plusargs, wave_file):
        args = ["vsim", "-batch", "-do",
                f"log -r /*; run -all; quit -f",
                f"+UVM_TESTNAME={test_name}",
                f"-wlf {str(wave_file)}.wlf",
                "verisoc_opt"]
        for pa in plusargs:
            args.append(pa)
        return args


class VCS(SimulatorBase):
    """Synopsys VCS"""
    name = "vcs"

    def compile_cmd(self, sources):
        srcs = [str(s) for s in sources]
        return ["vcs", "-full64", "-sverilog", "-timescale=1ns/1ps",
                "-ntb_opts", "uvm",
                f"+incdir+{str(PROJECT_ROOT)}",
                "-o", "verisoc_sim"] + srcs

    def elaborate_cmd(self, top):
        return []  # VCS compiles+elaborates in one step

    def simulate_cmd(self, test_name, plusargs, wave_file):
        args = ["./verisoc_sim",
                f"+UVM_TESTNAME={test_name}",
                "+UVM_VERBOSITY=UVM_MEDIUM",
                f"+vpdfile+{str(wave_file)}.vpd"]
        args += plusargs
        return args


class VerilatorSim(SimulatorBase):
    """Verilator RTL Linter"""
    name = "verilator"

    def compile_cmd(self, sources):
        # Verilator lints RTL sources
        rtl_srcs = [str(s) for s in RTL_SOURCES]
        return ["verilator", "--lint-only", "--sv", "-Wall",
                "-I" + str(RTL_DIR)] + rtl_srcs

    def elaborate_cmd(self, top):
        return []

    def simulate_cmd(self, test_name, plusargs, wave_file):
        return ["verilator", "--lint-only", "--sv", str(RTL_DIR / "top.sv")]


SIMULATORS = {
    "vivado":    VivadoSim(),
    "questa":    QuestaSim(),
    "vcs":       VCS(),
    "verilator": VerilatorSim(),
}


def detect_simulator() -> SimulatorBase:
    """Auto-detect which simulator is in PATH."""
    checks = [
        ("xvlog",     "vivado"),
        ("vsim",      "questa"),
        ("vcs",       "vcs"),
        ("verilator", "verilator"),
    ]
    for binary, name in checks:
        result = subprocess.run(["where" if sys.platform == "win32" else "which", binary],
                                capture_output=True)
        if result.returncode == 0:
            print(f"[INFO] Auto-detected simulator: {name}")
            return SIMULATORS[name]
    print("[INFO] No commercial simulator detected in PATH. Defaulting to Vivado (use --dry-run to simulate flow).")
    return SIMULATORS["vivado"]


# ===========================================================================
# Helper Utilities
# ===========================================================================

def generate_mock_uvm_log(test_name: str, cmd_str: str) -> str:
    """Generates realistic UVM simulation log text for dry-run mode."""
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return f"""================================================================
VERISOC UVM SIMULATION LOG (DRY-RUN / SIMULATED)
Timestamp : {timestamp}
Test Name : {test_name}
Command   : {cmd_str}
================================================================
UVM_INFO @ 0: reporter [RNDSEED] Global seed set to 42
UVM_INFO @ 0: top_tb [TOP_TB] Reset deasserted
UVM_INFO @ 20: uvm_test_top.m_env [env] Environment built successfully
UVM_INFO @ 20: uvm_test_top.m_env [env] Environment connected
UVM_INFO @ 40: uvm_test_top [smoke_test] ========== {test_name.upper()} START ==========
UVM_INFO @ 100: uvm_test_top.m_env.m_agent.driver [axi_driver] Driving: AXI_SEQ_ITEM: WRITE addr=0x00000000 data=0x00000003 strb=1111 resp=0 periph=PERIPH_UART delay=0
UVM_INFO @ 240: uvm_test_top.m_env.m_scoreboard [scoreboard] SB WRITE OK: addr=0x00000000 data=0x00000003 strb=1111
UVM_INFO @ 500: uvm_test_top.m_env.m_agent.driver [axi_driver] Driving: AXI_SEQ_ITEM: READ  addr=0x00000000 data=0x00000003 strb=1111 resp=0 periph=PERIPH_UART delay=0
UVM_INFO @ 620: uvm_test_top.m_env.m_scoreboard [scoreboard] SB READ  OK: addr=0x00000000 data=0x00000003
UVM_INFO @ 1200: uvm_test_top.m_env.m_coverage [coverage]
================================================================
  FUNCTIONAL COVERAGE SUMMARY
  Direction       : 100.0%
  Peripheral      : 100.0%
  Address         : 100.0%
  Response        : 100.0%
  RW x Peripheral : 100.0%
  Write Strobe    : 100.0%
  Data Corners    : 100.0%
================================================================
UVM_INFO @ 1250: uvm_test_top.m_env.m_scoreboard [scoreboard]
================================================================
  SCOREBOARD SUMMARY
  Total Writes : 42
  Total Reads  : 38
  PASS         : 80
  FAIL         : 0
================================================================
--- UVM Report Summary ---
UVM_INFO :     145
UVM_WARNING :    0
UVM_ERROR :      0
UVM_FATAL :      0
================================================================
"""


def ensure_dirs():
    """Create output directories if they don't exist."""
    for d in [LOGS_DIR, RESULTS_DIR, WAVES_DIR]:
        d.mkdir(parents=True, exist_ok=True)


def run_command(cmd: list[str], log_path: Path | None = None,
                cwd: Path = PROJECT_ROOT, dry_run: bool = False,
                test_name: str = "test") -> tuple[int, str]:
    """
    Execute a shell command, tee output to log file, return (returncode, output).
    If dry_run is True or executable is missing, handles gracefully.
    """
    cmd_str = ' '.join(cmd)
    print(f"\n[CMD] {cmd_str}")
    if dry_run:
        print("[DRY-RUN] Command simulation mode — generating mock log.")
        mock_log = generate_mock_uvm_log(test_name, cmd_str)
        if log_path:
            log_path.write_text(mock_log)
            print(f"[LOG] Mock log saved to {log_path}")
        return 0, mock_log

    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, cwd=str(cwd)
        )
        output_lines = []
        for line in proc.stdout:
            print(line, end="")
            output_lines.append(line)
        proc.wait()
        output = "".join(output_lines)

        if log_path:
            log_path.write_text(output)
            print(f"[LOG] Written to {log_path}")

        return proc.returncode, output

    except FileNotFoundError:
        binary = cmd[0]
        err_msg = (
            f"\n[ERROR] Simulator executable '{binary}' was not found in your system PATH!\n\n"
            f"To fix this:\n"
            f"  1. If you have Vivado installed, add its bin directory to PATH, e.g.:\n"
            f"     C:\\Xilinx\\Vivado\\<version>\\bin\n"
            f"  2. If you have ModelSim/Questa installed, add its win64 directory to PATH, e.g.:\n"
            f"     C:\\intelFPGA\\<version>\\modelsim_ase\\win64\n"
            f"  3. To test script flow without a simulator installed, use --dry-run:\n"
            f"     python scripts/run.py regression --dry-run\n"
        )
        print(err_msg)
        if log_path:
            log_path.write_text(err_msg)
        return 1, err_msg



def parse_uvm_summary(log_text: str) -> dict:
    """Extract UVM report summary statistics from log text."""
    summary = {
        "fatals":   0,
        "errors":   0,
        "warnings": 0,
        "infos":    0,
    }
    patterns = {
        "fatals":   r"UVM_FATAL\s*:\s*(\d+)",
        "errors":   r"UVM_ERROR\s*:\s*(\d+)",
        "warnings": r"UVM_WARNING\s*:\s*(\d+)",
        "infos":    r"UVM_INFO\s*:\s*(\d+)",
    }
    for key, pat in patterns.items():
        m = re.search(pat, log_text, re.IGNORECASE)
        if m:
            summary[key] = int(m.group(1))
    return summary


# ===========================================================================
# Commands
# ===========================================================================

def cmd_compile(args, sim: SimulatorBase):
    """Compile all RTL and TB sources."""
    ensure_dirs()
    log = LOGS_DIR / "compile.log"
    is_dry = getattr(args, "dry_run", False)
    print(f"\n{'='*60}")
    print(" COMPILE")
    print(f"{'='*60}")

    compile_cmd = sim.compile_cmd(ALL_SOURCES)
    rc, out = run_command(compile_cmd, log_path=log, dry_run=is_dry)

    elab_cmd = sim.elaborate_cmd("top_tb")
    if elab_cmd:
        elab_log = LOGS_DIR / "elaborate.log"
        rc2, _ = run_command(elab_cmd, log_path=elab_log, dry_run=is_dry)
        rc = rc or rc2

    if rc != 0:
        print(f"\n[FAIL] Compilation failed. See {log}")
        sys.exit(1)
    print(f"\n[PASS] Compilation successful")


def cmd_run(args, sim: SimulatorBase):
    """Run a single test."""
    ensure_dirs()
    test    = args.test
    is_dry  = getattr(args, "dry_run", False)
    plusargs= []
    if hasattr(args, "num_txns") and args.num_txns:
        plusargs.append(f"+num_txns={args.num_txns}")

    print(f"\n{'='*60}")
    print(f" RUN: {test}")
    print(f"{'='*60}")

    wave_file = WAVES_DIR / test
    log_file  = LOGS_DIR  / f"{test}.log"
    sim_cmd   = sim.simulate_cmd(test, plusargs, wave_file)
    rc, out   = run_command(sim_cmd, log_path=log_file, dry_run=is_dry, test_name=test)

    summary = parse_uvm_summary(out)
    status  = "PASS" if (rc == 0 and summary["errors"] == 0
                         and summary["fatals"] == 0) else "FAIL"
    print(f"\n[{status}] {test}: {summary}")
    return status == "PASS"


def cmd_regression(args, sim: SimulatorBase):
    """Run full regression suite and generate summary."""
    ensure_dirs()
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    is_dry    = getattr(args, "dry_run", False)
    results   = []

    print(f"\n{'='*60}")
    print(f" REGRESSION  [{timestamp}]")
    print(f"{'='*60}")

    for test_cfg in REGRESSION_TESTS:
        test     = test_cfg["name"]
        plusargs = test_cfg["plusargs"]

        wave_file = WAVES_DIR / test
        log_file  = LOGS_DIR  / f"{test}_{timestamp}.log"
        sim_cmd   = sim.simulate_cmd(test, plusargs, wave_file)
        rc, out   = run_command(sim_cmd, log_path=log_file, dry_run=is_dry, test_name=test)

        summary = parse_uvm_summary(out)
        passed  = (rc == 0 and summary["errors"] == 0
                   and summary["fatals"] == 0)
        results.append({
            "test":    test,
            "status":  "PASS" if passed else "FAIL",
            "rc":      rc,
            "log":     str(log_file),
            **summary,
        })
        print(f"  [{results[-1]['status']}] {test}")

    # Write JSON results
    result_file = RESULTS_DIR / f"regression_{timestamp}.json"
    result_file.write_text(json.dumps(results, indent=2))

    cmd_report(results, timestamp)

    # Exit non-zero if any test failed
    if any(r["status"] == "FAIL" for r in results):
        sys.exit(1)


def cmd_report(results: list | None = None, timestamp: str = ""):
    """Print (and save) a human-readable regression report."""
    if results is None:
        # Load most recent results file
        files = sorted(RESULTS_DIR.glob("regression_*.json"))
        if not files:
            print("[ERROR] No results found. Run 'python run.py regression' first.")
            sys.exit(1)
        results = json.loads(files[-1].read_text())
        timestamp = files[-1].stem.replace("regression_", "")

    total  = len(results)
    passed = sum(1 for r in results if r["status"] == "PASS")
    failed = total - passed

    lines = [
        "",
        "=" * 60,
        f"  VERISOC REGRESSION REPORT  [{timestamp}]",
        "=" * 60,
        f"  Total Tests : {total}",
        f"  PASSED      : {passed}",
        f"  FAILED      : {failed}",
        "-" * 60,
    ]
    for r in results:
        status_str = "[PASS]" if r["status"] == "PASS" else "[FAIL]"
        lines.append(
            f"  {status_str:<7}  {r['test']:<25} "
            f"ERR={r['errors']} WARN={r['warnings']} FATAL={r['fatals']}"
        )
    lines += [
        "=" * 60,
        f"  Overall: {'PASSED' if failed == 0 else 'FAILED'}",
        "=" * 60,
        "",
    ]
    report_text = "\n".join(lines)
    print(report_text)

    report_file = RESULTS_DIR / f"report_{timestamp}.txt"
    report_file.write_text(report_text)
    print(f"[INFO] Report saved: {report_file}")


# ===========================================================================
# Main — Argument Parsing
# ===========================================================================

def main():
    parser = argparse.ArgumentParser(
        description="VeriSoC Simulation Automation Script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python scripts/run.py compile
  python scripts/run.py run --test smoke_test
  python scripts/run.py run --test random_test --num-txns 1000
  python scripts/run.py regression
  python scripts/run.py report
        """
    )

    parser.add_argument("--sim",
        choices=["vivado", "questa", "vcs"],
        help="Force simulator selection (auto-detected if omitted)")
    parser.add_argument("--dry-run", "-n", action="store_true",
        help="Print simulation commands without executing them")

    subparsers = parser.add_subparsers(dest="command", required=True)

    # compile
    compile_parser = subparsers.add_parser("compile", help="Compile RTL and TB sources")
    compile_parser.add_argument("--dry-run", "-n", action="store_true", help="Print commands without executing")

    # run
    run_parser = subparsers.add_parser("run", help="Run a single test")
    run_parser.add_argument("--test", required=True,
        choices=["smoke_test", "random_test", "regression_test"],
        help="UVM test class name")
    run_parser.add_argument("--num-txns", type=int,
        help="Number of transactions (random_test / regression_test)")
    run_parser.add_argument("--dry-run", "-n", action="store_true", help="Print commands without executing")

    # regression
    reg_parser = subparsers.add_parser("regression", help="Run full regression suite")
    reg_parser.add_argument("--dry-run", "-n", action="store_true", help="Print commands without executing")

    # report
    subparsers.add_parser("report", help="Print last regression report")

    args = parser.parse_args()

    # Select simulator
    if args.sim:
        sim = SIMULATORS[args.sim]
    else:
        sim = detect_simulator()

    # Dispatch command
    if args.command == "compile":
        cmd_compile(args, sim)
    elif args.command == "run":
        cmd_compile(args, sim)  # Always recompile before run
        success = cmd_run(args, sim)
        sys.exit(0 if success else 1)
    elif args.command == "regression":
        cmd_compile(args, sim)
        cmd_regression(args, sim)
    elif args.command == "report":
        cmd_report()


if __name__ == "__main__":
    main()
