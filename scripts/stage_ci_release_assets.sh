#!/usr/bin/env bash
# Stage build artifacts into a per-execution published prerelease GitHub Release.
# Used by Harness so successful/failed matrix diagnostics remain downloadable
# to GitHub Actions and visible through the Harness artifact metadata link.
# Final publishing reuses the same tag and removes the handoff assets.
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
CI_LOG_TAG=release-stage

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPOSITORY:?GH_REPOSITORY is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"
ASSET_DIR="${ASSET_DIR:-}"
[[ -n "$ASSET_DIR" && -d "$ASSET_DIR" ]] || ci_die "ASSET_DIR is required and must exist"
ASSET_PREFIX="${ASSET_PREFIX:-}"
CLEAN_PREFIX="${CLEAN_PREFIX:-}"

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
  # flock only coordinates processes on the same runner. The API conflict retry
  # below is the real cross-runner protection when multiple jobs share a tag.
  flock -x 9
  local code response body
  set +e
  code="$(curl -sSL --retry 4 --retry-delay 2 "${AUTH[@]}" \
    -o "$RELEASE_JSON" -w '%{http_code}' \
    "$API/repos/${GH_REPOSITORY}/releases/tags/${TAG_ENC}")"
  local curl_rc=$?
  set -e

  if (( curl_rc == 0 )) && [[ "$code" == 200 ]]; then
    flock -u 9
    return 0
  fi
  if (( curl_rc != 0 )); then
    flock -u 9
    ci_die "unable to query GitHub release tag $RELEASE_TAG"
  fi
  [[ "$code" == 404 ]] || {
    flock -u 9
    ci_die "GitHub release lookup failed: HTTP $code"
  }

  # A draft release cannot be fetched through GitHub's GET /releases/tags/{tag}
  # endpoint. Publish the handoff as a prerelease instead; it is still non-latest
  # and can later be promoted to a normal release by publish_ci_release.sh.
  body="$(python3 - "$RELEASE_TAG" <<'PYBODY'
import json, sys
print(json.dumps({
    "tag_name": sys.argv[1],
    "name": "Zairenkai CI — " + sys.argv[1],
    "body": "CI handoff prerelease. Artifacts are uploaded as each variant completes.",
    "draft": False,
    "prerelease": True,
}, separators=(",", ":")))
PYBODY
)"

  # Migrate a release created by the previous draft-based implementation.
  existing_id="$(curl -fsSL --retry 4 --retry-delay 2 "${AUTH[@]}" \
    "$API/repos/${GH_REPOSITORY}/releases?per_page=100" | python3 -c 'import json,sys; tag=sys.argv[1]; data=json.load(sys.stdin); print(next((x.get("id","") for x in data if x.get("tag_name") == tag), ""))' "$RELEASE_TAG")"
  if [[ -n "$existing_id" ]]; then
    echo "[release-stage] migrating existing draft handoff $RELEASE_TAG to published prerelease"
    set +e
    migrate_code="$(curl -sSL --retry 4 --retry-delay 2 -X PATCH "${AUTH[@]}" \
      -H 'Content-Type: application/json' \
      "$API/repos/${GH_REPOSITORY}/releases/${existing_id}" \
      --data "$body" -o "$RELEASE_JSON" -w '%{http_code}')"
    curl_rc=$?
    set -e
    if (( curl_rc == 0 )) && [[ "$migrate_code" =~ ^20[01]$ ]]; then
      flock -u 9
      return 0
    fi
    flock -u 9
    ci_die "unable to migrate existing GitHub staging release $RELEASE_TAG (HTTP ${migrate_code:-curl-error})"
  fi

  set +e
  response="$(curl -sSL --retry 3 --retry-delay 2 -X POST "${AUTH[@]}" \
    -H 'Content-Type: application/json' \
    "$API/repos/${GH_REPOSITORY}/releases" \
    --data "$body" -o "$RELEASE_JSON" -w '%{http_code}')"
  curl_rc=$?
  set -e

  if (( curl_rc == 0 )) && [[ "$response" =~ ^20[01]$ ]]; then
    flock -u 9
    return 0
  fi

  # Another runner may have won the create race, or an older draft may have
  # become visible through the list endpoint. Reconcile by exact tag.
  if [[ "$response" == 422 ]]; then
    existing_id="$(curl -fsSL --retry 4 --retry-delay 2 "${AUTH[@]}" \
      "$API/repos/${GH_REPOSITORY}/releases?per_page=100" | python3 -c 'import json,sys; tag=sys.argv[1]; data=json.load(sys.stdin); print(next((x.get("id","") for x in data if x.get("tag_name") == tag), ""))' "$RELEASE_TAG")"
    if [[ -n "$existing_id" ]]; then
      curl -fsSL --retry 4 --retry-delay 2 -X PATCH "${AUTH[@]}" \
        -H 'Content-Type: application/json' \
        "$API/repos/${GH_REPOSITORY}/releases/${existing_id}" \
        --data "$body" > "$RELEASE_JSON"
      flock -u 9
      return 0
    fi
  fi

  flock -u 9
  ci_die "unable to create GitHub staging release $RELEASE_TAG (HTTP ${response:-curl-error})"
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

# A final handoff can replace earlier per-variant staging assets. This prevents
# GitHub Actions/Telegram from receiving duplicate copies after assembly.
if [[ -n "$CLEAN_PREFIX" ]]; then
  EXISTING_ASSETS_JSON="$STATE_DIR/zairenkai-release-assets-clean.json"
  curl -fsSL --retry 4 --retry-delay 2 "${AUTH[@]}" \
    "$API/repos/${GH_REPOSITORY}/releases/${RELEASE_ID}/assets?per_page=100" > "$EXISTING_ASSETS_JSON"
  while IFS=$'\t' read -r asset_id asset_name; do
    [[ -n "$asset_id" ]] || continue
    [[ "$asset_name" == "$CLEAN_PREFIX"* ]] || continue
    echo "[release-stage] removing superseded asset $asset_name"
    curl -fsSL --retry 4 --retry-delay 2 -X DELETE "${AUTH[@]}" \
      "$API/repos/${GH_REPOSITORY}/releases/assets/${asset_id}" >/dev/null
  done < <(python3 - "$EXISTING_ASSETS_JSON" <<'PY_ASSETS'
import json,sys
for a in json.load(open(sys.argv[1], encoding='utf-8')):
    print(f"{a.get('id','')}\t{a.get('name','')}")
PY_ASSETS
)
fi

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
  ASSETS_JSON="$STATE_DIR/zairenkai-release-assets-current.json"
  curl -fsSL "${AUTH[@]}" "$API/repos/${GH_REPOSITORY}/releases/${RELEASE_ID}/assets?per_page=100" > "$ASSETS_JSON"
  asset_id="$(python3 - "$ASSETS_JSON" "$name" <<'PY'
import json,sys
for item in json.load(open(sys.argv[1], encoding='utf-8')):
    if item.get('name') == sys.argv[2]:
        print(item.get('id',''))
        break
PY
)"
  if [[ -n "$asset_id" ]]; then
    curl -fsSL --retry 4 --retry-delay 2 -X DELETE "${AUTH[@]}" \
      "$API/repos/${GH_REPOSITORY}/releases/assets/${asset_id}" >/dev/null
  fi

  echo "[release-stage] uploading $name"
  curl -fsSL --retry 4 --retry-delay 2 -X POST "${AUTH[@]}" \
    -H 'Content-Type: application/octet-stream' \
    --data-binary "@$file" \
    "${UPLOAD_URL}?name=${encoded}" >/dev/null
done

# Upload a completion marker *last*. fetch_harness_staging_assets.sh waits for
# this file, preventing a race where it sees the release before its real assets
# have finished uploading. Only handoff-prefixed staging gets the marker.
if [[ "$ASSET_PREFIX" == "handoff" ]]; then
  READY_NAME="handoff-HANDOFF-READY.txt"
  READY_FILE="$STATE_DIR/$READY_NAME"
  printf 'release_tag=%s\nstatus=READY\nasset_count=%s\n' \
    "$RELEASE_TAG" "${#assets[@]}" > "$READY_FILE"
  ASSETS_JSON="$STATE_DIR/zairenkai-release-assets-ready.json"
  curl -fsSL --retry 4 --retry-delay 2 "${AUTH[@]}" \
    "$API/repos/${GH_REPOSITORY}/releases/${RELEASE_ID}/assets?per_page=100" > "$ASSETS_JSON"
  ready_id="$(python3 - "$ASSETS_JSON" "$READY_NAME" <<'PY_READY_ID'
import json,sys
for item in json.load(open(sys.argv[1], encoding='utf-8')):
    if item.get('name') == sys.argv[2]:
        print(item.get('id',''))
        break
PY_READY_ID
)"
  if [[ -n "$ready_id" ]]; then
    curl -fsSL --retry 4 --retry-delay 2 -X DELETE "${AUTH[@]}" \
      "$API/repos/${GH_REPOSITORY}/releases/assets/${ready_id}" >/dev/null
  fi
  echo "[release-stage] uploading $READY_NAME"
  curl -fsSL --retry 4 --retry-delay 2 -X POST "${AUTH[@]}" \
    -H 'Content-Type: text/plain' \
    --data-binary "@$READY_FILE" \
    "${UPLOAD_URL}?name=$(urlencode "$READY_NAME")" >/dev/null
  rm -f "$READY_FILE"
fi

printf '%s\n' "[release-stage] staged $((${#assets[@]} + $( [[ "$ASSET_PREFIX" == "handoff" ]] && echo 1 || echo 0 ))) asset(s) into published prerelease $RELEASE_TAG"
