#!/usr/bin/env bash
# Independent Harness failure notification. It does not depend on release handoff.
set -Eeuo pipefail

: "${TG_BOT_TOKEN:?TG_BOT_TOKEN is required}"
: "${TG_CHAT_ID:?TG_CHAT_ID is required}"

MONITOR="${HARNESS_MONITOR_FILE:-harness-monitor.json}"
PROFILE="${BUILD_PROFILE:-unknown}"
RUN_URL="${HARNESS_RUN_URL:-}"
ESCAPED_RUN_URL="$(python3 - "$RUN_URL" <<'PYESC_URL'
import html,sys
print(html.escape(sys.argv[1], quote=True), end="")
PYESC_URL
)"

if [[ ! -f "$MONITOR" ]]; then
  API="https://api.telegram.org/bot${TG_BOT_TOKEN}"
  escaped_profile="$(python3 - "$PROFILE" <<'PYESC0'
import html,sys
print(html.escape(sys.argv[1]), end='')
PYESC0
)"
  text="❌ <b>Zairenkai Harness Kernel Build gagal</b>\n🎯 Target: <code>${escaped_profile}</code>\n🚨 <code>harness-monitor.json tidak tersedia; cek GitHub Actions run untuk detail.</code>"
  [[ -n "$RUN_URL" ]] && text+="\n🔗 <a href=\"$ESCAPED_RUN_URL\">Harness CI log</a>"
  send_missing() {
    local topic="${1:-}"
    local -a args=(--data-urlencode "chat_id=$TG_CHAT_ID" --data-urlencode "parse_mode=HTML" --data-urlencode "disable_web_page_preview=true" --data-urlencode "text=$text")
    [[ -n "$topic" ]] && args+=(--data-urlencode "message_thread_id=$topic")
    curl -fsS --retry 4 --retry-delay 2 -X POST "$API/sendMessage" "${args[@]}" > /tmp/tg_failure_response.json 2>/dev/null || return 1
    python3 - <<'PY2'
import json,sys
try:
    d=json.load(open('/tmp/tg_failure_response.json', encoding='utf-8'))
except Exception:
    sys.exit(1)
sys.exit(0 if d.get('ok') is True else 1)
PY2
  }
  if send_missing "${TG_RELEASE_TOPIC_ID:-}" || send_missing ""; then
    echo "[telegram-fallback] sent missing-monitor failure notification" >&2
  else
    echo "[telegram-fallback] ERROR: unable to deliver missing-monitor failure notification" >&2
    exit 1
  fi
  exit 0
fi

readarray -t fields < <(python3 - "$MONITOR" <<'PYJSON'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
for k in ('status','stage','step','error','plan_execution_id','completion_source'):
    print(str(p.get(k,'') or ''))
PYJSON
)
status="${fields[0]:-UNKNOWN}"
stage="${fields[1]:-}"
step="${fields[2]:-}"
error="${fields[3]:-}"
plan="${fields[4]:-}"
source="${fields[5]:-}"

case "${status^^}" in
  SUCCESS|SUCCEEDED) exit 0 ;;
esac

html_escape() {
  python3 - "$1" <<'PYESC'
import html,sys
print(html.escape(sys.argv[1]), end='')
PYESC
}

text="❌ <b>Zairenkai Harness Kernel Build Gagal</b>\n"
text+="🎯 Target: <code>$(html_escape "$PROFILE")</code>\n"
[[ -n "$stage" ]] && text+="🏗 Stage: <code>$(html_escape "$stage")</code>\n"
[[ -n "$step" ]] && text+="🧩 Step: <code>$(html_escape "$step")</code>\n"
text+="📌 Status: <code>$(html_escape "$status")</code>\n"
[[ -n "$plan" ]] && text+="🆔 Execution: <code>$(html_escape "$plan")</code>\n"
[[ -n "$source" ]] && text+="🔎 Source: <code>$(html_escape "$source")</code>\n"
[[ -n "$error" ]] && text+="🚨 Error: <code>$(html_escape "${error:0:1800}")</code>\n"
[[ -n "$RUN_URL" ]] && text+="🔗 <a href=\"$ESCAPED_RUN_URL\">Harness CI log</a>"

API="https://api.telegram.org/bot${TG_BOT_TOKEN}"

send_failure() {
  local topic="${1:-}" plain="${2:-false}"
  local -a args=(--data-urlencode "chat_id=$TG_CHAT_ID" --data-urlencode "disable_web_page_preview=true")
  [[ -n "$topic" ]] && args+=(--data-urlencode "message_thread_id=$topic")
  if [[ "$plain" == true ]]; then
    args+=(--data-urlencode "text=$(printf '%s' "$text" | sed -E 's/<[^>]+>//g')")
  else
    args+=(--data-urlencode "parse_mode=HTML" --data-urlencode "text=$text")
  fi
  curl -fsS --retry 4 --retry-delay 2 -X POST "$API/sendMessage" "${args[@]}" > /tmp/tg_failure_response.json 2>/dev/null || return 1
  python3 - <<'PY'
import json
import sys
try:
    d=json.load(open('/tmp/tg_failure_response.json', encoding='utf-8'))
except Exception:
    sys.exit(1)
sys.exit(0 if d.get('ok') is True else 1)
PY
}

if send_failure "${TG_RELEASE_TOPIC_ID:-}" false || \
   send_failure "${TG_RELEASE_TOPIC_ID:-}" true || \
   send_failure "" true; then
  echo "[telegram-fallback] sent Harness failure notification for $PROFILE status=$status"
else
  echo "[telegram-fallback] ERROR: unable to deliver Harness failure notification" >&2
  exit 1
fi
