{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.vrising;
  installDir = "/srv/vrising";
  serverDir = "${installDir}/server";
  steamAppId = "1829350";
  serverBinary = "${serverDir}/VRisingServer.exe";
  dataDir = "${serverDir}/save-data";
  logsDir = "${serverDir}/logs";
  serverConfigPath = "${serverDir}/save-data/Settings/ServerHostSettings.json";
  serverConfigFilePath = if cfg.serverConfigFile == null then "" else cfg.serverConfigFile;
  runtimeSteamAppId = cfg.runtimeSteamAppId;

  updateScript = pkgs.writeShellScript "vrising-update" ''
    set -euo pipefail
    mkdir -p "${installDir}" "${serverDir}"
    steamcmd \
      +@sSteamCmdForcePlatformType windows \
      +force_install_dir "${serverDir}" \
      +login anonymous \
      +app_update ${steamAppId} validate \
      +quit

    steamcmd \
      +@sSteamCmdForcePlatformType windows \
      +login anonymous \
      +download_depot 1007 1004 \
      +quit

    depot_dir="${installDir}/.local/share/Steam/linux32/steamapps/content/app_1007/depot_1004"
    if [ -d "''${depot_dir}" ]; then
      mkdir -p "${serverDir}/VRisingServer_Data/Plugins/x86_64"
      for dll in "''${depot_dir}"/*.dll; do
        [ -f "''${dll}" ] || continue
        install -m 0750 "''${dll}" "${serverDir}/$(basename "''${dll}")"
        install -m 0750 "''${dll}" "${serverDir}/VRisingServer_Data/Plugins/x86_64/$(basename "''${dll}")"
      done
    fi
  '';

  configWriter = pkgs.writeShellScript "vrising-config" ''
    set -euo pipefail
    if [ -n "${serverConfigFilePath}" ] && [ -f "${serverConfigFilePath}" ]; then
      mkdir -p "$(dirname "${serverConfigPath}")"
      install -m 0640 "${serverConfigFilePath}" "${serverConfigPath}"
    else
      if [ -n "${serverConfigFilePath}" ]; then
        echo "Config file not found at ${serverConfigFilePath}, skipping copy." >&2
      fi
    fi
  '';

  startScript = pkgs.writeShellScript "vrising-start" ''
    set -euo pipefail
    if [ ! -f "${serverBinary}" ]; then
      echo "V Rising server binary not found at ${serverBinary}" >&2
      exit 1
    fi

    for dll in steamclient64.dll; do
      if [ ! -f "${serverDir}/''${dll}" ]; then
        echo "Missing Steamworks DLL: ${serverDir}/''${dll}" >&2
        exit 1
      fi
    done

    plugin_dir="${serverDir}/VRisingServer_Data/Plugins/x86_64"
    mkdir -p "''${plugin_dir}"
    if [ ! -f "${serverDir}/steam_api64.dll" ]; then
      if [ ! -f "''${plugin_dir}/steam_api64.dll" ]; then
        echo "steam_api64.dll not found under ''${plugin_dir}" >&2
        exit 1
      fi
      install -m 0750 "''${plugin_dir}/steam_api64.dll" "${serverDir}/steam_api64.dll"
    fi
    if [ ! -f "''${plugin_dir}/steam_api64.dll" ]; then
      install -m 0750 "${serverDir}/steam_api64.dll" "''${plugin_dir}/steam_api64.dll"
    fi

    # Ensure Steamworks can find the dedicated server App ID.
    echo "${runtimeSteamAppId}" > "${serverDir}/steam_appid.txt"
    echo "${runtimeSteamAppId}" > "${serverDir}/VRisingServer_Data/Plugins/x86_64/steam_appid.txt"

    # Keep appid files readable by the service user.
    chown vrising:vrising "${serverDir}/steam_appid.txt" "${serverDir}/VRisingServer_Data/Plugins/x86_64/steam_appid.txt"

    mkdir -p "${dataDir}" "${logsDir}"
    ${pkgs.xorg.xvfb}/bin/Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
    xvfb_pid=$!
    trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
    export DISPLAY=:99

    exec ${pkgs.wine64}/bin/wine64 "${serverBinary}" -persistentDataPath "${dataDir}" -logFile "${logsDir}/VRisingServer.log" ${cfg.extraArgs}
  '';

  cpuQuota = "${toString (cfg.cpuCores * 100)}%";

  unit = {
    description = "V Rising dedicated server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "vrising";
      Group = "vrising";
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
      Environment = [
        "HOME=${installDir}"
        "SteamAppId=${runtimeSteamAppId}"
        "SteamGameId=${runtimeSteamAppId}"
        "WINEDLLOVERRIDES=steam_api64,steamclient64,steamclient=n,b"
      ]
      ++ lib.optionals (!cfg.wineDebug) [ "WINEDEBUG=-all" ];
    };
  };

  configOptions = {
    enable = lib.mkEnableOption "V Rising dedicated server";

    serverConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a ServerHostSettings.json file used verbatim.";
    };

    runtimeSteamAppId = lib.mkOption {
      type = lib.types.str;
      default = "1604030";
      description = "Steam App ID used at runtime.";
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
  options.services.vrising = configOptions;

  config = lib.mkIf cfg.enable {
    users.users.vrising = {
      isSystemUser = true;
      group = "vrising";
      home = installDir;
      createHome = true;
    };

    users.groups.vrising = { };

    systemd.tmpfiles.rules = [
      "d ${installDir} 0750 vrising vrising -"
      "d ${serverDir} 0750 vrising vrising -"
    ];

    environment.systemPackages = [ pkgs.steamcmd ];

    systemd.services.vrising = unit // {
      path = [
        pkgs.steamcmd
        pkgs.wine64
        pkgs.wine64Packages.staging
        pkgs.winePackages.staging
        pkgs.xorg.xvfb
        pkgs.samba
      ];
    };
  };
}
