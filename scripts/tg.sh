#!/usr/bin/env bash
# Telegram helper. Notifications are optional; build must still work without them.
set +u

TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT_ID="${TG_CHAT_ID:-}"
TG_TOPIC_ID="${TG_TOPIC_ID:-}"

if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
  API="https://api.telegram.org/bot${TG_BOT_TOKEN}"
  TG_ENABLED=true
else
  API=""
  TG_ENABLED=false
fi

tg_msg() {
  [[ "$TG_ENABLED" == true ]] || return 0
  curl -fsS -X POST "$API/sendMessage" \
    -d chat_id="$TG_CHAT_ID" \
    ${TG_TOPIC_ID:+-d message_thread_id="$TG_TOPIC_ID"} \
    -d parse_mode=HTML \
    -d disable_web_page_preview=true \
    --data-urlencode "text=$1" > /tmp/tg_last.json || return 0
  python3 -c 'import json; print(json.load(open("/tmp/tg_last.json")).get("result",{}).get("message_id",""))' 2>/dev/null || true
}

tg_edit() {
  [[ "$TG_ENABLED" == true ]] || return 0
  local message_id="${1:-}"
  local message="${2:-}"
  [[ -n "$message_id" ]] || return 0
  curl -fsS -X POST "$API/editMessageText" \
    -d chat_id="$TG_CHAT_ID" \
    -d message_id="$message_id" \
    -d parse_mode=HTML \
    -d disable_web_page_preview=true \
    --data-urlencode "text=$message" > /dev/null || true
}

tg_file() {
  [[ "$TG_ENABLED" == true ]] || return 0
  local file="${1:-}"
  local caption="${2:-}"
  [[ -f "$file" ]] || return 0
  curl -fsS -F chat_id="$TG_CHAT_ID" \
    ${TG_TOPIC_ID:+-F message_thread_id="$TG_TOPIC_ID"} \
    -F "document=@${file}" \
    -F parse_mode=HTML \
    -F "caption=${caption}" \
    "$API/sendDocument" > /dev/null || true
}

fmt_dur() {
  local seconds="${1:-0}"
  printf '%dm %ds' "$((seconds/60))" "$((seconds%60))"
}

# Restore caller nounset behavior after sourcing this helper.
set -u
