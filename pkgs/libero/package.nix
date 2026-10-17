# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Libero SoC in an FHS environment, with one wrapper per tool. The vendor's
# launch scripts expect FHS paths (/usr/bin/ls, libX11 in /usr/lib) and
# Libero bundles most of its libraries (Qt 5, Tcl, libstdc++, ...); the FHS
# environment provides the 74 it doesn't, found by scanning the ELF
# dependencies of Designer/bin64 and Designer/lib*.
{
  buildFHSEnv,
  callPackage,
  glibcLocales,
  symlinkJoin,
  writeShellScriptBin,
  unwrapped ? callPackage ./unwrapped.nix {},
}: let
  root = "${unwrapped}/opt/microchip/Libero_SoC";

  fhs = buildFHSEnv {
    name = "libero-fhs";
    targetPkgs = pkgs:
      with pkgs; [
        # Libraries Libero does not bundle.
        alsa-lib
        atk
        expat
        fontconfig
        freetype
        gdk-pixbuf
        glib
        gtk2
        krb5
        libGL
        libice
        libnsl
        libpulseaudio
        libsm
        libuuid
        libx11
        libxau
        libxcb
        libxcomposite
        libxcrypt-legacy
        libxcursor
        libxdamage
        libxext
        libxfixes
        libxi
        libxinerama
        libxkbcommon
        libxml2_13
        libxrandr
        libxrender
        libxslt
        libxtst
        libxxf86vm
        nspr
        nss
        pango
        pciutils
        sqlite
        systemdLibs
        xcbutilimage
        xcbutilkeysyms
        # Used by the launch scripts.
        coreutils
        gawk
        gnugrep
        gnused
        which
      ];
    # A few tools are 32-bit: the zcat that the programming data
    # verification (cdlver) runs, and the FlashPro tools in Designer/binfp.
    multiArch = true;
    multiPkgs = pkgs: [pkgs.zlib];
    # FlexLM keeps its lock files in /usr/tmp; the FHS /usr is read-only.
    extraBuildCommands = ''
      ln -s /var/tmp $out/usr/tmp
    '';
    # The launch scripts set LC_ALL=en_US.UTF-8.
    profile = ''
      export LOCALE_ARCHIVE=${glibcLocales}/lib/locale/locale-archive
    '';
    # Run the wrappers' arguments directly instead of a shell.
    runScript = "";
  };

  tool = name: path:
    writeShellScriptBin name ''
      # Libero's tool profiles run Synplify Pro by its bare name.
      export PATH=${root}/Synplify_Pro/bin''${PATH:+:$PATH}
      exec ${fhs}/bin/libero-fhs ${root}/${path} "$@"
    '';
in
  symlinkJoin {
    name = "libero-${unwrapped.version}";
    paths = [
      (tool "libero" "Designer/bin64/libero")
      (tool "FPExpress" "Designer/bin64/FPExpress")
    ];
    passthru = {inherit unwrapped fhs;};
    meta =
      unwrapped.meta
      // {
        description = "Microchip Libero SoC FPGA design suite";
        mainProgram = "libero";
      };
  }
