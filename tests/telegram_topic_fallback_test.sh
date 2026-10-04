#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURLMOCK'
#!/usr/bin/env bash
set -e
# HTML to primary topic: entity error.
if [[ "$*" == *"/sendMessage"* && "$*" == *"parse_mode=HTML"* && "$*" == *"message_thread_id=111"* ]]; then
  printf '%s\n' '{"ok":false,"error_code":400,"description":"Bad Request: can'"'"'t parse entities"}'
  exit 0
fi
# Plain to primary topic: simulate stale/bad topic.
if [[ "$*" == *"/sendMessage"* && "$*" == *"message_thread_id=111"* && "$*" != *"parse_mode=HTML"* ]]; then
  printf '%s\n' '{"ok":false,"error_code":400,"description":"Bad Request: message thread not found"}'
  exit 0
fi
# Fallback release topic succeeds.
if [[ "$*" == *"/sendMessage"* && "$*" == *"message_thread_id=999"* ]]; then
  printf '%s\n' '{"ok":true,"result":{"message_id":4242}}'
  exit 0
fi
# Document fallback to release topic succeeds.
if [[ "$*" == *"/sendDocument"* && "$*" == *"message_thread_id=111"* ]]; then
  printf '%s\n' '{"ok":false,"error_code":400,"description":"Bad Request: message thread not found"}'
  exit 0
fi
if [[ "$*" == *"/sendDocument"* && "$*" == *"message_thread_id=999"* ]]; then
  printf '%s\n' '{"ok":true,"result":{}}'
  exit 0
fi
printf '%s\n' '{"ok":true,"result":{"message_id":1}}'
CURLMOCK
chmod +x "$TMP/bin/curl"

PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=-1001 TG_TOPIC_ID=111 TG_RELEASE_TOPIC_ID=999 TG_REQUIRE_TOPIC=true TG_MAX_RETRIES=1 \
  bash -c 'source "$1/scripts/tg.sh"; id="$(tg_msg "<b>malformed & unsafe</b>")"; [[ "$id" == 4242 ]]' _ "$ROOT"

echo x > "$TMP/sample.txt"
PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=-1001 TG_TOPIC_ID=111 TG_RELEASE_TOPIC_ID=999 TG_REQUIRE_TOPIC=true TG_MAX_RETRIES=1 \
  bash -c 'source "$1/scripts/tg.sh"; tg_send_document_once "$2/sample.txt" "test"' _ "$ROOT" "$TMP"
printf 'PASS: Telegram primary-topic fallback\n'
