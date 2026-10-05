#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check(){ grep -qE "$2" "$1" && echo "PASS: $3" || { echo "FAIL: $3" >&2; fail=1; }; }
check "$ROOT/scripts/root_manager_apply.sh" 'v0\.9\.5' 'official KernelSU 4.x pins v0.9.5'
check "$ROOT/scripts/root_manager_apply.sh" 'KSU_NEXT_44_REF=.*v3\.4\.0-legacy' 'KernelSU-Next 4.4 defaults to the manual-hook legacy line'
check "$ROOT/profiles/targets/lavender-4.4.conf" '^PROFILE_KSU_NEXT_44_REF="v3\.4\.0-legacy"$' 'lavender-4.4 profile pins KernelSU-Next v3.4.0-legacy'
check "$ROOT/profiles/targets/lavender-4.19.conf" '^PROFILE_KSU_NEXT_LEGACY_REF="v3\.4\.0-legacy"$' 'lavender-4.19 profile pins KernelSU-Next v3.4.0-legacy'
check "$ROOT/profiles/targets/garnet-gki.conf" '^PROFILE_KSU_NEXT_GKI_REF="v3\.4\.0"$' 'garnet-gki profile pins KernelSU-Next v3.4.0'
check "$ROOT/scripts/root_manager_apply.sh" 'kernelsu-next@v3\.4\.0\]=1a879d6a866f80b1fa1c1009a2ffa747873cbb5e' 'KernelSU-Next v3.4.0 commit is verified'
check "$ROOT/profiles/targets/lavender-4.4.conf" '^PROFILE_DEFAULT_VARIANTS="vanilla,kernelsu-next,resukisu"$' 'lavender-4.4 default matrix excludes unsupported SukiSU Ultra'
check "$ROOT/scripts/root_manager_apply.sh" 'KSU_NEXT_LEGACY_REF=.*v3\.4\.0-legacy' 'KernelSU-Next non-GKI line is pinned to v3.4.0-legacy'
check "$ROOT/scripts/root_manager_apply.sh" 'kernelsu-next@v3\.4\.0-legacy\]=8af3d4fec33be32fa5d3f8dae4f380fac45bf2cd' 'KernelSU-Next v3.4.0-legacy commit is verified'
check "$ROOT/scripts/root_manager_apply.sh" 'resukisu@v4\.2\.0-rc3\]=239e1e8871b8fcd51a6e5b3002e0ba522fdd99fb' 'ReSukiSU v4.2.0-rc3 commit is verified'
check "$ROOT/scripts/root_manager_apply.sh" 'is not a legacy ref' 'non-legacy KernelSU-Next refs fail closed below 5.10'
check "$ROOT/scripts/root_manager_apply.sh" 'KSU_NEXT_GKI_REF=.*v3\.4\.0' 'KernelSU-Next GKI line is pinned to v3.4.0'
check "$ROOT/scripts/root_manager_apply.sh" 'v4\.2\.0-rc3' 'ReSukiSU deterministic default is pinned'
check "$ROOT/scripts/root_manager_apply.sh" 'SukiSU-Ultra/SukiSU-Ultra' 'SukiSU Ultra upstream is wired'
check "$ROOT/scripts/root_manager_apply.sh" 'PROVIDER_PATCH_DIR' 'provider-specific patch registry is wired'
test ! -e "$ROOT/scripts/apply_nongki_4_4.sh" && echo 'PASS: 4.4 hooks come from the patch registry (no external hook script)' || { echo 'FAIL: external NonGKI hook stage still present' >&2; fail=1; }
check "$ROOT/scripts/build_kernel.sh" 'SUKISU_ULTRA_REF_DEFAULT' 'build kernel defines SukiSU Ultra ref'
check "$ROOT/scripts/build_kernel.sh" 'KSU_NEXT_44_REF' 'build kernel carries explicit KSU-Next 4.4 ref'
check "$ROOT/scripts/build_variants.sh" 'KSU_NEXT_44_REF' 'matrix runner carries explicit KSU-Next 4.4 ref'
check "$ROOT/scripts/build_kernel.sh" 'ROOT_MANAGER_SOURCE_ROOT' 'build kernel passes root-manager source root'
check "$ROOT/scripts/root_manager_apply.sh" 'official KernelSU is not supported by upstream on Linux' 'official KernelSU 4.4 fail-closed gate'
check "$ROOT/scripts/apply_susfs.sh" 'apply --check' 'SUSFS uses strict patch preflight'
check "$ROOT/scripts/root_manager_apply.sh" 'KernelSU-Next legacy has no SUSFS hook mode' 'KernelSU-Next + SUSFS fails closed'
check "$ROOT/scripts/root_manager_apply.sh" 'resukisu:4\.4\)' 'ReSukiSU 4.4 + SUSFS fails closed'
for f in \
  "$ROOT/patches/root-manager/kernelsu/4.19/config.fragment" \
  "$ROOT/patches/root-manager/kernelsu-next/4.4/config.fragment" \
  "$ROOT/patches/root-manager/kernelsu-next/4.19/config.fragment" \
  "$ROOT/patches/root-manager/resukisu/4.4/config.fragment" \
  "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" \
  "$ROOT/patches/root-manager/resukisu/5.10/config.fragment" \
  "$ROOT/patches/root-manager/sukisu-ultra/4.19/config.fragment" \
  "$ROOT/patches/root-manager/sukisu-ultra/5.10/config.fragment"; do
  test -f "$f" && echo "PASS: $(basename "$(dirname "$f")") config fragment" || { echo "FAIL: missing $f" >&2; fail=1; }
done
grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$ROOT/patches/root-manager/resukisu/4.4/config.fragment" && echo 'PASS: ReSukiSU 4.4 manual hook' || { echo 'FAIL: ReSukiSU 4.4 manual hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" && echo 'PASS: ReSukiSU 4.19 manual hook' || { echo 'FAIL: ReSukiSU 4.19 manual hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y$' "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" && echo 'PASS: ReSukiSU 4.19 auto setuid hook' || { echo 'FAIL: ReSukiSU 4.19 auto setuid hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y$' "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" && echo 'PASS: ReSukiSU 4.19 auto initrc hook' || { echo 'FAIL: ReSukiSU 4.19 auto initrc hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y$' "$ROOT/patches/root-manager/resukisu/4.19/config.fragment" && echo 'PASS: ReSukiSU 4.19 auto input hook' || { echo 'FAIL: ReSukiSU 4.19 auto input hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_TRACEPOINT_HOOK=y$' "$ROOT/patches/root-manager/resukisu/5.10/config.fragment" && echo 'PASS: ReSukiSU 5.10 tracepoint hook' || { echo 'FAIL: ReSukiSU 5.10 tracepoint hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$ROOT/patches/root-manager/kernelsu-next/4.4/config.fragment" && echo 'PASS: KernelSU-Next 4.4 manual hook' || { echo 'FAIL: KernelSU-Next 4.4 manual hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "$ROOT/patches/root-manager/kernelsu-next/4.19/config.fragment" && echo 'PASS: KernelSU-Next 4.19 manual hook' || { echo 'FAIL: KernelSU-Next 4.19 manual hook' >&2; fail=1; }
grep -q '^CONFIG_KSU_SUSFS=y$' "$ROOT/patches/root-manager/resukisu/4.19/susfs.fragment" && grep -q '^# CONFIG_KSU_MANUAL_HOOK is not set$' "$ROOT/patches/root-manager/resukisu/4.19/susfs.fragment" && echo 'PASS: ReSukiSU 4.19 SUSFS hook mode' || { echo 'FAIL: ReSukiSU 4.19 SUSFS hook mode' >&2; fail=1; }
grep -q '^CONFIG_KSU_MANUAL_SU=y$' "$ROOT/patches/root-manager/sukisu-ultra/4.19/config.fragment" && echo 'PASS: SukiSU Ultra 4.19 manual su hook' || { echo 'FAIL: SukiSU Ultra 4.19 manual su hook' >&2; fail=1; }
exit "$fail"
