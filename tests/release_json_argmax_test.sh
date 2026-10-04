#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for f in "$ROOT/scripts/stage_ci_release_assets.sh" "$ROOT/scripts/publish_ci_release.sh" "$ROOT/scripts/cleanup_ci_release_transients.sh"; do
  bash -n "$f"
done

# Large GitHub API JSON must be read from files/stdin, never expanded as an argv payload.
if grep -Eq 'python3 - "\$[A-Z_][A-Z0-9_]*".*json\.loads\(sys\.argv\[1\]\)' \
    "$ROOT/scripts/stage_ci_release_assets.sh" \
    "$ROOT/scripts/publish_ci_release.sh" \
    "$ROOT/scripts/cleanup_ci_release_transients.sh"; then
  echo 'FAIL: release API JSON is still passed through argv' >&2
  exit 1
fi

echo 'PASS release JSON parsing avoids ARG_MAX-sized argv payloads'
