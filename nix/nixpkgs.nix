# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# The package set every perSystem module sees as `pkgs`: nixpkgs with this
# flake's overlay, and the Microchip packages allowed although unfree.
{
  inputs,
  self,
  ...
}: {
  perSystem = {system, ...}: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [self.overlays.default];
      config.allowUnfreePredicate = pkg:
        builtins.elem (inputs.nixpkgs.lib.getName pkg) [
          "libero"
          "libero-unwrapped"
          "libero-license-daemons"
          "libero-megavault"
          "libero-questasim"
        ];
    };
  };
}
