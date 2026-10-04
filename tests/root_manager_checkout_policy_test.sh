#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
pass(){ echo "PASS: $*"; }

for path in   "$ROOT/.github/workflows/ci-validation.yml"   "$ROOT/.github/workflows/kernel.yml"   "$ROOT/.github/workflows/harness-kernel.yml"
do
  if grep -q 'submodules: recursive' "$path"; then
    fail "recursive root-manager checkout remains enabled in $path"
  fi
done

grep -q 'ROOT_MANAGER_SOURCE_MODE: auto' "$ROOT/.github/workflows/kernel.yml" ||
  fail "kernel workflow does not use auto root-manager source mode"
grep -q 'ROOT_MANAGER_SOURCE_MODE: auto' "$ROOT/.github/workflows/harness-kernel.yml" ||
  fail "Harness workflow does not use auto root-manager source mode"

grep -q 'PROVIDERS="${ROOT_MANAGER_PROVIDERS:-${1:-all}}"'   "$ROOT/scripts/bootstrap_root_manager_submodules.sh" ||
  fail "selective root-manager bootstrap support missing"

pass "root-manager submodule checkout is decoupled from CI builds"
