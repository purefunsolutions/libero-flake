# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Headless Libero flow for a mkLiberoProject bundle. Run it from an empty,
# writable directory:
#
#   libero SCRIPT:<bundle>/tcl/build.tcl
#
# The project is created in ./project and the programming files are
# exported to ./export. Everything design specific comes from params.tcl;
# the family script provides export_programming.
#
# With LIBERO_SIMULATE set to presynth, postsynth or postlayout, it runs
# the testbench LIBERO_TESTBENCH, one of params.tcl's testbenches, at that
# stage instead, with the simulator LIBERO_SIMULATOR (its vsim), named
# LIBERO_SIMULATOR_TOOL in Libero's tool profiles. The results stay in
# ./project/simulation, with a VCD of the testbench's own signals if
# LIBERO_SIMULATION_VCD is "testbench", of every signal if it is "all".
# With LIBERO_SIMULATION_GUI set, it only prepares the simulation, and
# writes gui.do there to run it in the simulator's GUI.
set bundle [file dirname [file dirname [file normalize [info script]]]]
source [file join $bundle tcl params.tcl]
source [file join $bundle tcl family $project(family_script)]

set project_dir [file join [pwd] project]
set export_dir [file join [pwd] export]
set root "$project(top)::work"
set simulate [expr {[info exists ::env(LIBERO_SIMULATE)] ? $::env(LIBERO_SIMULATE) : ""}]
set tb {}
if {$simulate ne ""} {
    set tb [expr {[info exists ::env(LIBERO_TESTBENCH)] ? $::env(LIBERO_TESTBENCH) : ""}]
    if {$tb ni $testbenches} {
        error "mkLiberoProject: no testbench '$tb'; the design has: $testbenches"
    }
}

proc bundle_files {kind} {
    global bundle files
    set paths {}
    foreach f $files($kind) {
        lappend paths [file join $bundle $f]
    }
    return $paths
}

# Where import_files puts each kind of file inside the project.
proc imported_files {kind} {
    global files project_dir
    set dirs [dict create io_pdc constraint/io fp_pdc constraint/fp sdc constraint]
    set paths {}
    foreach f $files($kind) {
        lappend paths [file join $project_dir [dict get $dirs $kind] [file tail $f]]
    }
    return $paths
}

proc organize_constraints {tool kinds} {
    global root derived
    set args {}
    foreach kind $kinds {
        foreach f [imported_files $kind] {
            lappend args -file $f
        }
    }
    # Derived timing constraints go wherever the SDC files go.
    if {"sdc" in $kinds} {
        foreach f $derived {
            lappend args -file $f
        }
    }
    if {[llength $args]} {
        organize_tool_files -tool $tool {*}$args -module $root -input_type constraint
    }
}

# gui.do: Libero's do file for the simulator's GUI. It shows the
# testbench's signals and runs for the testbench's time, and $finish, an
# error or a break leave the GUI open.
proc gui_do {dir tb} {
    global testbench
    set in [open [file join $dir run.do]]
    set out [open [file join $dir gui.do] w]
    foreach line [split [read -nonewline $in] \n] {
        if {[string match "vsim *" $line]} {
            puts $out "$line -onfinish stop"
            puts $out "add wave /$testbench($tb,top)/*"
        } elseif {[string match "run *" $line]} {
            puts $out "run $testbench($tb,time)"
        } elseif {![regexp {^(onerror|onbreak|exit)\M} $line]} {
            puts $out $line
        }
    }
    close $in
    close $out
}

# Runs a testbench at a stage. Libero first synthesizes, and places and
# routes, as far as the stage needs.
proc simulate {stage tb} {
    global testbench files root project_dir
    set tools [dict create presynth SIM_PRESYNTH postsynth SIM_POSTSYNTH postlayout SIM_POSTLAYOUT]
    if {![dict exists $tools $stage]} {
        error "mkLiberoProject: unknown simulation stage '$stage' (presynth, postsynth or postlayout)"
    }
    set tool [dict get $tools $stage]
    # Libero runs simulators in batch mode when it runs a script, whatever
    # their profile says. For the GUI, it runs the simulation for no time,
    # which compiles and loads the design; gui.do runs it in the GUI.
    set gui [info exists ::env(LIBERO_SIMULATION_GUI)]

    add_profile -name mkLiberoProject -type simulation \
        -tool $::env(LIBERO_SIMULATOR_TOOL) \
        -location $::env(LIBERO_SIMULATOR) \
        -batch TRUE

    # Libero's own VCD always has every signal of the design. Ours, only if
    # asked for, has the testbench's own signals, the design's ports among
    # them, or all. vsim runs it after loading the design: Libero's batch
    # do file leaves out its "included" do files.
    set vsim_options {}
    if {[info exists ::env(LIBERO_SIMULATION_VCD)]} {
        set vcd [file join $project_dir simulation vcd.do]
        file mkdir [file dirname $vcd]
        set f [open $vcd w]
        puts $f "vcd file $testbench($tb,top).vcd"
        if {$::env(LIBERO_SIMULATION_VCD) eq "all"} {
            puts $f "vcd add -r /*"
        } else {
            puts $f "vcd add /$testbench($tb,top)/*"
        }
        close $f
        set vsim_options [list -do [file tail $vcd]]
    }

    set_modelsim_options \
        -tb_module_name $testbench($tb,top) \
        -tb_top_level_name $testbench($tb,instance) \
        -sim_runtime [expr {$gui ? "0ns" : $testbench($tb,time)}] \
        -dump_vcd 0 \
        -add_vsim_options $vsim_options

    set args {}
    foreach f $files(stimulus,$tb) {
        lappend args -file [file join $project_dir stimulus [file tail $f]]
    }
    organize_tool_files -tool $tool {*}$args -module $root -input_type stimulus
    save_project
    run_tool -name $tool
    if {$gui} {
        gui_do [file join $project_dir simulation] $tb
    }
}

new_project \
    -location $project_dir \
    -name $project(name) \
    -project_description {} \
    -block_mode 0 \
    -hdl $project(hdl) \
    -family $device(family) \
    -die $device(die) \
    -package $device(package) \
    -speed $device(speed) \
    -die_voltage $device(die_voltage) \
    -part_range $device(part_range) \
    -use_enhanced_constraint_flow 1

# IP cores from Libero's catalog, configured and generated into the project
# before the HDL that instantiates them is read. They come from the vault at
# LIBERO_VAULT (the runner's writable copy of libero-megavault), never from
# the network.
if {[llength $cores]} {
    if {![info exists ::env(LIBERO_VAULT)]} {
        error "mkLiberoProject: the design uses IP cores, set LIBERO_VAULT to a vault"
    }
    change_vault_location -location $::env(LIBERO_VAULT)
    foreach core $cores {
        lassign $core vlnv name core_params
        create_and_configure_core -core_vlnv $vlnv -component_name $name -params $core_params
        generate_component -component_name $name
    }
}

foreach f [bundle_files hdl] {
    import_files -hdl_source $f
}
if {$simulate ne ""} {
    foreach f [bundle_files stimulus,$tb] {
        import_files -stimulus $f
    }
}
foreach kind {io_pdc fp_pdc sdc} {
    foreach f [bundle_files $kind] {
        import_files -$kind $f
    }
}

build_design_hierarchy
set_root -module $root

# The cores' clock constraints (CCC outputs, oscillators), which Libero
# derives from the cores' own constraint files.
set derived {}
if {[llength $cores]} {
    derive_constraints_sdc
    set derived [glob -nocomplain -directory [file join $project_dir constraint] *_derived_constraints.sdc]
}

organize_constraints SYNTHESIZE {sdc}
organize_constraints PLACEROUTE {io_pdc fp_pdc sdc}
organize_constraints VERIFYTIMING {sdc}
save_project

if {$simulate ne ""} {
    simulate $simulate $tb
} else {
    foreach tool {SYNTHESIZE PLACEROUTE VERIFYTIMING GENERATEPROGRAMMINGDATA} {
        run_tool -name $tool
    }
    file mkdir $export_dir
    export_programming $project(name) $export_dir $export(formats) $export(components)
}
save_project
