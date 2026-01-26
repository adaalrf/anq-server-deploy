rec {
  # Service output name (matches nixosConfigurations.<service> in flake.nix).
  service = "enshrouded"; # or "palworld", "vrising"

  deploy = {
    # Hostname or IP of the target machine.
    host = "anq-server-deploy";

    # SSH user used when host does not include user@.
    user = "username";

    # Remote directory where the repo is synced.
    remoteRepoDir = "/srv/enshrouded-repo";

    # Build on the target instead of locally.
    buildOnRemote = false;

    # install = destructive (nixos-anywhere), switch = non-destructive.
    mode = "switch";

    # Suppress installer logs.
    quiet = false;
  };

  ssh = {
    # Auto-accept new SSH host keys (less secure).
    acceptNewHostKeys = false;
  };

  # Require explicit confirmation for destructive installs.
  installer = {
    confirmInstall = false;
  };

  # Local backup settings for /srv data (optional).
  backup = {
    enable = false;
    localDir = "./backups/${service}";
    archiveKeep = 10;
  };

  serviceDefaults = {
    # Enable Wine debug logging for Windows-based servers.
    wineDebug = false;
  };

  # Per-service settings (single source of truth).
  services = {
    enshrouded = {
      serviceName = "enshrouded";
      backupPaths = [
        "/srv/enshrouded/server/savegame"
        "/srv/enshrouded/server/logs"
      ];
      tcpPorts = [
        15636
        15637
        15638
      ];
      udpPorts = [
        15636
        15637
        15638
      ];
      configFile =
        if builtins.pathExists ./server-configs/enshrouded_server.json
        then ./server-configs/enshrouded_server.json
        else null;
      useWineDebug = true;
    };
    palworld = {
      serviceName = "palworld";
      backupPaths = [
        "/srv/palworld/server/Pal/Saved/SaveGames"
        "/srv/palworld/server/Pal/Saved/Config/LinuxServer"
        "/srv/palworld/server/Pal/Saved/Logs"
      ];
      tcpPorts = [];
      udpPorts = [8211];
      configFile =
        if builtins.pathExists ./server-configs/palworld_server_settings.ini
        then ./server-configs/palworld_server_settings.ini
        else null;
      useWineDebug = false;
    };
    vrising = {
      serviceName = "vrising";
      backupPaths = [
        "/srv/vrising/server/save-data"
        "/srv/vrising/server/logs"
      ];
      tcpPorts = [];
      udpPorts = [
        9876
        9877
      ];
      configFile =
        if builtins.pathExists ./server-configs/vrising_server_settings.json
        then ./server-configs/vrising_server_settings.json
        else null;
      useWineDebug = true;
    };
  };
}
