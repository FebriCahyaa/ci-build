#!/usr/bin/env bash
set -Eeuo pipefail
BUILD_LOG="${1:?build log is required}"
TOTAL="${2:-0}"
WORK_DIR="${3:-$(dirname -- "$BUILD_LOG")}" 
PROGRESS_SCRIPT="${4:?progress beacon path is required}"
INTERVAL="${CI_COMPILE_PROGRESS_SECONDS:-5}"
OFFSET="${CI_COMPILE_PROGRESS_OFFSET:-44}"
SPAN="${CI_COMPILE_PROGRESS_SPAN:-45}"
START_TIME="${CI_COMPILE_PROGRESS_START:-$(date +%s)}"
count_actions() {
  [[ -f "$BUILD_LOG" ]] || { echo 0; return; }
  grep -Ec '^[[:space:]]+(CC|AS|HOSTCC|HOSTAS)[[:space:]]' "$BUILD_LOG" 2>/dev/null || true
}
emit() {
  local pct="$1" detail="$2"
  [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" && -n "${TG_MESSAGE_ID:-}" || -n "${GH_TOKEN:-}" && -n "${GH_REPOSITORY:-}" && -n "${CI_BUILD_SHA:-}" ]] || return 0
  TG_MESSAGE_ID="${TG_MESSAGE_ID:-}" TG_START_TIME="$START_TIME" \
  TG_BOT_TOKEN="${TG_BOT_TOKEN:-}" TG_CHAT_ID="${TG_CHAT_ID:-}" TG_TOPIC_ID="${TG_TOPIC_ID:-}" \
  GH_TOKEN="${GH_TOKEN:-}" GH_REPOSITORY="${GH_REPOSITORY:-}" CI_BUILD_SHA="${CI_BUILD_SHA:-}" \
  BUILD_PROFILE="${BUILD_PROFILE:-unknown}" TG_REQUIRE_TOPIC="${TG_REQUIRE_TOPIC:-false}" \
  HARNESS_EXECUTION_ID="${HARNESS_EXECUTION_ID:-}" RUN_URL="${RUN_URL:-}" WORK_DIR="$WORK_DIR" BUILD_LOG="$BUILD_LOG" \
  DEVICE="${DEVICE:-}" ROOT_VARIANT="${ROOT_VARIANT:-}" VARIANT_LABEL="${VARIANT_LABEL:-}" \
  CI_PROGRESS_STATE_FILE="$WORK_DIR/.tg-progress-last" \
  "$PROGRESS_SCRIPT" "$pct" pending "compile" "$detail" || true
}
last=-1
last_count=-1
last_change="$(date +%s)"
while [[ ! -f "$WORK_DIR/.stop-compile-telemetry" ]]; do
  now="$(date +%s)"
  count="$(count_actions)"
  if [[ "$TOTAL" =~ ^[0-9]+$ ]] && ((TOTAL>0)); then
    (( count > TOTAL )) && count="$TOTAL"
    pct=$((OFFSET + count*SPAN/TOTAL))
  else
    pct="$OFFSET"
  fi
  if (( count != last_count )); then
    last_count="$count"
    last_change="$now"
  elif (( now - last_change >= INTERVAL * 3 )); then
    elapsed=$((now - START_TIME))
    ramp=$((elapsed / (INTERVAL * 3)))
    (( ramp > SPAN - 1 )) && ramp=$((SPAN - 1))
    fallback=$((OFFSET + ramp))
    (( fallback > pct )) && pct="$fallback"
  fi
  (( pct > 89 )) && pct=89
  if (( pct != last )); then
    if (( count > 0 && TOTAL > 0 )); then
      detail="objects ${count}/${TOTAL}"
    else
      detail="build activity • elapsed $((now-START_TIME))s"
    fi
    emit "$pct" "$detail"
    last="$pct"
  fi
  sleep "$INTERVAL"
done
