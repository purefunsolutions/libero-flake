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

## Libero SoC

1. Download "Libero SoC Design Suite Version 2026.1 Full Installer" for
   Linux (`libero_soc_2026.1_offline_lin.zip`, about 19 GB) from
   Microchip's FPGA software downloads page; this needs a free Microchip
   account. Check it against the sha256sum published there.
1. Add it to the Nix store with `nix-store --add-fixed sha256 <file>`, and
   keep a copy outside the store.
1. Build it on the x86_64-linux machine that will run it:
   `nix build .#libero`. The installation takes about 24 GB; the Identify
   debugger is left out unless the package is overridden with
   `withIdentify`.

The HDL simulators come from the same download, as packages of their own:
`libero-questasim`, QuestaSim ME, Libero's default simulator (7.2 GB),
and `libero-modelsim`, ModelSim ME Pro (0.75 GB). The license covers
both. The runners use them to simulate designs (see Simulating below);
Libero's own GUI finds them with
`libero.override { simulators = [libero-questasim libero-modelsim]; }`.

IP cores, such as the clock conditioning circuits with their PLLs, come from
the same download: `nix build .#libero-megavault` unpacks its MegaVault,
every core as of the release (5.8 GB). Only designs with IP cores need it,
and builds never download cores from Microchip's catalog. The cores'
documentation (about 250 MB) is its `doc` output,
`nix build .#libero-megavault.doc`.

On NixOS, `nixosModules.libero` installs it for all users and points it
at a license server (see below):

```nix
{lib, ...}: {
  imports = [libero-flake.nixosModules.libero];
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) ["libero" "libero-unwrapped"];
  programs.libero = {
    enable = true;
    licenseServer = "1702@licenses.example.org";
  };
}
```

Flakes that use this one can fetch the installer from elsewhere, for
example from a private mirror (see the license daemons below). It is the
`installer` argument of `libero.unwrapped` and of every other package
built from it, so an overlay after `overlays.default` can replace it:

```nix
_final: prev: let
  inherit (prev.libero.unwrapped) src;
  installer = import <nix/fetchurl.nix> {
    url = "https://mirror.example.org/${src.name}";
    inherit (src) name;
    hash = src.outputHash;
  };
in {
  libero = prev.libero.override {
    unwrapped = prev.libero.unwrapped.override {inherit installer;};
  };
  libero-megavault = prev.libero-megavault.override {inherit installer;};
  libero-questasim = prev.libero-questasim.override {inherit installer;};
  libero-modelsim = prev.libero-modelsim.override {inherit installer;};
}
```

## License server

Libero needs a FlexLM license server, even on a single machine: on Linux,
Microchip only offers floating licenses. The free Silver license covers
SmartFusion 2 and IGLOO 2 up to 25K logic elements and the smaller
PolarFire parts. It has one seat, is valid for a year, and is tied to the
MAC address of the license server, which Microchip expects to be a
physical x86_64 machine (VMs are not supported).

1. Download the Linux license daemons,
   `Linux_Licensing_Daemon_11.19.6.0_64-bit.tar.gz`, with a free Microchip
   account (Daemons tab of Microchip's FPGA licensing page), and add the
   tarball to the Nix store: `nix-store --add-fixed sha256 <file>`.
1. On the license server, run `nix run .#lmhostid` and pick the MAC
   address of a physical network interface.
1. At <https://www.microchipdirect.com/fpga-software-products>, choose
   "Request Free License" and register a Silver floating license for that
   MAC address. The license file arrives by email.
1. Enable the NixOS module, with the license file kept outside the Nix
   store:

```nix
{config, lib, ...}: {
  imports = [libero-flake.nixosModules.libero-license];
  nixpkgs.config.allowUnfreePredicate = pkg:
    lib.getName pkg == "libero-license-daemons";
  services.libero-license = {
    enable = true;
    licenseFile = "/etc/nixos/libero-license.dat";
  };
  # Open lmgrd and the vendor daemons on one interface only.
  networking.firewall.interfaces.wg0.allowedTCPPorts =
    config.services.libero-license.ports;
}
```

The service reads the license as a systemd credential, rewrites its SERVER
line and daemon paths at every start, and pins the vendor daemons to fixed
ports (1703 to 1705 by default), so the emailed file is used as it is.
Clients point `LM_LICENSE_FILE`, `SNPSLMD_LICENSE_FILE` and, for the
simulators, `SALT_LICENSE_SERVER` at `1702@<server>`. lmgrd tells them the
host name from the SERVER line, which must resolve for them too; if it
doesn't, set `services.libero-license.hostName` to an IP address they
reach the server at.

Flakes that use this one can fetch the tarball from elsewhere instead,
for example from a private mirror, by overriding the package's `src`.
Nix's built-in fetcher reads `nix.settings.netrc-file`, so the mirror
can sit behind basic auth; with the same name and hash, the store path
stays the same. Microchip's files must not be made public.

```nix
libero-license-daemons.overrideAttrs (old: {
  src = import <nix/fetchurl.nix> {
    url = "https://mirror.example.org/${old.src.name}";
    inherit (old.src) name;
    hash = old.src.outputHash;
  };
})
```

On NixOS, set it as `services.libero-license.package`.

## Designs

`mkLiberoProject` (in `overlays.default`) turns HDL and constraints into a
Libero project bundle. The bundle holds the sources plus Tcl that creates
the project, runs synthesis, place and route and timing analysis, and
exports the programming files. Building a bundle needs no Microchip
software.

A design can also configure IP cores from Libero's catalog, such as a
clock conditioning circuit that multiplies a clock with its PLL. They come
from `libero-megavault`: the runner gives Libero a writable copy of its
vault, and Libero derives the cores' clock constraints, so the design's
timing constraints need not repeat them.

Each bundle comes with these tests:

- a dry run of its Tcl with every Libero command stubbed out, building
  and, with a testbench, simulating;
- its runner against a stub Libero;
- for SmartFusion 2 and IGLOO 2, synthesis with Yosys' `synth_sf2`, which
  reports LUT, flip-flop and carry usage without a license. Designs with
  IP cores skip it: Libero generates the cores' HDL.

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

### Simulating

A design's testbenches (`testbenches` in `mkLiberoProject`) are simulated
by the same runner: before synthesis, after it, or after place and route
with the routed timing. `--testbench` picks one by its name; the first is
the default.

```sh
nix run .#<design> -- --simulate                  # before synthesis, QuestaSim
nix run .#<design> -- --simulate=postsynth        # the synthesized netlist
nix run .#<design> -- --simulate=postlayout       # the routed netlist and its timing
nix run .#<design> -- --simulate --testbench <name>
nix run .#<design> -- --simulate --simulator modelsim
nix run .#<design> -- --simulate --vcd            # a VCD of the testbench's signals
nix run .#<design> -- --simulate --gui            # the simulator's GUI
```

Libero compiles the design with Microchip's simulation libraries, after
synthesizing, placing and routing it as far as the stage needs, and runs
the simulator. The runner writes the simulator's log and Libero's logs to
`./out/<design>-<testbench>-<stage>-<simulator>`, and exits with status 5
if the testbench failed: `$error` or `$fatal`, a VHDL assertion of
severity error or failure, or a mismatch of Clash's `outputVerifier`.
Testbenches are written by hand in (System)Verilog or VHDL, or generated
by Clash.

A VCD, with `--vcd` of the testbench's own signals or with `--vcd-all` of
every signal of the design, grows with the simulated time: a testbench
with a clock of its own, as Clash's have, makes gigabytes per simulated
second, and ModelSim, a 32-bit program, can't write more than 2 GiB.
GTKWave or Surfer show VCDs on any system.

With `--gui`, the testbench runs in the simulator's GUI, with its signals
in the wave window. It stops at the testbench's end and the GUI stays
open; quitting it ends the run, which is then judged by the GUI's log.
That needs an X display: over SSH, `ssh -X` (XQuartz on macOS). The
simulators find the license server through `SALT_LICENSE_SERVER`, which
defaults to `LM_LICENSE_FILE`.

## Hello FPGA kit

Microchip's M2S-HELLO-FPGA-KIT carries a SmartFusion 2 M2S010-1VFG256 (hard
Cortex-M3, 12,084 LUT4 logic elements), a 50 MHz oscillator, three LEDs
and two push buttons on the FPGA, and a PIC32 that programs the FPGA over
USB. `hello-fpga-blinky` is a Clash counter on the three LEDs; SW1 resets
it. It runs from the SmartFusion 2's on-chip 50 MHz oscillator, like
Microchip's demo designs for the kit, instead of the board's oscillator.

`hello-fpga-blinky-pll` is the same counter at 400 MHz, the most a clock
conditioning circuit (CCC) puts out: the CCC's PLL multiplies the on-chip
oscillator, and Libero derives the clock constraints. It is the example of
a design with IP cores.

`hello-fpga-blinky`'s testbench `chip`, `blinky_tb.v`, releases SW1 and
checks that LED1 lights 2^25 oscillator periods later, 0.67 s: the carry
out of the counter's 25 lower bits. It runs at every stage: QuestaSim
takes about a minute before synthesis, 8 minutes after it and half an
hour with the routed timing; ModelSim, which Libero runs without
QuestaSim's `+acc`, takes 45 s, 6 and 14 minutes.

```sh
nix build .#hello-fpga-blinky    # Clash -> Verilog -> Libero bundle
nix build .#checks.<system>.hello-fpga-blinky-yosys    # LUT and FF usage
nix run .#hello-fpga-blinky -- --simulate    # testbench chip, with Libero
```

## Programming the Hello FPGA kit

The kit's on-board PIC32 programs the SmartFusion 2 from a DirectC `.dat`
file sent over the kit's USB serial port; no FlashPro is needed.
`flash-hello-fpga` finds the kit by its USB ID and programs it, on Linux
and on macOS:

```sh
nix run .#hello-fpga-blinky    # Libero, see above: out/hello-fpga-blinky/
nix run .#flash-hello-fpga     # programs the only .dat in out/*/
```

Give it a `.dat` file or a directory with one, and `--port` when more than
one MCP2221A is attached. It runs `hello-fpga program` from
`hello-fpga-cli`, which can also verify and erase the FPGA, read its core
power and bridge its UART (`nix run .#hello-fpga-cli -- --help`).
`hello-fpga-cli` is packaged from [captndo/hello-fpga-cli][hello-fpga-cli],
which has no license yet.

### Serial port access on Linux

The kit's serial port, `/dev/ttyACM*`, belongs to the `dialout` group. The
udev rules in `hello-fpga-udev-rules` give the user logged in at the
machine access to it, add the name `/dev/hello-fpga`, and keep
ModemManager from probing it. The kit's USB bridge, an MCP2221A, keeps
Microchip's generic USB ID, so the rules apply to any MCP2221A. On NixOS:

```nix
{
  imports = [libero-flake.nixosModules.hello-fpga];
  hardware.hello-fpga.enable = true;
}
```

Elsewhere, install them with

```sh
sudo cp "$(nix build --no-link --print-out-paths .#hello-fpga-udev-rules)"/lib/udev/rules.d/70-hello-fpga.rules /etc/udev/rules.d/
```

and replug the kit. Over SSH, access needs the `dialout` group.

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
