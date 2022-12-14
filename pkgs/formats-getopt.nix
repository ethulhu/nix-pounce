# SPDX-FileCopyrightText: 2022 Ethel Morgan
#
# SPDX-License-Identifier: MIT

{ lib, pkgs }:
let
  inherit (builtins) concatStringsSep filter isList typeOf;
  inherit (lib) mapAttrsToList;
  inherit (lib.types) attrsOf bool int oneOf str;
  inherit (pkgs) writeText;

  configFile = settings:
    let
      formatKV = key: value:
        {
          bool = if value then key else "";
          int = "${key} = ${toString value}";
          string = if value != "" then "${key} = ${value}" else "";
        }.${typeOf value};
    in concatStringsSep "\n"
    (filter (line: line != "") (mapAttrsToList formatKV settings));

in { }: {
  type = attrsOf (oneOf [ bool int str ]);

  generate = name: value: writeText name (configFile value);
}
