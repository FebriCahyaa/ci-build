#!/usr/bin/env bash
set -Eeuo pipefail
: "${TG_BOT_TOKEN:?TG_BOT_TOKEN is required}"
: "${TG_CHAT_ID:?TG_CHAT_ID is required}"
: "${TG_RELEASE_TOPIC_ID:?TG_RELEASE_TOPIC_ID is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GH_REPOSITORY:?GH_REPOSITORY is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"

API_GH="https://api.github.com"
API_TG="https://api.telegram.org/bot${TG_BOT_TOKEN}"
BUILD_PROFILE_LABEL="${BUILD_PROFILE:-unknown}"
WORK="${ASSET_DIR:-${RUNNER_TEMP:-/tmp}/harness-telegram-assets}"
mkdir -p "$WORK"; trap 'rm -rf "$WORK"' EXIT
TG_RELEASE_REQUIRE_TOPIC="${TG_RELEASE_REQUIRE_TOPIC:-true}"
html_escape(){ python3 - "$1" <<'PY'
import html,sys
print(html.escape(sys.argv[1]))
PY
}
tg_release_text(){
  local text="$1"; text="${text//$'\\n'/$'\n'}"
  [[ "$TG_RELEASE_REQUIRE_TOPIC" != true || -n "${TG_RELEASE_TOPIC_ID:-}" ]] || { echo "[telegram-release] TG_RELEASE_TOPIC_ID is required" >&2; return 1; }
  curl -fsS -X POST "$API_TG/sendMessage" --data-urlencode "chat_id=$TG_CHAT_ID" --data-urlencode "message_thread_id=$TG_RELEASE_TOPIC_ID" --data-urlencode "parse_mode=HTML" --data-urlencode "text=$text" >/dev/null
}
tg_release_file(){
  local file="$1" caption="$2"; [[ -f "$file" ]] || return 0
  curl -fsS -F "chat_id=$TG_CHAT_ID" -F "message_thread_id=$TG_RELEASE_TOPIC_ID" -F "document=@$file" -F "parse_mode=HTML" -F "caption=$caption" "$API_TG/sendDocument" >/dev/null
}
urlencode(){ python3 - "$1" <<'PY'
import sys,urllib.parse
print(urllib.parse.quote(sys.argv[1],safe=""))
PY
}
MONITOR="${HARNESS_MONITOR_FILE:-}"
STATUS="${RELEASE_STATUS:-PUBLISHED}"
ERROR=""
if [[ -n "$MONITOR" && -f "$MONITOR" ]]; then
  readarray -t values < <(python3 - "$MONITOR" <<'PY'
import json,sys
v=json.load(open(sys.argv[1],encoding="utf-8")); print(v.get("status","UNKNOWN")); print(v.get("error",""))
PY
)
  STATUS="${values[0]:-$STATUS}"; ERROR="${values[1]:-}"
  case "${STATUS^^}" in
    SUCCESS|SUCCEEDED) ;;
    *)
      echo "[telegram-release] skipping release relay for failed Harness build; failure is owned by TG_TOPIC_ID" >&2
      exit 0
      ;;
  esac
fi
TAG_ENC="$(urlencode "$RELEASE_TAG")"; RELEASE_JSON="$WORK/release.json"; release_found=false
for attempt in $(seq 1 36); do
  if curl -fsSL --retry 2 --retry-delay 2 -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$API_GH/repos/${GH_REPOSITORY}/releases/tags/${TAG_ENC}" > "$RELEASE_JSON"; then release_found=true; break; fi
  sleep 10
done
if [[ "$release_found" != true ]]; then
  tg_release_text "⚠️ <b>Zairenkai Kernel Release belum tersedia</b>\n🎯 Target: <code>$(html_escape "$BUILD_PROFILE_LABEL")</code>\n🏷 Tag: <code>$(html_escape "$RELEASE_TAG")</code>"
  [[ -n "$MONITOR" && -f "$MONITOR" ]] && tg_release_file "$MONITOR" "📄 <b>Release monitor</b> — $(html_escape "$BUILD_PROFILE_LABEL")" || true
  exit 0
fi
readarray -t relmeta < <(python3 - "$RELEASE_JSON" <<'PY'
import json,sys
v=json.load(open(sys.argv[1],encoding="utf-8")); is_pre=bool(v.get("prerelease")); print(v.get("html_url",""));
assets=[]
for a in v.get("assets",[]):
    if not isinstance(a,dict):
        continue
    name=str(a.get("name","") or "")
    if name == "handoff-HANDOFF-READY.txt" or name.startswith("staging-"):
        continue
    if is_pre:
        if not name.startswith("handoff-"):
            continue
    elif name.startswith("handoff-"):
        continue
    assets.append(a)
print(len(assets))
names=[a.get("name","") for a in assets]; variants=[]
for key,label in (("sukisu-ultra","SukiSU Ultra"),("kernelsu-next","KernelSU-Next"),("resukisu","ReSukiSU"),("kernelsu","KernelSU"),("vanilla","Vanilla")):
    if any(key in n.lower() for n in names): variants.append(label)
print(", ".join(variants) if variants else "lihat assets release")
PY
)
RELEASE_URL="${relmeta[0]:-}"; ASSET_COUNT="${relmeta[1]:-0}"; VARIANTS="${relmeta[2]:-lihat assets release}"
TG_MSG="🚀 <b>Zairenkai Kernel Release ${STATUS}</b>\n🎯 Target: <code>$(html_escape "$BUILD_PROFILE_LABEL")</code>\n🧩 Variants: <b>$(html_escape "$VARIANTS")</b>\n📦 Assets: <b>${ASSET_COUNT}</b>\n🏷 Tag: <code>$(html_escape "$RELEASE_TAG")</code>"
[[ -n "$RELEASE_URL" ]] && TG_MSG+="\n🔗 <a href=\"$(html_escape "$RELEASE_URL")\">Open GitHub Release</a>"
tg_release_text "$TG_MSG"
if [[ "${TG_SKIP_ASSET_UPLOAD:-false}" != true ]]; then
  python3 - "$RELEASE_JSON" "$WORK" <<'PY'
import json,sys,os
p=json.load(open(sys.argv[1],encoding="utf-8")); out=sys.argv[2]
is_pre=bool(p.get("prerelease"))
for a in p.get("assets",[]):
    name=a.get("name"); url=a.get("browser_download_url") or a.get("url")
    if not name or name == "handoff-HANDOFF-READY.txt" or name.startswith("staging-") or not url:
        continue
    if is_pre and not name.startswith("handoff-"):
        continue
    if not is_pre and name.startswith("handoff-"):
        continue
    open(os.path.join(out,name+".url"),"w",encoding="utf-8").write(url)
PY
  for marker in "$WORK"/*.url; do
    [[ -f "$marker" ]] || continue
    name="$(basename "$marker" .url)"; url="$(cat "$marker")"
    if ! curl -fsSL --retry 2 --retry-delay 2 -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/octet-stream" -H "X-GitHub-Api-Version: 2022-11-28" "$url" -o "$WORK/$name"; then
      tg_release_text "⚠️ <b>Asset gagal diunduh</b>\n<code>$(html_escape "$name")</code>" || true; rm -f "$WORK/$name"
    fi
  done
  rm -f "$WORK"/*.url
  for file in "$WORK"/*; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file")"; size="$(stat -c%s "$file")"
    if (( size <= 47185920 )); then
      tg_release_file "$file" "📦 <b>Release asset</b> — <code>$(html_escape "$name")</code>" || true
    else
      parts="$WORK/parts-$name"; mkdir -p "$parts"; split -b 45M -d -a 3 "$file" "$parts/${name}.part-"
      count="$(find "$parts" -maxdepth 1 -type f | wc -l | tr -d ' ')"
      tg_release_text "📦 <b>$(html_escape "$name")</b> dipecah menjadi ${count} bagian." || true
      i=1; for part in "$parts"/*; do tg_release_file "$part" "📦 <b>Release asset</b> — <code>$(html_escape "$name")</code> — part $i/$count" || true; i=$((i+1)); done
    fi
  done
fi
