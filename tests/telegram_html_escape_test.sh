#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURLMOCK'
#!/usr/bin/env bash
case "$*" in
  */sendMessage*) printf '%s\n' '{"ok":true,"result":{"message_id":123}}' ;;
  *) printf '%s\n' '{"ok":true,"result":{}}' ;;
esac
CURLMOCK
chmod +x "$TMP/bin/curl"

url='https://app.harness.io/ng/account/a/module/ci/orgs/default/projects/p/pipelines/Universal_Kernel_Build/executions/x/pipeline?serviceRef=a&stageRef=b&executionInputs=true'
PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=-1001 TG_MAX_RETRIES=1 \
  bash -c 'source "$1/scripts/tg.sh"; v="$(tg_escape_html "$2")"; [[ "$v" == *"&amp;"* ]]; [[ "$v" != *"&serviceRef"* ]]; tg_msg "<a href=\"$v\">Harness</a>"' _ "$ROOT" "$url"

# Guard every build-side explicit href that uses RUN_URL through the escaped value.
! grep -nE '<a href=\\?"\$RUN_URL|<a href=\\?"\$\{RUN_URL' "$ROOT/scripts/build_kernel.sh"
! grep -nE '<a href=\\?"\$RUN_URL|<a href=\\?"\$\{RUN_URL' "$ROOT/scripts/send_harness_failure_to_telegram.sh"
printf 'PASS Telegram HTML URL escaping contract\n'
