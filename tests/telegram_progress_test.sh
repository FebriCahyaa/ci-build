#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/work"
cat > "$TMP/bin/curl" <<'CURLMOCK'
#!/usr/bin/env bash
set -e
case "$*" in
  *'/sendMessage'*) printf '{"ok":true,"result":{"message_id":777}}\n' ;;
  *'/editMessageText'*)
    if [[ -f "$CURL_STATE" ]]; then
      printf '{"ok":true,"result":{}}\n'
    else
      : > "$CURL_STATE"
      printf 'simulated network failure\n' >&2
      exit 28
    fi
    ;;
  *) printf '{"ok":true,"result":{}}\n' ;;
esac
CURLMOCK
chmod +x "$TMP/bin/curl"
printf '[CC] foo.o\nhello <kernel> & world\n' > "$TMP/work/build.log"
CURL_STATE="$TMP/curl-state" PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=123 TG_MESSAGE_ID=777 TG_START_TIME="$(date +%s)" TG_MAX_RETRIES=1 \
WORK_DIR="$TMP/work" BUILD_LOG="$TMP/work/build.log" DEVICE=garnet ROOT_VARIANT=vanilla VARIANT_LABEL=Vanilla \
  bash -c 'source "$1/scripts/tg.sh"; tg_progress_update 44 pending compile "objects 1/2" "$BUILD_LOG"' _ "$ROOT" || true
! test -f "$TMP/work/.tg-progress-last"

CURL_STATE="$TMP/curl-state" PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=123 TG_MESSAGE_ID=777 TG_START_TIME="$(date +%s)" \
WORK_DIR="$TMP/work" BUILD_LOG="$TMP/work/build.log" DEVICE=garnet ROOT_VARIANT=vanilla VARIANT_LABEL=Vanilla \
  bash -c 'source "$1/scripts/tg.sh"; tg_progress_update 45 pending compile "objects 2/2" "$BUILD_LOG"' _ "$ROOT"
test -f "$TMP/work/.tg-progress-last"
PATH="$TMP/bin:$PATH" TG_BOT_TOKEN=test TG_CHAT_ID=123 TG_MESSAGE_ID=777 TG_START_TIME="$(date +%s)" \
WORK_DIR="$TMP/work" BUILD_LOG="$TMP/work/build.log" DEVICE=garnet ROOT_VARIANT=vanilla VARIANT_LABEL=Vanilla \
  GH_TOKEN= GH_REPOSITORY= CI_BUILD_SHA= "$ROOT/scripts/progress_beacon.sh" 45 pending compile 'objects 2/2'
printf 'PASS telegram progress helper\n'
