# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Dry run of a Libero script: every Libero command the bundle uses is
# replaced by a stub that prints its arguments, then the script named on
# the command line is sourced.
foreach command {
    build_design_hierarchy
    export_bitstream_file
    export_prog_job
    import_files
    new_project
    organize_tool_files
    run_tool
    save_project
    set_root
} {
    proc $command {args} [format {puts [concat %s $args]} $command]
}

source [lindex $argv 0]
