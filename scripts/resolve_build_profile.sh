#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_DIR="$ROOT_DIR/profiles/targets"
REQUESTED="${1:-${BUILD_PROFILE:-auto}}"
DEVICE_HINT="${DEVICE:-}"
FAMILY_HINT="${KERNEL_FAMILY:-}"

case "$REQUESTED" in
  auto)
    case "$DEVICE_HINT:$FAMILY_HINT" in
      lavender:4.4*) PROFILE="lavender-4.4" ;;
      lavender:4.19*) PROFILE="lavender-4.19" ;;
      garnet:5.10*|garnet:*) PROFILE="garnet-gki" ;;
      *) echo "ERROR: BUILD_PROFILE=auto needs DEVICE and KERNEL_FAMILY" >&2; exit 2 ;;
    esac
    ;;
  lavender-4.4|lavender-4.19|garnet-gki) PROFILE="$REQUESTED" ;;
  *) echo "ERROR: unknown build profile: $REQUESTED" >&2; ls -1 "$PROFILE_DIR"/*.conf 2>/dev/null | sed 's#.*/##; s#\.conf$##' >&2; exit 2 ;;
esac

PROFILE_FILE="$PROFILE_DIR/$PROFILE.conf"
[[ -f "$PROFILE_FILE" ]] || { echo "ERROR: missing profile $PROFILE_FILE" >&2; exit 2; }
# shellcheck source=/dev/null
source "$PROFILE_FILE"

keys=(
  PROFILE_ID PROFILE_DEVICE PROFILE_KERNEL_FAMILY PROFILE_ARCH
  PROFILE_KERNEL_REPO PROFILE_KERNEL_REF PROFILE_KERNEL_REF_TYPE
  PROFILE_DEFCONFIG PROFILE_CONFIG_FRAGMENT PROFILE_SCHEDULER_PROFILE
  PROFILE_PATCH_PROFILE PROFILE_UPSTREAM_PROFILE PROFILE_LTO_PLUS
  PROFILE_ROM_FAMILY PROFILE_ANYKERNEL_PROFILE PROFILE_ANYKERNEL3_REF
  PROFILE_PACKAGE_ANYKERNEL PROFILE_DYNAMIC_PARTITION PROFILE_GKI
  PROFILE_SOURCE_LABEL PROFILE_KSU_NEXT_LEGACY_REF PROFILE_KSU_NEXT_GKI_REF
  PROFILE_RESUKISU_REF PROFILE_SUKISU_ULTRA_REF PROFILE_NONGKI_4_4_HOOKS PROFILE_NONGKI_4_4_MODE
)
for key in "${keys[@]}"; do
  printf '%s=%q\n' "$key" "${!key:-}"
done
