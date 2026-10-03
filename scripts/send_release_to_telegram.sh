#!/usr/bin/env bash
set -Eeuo pipefail

: "${TG_BOT_TOKEN:?TG_BOT_TOKEN is required}"
: "${TG_CHAT_ID:?TG_CHAT_ID is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GH_REPOSITORY:?GH_REPOSITORY is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"

API_GH="https://api.github.com"
API_TG="https://api.telegram.org/bot${TG_BOT_TOKEN}"
WORK="${ASSET_DIR:-$RUNNER_TEMP/harness-telegram-assets}"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

tg_text() {
  local text="$1"

  # Convert literal "\\n" sequences to real newlines before sending.
  text="${text//$'\\n'/$'\n'}"

  local args=(--data-urlencode "chat_id=$TG_CHAT_ID" --data-urlencode "text=$text" -d "parse_mode=HTML")
  [[ -n "${TG_TOPIC_ID:-}" ]] && args+=(-d "message_thread_id=$TG_TOPIC_ID")
  curl -fsS -X POST "$API_TG/sendMessage" "${args[@]}" >/dev/null || true
}

tg_file() {
  local file="$1"
  local caption="$2"
  [[ -f "$file" ]] || return 0
  if [[ -n "${TG_TOPIC_ID:-}" ]]; then
    curl -fsS -F "chat_id=$TG_CHAT_ID" -F "message_thread_id=$TG_TOPIC_ID" \
      -F "document=@$file" -F "parse_mode=HTML" -F "caption=$caption" \
      "$API_TG/sendDocument" >/dev/null
  else
    curl -fsS -F "chat_id=$TG_CHAT_ID" -F "document=@$file" \
      -F "parse_mode=HTML" -F "caption=$caption" \
      "$API_TG/sendDocument" >/dev/null
  fi
}

urlencode() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

MONITOR="${HARNESS_MONITOR_FILE:-harness-monitor.json}"
STATUS="UNKNOWN"
ERROR=""
if [[ -f "$MONITOR" ]]; then
  readarray -t values < <(python3 - "$MONITOR" <<'PY'
import json,sys
v=json.load(open(sys.argv[1], encoding="utf-8"))
print(v.get("status","UNKNOWN"))
print(v.get("error",""))
PY
)
  STATUS="${values[0]:-UNKNOWN}"
  ERROR="${values[1]:-}"
fi

TAG_ENC="$(urlencode "$RELEASE_TAG")"
RELEASE_JSON="$WORK/release.json"

release_found=false
for attempt in $(seq 1 36); do
  if curl -fsSL --retry 2 --retry-delay 2 \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$API_GH/repos/${GH_REPOSITORY}/releases/tags/${TAG_ENC}" > "$RELEASE_JSON"; then
    release_found=true
    break
  fi
  sleep 10
done

if [[ "$release_found" != true ]]; then
  tg_text "❌ <b>Harness Build</b>\nRelease artifact belum tersedia setelah 6 menit: <code>$RELEASE_TAG</code>"
  [[ -f "$MONITOR" ]] && tg_file "$MONITOR" "📄 Harness monitor result" || true
  exit 0
fi

RELEASE_URL="$(python3 - "$RELEASE_JSON" <<'PY'
import json,sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("html_url",""))
PY
)"

python3 - "$RELEASE_JSON" "$WORK" <<'PY'
import json,sys,os
p=json.load(open(sys.argv[1], encoding="utf-8"))
out=sys.argv[2]
for a in p.get("assets",[]):
    name=a.get("name")
    url=a.get("browser_download_url") or a.get("url")
    if name and url:
        open(os.path.join(out,name+".url"),"w",encoding="utf-8").write(url)
PY

for marker in "$WORK"/*.url; do
  [[ -f "$marker" ]] || continue
  name="$(basename "$marker" .url)"
  url="$(cat "$marker")"
  echo "[telegram-relay] downloading asset: $name"
  if ! curl -fsSL --retry 2 --retry-delay 2 \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/octet-stream" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url" -o "$WORK/$name"; then
    tg_text "⚠️ <b>Asset gagal diunduh</b>\n<code>$name</code>" || true
    rm -f "$WORK/$name"
  fi
done
rm -f "$WORK"/*.url

tg_text "📦 <b>Harness Build ${STATUS}</b>\n🔗 <a href=\"${RELEASE_URL}\">GitHub Release</a>"
[[ -n "$ERROR" ]] && tg_text "⚠️ <b>Error</b>\n<code>$(printf '%s' "$ERROR" | cut -c1-1200)</code>" || true

for file in "$WORK"/*; do
  [[ -f "$file" ]] || continue
  name="$(basename "$file")"
  size="$(stat -c%s "$file")"
  if (( size <= 47185920 )); then
    tg_file "$file" "📎 <code>$name</code>" || true
  else
    parts="$WORK/parts-$name"
    mkdir -p "$parts"
    split -b 45M -d -a 3 "$file" "$parts/${name}.part-"
    count="$(find "$parts" -maxdepth 1 -type f | wc -l | tr -d ' ')"
    tg_text "📦 <b>$name</b> dipecah menjadi $count bagian karena ukuran file."
    i=1
    for part in "$parts"/*; do
      tg_file "$part" "📦 $name — part $i/$count" || true
      i=$((i+1))
    done
  fi
done
