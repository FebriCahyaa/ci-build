#!/usr/bin/env bash
set -Eeuo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPOSITORY:?GH_REPOSITORY is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"
: "${ASSET_DIR:?ASSET_DIR is required}"

RELEASE_NAME="${RELEASE_NAME:-Harness Kernel Build ${RELEASE_TAG}}"
API="https://api.github.com"
AUTH=(
  -H "Authorization: Bearer ${GH_TOKEN}"
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

urlencode() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

mkdir -p "$ASSET_DIR"
TAG_ENC="$(urlencode "$RELEASE_TAG")"
JSON_FILE="$(mktemp)"
trap 'rm -f "$JSON_FILE"' EXIT

if ! curl -fsSL "${AUTH[@]}" \
    "$API/repos/${GH_REPOSITORY}/releases/tags/${TAG_ENC}" > "$JSON_FILE"; then
  curl -fsSL -X POST "${AUTH[@]}" \
    -H "Content-Type: application/json" \
    "$API/repos/${GH_REPOSITORY}/releases" \
    --data "$(python3 - "$RELEASE_TAG" "$RELEASE_NAME" <<'PY'
import json, sys
print(json.dumps({"tag_name":sys.argv[1],"name":sys.argv[2],"body":"Artifacts from ci-build Harness execution.","draft":False,"prerelease":True}))
PY
)" > "$JSON_FILE"
fi

UPLOAD_URL="$(python3 - "$JSON_FILE" <<'PY'
import json,sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("upload_url", "").split("{",1)[0])
PY
)"
[[ -n "$UPLOAD_URL" ]] || { echo "ERROR: release upload URL missing" >&2; exit 1; }

shopt -s nullglob
found=false
for file in "$ASSET_DIR"/*; do
  [[ -f "$file" ]] || continue
  found=true
  name="$(basename "$file")"
  encoded="$(urlencode "$name")"
  echo "[release] uploading $name"
  curl -fsSL -X POST "${AUTH[@]}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$file" \
    "${UPLOAD_URL}?name=${encoded}" >/dev/null
 done

[[ "$found" == true ]] || { echo "ERROR: no assets to publish" >&2; exit 1; }
