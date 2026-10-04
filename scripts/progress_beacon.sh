#!/usr/bin/env bash
# progress_beacon.sh <percent> [state] [phase] [detail]
#
# Records build progress in the JSON state file read by tg_dashboard.py
# (CI_PROGRESS_STATE_JSON, default $WORK_DIR/.ci-progress.json). When no live
# dashboard owns the Telegram message (TG_DASHBOARD_ACTIVE!=true), it falls back
# to a direct throttled edit through tg.sh. Optional GitHub commit-status
# progress stays opt-in (CI_GITHUB_STATUS_ENABLED=true); Telegram is the
# primary live UI.
#
# Extra state keys: COMPILE_DONE / COMPILE_TOTAL environment variables.
set -Eeuo pipefail
PERCENT="${1:?percent is required}"
STATE="${2:-pending}"
PHASE="${3:-build}"
DETAIL="${4:-working}"
[[ "$PERCENT" =~ ^[0-9]+$ ]] && ((PERCENT>=0 && PERCENT<=100)) || exit 2
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

STATE_JSON="${CI_PROGRESS_STATE_JSON:-${WORK_DIR:-/tmp}/.ci-progress.json}"
extra=()
[[ -n "${COMPILE_DONE:-}" ]] && extra+=("compile_done=$COMPILE_DONE")
[[ -n "${COMPILE_TOTAL:-}" ]] && extra+=("compile_total=$COMPILE_TOTAL")
python3 "$SCRIPT_DIR/progress_state.py" "$STATE_JSON" \
  "pct=$PERCENT" "state=$STATE" "phase=$PHASE" "detail=$DETAIL" "${extra[@]}" 2>/dev/null || true

if [[ "${TG_DASHBOARD_ACTIVE:-false}" != true && -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" && -n "${TG_MESSAGE_ID:-}" ]]; then
  # shellcheck source=tg.sh
  source "$SCRIPT_DIR/tg.sh"
  TG_START_TIME="${TG_START_TIME:-$(date +%s)}"
  TG_PROGRESS_STATE_FILE="${CI_PROGRESS_STATE_FILE:-${WORK_DIR:-/tmp}/.tg-progress-last}"
  BUILD_LOG="${BUILD_LOG:-${WORK_DIR:-/tmp}/build.log}"
  tg_progress_update "$PERCENT" "$STATE" "$PHASE" "$DETAIL" "$BUILD_LOG" || true
fi

# GitHub commit-status progress is opt-in. Telegram is the primary live UI.
if [[ "${CI_GITHUB_STATUS_ENABLED:-false}" == "true" && -n "${GH_TOKEN:-}" && -n "${GH_REPOSITORY:-}" && -n "${CI_BUILD_SHA:-}" ]]; then
  CONTEXT="${CI_PROGRESS_CONTEXT:-zairenkai/${HARNESS_EXECUTION_ID:-github-${GITHUB_RUN_ID:-local}}}"
  TARGET_URL="${RUN_URL:-}"
  STATE_FILE="${CI_STATUS_STATE_FILE:-${WORK_DIR:-/tmp}/.ci-status-last}"
  mkdir -p "$(dirname -- "$STATE_FILE")"
  signature="${PERCENT}|${STATE}|${PHASE}|${DETAIL}"
  last=""
  [[ -f "$STATE_FILE" ]] && last="$(cat "$STATE_FILE" 2>/dev/null || true)"
  if [[ "$signature" != "$last" || -n "${CI_PROGRESS_FORCE:-}" ]]; then
    desc="[${PERCENT}%] ${PHASE}: ${DETAIL}"
    desc="${desc:0:140}"
    payload="$(python3 - "$STATE" "$desc" "$TARGET_URL" "$CONTEXT" <<'PYTG'
import json,sys
state,desc,target,context=sys.argv[1:5]
print(json.dumps({"state":state,"description":desc,"target_url":target or None,"context":context},separators=(",",":")))
PYTG
)"
    if curl -fsSL --retry 2 --retry-delay 1 -X POST \
      -H "Authorization: Bearer ${GH_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      --data "$payload" "https://api.github.com/repos/${GH_REPOSITORY}/statuses/${CI_BUILD_SHA}" >/dev/null 2>&1; then
      printf '%s\n' "$signature" > "$STATE_FILE"
    fi
  fi
fi
