#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="${PROFILE_DIR:-$SCRIPT_DIR/../anykernel/profiles}"

DEVICE="${DEVICE:-generic}"
KERNEL_VERSION="${KERNEL_VERSION:-}"
ROM_FAMILY="${ROM_FAMILY:-oss}"
REQUESTED="${ANYKERNEL_PROFILE:-auto}"

list_profiles() {
  find "$PROFILE_DIR" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' | sed 's/\.conf$//' | sort
}

case "$REQUESTED" in
  auto|"")
    case "$DEVICE:$KERNEL_VERSION" in
      lavender:4.4*|lavender:4.4)
        PROFILE="lavender-4.4" ;;
      lavender:4.19*|lavender:4.19)
        PROFILE="lavender-4.19" ;;
      garnet:*)
        case "${ROM_FAMILY,,}" in
          hyperos|hyper-os|miui)
            PROFILE="garnet-hyperos" ;;
          *)
            PROFILE="garnet-oss" ;;
        esac
        ;;
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
