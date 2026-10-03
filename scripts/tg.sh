#!/usr/bin/env bash
# Helper Telegram. Wajib: TG_BOT_TOKEN, TG_CHAT_ID. Opsional: TG_TOPIC_ID
API="https://api.telegram.org/bot${TG_BOT_TOKEN}"

tg_msg() {
  curl -s -X POST "$API/sendMessage" \
    -d chat_id="$TG_CHAT_ID" ${TG_TOPIC_ID:+-d message_thread_id="$TG_TOPIC_ID"} \
    -d parse_mode=HTML -d disable_web_page_preview=true \
    --data-urlencode text="$1" > /tmp/tg_last.json
  python3 -c 'import json;print(json.load(open("/tmp/tg_last.json")).get("result",{}).get("message_id",""))' 2>/dev/null || true
}

tg_edit() { # $1=message_id $2=text
  curl -s -X POST "$API/editMessageText" \
    -d chat_id="$TG_CHAT_ID" -d message_id="$1" \
    -d parse_mode=HTML -d disable_web_page_preview=true \
    --data-urlencode text="$2" > /dev/null
}

tg_file() { # $1=file $2=caption
  curl -s -F chat_id="$TG_CHAT_ID" ${TG_TOPIC_ID:+-F message_thread_id="$TG_TOPIC_ID"} \
    -F document=@"$1" -F parse_mode=HTML -F caption="$2" \
    "$API/sendDocument" > /dev/null
}

fmt_dur() { printf '%dm %ds' $(($1/60)) $(($1%60)); }
