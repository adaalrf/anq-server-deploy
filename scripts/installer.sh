#!/usr/bin/env bash
set -euo pipefail

read_opt() {
  local key="$1"
  nix eval --impure --raw --expr "builtins.toString ((import ./options.nix).${key})" 2>/dev/null || true
}

normalize_bool() {
  case "$1" in
    1|true|yes|on) echo "1" ;;
    0|false|no|off|"") echo "0" ;;
    *)
      echo "Invalid boolean value: $1" >&2
      exit 1
      ;;
  esac
}

HOST="$(read_opt deploy.host)"
USER="$(read_opt deploy.user)"
SERVICE="$(read_opt service)"
REMOTE_REPO_DIR="$(read_opt deploy.remoteRepoDir)"
BUILD_ON_REMOTE="$(normalize_bool "$(read_opt deploy.buildOnRemote)")"
QUIET="$(normalize_bool "$(read_opt deploy.quiet)")"
MODE="$(read_opt deploy.mode)"
ACCEPT_NEW_HOST_KEYS="$(normalize_bool "$(read_opt ssh.acceptNewHostKeys)")"
CONFIRM_INSTALL="$(normalize_bool "$(read_opt installer.confirmInstall)")"
BACKUP_ENABLE="$(normalize_bool "$(read_opt backup.enable)")"
BACKUP_DIR="$(read_opt backup.localDir)"
ARCHIVE_KEEP="$(read_opt backup.archiveKeep)"
BACKUP_ALLOW_INSIDE_NO_GIT="$(normalize_bool "$(read_opt backup.allowInsideRepoWithoutGit)")"
BACKUP_PATHS="$(nix eval --impure --raw --expr "builtins.concatStringsSep \" \" ((import ./options.nix).services.${SERVICE}.backupPaths or [])" 2>/dev/null || true)"

if [[ -z "$HOST" ]]; then
  echo "Missing host in options.nix" >&2
  exit 1
fi

if [[ -z "$USER" && "$HOST" != *@* ]]; then
  echo "Missing user in options.nix" >&2
  exit 1
fi

if [[ -z "$REMOTE_REPO_DIR" ]]; then
  echo "Missing remoteRepoDir in options.nix" >&2
  exit 1
fi

if [[ -z "$SERVICE" ]]; then
  echo "Missing service in options.nix" >&2
  exit 1
fi

FLAKE=".#$SERVICE"

if [[ -z "$MODE" ]]; then
  echo "Missing mode in options.nix" >&2
  exit 1
fi

if [[ "$MODE" != "install" && "$MODE" != "switch" ]]; then
  echo "Invalid mode: $MODE" >&2
  echo "Expected 'install' or 'switch'." >&2
  exit 1
fi

if [[ "$MODE" == "install" && "$CONFIRM_INSTALL" != "1" ]]; then
  echo "Install mode is destructive. Set installer.confirmInstall = true to continue." >&2
  exit 1
fi

TARGET_HOST="$HOST"
if [[ "$HOST" != *@* ]]; then
  TARGET_HOST="$USER@$HOST"
fi

log() {
  if [[ "$QUIET" != "1" ]]; then
    echo "$@"
  fi
}

log "Checking SSH connectivity to $TARGET_HOST..."
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
if [[ "$ACCEPT_NEW_HOST_KEYS" == "1" ]]; then
  SSH_OPTS+=(-o StrictHostKeyChecking=accept-new)
fi
if ! ssh "${SSH_OPTS[@]}" "$TARGET_HOST" true; then
  echo "Unable to reach $TARGET_HOST via SSH." >&2
  exit 1
fi

log "Detecting sudo on target..."
REMOTE_SUDO=""
if ssh "$TARGET_HOST" "command -v sudo >/dev/null 2>&1"; then
  REMOTE_SUDO="sudo"
fi

log "Ensuring $REMOTE_REPO_DIR exists on target..."
if [[ -n "$REMOTE_SUDO" ]]; then
  ssh "$TARGET_HOST" "$REMOTE_SUDO" mkdir -p "$REMOTE_REPO_DIR"
else
  ssh "$TARGET_HOST" mkdir -p "$REMOTE_REPO_DIR"
fi

RSYNC_PATH="rsync"
if [[ -n "$REMOTE_SUDO" ]]; then
  RSYNC_PATH="$REMOTE_SUDO rsync"
fi

if [[ "$BACKUP_ENABLE" == "1" ]]; then
  if [[ -z "$BACKUP_DIR" ]]; then
    echo "Backup enabled but backup.localDir is empty." >&2
    exit 1
  fi
  if [[ -z "$ARCHIVE_KEEP" ]]; then
    ARCHIVE_KEEP=10
  fi
  if ! [[ "$ARCHIVE_KEEP" =~ ^[0-9]+$ ]]; then
    echo "Invalid backup.archiveKeep value: $ARCHIVE_KEEP" >&2
    exit 1
  fi

  REPO_ROOT_REAL="$(realpath -m "$(pwd)")"
  BACKUP_DIR_REAL="$(realpath -m "$BACKUP_DIR")"
  if [[ "$BACKUP_DIR_REAL" == "$REPO_ROOT_REAL"* && ! -d "${REPO_ROOT_REAL}/.git" ]]; then
    if [[ "$BACKUP_ALLOW_INSIDE_NO_GIT" == "1" ]]; then
      log "Warning: backup.localDir lives inside the repo but .git is missing. Backups will continue because backup.allowInsideRepoWithoutGit is true."
    else
      echo "backup.localDir is inside the repo but .git is missing." >&2
      echo "Move backups outside the repo or initialize git to keep backups inside." >&2
      exit 1
    fi
  fi
  if [[ -z "$BACKUP_PATHS" ]]; then
    BACKUP_PATHS="/srv/$SERVICE"
  fi

  log "Backing up remote paths to $BACKUP_DIR..."
  mkdir -p "$BACKUP_DIR"
  for path in $BACKUP_PATHS; do
    if [[ -n "$REMOTE_SUDO" ]]; then
      path_exists=$(ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "$REMOTE_SUDO" test -d "$path" && echo 1 || echo 0)
    else
      path_exists=$(ssh "${SSH_OPTS[@]}" "$TARGET_HOST" test -d "$path" && echo 1 || echo 0)
    fi
    if [[ "$path_exists" == "1" ]]; then
      backup_name="$(basename "$path")"
      if [[ "$path" == "/srv/$SERVICE/server" ]]; then
        backup_name="${SERVICE}-server"
      fi
      rsync -az --delete --rsync-path="$RSYNC_PATH" "$TARGET_HOST:$path/" "$BACKUP_DIR/$backup_name/"
    else
      log "Skipping missing path: $path"
    fi
  done

  if (( ARCHIVE_KEEP > 0 )); then
    ARCHIVE_DIR="$BACKUP_DIR/archives"
    mkdir -p "$ARCHIVE_DIR"
    ARCHIVE_TS="$(date +"%Y%m%d-%H%M%S")"
    ARCHIVE_PATH="$ARCHIVE_DIR/backup-${SERVICE}-${ARCHIVE_TS}.tar.gz"
    tar -czf "$ARCHIVE_PATH" -C "$BACKUP_DIR" --exclude "archives" .
    mapfile -t ARCHIVES < <(ls -1t "$ARCHIVE_DIR"/backup-"${SERVICE}"-*.tar.gz 2>/dev/null || true)
    if (( ${#ARCHIVES[@]} > ARCHIVE_KEEP )); then
      for old_archive in "${ARCHIVES[@]:$ARCHIVE_KEEP}"; do
        rm -f "$old_archive"
      done
    fi
  fi
fi

log "Syncing repository to $TARGET_HOST:$REMOTE_REPO_DIR..."
rsync -az --delete --rsync-path="$RSYNC_PATH" \
  --exclude ".git" \
  --exclude "result" \
  --exclude ".direnv" \
  --exclude ".zed" \
  --exclude "backups" \
  ./ "$TARGET_HOST:$REMOTE_REPO_DIR/"

log "Starting deployment ($MODE)..."
if [[ "$MODE" == "switch" ]]; then
  log "Running nixos-rebuild switch (this may take a while depending on local/remote network)..."

  SYSTEM_NAME="$FLAKE"
  if [[ "$FLAKE" == *"#"* ]]; then
    SYSTEM_NAME="$(printf '%s' "$FLAKE" | cut -d'#' -f2-)"
  fi
  if ! ssh "$TARGET_HOST" "command -v nixos-rebuild >/dev/null 2>&1"; then
    echo "nixos-rebuild not found on target. Use mode=install for fresh installs." >&2
    exit 1
  fi
  if [[ -n "$REMOTE_SUDO" ]]; then
    ssh "$TARGET_HOST" "$REMOTE_SUDO" nixos-rebuild switch --flake "$REMOTE_REPO_DIR#$SYSTEM_NAME"
  else
    ssh "$TARGET_HOST" nixos-rebuild switch --flake "$REMOTE_REPO_DIR#$SYSTEM_NAME"
  fi
else
  NIXOS_ANYWHERE_ARGS=(--flake "$FLAKE" --target-host "$TARGET_HOST")
  if [[ "$BUILD_ON_REMOTE" == "1" ]]; then
    NIXOS_ANYWHERE_ARGS+=(--build-on-remote)
  fi
  nix run github:nix-community/nixos-anywhere -- "${NIXOS_ANYWHERE_ARGS[@]}"
fi


log "Deployment complete."
