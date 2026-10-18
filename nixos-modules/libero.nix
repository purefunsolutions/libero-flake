# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# programs.libero: Libero SoC for the users of this machine, pointed at a
# license server.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.libero;
in {
  options.programs.libero = {
    enable = lib.mkEnableOption "Microchip Libero SoC";

    package = lib.mkPackageOption pkgs "libero" {};

    licenseServer = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "1702@licenses.example.org";
      description = ''
        The FlexLM license server for Libero, as `port@host`; several are
        separated by colons. Sets `LM_LICENSE_FILE` for all users.
      '';
    };

    synplifyLicenseServer = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = cfg.licenseServer;
      defaultText = lib.literalExpression "config.programs.libero.licenseServer";
      description = ''
        The license server for Synplify, which Libero runs for synthesis.
        Sets `SNPSLMD_LICENSE_FILE` and its older name
        `SYNPLCTYD_LICENSE_FILE`.
      '';
    };

    simulatorLicenseServer = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = cfg.licenseServer;
      defaultText = lib.literalExpression "config.programs.libero.licenseServer";
      description = ''
        The license server for the simulators, QuestaSim and ModelSim
        (`libero-questasim`, `libero-modelsim`), which read only
        `SALT_LICENSE_SERVER`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];
    environment.sessionVariables =
      lib.optionalAttrs (cfg.licenseServer != null) {
        LM_LICENSE_FILE = cfg.licenseServer;
      }
      // lib.optionalAttrs (cfg.synplifyLicenseServer != null) {
        SNPSLMD_LICENSE_FILE = cfg.synplifyLicenseServer;
        SYNPLCTYD_LICENSE_FILE = cfg.synplifyLicenseServer;
      }
      // lib.optionalAttrs (cfg.simulatorLicenseServer != null) {
        SALT_LICENSE_SERVER = cfg.simulatorLicenseServer;
      };
  };
}
