# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# `nix fmt` and `checks.treefmt`. Every file type in the repository gets a
# formatter here in the same commit that adds the first file of that type.
{inputs, ...}: {
  imports = [
    inputs.treefmt-nix.flakeModule
  ];

  perSystem = {pkgs, ...}: let
    # nixos-26.05's verible doesn't build on Darwin: its Bazel dependencies
    # no longer match their hash there. This is the fix from nixpkgs master
    # (NixOS/nixpkgs#541557), which 26.05 lacks; drop it once nixos-26.05
    # has the backport (NixOS/nixpkgs#575419). Hydra doesn't build this
    # variant, so Macs compile it themselves.
    verible =
      if pkgs.stdenv.hostPlatform.isDarwin
      then
        pkgs.verible.override {
          buildBazelPackage = args:
            pkgs.buildBazelPackage (args
              // {
                env = args.env // {NIX_CFLAGS_COMPILE = "-mmacos-version-min=10.15";};
                fetchAttrs =
                  args.fetchAttrs
                  // {
                    preInstall =
                      args.fetchAttrs.preInstall
                      + ''
                        find $bazelOut/external/abseil-cpp~ -type f -name BUILD.bazel -exec sed -i -e 's/"layering_check",//g' {} \;
                      '';
                    hash = "sha256-XGDsePwK70cdF9tgtykezlJdbGnnwNSbeZlpM67PhPc=";
                  };
              });
        }
      else pkgs.verible;
  in {
    treefmt = {
      projectRootFile = "flake.nix";

      programs = {
        alejandra.enable = true;
        deadnix.enable = true;
        statix.enable = true;
        taplo.enable = true;
        ormolu.enable = true;
        mdformat = {
          enable = true;
          # GitHub-flavoured Markdown: plain mdformat would mangle tables.
          plugins = ps: [ps.mdformat-gfm];
        };
        ruff-check.enable = true;
        ruff-format.enable = true;
        shellcheck.enable = true;
        shfmt.enable = true;
        yamlfmt.enable = true;
      };

      # treefmt-nix has no Tcl formatter of its own.
      settings.formatter.tclfmt = {
        command = "${pkgs.tclint}/bin/tclfmt";
        options = ["--in-place"];
        # Libero's PDC and SDC constraint files are Tcl too.
        includes = ["*.pdc" "*.sdc" "*.tcl"];
      };

      # Nor a Verilog one.
      settings.formatter.verible = {
        command = "${verible}/bin/verible-verilog-format";
        options = ["--inplace"];
        includes = ["*.v"];
      };

      # Files without a formatter, and test fixtures that must stay byte
      # for byte as they are.
      settings.global.excludes = [
        "*.golden"
        "*.lic"
        "*.png"
        ".gitignore"
        "LICENSES/*"
        "flake.lock"
      ];
    };
  };
}
