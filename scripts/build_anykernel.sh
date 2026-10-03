#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SELECTOR="$SCRIPT_DIR/select_anykernel_profile.sh"

WORK_DIR="${WORK_DIR:-$PWD/work}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$WORK_DIR/artifacts}"
OUTPUT_DIR="${OUTPUT_DIR:-$ARTIFACT_DIR}"
DEVICE="${DEVICE:-generic}"
KERNEL_VERSION="${KERNEL_VERSION:-}"
ROM_FAMILY="${ROM_FAMILY:-oss}"
ANYKERNEL_PROFILE_REQUESTED="${ANYKERNEL_PROFILE:-auto}"
ANYKERNEL3_REPO="${ANYKERNEL3_REPO:-https://github.com/osm0sis/AnyKernel3.git}"
ANYKERNEL3_REF_REQUESTED="${ANYKERNEL3_REF:-}"
KERNEL_IMAGE="${KERNEL_IMAGE:-}"
DTBO_IMAGE="${DTBO_IMAGE:-$ARTIFACT_DIR/dtbo.img}"
MODULES_ARCHIVE="${MODULES_ARCHIVE:-$ARTIFACT_DIR/modules.tar.gz}"
VERSION_TEXT="${VERSION_TEXT:-}"

log() { printf '[anykernel] %s\n' "$*"; }
die() { printf '[anykernel] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -x "$SELECTOR" ]] || die "missing selector: $SELECTOR"
[[ -d "$ARTIFACT_DIR" ]] || die "artifact directory not found: $ARTIFACT_DIR"

export PROFILE_DIR="$ROOT_DIR/anykernel/profiles"
PROFILE_FILE="$(DEVICE="$DEVICE" KERNEL_VERSION="$KERNEL_VERSION" ROM_FAMILY="$ROM_FAMILY" ANYKERNEL_PROFILE="$ANYKERNEL_PROFILE_REQUESTED" "$SELECTOR")"
# shellcheck source=/dev/null
source "$PROFILE_FILE"

: "${PROFILE_ID:?PROFILE_ID missing}"
: "${DEVICE_NAMES:?DEVICE_NAMES missing}"
: "${BLOCK:?BLOCK missing}"
: "${IS_SLOT_DEVICE:?IS_SLOT_DEVICE missing}"
: "${RAMDISK_COMPRESSION:?RAMDISK_COMPRESSION missing}"
: "${PATCH_VBMETA_FLAG:?PATCH_VBMETA_FLAG missing}"

REF="${ANYKERNEL3_REF_REQUESTED:-${ANYKERNEL3_REF:-master}}"
AK_WORK="$WORK_DIR/anykernel-$PROFILE_ID"
rm -rf "$AK_WORK"
mkdir -p "$AK_WORK" "$OUTPUT_DIR"

log "profile=$PROFILE_ID"
log "device=$DEVICE"
log "kernel=$KERNEL_VERSION"
log "rom=$ROM_FAMILY"
log "AnyKernel3=$REF"

if ! git clone --depth=1 --filter=blob:none "$ANYKERNEL3_REPO" "$AK_WORK" >/dev/null 2>&1; then
  die "unable to clone $ANYKERNEL3_REPO"
fi
if ! git -C "$AK_WORK" checkout --quiet "$REF" >/dev/null 2>&1; then
  git -C "$AK_WORK" fetch --depth=1 origin "$REF" >/dev/null 2>&1 || die "unable to fetch AnyKernel3 ref $REF"
  git -C "$AK_WORK" checkout --quiet "$REF" || die "unable to checkout AnyKernel3 ref $REF"
fi
UPSTREAM_COMMIT="$(git -C "$AK_WORK" rev-parse HEAD)"

if [[ -z "$KERNEL_IMAGE" ]]; then
  for candidate in \
    "$ARTIFACT_DIR/Image" \
    "$ARTIFACT_DIR/Image.gz" \
    "$ARTIFACT_DIR/Image.lz4" \
    "$ARTIFACT_DIR/Image.gz-dtb" \
    "$ARTIFACT_DIR/Image-dtb" \
    "$ARTIFACT_DIR/zImage"; do
    if [[ -f "$candidate" ]]; then
      KERNEL_IMAGE="$candidate"
      break
    fi
  done
fi
[[ -f "$KERNEL_IMAGE" ]] || die "kernel image not found"

# Remove upstream sample payloads; keep the official AnyKernel3 backend and installer.
rm -f "$AK_WORK/Image" "$AK_WORK/Image.gz" "$AK_WORK/Image.lz4" "$AK_WORK/Image.gz-dtb" "$AK_WORK/Image-dtb" "$AK_WORK/zImage" "$AK_WORK/dtbo.img" "$AK_WORK/version"
rm -rf "$AK_WORK/.git"

cp -f "$KERNEL_IMAGE" "$AK_WORK/$(basename "$KERNEL_IMAGE")"
if [[ "${FLASH_DTBO:-0}" == "1" && -f "$DTBO_IMAGE" ]]; then
  cp -f "$DTBO_IMAGE" "$AK_WORK/dtbo.img"
fi
if [[ "${DO_MODULES:-0}" == "1" && -f "$MODULES_ARCHIVE" ]]; then
  mkdir -p "$AK_WORK/modules/system/lib/modules"
  tar -xzf "$MODULES_ARCHIVE" -C "$AK_WORK/modules/system/lib/modules" || die "module extraction failed"
fi

cat > "$AK_WORK/banner" <<EOF_BANNER
============================================
              CI-Build AnyKernel3
============================================
Profile : $PROFILE_ID
Device  : $DEVICE
Kernel  : ${KERNEL_VERSION:-unknown}
ROM     : $ROM_FAMILY
============================================
EOF_BANNER

if [[ -n "$VERSION_TEXT" ]]; then
  printf '%s\n' "$VERSION_TEXT" > "$AK_WORK/version"
elif [[ -f "$ARTIFACT_DIR/build-info.txt" ]]; then
  cp -f "$ARTIFACT_DIR/build-info.txt" "$AK_WORK/version"
else
  cat > "$AK_WORK/version" <<EOF_VERSION
profile=$PROFILE_ID
device=$DEVICE
kernel_version=${KERNEL_VERSION:-unknown}
rom_family=$ROM_FAMILY
anykernel3_commit=$UPSTREAM_COMMIT
EOF_VERSION
fi

DEVICE_PROPS=""
index=1
for name in $DEVICE_NAMES; do
  DEVICE_PROPS+="device.name${index}=${name}"$'\n'
  index=$((index + 1))
  [[ $index -gt 8 ]] && break
done

cat > "$AK_WORK/anykernel.sh" <<EOF_AK
#!/sbin/sh

properties() { '
kernel.string=$KERNEL_STRING
do.devicecheck=$DO_DEVICECHECK
do.modules=$DO_MODULES
do.systemless=$DO_SYSTEMLESS
do.cleanup=1
do.cleanuponabort=0
${DEVICE_PROPS}supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=$BLOCK;
IS_SLOT_DEVICE=$IS_SLOT_DEVICE;
RAMDISK_COMPRESSION=$RAMDISK_COMPRESSION;
PATCH_VBMETA_FLAG=$PATCH_VBMETA_FLAG;
NO_MAGISK_CHECK=${NO_MAGISK_CHECK:-0};
FLASH_DTBO=${FLASH_DTBO:-0};

. tools/ak3-core.sh;

ui_print " ";
ui_print "CI-Build Custom AnyKernel3";
ui_print "Profile : $PROFILE_ID";
ui_print "Device  : $DEVICE";
ui_print "Kernel  : ${KERNEL_VERSION:-unknown}";
ui_print "ROM     : $ROM_FAMILY";
ui_print " ";

split_boot;

if [ -f dtbo.img ] && [ "$FLASH_DTBO" = 1 ]; then
    ui_print "Flashing DTBO...";
    flash_dtbo;
fi;

write_boot;

ui_print " ";
ui_print "Kernel installation completed.";
EOF_AK
chmod 755 "$AK_WORK/anykernel.sh"

ZIP="$OUTPUT_DIR/Kernel-${DEVICE}-${PROFILE_ID}-AnyKernel3.zip"
rm -f "$ZIP"
(
  cd "$AK_WORK"
  zip -r9 "$ZIP" . -x '*.git/*' '*.git*' >/dev/null
)
unzip -t "$ZIP" >/dev/null
SHA="$(sha256sum "$ZIP" | cut -d' ' -f1)"

log "created=$(basename "$ZIP")"
log "sha256=$SHA"
log "AnyKernel3 commit=$UPSTREAM_COMMIT"
printf 'ANYKERNEL_ZIP=%s\nANYKERNEL_PROFILE=%s\nANYKERNEL_SHA256=%s\nANYKERNEL3_COMMIT=%s\n' "$ZIP" "$PROFILE_ID" "$SHA" "$UPSTREAM_COMMIT"
