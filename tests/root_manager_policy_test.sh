#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check(){ grep -qE "$2" "$1" && echo "PASS: $3" || { echo "FAIL: $3" >&2; fail=1; }; }
check "$ROOT/scripts/root_manager_apply.sh" 'v0\.9\.5' 'official KernelSU 4.19 pins v0.9.5'
check "$ROOT/scripts/root_manager_apply.sh" 'v3\.4\.0' 'KernelSU-Next 4.19 defaults to v3.4.0'
check "$ROOT/scripts/root_manager_apply.sh" 'PROVIDER_REF="main"' 'ReSukiSU defaults to main'
check "$ROOT/scripts/apply_susfs.sh" '001e69919c6271f690fd00b17e4c721c9e599152' 'SUSFS 4.19 revision is pinned'
check "$ROOT/scripts/apply_susfs.sh" 'KSU-Next' 'KSU-Next + external SUSFS is fail-closed'
check "$ROOT/scripts/apply_susfs.sh" 'git apply --check' 'SUSFS uses strict patch preflight'
test -f "$ROOT/patches/root-manager/kernelsu/4.19/config.fragment" && echo "PASS: KernelSU config fragment present" || { echo "FAIL: KernelSU config fragment missing" >&2; fail=1; }
test -f "$ROOT/patches/root-manager/kernelsu-next/4.19/config.fragment" && echo "PASS: KernelSU-Next config fragment present" || { echo "FAIL: KernelSU-Next config fragment missing" >&2; fail=1; }
test -f "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" && echo "PASS: ReSukiSU config fragment present" || { echo "FAIL: ReSukiSU config fragment missing" >&2; fail=1; }
test -f "$ROOT/patches/features/susfs/kernel-4.19/config.fragment" && echo "PASS: SUSFS config fragment present" || { echo "FAIL: SUSFS config fragment missing" >&2; fail=1; }
exit "$fail"
