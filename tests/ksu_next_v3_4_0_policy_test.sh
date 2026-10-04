#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check() {
  local file="$1" pattern="$2" label="$3"
  if grep -qF "$pattern" "$file"; then echo "PASS: $label"; else echo "FAIL: $label" >&2; fail=1; fi
}
check "$ROOT/profiles/targets/lavender-4.19.conf" 'PROFILE_KSU_NEXT_LEGACY_REF="v3.4.0"' 'lavender 4.19 uses KernelSU-Next v3.4.0'
check "$ROOT/profiles/targets/lavender-4.4.conf" 'PROFILE_KSU_NEXT_4_4_REF="v1.1.1"' 'lavender 4.4 keeps KernelSU-Next v1.1.1 compatibility pin'
check "$ROOT/profiles/targets/garnet-gki.conf" 'PROFILE_KSU_NEXT_GKI_REF="v3.4.0"' 'garnet GKI uses KernelSU-Next v3.4.0'
check "$ROOT/scripts/root_manager_apply.sh" 'if [[ "$KERNEL_MM" == "4.4" ]]; then' '4.4 gets an explicit legacy provider pin'
check "$ROOT/scripts/build_kernel.sh" 'KSU_NEXT_4_4_REF' 'build kernel carries the dedicated 4.4 KSU-Next pin'
check "$ROOT/scripts/build_kernel.sh" 'KSU_NEXT_LEGACY_REF' 'build kernel carries the 4.19 KSU-Next pin'
check "$ROOT/scripts/build_variants.sh" 'KSU_NEXT_4_4_REF' 'matrix build carries the dedicated 4.4 KSU-Next pin'
check "$ROOT/scripts/root_manager_apply.sh" 'PROVIDER_REF="$KSU_NEXT_GKI_REF"' 'GKI selects v3.4.0 provider channel'
check "$ROOT/scripts/root_manager_apply.sh" 'PROVIDER_REF="$KSU_NEXT_LEGACY_REF"' '4.19 legacy selects v3.4.0 provider channel'
check "$ROOT/patches/root-manager/kernelsu-next/README.md" 'Linux 4.19 legacy builds use `v3.4.0`' 'KernelSU-Next provider documentation'
exit "$fail"
