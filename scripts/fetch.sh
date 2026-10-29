set -euo pipefail
: "${ANQ_ROOT:?}" "${ANQ_APP_ID:?}" "${ANQ_WINDOWS:?}"
mkdir -p "$ANQ_ROOT/server" "$ANQ_ROOT/home"
args=(+force_install_dir "$ANQ_ROOT/server")
if [[ "$ANQ_WINDOWS" == true ]]; then
  args=(+@sSteamCmdForcePlatformType windows "${args[@]}")
fi
# Deliberately separate from service start/restart. Steam owns these binaries.
exec steamcmd "${args[@]}" +login anonymous +app_update "$ANQ_APP_ID" validate +quit
