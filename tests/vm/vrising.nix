{
  pkgs,
  lib,
  nixosTest,
}:
nixosTest.makeTest {
  name = "vrising-vm";
  nodes.machine = {...}: {
    imports = [../../services/vrising-server.nix];

    nixpkgs.config.allowUnfree = true;

    services.vrising = {
      enable = true;
      cpuCores = 2;
      memoryMax = "8G";
    };

    systemd.services.vrising.serviceConfig = {
      ExecStartPre = lib.mkForce [];
      ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
      Type = lib.mkForce "oneshot";
      RemainAfterExit = lib.mkForce true;
    };
  };

  testScript = ''
    machine.wait_for_unit("vrising.service")
    machine.succeed("getent passwd vrising")
    machine.succeed("test -d /srv/vrising")
    machine.succeed("systemctl cat vrising.service | grep -q 'CPUQuota=200%'")
    machine.succeed("systemctl cat vrising.service | grep -q 'MemoryMax=8G'")
    machine.succeed("systemctl cat vrising.service | grep -q 'SteamAppId=1604030'")
  '';
}
