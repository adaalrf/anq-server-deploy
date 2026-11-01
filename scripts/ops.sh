set -euo pipefail
umask 077
usage() {
  echo 'Usage: game-ops {status|backup|update} {palworld|enshrouded|vrising}' >&2
  echo '       game-ops restore-check GAME ARCHIVE NEW_DIRECTORY' >&2
  exit 2
}
[[ $# -ge 2 ]] || usage
operation=$1
name=$2
case "$name" in palworld|enshrouded|vrising) ;; *) usage ;; esac
case "$operation" in status|backup|update) [[ $# == 2 ]] || usage ;; restore-check) [[ $# == 4 ]] || usage ;; *) usage ;; esac
[[ $(id -u) == 0 ]] || { echo 'Run game-ops as root on the configured NixOS host.' >&2; exit 1; }
: "${ANQ_CONFIG_ROOT:=/etc/anq-games}" "${ANQ_RESTORE_HELPER:?}"
manifest="$ANQ_CONFIG_ROOT/$name.json"
[[ -f "$manifest" ]] || { echo "Game is not enabled: $name" >&2; exit 1; }
root=$(jq -er '.stateDirectory' "$manifest")
unit=$(jq -er '.unit' "$manifest")
fetch_unit=$(jq -er '.fetchUnit' "$manifest")
backups=$(jq -er '.backupDirectory' "$manifest")
if [[ "$operation" == status ]]; then
  systemctl --no-pager status "$unit"
  echo 'Listener evidence (not a game-protocol/client connection check):'
  ss -lntu
  exit 0
fi
if [[ "$operation" == restore-check ]]; then
  exec python3 "$ANQ_RESTORE_HELPER" "$3" "$4" "$root"
fi
install -d -m 0700 "$backups" "$backups/.locks"
exec 9> "$backups/.locks/$name.lock"
flock -n 9 || { echo "Another backup/update holds the $name lock." >&2; exit 1; }
was_running=false
state=$(systemctl show --property=ActiveState --value "$unit")
case "$state" in
  inactive|failed) ;;
  active|activating|deactivating|reloading|refreshing) was_running=true ;;
  *) echo 'Cannot determine game state safely; no operation attempted.' >&2; exit 1 ;;
esac
configured_paths=$(jq -er '.backupPaths[]' "$manifest")
: "${ANQ_RUNTIME_ROOT:=/run/anq-games}"
install -d -m 0755 "$ANQ_RUNTIME_ROOT"
maintenance="$ANQ_RUNTIME_ROOT/$name.maintenance"
fetch_ready="$ANQ_RUNTIME_ROOT/$name.fetch-ready"
# Conditions on the units block new starts while the coordinator quiesces state.
# Never reuse a marker left by an interrupted operation without inspection.
if [[ -e "$fetch_ready" || -L "$fetch_ready" ]] || ! (set -o noclobber; : > "$maintenance"); then
  echo 'Interrupted maintenance marker exists; inspect the game and update before removing it.' >&2
  exit 1
fi
restart=false
finish() {
  local result=$?
  trap - EXIT
  if [[ -e "$fetch_ready" ]]; then
    local fetch_state
    fetch_state=$(systemctl show --property=ActiveState --value "$fetch_unit") || fetch_state=unknown
    case "$fetch_state" in
      inactive|failed) ;;
      *)
        echo 'Fetch still active or uncertain; maintenance markers retained for inspection.' >&2
        [[ "$result" != 0 ]] || result=1
        exit "$result"
        ;;
    esac
  fi
  rm -f -- "$fetch_ready" "$maintenance"
  if [[ "$restart" == true && "$was_running" == true ]]; then
    if ! systemctl start "$unit"; then
      echo "Restart failed: inspect $unit before continuing." >&2
      [[ "$result" != 0 ]] || result=1
    fi
  fi
  exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
# Stop even inactive units: this cancels queued starts and auto-restart jobs.
systemctl stop "$unit"
case $(systemctl show --property=ActiveState --value "$unit") in
  inactive|failed) ;;
  *) echo 'Game did not stop; backup/update aborted.' >&2; exit 1 ;;
esac
if [[ "$was_running" == true ]]; then
  if [[ $(systemctl show --property=Result --value "$unit") != success ]]; then
    echo 'Service did not stop cleanly. Backup/update aborted; it was left stopped.' >&2
    exit 1
  fi
fi
# Backup failure is safe to restart: no binary update has begun.
restart=true
paths=()
while IFS= read -r path; do
  [[ "$path" != /* && "$path" != *'..'* && -n "$path" ]] || { echo 'Invalid configured backup path.' >&2; exit 1; }
  if [[ -e "$root/$path" || -L "$root/$path" ]]; then paths+=("$path"); fi
done <<< "$configured_paths"
if [[ ${#paths[@]} -gt 0 ]]; then
  temporary=$(mktemp "$backups/.$name-XXXXXX.tar.gz")
  if ! tar -czf "$temporary" -C "$root" -- "${paths[@]}"; then
    rm -f "$temporary"
    echo 'Backup failed; no update was attempted.' >&2
    exit 1
  fi
  if ! gzip -t "$temporary" || ! python3 "$ANQ_RESTORE_HELPER" --validate "$temporary"; then
    rm -f "$temporary"
    echo 'Snapshot is not safely restorable; no update was attempted.' >&2
    exit 1
  fi
  final="$backups/$name-$(date -u +%Y%m%dT%H%M%SZ)-${temporary##*-}"
  mv "$temporary" "$final"
  sha256sum "$final" > "$final.sha256"
  echo "Backup: $final"
elif [[ "$operation" == backup ]]; then
  echo 'No saved state/config exists to back up yet.' >&2
  exit 1
fi
if [[ "$operation" == update ]]; then
  # SteamCMD may modify binaries in place. Failed updates stay stopped.
  restart=false
  (set -o noclobber; : > "$fetch_ready")
  if ! systemctl start "$fetch_unit"; then
    echo 'Update failed. The game remains stopped; repair/retry before starting it.' >&2
    exit 1
  fi
  restart=true
  echo 'Update completed. Previous running/stopped state will be preserved.'
fi
