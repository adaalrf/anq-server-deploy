{ pkgs, module }:
let
  fixtureGame = pkgs.writeShellScript "fixture-game" ''
    set -euo pipefail
    case "$ANQ_GAME" in
      palworld) save="$ANQ_ROOT/server/Pal/Saved/SaveGames/world" ;;
      enshrouded) save="$ANQ_ROOT/server/savegame/world" ;;
      vrising) save="$ANQ_ROOT/data/Saves/world" ;;
    esac
    mkdir -p "$(dirname "$save")"
    if [ ! -f "$save" ]; then echo fictional-save > "$save"; fi
    trap 'exit 0' INT TERM
    while true; do ${pkgs.coreutils}/bin/sleep 1; done
  '';
  fakeSteam = pkgs.writeShellApplication {
    name = "steamcmd";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      if [ -e "$HOME/fail-fetch" ]; then exit 1; fi
      target=
      while [ "$#" -gt 0 ]; do
        if [ "$1" = +force_install_dir ]; then target=$2; break; fi
        shift
      done
      test -n "$target"
      mkdir -p "$target"
      for executable in PalServer.sh enshrouded_server.exe VRisingServer.exe; do
        ln -sf ${fixtureGame} "$target/$executable"
      done
    '';
  };
  direct = name: pkgs.writeShellScriptBin name ''exec "$@"'';
  fakeDisplay = pkgs.writeShellScriptBin "xvfb-run" ''
    shift
    shift
    shift
    exec "$@"
  '';
in
pkgs.testers.runNixOSTest {
  name = "anq-games-lifecycle";
  requiredFeatures.kvm = false;
  nodes.machine = { lib, ... }: {
    imports = [ module ];
    virtualisation.memorySize = 768;
    virtualisation.cores = 2;
    services.anqGames = {
      steamcmdPackage = fakeSteam;
      steamRunPackage = direct "steam-run";
      winePackage = direct "wine";
      xvfbPackage = fakeDisplay;
      palworld = {
        enable = true;
        settingsFile = "/etc/fixture-palworld.ini";
      };
      enshrouded = {
        enable = true;
        settingsFile = "/etc/fixture-enshrouded.json";
      };
      vrising = {
        enable = true;
        settingsFile = "/etc/fixture-vrising.json";
      };
    };
    environment.etc = {
      "fixture-palworld.ini".text =
        "[/Script/Pal.PalGameWorldSettings]\nOptionSettings=(ServerName=\"Fictional fixture\")\n";
      "fixture-enshrouded.json".text = builtins.toJSON {
        name = "Fictional fixture";
        queryPort = 15637;
      };
      "fixture-vrising.json".text = builtins.toJSON {
        Name = "Fictional fixture";
        Port = 9876;
        QueryPort = 9877;
      };
    };
    # No accidental retry loop in an intentional failure test.
    systemd.services.anq-game-palworld.serviceConfig.Restart = lib.mkForce "no";
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    for game in ["palworld", "enshrouded", "vrising"]:
        machine.succeed(f"game-ops update {game}")
        machine.succeed(f"systemctl start anq-game-{game}")
        machine.wait_for_unit(f"anq-game-{game}.service")
        machine.succeed(f"test $(stat -c %U /var/lib/anq-games/{game}) = anq-{game}")
        paths = {"palworld": "server/Pal/Saved/SaveGames/world", "enshrouded": "server/savegame/world", "vrising": "data/Saves/world"}
        machine.wait_until_succeeds(f"test -f /var/lib/anq-games/{game}/{paths[game]}")
        machine.succeed(f"game-ops backup {game}")
    machine.wait_until_succeeds("test -f /var/lib/anq-games/palworld/server/Pal/Saved/SaveGames/world")
    machine.succeed("game-ops backup palworld")
    machine.wait_for_unit("anq-game-palworld.service")
    machine.succeed("archive=$(find /var/backup/anq-games -name 'palworld-*.tar.gz' | head -n1); game-ops restore-check palworld $archive /var/tmp/restored-palworld")
    machine.succeed("grep fictional-save /var/tmp/restored-palworld/server/Pal/Saved/SaveGames/world")
    machine.succeed("test $(stat -c %a /var/lib/anq-games/palworld/server/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini) = 600")
    machine.fail("su -s /bin/sh nobody -c 'cat /var/lib/anq-games/palworld/server/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini'")
    machine.succeed("game-ops update palworld")
    machine.wait_for_unit("anq-game-palworld.service")
    machine.succeed("touch /var/lib/anq-games/palworld/home/fail-fetch")
    machine.fail("game-ops update palworld")
    machine.fail("systemctl is-active --quiet anq-game-palworld.service")
    machine.succeed("grep fictional-save /var/lib/anq-games/palworld/server/Pal/Saved/SaveGames/world")
    machine.succeed("rm /var/lib/anq-games/palworld/home/fail-fetch; game-ops update palworld")
    machine.fail("systemctl is-active --quiet anq-game-palworld.service")
    machine.succeed("systemctl start anq-game-palworld")
    machine.wait_for_unit("anq-game-palworld.service")
  '';
}
