set -euo pipefail
umask 077
: "${ANQ_ROOT:?}" "${ANQ_GAME:?}" "${ANQ_EXECUTABLE:?}" "${ANQ_SETTINGS:?}" "${CREDENTIALS_DIRECTORY:?}"
if [[ ! -f "$ANQ_ROOT/server/$ANQ_EXECUTABLE" ]]; then
  echo "Server is not installed. Run: sudo game-ops update $ANQ_GAME" >&2
  exit 1
fi
settings="$CREDENTIALS_DIRECTORY/settings"
[[ -s "$settings" ]] || { echo 'Private settings credential is missing or empty.' >&2; exit 1; }
mkdir -p "$ANQ_ROOT/home" "$ANQ_ROOT/data" "$ANQ_ROOT/logs" "$(dirname "$ANQ_ROOT/$ANQ_SETTINGS")"
case "$ANQ_GAME" in
  palworld)
    install -m 0600 "$settings" "$ANQ_ROOT/$ANQ_SETTINGS"
    ;;
  enshrouded)
    mkdir -p "$ANQ_ROOT/server/savegame" "$ANQ_ROOT/server/logs"
    jq -e 'type == "object"' "$settings" >/dev/null
    temporary=$(mktemp "$ANQ_ROOT/server/.settings-XXXXXX")
    trap 'rm -f "$temporary"' EXIT
    # Keep saves/logs within the documented backup and writable boundaries.
    jq '.saveDirectory="./savegame" | .logDirectory="./logs"' "$settings" > "$temporary"
    chmod 0600 "$temporary"
    mv -f "$temporary" "$ANQ_ROOT/$ANQ_SETTINGS"
    ;;
  vrising)
    jq -e 'type == "object"' "$settings" >/dev/null
    install -m 0600 "$settings" "$ANQ_ROOT/$ANQ_SETTINGS"
    ;;
  *) echo 'Unknown game.' >&2; exit 1 ;;
esac
