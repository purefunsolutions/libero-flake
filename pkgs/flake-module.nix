# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# This flake's packages, nixpkgs style: pkgs/<name>/package.nix. They are
# exported through overlays.default (used by the NixOS modules) and as
# perSystem packages. Their passthru.tests become flake checks.
let
  ourPackages = final: {
    flexlm-license-rewrite = final.callPackage ./flexlm-license-rewrite/package.nix {};
    hello-fpga-cli = final.callPackage ./hello-fpga-cli/package.nix {};
  };

  # Functions, not packages.
  ourLibs = final: {
    mkLiberoProject = final.callPackage ./libero-project {};
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
    packages =
      lib.filterAttrs (_: lib.meta.availableOn pkgs.stdenv.hostPlatform)
      (lib.mapAttrs (name: _: pkgs.${name}) (ourPackages pkgs));

    testsOf = name: drv:
      lib.mapAttrs' (test: lib.nameValuePair "${name}-${test}")
      (drv.passthru.tests or {});
  in {
    inherit packages;

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
