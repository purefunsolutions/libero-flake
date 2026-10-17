# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# The blinky at 400 MHz for the Microchip Hello FPGA kit, the example of IP
# cores: a clock conditioning circuit (CCC) multiplies the on-chip 50 MHz
# oscillator to its 400 MHz maximum, and Libero derives the clock
# constraints. Clash -> Verilog -> Libero bundle; blinky_pll.v wraps the
# Clash module with the oscillator and the CCC.
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
    runCommand "hello-fpga-blinky-pll-verilog" {
      nativeBuildInputs = [clash];
    } ''
      export HOME=$TMPDIR
      cp ${./BlinkyPll.hs} BlinkyPll.hs
      clash --verilog BlinkyPll.hs
      mkdir $out
      cp verilog/BlinkyPll.topEntity/*.v $out/
    '';
in
  mkLiberoProject {
    pname = "hello-fpga-blinky-pll";
    # The kit's device, as in hello-fpga-blinky.
    device = {
      family = "SmartFusion2";
      die = "M2S010";
      package = "256 VF";
      speed = "-1";
      dieVoltage = "1.2";
      partRange = "COM";
    };
    top = "blinky_pll";
    hdl = [verilog ./blinky_pll.v];
    ioConstraints = [./blinky_pll.pdc];
    cores = [
      {
        vlnv = "Actel:SgCore:FCCC:2.0.201";
        name = "FCCC_C0";
        # GL0 = 400 MHz from the on-chip 50 MHz oscillator (the PLL's VCO
        # runs at 800 MHz), and LOCK; no other outputs, no reset ports.
        params = {
          PLL_IN_SRC = "OSC_50MHZ";
          PLL_IN_FREQ = "50.000";
          RCOSC_25_50MHZ_IS_USED = true;
          GL0_IS_USED = true;
          GL0_OUT_0_FREQ = 400;
          GL1_IS_USED = false;
          PLL_EXPOSE_RESETS = false;
          GPD0_IS_USED = false;
          GPD1_IS_USED = false;
        };
      }
    ];
  }
