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

Each bundle comes with these tests:

- a dry run of its Tcl with every Libero command stubbed out;
- its runner against a stub Libero;
- for SmartFusion 2 and IGLOO 2, synthesis with Yosys' `synth_sf2`, which
  reports LUT, flip-flop and carry usage without a license.

### Building with Libero

Libero checks its license out from a FlexLM server over the network, which
a Nix build cannot reach. So Nix only builds the bundle and a runner
script; `nix run` executes the runner on an x86_64-linux machine:

```sh
LM_LICENSE_FILE=1702@licenses.example.org nix run .#<design> -- -o out/<design>
```

The runner copies the bundle to a scratch directory and runs Libero
headless with its own `HOME`. It moves the programming files, reports and
logs to the output directory (default `./out/<design>`) only when every
requested programming file was exported. The free license has a single
seat: runs on one host take turns, and while the seat is in use elsewhere
the runner retries with backoff.

## Hello FPGA kit

Microchip's M2S-HELLO-FPGA-KIT carries a SmartFusion 2 M2S010-1VFG256 (hard
Cortex-M3, 12,084 LUT4 logic elements), a 50 MHz oscillator, three LEDs
and two push buttons on the FPGA, and a PIC32 that programs the FPGA over
USB. `hello-fpga-blinky` is a Clash counter on the three LEDs; SW1 resets
it. It runs from the SmartFusion 2's on-chip 50 MHz oscillator, like
Microchip's demo designs for the kit, instead of the board's oscillator.

```sh
nix build .#hello-fpga-blinky    # Clash -> Verilog -> Libero bundle
nix build .#checks.<system>.hello-fpga-blinky-yosys    # LUT and FF usage
```

## Programming the Hello FPGA kit

The kit's on-board PIC32 programs the SmartFusion 2 from a DirectC `.dat`
file sent over the kit's USB serial port; no FlashPro is needed.
`hello-fpga-cli` drives it, on Linux and on macOS:

```sh
nix run .#hello-fpga-cli -- program design.dat --port /dev/ttyACM0
```

It is packaged from [captndo/hello-fpga-cli][hello-fpga-cli], which has no
license yet.

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

[hello-fpga-cli]: https://github.com/captndo/hello-fpga-cli
