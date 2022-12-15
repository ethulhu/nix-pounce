# SPDX-FileCopyrightText: 2022 Ethel Morgan
#
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    escapeShellArgs filterAttrs mapAttrs' mdDoc mkEnableOption mkIf mkMerge
    mkOption optional;
  inherit (lib.types) attrsOf int listOf nullOr oneOf path port str submodule;
  inherit (pkgs.formats) getopt;

  description = "Pounce IRC bouncer";
  calico = {
    description = "dispatches cat";
    unitName = "pounce-calico";
  };
  notify = {
    description = "notifications for Pounce";
    suffix = "notify";
  };
  palaver = {
    description = "Palaver push notifications for Pounce";
    suffix = "palaver";
  };

  cfg = config.services.pounce;

  settingsFormat = getopt { };

  unitName = name: "pounce-network-${name}";

  networkService = name: opts:
    let
      unit = unitName name;

      expandedConfig = "/tmp/${unit}.conf";
      unexpandedConfig = settingsFormat.generate "${unit}.conf" opts.settings;
    in {
      name = unit;
      value = {
        description = "${description} for ${name}";
        after = [ "${calico.unitName}.service" "network.target" ];
        requisite = [ "${calico.unitName}.service" ];
        wants = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = rec {
          User = cfg.user;
          PrivateTmp = true;
          SupplementaryGroups = opts.extraGroups;
          ExecStartPre =
            "${pkgs.envsubst}/bin/envsubst -i ${unexpandedConfig} -o ${expandedConfig}";
          ExecStart = "${pkgs.pounce}/bin/pounce ${expandedConfig}";
          StateDirectory = unit;
          Environment = [ "HOME=/var/lib/${StateDirectory}" ];
          EnvironmentFile = opts.environmentFiles;
          Restart = "always";
          RestartSec = opts.reconnectDelay;
          RestartPreventExitStatus = [
            73 # CANTCREAT
          ];
        };
      };
    };

  botService = { name, opts, meta, ExecStart }:
    let
      pounce = unitName name;
      unit = "${pounce}-${meta.suffix}";
    in {
      name = unit;
      value = {
        description = "${meta.description} for ${name}";
        wants = [ "network.target" ];
        after = [ "${pounce}.service" "network.target" ];
        requisite = [ "${pounce}.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = rec {
          inherit ExecStart;
          DynamicUser = true;
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

  notifyService = name: opts:
    botService {
      inherit name opts;
      meta = notify;
      ExecStart =
        "${pkgs.pounce}/bin/pounce-notify -p ${toString opts.notify.port} ${
          escapeShellArgs opts.notify.extraFlags
        } ${opts.notify.host} ${opts.notify.command}";
    };

  palaverService = name: opts:
    botService {
      inherit name opts;
      meta = palaver;
      ExecStart =
        "${pkgs.pounce}/bin/pounce-palaver -p ${toString opts.palaver.port} ${
          escapeShellArgs opts.palaver.extraFlags
        } ${opts.palaver.host}";
    };

in {
  options.services.pounce = {
    enable = mkEnableOption description;

    user = mkOption {
      type = str;
      default = "pounce";
      description = ''
        The user to run Calico and Pounce instances under.
        Notify & Palaver bots do not use this, and run under DynamicUser.
      '';
    };

    group = mkOption {
      type = str;
      default = "pounce";
      description = ''
        The group to run Calico and Pounce instances under.
        Notify & Palaver bots do not use this, and run under DynamicUser.
      '';
    };

    calico = {
      enable = mkEnableOption calico.description;

      port = mkOption {
        type = port;
        default = 6697;
        description = "Port to bind to.";
      };

      host = mkOption {
        type = str;
        description = "Hostname to dispatch.";
        example = "irc.jimothy.horse";
      };

      timeoutMilliseconds = mkOption {
        type = int;
        default = 1000;
        description =
          "The timeout after which a connection will be closed if it has not sent the ClientHello message.";
      };

      socketsDirectory = mkOption {
        type = path;
        default = "/run/${calico.unitName}";
        readOnly = true;
        description = "The directory containing Pounce sockets.";
      };
    };

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
                type = nullOr port;
                default = if cfg.calico.enable then null else 6697;
                description =
                  "Port to bind to. Disabled by default if Calico is enabled.";
              };
              options.local-path = mkOption {
                type = nullOr path;
                default = if cfg.calico.enable then
                  cfg.calico.socketsDirectory
                else
                  null;
                description = mdDoc ''
                  Path to sockets directory for `calico(1)`.
                  Disabled by default if Calico is not enabled.
                '';
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
              default = config.settings.local-host;
              description = "Host of the Pounce instance.";
              example = "irc.jimothy.horse";
            };
            port = mkOption {
              type = port;
              default = if cfg.calico.enable then
                cfg.calico.port
              else
                config.settings.local-port;
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
              default = config.settings.local-host;
              description = "Host of the Pounce instance.";
              example = "irc.jimothy.horse";
            };
            port = mkOption {
              type = port;
              default = if cfg.calico.enable then
                cfg.calico.port
              else
                config.settings.local-port;
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

  in mkMerge [
    (mkIf cfg.enable {
      users.users.${cfg.user} = {
        inherit (cfg) group;
        isSystemUser = true;
      };
      users.groups.${cfg.group} = { };

      systemd.services = networkServices // notifyServices // palaverServices;
    })
    (mkIf (cfg.enable && cfg.calico.enable) {
      systemd.services.${calico.unitName} = {
        inherit (calico) description;
        wants = [ "network.target" ];
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = cfg.user;
          PrivateTmp = true;
          ExecStart = "${pkgs.pounce}/bin/calico -H ${cfg.calico.host} -P ${
              toString cfg.calico.port
            } -t ${
              toString cfg.calico.timeoutMilliseconds
            } ${cfg.calico.socketsDirectory}";
          RuntimeDirectory = calico.unitName;
        };
      };
    })
  ];
}
