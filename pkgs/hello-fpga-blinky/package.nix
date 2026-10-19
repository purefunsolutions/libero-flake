# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Clash blinky for the Microchip Hello FPGA kit (SmartFusion 2
# M2S010-1VFG256): Clash -> Verilog -> Libero bundle. blinky.v wraps the
# Clash module with the on-chip oscillator. Its testbenches: blinky_tb.v,
# of the whole chip, and one of the Clash module, written in Clash.
{
  runCommand,
  haskellPackages,
  mkLiberoProject,
}: let
  clash = haskellPackages.ghcWithPackages (ps: [
    ps.clash-ghc
    ps.clash-prelude
  ]);

  # The core, and its testbench in the second output.
  verilog =
    runCommand "hello-fpga-blinky-verilog" {
      nativeBuildInputs = [clash];
      outputs = ["out" "testbench"];
    } ''
      export HOME=$TMPDIR
      cp ${./Blinky.hs} Blinky.hs
      clash --verilog Blinky.hs
      mkdir $out $testbench
      cp verilog/Blinky.topEntity/*.v $out/
      cp verilog/Blinky.testBench/*.v $testbench/
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
    testbenches = [
      # The whole chip, at every stage: blinky_tb.v.
      {
        name = "chip";
        hdl = [./blinky_tb.v];
        top = "blinky_tb";
        instance = "dut";
      }
      # Clash's testbench of the core (Blinky.hs), before synthesis only.
      {
        name = "core";
        hdl = [verilog.testbench];
        top = "testBench";
      }
    ];
  }
