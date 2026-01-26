{
  pkgs,
  lib,
  nixosTest,
}:
nixosTest.makeTest {
  name = "palworld-vm";
  nodes.machine =
    { ... }:
    {
      imports = [ ../../services/palworld-server.nix ];

      nixpkgs.config.allowUnfree = true;

      services.palworld = {
        enable = true;
        cpuCores = 2;
        memoryMax = "8G";
      };

      systemd.services.palworld.serviceConfig = {
        ExecStartPre = lib.mkForce [ ];
        ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
        Type = lib.mkForce "oneshot";
        RemainAfterExit = lib.mkForce true;
      };
    };

  testScript = ''
    machine.wait_for_unit("palworld.service")
    machine.succeed("getent passwd palworld")
    machine.succeed("test -d /srv/palworld")
    machine.succeed("systemctl cat palworld.service | grep -q 'CPUQuota=200%'")
    machine.succeed("systemctl cat palworld.service | grep -q 'MemoryMax=8G'")
  '';
}
