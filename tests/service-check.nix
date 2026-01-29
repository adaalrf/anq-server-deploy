{
  pkgs,
  lib,
  nixosTest,
  serviceName,
  serviceModulePath,
}:

let
  service =
    if serviceName == null then lib.throw "service-check requires `serviceName`" else serviceName;
  _ = builtins.pathExists serviceModulePath "Missing service module for '${service}'";
  scriptBody = ''
    machine.wait_for_unit("${service}.service")
    machine.succeed("test -d /srv/${service}/server")
    machine.succeed("systemctl is-active ${service}.service")
  '';
in
nixosTest.makeTest {
  name = "${service}-smoke";
  nodes.machine =
    { ... }:
    {
      imports = [ serviceModulePath ];

      nixpkgs.config.allowUnfree = true;

      services.${service} = {
        enable = true;
        cpuCores = 1;
        memoryMax = "1G";
      };

      systemd.services.${service}.serviceConfig = lib.mkForce {
        ExecStart = "${pkgs.coreutils}/bin/true";
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

  testScript = scriptBody;
}
