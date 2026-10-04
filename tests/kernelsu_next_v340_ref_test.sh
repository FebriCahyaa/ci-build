#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
grep -q 'KSU_NEXT_LEGACY_REF="${KSU_NEXT_LEGACY_REF:-v3.4.0}"' "$ROOT/scripts/root_manager_apply.sh"
grep -q 'KSU_NEXT_GKI_REF="${KSU_NEXT_GKI_REF:-v3.4.0}"' "$ROOT/scripts/root_manager_apply.sh"
grep -q '1a879d6a866f80b1fa1c1009a2ffa747873cbb5e' "$ROOT/scripts/root_manager_apply.sh"
echo 'PASS: KernelSU-Next v3.4.0 is deterministically pinned for 4.19+/GKI'
