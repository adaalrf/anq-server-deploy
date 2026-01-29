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
          inherit system;
          modules = baseModules ++ [ module ];
          specialArgs = {
            inherit serviceName;
          };
        };

      optionsPath =
        if builtins.pathExists ./options.nix then ./options.nix else ./examples/options.example.nix;
      opts = import optionsPath;
      selectedService = opts.service;

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
          exec ${healthScript}/bin/health-check ${optionsPath} ${./tests}
        '';
      };

      testApp = pkgs.writeShellApplication {
        name = "test";
        runtimeInputs = [ pkgs.nix ];
        text = ''
          set -euo pipefail
          nix flake check -L
        '';
      };

      lintApp = pkgs.writeShellApplication {
        name = "lint";
        runtimeInputs = [
          pkgs.alejandra
          pkgs.statix
          pkgs.shellcheck
        ];
        text = ''
          set -euo pipefail
          alejandra --check .
          statix check .
          shellcheck scripts/*.sh checks/*.sh
        '';
      };
    in
    {
      checks.${system} = {
        enshrouded-vm = import ./tests/vm/enshrouded.nix {
          inherit pkgs nixosTest;
          inherit (nixpkgs) lib;
        };
        palworld-vm = import ./tests/vm/palworld.nix {
          inherit pkgs nixosTest;
          inherit (nixpkgs) lib;
        };
        vrising-vm = import ./tests/vm/vrising.nix {
          inherit pkgs nixosTest;
          inherit (nixpkgs) lib;
        };
        service-check = import ./tests/service-check.nix {
          inherit pkgs nixosTest;
          inherit (nixpkgs) lib;
          serviceName = selectedService;
          serviceModulePath = ./services/${selectedService}-server.nix;
        };
      };

      apps.${system} = {
        install = import ./installer.nix { inherit pkgs; };
        switch = import ./switcher.nix { inherit pkgs; };
        lint = {
          type = "app";
          program = "${lintApp}/bin/lint";
          meta = {
            description = "Run local formatter and linters.";
          };
        };
        test = {
          type = "app";
          program = "${testApp}/bin/test";
          meta = {
            description = "Run nix flake check -L locally.";
          };
        };
        health = {
          type = "app";
          program = "${healthApp}/bin/health";
          meta = {
            description = "Run live health checks over SSH.";
          };
        };
      };

      devShells.${system} = {
        default = pkgs.mkShell {
          packages = [
            pkgs.alejandra
            pkgs.statix
            pkgs.shellcheck
          ];
        };
      };

      nixosConfigurations = {
        enshrouded = mkService "enshrouded" ./services/enshrouded-server.nix;
        palworld = mkService "palworld" ./services/palworld-server.nix;
        vrising = mkService "vrising" ./services/vrising-server.nix;
      };
    };
}
