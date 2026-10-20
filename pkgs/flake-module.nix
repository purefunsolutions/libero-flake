# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# This flake's packages, nixpkgs style: pkgs/<name>/package.nix. They are
# exported through overlays.default (used by the NixOS modules) and as
# perSystem packages. Their passthru.tests become flake checks.
let
  ourPackages = final: {
    flash-hello-fpga = final.callPackage ./flash-hello-fpga/package.nix {};
    flexlm-license-rewrite = final.callPackage ./flexlm-license-rewrite/package.nix {};
    hello-fpga-cli = final.callPackage ./hello-fpga-cli/package.nix {};
    hello-fpga-udev-rules = final.callPackage ./hello-fpga-udev-rules/package.nix {};
    libero = final.callPackage ./libero/package.nix {};
    libero-license-daemons = final.callPackage ./libero-license-daemons/package.nix {};
    libero-megavault = final.callPackage ./libero/megavault.nix {};
    libero-modelsim = final.callPackage ./libero/simulator.nix {
      pname = "libero-modelsim";
      dir = "ModelSim_Pro";
      binDir = "linuxacoem";
      profileTool = "ModelSim Pro Edition";
      description = "ModelSim ME Pro, the HDL simulator of Microchip Libero SoC before QuestaSim";
    };
    libero-questasim = final.callPackage ./libero/simulator.nix {
      pname = "libero-questasim";
      dir = "QuestaSim_Pro";
      binDir = "bin";
      profileTool = "QuestaSim ME";
      description = "QuestaSim ME, the default HDL simulator of Microchip Libero SoC";
    };
  };

  # Functions, not packages.
  ourLibs = final: {
    mkLiberoProject = final.callPackage ./libero-project {};
  };

  # Board designs, mkLiberoProject bundles. Flake outputs only, not part of
  # the overlay. Where Libero is available, each one's runner is an app.
  designs = pkgs: {
    hello-fpga-blinky = pkgs.callPackage ./hello-fpga-blinky/package.nix {};
    hello-fpga-blinky-pll = pkgs.callPackage ./hello-fpga-blinky-pll/package.nix {};
    hello-fpga-nixos-logo = pkgs.callPackage ./hello-fpga-nixos-logo/package.nix {};
  };

  # Tools for working on this repository. Flake packages only: not part of
  # the overlay, and no checks build them (optimize-screenshots tests itself
  # in its own build).
  tools = pkgs: {
    optimize-screenshots = pkgs.callPackage ./optimize-screenshots/package.nix {};
  };
in {
  flake.overlays.default = final: _prev: ourPackages final // ourLibs final;

  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    # A package not available on this system is left out instead of
    # breaking evaluation.
    available = lib.filterAttrs (_: lib.meta.availableOn pkgs.stdenv.hostPlatform);
    packages = available (lib.mapAttrs (name: _: pkgs.${name}) (ourPackages pkgs) // designs pkgs);

    runners =
      lib.filterAttrs (_: runner: runner != null && lib.meta.availableOn pkgs.stdenv.hostPlatform runner)
      (lib.mapAttrs (_: design: design.runner) (designs pkgs));

    testsOf = name: drv:
      lib.mapAttrs' (test: lib.nameValuePair "${name}-${test}")
      (drv.passthru.tests or {});
  in {
    # The tools on top of the packages the checks build.
    packages = packages // available (tools pkgs);

    apps =
      lib.mapAttrs (_: runner: {
        type = "app";
        program = lib.getExe runner;
        inherit (runner) meta;
      })
      runners
      // lib.optionalAttrs (packages ? libero-license-daemons) {
        lmhostid = {
          type = "app";
          program = lib.getExe' packages.libero-license-daemons "lmhostid";
          meta.description = "Print the FlexLM host IDs to request a Libero license for";
        };
      };

    # Free packages are built by the checks too. Unfree ones are left out:
    # they need the login-gated Microchip downloads.
    checks =
      lib.filterAttrs (_: drv: !drv.meta.unfree) packages
      // lib.concatMapAttrs testsOf (packages
        // {
          libero-project-example = pkgs.callPackage ./libero-project/tests/example.nix {};
        });
  };
}
