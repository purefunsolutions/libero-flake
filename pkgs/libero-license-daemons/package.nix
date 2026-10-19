# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Microchip's FlexLM license daemons for Libero SoC: lmgrd, lmutil and its
# aliases, and the vendor daemons actlmgrd (Libero), snpslmd (Synopsys
# Synplify) and saltd (Siemens QuestaSim). The download needs a Microchip
# account, hence requireFile. The binaries are patched to run on NixOS, so
# what this builds must never be redistributed.
{
  lib,
  stdenv,
  requireFile,
  autoPatchelfHook,
  xz,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "libero-license-daemons";
  version = "11.19.6.0";

  src = requireFile {
    name = "Linux_Licensing_Daemon_${finalAttrs.version}_64-bit.tar.gz";
    hash = "sha256-FObHTNuOSpzRjlehNIkvH7Kjl114/IpaEJFhmNUoZ+0=";
    url = "https://ww1.microchip.com/downloads/secure/aemDocuments/documents/FPGA/media-content/FPGA/daemons/Linux_Licensing_Daemon_${finalAttrs.version}_64-bit.tar.gz";
    message = ''
      The Libero SoC license daemons need a manual download with a free
      Microchip account:

        1. Sign in at microchip.com and download
           https://ww1.microchip.com/downloads/secure/aemDocuments/documents/FPGA/media-content/FPGA/daemons/Linux_Licensing_Daemon_${finalAttrs.version}_64-bit.tar.gz
           (also on the Daemons tab of
           https://www.microchip.com/en-us/products/fpgas-and-plds/fpga-and-soc-design-tools/fpga/licensing)
        2. Add it to the Nix store:
             nix-store --add-fixed sha256 Linux_Licensing_Daemon_${finalAttrs.version}_64-bit.tar.gz
    '';
  };

  # The tarball has no top-level directory.
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tar -xzf $src -C source
    cd source
    runHook postUnpack
  '';

  nativeBuildInputs = [autoPatchelfHook];
  # libgcc_s and libstdc++, and liblzma for snpslmd.
  buildInputs = [
    stdenv.cc.cc.lib
    xz
  ];

  dontConfigure = true;
  dontBuild = true;
  # Shipped stripped already.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin lmgrd lmutil lmdown lmhostid lmreread lmstat lmver
    install -Dm755 -t $out/libexec/libero-license actlmgrd saltd snpslmd
    runHook postInstall
  '';

  passthru = {
    # Where the vendor daemons are, and which ones a license may name.
    daemonDir = "${finalAttrs.finalPackage}/libexec/libero-license";
    daemons = ["actlmgrd" "saltd" "snpslmd"];
  };

  meta = {
    description = "FlexLM license daemons for Microchip Libero SoC";
    homepage = "https://www.microchip.com/en-us/products/fpgas-and-plds/fpga-and-soc-design-tools/fpga/licensing";
    license = lib.licenses.unfree;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    mainProgram = "lmgrd";
    platforms = ["x86_64-linux"];
  };
})
