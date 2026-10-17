# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# udev rules for the Microchip Hello FPGA kit's USB serial port, the
# MCP2221A bridge to the kit's on-board PIC32 programmer.
{
  lib,
  writeTextFile,
  runCommand,
  systemd,
}:
writeTextFile (finalAttrs: {
  name = "hello-fpga-udev-rules";
  # Before 73-seat-late.rules, which applies the uaccess tag.
  destination = "/lib/udev/rules.d/70-hello-fpga.rules";
  text = ''
    # Microchip Hello FPGA kit: the MCP2221A USB-UART bridge to the on-board
    # PIC32 programmer. It keeps Microchip's default USB ID and descriptors and
    # has no serial number, so these rules match any MCP2221A.

    # ModemManager would probe the port with AT commands, which the PIC32's
    # stateful protocol does not expect.
    ATTRS{idVendor}=="04d8", ATTRS{idProduct}=="00dd", ENV{ID_MM_DEVICE_IGNORE}="1"

    # Access for the user logged in at the machine, and a stable name.
    SUBSYSTEM=="tty", ATTRS{idVendor}=="04d8", ATTRS{idProduct}=="00dd", TAG+="uaccess", SYMLINK+="hello-fpga"
  '';

  passthru.tests.verify =
    runCommand "hello-fpga-udev-rules-verify" {
      nativeBuildInputs = [systemd];
    } ''
      udevadm verify --resolve-names=never ${finalAttrs.finalPackage}${finalAttrs.destination}
      touch $out
    '';

  meta = {
    description = "udev rules for the Microchip Hello FPGA kit's USB serial port";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
