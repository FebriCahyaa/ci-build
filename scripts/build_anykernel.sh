#!/usr/bin/env bash
# Package one flashable AnyKernel3 ZIP from build artifacts.
#
# Inputs (environment):
#   ARTIFACT_DIR       directory with the kernel image(s) and build-info.txt
#   DEVICE KERNEL_VERSION ANYKERNEL_PROFILE ROOT_VARIANT
#   KERNEL_NAME KERNEL_RELEASE SCHEDULER TOOLCHAIN KBUILD_BUILD_USER KBUILD_BUILD_HOST SOURCE
#   ANYKERNEL3_REPO    "local" (default, ./anykernel) or a git URL of a Zairenkai-layout AnyKernel3 fork
#   ANYKERNEL3_REF     branch/tag/commit when ANYKERNEL3_REPO is a URL
#
# stdout: ANYKERNEL_ZIP / ANYKERNEL_PROFILE / ANYKERNEL_SHA256 / ANYKERNEL3_COMMIT assignments.
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
CI_LOG_TAG=anykernel

WORK_DIR="${WORK_DIR:-$PWD/work}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$WORK_DIR/artifacts}"
OUTPUT_DIR="${OUTPUT_DIR:-$ARTIFACT_DIR}"
DEVICE="${DEVICE:-generic}"
KERNEL_VERSION="${KERNEL_VERSION:-}"
VARIANT="$(normalize_variant "${ROOT_VARIANT:-vanilla}")" || ci_die "invalid ROOT_VARIANT=${ROOT_VARIANT:-}"
ANYKERNEL3_REPO="${ANYKERNEL3_REPO:-local}"
ANYKERNEL3_REF="${ANYKERNEL3_REF:-master}"

[[ -d "$ARTIFACT_DIR" ]] || ci_die "artifact directory not found: $ARTIFACT_DIR"

PROFILE_FILE="$(DEVICE="$DEVICE" KERNEL_VERSION="$KERNEL_VERSION" ANYKERNEL_PROFILE="${ANYKERNEL_PROFILE:-auto}" \
  bash "$CI_ROOT/scripts/select_anykernel_profile.sh")"
# shellcheck source=/dev/null
source "$PROFILE_FILE"
: "${PROFILE_ID:?PROFILE_ID missing in $PROFILE_FILE}"
: "${KERNEL_IMAGES:?KERNEL_IMAGES missing in $PROFILE_FILE}"

AK_WORK="$WORK_DIR/anykernel-$PROFILE_ID-$VARIANT"
rm -rf "$AK_WORK"
mkdir -p "$OUTPUT_DIR"

case "$ANYKERNEL3_REPO" in
  local|vendored|"")
    cp -a "$CI_ROOT/anykernel" "$AK_WORK"
    AK_COMMIT="$(git -C "$CI_ROOT" rev-parse --short HEAD 2>/dev/null || echo local)"
    ;;
  *)
    git_fetch_ref "$ANYKERNEL3_REPO" "$ANYKERNEL3_REF" "$AK_WORK" || ci_die "unable to fetch $ANYKERNEL3_REPO@$ANYKERNEL3_REF"
    AK_COMMIT="$(git -C "$AK_WORK" rev-parse --short HEAD)"
    rm -rf "$AK_WORK/.git"
    # Upstream osm0sis/AnyKernel3 has no Zairenkai templates: overlay them.
    if [[ ! -f "$AK_WORK/ci-patch.sh" ]]; then
      cp -a "$CI_ROOT/anykernel/"{anykernel.sh,banner,ci-patch.sh,version.conf,profiles} "$AK_WORK/"
    fi
    ;;
esac

# Drop sample payloads, then copy the first kernel image the profile accepts.
for img in Image Image.gz Image.lz4 Image.gz-dtb Image-dtb zImage zImage-dtb dtb dtbo.img; do
  rm -f "$AK_WORK/$img"
done
KERNEL_IMAGE=""
for img in $KERNEL_IMAGES; do
  if [[ -f "$ARTIFACT_DIR/$img" ]]; then
    KERNEL_IMAGE="$img"
    cp -f "$ARTIFACT_DIR/$img" "$AK_WORK/$img"
    break
  fi
done
[[ -n "$KERNEL_IMAGE" ]] || ci_die "no kernel image for $PROFILE_ID in $ARTIFACT_DIR (wanted: $KERNEL_IMAGES)"
# Separate DTB (when the kernel image has none appended) and optional DTBO.
if [[ "$KERNEL_IMAGE" != *-dtb && -f "$ARTIFACT_DIR/dtb" && "${GKI:-0}" != 1 ]]; then
  cp -f "$ARTIFACT_DIR/dtb" "$AK_WORK/dtb"
fi
if [[ "${FLASH_DTBO:-0}" == 1 && -f "$ARTIFACT_DIR/dtbo.img" ]]; then
  cp -f "$ARTIFACT_DIR/dtbo.img" "$AK_WORK/dtbo.img"
fi

CODENAME="$(read_value_file "$CI_ROOT/kernel-codename")"
BUILD_NUM="$(read_value_file "$CI_ROOT/kernel-build")"
KERNEL_NAME="${KERNEL_NAME:-$(read_value_file "$CI_ROOT/kernel-name")}"
KERNEL_NAME="${KERNEL_NAME#-}"
KERNEL_NAME="${KERNEL_NAME:-Zairenkai}"
CODENAME="${CODENAME:-VEGA}"
BUILD_NUM="${BUILD_NUM:-1}"
BUILD_LABEL="${KERNEL_NAME}-${CODENAME}${BUILD_NUM}"

KERNEL_NAME="$KERNEL_NAME" KERNEL_CODENAME="$CODENAME" KERNEL_BUILD="$BUILD_NUM" BUILD_LABEL="$BUILD_LABEL" \
KERNEL_RELEASE="${KERNEL_RELEASE:-}" SCHEDULER="${SCHEDULER:-}" TOOLCHAIN="${TOOLCHAIN:-}" \
BUILD_USER="${KBUILD_BUILD_USER:-}" BUILD_HOST="${KBUILD_BUILD_HOST:-}" SOURCE="${SOURCE:-}" \
  bash "$AK_WORK/ci-patch.sh" --profile "$PROFILE_ID" --variant "$VARIANT" --dir "$AK_WORK" >&2

# Shipped for traceability only. update-binary no longer prints it while flashing.
[[ -f "$ARTIFACT_DIR/build-info.txt" ]] && cp -f "$ARTIFACT_DIR/build-info.txt" "$AK_WORK/build-info.txt"
rm -rf "$AK_WORK/ci-patch.sh" "$AK_WORK/build.sh" "$AK_WORK/version.conf" "$AK_WORK/README.md" \
       "$AK_WORK/CI.md" "$AK_WORK/profiles" "$AK_WORK/images" "$AK_WORK/out"

# Lavender 4.4 ships HMP and EAS builds; keep the scheduler in the file name.
SCHED_TAG=""
if [[ "$(wc -w <<< "${SCHEDULERS:-}")" -gt 1 && -n "${SCHEDULER:-}" && "${SCHEDULER}" != none ]]; then
  SCHED_TAG="-${SCHEDULER}"
fi
ZIP="$OUTPUT_DIR/${BUILD_LABEL}-${DEVICE}-${KERNEL_FAMILY}${SCHED_TAG}-$(variant_label "$VARIANT")-$(date -u +%Y%m%d).zip"
rm -f "$ZIP"
(cd "$AK_WORK" && zip -r9 -q "$ZIP" . -x '*.git*')
unzip -tq "$ZIP" >/dev/null
SHA="$(sha256sum "$ZIP" | cut -d' ' -f1)"

ci_log "created=$(basename "$ZIP") sha256=$SHA profile=$PROFILE_ID image=$KERNEL_IMAGE ak3=$AK_COMMIT"
printf 'ANYKERNEL_ZIP=%q\nANYKERNEL_PROFILE=%q\nANYKERNEL_SHA256=%q\nANYKERNEL3_COMMIT=%q\n' \
  "$ZIP" "$PROFILE_ID" "$SHA" "$AK_COMMIT"
