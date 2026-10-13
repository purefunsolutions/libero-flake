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
- `pkgs/flexlm-license-rewrite`: rewrites the user-editable lines of a
  FlexLM license (SERVER host and port, VENDOR/DAEMON path and port) and
  copies the signed FEATURE/INCREMENT lines unchanged, so a license
  server can use the license exactly as Microchip emailed it. Tested on a
  synthetic license under `tests/`; never commit a real license.

## Conventions

- Every file has SPDX copyright and license comments (`MIT`,
  "2026 Mika Tammi"). Files that can't hold comments are annotated in
  `REUSE.toml`.
- Every file type has a formatter in `nix/treefmt.nix`, enabled in the
  commit that adds the first file of that type.
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
