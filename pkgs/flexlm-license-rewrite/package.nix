# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
{
  lib,
  stdenvNoCC,
  python3,
  runCommand,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "flexlm-license-rewrite";
  version = "0.1.0";

  src = ./flexlm-license-rewrite.py;
  dontUnpack = true;

  # For patchShebangs.
  buildInputs = [python3];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/flexlm-license-rewrite
    runHook postInstall
  '';

  passthru.tests.golden =
    runCommand "flexlm-license-rewrite-golden" {
      nativeBuildInputs = [finalAttrs.finalPackage];
    } ''
      args=(
        --server-host licserv.example --server-port 27000
        --daemon actlmgrd=/opt/test/actlmgrd
        --daemon saltd=/opt/test/saltd
        --daemon snpslmd=/opt/test/snpslmd
        --daemon-port actlmgrd=27001
        --daemon-port snpslmd=27002
        --daemon-port saltd=27003
      )
      flexlm-license-rewrite "''${args[@]}" ${./tests/license.lic} >out.lic
      diff -u ${./tests/expected.lic} out.lic

      # CRLF input gives the same LF output.
      sed 's/$/\r/' ${./tests/license.lic} >crlf.lic
      flexlm-license-rewrite "''${args[@]}" crlf.lic >crlf-out.lic
      diff -u ${./tests/expected.lic} crlf-out.lic

      # Refused: a vendor daemon without a path, and redundant servers.
      if flexlm-license-rewrite --daemon actlmgrd=/x ${./tests/license.lic}; then
        echo "error: accepted VENDOR lines without paths" >&2
        exit 1
      fi
      { cat ${./tests/license.lic}; echo "SERVER other 0123456789AC 1702"; } >two.lic
      if flexlm-license-rewrite "''${args[@]}" two.lic; then
        echo "error: accepted two SERVER lines" >&2
        exit 1
      fi

      touch $out
    '';

  meta = {
    description = "Rewrite the user-editable lines of a FlexLM license file";
    license = lib.licenses.mit;
    mainProgram = "flexlm-license-rewrite";
    platforms = lib.platforms.all;
  };
})
