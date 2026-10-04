#!/usr/bin/env bash
# Fetch the per-execution Harness handoff release from GitHub.
# Harness persists every completed/failed variant there; GitHub Actions then
# materializes those files as native Actions artifacts and can relay them on to
# Telegram without depending on the Harness runner filesystem.
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
CI_LOG_TAG=harness-fetch

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPOSITORY:?GH_REPOSITORY is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"
OUT_DIR="${OUT_DIR:-${RUNNER_TEMP:-/tmp}/harness-artifacts}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-36}"
SLEEP_SECONDS="${SLEEP_SECONDS:-10}"

API="${GITHUB_API:-https://api.github.com}"
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

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
TAG_ENC="$(urlencode "$RELEASE_TAG")"
RELEASE_JSON="$OUT_DIR/release.json"
found=false

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  if curl -fsSL --retry 2 --retry-delay 2 "${AUTH[@]}" \
      "$API/repos/${GH_REPOSITORY}/releases/tags/${TAG_ENC}" > "$RELEASE_JSON"; then
    found=true
    break
  fi
  echo "[harness-fetch] waiting for release tag=$RELEASE_TAG attempt=$attempt/$MAX_ATTEMPTS" >&2
  sleep "$SLEEP_SECONDS"
done

[[ "$found" == true ]] || ci_die "Harness staging release was not found: $RELEASE_TAG"

python3 - "$RELEASE_JSON" "$OUT_DIR" <<'PY'
import json, os, sys
release=json.load(open(sys.argv[1], encoding='utf-8'))
out=sys.argv[2]
assets=[]
for item in release.get('assets', []):
    if not isinstance(item, dict):
        continue
    asset_id=str(item.get('id') or '').strip()
    name=str(item.get('name') or '').strip()
    url=str(item.get('url') or '').strip()
    if asset_id and name and url:
        assets.append((asset_id,name,url))
with open(os.path.join(out,'assets.tsv'),'w',encoding='utf-8') as fh:
    for row in assets:
        fh.write('\t'.join(row)+'\n')
print(f"asset_count={len(assets)}")
PY

count=0
while IFS=$'\t' read -r asset_id name url; do
  [[ -n "$asset_id" && -n "$name" && -n "$url" ]] || continue
  echo "[harness-fetch] downloading $name"
  curl -fsSL --retry 4 --retry-delay 2 \
    -H 'Accept: application/octet-stream' \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "$url" -o "$OUT_DIR/$name"
  count=$((count + 1))
done < "$OUT_DIR/assets.tsv"

rm -f "$OUT_DIR/release.json" "$OUT_DIR/assets.tsv"

find "$OUT_DIR" -maxdepth 1 -type f -printf '%f\n' | sort > "$OUT_DIR/MANIFEST.txt"
printf '[harness-fetch] fetched %s asset(s) into %s\n' "$count" "$OUT_DIR"
