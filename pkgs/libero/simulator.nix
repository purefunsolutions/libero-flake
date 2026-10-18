# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# One of the HDL simulators in Libero SoC's installation tree, QuestaSim
# or ModelSim in their Microchip editions, extracted from the offline
# installer on its own: designs that never simulate don't need it. The
# Libero license covers both, through its Siemens vendor daemons (saltd,
# mgcld). They run inside libero's FHS environment.
# Output: $out/opt/microchip/Libero_SoC/<dir>.
{
  lib,
  stdenvNoCC,
  callPackage,
  unzip,
  p7zip,
  installer ? (callPackage ./sources.nix {}).installer,
  pname,
  # The simulator's directory in the Libero_SoC tree.
  dir,
  # Its executables (vsim, vlog, ...) in there. QuestaSim's bin/ holds
  # links to its platform-picking launcher, vco; vco doesn't know
  # ModelSim's 32-bit linuxacoem/, which therefore runs directly.
  binDir,
  # Its name in Libero's simulation tool profiles (Designer/data/libero.def).
  profileTool,
  description,
}: let
  sources = callPackage ./sources.nix {};
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    inherit pname;
    inherit (sources) version;
    src = installer;

    nativeBuildInputs = [unzip p7zip];
    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      unzip -q $src '*/${sources.componentPrefix}libero.soc.7z' -d installer
      mkdir -p $out/opt/microchip
      7z x -y -bd -o$out/opt/microchip \
        installer/*/${sources.componentPrefix}libero.soc.7z 'Libero_SoC/${dir}' >/dev/null
      rm -r installer
      test -x $out/opt/microchip/Libero_SoC/${dir}/${binDir}/vsim
      runHook postInstall
    '';

    # Used unmodified, inside libero's FHS environment.
    dontFixup = true;

    passthru = {
      root = "${finalAttrs.finalPackage}/opt/microchip/Libero_SoC/${dir}";
      bin = "${finalAttrs.finalPackage}/opt/microchip/Libero_SoC/${dir}/${binDir}";
      inherit profileTool;
    };

    meta = {
      inherit description;
      homepage = "https://www.microchip.com/en-us/products/fpgas-and-plds/fpga-and-soc-design-tools/fpga/libero-software-later-versions";
      license = lib.licenses.unfree;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      platforms = ["x86_64-linux"];
    };
  })
