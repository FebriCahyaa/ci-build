#!/usr/bin/env bash
set -Eeuo pipefail
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPOSITORY:?GH_REPOSITORY is required}"
: "${CI_BUILD_SHA:?CI_BUILD_SHA is required}"
: "${HARNESS_EXECUTION_ID:?HARNESS_EXECUTION_ID is required}"
PERCENT="${1:?percent is required}"
STATE="${2:-pending}"
PHASE="${3:-build}"
DETAIL="${4:-working}"
CONTEXT="${CI_PROGRESS_CONTEXT:-harness-progress/${HARNESS_EXECUTION_ID}}"
TARGET_URL="${RUN_URL:-}"
STATE_FILE="${CI_PROGRESS_STATE_FILE:-${WORK_DIR:-/tmp}/.ci-progress-last}"
API="https://api.github.com/repos/${GH_REPOSITORY}/statuses/${CI_BUILD_SHA}"
[[ "$PERCENT" =~ ^[0-9]+$ ]] && ((PERCENT>=0 && PERCENT<=100)) || exit 2
DESC="[${PERCENT}%] ${PHASE}: ${DETAIL}"
DESC="${DESC:0:140}"
mkdir -p "$(dirname -- "$STATE_FILE")"
last=""
[[ -f "$STATE_FILE" ]] && last="$(cat "$STATE_FILE" 2>/dev/null || true)"
signature="${PERCENT}|${STATE}|${DESC}"
if [[ "$signature" == "$last" && -z "${CI_PROGRESS_FORCE:-}" ]]; then exit 0; fi
if [[ -f "$STATE_FILE" && -z "${CI_PROGRESS_FORCE:-}" ]]; then
  now="$(date +%s)"; mtime="$(stat -c %Y "$STATE_FILE" 2>/dev/null || echo 0)"
  (( now - mtime < 5 )) && exit 0
fi
payload="$(python3 - "$STATE" "$DESC" "$TARGET_URL" "$CONTEXT" <<'PY'
import json,sys
state,desc,target,context=sys.argv[1:5]
print(json.dumps({"state":state,"description":desc,"target_url":target or None,"context":context},separators=(",",":")))
PY
)"
if curl -fsSL --retry 2 --retry-delay 1 -X POST \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  --data "$payload" "$API" >/dev/null 2>&1; then
  printf '%s\n' "$signature" > "$STATE_FILE"
fi
exit 0
