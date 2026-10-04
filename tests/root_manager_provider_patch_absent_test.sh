#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Static CI checkout deliberately has no recursive root-manager worktrees.
# Simulate that layout and verify the provider test exits cleanly without
# invoking git -C on a nonexistent path.
mkdir -p "$ROOT/third_party/root-managers"

out="$TMP/output"
if bash "$ROOT/tests/root_manager_provider_patch_test.sh" >"$out" 2>&1; then
  :
else
  rc=$?
  echo "FAIL: provider patch test returned $rc without submodule worktrees" >&2
  cat "$out" >&2
  exit 1
fi

if grep -qE '^fatal: .*third_party/root-managers/.+ does not exist$' "$out"; then
  echo "FAIL: provider patch test emitted fatal missing-worktree error" >&2
  cat "$out" >&2
  exit 1
fi

grep -q 'SKIP: kernelsu-next submodule worktree is not present' "$out"
grep -q 'SKIP: sukisu-ultra submodule worktree is not present' "$out"
echo 'PASS: provider patch tests skip absent submodule worktrees without fatal git errors'
