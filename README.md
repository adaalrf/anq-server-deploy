# ANQ Server Deploy

Small NixOS modules and operations for Palworld, Enshrouded and V Rising. Each
game gets its own system user, writable state directory, private runtime settings
and explicit SteamCMD update command.

This v1 targets an **existing x86_64 NixOS host**. It does not install/repartition
a machine. Project checks/tools use
NixOS 26.05 pinned in flake.lock; your host controls its own Nixpkgs input.
Game binaries remain mutable Steam downloads, not pinned
Nix packages.

## Use the module

In your existing host flake, add a local input pointing at this checkout:

```nix
inputs.anqGames.url = "path:/absolute/path/to/anq-server-deploy";
```

Add the module to that host's modules list, alongside its own hardware/config:

```nix
anqGames.nixosModules.default
{
  nixpkgs.config.allowUnfree = true;
  services.anqGames.palworld = {
    enable = true;
    settingsFile = "/var/lib/anq-game-secrets/palworld.ini";
    autoStart = false;
    openFirewall = false;
  };
}
```

Use the input name from your flake outputs arguments. The standalone
[host fragment](examples/host.nix) shows the same setup with a relative import.
The module does not change SSH users/keys, disks, bootloaders or your host name.

Copy the appropriate fictional settings example outside the repository, edit it,
and protect its parent directory/file as root (700/600). `settingsFile` must be an
absolute **string** pointing to that host file. Nix paths/interpolated secret
files can enter the world-readable Nix store; store paths are rejected here.
The service reads settings using systemd `LoadCredential`, then installs its
runtime copy with mode 600. Example passwords must be replaced before real use.

Build/review the existing host configuration through your usual NixOS workflow,
then apply it deliberately. First installation is explicit:

```sh
sudo game-ops update palworld
sudo systemctl start anq-game-palworld
sudo game-ops status palworld
```

A routine restart never downloads game updates. Auto-start and firewall changes
are off by default. Enable them after a successful install and real client check.
Keep configured ports consistent with the private game settings and any provider
firewall. Resource ceilings are examples, not player-capacity recommendations.

## Games and paths

| Game | Download app ID | Launcher | Default UDP ports | Snapshot paths, relative to state |
| --- | --- | --- | --- | --- |
| Palworld | 2394010 | Native Linux via steam-run | 8211 | server/Pal/Saved |
| Enshrouded | 2278520 | Wine and an automatic X display | 15637 | server/savegame, server/enshrouded_server.json |
| V Rising | 1829350 | Wine and an automatic X display | 9876, 9877 | data |

State lives in `/var/lib/anq-games/GAME`, owned by `anq-GAME` with mode 700.
Executables are under `server/`; Steam's home/cache is under `home/`; each Wine
service has its own prefix/display. V Rising uses `data/Settings` and `data/Saves`.
Enshrouded's save/log paths are fixed to its local server directories so its
configured data cannot silently escape the snapshot boundary. Extra arguments
are literal list entries, not shell code.

The SteamCMD unit is `anq-game-fetch-GAME.service`; use `game-ops update`, which
stops the game and snapshots first. Starting the fetch unit directly bypasses
that coordination. Default firewalls expose no ports, and RCON is not enabled by
the module. See the [upstream references](docs/UPSTREAM.md) for settings/ports.

## Operations

```sh
sudo game-ops backup palworld
sudo game-ops update palworld
sudo game-ops restore-check palworld /var/backup/anq-games/ARCHIVE.tar.gz /var/tmp/palworld-drill
```

Backups stop an active game, require a clean stop result, archive existing saved
state/settings, and restart only if it was previously running. An update takes
the same snapshot before SteamCMD runs. A failed snapshot prevents the update;
a failed update leaves the game stopped because its binaries may be partly
changed. Successful updates preserve the previous running/stopped state.

Snapshots and SHA-256 sidecars live under root-only `/var/backup/anq-games`.
They include private settings. They are local, unencrypted recovery copies with
no automatic retention/off-host transfer; configure those separately for a real
host. Checksums detect accidental corruption, not a malicious operator.

Restore checks verify the checksum, reject traversal/links/special files, and
extract into a **new** directory outside live game state. They do not restore a
running world in place. See [operations and recovery](docs/OPERATIONS.md).

`status` shows systemd state and socket evidence. It does not prove discovery,
a healthy world, or the ability for a client to join.

## Verify locally

```sh
nix flake check --no-build
nix build .#checks.x86_64-linux.module-evaluation .#checks.x86_64-linux.operations .#checks.x86_64-linux.shell-package --no-link -L
nix build .#checks.x86_64-linux.lifecycle-vm --no-link -L
```

The operations suite uses temporary files and a fake systemctl for failure cases.
The VM boots actual NixOS/systemd and exercises all three service launch paths,
private settings, update/start/stop, backups, extraction and failed-update recovery.
It substitutes fixture executables for SteamCMD, steam-run, Wine and the games.
It can run with software emulation when KVM is absent. No real game downloads or
client connections are performed by these checks.

The built package exposes `game-ops`; configured hosts receive it automatically.
For formatting, use `nix fmt -- flake.nix lib/*.nix modules/*.nix tests/*.nix examples/*.nix`.
`nix develop` also provides ShellCheck and Python for direct test iteration.

## Scope and evidence

See [upstream references](docs/UPSTREAM.md). The local/fixture checks validate this
project's lifecycle mechanics. Real Steam/Wine startup, game-client joins and
world recovery are separate deployment acceptance checks, still outstanding.
No game availability, load capacity or cross-version save compatibility is
claimed.

See [contributing and source layout](CONTRIBUTING.md) for development commands, editing locations and verification boundaries.
