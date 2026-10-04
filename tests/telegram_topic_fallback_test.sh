#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURLMOCK'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$CURL_CAPTURE"
# Primary build topic succeeds.
if [[ "$*" == *"/sendMessage"* && "$*" == *"message_thread_id=111"* ]]; then
  printf '%s\n' '{"ok":true,"result":{"message_id":4242}}'
  exit 0
fi
if [[ "$*" == *"/sendDocument"* && "$*" == *"message_thread_id=111"* ]]; then
  printf '%s\n' '{"ok":true,"result":{}}'
  exit 0
fi
# Any attempt to use release topic is a test failure.
if [[ "$*" == *"message_thread_id=999"* ]]; then
  printf '%s\n' '{"ok":false,"error_code":400,"description":"release topic must not be used by build helper"}'
  exit 0
fi
printf '%s\n' '{"ok":true,"result":{"message_id":1}}'
CURLMOCK
chmod +x "$TMP/bin/curl"

CURL_CAPTURE="$TMP/calls" PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=-1001 TG_TOPIC_ID=111 TG_RELEASE_TOPIC_ID=999 TG_REQUIRE_TOPIC=true TG_MAX_RETRIES=1 \
  bash -c 'source "$1/scripts/tg.sh"; id="$(tg_msg "<b>build progress</b>")"; [[ "$id" == 4242 ]]' _ "$ROOT"

echo x > "$TMP/sample.txt"
CURL_CAPTURE="$TMP/calls" PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=-1001 TG_TOPIC_ID=111 TG_RELEASE_TOPIC_ID=999 TG_REQUIRE_TOPIC=true TG_MAX_RETRIES=1 \
  bash -c 'source "$1/scripts/tg.sh"; tg_send_document_once "$2/sample.txt" "test"' _ "$ROOT" "$TMP"

! grep -q 'message_thread_id=999' "$TMP/calls"
echo 'PASS: Telegram build helper never falls back to release topic'
