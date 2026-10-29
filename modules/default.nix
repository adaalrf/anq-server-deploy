{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.anqGames;
  games = import ../lib/games.nix;
  names = builtins.attrNames games;
  enabled = lib.filter (name: cfg.${name}.enable) names;
  rootFor = name: "/var/lib/anq-games/${name}";
  unitFor = name: "anq-game-${name}";
  fetchFor = name: "anq-game-fetch-${name}";
  ops = import ../lib/ops-package.nix { inherit pkgs; };
  environmentFor = name: {
    ANQ_GAME = name;
    ANQ_ROOT = rootFor name;
    ANQ_APP_ID = games.${name}.appId;
    ANQ_EXECUTABLE = games.${name}.executable;
    ANQ_SETTINGS = games.${name}.settings;
    ANQ_WINDOWS = if games.${name}.windows then "true" else "false";
    HOME = "${rootFor name}/home";
    WINEPREFIX = "${rootFor name}/wine";
    WINEDEBUG = "-all";
  };
  prepare = pkgs.writeShellApplication {
    name = "anq-game-prepare";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = builtins.readFile ../scripts/prepare.sh;
  };
  fetch = pkgs.writeShellApplication {
    name = "anq-game-fetch";
    runtimeInputs = [
      pkgs.coreutils
      cfg.steamcmdPackage
    ];
    text = builtins.readFile ../scripts/fetch.sh;
  };
  launch =
    name:
    let
      game = games.${name};
      root = rootFor name;
      args = lib.escapeShellArgs cfg.${name}.extraArgs;
    in
    pkgs.writeShellApplication {
      name = "anq-game-start-${name}";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        cd ${lib.escapeShellArg "${root}/server"}
        ${
          if game.windows then
            ''
              exec ${cfg.xvfbPackage}/bin/xvfb-run -a -s '-screen 0 1024x768x24 -nolisten tcp' \
                ${cfg.winePackage}/bin/wine ${lib.escapeShellArg "${root}/server/${game.executable}"} \
                ${
                  lib.optionalString (name == "vrising")
                    "-persistentDataPath ${lib.escapeShellArg "${root}/data"} -logFile ${lib.escapeShellArg "${root}/logs/VRisingServer.log"}"
                } ${args}
            ''
          else
            ''
              exec ${cfg.steamRunPackage}/bin/steam-run ${lib.escapeShellArg "${root}/server/${game.executable}"} ${args}
            ''
        }
      '';
    };
  common = name: {
    User = "anq-${name}";
    Group = "anq-${name}";
    StateDirectory = "anq-games/${name}";
    StateDirectoryMode = "0700";
    UMask = "0077";
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ReadWritePaths = [ (rootFor name) ];
    CapabilityBoundingSet = "";
    RestrictSUIDSGID = true;
    TimeoutStopSec = 120;
  };
  gameOptions = name: {
    enable = lib.mkEnableOption "the ${name} dedicated service";
    settingsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Absolute host path to private game settings. Use a string, not a Nix path containing secrets.";
    };
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start at boot after an explicit installation/update.";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the explicitly configured game ports.";
    };
    udpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = games.${name}.udpPorts;
      description = "UDP ports matching the runtime settings.";
    };
    tcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Additional explicitly required TCP ports; RCON is not opened by default.";
    };
    cpuCores = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "CPU quota in core equivalents.";
    };
    memoryMax = lib.mkOption {
      type = lib.types.strMatching "[1-9][0-9]*[MG]";
      default = "8G";
      description = "systemd memory ceiling; size for your actual workload.";
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional literal argv entries; not shell code.";
    };
  };
in
{
  options.services.anqGames = {
    steamcmdPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.steamcmd;
      description = "SteamCMD package.";
    };
    steamRunPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.steam-run;
      description = "FHS launcher for the native Linux game.";
    };
    winePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.wine64;
      description = "Wine package exposing bin/wine for Windows game servers.";
    };
    xvfbPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.xvfb-run;
      description = "Per-service automatic X display launcher.";
    };
  }
  // lib.genAttrs names gameOptions;

  config = lib.mkIf (enabled != [ ]) {
    assertions = map (name: {
      assertion =
        cfg.${name}.settingsFile != null
        && lib.hasPrefix "/" cfg.${name}.settingsFile
        && !(lib.hasPrefix "/nix/store/" cfg.${name}.settingsFile);
      message = "anqGames.${name}.settingsFile must be an absolute runtime file outside the Nix store.";
    }) enabled;
    users.groups = lib.genAttrs (map (name: "anq-${name}") enabled) (_: { });
    users.users = lib.listToAttrs (
      map (
        name:
        lib.nameValuePair "anq-${name}" {
          isSystemUser = true;
          group = "anq-${name}";
          home = "${rootFor name}/home";
        }
      ) enabled
    );
    environment.systemPackages = [ ops ];
    environment.etc = lib.listToAttrs (
      map (
        name:
        lib.nameValuePair "anq-games/${name}.json" {
          text = builtins.toJSON {
            game = name;
            stateDirectory = rootFor name;
            unit = "${unitFor name}.service";
            fetchUnit = "${fetchFor name}.service";
            backupDirectory = "/var/backup/anq-games";
            inherit (games.${name}) backupPaths;
            inherit (cfg.${name}) udpPorts tcpPorts;
          };
        }
      ) enabled
    );
    networking.firewall.allowedUDPPorts = lib.concatMap (
      name: lib.optionals cfg.${name}.openFirewall cfg.${name}.udpPorts
    ) enabled;
    networking.firewall.allowedTCPPorts = lib.concatMap (
      name: lib.optionals cfg.${name}.openFirewall cfg.${name}.tcpPorts
    ) enabled;
    systemd.services = lib.mkMerge (
      map (name: {
        ${unitFor name} = {
          description = "Anq ${name} dedicated game service";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = lib.optional cfg.${name}.autoStart "multi-user.target";
          environment = environmentFor name;
          serviceConfig = common name // {
            Type = "simple";
            WorkingDirectory = rootFor name;
            LoadCredential = [
              "settings:${
                if cfg.${name}.settingsFile == null then
                  "/run/anq-games-settings-missing"
                else
                  cfg.${name}.settingsFile
              }"
            ];
            ExecStartPre = "${prepare}/bin/anq-game-prepare";
            ExecStart = "${launch name}/bin/anq-game-start-${name}";
            Restart = "on-failure";
            RestartSec = 10;
            KillSignal = "SIGINT";
            CPUQuota = "${toString (cfg.${name}.cpuCores * 100)}%";
            MemoryMax = cfg.${name}.memoryMax;
            LimitNOFILE = 1048576;
          };
        };
        ${fetchFor name} = {
          description = "Explicit SteamCMD install/update for ${name}";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          environment = environmentFor name;
          serviceConfig = common name // {
            Type = "oneshot";
            ExecStart = "${fetch}/bin/anq-game-fetch";
            TimeoutStartSec = 3600;
          };
        };
      }) enabled
    );
  };
}
