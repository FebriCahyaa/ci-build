#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURLMOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_CAPTURE"
case "$*" in
  *releases/tags/*) printf '{"html_url":"https://github.com/FebriCahyaa/ci-build/releases/tag/test","assets":[{"name":"Kernel-lavender-sukisu-ultra.zip","browser_download_url":"https://example.invalid/a.zip"}]}' ;;
  *sendMessage*) printf '{"ok":true,"result":{"message_id":777}}' ;;
  *sendDocument*) printf '{"ok":true,"result":{"message_id":778}}' ;;
  *) printf '{"ok":true}' ;;
esac
CURLMOCK
chmod +x "$TMP/bin/curl"
CURL_CAPTURE="$TMP/calls" PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=-100123 TG_RELEASE_TOPIC_ID=5555 GITHUB_TOKEN=test GH_REPOSITORY=FebriCahyaa/ci-build RELEASE_TAG=test BUILD_PROFILE=lavender-4.4 TG_SKIP_ASSET_UPLOAD=false \
  bash "$ROOT/scripts/send_release_to_telegram.sh"
grep -q 'sendMessage' "$TMP/calls"
grep 'sendMessage' "$TMP/calls" | grep -q -- '--data-urlencode message_thread_id=5555'
grep 'sendMessage' "$TMP/calls" | grep -q 'Zairenkai Kernel Release'
grep -q 'sendDocument' "$TMP/calls"
grep 'sendDocument' "$TMP/calls" | grep -q -- '-F message_thread_id=5555'
grep 'sendDocument' "$TMP/calls" | grep -q 'Release asset'
! grep -q 'TG_TOPIC_ID' "$ROOT/scripts/send_release_to_telegram.sh"
# Release workflow must use the release topic, not the build-progress topic.
grep -q 'TG_RELEASE_TOPIC_ID:.*TG_RELEASE_TOPIC_ID' "$ROOT/.github/workflows/harness-kernel.yml" || true
echo 'PASS Telegram release topic routing and release-specific message'
