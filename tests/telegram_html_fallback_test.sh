#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURLMOCK'
#!/usr/bin/env bash
if [[ "$*" == *"/sendMessage"* ]]; then
  if [[ "$*" == *"parse_mode=HTML"* ]]; then
    printf '%s\n' '{"ok":false,"error_code":400,"description":"Bad Request: can'"'"'t parse entities: malformed tag"}'
  else
    printf '%s\n' '{"ok":true,"result":{"message_id":4242}}'
  fi
else
  printf '%s\n' '{"ok":true,"result":{}}'
fi
CURLMOCK
chmod +x "$TMP/bin/curl"
PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=-1001 TG_MAX_RETRIES=1 TG_RELEASE_TOPIC_ID=999 \
  bash -c 'source "$1/scripts/tg.sh"; id="$(tg_msg "<b>this is malformed & unsafe</b>")"; [[ "$id" == 4242 ]]' _ "$ROOT"
printf 'PASS Telegram malformed-HTML plain-text fallback\n'
