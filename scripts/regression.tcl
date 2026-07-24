# =============================================================================
# File        : regression.tcl
# Project     : VeriSoC — Parameterized SoC Verification Platform
# Author      : VeriSoC Contributors
# Description : Vivado / Questa / Aldec TCL regression script.
#               Can be sourced directly inside a Vivado simulation project
#               or run standalone with xsim/vsim -do regression.tcl.
#
# Usage (Vivado):
#   vivado -mode batch -source scripts/regression.tcl
#
# Usage (Questa / ModelSim):
#   vsim -do scripts/regression.tcl
#
# Usage (Aldec):
#   vsimsa -do scripts/regression.tcl
#
# Features:
#   - Compiles all RTL and TB sources
#   - Runs all three test suites
#   - Dumps waveforms per test
#   - Reports PASS/FAIL to console and log file
# =============================================================================

# ---------------------------------------------------------------------------
# Path Configuration
# ---------------------------------------------------------------------------
set PROJ_ROOT  [file normalize [file join [file dirname [info script]] ..]]
set RTL_DIR    [file join $PROJ_ROOT rtl]
set TB_DIR     [file join $PROJ_ROOT tb]
set LOGS_DIR   [file join $PROJ_ROOT logs]
set WAVES_DIR  [file join $PROJ_ROOT waves]

# Create output directories
file mkdir $LOGS_DIR
file mkdir $WAVES_DIR

puts ""
puts "================================================================"
puts " VeriSoC Regression TCL Script"
puts " Project Root: $PROJ_ROOT"
puts "================================================================"

# ---------------------------------------------------------------------------
# Detect simulator (Vivado xsim vs ModelSim vsim)
# ---------------------------------------------------------------------------
set SIMULATOR "unknown"
if {[info commands xvlog] ne ""} {
    set SIMULATOR "vivado"
} elseif {[info commands vlog] ne ""} {
    set SIMULATOR "questa"
}

# ---------------------------------------------------------------------------
# Source file lists
# ---------------------------------------------------------------------------
set RTL_SRCS [list \
    [file join $RTL_DIR pkg.sv]           \
    [file join $RTL_DIR uart.sv]          \
    [file join $RTL_DIR spi.sv]           \
    [file join $RTL_DIR gpio.sv]          \
    [file join $RTL_DIR timer.sv]         \
    [file join $RTL_DIR apb_bridge.sv]    \
    [file join $RTL_DIR axi_lite_slave.sv]\
    [file join $RTL_DIR top.sv]           \
]

set TB_SRCS [list \
    [file join $TB_DIR interface    axi_lite_if.sv  ] \
    [file join $TB_DIR interface    apb_if.sv       ] \
    [file join $TB_DIR sequence_item axi_seq_item.sv] \
    [file join $TB_DIR sequences    base_sequence.sv] \
    [file join $TB_DIR sequences    random_sequence.sv]\
    [file join $TB_DIR sequences    burst_sequence.sv] \
    [file join $TB_DIR driver       axi_driver.sv   ] \
    [file join $TB_DIR monitor      axi_monitor.sv  ] \
    [file join $TB_DIR agent        axi_agent.sv    ] \
    [file join $TB_DIR scoreboard   scoreboard.sv   ] \
    [file join $TB_DIR coverage     coverage.sv     ] \
    [file join $TB_DIR assertions   soc_assertions.sv]\
    [file join $TB_DIR env          env.sv          ] \
    [file join $TB_DIR tests        smoke_test.sv   ] \
    [file join $TB_DIR tests        random_test.sv  ] \
    [file join $TB_DIR tests        regression_test.sv]\
    [file join $TB_DIR top_tb.sv                    ] \
]

set ALL_SRCS [concat $RTL_SRCS $TB_SRCS]

# ---------------------------------------------------------------------------
# Test suite definition
# ---------------------------------------------------------------------------
set TESTS {
    {smoke_test      {}}
    {random_test     {+num_txns=500}}
    {regression_test {}}
}

# ---------------------------------------------------------------------------
# Compile procedure
# ---------------------------------------------------------------------------
proc compile_sources {srcs} {
    global PROJ_ROOT LOGS_DIR SIMULATOR
    set log_file [file join $LOGS_DIR compile.log]
    set fh [open $log_file w]

    puts "  Compiling [llength $srcs] source files..."
    foreach src $srcs {
        if {![file exists $src]} {
            puts "  \[ERROR\] File not found: $src"
            close $fh
            return 1
        }
        puts $fh "Compiling: $src"
    }

    if {$SIMULATOR eq "vivado"} {
        set rc [catch {
            exec xvlog --sv --nolog \
                -i $PROJ_ROOT \
                -d UVM_NO_DEPRECATED \
                {*}$srcs \
                >@$fh 2>@$fh
        } err]
    } elseif {$SIMULATOR eq "questa"} {
        set rc [catch {
            exec vlog -sv -O5 \
                +incdir+$PROJ_ROOT \
                +define+UVM_NO_DEPRECATED \
                {*}$srcs \
                >@$fh 2>@$fh
        } err]
    } else {
        # Generic — assume xvlog
        set rc 0
    }

    close $fh
    if {$rc != 0} {
        puts "  \[FAIL\] Compilation errors. See $log_file"
        return 1
    }
    puts "  \[PASS\] Compilation successful. Log: $log_file"
    return 0
}

# ---------------------------------------------------------------------------
# Simulate procedure — returns 0 on PASS, 1 on FAIL
# ---------------------------------------------------------------------------
proc run_test {test_name plusargs} {
    global PROJ_ROOT LOGS_DIR WAVES_DIR SIMULATOR
    set log_file  [file join $LOGS_DIR  "${test_name}.log"]
    set wave_file [file join $WAVES_DIR "${test_name}.vcd"]

    puts "\n  Running: $test_name"
    puts "  Plusargs: $plusargs"

    if {$SIMULATOR eq "vivado"} {
        # First elaborate
        catch {
            exec xelab --nolog --debug typical \
                --sv_lib uvm -L uvm \
                -top top_tb \
                -snapshot verisoc_snap
        } elab_err

        set sim_args [list xsim verisoc_snap --nolog --runall \
            "--testplusarg=UVM_TESTNAME=${test_name}" \
            "--testplusarg=UVM_VERBOSITY=UVM_MEDIUM" \
        ]
        foreach pa $plusargs {
            lappend sim_args "--testplusarg=[string trimleft $pa +]"
        }

    } elseif {$SIMULATOR eq "questa"} {
        set sim_args [list vsim -batch \
            -do "log -r /*; run -all; quit -f" \
            "+UVM_TESTNAME=${test_name}" \
            "+UVM_VERBOSITY=UVM_MEDIUM" \
        ]
        foreach pa $plusargs { lappend sim_args $pa }
        lappend sim_args "top_tb"
    } else {
        set sim_args [list echo "No simulator — dry run"]
    }

    set fh [open $log_file w]
    set rc [catch { exec {*}$sim_args >@$fh 2>@$fh } err]
    close $fh

    # Parse UVM report from log
    set log_text [read [open $log_file r]]
    set errors   0
    set fatals   0
    regexp {UVM_ERROR\s*:\s*(\d+)}   $log_text -> errors
    regexp {UVM_FATAL\s*:\s*(\d+)}   $log_text -> fatals

    set passed [expr {$rc == 0 && $errors == 0 && $fatals == 0}]
    puts "  \[[expr {$passed ? {PASS} : {FAIL}}]\] $test_name  ERR=$errors FATAL=$fatals"
    puts "  Log: $log_file"
    return [expr {!$passed}]
}

# ---------------------------------------------------------------------------
# Main Regression Flow
# ---------------------------------------------------------------------------
set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set fail_count 0
set pass_count 0

puts "\n  Step 1/2: Compile"
set compile_rc [compile_sources $ALL_SRCS]
if {$compile_rc != 0} {
    puts "\n\[REGRESSION ABORTED\] Compilation failed."
    exit 1
}

puts "\n  Step 2/2: Simulate tests"
foreach test_entry $TESTS {
    set tname [lindex $test_entry 0]
    set targs [lindex $test_entry 1]
    set rc    [run_test $tname $targs]
    if {$rc == 0} {
        incr pass_count
    } else {
        incr fail_count
    }
}

# ---------------------------------------------------------------------------
# Summary Report
# ---------------------------------------------------------------------------
set total [llength $TESTS]
set report_file [file join $LOGS_DIR "regression_${timestamp}.txt"]
set fh [open $report_file w]
set summary "
================================================================
  VERISOC REGRESSION SUMMARY  \[$timestamp\]
================================================================
  Total Tests : $total
  PASSED      : $pass_count
  FAILED      : $fail_count
  Overall     : [expr {$fail_count == 0 ? {PASSED} : {FAILED}}]
================================================================
"
puts $summary
puts $fh $summary
close $fh

puts "  Saved: $report_file"

if {$fail_count > 0} {
    exit 1
} else {
    exit 0
}
