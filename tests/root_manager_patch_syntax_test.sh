#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
for patch in $(find "$ROOT/patches/root-manager" -type f -name '*.patch' -print); do
  output="$(git -C "$TMP" apply --check --whitespace=nowarn "$patch" 2>&1 || true)"
  if grep -qi 'corrupt patch' <<<"$output"; then
    printf 'FAIL: corrupt patch %s\n%s\n' "$patch" "$output" >&2
    exit 1
  fi
done
echo 'PASS: no root-manager patch is syntactically corrupt'
