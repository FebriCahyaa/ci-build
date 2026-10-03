#!/usr/bin/env bash
set -Eeuo pipefail

LABEL="${1:?phase label is required}"
LOG_FILE="${2:?log file is required}"
shift 2
[[ $# -gt 0 ]] || { echo "usage: run_with_heartbeat.sh LABEL LOG_FILE COMMAND [ARGS...]" >&2; exit 2; }

INTERVAL="${CI_HEARTBEAT_SECONDS:-15}"
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || (( INTERVAL < 1 )); then
  echo "ERROR: CI_HEARTBEAT_SECONDS must be a positive integer" >&2
  exit 2
fi

mkdir -p "$(dirname -- "$LOG_FILE")"
touch "$LOG_FILE"

started="$(date +%s)"
echo "[CI-PHASE] ${LABEL} START" | tee -a "$LOG_FILE"
echo "[CI-COMMAND] ${LABEL}: $(printf '%q ' "$@")" | tee -a "$LOG_FILE"

run_child() {
  set +e
  if command -v stdbuf >/dev/null 2>&1; then
    stdbuf -oL -eL "$@" 2>&1 | tee -a "$LOG_FILE"
  else
    "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
  return "${PIPESTATUS[0]}"
}

run_child "$@" &
child_pid=$!

heartbeat_pid=""
heartbeat() {
  while kill -0 "$child_pid" 2>/dev/null; do
    sleep "$INTERVAL"
    if kill -0 "$child_pid" 2>/dev/null; then
      now="$(date +%s)"
      elapsed=$((now - started))
      printf '[CI-HEARTBEAT] phase=%s status=RUNNING elapsed=%ss pid=%s\n' \
        "$LABEL" "$elapsed" "$child_pid" | tee -a "$LOG_FILE"
    fi
  done
}
heartbeat &
heartbeat_pid=$!

cleanup() {
  if [[ -n "$heartbeat_pid" ]]; then
    kill "$heartbeat_pid" 2>/dev/null || true
    wait "$heartbeat_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

set +e
wait "$child_pid"
rc=$?
set -e

now="$(date +%s)"
elapsed=$((now - started))
if (( rc == 0 )); then
  printf '[CI-PHASE] %s DONE status=SUCCEEDED elapsed=%ss\n' "$LABEL" "$elapsed" | tee -a "$LOG_FILE"
else
  printf '[CI-PHASE] %s DONE status=FAILED exit=%s elapsed=%ss\n' "$LABEL" "$rc" "$elapsed" | tee -a "$LOG_FILE"
fi

exit "$rc"
