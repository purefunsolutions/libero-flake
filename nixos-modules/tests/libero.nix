# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Evaluates programs.libero with a stub package (the real one needs the
# Microchip download).
{
  lib,
  writeShellScriptBin,
  runCommand,
  nixosSystem,
  system,
  module,
}: let
  stub = writeShellScriptBin "libero" "";

  inherit
    (nixosSystem {
      modules = [
        module
        {
          nixpkgs.hostPlatform = system;
          boot.isContainer = true;
          system.stateVersion = "26.05";
          programs.libero = {
            enable = true;
            package = stub;
            licenseServer = "1702@licenses.example.org";
          };
        }
      ];
    })
    config
    ;
  variables = config.environment.sessionVariables;
in
  assert variables.LM_LICENSE_FILE == "1702@licenses.example.org";
  assert variables.SNPSLMD_LICENSE_FILE == "1702@licenses.example.org";
  assert variables.SYNPLCTYD_LICENSE_FILE == "1702@licenses.example.org";
  assert variables.SALT_LICENSE_SERVER == "1702@licenses.example.org";
  assert lib.elem stub config.environment.systemPackages;
    runCommand "nixos-libero" {} "touch $out"
