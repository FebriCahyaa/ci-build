#!/usr/bin/env bash
# Standalone AnyKernel3 packager.
# Usage: ./build.sh <profile> [variant ...]
#   variant: vanilla | kernelsu | kernelsu-next | resukisu | resukisu-susfs | sukisu-ultra (aliases accepted)
set -Eeuo pipefail
cd "$(dirname -- "$0")"

PROFILE="${1:?usage: ./build.sh <profile> [variant ...]}"
shift || true
VARIANT_ARGS=("$@")
if ((${#VARIANT_ARGS[@]} == 0)); then
  read -r -a VARIANT_ARGS <<< "${VARIANTS:-vanilla kernelsu-next resukisu sukisu-ultra}"
fi

OUT="${OUT:-out}"
PROFILE_FILE="profiles/$PROFILE.conf"
[[ -f "$PROFILE_FILE" ]] || { echo "ERROR: unknown AnyKernel profile: $PROFILE" >&2; exit 2; }
# shellcheck source=/dev/null
source "$PROFILE_FILE"

mkdir -p "$OUT" images
for raw in "${VARIANT_ARGS[@]}"; do
  case "${raw,,}" in
    vanilla|none|false) VARIANT=vanilla ;;
    ksu|kernelsu|official) VARIANT=kernelsu ;;
    ksun|kernelsu-next|next) VARIANT=kernelsu-next ;;
    resukisu|re-sukisu) VARIANT=resukisu ;;
    resukisu-susfs|resukisu+susfs) VARIANT=resukisu-susfs ;;
    suki|sukisu|sukisu-ultra|sukisu_ultra|sukisuultra) VARIANT=sukisu-ultra ;;
    *) echo "ERROR: unsupported variant: $raw" >&2; exit 2 ;;
  esac

  W="$(mktemp -d)"
  cp -a . "$W/"
  rm -rf "$W/out" "$W/images" "$W/.git"

  found=""
  for img in $KERNEL_IMAGES; do
    if [[ -f "images/$VARIANT/$img" ]]; then
      cp -f "images/$VARIANT/$img" "$W/$img"
      found="$img"
      break
    fi
  done
  [[ -n "$found" ]] || { echo "ERROR: no kernel image for $PROFILE/$VARIANT (wanted: $KERNEL_IMAGES)" >&2; exit 1; }

  KERNEL_NAME="${KERNEL_NAME:-Zairenkai}"
  KERNEL_NAME="$KERNEL_NAME" BUILD_LABEL="${BUILD_LABEL:-$KERNEL_NAME-$PROFILE}" \
    KERNEL_RELEASE="${KERNEL_RELEASE:-}" SCHEDULER="${SCHEDULER:-}" TOOLCHAIN="${TOOLCHAIN:-}" \
    bash "$W/ci-patch.sh" --profile "$PROFILE" --variant "$VARIANT" --dir "$W" >&2

  rm -rf "$W/ci-patch.sh" "$W/build.sh" "$W/version.conf" "$W/README.md" "$W/CI.md" "$W/profiles" "$W/images" "$W/out"
  if [[ "$OUT" = /* ]]; then
    ZIP="$OUT/${KERNEL_NAME:-Zairenkai}-$PROFILE-$VARIANT-$(date -u +%Y%m%d).zip"
  else
    ZIP="$PWD/$OUT/${KERNEL_NAME:-Zairenkai}-$PROFILE-$VARIANT-$(date -u +%Y%m%d).zip"
  fi
  rm -f "$ZIP"
  (cd "$W" && zip -r9 -q "$ZIP" . -x '*.git*')
  unzip -tq "$ZIP" >/dev/null
  rm -rf "$W"
  echo "[+] $ZIP (image=$found)"
done
