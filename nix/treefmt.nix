# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# `nix fmt` and `checks.treefmt`. Every file type in the repository gets a
# formatter here in the same commit that adds the first file of that type.
{inputs, ...}: {
  imports = [
    inputs.treefmt-nix.flakeModule
  ];

  perSystem = {pkgs, ...}: {
    treefmt = {
      projectRootFile = "flake.nix";

      programs = {
        alejandra.enable = true;
        deadnix.enable = true;
        statix.enable = true;
        taplo.enable = true;
        mdformat = {
          enable = true;
          # GitHub-flavoured Markdown: plain mdformat would mangle tables.
          plugins = ps: [ps.mdformat-gfm];
        };
        ruff-check.enable = true;
        ruff-format.enable = true;
        shellcheck.enable = true;
        shfmt.enable = true;
      };

      # treefmt-nix has no Tcl formatter of its own.
      settings.formatter.tclfmt = {
        command = "${pkgs.tclint}/bin/tclfmt";
        options = ["--in-place"];
        includes = ["*.tcl"];
      };

      # Files without a formatter, and test fixtures that must stay byte
      # for byte as they are.
      settings.global.excludes = [
        "*.golden"
        "*.lic"
        ".gitignore"
        "LICENSES/*"
        "flake.lock"
      ];
    };
  };
}
