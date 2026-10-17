<!--
SPDX-FileCopyrightText: 2026 Mika Tammi
SPDX-License-Identifier: MIT
-->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Project overview

Nix flake for the Microchip Libero SoC FPGA toolchain, published as open
source. It is generic: it provides packages and NixOS modules, never
deployment decisions. The first board is the Microchip Hello FPGA kit
(SmartFusion 2 M2S010), designed in Clash.

## Commands

```sh
nix fmt
nix flake check --all-systems --no-update-lock-file
```

`nix flake check` evaluates every system but builds only the current
system's checks. The per-commit gate builds them for all systems. On the
development Mac (aarch64-darwin) the Linux ones go to its remote builder:

```sh
nix flake check --all-systems --no-update-lock-file &&
  for s in x86_64-linux aarch64-linux aarch64-darwin; do
    nix build --no-link --impure --expr \
      "builtins.attrValues (builtins.getFlake \"git+file://$PWD\").checks.$s"
  done
```

## Architecture

- `flake.nix`: flake-parts, systems x86_64-linux, aarch64-linux and
  aarch64-darwin.
- `nix/`: flake-parts modules. `treefmt.nix` (formatters, `checks.treefmt`),
  `checks.nix` (`reuse lint`) and `nixpkgs.nix` (the `pkgs` every perSystem
  module sees: nixpkgs plus our overlay).
- `pkgs/flake-module.nix`: our packages, `pkgs/<name>/package.nix`,
  exported as `overlays.default` and as `packages` filtered with
  `lib.meta.availableOn`. Free packages are checks, and so are all
  packages' `passthru.tests` (named `<package>-<test>`). Unfree packages
  are not built by the checks, because they need the Microchip downloads.
- `pkgs/hello-fpga-cli`: host CLI for the Hello FPGA kit's PIC32
  programmer (DirectC `.dat` files over the kit's USB serial port). Upstream
  has no license, so the package has no `meta.license`.
- `pkgs/hello-fpga-udev-rules`: udev rules for the kit's MCP2221A USB
  bridge (04d8:00dd, Microchip's default ID and descriptors, no serial
  number, so they match any MCP2221A): ModemManager ignores it (its AT
  probing would upset the PIC32's stateful protocol), `uaccess`, and
  `/dev/hello-fpga`. Numbered 70 because `uaccess` only works before
  `73-seat-late.rules`. Checked with `udevadm verify`. On the real kit,
  `udevadm test` with the rules as an `--extra-rules-dir` showed the
  symlink, the tag and the property.
- `nixos-modules/hello-fpga.nix`: `hardware.hello-fpga` installs them
  through `services.udev.packages`. `services.udev.extraRules` would land
  in `99-local.rules`, too late for `uaccess`.
- `pkgs/flash-hello-fpga`: wraps `hello-fpga program`. It finds the kit's
  port by USB ID with pyserial, on Linux and macOS alike, and the `.dat`
  file: the argument, the only one in a directory, or the only one in
  `./out/*/`, where the runners put theirs. Its test covers the `.dat`
  search and the `hello-fpga` call with a stub; finding the port needs a
  kit and was tested by hand.
- `pkgs/flexlm-license-rewrite`: rewrites the user-editable lines of a
  FlexLM license (SERVER host and port, VENDOR/DAEMON path and port) and
  copies the signed FEATURE/INCREMENT lines unchanged, so a license
  server can use the license exactly as Microchip emailed it. Tested on a
  synthetic license under `tests/`; never commit a real license.
- `pkgs/libero-project`: `mkLiberoProject`, a function in the overlay. It
  turns HDL and constraints into a bundle:
  - `hdl/` and `constraints/{io,fp,timing}/`;
  - `tcl/build.tcl`, the generic flow. Run it from an empty directory; the
    project goes to `./project` and the programming files to `./export`;
  - `tcl/family/<family>.tcl`, which provides `export_programming`;
  - `tcl/params.tcl`, generated, with every value restricted to a safe
    character set;
  - test: a dry run with `tests/libero-stub.tcl` stubbing every Libero
    command. The example project's transcript is compared against
    `tests/example.golden`; when the flow changes, regenerate it and review
    the diff;
  - test: Yosys synthesis. `synth_sf2` maps to CFG LUTs, SLE flip-flops,
    ARI1 carry chains and IO/clock buffers. It infers no LSRAM, µSRAM or
    math blocks, and there is no open place and route for these families.
- `pkgs/libero-project/runner.sh`: `passthru.runner` of every bundle,
  built purely by Nix and run with `nix run`. Libero needs the network for
  its license, so it never runs inside a Nix build (no impure derivations,
  no `__noChroot`). The runner:
  - needs `LM_LICENSE_FILE` (exit 3 without it), and refuses an existing
    output directory unless `--force` (exit 2);
  - runs Libero in a scratch copy of the bundle with its own `HOME` and
    `XDG_*` directories;
  - takes a host-local `flock`, because the free license has one seat;
  - retries with backoff while the seat is busy (FlexLM -4) or the server
    is unreachable (-15, -96, -97). Any other license error exits 4, and
    a build failure exits 1. Both keep the work directory;
  - moves the exports, reports, logs and `manifest.txt` into place
    atomically, and only after every format in `exports` was written;
  - is tested with `tests/libero-stub.sh` standing in for `libero`, and is
    null until a `libero` package is in scope.

## Libero

- `pkgs/libero/sources.nix`: the offline installer (`requireFile`), pinned
  to the sha256 Microchip publishes.
- `pkgs/libero/unwrapped.nix`: the zip holds the vendor's Qt installer
  and one 7z archive per component. The `Libero_SoC` archive is the
  finished installation tree (it includes FlashPro Express), so it is
  extracted with `7z`; no installer runs. `adm/verinfo`, which the launch
  scripts look for, ships in the archive.
- `pkgs/libero/megavault.nix`: `libero-megavault`, the IP cores from the
  installer's MegaVault archive, every public core as of the release
  (5.8 GB). Its `doc` output has the cores' documentation (about
  250 MB), which the core configurators otherwise link to on the web.
  `download_core` from Microchip's web catalog failed here, and the vault
  holds only some versions (FCCC 2.0.100, 2.0.200 and 2.0.201, not the
  catalog's 2.0.204).
  Libero unpacks a core's further packages (`pkg/*.zip` into `fs/p<N>f0`,
  with a marker file `p<N>`) into the vault the first time a design uses
  the core, so it needs a writable vault.
- `pkgs/libero/package.nix`: buildFHSEnv with the 74 system libraries
  Libero doesn't bundle (from a scan of the ELF dependencies; the binaries
  use the standard loader, no LSB shim). The launch scripts call
  `/usr/bin/ls`, look for libX11 in `/usr/lib` and set
  `LC_ALL=en_US.UTF-8`. Two bundled `libboost_wave` builds want a
  `libboost_chrono` Microchip doesn't ship; nothing seems to load them.
- Libero runs headless in batch mode (`libero SCRIPT:x.tcl`), without a
  display or `QT_QPA_PLATFORM`.
- Its default tool profiles name Synplify Pro, QuestaSim and Identify by
  their bare executable names (`synplify_pro`, `vsim`,
  `identify_debugger`); `Designer/data/install.def` leaves their
  locations empty. The wrappers put `Synplify_Pro/bin` on `PATH`; the
  simulators are left out, and Identify (`withIdentify`) is untested and
  would need the same.
- A few tools are 32-bit, hence `multiArch`: `Designer/am/exe/zcat`, which
  `cdlver` runs while generating the programming data, and the FlashPro
  tools in `Designer/binfp`. Their GUI libraries (Qt 4, Motif) are not in
  the environment.
- On distributions the launch script doesn't know, it adds the bundled
  RHEL `libstdc++` (`Designer/lib64/rhel`) to the library path and prints
  an unsupported-OS warning.
- `nixos-modules/libero.nix`: `programs.libero` installs the package and
  sets `LM_LICENSE_FILE`, `SNPSLMD_LICENSE_FILE` and
  `SYNPLCTYD_LICENSE_FILE` as session variables. Checked with a stub
  package by `nixos-modules/tests/libero.nix`.

## License server

- `pkgs/libero-license-daemons`: Microchip's FlexLM 11.19 daemons
  (`requireFile`; the download needs a Microchip account). The binaries
  use the standard glibc loader, not the LSB one, and are patched with
  `autoPatchelfHook`; the patched vendor daemons run normally, without
  tamper complaints. `passthru.daemonDir` and `passthru.daemons` describe
  the vendor daemons. Nothing built from them may be published (no public
  binary caches): every user downloads the Microchip files themselves.
- lmgrd wants `/usr/tmp/.flexlm` for its lock files.
- lmgrd and the vendor daemons exit with `Not a valid server hostname`
  unless the SERVER line names their host. An IP address only counts when
  the host name resolves to it, which on NixOS it doesn't (127.0.0.2).
  `FLEXLM_ANYHOSTNAME=1` skips the check (verified with 11.19.6).
- `nixos-modules/libero-license.nix`: `services.libero-license`.
  - The license is a systemd credential (`LoadCredential`) from
    `licenseFile`, a `types.externalPath`, so it can never be a store path.
  - `preStart` runs `flexlm-license-rewrite` into `$RUNTIME_DIRECTORY`;
    lmgrd runs with `-z` (foreground, logs in the journal) as the static
    user `libero-license`.
  - Fully hardened unit, except `PrivateNetwork`: the host ID is a physical
    NIC's MAC. `/usr/tmp` is linked to `/var/tmp` (tmpfiles), which
    `PrivateTmp` makes private.
  - `nixos-modules/tests/libero-license.nix` checks it with stub daemons.
    The real daemons were run under this unit in a NixOS VM test with a
    dummy license; that test needs the download, so it is not a check.

## Hello FPGA kit

Device: SmartFusion 2 M2S010-1VFG256 (Libero: die M2S010, package
`256 VF`, speed -1, 1.2 V core, COM). Kit schematics:
<https://ww1.microchip.com/downloads/aemdocuments/documents/fpga/ProductDocuments/UserGuides/hello_fpga_kit_schematics.pdf>

| Signal     | Pin     | Bank (VDDI) | Notes (schematic sheet)                      |
| ---------- | ------- | ----------- | -------------------------------------------- |
| CLK_50MHz  | N8      | 4 (3.3 V)   | DSC1001 50 MHz oscillator (4)                |
| LED1_DEBUG | T12     | 4 (3.3 V)   | LD1, lit when driven low (4, 6)              |
| LED2_DEBUG | T13     | 4 (3.3 V)   | LD2, lit when driven low (4, 6)              |
| LED3_DEBUG | G13     | 1 (3.3 V)   | LD3, lit when driven low (4, 6)              |
| PB1_DEBUG  | K1      | 5 (1.5 V)   | SW1, pulled up, low while pressed (6)        |
| PB3_DEBUG  | L1      | 5 (1.5 V)   | SW3, pulled up, low while pressed (6)        |
| FF_SW2     | J2      | 5 (1.5 V)   | SW2, Flash\*Freeze (6)                       |
| UART_TX/RX | H12/H13 | 1 (3.3 V)   | MMUART_1 pads to the PIC32's UART bridge (4) |

Bank supplies are on sheet 7: banks 1 to 4 and 7 at 3.3 V, banks 0 and 5
at 1.5 V. LD4 and LD5 belong to the PIC32.

- SmartFusion 2/IGLOO 2 I/O PDC syntax is
  `set_io <port> -pinname <pin> -fixed yes -iostd <std>`. PolarFire's is
  different (`-port_name`, `-pin_name`, `-io_std`).
- Never invent pins, banks or I/O standards: cite the schematic sheet.
- `hello-fpga-blinky` clocks from the on-chip 25/50 MHz RC oscillator
  (50 MHz at 1.2 V core, about 1 % accurate), as Microchip's demo designs
  for the kit do: `RCOSC_25_50MHZ` -> `RCOSC_25_50MHZ_FAB` -> `CLKINT` in
  `blinky.v`, a Verilog top around the Clash module. The primitives are
  declared there as black boxes (`syn_black_box` for Synplify, which also
  keeps Yosys happy), inside `ifdef SYNTHESIS`, which both define:
  simulations use the SmartFusion 2 library's models of them, and
  Synplify's netlist has empty stubs of them anyway. The SDC constrains
  the oscillator's instance pin.
  The kit's own 50 MHz oscillator X1 (N8) is not used: on one kit it
  stopped driving its output after most power-ups (the pin floated: a
  weak pull-down read low, none read high), and never recovered.

## Conventions

- Every file has SPDX copyright and license comments (`MIT`,
  "2026 Mika Tammi"). Files that can't hold comments are annotated in
  `REUSE.toml`.
- Every file type has a formatter in `nix/treefmt.nix`, enabled in the
  commit that adds the first file of that type. Verilog's is verible. On
  Darwin, nixos-26.05's verible doesn't build (its Bazel dependencies no
  longer match their hash), so `nix/treefmt.nix` applies nixpkgs master's
  fix (NixOS/nixpkgs#541557) there. Hydra doesn't build that variant, so
  Macs compile it once. Drop the override once nixos-26.05 has the fix.
- Nothing host-specific in the repository: no hostnames, MAC addresses,
  license files or absolute paths of anyone's machine.
- Checks never depend on the login-gated Microchip downloads. CI and
  contributors don't have them.

## Git workflow

- One commit per reasonably sized feature. Docs (README, this file) change
  in the same commit as the feature they describe.
- Subjects in nixpkgs style, `<attr or area>: <summary>`, e.g.
  `libero: init at 2026.1` or `nixos/libero-license: init`. Short bodies:
  why, and facts that aren't obvious from the diff.
- Commit with `git commit -s`. No other trailers.
- `flake.lock` changes only together with the input change that needs them.
- Every commit passes the per-commit gate (see Commands).
- Corrections to earlier commits go in as `git commit --fixup=<commit>`
  (or `--squash`) and are autosquashed before the merge request. To check
  the squashed series without touching the branch, save the gate as a
  script outside the repository and, in a scratch
  `git worktree add --detach`, run
  `git rebase --autosquash --exec <script> master`.

## Common mistakes to avoid

- `path:` flake inputs, or flake.lock updates riding along in unrelated
  commits.
- Dummy hashes in fixed-output derivations. A commit that pins a download
  is made only once the real hash is known.
- Committing `HANDOFF.md` or other session notes.
- Writing SPDX tag names followed by a colon in prose: `reuse lint`
  parses them anywhere in a file.
