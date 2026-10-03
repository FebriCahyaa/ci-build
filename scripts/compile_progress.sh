#!/usr/bin/env bash
set -Eeuo pipefail
BUILD_LOG="${1:?build log is required}"
TOTAL="${2:-0}"
WORK_DIR="${3:-$(dirname -- "$BUILD_LOG")}"
PROGRESS_SCRIPT="${4:?progress beacon path is required}"
INTERVAL="${CI_COMPILE_PROGRESS_SECONDS:-2}"
OFFSET="${CI_COMPILE_PROGRESS_OFFSET:-45}"
SPAN="${CI_COMPILE_PROGRESS_SPAN:-44}"
count_actions() {
  [[ -f "$BUILD_LOG" ]] || { echo 0; return; }
  grep -Ec '^[[:space:]]+(CC|AS|HOSTCC|HOSTAS)[[:space:]]' "$BUILD_LOG" 2>/dev/null || true
}
emit() {
  GH_TOKEN="${GH_TOKEN:-}" GH_REPOSITORY="${GH_REPOSITORY:-}" \
  CI_BUILD_SHA="${CI_BUILD_SHA:-}" HARNESS_EXECUTION_ID="${HARNESS_EXECUTION_ID:-}" \
  RUN_URL="${RUN_URL:-}" WORK_DIR="$WORK_DIR" \
  "$PROGRESS_SCRIPT" "$1" pending "kernel compile" "$2" || true
}
last=-1
while [[ ! -f "$WORK_DIR/.stop-compile-telemetry" ]]; do
  count="$(count_actions)"
  pct="$OFFSET"
  if [[ "$TOTAL" =~ ^[0-9]+$ ]] && ((TOTAL>0)); then
    ((count>TOTAL)) && count="$TOTAL"
    pct=$((OFFSET + count*SPAN/TOTAL))
  fi
  ((pct>89)) && pct=89
  if ((pct!=last)); then emit "$pct" "objects ${count}/${TOTAL}"; last="$pct"; fi
  sleep "$INTERVAL"
done
