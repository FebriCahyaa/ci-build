#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check(){ grep -qE "$2" "$1" && echo "PASS: $3" || { echo "FAIL: $3" >&2; fail=1; }; }

check "$ROOT/patches/upstream/lokitla-nongki/4.4/manifest.conf" 'UPSTREAM_NONGKI_COMMIT="ab5b09509bcdf7a077468b0ab30bfe3cc86a0c77"' 'NonGKI upstream commit is pinned in manifest'
check "$ROOT/patches/upstream/lokitla-nongki/4.4/manifest.conf" 'UPSTREAM_SYSCALL_HOOK_BLOB="3c2a22bc0114a743e352d372115213d957e9c2ae"' 'syscall hook blob is pinned'
check "$ROOT/patches/upstream/lokitla-nongki/4.4/manifest.conf" 'UPSTREAM_INLINE_HOOK_BLOB="250d004b0010f29cca73c6f52fab926197877aea"' 'inline hook blob is pinned'
check "$ROOT/patches/upstream/lokitla-nongki/4.4/manifest.conf" 'UPSTREAM_SUSFS_4_4_BLOB="eed2afc8702b5b01bde129c5864c47b763d92294"' 'dedicated 4.4 SUSFS patch blob is pinned'
check "$ROOT/scripts/apply_susfs.sh" 'susfs_patch_to_4\.4\.patch' 'dedicated 4.4 SUSFS patch path exists'
check "$ROOT/scripts/build_kernel.sh" 'apply_nongki_4_4\.sh' 'build pipeline invokes NonGKI 4.4 integration'
check "$ROOT/scripts/build_kernel.sh" 'NONGKI_4_4_MODE' 'NonGKI mode is configurable'
check "$ROOT/profiles/targets/lavender-4.4.conf" '^PROFILE_NONGKI_4_4_HOOKS="true"$' 'lavender 4.4 enables NonGKI hooks'
check "$ROOT/profiles/targets/lavender-4.4.conf" '^PROFILE_NONGKI_4_4_MODE="auto"$' 'lavender 4.4 uses automatic hook selection'
check "$ROOT/patches/features/susfs/kernel-4.4/config.fragment" '^CONFIG_KSU_SUSFS_OPEN_REDIRECT=y$' '4.4 SUSFS config exposes open redirect'
check "$ROOT/patches/features/susfs/kernel-4.4/config.fragment" '^CONFIG_KSU_SUSFS_SUS_MAP=y$' '4.4 SUSFS config exposes SUS map'

for script in apply_nongki_4_4.sh apply_susfs.sh build_kernel.sh build_variants.sh; do
  bash -n "$ROOT/scripts/$script" || { echo "FAIL: $script shell syntax" >&2; fail=1; }
done
check "$ROOT/scripts/apply_nongki_4_4.sh" 'kernelsu-next\|sukisu-ultra' 'provider-native hook providers are explicit'
check "$ROOT/scripts/root_manager_apply.sh" 'SukiSU Ultra does not support Linux' 'SukiSU Ultra fails closed below 4.19'
check "$ROOT/scripts/apply_nongki_4_4.sh" 'exclude-dir=kernelsu' 'hook verification ignores the provider tree itself'

if (( fail == 0 )); then echo 'PASS: NonGKI 4.4 policy'; else exit 1; fi
