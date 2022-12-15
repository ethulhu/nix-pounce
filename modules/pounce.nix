# SPDX-FileCopyrightText: 2022 Ethel Morgan
#
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib) mapAttrs' mdDoc mkEnableOption mkIf mkOption;
  inherit (lib.types) attrsOf listOf oneOf path port str submodule;
  inherit (pkgs.formats) getopt;

  description = "Pounce IRC bouncer";
  cfg = config.services.pounce;

  settingsFormat = getopt { };

  mkService = name: opts:
    let
      unit = "pounce-network-${name}";

      # DynamicUser implies PrivateTmp.
      expandedConfig = "/tmp/${unit}.conf";
      unexpandedConfig = settingsFormat.generate "${unit}.conf" opts.settings;
    in {
      name = unit;
      value = mkIf opts.enable {
        description = "${description} for ${name}";
        wants = [ "network.target" ];
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = rec {
          DynamicUser = true;
          SupplementaryGroups = opts.extraGroups;
          ExecStartPre =
            "${pkgs.envsubst}/bin/envsubst -i ${unexpandedConfig} -o ${expandedConfig}";
          ExecStart = "${pkgs.pounce}/bin/pounce ${expandedConfig}";
          StateDirectory = unit;
          Environment = [ "HOME=/var/lib/${StateDirectory}" ];
          EnvironmentFile = opts.environmentFiles;
          Restart = "always";
          RestartSec = opts.reconnectDelay;
        };
      };
    };

in {
  options.services.pounce = {
    enable = mkEnableOption description;

    networks = mkOption {
      type = attrsOf (submodule {
        options = {
          enable = mkEnableOption "this instance of Pounce" // {
            default = true;
          };

          extraGroups = mkOption {
            type = listOf str;
            description =
              "SupplementaryGroups for the systemd DynamicUser (e.g. for accessing certificates).";
            default = [ ];
          };

          environmentFiles = mkOption {
            type = listOf path;
            default = [ ];
            example = [ "/root/pounce-password.env" ];
            description =
              "Files to load systemd Unit environment variables from.";
          };

          reconnectDelay = mkOption rec {
            type = str;
            default = "260 seconds";
            description = mdDoc ''
              How long to wait before restarting after disconnect, as a `systemd.time(5)` span.
              The default (${default}) is appropriate for most networks' timeouts.
            '';
          };

          settings = mkOption {
            type = submodule { freeformType = settingsFormat.type; };
            description = mdDoc ''
              Options as described in `pounce(1)`.
              Substitutions can be made for environment variables,
              such as those defined in `environmentFiles`.
            '';
            default = { };
            example = {
              local-pass = "$POUNCE_PASS_HASHED";
              local-port = 6969;
              no-sts = true;
              sasl-plain = "nicknick:$IRC_PASS";
            };
          };
        };
      });
      default = { };
      description = "Pounce runs a separate instance per IRC server.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services = mapAttrs' mkService config.services.pounce.networks;
  };
}
