# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# `nix develop`: Clash, Yosys and the tools for the Hello FPGA kit. No
# Libero, so it works on every system and without the Microchip downloads.
{
  perSystem = {
    config,
    pkgs,
    ...
  }: {
    devShells.default = pkgs.mkShell {
      packages = [
        (pkgs.haskellPackages.ghcWithPackages (ps: [
          ps.clash-ghc
          ps.clash-prelude
        ]))
        pkgs.reuse
        pkgs.tclint
        pkgs.yosys
        config.packages.hello-fpga-cli
      ];
    };
  };
}
