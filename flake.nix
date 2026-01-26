{
  description = "[NixOS] anq-server-deploy";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      nixosTest = import (nixpkgs + "/nixos/lib/testing-python.nix") {
        inherit system pkgs;
      };

      baseModules = [
        disko.nixosModules.disko
        ./disko.nix
        ./configuration.nix
      ];

      mkService =
        serviceName: module:
        nixpkgs.lib.nixosSystem {
          system = system;
          modules = baseModules ++ [ module ];
          specialArgs = {
            inherit serviceName;
          };
        };

      healthScript = pkgs.writeShellApplication {
        name = "health-check";
        runtimeInputs = [
          self
          pkgs.openssh
          pkgs.iproute2
          pkgs.gnugrep
          pkgs.systemd
          pkgs.nix
          pkgs.jq
        ];
        text = builtins.readFile ./checks/health-check.sh;
      };
      healthApp = pkgs.writeShellApplication {
        name = "health";
        runtimeInputs = [ healthScript ];
        text = ''
          exec ${healthScript}/bin/health-check ${./options.nix} ${./tests}
        '';
      };
    in
    {
      checks.${system} = {
        enshrouded-vm = import ./tests/vm/enshrouded.nix {
          inherit pkgs nixosTest;
          lib = nixpkgs.lib;
        };
        palworld-vm = import ./tests/vm/palworld.nix {
          inherit pkgs nixosTest;
          lib = nixpkgs.lib;
        };
        vrising-vm = import ./tests/vm/vrising.nix {
          inherit pkgs nixosTest;
          lib = nixpkgs.lib;
        };
      };

      apps.${system} = {
        install = import ./installer.nix { pkgs = pkgs; };
        health = {
          type = "app";
          program = "${healthApp}/bin/health";
          meta = {
            description = "Run live health checks over SSH.";
          };
        };
      };

      nixosConfigurations = {
        enshrouded = mkService "enshrouded" ./services/enshrouded-server.nix;
        palworld = mkService "palworld" ./services/palworld-server.nix;
        vrising = mkService "vrising" ./services/vrising-server.nix;
      };
    };
}
