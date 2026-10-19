# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Libero SoC's installation tree, extracted from the offline installer.
# The installer zip holds the vendor's Qt installer and one 7z archive per
# component; the Libero_SoC archive is the finished installation tree
# (Designer, Synplify_Pro, Identify, QuestaSim_Pro, ModelSim_Pro), so it
# is extracted directly and no installer runs in the build.
# Output: $out/opt/microchip/Libero_SoC.
{
  lib,
  stdenvNoCC,
  callPackage,
  unzip,
  p7zip,
  installer ? (callPackage ./sources.nix {}).installer,
  # The Identify debugger (3 GB) is left out unless asked for; synthesis,
  # place and route and FlashPro Express don't need it. The simulators are
  # packages of their own (simulator.nix).
  withIdentify ? false,
}: let
  sources = callPackage ./sources.nix {};
  excluded =
    ["Libero_SoC/QuestaSim_Pro" "Libero_SoC/ModelSim_Pro"]
    ++ lib.optional (!withIdentify) "Libero_SoC/Identify";
in
  stdenvNoCC.mkDerivation {
    pname = "libero-unwrapped";
    inherit (sources) version;
    src = installer;

    nativeBuildInputs = [unzip p7zip];
    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      unzip -q $src '*/${sources.componentPrefix}libero.soc.7z' -d installer
      mkdir -p $out/opt/microchip
      7z x -y -bd -o$out/opt/microchip \
        ${lib.escapeShellArgs (map (dir: "-x!${dir}") excluded)} \
        installer/*/${sources.componentPrefix}libero.soc.7z >/dev/null
      rm -r installer
      test -x $out/opt/microchip/Libero_SoC/Designer/bin64/libero_bin
      runHook postInstall
    '';

    # Used unmodified, inside the FHS environment of package.nix.
    dontFixup = true;

    meta = {
      description = "Microchip Libero SoC FPGA design suite, unwrapped";
      homepage = "https://www.microchip.com/en-us/products/fpgas-and-plds/fpga-and-soc-design-tools/fpga/libero-software-later-versions";
      license = lib.licenses.unfree;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      platforms = ["x86_64-linux"];
    };
  }
