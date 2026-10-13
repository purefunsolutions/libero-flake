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
    global root
    set args {}
    foreach kind $kinds {
        foreach f [imported_files $kind] {
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
