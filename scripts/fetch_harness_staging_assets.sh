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
READY_ASSET_NAME="${READY_ASSET_NAME:-handoff-HANDOFF-READY.txt}"

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
last_status=0

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  set +e
  status="$(curl -sSL --retry 2 --retry-delay 2 "${AUTH[@]}" \
      -o "$RELEASE_JSON" -w '%{http_code}' \
      "$API/repos/${GH_REPOSITORY}/releases/tags/${TAG_ENC}")"
  curl_rc=$?
  set -e

  if (( curl_rc == 0 )) && [[ "$status" == "200" ]]; then
    ready="$(python3 - "$RELEASE_JSON" "$READY_ASSET_NAME" <<'PY_READY'
import json,sys
r=json.load(open(sys.argv[1],encoding='utf-8'))
if r.get('draft', True):
    print('draft')
    raise SystemExit(0)
for a in r.get('assets',[]):
    if isinstance(a,dict) and a.get('name') == sys.argv[2]:
        print('ready')
        break
else:
    print('waiting')
PY_READY
)"
    if [[ "$ready" == "ready" ]]; then
      found=true
      break
    fi
    status="200/no-ready-marker"
  fi

  last_status="${status:-curl-error}"
  echo "[harness-fetch] waiting for release tag=$RELEASE_TAG attempt=$attempt/$MAX_ATTEMPTS status=$last_status" >&2
  sleep "$SLEEP_SECONDS"
done

[[ "$found" == true ]] || ci_die \
  "Harness staging release handoff was not ready: $RELEASE_TAG (last_status=$last_status; expected published prerelease + $READY_ASSET_NAME)"

python3 - "$RELEASE_JSON" "$OUT_DIR" "$READY_ASSET_NAME" <<'PY'
import json, os, sys
release=json.load(open(sys.argv[1], encoding='utf-8'))
out=sys.argv[2]
ready_name=sys.argv[3]
is_prerelease=bool(release.get('prerelease'))
assets=[]
for item in release.get('assets', []):
    if not isinstance(item, dict):
        continue
    asset_id=str(item.get('id') or '').strip()
    name=str(item.get('name') or '').strip()
    url=str(item.get('url') or '').strip()
    if not (asset_id and name and url):
        continue
    if name == ready_name:
        continue
    # During the Harness handoff, fetch the handoff copies. Once the same
    # release is promoted to final, fetch only canonical assets so Telegram
    # and Actions never receive duplicate handoff/staging files.
    if not is_prerelease and (name.startswith('handoff-') or name.startswith('staging-')):
        continue
    assets.append((asset_id,name,url))
with open(os.path.join(out,'assets.tsv'),'w',encoding='utf-8') as fh:
    for row in assets:
        fh.write('\t'.join(row)+'\n')
print(f"release_prerelease={str(is_prerelease).lower()} asset_count={len(assets)}")
PY

count=0
while IFS=$'\t' read -r asset_id name url; do
  [[ -n "$asset_id" && -n "$name" && -n "$url" ]] || continue
  # "handoff-" only marks transient staging assets on the release; users should
  # get the canonical file name. Keep the prefix if stripping would collide.
  local_name="${name#handoff-}"
  [[ -e "$OUT_DIR/$local_name" || -z "$local_name" ]] && local_name="$name"
  echo "[harness-fetch] downloading $name -> $local_name"
  curl -fsSL --retry 4 --retry-delay 2 \
    -H 'Accept: application/octet-stream' \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "$url" -o "$OUT_DIR/$local_name"
  count=$((count + 1))
done < "$OUT_DIR/assets.tsv"

rm -f "$OUT_DIR/release.json" "$OUT_DIR/assets.tsv"

find "$OUT_DIR" -maxdepth 1 -type f -printf '%f\n' | sort > "$OUT_DIR/MANIFEST.txt"
printf '[harness-fetch] fetched %s asset(s) into %s\n' "$count" "$OUT_DIR"
