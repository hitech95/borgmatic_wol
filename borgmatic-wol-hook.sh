#!/usr/bin/env bash
set -euo pipefail

BORG_WOL_HOST="${BORG_WOL_HOST:-}"
BORG_WOL_MAC="${BORG_WOL_MAC:-}"
BORG_WOL_TIMEOUT="${BORG_WOL_TIMEOUT:-300}"
BORG_WOL_POLL_INTERVAL="${BORG_WOL_POLL_INTERVAL:-5}"
BORG_WOL_BROADCAST="${BORG_WOL_BROADCAST:-255.255.255.255}"
BORG_WOL_PORT="${BORG_WOL_PORT:-9}"
BORG_WOL_CHECK_PORT="${BORG_WOL_CHECK_PORT:-}"
BORG_WOL_SSH_USER="${BORG_WOL_SSH_USER:-root}"
BORG_WOL_SSH_HOST="${BORG_WOL_SSH_HOST:-$BORG_WOL_HOST}"
BORG_WOL_SSH_OPTIONS="${BORG_WOL_SSH_OPTIONS:--o ConnectTimeout=10 -o BatchMode=yes}"
BORG_WOL_POWEROFF_CMD="${BORG_WOL_POWEROFF_CMD:-systemctl poweroff}"
BORG_WOL_STATE_FILE="${BORG_WOL_STATE_FILE:-/tmp/borgmatic-wol.state}"

log() { printf '[borgmatic-wol] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<'EOF'
Usage: borgmatic-wol-hook.sh <wake|shutdown|--help>

Wake-on-LAN helper for borgmatic. Call `wake` in before_everything and
`shutdown` in after_everything. If the target was offline when `wake` ran,
`shutdown` powers it off after the backup completes; otherwise it does nothing.

Configuration (environment variables):
  BORG_WOL_HOST            IP/hostname used for the online check.       (required)
  BORG_WOL_MAC             MAC address of the target NIC (xx:xx:...).   (wake)
  BORG_WOL_TIMEOUT         Seconds to wait for the target to come up.   (300)
  BORG_WOL_POLL_INTERVAL   Seconds between online checks.               (5)
  BORG_WOL_BROADCAST       Broadcast address for the WoL packet.        (255.255.255.255)
  BORG_WOL_PORT            UDP port for the WoL packet.                 (9)
  BORG_WOL_CHECK_PORT      TCP port to probe instead of ICMP ping.      (ping)
  BORG_WOL_SSH_USER        SSH user for shutdown.                       (root)
  BORG_WOL_SSH_HOST        SSH host for shutdown.                       (= BORG_WOL_HOST)
  BORG_WOL_SSH_OPTIONS     Extra ssh options.                           (ConnectTimeout/BatchMode)
  BORG_WOL_POWEROFF_CMD    Command run over SSH to power off.           (systemctl poweroff)
  BORG_WOL_STATE_FILE      Path used to persist the initial state.      (/tmp/borgmatic-wol.state)

The WoL magic packet is sent via `wakeonlan` (installed in the image). The
online check uses `ping`, or
`nc`/python3 TCP probe when BORG_WOL_CHECK_PORT is set. Shutdown requires
passwordless SSH (key-based) to the target, so openssh-client must be
installed in the container (see Dockerfile).

borgmatic config.yaml:
  before_everything:
    - /usr/local/bin/borgmatic-wol-hook.sh wake
  after_everything:
    - /usr/local/bin/borgmatic-wol-hook.sh shutdown
EOF
}

check_online() {
  if [[ -n "$BORG_WOL_CHECK_PORT" ]]; then
    if command -v nc >/dev/null 2>&1; then
      nc -z -w 2 "$BORG_WOL_HOST" "$BORG_WOL_CHECK_PORT" >/dev/null 2>&1
    else
      python3 - "$BORG_WOL_HOST" "$BORG_WOL_CHECK_PORT" <<'PY'
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect((host, port))
    sys.exit(0)
except OSError:
    sys.exit(1)
finally:
    s.close()
PY
    fi
  else
    ping -c 1 -W 2 "$BORG_WOL_HOST" >/dev/null 2>&1
  fi
}

wait_online() {
  local deadline=$(( SECONDS + BORG_WOL_TIMEOUT ))
  while (( SECONDS < deadline )); do
    if check_online; then return 0; fi
    sleep "$BORG_WOL_POLL_INTERVAL"
  done
  return 1
}

send_wol() {
  local mac="$1"
  [[ -n "$mac" ]] || die "BORG_WOL_MAC not set; cannot wake $BORG_WOL_HOST"
  wakeonlan -i "$BORG_WOL_BROADCAST" -p "$BORG_WOL_PORT" "$mac"
}

write_state() { printf '%s' "$1" > "$BORG_WOL_STATE_FILE"; }
read_state()  { [[ -r "$BORG_WOL_STATE_FILE" ]] && cat "$BORG_WOL_STATE_FILE" || printf 'up'; }

do_wake() {
  [[ -n "$BORG_WOL_HOST" ]] || die "BORG_WOL_HOST not set"
  if check_online; then
    log "$BORG_WOL_HOST already up; nothing to wake"
    write_state up
    return 0
  fi
  log "$BORG_WOL_HOST is offline; sending WoL to ${BORG_WOL_MAC:-<unset>}"
  write_state down
  send_wol "$BORG_WOL_MAC"
  log "waiting up to ${BORG_WOL_TIMEOUT}s for $BORG_WOL_HOST to come online..."
  if wait_online; then
    log "$BORG_WOL_HOST is online"
    return 0
  fi
  die "timed out waiting for $BORG_WOL_HOST"
}

do_shutdown() {
  local state
  state="$(read_state)"
  if [[ "$state" != "down" ]]; then
    log "target was already up before backup; leaving it on"
    rm -f "$BORG_WOL_STATE_FILE"
    return 0
  fi
  log "target was woken for backup; powering off via SSH"
  ssh $BORG_WOL_SSH_OPTIONS "${BORG_WOL_SSH_USER}@${BORG_WOL_SSH_HOST}" "$BORG_WOL_POWEROFF_CMD"
  rm -f "$BORG_WOL_STATE_FILE"
}

main() {
  case "${1:-}" in
    wake)            do_wake ;;
    shutdown)        do_shutdown ;;
    -h|--help|help)  usage ;;
    "")              usage; die "missing action" ;;
    *)               usage; die "unknown action: $1" ;;
  esac
}

main "$@"
