#!/usr/bin/env bash
set -euo pipefail

OPTIONS_PATH="${1:-"${PWD}/options.nix"}"
TESTS_DIR="${2:-"${PWD}/tests"}"

if [[ ! -f "$OPTIONS_PATH" ]]; then
  echo "options.nix not found at $OPTIONS_PATH" >&2
  exit 1
fi

if [[ ! -d "$TESTS_DIR" ]]; then
  echo "tests directory not found at $TESTS_DIR" >&2
  exit 1
fi

OPTS_JSON="$(nix eval --impure --json --expr "let opts = import ${OPTIONS_PATH}; in { host = opts.deploy.host; user = opts.deploy.user; service = opts.service; acceptNewHostKeys = opts.ssh.acceptNewHostKeys; }" 2>/dev/null || true)"

if [[ -z "$OPTS_JSON" ]]; then
  echo "Unable to read options from $OPTIONS_PATH" >&2
  exit 1
fi

HOST="$(jq -r '.host // empty' <<<"$OPTS_JSON")"
USER="$(jq -r '.user // empty' <<<"$OPTS_JSON")"
SERVICE_KEY="$(jq -r '.service // empty' <<<"$OPTS_JSON")"
ACCEPT_NEW_HOST_KEYS="$(jq -r '.acceptNewHostKeys // false' <<<"$OPTS_JSON")"

if [[ -z "$SERVICE_KEY" ]]; then
  echo "Missing service in options.nix" >&2
  exit 1
fi

SERVICE_TEST_PATH="${TESTS_DIR}/${SERVICE_KEY}.nix"
if [[ ! -f "$SERVICE_TEST_PATH" ]]; then
  echo "Missing tests/${SERVICE_KEY}.nix" >&2
  echo "Available tests:" >&2
  for test in "$TESTS_DIR"/*.nix; do
    if [[ -f "$test" ]]; then
      echo "- $(basename "$test" .nix)" >&2
    fi
  done
  exit 1
fi

TEST_JSON="$(nix eval --impure --json --expr "let test = import ${SERVICE_TEST_PATH}; in { serviceName = test.serviceName; logPattern = test.logPattern or null; ports = test.ports or {}; }" 2>/dev/null || true)"

if [[ -z "$TEST_JSON" ]]; then
  echo "Unable to read tests from $SERVICE_TEST_PATH" >&2
  exit 1
fi

SERVICE="$(jq -r '.serviceName // empty' <<<"$TEST_JSON")"
LOG_PATTERN="$(jq -r '.logPattern // empty' <<<"$TEST_JSON")"
UDP_PORTS="$(jq -r '.ports.udp // [] | map(tostring) | join(" ")' <<<"$TEST_JSON")"
UDP_PORTS_OPTIONAL="$(jq -r '.ports.udpOptional // [] | map(tostring) | join(" ")' <<<"$TEST_JSON")"
TCP_PORTS="$(jq -r '.ports.tcp // [] | map(tostring) | join(" ")' <<<"$TEST_JSON")"
TCP_PORTS_OPTIONAL="$(jq -r '.ports.tcpOptional // [] | map(tostring) | join(" ")' <<<"$TEST_JSON")"

if [[ -z "$HOST" ]]; then
  echo "Missing host in options.nix" >&2
  exit 1
fi

if [[ -z "$USER" && "$HOST" != *@* ]]; then
  echo "Missing user in options.nix" >&2
  exit 1
fi

if [[ -z "$SERVICE" ]]; then
  echo "Missing serviceName in tests/${SERVICE_KEY}.nix" >&2
  exit 1
fi

TARGET_HOST="$HOST"
if [[ "$HOST" != *@* ]]; then
  TARGET_HOST="$USER@$HOST"
fi

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
if [[ "$ACCEPT_NEW_HOST_KEYS" == "1" || "$ACCEPT_NEW_HOST_KEYS" == "true" ]]; then
  SSH_OPTS+=(-o StrictHostKeyChecking=accept-new)
fi

log() {
  echo "$@"
}

log "Checking SSH connectivity to $TARGET_HOST..."
ssh "${SSH_OPTS[@]}" "$TARGET_HOST" true

log "Checking service status ($SERVICE)..."
ssh "${SSH_OPTS[@]}" "$TARGET_HOST" systemctl is-active --quiet "$SERVICE"

log "Checking service process is running..."
SERVICE_PID="$(ssh "${SSH_OPTS[@]}" "$TARGET_HOST" systemctl show -p MainPID --value "$SERVICE")"
if [[ -z "$SERVICE_PID" || "$SERVICE_PID" == "0" ]]; then
  echo "Service has no running PID." >&2
  exit 1
fi

if ! ssh "${SSH_OPTS[@]}" "$TARGET_HOST" test -d "/proc/${SERVICE_PID}"; then
  echo "Service PID not found: ${SERVICE_PID}" >&2
  exit 1
fi

PROCESS_NAME="$(ssh "${SSH_OPTS[@]}" "$TARGET_HOST" ps -p "$SERVICE_PID" -o comm=)"
PROCESS_CMDLINE="$(ssh "${SSH_OPTS[@]}" "$TARGET_HOST" ps -p "$SERVICE_PID" -o args=)"
log "Service PID: ${SERVICE_PID} (${PROCESS_NAME:-unknown})"
log "Service command: ${PROCESS_CMDLINE:-unknown}"

check_port() {
  local protocol="$1"
  local port="$2"

  if ! ssh "${SSH_OPTS[@]}" "$TARGET_HOST" ss -"${protocol}" -l -n | grep -q ":${port} "; then
    echo "Port check failed: ${protocol^^} ${port}" >&2
    exit 1
  fi
}

if [[ -n "$UDP_PORTS" ]]; then
  log "Checking UDP ports: $UDP_PORTS"
  for port in $UDP_PORTS; do
    check_port u "$port"
  done
fi

if [[ -n "$UDP_PORTS_OPTIONAL" ]]; then
  log "Checking UDP optional ports: $UDP_PORTS_OPTIONAL"
  for port in $UDP_PORTS_OPTIONAL; do
    if ! ssh "${SSH_OPTS[@]}" "$TARGET_HOST" ss -u -l -n | grep -q ":${port} "; then
      log "UDP optional port not listening: ${port}"
    fi
  done
fi

if [[ -n "$TCP_PORTS" ]]; then
  log "Checking TCP ports: $TCP_PORTS"
  for port in $TCP_PORTS; do
    check_port t "$port"
  done
fi

if [[ -n "$TCP_PORTS_OPTIONAL" ]]; then
  log "Checking TCP optional ports: $TCP_PORTS_OPTIONAL"
  for port in $TCP_PORTS_OPTIONAL; do
    if ! ssh "${SSH_OPTS[@]}" "$TARGET_HOST" ss -t -l -n | grep -q ":${port} "; then
      log "TCP optional port not listening: ${port}"
    fi
  done
fi

if [[ -n "$LOG_PATTERN" && "$LOG_PATTERN" != "null" ]]; then
  log "Checking logs for pattern: $LOG_PATTERN"
  if ! ssh "${SSH_OPTS[@]}" "$TARGET_HOST" journalctl -u "${SERVICE}" -n 200 --no-pager | grep -q "${LOG_PATTERN}"; then
    echo "Log pattern not found: ${LOG_PATTERN}" >&2
    exit 1
  fi
fi

log "Health check passed."
