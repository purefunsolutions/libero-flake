# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# The Libero SoC full (offline) installer for Linux. Downloading it needs a
# free Microchip account, hence requireFile. The hash is the sha256sum
# Microchip publishes next to the download.
{requireFile}: let
  version = "2026.1";
  name = "libero_soc_${version}_offline_lin.zip";
  downloads = "https://www.microchip.com/en-us/products/fpgas-and-plds/fpga-and-soc-design-tools/fpga-software-downloads";
in {
  inherit version;
  # The component archives in the zip are named <prefix><component>.7z.
  componentPrefix = "${version}.0.17";
  installer = requireFile {
    inherit name;
    hash = "sha256-vhST/4rlWCWAh9nCaFr8vJLzVDhsypQFO3ATDmmP8CE=";
    url = downloads;
    message = ''
      Libero SoC ${version} needs a manual download (free Microchip account,
      about 19 GB):

        1. Sign in at microchip.com and download "Libero SoC Design Suite
           Version ${version} Full Installer" for Linux (${name}) from
           ${downloads}
        2. Add it to the Nix store:
             nix-store --add-fixed sha256 ${name}

      Keep a copy outside the store: garbage collection removes it once
      nothing refers to it.
    '';
  };
}
