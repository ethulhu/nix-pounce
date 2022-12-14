# SPDX-FileCopyrightText: 2022 Ethel Morgan
#
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib) mapAttrs' mdDoc mkEnableOption mkIf mkOption;
  inherit (lib.types) attrsOf listOf oneOf path str submodule;
  inherit (pkgs.formats) getopt;

  settingsFormat = getopt { };

  mkService = name: opts:
    let
      unit = "litterbox-network-${name}";

      expandedConfig = "/tmp/${unit}.conf";
      unexpandedConfig = settingsFormat.generate "${unit}.conf" opts.settings;
    in {
      name = unit;
      value = mkIf opts.enable {
        description = "${description} for ${name}";
        after = [ "litterbox-initdb.service" "network.target" ];
        requires = [ "litterbox-initdb.service" ];
        wants = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = cfg.user;
          PrivateTmp = true;
          SupplementaryGroups = opts.extraGroups;
          ExecStartPre =
            "${pkgs.envsubst}/bin/envsubst -i ${unexpandedConfig} -o ${expandedConfig}";
          ExecStart = "${pkgs.litterbox}/bin/litterbox ${expandedConfig}";
          EnvironmentFile = opts.environmentFiles;
        };
      };
    };

  description = "Litterbox IRC logger";
  cfg = config.services.litterbox;

in {
  options.services.litterbox = {
    enable = mkEnableOption description;

    user = mkOption {
      type = str;
      default = "litterbox";
      description = "User to own the DB and run Litterbox instances.";
    };

    group = mkOption {
      type = str;
      default = "litterbox";
      description = "Group to own the DB and run Litterbox instances.";
    };

    database = mkOption {
      type = path;
      default = "/var/lib/litterbox/litterbox.db";
    };

    networks = mkOption {
      type = attrsOf (submodule {
        options = {
          enable = mkEnableOption "this instance of Litterbox" // {
            default = true;
          };

          extraGroups = mkOption {
            type = listOf str;
            description =
              "SupplementaryGroups for the systemd Unit (e.g. for accessing certificates).";
            default = [ ];
          };

          environmentFiles = mkOption {
            type = listOf path;
            default = [ ];
            example = [ "/root/pounce-password.env" ];
            description =
              "Files to load systemd Unit environment variables from.";
          };

          settings = mkOption {
            type = submodule {
              freeformType = settingsFormat.type;
              options.database = mkOption {
                type = path;
                default = cfg.database;
              };
            };
            description = mdDoc ''
              Options as described in `litterbox(1)`.
              Substitutions can be made for environment variables,
              such as those defined in `environmentFiles`.
            '';
            default = { };
            example = {
              pass = "$POUNCE_PASS";
              port = 6969;
              private-query = true;
            };
          };
        };
      });
    };
    default = { };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      inherit description;
      inherit (cfg) group;
      isSystemUser = true;
    };
    users.groups.${cfg.group} = { };

    systemd.services = mapAttrs' mkService cfg.networks // {
      litterbox-initdb = {
        script = ''
          set -eu

          if [ ! -f ${cfg.database} ]; then
            ${pkgs.litterbox}/bin/litterbox -i -d ${cfg.database}

            chmod g+w ${cfg.database}
            chmod o-rwx ${cfg.database}
          fi
        '';
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          StateDirectory = "litterbox";
        };
      };
    };
  };
}
