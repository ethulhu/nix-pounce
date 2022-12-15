# SPDX-FileCopyrightText: 2022 Ethel Morgan
#
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    escapeShellArgs filterAttrs mapAttrs' mdDoc mkEnableOption mkIf mkOption;
  inherit (lib.types) attrsOf listOf oneOf path port str submodule;
  inherit (pkgs.formats) getopt;

  description = "Pounce IRC bouncer";
  palaver.description = "Palaver push notifications for Pounce";
  notify.description = "notifications for Pounce";
  cfg = config.services.pounce;

  settingsFormat = getopt { };

  unitName = name: "pounce-network-${name}";

  networkService = name: opts:
    let
      unit = unitName name;

      # DynamicUser implies PrivateTmp.
      expandedConfig = "/tmp/${unit}.conf";
      unexpandedConfig = settingsFormat.generate "${unit}.conf" opts.settings;
    in {
      name = unit;
      value = {
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

  notifyService = name: opts:
    let
      pounceUnit = unitName name;
      unit = "${pounceUnit}-notify";
      opts' = opts.notify;
    in {
      name = unit;
      value = {
        description = "${notify.description} for ${name}";
        wants = [ "network.target" ];
        after = [ "${pounceUnit}.service" "network.target" ];
        requires = [ "${pounceUnit}.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = rec {
          DynamicUser = true;
          ExecStart =
            "${pkgs.pounce}/bin/pounce-notify -p ${toString opts'.port} ${
              escapeShellArgs opts'.extraFlags
            } ${opts'.host} ${opts'.command}";
          StateDirectory = unit;
          Environment = [ "HOME=/var/lib/${StateDirectory}" ];
          EnvironmentFile = opts.environmentFiles;
          Restart = "always";
        };
        preStart = ''
          set -eu

          mkdir -p $HOME/.local/share/pounce/
        '';
      };
    };

  palaverService = name: opts:
    let
      pounceUnit = unitName name;
      unit = "${pounceUnit}-palaver";
      opts' = opts.palaver;
    in {
      name = unit;
      value = {
        description = "${palaver.description} for ${name}";
        wants = [ "network.target" ];
        after = [ "${pounceUnit}.service" "network.target" ];
        requires = [ "${pounceUnit}.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = rec {
          DynamicUser = true;
          ExecStart =
            "${pkgs.pounce}/bin/pounce-palaver -p ${toString opts'.port} ${
              escapeShellArgs opts'.extraFlags
            } ${opts'.host}";
          StateDirectory = unit;
          Environment = [ "HOME=/var/lib/${StateDirectory}" ];
          EnvironmentFile = opts.environmentFiles;
          Restart = "always";
        };
        preStart = ''
          set -eu

          mkdir -p $HOME/.local/share/pounce/
        '';
      };
    };

in {
  options.services.pounce = {
    enable = mkEnableOption description;

    networks = mkOption {
      type = attrsOf (submodule ({ config, ... }: {
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
            type = submodule {
              freeformType = settingsFormat.type;
              options.local-port = mkOption {
                type = port;
                default = 6697;
                description = "Port to bind to.";
              };
            };
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

          notify = {
            enable = mkEnableOption notify.description;
            host = mkOption {
              type = str;
              description = "Host of the Pounce instance.";
              example = "irc.jimothy.horse";
            };
            port = mkOption {
              type = port;
              default = config.settings.local-port;
              description = "Port of the Pounce instance.";
            };
            command = mkOption {
              type = oneOf [ path str ];
              description = mdDoc "Command to run, as per `pounce-notify(1)`.";
            };
            extraFlags = mkOption {
              type = listOf str;
              default = [ ];
              description =
                mdDoc "Additional flags as described in `pounce-notify(1)`.";
            };
          };

          palaver = {
            enable = mkEnableOption palaver.description;
            host = mkOption {
              type = str;
              description = "Host of the Pounce instance.";
              example = "irc.jimothy.horse";
            };
            port = mkOption {
              type = port;
              default = config.settings.local-port;
              description = "Port of the Pounce instance.";
            };
            extraFlags = mkOption {
              type = listOf str;
              default = [ ];
              description = mdDoc "Flags as described in `pounce-palaver(1)`.";
            };
          };
        };
      }));
      default = { };
      description = "Pounce runs a separate instance per IRC server.";
    };
  };

  config = let
    networkServices = mapAttrs' networkService
      (filterAttrs (_name: opts: opts.enable) cfg.networks);

    palaverServices = mapAttrs' palaverService
      (filterAttrs (_name: opts: opts.enable && opts.palaver.enable)
        cfg.networks);

    notifyServices = mapAttrs' notifyService
      (filterAttrs (_name: opts: opts.enable && opts.notify.enable)
        cfg.networks);

  in mkIf cfg.enable {
    systemd.services = networkServices // notifyServices // palaverServices;
  };
}
