#!/usr/bin/env bash
set -Eeuo pipefail
PERCENT="${1:?percent is required}"
STATE="${2:-pending}"
PHASE="${3:-build}"
DETAIL="${4:-working}"
[[ "$PERCENT" =~ ^[0-9]+$ ]] && ((PERCENT>=0 && PERCENT<=100)) || exit 2

if [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" && -n "${TG_MESSAGE_ID:-}" ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/tg.sh"
  TG_MESSAGE_ID="$TG_MESSAGE_ID" \
  TG_START_TIME="${TG_START_TIME:-$(date +%s)}" \
  TG_PROGRESS_STATE_FILE="${CI_PROGRESS_STATE_FILE:-${WORK_DIR:-/tmp}/.tg-progress-last}" \
  BUILD_LOG="${BUILD_LOG:-${WORK_DIR:-/tmp}/build.log}" \
    tg_progress_update "$PERCENT" "$STATE" "$PHASE" "$DETAIL" "$BUILD_LOG" || true
fi

if [[ -n "${GH_TOKEN:-}" && -n "${GH_REPOSITORY:-}" && -n "${CI_BUILD_SHA:-}" ]]; then
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
