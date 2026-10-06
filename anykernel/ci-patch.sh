#!/usr/bin/env bash
# ci-patch.sh - render the AnyKernel3 templates (anykernel.sh + banner) for one
# device profile and one root variant. Called by ci-build before zipping.
#
# Usage:
#   ./ci-patch.sh --profile <profile> --variant <variant> [--dir DIR]
#   ./ci-patch.sh <variant> [DIR]                 # legacy form, profile from $PROFILE_ID
#
#   profile : lavender-4.4 | lavender-4.19 | garnet-gki   (see profiles/)
#   variant : vanilla | kernelsu | kernelsu-next | resukisu | resukisu-susfs | sukisu-ultra (aliases: ksu, ksun)
#
# Optional environment (empty -> auto-detected from the kernel image / fallback):
#   KERNEL_NAME KERNEL_CODENAME KERNEL_BUILD BUILD_LABEL KERNEL_RELEASE SCHEDULER
#   TOOLCHAIN BUILD_USER BUILD_HOST BUILD_DATE MAINTAINER SOURCE
#
# The banner is kept narrow (<= 42 columns) so KernelSU/Magisk/APatch managers and
# recoveries do not wrap it. @RT_ANDROID@ and @RT_ROM@ are intentionally left in the
# rendered banner: update-binary resolves them on the device while flashing.
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true   # '&' in values is not special

PROFILE="${PROFILE_ID:-lavender-4.19}"
VARIANT=""
DIR="."

while (($#)); do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --variant) VARIANT="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *)
      if [[ -z "$VARIANT" ]]; then VARIANT="$1"; else DIR="$1"; fi
      shift
      ;;
  esac
done

case "${VARIANT,,}" in
  vanilla|none)            ROOT="None";          MODE="Vanilla (no root integrated)" ;;
  ksu|kernelsu)            ROOT="KernelSU";      MODE="KernelSU integrated" ;;
  ksun|kernelsu-next|next) ROOT="KernelSU-Next"; MODE="KernelSU-Next integrated" ;;
  resukisu)                ROOT="ReSukiSU";      MODE="ReSukiSU integrated" ;;
  resukisu-susfs)          ROOT="ReSukiSU";      MODE="ReSukiSU + SUSFS integrated" ;;
  sukisu-ultra|sukisu_ultra|sukisuultra) ROOT="SukiSU Ultra"; MODE="SukiSU Ultra integrated" ;;
  *) echo "[ci-patch] unknown variant '$VARIANT' (vanilla|kernelsu|kernelsu-next|resukisu|resukisu-susfs|sukisu-ultra)" >&2; exit 1 ;;
esac

PROFILE_FILE="$DIR/profiles/$PROFILE.conf"
[[ -f "$PROFILE_FILE" ]] || { echo "[ci-patch] profile not found: $PROFILE_FILE" >&2; exit 1; }
# shellcheck source=/dev/null
source "$PROFILE_FILE"
[[ -f "$DIR/version.conf" ]] && source "$DIR/version.conf"

KERNEL_NAME="${KERNEL_NAME:-Zairenkai}"
CODENAME="$(printf '%s' "${KERNEL_CODENAME:-${CODENAME:-VEGA}}" | tr '[:lower:]' '[:upper:]')"
BUILD_NUM="${KERNEL_BUILD:-${BUILD:-1}}"
BUILD_LABEL="${BUILD_LABEL:-$KERNEL_NAME-$CODENAME$BUILD_NUM}"

# Best-effort metadata from the linux_banner embedded in the kernel image.
K_REL="${KERNEL_RELEASE:-}"; B_USER="${BUILD_USER:-${KBUILD_BUILD_USER:-}}"
B_HOST="${BUILD_HOST:-${KBUILD_BUILD_HOST:-}}"; TC="${TOOLCHAIN:-}"
for img in $KERNEL_IMAGES; do
  [[ -f "$DIR/$img" ]] || continue
  case "$img" in
    *.gz*) LB="$(gzip -dc < "$DIR/$img" 2>/dev/null | grep -a -m1 -o 'Linux version [0-9][^#]*' || true)" ;;
    *.lz4) LB="$(lz4 -dc < "$DIR/$img" 2>/dev/null | grep -a -m1 -o 'Linux version [0-9][^#]*' || true)" ;;
    *) LB="$(grep -a -m1 -o 'Linux version [0-9][^#]*' "$DIR/$img" || true)" ;;
  esac
  if [[ -n "$LB" ]]; then
    [[ -n "$K_REL" ]]  || K_REL="$(awk '{print $3}' <<< "$LB")"
    [[ -n "$B_USER" ]] || B_USER="$(sed -n 's/.*(\([^@ ()]*\)@\([^) ]*\)).*/\1/p' <<< "$LB")"
    [[ -n "$B_HOST" ]] || B_HOST="$(sed -n 's/.*(\([^@ ()]*\)@\([^) ]*\)).*/\2/p' <<< "$LB")"
    [[ -n "$TC" ]]     || TC="$(grep -o '\(Android clang\|clang\|gcc\)[^)]*' <<< "$LB" | head -n1 | sed 's/ (.*//' | cut -c1-48)"
  fi
  break
done

K_REL="${K_REL:-$KERNEL_FAMILY.x}"
B_USER="${B_USER:-$(whoami)}"
B_HOST="${B_HOST:-$(hostname)}"
TC="${TC:-unknown}"
SCHED="${SCHEDULER:-}"
[[ -z "$SCHED" || "$SCHED" == none ]] && SCHED="${SCHEDULERS%% *}"
if [[ " $SCHEDULERS " != *" $SCHED "* ]]; then
  echo "[ci-patch] WARNING: scheduler '$SCHED' is not listed for $PROFILE_ID ($SCHEDULERS)" >&2
fi

case "$DYNAMIC_PARTITIONS" in
  required)  PARTITION_LABEL="Dynamic (super) required" ;;
  supported) PARTITION_LABEL="Legacy + Dynamic (retrofit)" ;;
  *)         PARTITION_LABEL="Legacy" ;;
esac

# clip <text> [max]: single-line banner value, ellipsised so a row never wraps.
clip() {
  local v="${1//$'\n'/ }" n="${2:-28}"
  v="${v//[^[:print:]]/}"
  if ((${#v} > n)); then v="${v:0:n-3}..."; fi
  printf '%s' "$v"
}

# compact_toolchain <raw compiler string>: "Clang 12.0.5 (r416183b)" instead of the
# full "Android (..., based on r416183b) clang version 12.0.5 (https://...)" line.
compact_toolchain() {
  local raw="$1" ver rev
  ver="$(grep -oE 'clang version [0-9][0-9.]*' <<< "$raw" | head -n1 | awk '{print $3}' || true)"
  rev="$(grep -oE '\br[0-9]{5,}[a-z]?' <<< "$raw" | head -n1 || true)"
  if [[ -n "$ver" ]]; then
    printf 'Clang %s%s' "$ver" "${rev:+ ($rev)}"
  else
    sed 's/ (.*//' <<< "$raw"
  fi
}

# compact_source <repo url|name>: "xiaomi_sdm660_southwest-ng" from the full repo URL.
compact_source() {
  local v="$1"
  v="${v%/}"; v="${v##*/}"; v="${v%.git}"; v="${v#android_kernel_}"
  printf '%s' "${v:-unknown}"
}

DEVICE_PROPS=""
i=1
for name in $DEVICE_NAMES; do
  DEVICE_PROPS+="device.name${i}=${name}"$'\n'
  i=$((i + 1))
done
DEVICE_PROPS="${DEVICE_PROPS%$'\n'}"

KERNEL_STRING="$KERNEL_NAME Kernel $CODENAME$BUILD_NUM | ${DEVICE_NAMES%% *} $KERNEL_FAMILY | $ROOT"

declare -A VALUES=(
  [PROFILE_ID]="$PROFILE_ID" [PROFILE_DESC]="$PROFILE_DESC"
  [DO_DEVICECHECK]="1" [DO_MODULES]="0" [DO_SYSTEMLESS]="1"
  [KERNEL_STRING]="$KERNEL_STRING" [DEVICE_PROPS]="$DEVICE_PROPS"
  [SUPPORTED_VERSIONS]="$SUPPORTED_VERSIONS" [BLOCK]="$BLOCK" [IS_SLOT_DEVICE]="$IS_SLOT_DEVICE"
  [KERNEL_FAMILY]="$KERNEL_FAMILY" [DYNAMIC_PARTITIONS]="$DYNAMIC_PARTITIONS" [GKI]="$GKI"
  [FLASH_DTBO]="$FLASH_DTBO" [SCHEDULER]="$SCHED" [ROOT]="$ROOT" [MODE]="$MODE"
  [KERNEL_RELEASE]="$(clip "$K_REL")" [CODENAME]="$CODENAME" [BUILD_LABEL]="$(clip "$BUILD_LABEL")"
  [DEVICE_LABEL]="$(clip "$DEVICE_LABEL")" [PARTITION_LABEL]="$(clip "$PARTITION_LABEL")"
  [TOOLCHAIN]="$(clip "$(compact_toolchain "$TC")")" [BUILD_USER]="$(clip "$B_USER")" [BUILD_HOST]="$(clip "$B_HOST")"
  [BUILD_DATE]="${BUILD_DATE:-$(date -u +%Y-%m-%d)}"
  [MAINTAINER]="$(clip "${MAINTAINER:-Febrian Rahmad Cahya}")" [SOURCE]="$(clip "$(compact_source "${SOURCE:-unknown}")")"
)

render() {
  local f="$1" c key
  [[ -f "$f" ]] || { echo "[ci-patch] missing template: $f" >&2; exit 1; }
  c="$(cat "$f")"
  for key in "${!VALUES[@]}"; do
    c="${c//@${key}@/${VALUES[$key]}}"
  done
  printf '%s\n' "$c" > "$f"   # overwrite content only; keep file mode
}

render "$DIR/banner"
render "$DIR/anykernel.sh"

# @RT_*@ tokens are resolved on the device by update-binary, so they are not errors.
if grep -nE '@[A-Z_]+@' "$DIR/banner" "$DIR/anykernel.sh" | grep -vE '@RT_(ANDROID|ROM)@'; then
  echo "[ci-patch] unresolved placeholders remain" >&2
  exit 1
fi
echo "[ci-patch] $PROFILE_ID | $BUILD_LABEL | $ROOT | $K_REL | $SCHED | $TC"
