# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# The NixOS rainbow snowflake on the Microchip Hello FPGA kit's LCD
# (SmartFusion 2 M2S010-1VFG256). The official SVG, from NixOS/nixos-artwork
# at build time -> integer edge and gradient functions (flake-geometry.py)
# -> a Clash renderer and LCD sequencer -> Verilog -> Libero bundle.
# nixos_logo.v wraps the Clash module with the on-chip oscillator and the
# power-on reset.
#
# passthru.tests.frame simulates the Clash module and checks the frame it
# writes against the SVG (FrameTest.hs).
{
  fetchurl,
  runCommand,
  writeText,
  haskellPackages,
  librsvg,
  netpbm,
  python3,
  mkLiberoProject,
}: let
  # The logo by Simon Frankau and Tim Cuthbertson, CC BY 4.0; its rainbow
  # variant, from the commit that added it.
  svg = fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/a1dc097cbb3407233ed731eef3d4daa3b7e2d121/logo/nix-snowflake-rainbow.svg";
    hash = "sha256-gMeJgiSSA5hFwtW3njZQAd4OHji6kbRCJKVoN6zsRbY=";
  };

  # The panel's 480x320 pixels, and where the SVG's square page goes on
  # them: 350 pixels wide at (65, -15), which centres the snowflake, 350 by
  # 304 pixels. The generator and the reference rendering both take these.
  screen = {
    width = 480;
    height = 320;
  };
  page = {
    left = 65;
    top = -15;
    size = 350;
  };

  geometry =
    runCommand "hello-fpga-nixos-logo-geometry" {
      nativeBuildInputs = [python3];
    } ''
      mkdir $out
      python3 ${./flake-geometry.py} ${svg} \
        --width ${toString screen.width} --height ${toString screen.height} \
        --left ${toString page.left} --top ${toString page.top} --size ${toString page.size} \
        >$out/Geometry.hs
    '';

  clash = haskellPackages.ghcWithPackages (ps: [
    ps.clash-ghc
    ps.clash-prelude
  ]);

  sources = ''
    export HOME=$TMPDIR
    cp ${./NixosLogo.hs} NixosLogo.hs
    cp ${geometry}/Geometry.hs Geometry.hs
  '';

  verilog =
    runCommand "hello-fpga-nixos-logo-verilog" {
      nativeBuildInputs = [clash];
    } ''
      ${sources}
      clash --verilog NixosLogo.hs
      mkdir $out
      cp verilog/NixosLogo.topEntity/*.v $out/
    '';

  # Without antialiasing, as the panel shows it. !important, because some
  # of the paths set shape-rendering in their own style.
  crispEdges = writeText "crisp-edges.css" ''
    * { shape-rendering: crispEdges !important; }
  '';

  frame =
    runCommand "hello-fpga-nixos-logo-frame" {
      nativeBuildInputs = [clash librsvg netpbm];
    } ''
      ${sources}
      cp ${./FrameTest.hs} FrameTest.hs
      ghc -O2 -rtsopts -outputdir build -o frame-test FrameTest.hs

      rsvg-convert --background-color=white --stylesheet=${crispEdges} \
        --page-width=${toString screen.width} --page-height=${toString screen.height} \
        --left=${toString page.left} --top=${toString page.top} \
        --width=${toString page.size} --height=${toString page.size} \
        ${svg} -o reference.png
      pngtopam reference.png >reference.ppm

      ./frame-test reference.ppm frame.ppm diff.ppm +RTS -M512m

      mkdir $out
      cp reference.png $out/
      pnmtopng frame.ppm >$out/frame.png
      pnmtopng diff.ppm >$out/diff.png
    '';

  bundle = mkLiberoProject {
    pname = "hello-fpga-nixos-logo";
    # The kit's device, as in hello-fpga-blinky.
    device = {
      family = "SmartFusion2";
      die = "M2S010";
      package = "256 VF";
      speed = "-1";
      dieVoltage = "1.2";
      partRange = "COM";
    };
    top = "nixos_logo";
    hdl = [verilog ./nixos_logo.v];
    ioConstraints = [./nixos_logo.pdc];
    timingConstraints = [./nixos_logo.sdc];
  };
in
  bundle.overrideAttrs (old: {
    passthru =
      old.passthru
      // {
        tests = old.passthru.tests // {inherit frame;};
      };
  })
