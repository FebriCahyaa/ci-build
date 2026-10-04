#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURLMOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_CAPTURE"
printf '{"ok":true,"result":{"message_id":999}}\n'
CURLMOCK
chmod +x "$TMP/bin/curl"
cat > "$TMP/monitor.json" <<'JSON'
{
  "plan_execution_id": "pe-test",
  "status": "FAILED",
  "stage": "Kernel Build",
  "step": "Build Universal Kernel Matrix",
  "error": "source patch series failed",
  "completion_source": "harness_api"
}
JSON
CURL_CAPTURE="$TMP/calls" PATH="$TMP/bin:$PATH" \
  TG_BOT_TOKEN=test TG_CHAT_ID=-100123 TG_TOPIC_ID=13 \
  BUILD_PROFILE=lavender-4.19 HARNESS_MONITOR_FILE="$TMP/monitor.json" \
  HARNESS_RUN_URL=https://example.invalid/harness \
  bash "$ROOT/scripts/send_harness_failure_to_telegram.sh"
grep -q 'sendMessage' "$TMP/calls"
grep -q -- 'message_thread_id=13' "$TMP/calls"
grep -q 'source patch series failed' "$TMP/calls"
# Line breaks must be real newlines, not a literal backslash-n in the message.
! grep -qF '\n' "$TMP/calls" || { echo 'FAIL: literal \n sent to Telegram' >&2; exit 1; }

CURL_CAPTURE="$TMP/calls-missing" PATH="$TMP/bin:$PATH" \
  TG_BOT_TOKEN=test TG_CHAT_ID=-100123 TG_TOPIC_ID=13 \
  BUILD_PROFILE=lavender-4.19 HARNESS_MONITOR_FILE="$TMP/no-monitor.json" \
  bash "$ROOT/scripts/send_harness_failure_to_telegram.sh"
grep -q 'sendMessage' "$TMP/calls-missing"

cat > "$TMP/success.json" <<'JSON'
{"status":"SUCCEEDED","plan_execution_id":"pe-ok"}
JSON
: > "$TMP/calls-success"
CURL_CAPTURE="$TMP/calls-success" PATH="$TMP/bin:$PATH" \
  TG_BOT_TOKEN=test TG_CHAT_ID=-100123 TG_TOPIC_ID=13 \
  BUILD_PROFILE=lavender-4.19 HARNESS_MONITOR_FILE="$TMP/success.json" \
  bash "$ROOT/scripts/send_harness_failure_to_telegram.sh"
! test -s "$TMP/calls-success"

# Telegram is optional: without credentials the relay is a successful no-op.
: > "$TMP/calls-unconfigured"
CURL_CAPTURE="$TMP/calls-unconfigured" PATH="$TMP/bin:$PATH" TG_BOT_TOKEN= TG_CHAT_ID= TG_TOPIC_ID= \
  HARNESS_MONITOR_FILE="$TMP/monitor.json" bash "$ROOT/scripts/send_harness_failure_to_telegram.sh"
! test -s "$TMP/calls-unconfigured"

echo 'PASS Telegram Harness failure fallback'
