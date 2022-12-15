# SPDX-FileCopyrightText: 2022 Ethel Morgan
#
# SPDX-License-Identifier: MIT

{
  description = "Pounce IRC bouncer & associated tools.";

  inputs = { nixpkgs.url = "nixpkgs"; };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      derivations = pkgs: {
        litterbox = pkgs.callPackage ./pkgs/litterbox { };
        pounce = pkgs.callPackage ./pkgs/pounce { };
      };

    in {
      overlays.default = final: prev:
        derivations final // {
          formats = prev.formats // {
            getopt = final.callPackage ./pkgs/formats-getopt.nix { };
          };
        };

      nixosModules = {
        litterbox = {
          imports = [ ./modules/litterbox.nix ];
          nixpkgs.overlays = [ self.overlays.default ];
        };

        pounce = {
          imports = [ ./modules/pounce.nix ];
          nixpkgs.overlays = [ self.overlays.default ];
        };

        default = {
          imports = [ self.nixosModules.pounce self.nixosModules.litterbox ];
        };
      };

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
