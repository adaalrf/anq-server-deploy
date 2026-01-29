```nix
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.exampleservice;
  installDir = "/srv/exampleservice";
  serverDir = "${installDir}/server";
  serverBinary = "${serverDir}/example-server";
  serverConfigPath = "${serverDir}/config.json";
  serverConfigFilePath =
    if cfg.serverConfigFile == null
    then ""
    else cfg.serverConfigFile;

  startScript = pkgs.writeShellScript "exampleservice-start" ''
    set -euo pipefail
    if [ ! -x "${serverBinary}" ]; then
      echo "Example server binary not found at ${serverBinary}" >&2
      exit 1
    fi

    exec "${serverBinary}" ${cfg.extraArgs}
  '';

  unit = {
    description = "Example dedicated server";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "exampleservice";
      Group = "exampleservice";
      WorkingDirectory = installDir;
      ExecStart = "${startScript}";
      Restart = "on-failure";
      RestartSec = 10;
      LimitNOFILE = 1048576;
      UMask = "0027";
      Environment = ["HOME=${installDir}"];
    };
  };

  configOptions = {
    enable = lib.mkEnableOption "Example dedicated server";

    serverConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a config file used verbatim.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Additional arguments passed to the server binary.";
    };
  };
in {
  options.services.exampleservice = configOptions;

  config = lib.mkIf cfg.enable {
    users.users.exampleservice = {
      isSystemUser = true;
      group = "exampleservice";
      home = installDir;
      createHome = true;
    };

    users.groups.exampleservice = {};

    systemd.services.exampleservice = unit;
  };
}
```
