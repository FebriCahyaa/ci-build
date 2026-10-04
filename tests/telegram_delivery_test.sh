#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURLMOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_CAPTURE"
printf '{"ok":true,"result":{"message_id":123}}\n'
CURLMOCK
chmod +x "$TMP/bin/curl"
printf 'test zip payload\n' > "$TMP/package.zip"
CURL_CAPTURE="$TMP/calls" PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=-100123 TG_TOPIC_ID=9876 TG_MAX_RETRIES=1 \
  bash -c 'source "$1/scripts/tg.sh"; id="$(tg_msg "Target lavender-4.4")"; [[ "$id" == 123 ]]; tg_file "$2" "lavender-4.4 package"' _ "$ROOT" "$TMP/package.zip"
grep -q 'sendMessage' "$TMP/calls"
grep -q 'sendDocument' "$TMP/calls"
# Topic must be explicitly attached to both message and document requests.
grep 'sendMessage' "$TMP/calls" | grep -q -- '-d message_thread_id=9876'
grep 'sendDocument' "$TMP/calls" | grep -q -- '-F message_thread_id=9876'
# Missing required topic must fail closed rather than falling back to General.
if CURL_CAPTURE="$TMP/no-topic-calls" PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=-100123 TG_TOPIC_ID= TG_REQUIRE_TOPIC=true \
  bash -c 'source "$1/scripts/tg.sh"; tg_msg "must not go to General"' _ "$ROOT"; then
  echo 'ERROR: missing topic unexpectedly succeeded' >&2
  exit 1
fi
test ! -s "$TMP/no-topic-calls"
printf 'PASS Telegram topic routing, fail-closed behavior, and document upload contract\n' 
