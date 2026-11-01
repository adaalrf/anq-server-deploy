{ pkgs, module }:
let
  fixtureGame = pkgs.writeShellScript "fixture-game" ''
    set -euo pipefail
    if [ -e "$HOME/crash-game" ]; then exit 1; fi
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
      while [ -e "$HOME/hold-fetch" ]; do sleep 1; done
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
  nodes.machine = { ... }: {
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
    # Exercise an actual Restart=on-failure delay, not a mocked active state.
    machine.succeed("touch /var/lib/anq-games/palworld/home/crash-game; systemctl restart anq-game-palworld")
    machine.wait_until_succeeds("test $(systemctl show -p SubState --value anq-game-palworld) = auto-restart")
    machine.succeed("rm /var/lib/anq-games/palworld/home/crash-game; touch /var/lib/anq-games/palworld/home/hold-fetch")
    machine.succeed("systemd-run --no-block --unit=fixture-update --property=Type=oneshot /run/current-system/sw/bin/game-ops update palworld")
    machine.wait_until_succeeds("test $(systemctl show -p ActiveState --value anq-game-fetch-palworld) = activating")
    machine.fail("systemctl is-active --quiet anq-game-palworld")
    machine.succeed("systemctl start anq-game-palworld")
    machine.fail("systemctl is-active --quiet anq-game-palworld")
    machine.succeed("test -e /run/anq-games/palworld.maintenance")
    machine.succeed("rm /var/lib/anq-games/palworld/home/hold-fetch")
    machine.wait_until_succeeds("test $(systemctl show -p ActiveState --value fixture-update) = inactive")
    machine.succeed("test $(systemctl show -p Result --value fixture-update) = success")
    machine.wait_for_unit("anq-game-palworld.service")
    machine.succeed("test ! -e /run/anq-games/palworld.maintenance; test ! -e /run/anq-games/palworld.fetch-ready")
    # Losing the coordinator must not open the game while its fetch still runs.
    machine.succeed("touch /var/lib/anq-games/palworld/home/hold-fetch")
    machine.succeed("systemd-run --no-block --unit=fixture-interrupted --property=Type=oneshot /run/current-system/sw/bin/game-ops update palworld")
    machine.wait_until_succeeds("test $(systemctl show -p ActiveState --value anq-game-fetch-palworld) = activating")
    machine.succeed("systemctl stop fixture-interrupted")
    machine.succeed("test -e /run/anq-games/palworld.maintenance; systemctl start anq-game-palworld")
    machine.fail("systemctl is-active --quiet anq-game-palworld")
    machine.succeed("rm /var/lib/anq-games/palworld/home/hold-fetch")
    machine.wait_until_succeeds("test $(systemctl show -p ActiveState --value anq-game-fetch-palworld) = inactive")
    machine.succeed("rm /run/anq-games/palworld.fetch-ready /run/anq-games/palworld.maintenance; systemctl start anq-game-palworld")
    machine.wait_for_unit("anq-game-palworld.service")
    # Direct fetch starts are skipped outside the coordinator's fetch phase.
    machine.succeed("touch /var/lib/anq-games/palworld/home/hold-fetch; systemctl start anq-game-fetch-palworld")
    machine.fail("systemctl is-active --quiet anq-game-fetch-palworld")
    machine.succeed("rm /var/lib/anq-games/palworld/home/hold-fetch")
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
