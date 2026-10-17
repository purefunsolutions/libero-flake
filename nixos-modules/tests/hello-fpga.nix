# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Evaluates hardware.hello-fpga and builds the system's udev rules with it.
{
  lib,
  runCommand,
  nixosSystem,
  system,
  module,
}: let
  inherit
    (nixosSystem {
      modules = [
        module
        {
          nixpkgs.hostPlatform = system;
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          system.stateVersion = "26.05";
          hardware.hello-fpga.enable = true;
        }
      ];
    })
    config
    ;
  rules = config.environment.etc."udev/rules.d".source;
in
  assert lib.elem config.hardware.hello-fpga.package config.services.udev.packages;
    runCommand "nixos-hello-fpga" {} ''
      grep -q 'SYMLINK+="hello-fpga"' ${rules}/70-hello-fpga.rules
      touch $out
    ''
