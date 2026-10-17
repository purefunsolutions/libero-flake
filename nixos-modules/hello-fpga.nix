# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# hardware.hello-fpga: udev rules for the Microchip Hello FPGA kit's USB
# serial port (pkgs/hello-fpga-udev-rules).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.hello-fpga;
in {
  options.hardware.hello-fpga = {
    enable = lib.mkEnableOption "udev rules for the Microchip Hello FPGA kit's USB serial port";

    package = lib.mkPackageOption pkgs "hello-fpga-udev-rules" {};
  };

  config = lib.mkIf cfg.enable {
    # A udev package, not services.udev.extraRules: those go into
    # 99-local.rules, after 73-seat-late.rules has applied uaccess.
    services.udev.packages = [cfg.package];
  };
}
