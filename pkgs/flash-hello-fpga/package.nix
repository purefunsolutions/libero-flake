# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Programs the Microchip Hello FPGA kit: finds the kit's serial port by its
# USB ID and the .dat file, then runs `hello-fpga program`.
{
  lib,
  stdenvNoCC,
  python3,
  hello-fpga-cli,
  runCommand,
  runtimeShell,
}: let
  python = python3.withPackages (ps: [ps.pyserial]);
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "flash-hello-fpga";
    version = "0.1.0";

    src = ./flash-hello-fpga.py;
    dontUnpack = true;

    # For patchShebangs.
    buildInputs = [python];

    installPhase = ''
      runHook preInstall
      install -Dm755 $src $out/bin/flash-hello-fpga
      substituteInPlace $out/bin/flash-hello-fpga \
        --replace-fail @hello-fpga@ ${lib.getExe hello-fpga-cli}
      runHook postInstall
    '';

    # Finding the port needs a kit. This checks finding the .dat file and
    # the call of hello-fpga, with a stub that records its arguments.
    passthru.tests.args =
      runCommand "flash-hello-fpga-args" {
        nativeBuildInputs = [python];
      } ''
        ${lib.getExe finalAttrs.finalPackage} --help >/dev/null

        cat >hello-fpga <<EOF
        #!${runtimeShell}
        echo "\$*" >>$PWD/calls
        EOF
        chmod +x hello-fpga
        substitute ${finalAttrs.src} flash.py --replace-fail @hello-fpga@ $PWD/hello-fpga
        flash() { python3 flash.py --port /dev/kit "$@"; }

        mkdir -p dir out/blinky empty
        touch dir/a.dat out/blinky/blinky.dat
        flash dir/a.dat
        flash dir
        flash
        diff -u - calls <<EOF
        program --port /dev/kit dir/a.dat
        program --port /dev/kit dir/a.dat
        program --port /dev/kit out/blinky/blinky.dat
        EOF

        # Refused with argparse's exit status: two .dat files in ./out/*/,
        # none, and a missing file.
        touch out/blinky/other.dat
        for arg in "" empty missing.dat; do
          status=0
          flash $arg 2>err || status=$?
          if [ $status != 2 ]; then
            echo "error: flash '$arg' exited with $status" >&2
            cat err >&2
            exit 1
          fi
        done
        [ "$(wc -l <calls)" -eq 3 ]

        touch $out
      '';

    meta = {
      description = "Program the Microchip Hello FPGA kit with a DirectC .dat file";
      license = lib.licenses.mit;
      mainProgram = "flash-hello-fpga";
      inherit (hello-fpga-cli.meta) platforms;
    };
  })
