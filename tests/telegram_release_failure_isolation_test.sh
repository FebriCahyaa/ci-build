#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap '''rm -rf "$TMP"''' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURLMOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_CAPTURE"
printf '%s\n' '''{"ok":true,"result":{"message_id":1}}'''
CURLMOCK
chmod +x "$TMP/bin/curl"
cat > "$TMP/failed.json" <<'JSON'
{"status":"FAILED","error":"root provider integration failed"}
JSON
CURL_CAPTURE="$TMP/calls" PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=-1001 TG_RELEASE_TOPIC_ID=999 TG_RELEASE_REQUIRE_TOPIC=true GITHUB_TOKEN=test GH_REPOSITORY=FebriCahyaa/ci-build RELEASE_TAG=harness-failed BUILD_PROFILE=lavender-4.19 HARNESS_MONITOR_FILE="$TMP/failed.json" bash "$ROOT/scripts/send_release_to_telegram.sh"
! test -s "$TMP/calls"
echo 'PASS: failed Harness builds never relay errors to Telegram release topic'
