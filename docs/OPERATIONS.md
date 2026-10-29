# Operating and recovering a world

## Switching the dedicated host between games

Keep each installed game's state and settings separate. Configure at most the
chosen default game to auto-start; the other installed games stay manual. For
example, after installing and testing both games, switch from Enshrouded to
Palworld with:

```sh
sudo game-ops backup enshrouded &&
sudo systemctl stop anq-game-enshrouded.service &&
sudo systemctl start anq-game-palworld.service
```

The chained commands prevent a start after a failed backup or stop. Inspect the
selected game's logs and join with a client before considering the switch done.
Stopping does not delete its saved world or uninstall the game. Routine starts
do not download updates. This is an explicit administrative procedure, not a
global exclusion lock; direct systemctl commands can still run multiple games.
If exclusive switching is later exposed in a UI, it needs its own guarded host
operation. The web-app publishing dashboard does not currently provide that.

## Planned change

1. Tell players about the interruption and use the game's own save/shutdown
   mechanism where available. Check its logs before proceeding.
2. Run `sudo game-ops backup GAME`. Confirm the service returns to its previous
   state and the archive/sidecar exist. Copy them to protected off-host storage.
3. Edit private settings outside the Nix store. Run a normal service restart for
   configuration changes, or `game-ops update GAME` for a deliberate binary update.
4. Inspect systemd and game logs. Join from a real client and check the world.

A game that ignores the stop signal may time out. The helper requires a successful
systemd stop result and aborts otherwise. A clean process exit is useful evidence,
not proof that a proprietary game flushed every save correctly.

## Failed update

The helper leaves the game stopped after SteamCMD failure. Its data snapshot is
retained. Inspect `journalctl -u anq-game-fetch-GAME`, resolve the download or
storage problem, and retry `game-ops update GAME`. A retry from stopped state
stays stopped; start the main service explicitly after inspection.

Game binaries are updated in place. Snapshot recovery covers configured saved
state/settings, not a transactional rollback of the Steam binaries. A NixOS
configuration rollback does not roll back Steam content or reverse a game's save
schema migration.

## Recovery drill

Run `game-ops restore-check GAME ARCHIVE NEW_DIRECTORY`. The destination must not
exist and cannot sit inside that game's live state tree. Inspect the extracted
save files and settings, check ownership/expected paths, and compare known world
data. The helper does not start a game on this copy.

For a real recovery, keep the main service stopped, preserve the damaged state
separately, and deliberately copy the verified data into the documented game
paths with the corresponding game user's ownership. Start with a compatible game
version and verify with a client. This overwrite is intentionally a manual step;
there is no command that silently replaces live saves.

## Snapshot boundaries

- Palworld: `server/Pal/Saved`, including configs/saves/logs.
- Enshrouded: `server/savegame` and the runtime `enshrouded_server.json`.
- V Rising: `data`, including Settings and Saves. Its separate logs/Wine cache and
  binary installation are not part of saved-world snapshots.

The first install can have no saved state yet, so update skips that empty snapshot.
An explicit backup with no saved state fails. Archives do not follow symlinks;
restore-check rejects them. Do not move saves outside the documented boundary or
replace saved-state directories with links.

Snapshots contain passwords/settings; use protected destinations when moving or
extracting them. v1 has no encryption, pruning or remote backup delivery. Archive
and sidecar are written separately; a missing sidecar makes the snapshot unusable
by restore-check. Investigate it rather than treating it as a verified backup.
