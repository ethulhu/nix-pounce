<!--
SPDX-FileCopyrightText: 2022 Ethel Morgan

SPDX-License-Identifier: MIT
-->

# Nix flake for Pounce IRC bouncer & associated tools.

This flake provides NixOS modules to run [Pounce](https://git.causal.agency/pounce/about/), an IRC bouncer, and [Litterbox](https://git.causal.agency/litterbox/about/), an IRC logger.

## Flakes and branches

This flake will use branches to allow users to protect against API changes. The intial branch is `api-v1`, which will be updated until there are breaking changes to the API. When that happens, new development will switch to a branch `api-v2`, and so on.

## Example

The following will:

- Run an instance of Pounce to connect to [Libera](https://libera.chat).
- Run an instance of Litterbox to provide logging for Libera.
- Grant a user access to that Litterbox log.
- Share a LetsEncrypt certificate between NGINX and Pounce.
- Use [agenix](https://github.com/ryantm/agenix) to manage secrets.

In `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";

    nix-pounce = {
      url = "github:ethulhu/nix-pounce/api-v1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-pounce, agenix }@inputs: {
    nixosConfigurations.bouncer = nixpkgs.lib.nixosSystem {
      modules = [ ... ]; # The rest of your config

      # Pass the flake inputs to nixos modules as the argument `flake`.
      specialArgs = { flake = inputs; };
    }
  };
}
```

In the config for `bouncer`:

```nix
{ config, pkgs, flake, ... }:
let
  nginx_certificate_group = "nginx_pounce";
  agenix_secrets_group = "pounce_secrets";

  domain = "irc.jimothy.horse";

in {

  # Import the nix-pounce modules.
  imports = [ flake.nix-pounce.nixosModules.default ];

  # Create a group to share the LetsEncrypt certificate between us & NGINX.
  users.groups.${nginx_certificate_group} = {
    members = [ config.services.nginx.user ];
  };

  # Set the certificate's ownership to that group.
  security.acme.certs.${domain}.group = nginx_certificate_group;

  # Setting up NGINX is an exercise left for the reader…


  # Create a group to own Pounce's secrets.
  users.groups.${agenix_secrets_group} = { };

  # Load those secrets with agenix.
  age.secrets = {
    # Contains:
    #   POUNCE_PASS=...
    #   POUNCE_PASS_HASHED=...
    pounce = {
      file = ./secrets/pounce.age;
      group = agenix_secrets_group;
      mode = "440";
    };

    # Contains:
    #   LIBERACHAT_PASS=...
    libera = {
      file = ./secrets/libera.age;
      group = agenix_secrets_group;
      mode = "440";
    };
  };

  # Open the firewall for our IRC client to connect to Pounce.
  networking.firewall.allowedTCPPorts = [
    config.services.pounce.networks.LiberaChat.settings.local-port
  ];

  # Configure Pounce with an instance for Libera.
  services.pounce = {
    enable = true;
    networks = {
      LiberaChat = {
        extraGroups = [
          agenix_secrets_group
          nginx_certificate_group
        ];
        environmentFiles = [
          config.age.secrets.pounce.path
          config.age.secrets.libera.path
        ];
        settings = rec {
          local-host = "::";
          local-port = 6060;
          local-cert =
            "${config.security.acme.certs.${domain}.directory}/cert.pem";
          local-priv =
            "${config.security.acme.certs.${domain}.directory}/key.pem";
          local-pass = "$POUNCE_PASS_HASHED";
          host = "irc.libera.chat";
          nick = "jimothy";
          sasl-plain = "${nick}:$LIBERACHAT_PASS";
        };
      };
    };
  };

  # Configure Litterbox to log from our Pounce instance.
  services.litterbox = {
    enable = true;
    networks = {
      LiberaChat = {
        extraGroups = [ agenix_secrets_group ];
        environmentFiles = [ config.age.secrets.pounce.path ];
        settings = {
          pass = "$POUNCE_PASS";
          host = domain;
          port = config.services.pounce.networks.LiberaChat.settings.local-port;
        };
      };
    };
  };

  users.users.jimothy = {
    # Add `scoop` and `unscoop` utilities for accessing the logs.
    packages = with pkgs; [ litterbox ];

    # Grant access to litterbox.db.
    extraGroups = [ config.services.litterbox.group ];
  };
}
```
