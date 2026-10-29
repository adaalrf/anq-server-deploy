{
  pkgs,
  nixpkgs,
  module,
}:
let
  lib = pkgs.lib;
  names = [
    "palworld"
    "enshrouded"
    "vrising"
  ];
  evaluate =
    options:
    (nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        module
        {
          nixpkgs.pkgs = pkgs;
          boot.isContainer = true;
          system.stateVersion = "26.05";
          services.anqGames = options;
        }
      ];
    }).config;
  settings = lib.genAttrs names (name: {
    enable = true;
    settingsFile = "/run/private/${name}";
  });
  config = evaluate settings;
  rejected = evaluate {
    palworld = {
      enable = true;
      settingsFile = "/nix/store/unsafe-settings";
    };
  };
  good = builtins.all (a: a.assertion) config.assertions;
  report = lib.genAttrs names (
    name:
    let
      unit = config.systemd.services."anq-game-${name}";
    in
    {
      user = unit.serviceConfig.User;
      autoStart = unit.wantedBy;
      credentials = unit.serviceConfig.LoadCredential;
      stateDirectory = unit.serviceConfig.StateDirectory;
      noNewPrivileges = unit.serviceConfig.NoNewPrivileges;
      privateTmp = unit.serviceConfig.PrivateTmp;
      protectSystem = unit.serviceConfig.ProtectSystem;
      usesOwnDisplay =
        if name == "palworld" then
          true
        else
          lib.hasInfix "anq-game-start-${name}" unit.serviceConfig.ExecStart;
    }
  );
in
assert lib.assertMsg good "Example game configurations must satisfy NixOS assertions";
assert config.networking.firewall.allowedUDPPorts == [ ];
assert config.networking.firewall.allowedTCPPorts == [ ];
assert builtins.any (a: !a.assertion) rejected.assertions;
assert builtins.all (
  name: config.systemd.services."anq-game-${name}".serviceConfig.User == "anq-${name}"
) names;
assert builtins.all (name: config.systemd.services."anq-game-${name}".wantedBy == [ ]) names;
pkgs.writeText "anq-game-module-evaluation.json" (builtins.toJSON report)
