# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# SmartFusion 2 and IGLOO 2. Formats: DAT for DirectC (the Hello FPGA
# kit's on-board PIC32 programs these), STP (STAPL) for FlashPro, and JOB
# for FlashPro Express. Components: FABRIC, ENVM.
proc export_programming {name dir formats components} {
    set bitstream_formats {}
    foreach format $formats {
        if {$format ne "JOB"} {
            lappend bitstream_formats $format
        }
    }
    if {[llength $bitstream_formats]} {
        export_bitstream_file \
            -file_name $name \
            -export_dir $dir \
            -format $bitstream_formats \
            -trusted_facility_file 1 \
            -trusted_facility_file_components $components
    }
    if {"JOB" in $formats} {
        export_prog_job \
            -job_file_name $name \
            -export_dir $dir \
            -bitstream_file_type TRUSTED_FACILITY \
            -bitstream_file_components $components
    }
}
