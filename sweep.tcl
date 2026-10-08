# sweep.tcl - PBL-2 Task 7: design-space sweep for delay / power / speed
#
# Runs out-of-context synth + implementation of rv64_top across
#   target clock period  x  synthesis directive
# and writes sweep/results.csv plus per-run timing/util/power reports.
#
# Full sweep (18 runs):  vivado -mode batch -source sweep.tcl
# Quick check (2 runs):  vivado -mode batch -source sweep.tcl -tclargs quick

set root [file dirname [file normalize [info script]]]
cd $root

set part       xc7z020clg484-1          ;# ZedBoard Zynq-7020
set periods    {8 10 12 15 20 25}       ;# ns
set synth_dirs {Default PerformanceOptimized AreaOptimized_high}

if {[lsearch $argv quick] >= 0} {
    set periods    {10 20}
    set synth_dirs {Default}
}

set out $root/sweep
file mkdir $out/reports
set csv [open $out/results.csv w]
puts $csv "run,period_ns,synth_directive,status,wns_ns,tns_ns,fmax_mhz,logic_levels,path_delay_ns,logic_delay_ns,net_delay_ns,luts,lutram,ffs,carry4,total_power_w,dynamic_power_w,static_power_w"
flush $csv

# pull the first number matching a regex out of a report string, else -1
proc grab {rx text} {
    if {[regexp $rx $text -> v]} { return $v }
    return -1
}
proc pathprop {path prop} {
    if {[catch {set v [get_property $prop $path]}] || $v eq ""} { return -1 }
    return $v
}

set rtl [glob $root/rtl/*.v]
set total [expr {[llength $periods] * [llength $synth_dirs]}]
set n 0

foreach p $periods {
    foreach sd $synth_dirs {
        incr n
        set run "p${p}_${sd}"
        puts "\n================ RUN $n/$total : $run ================"

        set xdc $out/reports/$run.xdc
        set fh [open $xdc w]
        puts $fh "create_clock -period $p -name clk \[get_ports clk\]"
        close $fh

        set status ok
        if {[catch {
            close_project -quiet
            create_project -in_memory -part $part
            read_verilog $rtl
            read_xdc -mode out_of_context $xdc
            synth_design -top rv64_top -part $part -mode out_of_context -directive $sd
            opt_design
            place_design
            phys_opt_design
            route_design
        } err]} {
            puts "ERROR in $run: $err"
            puts $csv "$run,$p,$sd,failed,,,,,,,,,,,,,,"
            flush $csv
            continue
        }

        # ---- timing ----
        set ts [report_timing_summary -max_paths 1 -return_string]
        set wns -1; set tns -1
        regexp {WNS\(ns\)\s+TNS\(ns\)[^\n]*\n[\s-]+\n\s*(-?[0-9.]+)\s+(-?[0-9.]+)} $ts -> wns tns
        set path [get_timing_paths -max_paths 1 -nworst 1 -setup]
        set slack [pathprop $path SLACK]
        if {$slack != -1} { set wns $slack }
        set fmax [format %.2f [expr {1000.0 / ($p - $wns)}]]
        set ll   [pathprop $path LOGIC_LEVELS]
        set dly  [pathprop $path DATAPATH_DELAY]
        set ldly [pathprop $path DATAPATH_LOGIC_DELAY]
        set ndly [pathprop $path DATAPATH_NET_DELAY]
        if {$wns < 0} { set status timing_fail }

        # ---- utilization ----
        set ut [report_utilization -return_string]
        set luts   [grab {\|\s*Slice LUTs\*?\s*\|\s*(\d+)} $ut]
        set lutram [grab {\|\s*LUT as Memory\s*\|\s*(\d+)} $ut]
        set ffs    [grab {\|\s*Slice Registers\s*\|\s*(\d+)} $ut]
        set carry  [grab {\|\s*CARRY4\s*\|\s*(\d+)} $ut]

        # ---- power (vectorless, default toggle rates) ----
        set pw [report_power -return_string]
        set ptot [grab {Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)} $pw]
        set pdyn [grab {Dynamic \(W\)\s*\|\s*([0-9.]+)} $pw]
        set psta [grab {Device Static \(W\)\s*\|\s*([0-9.]+)} $pw]

        # ---- keep full reports for the write-up ----
        set rd $out/reports
        set f [open $rd/${run}_timing_summary.rpt w]; puts $f $ts; close $f
        set f [open $rd/${run}_utilization.rpt w];    puts $f $ut; close $f
        set f [open $rd/${run}_power.rpt w];          puts $f $pw; close $f
        report_timing -max_paths 1 -nworst 1 -file $rd/${run}_critical_path.rpt

        puts $csv "$run,$p,$sd,$status,$wns,$tns,$fmax,$ll,$dly,$ldly,$ndly,$luts,$lutram,$ffs,$carry,$ptot,$pdyn,$psta"
        flush $csv
        puts ">> $run : WNS=$wns ns  Fmax=$fmax MHz  LUTs=$luts  P=$ptot W"
    }
}

close $csv
puts "\nSweep done -> $out/results.csv"
