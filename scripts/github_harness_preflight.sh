#!/usr/bin/env bash
set -Eeuo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPOSITORY:?GH_REPOSITORY is required}"

API="https://api.github.com"
AUTH=(
  -H "Authorization: Bearer ${GH_TOKEN}"
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

echo "=== GITHUB HARNESS PREFLIGHT ==="

USER_HTTP="$(curl -sS -o /tmp/github-harness-user.json -w '%{http_code}' \
  "${AUTH[@]}" "$API/user")"
echo "GitHub /user HTTP: $USER_HTTP"

python3 -c 'import json; d=json.load(open("/tmp/github-harness-user.json", encoding="utf-8")); print("login:", d.get("login", "unknown")); print("user_id:", d.get("id", "unknown")); print("message:", d.get("message")) if d.get("message") else None'

[[ "$USER_HTTP" == "200" ]] || { echo "ERROR: GitHub authentication failed" >&2; exit 1; }

REPO_HTTP="$(curl -sS -o /tmp/github-harness-repo.json -w '%{http_code}' \
  "${AUTH[@]}" "$API/repos/${GH_REPOSITORY}")"
echo "GitHub repository HTTP: $REPO_HTTP"

python3 -c 'import json; d=json.load(open("/tmp/github-harness-repo.json", encoding="utf-8")); print("repository:", d.get("full_name", "unknown")); print("permissions:", d.get("permissions", {})); print("message:", d.get("message")) if d.get("message") else None'

[[ "$REPO_HTTP" == "200" ]] || { echo "ERROR: repository access failed" >&2; exit 1; }

TEST_TAG="ci-build-harness-preflight-$(date +%Y%m%d%H%M%S)-$$"
RESPONSE="/tmp/github-harness-release.json"
RELEASE_ID=""

cleanup() {
  local rc=$?
  set +e
  if [[ -n "$RELEASE_ID" ]]; then
    curl -sS -X DELETE "${AUTH[@]}" \
      "$API/repos/${GH_REPOSITORY}/releases/${RELEASE_ID}" >/dev/null || true
  fi
  curl -sS -X DELETE "${AUTH[@]}" \
    "$API/repos/${GH_REPOSITORY}/git/refs/tags/${TEST_TAG}" >/dev/null || true
  rm -f /tmp/github-harness-user.json /tmp/github-harness-repo.json "$RESPONSE"
  exit "$rc"
}
trap cleanup EXIT

echo "Testing Contents: write with temporary draft release..."

CREATE_HTTP="$(curl -sS -o "$RESPONSE" -w '%{http_code}' \
  -X POST "${AUTH[@]}" \
  -H "Content-Type: application/json" \
  "$API/repos/${GH_REPOSITORY}/releases" \
  --data "$(python3 - "$TEST_TAG" <<'PY_PAYLOAD'
import json, sys
print(json.dumps({
    "tag_name": sys.argv[1],
    "name": "ci-build Harness preflight",
    "body": "Temporary preflight release; deleted automatically.",
    "draft": True,
    "prerelease": True,
}))
PY_PAYLOAD
)")"

echo "GitHub create-release HTTP: $CREATE_HTTP"

python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); print("message:", d.get("message")) if d.get("message") else None; print("temporary_release_id:", d.get("id", "unknown")); print("temporary_release_url:", d.get("html_url", "unknown"))' "$RESPONSE"

[[ "$CREATE_HTTP" == "201" ]] || { echo "ERROR: Harness github_token cannot create a release" >&2; exit 1; }

RELEASE_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("id", ""))' "$RESPONSE")"
[[ -n "$RELEASE_ID" ]] || { echo "ERROR: GitHub did not return a release ID" >&2; exit 1; }

echo "Authentication: PASS"
echo "Repository access: PASS"
echo "Contents: write: PASS"
echo "GitHub Harness preflight: PASS"
