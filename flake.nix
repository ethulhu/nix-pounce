# SPDX-FileCopyrightText: 2022 Ethel Morgan
#
# SPDX-License-Identifier: MIT

{
  description = "Pounce IRC bouncer & associated tools.";

  inputs = { nixpkgs.url = "nixpkgs"; };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      derivations = pkgs: {
        litterbox = pkgs.callPackage ./pkgs/litterbox { };
      };

    in {
      overlays.default = final: _prev: derivations final;

      packages =
        forAllSystems (system: derivations nixpkgs.legacyPackages.${system});

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default =
            pkgs.mkShell { packages = with pkgs; [ nixfmt pre-commit reuse ]; };
        });

      checks = self.packages;
    };
}
