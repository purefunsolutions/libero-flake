# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Dry run of a Libero script: every Libero command the bundle uses is
# replaced by a stub that prints its arguments, then the script named on
# the command line is sourced. Simulation tools also write a do file in
# Libero's shape, which the GUI's do file is made of.
foreach command {
    add_profile
    build_design_hierarchy
    change_vault_location
    create_and_configure_core
    derive_constraints_sdc
    export_bitstream_file
    export_prog_job
    generate_component
    import_files
    new_project
    organize_tool_files
    run_tool
    save_project
    set_modelsim_options
    set_root
} {
    proc $command {args} [format {puts [concat %s $args]} $command]
}

rename run_tool print_run_tool
proc run_tool {args} {
    print_run_tool {*}$args
    if {[string match SIM_* [lindex $args 1]]} {
        file mkdir project/simulation
        set f [open project/simulation/run.do w]
        puts $f "onerror { quit -f }"
        puts $f "onbreak { quit -f }"
        puts $f "vlog -sv -work presynth stimulus/tb.v"
        puts $f "vsim -L SmartFusion2 -L presynth -t 1fs presynth.tb"
        puts $f "run 0ns"
        puts $f "log -r /tb/*"
        puts $f "exit"
        close $f
    }
}

source [lindex $argv 0]
