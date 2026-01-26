{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.enshrouded;
  installDir = "/srv/enshrouded";
  serverDir = "${installDir}/server";
  steamAppId = "2278520";
  serverBinary = "${serverDir}/enshrouded_server.exe";
  serverConfigPath = "${serverDir}/enshrouded_server.json";
  serverConfigFilePath = if cfg.serverConfigFile == null then "" else cfg.serverConfigFile;
  serverConfigJson = builtins.toJSON {
    name = cfg.serverName;
    password = cfg.serverPassword;
    maxPlayers = cfg.maxPlayers;
    gameSettings = cfg.gameSettings;
  };

  updateScript = pkgs.writeShellScript "enshrouded-update" ''
    set -euo pipefail
    mkdir -p "${serverDir}"
    steamcmd \
      +@sSteamCmdForcePlatformType windows \
      +force_install_dir "${serverDir}" \
      +login anonymous \
      +app_update ${steamAppId} validate \
      +quit
    if [ -d "${serverDir}/EnshroudedServer" ] && [ ! -d "${serverDir}/steamapps" ]; then
      mkdir -p "${serverDir}/steamapps/common"
      mv "${serverDir}/EnshroudedServer" "${serverDir}/steamapps/common/EnshroudedServer"
    fi
  '';

  configWriter = pkgs.writeShellScript "enshrouded-config" ''
            set -euo pipefail
            mkdir -p "${serverDir}"
        if [ -n "${serverConfigFilePath}" ] && [ -f "${serverConfigFilePath}" ]; then
          install -m 0640 "${serverConfigFilePath}" "${serverConfigPath}"
        else
          if [ -n "${serverConfigFilePath}" ]; then
            echo "Config file not found at ${serverConfigFilePath}, using defaults." >&2
          fi
          cat > "${serverConfigPath}" <<'EOF'
    ${serverConfigJson}
    EOF
        fi

  '';

  startScript = pkgs.writeShellScript "enshrouded-start" ''
    set -euo pipefail
    if [ ! -f "${serverBinary}" ]; then
      echo "Enshrouded server binary not found at ${serverBinary}" >&2
      exit 1
    fi

    exec ${pkgs.wine64}/bin/wine64 "${serverBinary}" ${cfg.extraArgs}
  '';

  cpuQuota = "${toString (cfg.cpuCores * 100)}%";

  unit = {
    description = "Enshrouded dedicated server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "enshrouded";
      Group = "enshrouded";
      WorkingDirectory = installDir;
      ExecStartPre = [
        "${updateScript}"
        "${configWriter}"
      ];
      ExecStart = "${startScript}";
      Restart = "on-failure";
      RestartSec = 10;
      LimitNOFILE = 1048576;
      UMask = "0027";
      CPUQuota = cpuQuota;
      MemoryMax = cfg.memoryMax;
      Environment = [ "HOME=${installDir}" ] ++ lib.optionals (!cfg.wineDebug) [ "WINEDEBUG=-all" ];
    };
  };

  configOptions = {
    enable = lib.mkEnableOption "Enshrouded dedicated server";

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "Enshrouded NixOS";
      description = "Server display name.";
    };

    serverPassword = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Server password (empty for no password).";
    };

    maxPlayers = lib.mkOption {
      type = lib.types.int;
      default = 16;
      description = "Maximum players.";
    };

    serverConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to an enshrouded_server.json file used verbatim.";
    };

    gameSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Game settings JSON payload.";
    };

    cpuCores = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "CPU core limit for the service.";
    };

    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "8G";
      description = "Memory limit for the service.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Additional arguments passed to the server binary.";
    };

    wineDebug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Wine debug logging (set false to silence Wine).";
    };
  };

in
{
  options.services.enshrouded = configOptions;

  config = lib.mkIf cfg.enable {
    users.users.enshrouded = {
      isSystemUser = true;
      group = "enshrouded";
      home = installDir;
      createHome = true;
    };

    users.groups.enshrouded = { };

    environment.systemPackages = [ pkgs.steamcmd ];

    systemd.services.enshrouded = unit // {
      path = [
        pkgs.steamcmd
        pkgs.wine64
        pkgs.wine64Packages.staging
        pkgs.winePackages.staging
      ];
    };
  };
}
