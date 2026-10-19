# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Libero SoC's IP cores (CCCs, oscillators, DirectCores and so on): the
# MegaVault from the offline installer, every public core as of the
# release, so builds never download cores.
# Outputs: out, with $out/share/libero/vault for Libero's vault location;
# doc, the cores' documentation (user guides, handbooks), which the core
# configurators link to on the web. Libero unpacks parts of a core into the
# vault the first time a design uses it, so it needs a writable copy
# (mkLiberoProject's runner makes one).
{
  lib,
  stdenvNoCC,
  callPackage,
  unzip,
  p7zip,
  installer ? (callPackage ./sources.nix {}).installer,
}: let
  sources = callPackage ./sources.nix {};
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "libero-megavault";
    inherit (sources) version;
    src = installer;

    outputs = ["out" "doc"];

    nativeBuildInputs = [unzip p7zip];
    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      unzip -q $src '*/${sources.componentPrefix}megavault.7z' -d installer
      7z x -y -bd -oextracted installer/*/${sources.componentPrefix}megavault.7z >/dev/null
      mkdir -p $out/share/libero $doc/share/doc
      mv extracted/MegaVault/Libero_SoC_v${finalAttrs.version}_MegaVault $out/share/libero/vault
      mv extracted/MegaVault/Libero_CoreDocs $doc/share/doc/libero-megavault
      rm -r installer extracted
      test -f $out/share/libero/vault/index.xml
      runHook postInstall
    '';

    # Used unmodified; the fixup phase would also move documentation around.
    dontFixup = true;

    passthru.vault = "${finalAttrs.finalPackage}/share/libero/vault";

    meta = {
      description = "IP cores of the Microchip Libero SoC FPGA design suite";
      homepage = "https://www.microchip.com/en-us/products/fpgas-and-plds/fpga-and-soc-design-tools/fpga/libero-software-later-versions";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux"];
    };
  })
