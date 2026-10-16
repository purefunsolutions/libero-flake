# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# services.libero-license: the FlexLM license server for Microchip Libero
# SoC. The license file stays outside the Nix store: it is loaded as a
# systemd credential and rewritten at every start (SERVER host and port,
# vendor daemon paths and ports; the signed lines are kept as they are).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.libero-license;

  rewriteArgs =
    [
      "--server-host"
      cfg.hostName
      "--server-port"
      (toString cfg.port)
    ]
    ++ lib.concatMap (name: ["--daemon" "${name}=${cfg.package.daemonDir}/${name}"])
    cfg.package.daemons
    ++ lib.concatLists (lib.mapAttrsToList (name: port: ["--daemon-port" "${name}=${toString port}"])
      cfg.vendorDaemonPorts);
in {
  options.services.libero-license = {
    enable = lib.mkEnableOption "the FlexLM license server for Microchip Libero SoC";

    package = lib.mkPackageOption pkgs "libero-license-daemons" {};

    licenseFile = lib.mkOption {
      type = lib.types.externalPath;
      example = "/var/lib/secrets/libero-license.dat";
      description = ''
        The license file as Microchip emailed it. Read by systemd at every
        start, so it never enters the Nix store; it may be readable by root
        only.
      '';
    };

    hostName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = ''
        Host name or IP address for the license's SERVER line. lmgrd hands
        it to clients, which use it for their further connections, so it
        must resolve for them; an IP address of this host avoids depending
        on DNS.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1702;
      description = "TCP port of lmgrd.";
    };

    vendorDaemonPorts = lib.mkOption {
      type = lib.types.attrsOf lib.types.port;
      default = {
        actlmgrd = 1703;
        snpslmd = 1704;
        saltd = 1705;
      };
      description = ''
        Fixed TCP ports for the vendor daemons, so that a firewall can
        allow them. Without one, FlexLM picks a random port. Daemons that
        are not in the license are ignored.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the license server's ports on all interfaces. To open them on
        one interface only, use
        `networking.firewall.interfaces.<name>.allowedTCPPorts = config.services.libero-license.ports;`
      '';
    };

    ports = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      readOnly = true;
      default = [cfg.port] ++ lib.attrValues cfg.vendorDaemonPorts;
      defaultText = lib.literalExpression "[ port ] ++ attrValues vendorDaemonPorts";
      description = "All TCP ports the license server listens on.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra command line arguments for lmgrd.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.allUnique cfg.ports;
        message = "services.libero-license: the lmgrd and vendor daemon ports must differ.";
      }
    ];

    users.users.libero-license = {
      isSystemUser = true;
      group = "libero-license";
    };
    users.groups.libero-license = {};

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall cfg.ports;

    # FlexLM keeps its lock files in /usr/tmp/.flexlm. Many distributions
    # link /usr/tmp to /var/tmp; with PrivateTmp, that is the service's own.
    systemd.tmpfiles.rules = ["L /usr/tmp - - - - /var/tmp"];

    systemd.services.libero-license = {
      description = "FlexLM license server for Microchip Libero SoC";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];

      # lmgrd and the vendor daemons exit unless the SERVER line names this
      # host, and an IP address only does when the host name resolves to it
      # (NixOS resolves it to 127.0.0.2). The SERVER line comes from
      # hostName, so skip that check.
      environment.FLEXLM_ANYHOSTNAME = "1";

      preStart = ''
        ${lib.getExe pkgs.flexlm-license-rewrite} ${lib.escapeShellArgs rewriteArgs} \
          -o "$RUNTIME_DIRECTORY/license.dat" "$CREDENTIALS_DIRECTORY/license"
      '';
      # -z: stay in the foreground and log to the journal.
      script = ''
        exec ${lib.getExe' cfg.package "lmgrd"} -z -c "$RUNTIME_DIRECTORY/license.dat" ${lib.escapeShellArgs cfg.extraFlags}
      '';

      serviceConfig = {
        User = "libero-license";
        Group = "libero-license";
        LoadCredential = "license:${cfg.licenseFile}";
        RuntimeDirectory = "libero-license";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = "%t/libero-license";
        UMask = "0077";
        Restart = "on-failure";

        # No PrivateNetwork: the host ID is the MAC address of a physical
        # network interface.
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateUsers = true;
        DevicePolicy = "closed";
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];
        LockPersonality = true;
        RemoveIPC = true;
        CapabilityBoundingSet = "";
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service"];
        SystemCallErrorNumber = "EPERM";
      };
    };
  };
}
