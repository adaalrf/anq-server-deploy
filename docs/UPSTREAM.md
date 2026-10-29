# Upstream references

Checked 2026-10-27. These document upstream downloads/settings; they are not proof
that this Linux compatibility recipe has passed a live game-client test.

- [NixOS download/release](https://nixos.org/download/): the project locks the
  stable 26.05 input. Update flake.lock deliberately and rerun checks.
- [Palworld deployment](https://docs.palworldgame.com/getting-started/deploy-dedicated-server/):
  SteamCMD app 2394010 and the native Linux PalServer.sh entry point.
- [Enshrouded installation](https://enshrouded.zendesk.com/hc/en-us/articles/16051370691485-Dedicated-Server-Installation-on-Steam):
  the upstream server is a Windows executable. Wine on Linux is a compatibility
  path in this project, not an upstream Linux-support promise.
- [Enshrouded FAQ](https://enshrouded.zendesk.com/hc/en-us/articles/16056312924957-Dedicated-Server-FAQ):
  query port 15637 and the default savegame/log directories.
- [Enshrouded server on Steam](https://store.steampowered.com/app/2278520/):
  server application identity used by the archived project and this catalog.
- [V Rising current PC instructions](https://github.com/StunlockStudios/vrising-dedicated-server-instructions/blob/master/1.1.x-pc/INSTRUCTIONS.md):
  server download app 1829350, persistentDataPath, settings overrides, saves and
  offline updates. The supplied runtime steam_appid.txt remains upstream-owned;
  this project does not overwrite it or fetch additional Steam DLL depots.

Use the current configuration generated/shipped by each game as the reference
when adopting an example. The examples are small fictional starting points, not
complete game configuration schemas. Defaults, networking and compatibility can
change independently of NixOS and this repository.
