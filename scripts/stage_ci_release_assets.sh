#!/usr/bin/env bash
# Stage build artifacts into a per-execution draft GitHub Release.
# Used by Harness so successful matrix variants remain downloadable even when
# another variant fails later. Final publishing reuses the same tag.
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
CI_LOG_TAG=release-stage

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPOSITORY:?GH_REPOSITORY is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"
ASSET_DIR="${ASSET_DIR:-}"
[[ -n "$ASSET_DIR" && -d "$ASSET_DIR" ]] || ci_die "ASSET_DIR is required and must exist"
ASSET_PREFIX="${ASSET_PREFIX:-}"

API="${GITHUB_API:-https://api.github.com}"
AUTH=(
  -H "Authorization: Bearer ${GH_TOKEN}"
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

urlencode() {
  python3 - "$1" <<'PY'
import urllib.parse, sys
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

TAG_ENC="$(urlencode "$RELEASE_TAG")"
STATE_DIR="${CI_RELEASE_STATE_DIR:-${RUNNER_TEMP:-/tmp}}"
mkdir -p "$STATE_DIR"
LOCK_FILE="$STATE_DIR/zairenkai-release-${GH_REPOSITORY//\//_}-${RELEASE_TAG//[^A-Za-z0-9_.-]/_}.lock"
RELEASE_JSON="$STATE_DIR/zairenkai-release.json"

ensure_release() {
  # Serialise create/update so parallel matrix variants cannot race on release creation.
  flock -x 9
  if curl -fsSL "${AUTH[@]}" "$API/repos/${GH_REPOSITORY}/releases/tags/${TAG_ENC}" -o "$RELEASE_JSON" 2>/dev/null; then
    :
  else
    body="$(python3 - "$RELEASE_TAG" <<'PY'
import json, sys
print(json.dumps({
    "tag_name": sys.argv[1],
    "name": "Zairenkai CI — " + sys.argv[1],
    "body": "CI staging release. Artifacts are uploaded as each variant completes.",
    "draft": True,
    "prerelease": False,
}, separators=(",", ":")))
PY
)"
    curl -fsSL -X POST "${AUTH[@]}" -H 'Content-Type: application/json' \
      "$API/repos/${GH_REPOSITORY}/releases" --data "$body" -o "$RELEASE_JSON"
  fi
  flock -u 9
}

exec 9>"$LOCK_FILE"
ensure_release

RELEASE_ID="$(python3 - "$RELEASE_JSON" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding='utf-8'))['id'])
PY
)"
UPLOAD_URL="$(python3 - "$RELEASE_JSON" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding='utf-8')).get('upload_url','').split('{',1)[0])
PY
)"
[[ -n "$RELEASE_ID" && -n "$UPLOAD_URL" ]] || ci_die "release metadata is incomplete"

shopt -s nullglob
assets=("$ASSET_DIR"/*.zip "$ASSET_DIR"/*.tar.gz "$ASSET_DIR"/*.md "$ASSET_DIR"/*.txt "$ASSET_DIR"/*.gz)
# Deduplicate overlapping globs (for example *.tar.gz also matches *.gz).
unique_assets=()
declare -A seen_asset=()
for file in "${assets[@]}"; do
  [[ -f "$file" ]] || continue
  name="$(basename "$file")"
  [[ -n "${seen_asset[$name]:-}" ]] && continue
  seen_asset[$name]=1
  unique_assets+=("$file")
done
assets=("${unique_assets[@]}")
((${#assets[@]} > 0)) || { echo "[release-stage] no assets in $ASSET_DIR" >&2; exit 0; }

for file in "${assets[@]}"; do
  [[ -f "$file" ]] || continue
  base_name="$(basename "$file")"
  if [[ -n "$ASSET_PREFIX" ]]; then
    name="${ASSET_PREFIX}-${base_name}"
  else
    name="$base_name"
  fi
  encoded="$(urlencode "$name")"

  # Remove a previous same-named asset before replacement.
  assets_json="$(curl -fsSL "${AUTH[@]}" "$API/repos/${GH_REPOSITORY}/releases/${RELEASE_ID}/assets?per_page=100")"
  asset_id="$(python3 - "$assets_json" "$name" <<'PY'
import json, sys
for item in json.loads(sys.argv[1]):
    if item.get('name') == sys.argv[2]:
        print(item.get('id',''))
        break
PY
)"
  if [[ -n "$asset_id" ]]; then
    curl -fsSL -X DELETE "${AUTH[@]}" "$API/repos/${GH_REPOSITORY}/releases/assets/${asset_id}" >/dev/null
  fi

  echo "[release-stage] uploading $name"
  curl -fsSL -X POST "${AUTH[@]}" \
    -H 'Content-Type: application/octet-stream' \
    --data-binary "@$file" \
    "${UPLOAD_URL}?name=${encoded}" >/dev/null
 done

printf '%s\n' "[release-stage] staged $((${#assets[@]})) asset(s) into draft $RELEASE_TAG"
