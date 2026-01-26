{
  pkgs,
  lib,
  nixosTest,
}:
nixosTest.makeTest {
  name = "enshrouded-vm";
  nodes.machine = {...}: {
    imports = [../../services/enshrouded-server.nix];

    nixpkgs.config.allowUnfree = true;

    services.enshrouded = {
      enable = true;
      cpuCores = 2;
      memoryMax = "8G";
    };

    systemd.services.enshrouded.serviceConfig = {
      ExecStartPre = lib.mkForce [];
      ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
      Type = lib.mkForce "oneshot";
      RemainAfterExit = lib.mkForce true;
    };
  };

  testScript = ''
    machine.wait_for_unit("enshrouded.service")
    machine.succeed("getent passwd enshrouded")
    machine.succeed("test -d /srv/enshrouded")
    machine.succeed("systemctl cat enshrouded.service | grep -q 'CPUQuota=200%'")
    machine.succeed("systemctl cat enshrouded.service | grep -q 'MemoryMax=8G'")
  '';
}
