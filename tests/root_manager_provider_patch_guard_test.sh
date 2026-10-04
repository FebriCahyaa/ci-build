#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST="$ROOT/tests/root_manager_provider_patch_test.sh"

grep -q 'if \[\[ ! -d "\$source" \]\]' "$TEST" ||
  { echo "FAIL: missing provider directory guard" >&2; exit 1; }
grep -q 'SKIP: \$provider submodule worktree is not present' "$TEST" ||
  { echo "FAIL: missing absent-worktree skip" >&2; exit 1; }
echo 'PASS: root-manager provider patch test has an absent-worktree guard'
