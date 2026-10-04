#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="${PROFILE_DIR:-$SCRIPT_DIR/../anykernel/profiles}"
PROFILE_DIR="$(cd -- "$PROFILE_DIR" && pwd -P)"

# Positional arguments are supported for local/harness callers:
#   select_anykernel_profile.sh <device> <kernel_version> [rom_family] [profile]
DEVICE="${DEVICE:-${1:-generic}}"
KERNEL_VERSION="${KERNEL_VERSION:-${2:-}}"
ROM_FAMILY="${ROM_FAMILY:-${3:-oss}}"
REQUESTED="${ANYKERNEL_PROFILE:-${4:-auto}}"

list_profiles() {
  find "$PROFILE_DIR" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' | sed 's/\.conf$//' | sort
}

# Normalize 4.4/4.19/5.10 forms while accepting a full kernel release string.
case "$KERNEL_VERSION" in
  4.4|4.4.*) FAMILY=4.4 ;;
  4.19|4.19.*) FAMILY=4.19 ;;
  5.10|5.10.*) FAMILY=5.10 ;;
  *) FAMILY="${KERNEL_VERSION%%.*}.$(cut -d. -f2 <<< "$KERNEL_VERSION")" ;;
esac

case "$REQUESTED" in
  auto|"")
    case "$DEVICE:$FAMILY" in
      lavender:4.4) PROFILE="lavender-4.4" ;;
      lavender:4.19) PROFILE="lavender-4.19" ;;
      garnet:5.10) PROFILE="garnet-gki" ;;
      *)
        echo "ERROR: cannot auto-select AnyKernel profile for DEVICE=$DEVICE KERNEL_VERSION=$KERNEL_VERSION ROM_FAMILY=$ROM_FAMILY" >&2
        echo "Available profiles:" >&2
        list_profiles >&2
        exit 2
        ;;
    esac
    ;;
  *) PROFILE="$REQUESTED" ;;
esac

PROFILE_FILE="$PROFILE_DIR/$PROFILE.conf"
[[ -f "$PROFILE_FILE" ]] || {
  echo "ERROR: AnyKernel profile not found: $PROFILE" >&2
  echo "Available profiles:" >&2
  list_profiles >&2
  exit 2
}

printf '%s\n' "$PROFILE_FILE"
