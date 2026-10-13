# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Clash blinky for the Microchip Hello FPGA kit (SmartFusion 2
# M2S010-1VFG256): Clash -> Verilog -> Libero bundle. blinky.v wraps the
# Clash module with the on-chip oscillator.
{
  runCommand,
  haskellPackages,
  mkLiberoProject,
}: let
  clash = haskellPackages.ghcWithPackages (ps: [
    ps.clash-ghc
    ps.clash-prelude
  ]);

  verilog =
    runCommand "hello-fpga-blinky-verilog" {
      nativeBuildInputs = [clash];
    } ''
      export HOME=$TMPDIR
      cp ${./Blinky.hs} Blinky.hs
      clash --verilog Blinky.hs
      mkdir $out
      cp verilog/Blinky.topEntity/*.v $out/
    '';
in
  mkLiberoProject {
    pname = "hello-fpga-blinky";
    # The kit's device: the Microchip product page and distributors list
    # M2S010-1VFG256. The core runs at 1.2 V (schematic sheet 7).
    device = {
      family = "SmartFusion2";
      die = "M2S010";
      package = "256 VF";
      speed = "-1";
      dieVoltage = "1.2";
      partRange = "COM";
    };
    top = "blinky";
    hdl = [verilog ./blinky.v];
    ioConstraints = [./blinky.pdc];
    timingConstraints = [./blinky.sdc];
  }
