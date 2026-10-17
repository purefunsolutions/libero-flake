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
set bundle [file dirname [file dirname [file normalize [info script]]]]
source [file join $bundle tcl params.tcl]
source [file join $bundle tcl family $project(family_script)]

set project_dir [file join [pwd] project]
set export_dir [file join [pwd] export]
set root "$project(top)::work"

proc bundle_files {kind} {
    global bundle files
    set paths {}
    foreach f $files($kind) {
        lappend paths [file join $bundle $f]
    }
    return $paths
}

# Where import_files puts each kind of constraint inside the project.
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

foreach tool {SYNTHESIZE PLACEROUTE VERIFYTIMING GENERATEPROGRAMMINGDATA} {
    run_tool -name $tool
}

file mkdir $export_dir
export_programming $project(name) $export_dir $export(formats) $export(components)
save_project
