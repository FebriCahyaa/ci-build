#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check(){ grep -qE "$2" "$1" && echo "PASS: $3" || { echo "FAIL: $3" >&2; fail=1; }; }
check "$ROOT/scripts/root_manager_apply.sh" 'v0\.9\.5' 'official KernelSU 4.x pins v0.9.5'
check "$ROOT/scripts/root_manager_apply.sh" 'v1\.1\.1' 'KernelSU-Next legacy line is pinned'
check "$ROOT/scripts/root_manager_apply.sh" 'v3\.4\.0' 'KernelSU-Next GKI line is pinned'
check "$ROOT/scripts/root_manager_apply.sh" 'v4\.2\.0-rc3' 'ReSukiSU deterministic default is pinned'
check "$ROOT/scripts/apply_susfs.sh" 'git apply --check' 'SUSFS uses strict patch preflight'
for f in \
  "$ROOT/patches/root-manager/kernelsu/4.19/config.fragment" \
  "$ROOT/patches/root-manager/kernelsu-next/4.4/config.fragment" \
  "$ROOT/patches/root-manager/kernelsu-next/4.19/config.fragment" \
  "$ROOT/patches/root-manager/resukisu/4.4/config.fragment" \
  "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" \
  "$ROOT/patches/root-manager/resukisu/5.10/config.fragment"; do
  test -f "$f" && echo "PASS: $(basename "$(dirname "$f")") config fragment" || { echo "FAIL: missing $f" >&2; fail=1; }
done
grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$ROOT/patches/root-manager/resukisu/4.4/config.fragment" && echo 'PASS: ReSukiSU 4.4 manual hook' || { echo 'FAIL: ReSukiSU 4.4 manual hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" && echo 'PASS: ReSukiSU 4.19 manual hook' || { echo 'FAIL: ReSukiSU 4.19 manual hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y$' "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" && echo 'PASS: ReSukiSU 4.19 auto setuid hook' || { echo 'FAIL: ReSukiSU 4.19 auto setuid hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y$' "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" && echo 'PASS: ReSukiSU 4.19 auto initrc hook' || { echo 'FAIL: ReSukiSU 4.19 auto initrc hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y$' "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" && echo 'PASS: ReSukiSU 4.19 auto input hook' || { echo 'FAIL: ReSukiSU 4.19 auto input hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_TRACEPOINT_HOOK=y$' "$ROOT/patches/root-manager/resukisu/5.10/config.fragment" && echo 'PASS: ReSukiSU 5.10 tracepoint hook' || { echo 'FAIL: ReSukiSU 5.10 tracepoint hook' >&2; fail=1; }
test -f "$ROOT/patches/features/susfs/kernel-4.4/config.fragment" && echo 'PASS: SUSFS 4.4 config fragment' || { echo 'FAIL: SUSFS 4.4 config fragment' >&2; fail=1; }
grep -q '^CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y$' "$ROOT/patches/features/susfs/kernel-4.4/config.fragment" && echo 'PASS: SUSFS 4.4 cmdline spoof' || { echo 'FAIL: SUSFS 4.4 cmdline spoof' >&2; fail=1; }
exit "$fail"
