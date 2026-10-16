# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Evaluates services.libero-license with stub daemons (the real ones need
# the Microchip download) and checks the generated systemd unit.
{
  lib,
  stdenvNoCC,
  runCommand,
  nixosSystem,
  system,
  module,
}: let
  stub = stdenvNoCC.mkDerivation (finalAttrs: {
    name = "libero-license-daemons-stub";
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin $out/libexec/libero-license
      for tool in bin/lmgrd bin/lmutil libexec/libero-license/{actlmgrd,saltd,snpslmd}; do
        printf '#!/bin/sh\n' >$out/$tool
        chmod +x $out/$tool
      done
    '';
    passthru = {
      daemonDir = "${finalAttrs.finalPackage}/libexec/libero-license";
      daemons = ["actlmgrd" "saltd" "snpslmd"];
    };
    meta.mainProgram = "lmgrd";
  });

  eval = licenseFile:
    nixosSystem {
      modules = [
        module
        {
          nixpkgs.hostPlatform = system;
          boot.isContainer = true;
          system.stateVersion = "26.05";
          networking.hostName = "licenses";
          networking.firewall.interfaces.wg0.allowedTCPPorts = [1702];
          services.libero-license = {
            enable = true;
            package = stub;
            inherit licenseFile;
          };
        }
      ];
    };

  inherit (eval "/var/lib/secrets/libero.lic") config;
  service = config.systemd.units."libero-license.service".unit;

  # The license must never be a store path or a path literal.
  rejected = licenseFile: !(builtins.tryEval (eval licenseFile).config.services.libero-license.licenseFile).success;

  preStart = builtins.unsafeDiscardStringContext config.systemd.services.libero-license.preStart;
in
  assert config.services.libero-license.ports == [1702 1703 1705 1704];
  assert rejected "${stub}/license.dat";
  assert rejected ./libero-license.nix;
  assert lib.hasInfix "--server-host licenses --server-port 1702" preStart;
  assert lib.hasInfix "--daemon 'snpslmd=${builtins.unsafeDiscardStringContext stub}/libexec/libero-license/snpslmd'" preStart;
  assert lib.hasInfix "--daemon-port 'saltd=1705'" preStart;
  assert lib.elem "L /usr/tmp - - - - /var/tmp" config.systemd.tmpfiles.rules;
    runCommand "nixos-libero-license" {} ''
      unit=${service}/libero-license.service
      grep -qx 'LoadCredential=license:/var/lib/secrets/libero.lic' $unit
      grep -qx 'User=libero-license' $unit
      grep -qx 'RestrictNamespaces=true' $unit
      grep -qx 'Environment="FLEXLM_ANYHOSTNAME=1"' $unit
      # The host ID is the MAC of a real network interface.
      if grep -q PrivateNetwork $unit; then exit 1; fi
      touch $out
    ''
