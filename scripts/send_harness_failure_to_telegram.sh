#!/usr/bin/env bash
# Independent Harness failure notification. It does not depend on release handoff.
set -Eeuo pipefail

: "${TG_BOT_TOKEN:?TG_BOT_TOKEN is required}"
: "${TG_CHAT_ID:?TG_CHAT_ID is required}"
: "${TG_RELEASE_TOPIC_ID:?TG_RELEASE_TOPIC_ID is required}"

MONITOR="${HARNESS_MONITOR_FILE:-harness-monitor.json}"
PROFILE="${BUILD_PROFILE:-unknown}"
RUN_URL="${HARNESS_RUN_URL:-}"

if [[ ! -f "$MONITOR" ]]; then
  API="https://api.telegram.org/bot${TG_BOT_TOKEN}"
  escaped_profile="$(python3 - "$PROFILE" <<'PYESC0'
import html,sys
print(html.escape(sys.argv[1]), end='')
PYESC0
)"
  text="❌ <b>Zairenkai Harness Kernel Build gagal</b>\n🎯 Target: <code>${escaped_profile}</code>\n🚨 <code>harness-monitor.json tidak tersedia; cek GitHub Actions run untuk detail.</code>"
  [[ -n "$RUN_URL" ]] && text+="\n🔗 <a href=\"$RUN_URL\">Harness CI log</a>"
  curl -fsS --retry 4 --retry-delay 2 -X POST "$API/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "message_thread_id=$TG_RELEASE_TOPIC_ID" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" \
    --data-urlencode "text=$text" >/dev/null
  echo "[telegram-fallback] sent missing-monitor failure notification" >&2
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
[[ -n "$RUN_URL" ]] && text+="🔗 <a href=\"$RUN_URL\">Harness CI log</a>"

API="https://api.telegram.org/bot${TG_BOT_TOKEN}"
curl -fsS --retry 4 --retry-delay 2 -X POST "$API/sendMessage" \
  --data-urlencode "chat_id=$TG_CHAT_ID" \
  --data-urlencode "message_thread_id=$TG_RELEASE_TOPIC_ID" \
  --data-urlencode "parse_mode=HTML" \
  --data-urlencode "disable_web_page_preview=true" \
  --data-urlencode "text=$text" >/dev/null

echo "[telegram-fallback] sent Harness failure notification for $PROFILE status=$status"
