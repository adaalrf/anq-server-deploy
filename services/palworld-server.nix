{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.palworld;
  installDir = "/srv/palworld";
  serverDir = "${installDir}/server";
  steamAppId = "2394010";
  serverBinary = "${serverDir}/PalServer.sh";
  serverConfigPath = "${serverDir}/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini";
  serverConfigFilePath =
    if cfg.serverConfigFile == null
    then ""
    else cfg.serverConfigFile;

  updateScript = pkgs.writeShellScript "palworld-update" ''
    set -euo pipefail
    mkdir -p "${serverDir}"
    steamcmd \
      +force_install_dir "${serverDir}" \
      +login anonymous \
      +app_update ${steamAppId} validate \
      +quit
  '';

  configWriter = pkgs.writeShellScript "palworld-config" ''
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

  startScript = pkgs.writeShellScript "palworld-start" ''
    set -euo pipefail
    if [ ! -x "${serverBinary}" ]; then
      echo "Palworld server binary not found at ${serverBinary}" >&2
      exit 1
    fi

    exec "${serverBinary}" ${cfg.extraArgs}
  '';

  cpuQuota = "${toString (cfg.cpuCores * 100)}%";

  unit = {
    description = "Palworld dedicated server";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "palworld";
      Group = "palworld";
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
      Environment = ["HOME=${installDir}"];
    };
  };

  configOptions = {
    enable = lib.mkEnableOption "Palworld dedicated server";

    serverConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a PalWorldSettings.ini file used verbatim.";
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
      default = "-useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS";
      description = "Additional arguments passed to the server binary.";
    };
  };
in {
  options.services.palworld = configOptions;

  config = lib.mkIf cfg.enable {
    users.users.palworld = {
      isSystemUser = true;
      group = "palworld";
      home = installDir;
      createHome = true;
    };

    users.groups.palworld = {};

    environment.systemPackages = [pkgs.steamcmd];

    systemd.services.palworld =
      unit
      // {
        path = [pkgs.steamcmd];
      };
  };
}
