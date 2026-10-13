<!--
SPDX-FileCopyrightText: 2026 Mika Tammi
SPDX-License-Identifier: MIT
-->

# libero-flake

Nix flake for the Microchip Libero SoC FPGA toolchain. Libero covers
PolarFire, PolarFire SoC, SmartFusion 2, IGLOO 2, RTG4, RT PolarFire and
RT PolarFire SoC.

## Platforms

Microchip ships Libero SoC, FlashPro Express and the FlexLM license
daemons for x86_64 only:

| Platform       | Vendor support                                 | In this flake                    |
| -------------- | ---------------------------------------------- | -------------------------------- |
| x86_64-linux   | RHEL/AlmaLinux 8 and 9, Ubuntu 22.04 and 24.04 | vendor tools and everything else |
| Windows 11     | full, including node-locked licenses           | not packaged                     |
| aarch64-linux  | none                                           | portable parts only              |
| aarch64-darwin | none                                           | portable parts only              |

On aarch64-linux the x86_64-linux packages still work through binary
translation, for example in a VM with Rosetta and
`extra-platforms = x86_64-linux`. On macOS, run them on such a VM or on an
x86_64-linux host.

## Designs

`mkLiberoProject` (in `overlays.default`) turns HDL and constraints into a
Libero project bundle. The bundle holds the sources plus Tcl that creates
the project, runs synthesis, place and route and timing analysis, and
exports the programming files. Building a bundle needs no Microchip
software.

Each bundle comes with two tests:

- a dry run of its Tcl with every Libero command stubbed out;
- for SmartFusion 2 and IGLOO 2, synthesis with Yosys' `synth_sf2`, which
  reports LUT, flip-flop and carry usage without a license.

## Development

```sh
nix fmt                          # format everything
nix flake check --all-systems    # evaluate all systems, check this one
```

`nix flake check` never needs the Microchip downloads. Every commit passes
the checks of all three systems; `CLAUDE.md` has the command.

## License

The Nix code and scripts in this repository are licensed under the MIT
license, see `LICENSES/MIT.txt`. Microchip's software is proprietary: every
user downloads it from Microchip themselves, and nothing built from it may
be redistributed.
