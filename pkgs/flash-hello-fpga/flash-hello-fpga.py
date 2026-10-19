#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
"""Program the Microchip Hello FPGA kit with a DirectC .dat file.

Finds the kit's serial port by its USB ID and the .dat file to program,
then runs `hello-fpga program` from hello-fpga-cli.
"""

import argparse
import os
import sys
from pathlib import Path

# The path of hello-fpga-cli's `hello-fpga`, filled in at installation.
HELLO_FPGA = "@hello-fpga@"

# The kit's MCP2221A USB bridge keeps Microchip's default USB ID.
KIT_USB_ID = (0x04D8, 0x00DD)


def find_dat(parser, path):
    """The file itself, the only .dat in a directory, or without a path
    the only one in ./out/*/, where the Libero runners put theirs."""
    if path is None:
        where, found = "./out/*/", sorted(Path("out").glob("*/*.dat"))
    elif Path(path).is_dir():
        where, found = path, sorted(Path(path).glob("*.dat"))
    elif Path(path).is_file():
        return path
    else:
        parser.error(f"{path}: no such file or directory")
    if len(found) != 1:
        names = ", ".join(map(str, found)) or "none"
        parser.error(f"expected one .dat file in {where}, found: {names}")
    return str(found[0])


def find_port(parser):
    """The serial port of the only kit attached."""
    # Only needed without --port.
    from serial.tools import list_ports

    found = sorted(
        port.device
        for port in list_ports.comports()
        if (port.vid, port.pid) == KIT_USB_ID
    )
    if len(found) != 1:
        names = ", ".join(found) or "none"
        parser.error(f"expected one kit (USB ID 04d8:00dd), found: {names}")
    return found[0]


def main():
    parser = argparse.ArgumentParser(
        prog="flash-hello-fpga",
        description="Program the Hello FPGA kit's SmartFusion 2 through its PIC32.",
    )
    parser.add_argument(
        "dat",
        nargs="?",
        help="a .dat file, or a directory with one (default: the one in ./out/*/)",
    )
    parser.add_argument(
        "-p", "--port", help="the kit's serial port (default: found by USB ID)"
    )
    args = parser.parse_args()

    dat = find_dat(parser, args.dat)
    port = args.port or find_port(parser)
    print(f"flash-hello-fpga: programming {dat} through {port}", file=sys.stderr)
    os.execv(HELLO_FPGA, ["hello-fpga", "program", "--port", port, dat])


if __name__ == "__main__":
    main()
