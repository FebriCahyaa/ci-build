#!/usr/bin/env bash
# Remove temporary Harness handoff/staging assets after GitHub Actions has
# materialized the release and completed the Telegram relay.
set -Eeuo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPOSITORY:?GH_REPOSITORY is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"
CLEAN_PREFIXES="${CLEAN_PREFIXES:-handoff-,staging-}"
API="${GITHUB_API:-https://api.github.com}"
AUTH=(
  -H "Authorization: Bearer ${GH_TOKEN}"
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

urlencode() { python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

TAG_ENC="$(urlencode "$RELEASE_TAG")"
JSON="$(mktemp)"
trap 'rm -f "$JSON" "${ASSETS_JSON:-}"' EXIT
curl -fsSL --retry 4 --retry-delay 2 "${AUTH[@]}" \
  "$API/repos/${GH_REPOSITORY}/releases/tags/${TAG_ENC}" > "$JSON"
RELEASE_ID="$(python3 - "$JSON" <<'PY'
import json,sys
r=json.load(open(sys.argv[1],encoding='utf-8'))
if bool(r.get('draft')) or bool(r.get('prerelease')):
    print('')
else:
    print(r.get('id',''))
PY
)"
if [[ -z "$RELEASE_ID" ]]; then
  echo "[release-cleanup] release is still draft/prerelease; preserving handoff assets"
  exit 0
fi
ASSETS_JSON="$(mktemp)"
curl -fsSL --retry 4 --retry-delay 2 "${AUTH[@]}" \
  "$API/repos/${GH_REPOSITORY}/releases/${RELEASE_ID}/assets?per_page=100" > "$ASSETS_JSON"

removed=0
while IFS=$'\t' read -r asset_id asset_name; do
  [[ -n "$asset_id" && -n "$asset_name" ]] || continue
  remove=false
  IFS=',' read -ra prefixes <<< "$CLEAN_PREFIXES"
  for prefix in "${prefixes[@]}"; do
    [[ "$asset_name" == "$prefix"* ]] && remove=true && break
  done
  [[ "$remove" == true ]] || continue
  echo "[release-cleanup] removing $asset_name"
  curl -fsSL --retry 4 --retry-delay 2 -X DELETE "${AUTH[@]}" \
    "$API/repos/${GH_REPOSITORY}/releases/assets/${asset_id}" >/dev/null
  removed=$((removed + 1))
done < <(python3 - "$ASSETS_JSON" <<'PY'
import json,sys
for a in json.load(open(sys.argv[1], encoding='utf-8')):
    print(f"{a.get('id','')}\t{a.get('name','')}")
PY
)

echo "[release-cleanup] removed=$removed tag=$RELEASE_TAG"
