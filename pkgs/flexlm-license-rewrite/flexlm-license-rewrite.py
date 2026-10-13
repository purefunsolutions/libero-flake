#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
"""Rewrite the user-editable lines of a FlexLM license file.

A license server needs its SERVER line to name the local host and its
VENDOR (or DAEMON) lines to point at the installed vendor daemons. Those
fields are meant to be edited by the user; the FEATURE and INCREMENT lines
are signed and must not change. This tool rewrites the former and copies
everything else line by line. The only normalization is CRLF to LF.
"""

import argparse
import sys

VENDOR_KEYWORDS = ("VENDOR", "DAEMON")


class LicenseError(Exception):
    pass


def logical_lines(text):
    """Yield (physical lines, joined line); a trailing backslash continues."""
    physical = []
    for line in text.splitlines():
        if not physical and line.lstrip().startswith("#"):
            yield [line], line
            continue
        physical.append(line)
        if line.endswith("\\"):
            continue
        yield physical, " ".join(p.removesuffix("\\") for p in physical)
        physical = []
    if physical:
        yield physical, " ".join(p.removesuffix("\\") for p in physical)


def rewrite_server(tokens, host, port):
    if len(tokens) < 3:
        raise LicenseError("SERVER line needs a host name and a host ID")
    rest = tokens[3:]
    old_port = rest.pop(0) if rest and rest[0].isdigit() else None
    new_port = port or old_port
    out = [tokens[0], host or tokens[1], tokens[2]]
    if new_port:
        out.append(new_port)
    return " ".join(out + rest)


def rewrite_vendor(tokens, paths, ports):
    if len(tokens) < 2:
        raise LicenseError(f"{tokens[0]} line needs a vendor daemon name")
    keyword, name = tokens[:2]
    if name not in paths:
        raise LicenseError(
            f"no path for vendor daemon {name!r} (pass --daemon {name}=PATH)"
        )
    positional, options, port, other = [], None, None, []
    for token in tokens[2:]:
        key, sep, value = token.partition("=")
        if sep and key.upper() == "OPTIONS":
            options = value
        elif sep and key.upper() == "PORT":
            port = value
        elif sep:
            other.append(token)
        else:
            positional.append(token)
    # VENDOR name [path] [[OPTIONS=]options] [[PORT=]port]
    if len(positional) > 3:
        raise LicenseError(f"too many fields on the {keyword} {name} line")
    if len(positional) > 1:
        options = positional[1]
    if len(positional) > 2:
        port = positional[2]
    port = ports.get(name, port)
    out = [keyword, name, paths[name]]
    if options:
        out.append(f"OPTIONS={options}")
    if port:
        out.append(f"PORT={port}")
    return " ".join(out + other)


def rewrite(text, host=None, port=None, paths=None, ports=None):
    paths, ports = paths or {}, ports or {}
    output, servers, vendors = [], 0, set()
    for physical, line in logical_lines(text):
        tokens = line.split()
        keyword = tokens[0].upper() if tokens else ""
        if keyword == "SERVER":
            servers += 1
            output.append(rewrite_server(tokens, host, port))
        elif keyword in VENDOR_KEYWORDS:
            vendors.add(tokens[1] if len(tokens) > 1 else "")
            output.append(rewrite_vendor(tokens, paths, ports))
        else:
            output.extend(physical)
    if servers != 1:
        raise LicenseError(
            f"expected exactly one SERVER line, found {servers}"
            " (redundant server triads are not supported)"
        )
    for name in sorted(set(ports) - vendors):
        print(f"warning: no vendor daemon {name!r} in the license", file=sys.stderr)
    return "\n".join(output) + "\n"


def name_value(arg, convert=str):
    name, sep, value = arg.partition("=")
    if not (sep and name and value):
        raise argparse.ArgumentTypeError(f"expected NAME=VALUE, got {arg!r}")
    return name, convert(value)


def port_number(value):
    if not value.isdigit() or not 0 < int(value) < 65536:
        raise argparse.ArgumentTypeError(f"not a TCP port: {value!r}")
    return value


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("input", nargs="?", default="-", help="license file")
    parser.add_argument("-o", "--output", default="-", help="output file")
    parser.add_argument("--server-host", help="host name for the SERVER line")
    parser.add_argument("--server-port", type=port_number, help="lmgrd port")
    parser.add_argument(
        "--daemon",
        action="append",
        default=[],
        type=name_value,
        metavar="NAME=PATH",
        help="path of a vendor daemon (needed for every VENDOR line)",
    )
    parser.add_argument(
        "--daemon-port",
        action="append",
        default=[],
        type=lambda arg: name_value(arg, port_number),
        metavar="NAME=PORT",
        help="fixed TCP port of a vendor daemon",
    )
    args = parser.parse_args(argv)

    if args.input == "-":
        text = sys.stdin.read()
    else:
        with open(args.input, encoding="utf-8") as f:
            text = f.read()
    try:
        result = rewrite(
            text,
            host=args.server_host,
            port=args.server_port,
            paths=dict(args.daemon),
            ports=dict(args.daemon_port),
        )
    except LicenseError as e:
        print(f"{parser.prog}: error: {e}", file=sys.stderr)
        return 1
    if args.output == "-":
        sys.stdout.write(result)
    else:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
