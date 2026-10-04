#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }

# GitHub Actions uses a non-recursive checkout. The provider worktree
# directories therefore do not exist at all.
rm -rf \
  "$ROOT/third_party/root-managers/kernelsu-next" \
  "$ROOT/third_party/root-managers/sukisu-ultra"

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

set +e
bash "$ROOT/tests/root_manager_provider_patch_test.sh" >"$out" 2>&1
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  cat "$out" >&2
  fail "provider patch test returned $rc without provider worktrees"
fi

if grep -qE '^fatal: .*third_party/root-managers/(kernelsu-next|sukisu-ultra)' "$out"; then
  cat "$out" >&2
  fail "provider patch test emitted a fatal git error for an absent provider"
fi

grep -q 'SKIP: kernelsu-next submodule worktree is not present' "$out" ||
  fail "missing kernelsu-next absent-worktree skip"
grep -q 'SKIP: sukisu-ultra submodule worktree is not present' "$out" ||
  fail "missing sukisu-ultra absent-worktree skip"

echo 'PASS: provider patch test safely skips absent root-manager worktrees'
