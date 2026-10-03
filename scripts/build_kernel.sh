#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/tg.sh"

: "${KERNEL_REPO:?KERNEL_REPO is required}"
KERNEL_BRANCH="${KERNEL_BRANCH:-main}"
DEVICE="${DEVICE:-generic}"
ARCH="${ARCH:-auto}"
DEFCONFIG="${DEFCONFIG:-auto}"
CONFIG_FRAGMENT="${CONFIG_FRAGMENT:-auto}"
KERNEL_REF_TYPE="${KERNEL_REF_TYPE:-auto}"
JOBS="${JOBS:-0}"
KERNEL_TARGET="${KERNEL_TARGET:-}"
TOOLCHAIN="${TOOLCHAIN:-auto}"
TOOLCHAIN_VERSION="${TOOLCHAIN_VERSION:-auto}"
LLVM="${LLVM:-auto}"
LLVM_IAS="${LLVM_IAS:-auto}"
CROSS_COMPILE="${CROSS_COMPILE:-auto}"
CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32:-}"
CLANG_URL="${CLANG_URL:-}"
GCC_URL="${GCC_URL:-}"
APT_PACKAGES="${APT_PACKAGES:-}"
EXTRA_MAKE_ARGS="${EXTRA_MAKE_ARGS:-}"
SCHEDULER_PROFILE="${SCHEDULER_PROFILE:-auto}"
ENABLE_KSU="${ENABLE_KSU:-false}"
KSU_REF="${KSU_REF:-}"
PACKAGE_ANYKERNEL="${PACKAGE_ANYKERNEL:-false}"
ROM_FAMILY="${ROM_FAMILY:-oss}"
ANYKERNEL_PROFILE="${ANYKERNEL_PROFILE:-auto}"
ANYKERNEL_REPO="${ANYKERNEL_REPO:-https://github.com/osm0sis/AnyKernel3}"
ANYKERNEL_BRANCH="${ANYKERNEL_BRANCH:-master}"
ANYKERNEL3_REPO="${ANYKERNEL3_REPO:-$ANYKERNEL_REPO}"
ANYKERNEL3_REF="${ANYKERNEL3_REF:-$ANYKERNEL_BRANCH}"
BUILD_ENV="${BUILD_ENV:-}"
RUN_URL="${RUN_URL:-}"

START="$(date +%s)"
WORK="${WORK_DIR:-$PWD/work}"
SRC_DIR="$WORK/kernel"
OUT="${KERNEL_OUT:-$WORK/kernel-out}"
ARTIFACTS="$WORK/artifacts"
BUILD_LOG="$WORK/build.log"
mkdir -p "$WORK" "$ARTIFACTS"

fail() {
  local reason="$1"
  local duration=$(( $(date +%s) - START ))
  tg_edit "${MID:-}" "❌ <b>Kernel build gagal</b>
📱 $DEVICE | 🏗 ${DETECTED_ARCH:-$ARCH}
🧩 Tahap: <code>$reason</code>
⏱ $(fmt_dur "$duration")
🔗 <a href=\"$RUN_URL\">CI log</a>"
  [[ -f "$BUILD_LOG" ]] && { tail -n 300 "$BUILD_LOG" > "$WORK/error_tail.log" || true; tg_file "$WORK/error_tail.log" "📄 Last 300 build log lines — $DEVICE"; }
  exit 1
}
trap 'fail "unexpected error at line $LINENO"' ERR

if [[ "$JOBS" == "0" || -z "$JOBS" ]]; then JOBS="$(nproc 2>/dev/null || echo 2)"; fi

# ---- Source checkout ----
rm -rf "$SRC_DIR"
case "$KERNEL_REF_TYPE" in
  auto)
    if [[ "$KERNEL_BRANCH" =~ ^[0-9a-fA-F]{40}$ || "$KERNEL_BRANCH" =~ ^[0-9a-fA-F]{64}$ ]]; then
      KERNEL_REF_TYPE=commit
    else
      KERNEL_REF_TYPE=branch
    fi
    ;;
  branch|tag|commit)
    ;;
  *)
    fail "invalid KERNEL_REF_TYPE=$KERNEL_REF_TYPE"
    ;;
esac

if [[ "$KERNEL_REF_TYPE" == commit ]]; then
  git init "$SRC_DIR" >/dev/null
  git -C "$SRC_DIR" remote add origin "$KERNEL_REPO"
  git -C "$SRC_DIR" fetch --depth=1 origin "$KERNEL_BRANCH" || fail "fetch kernel commit"
  git -C "$SRC_DIR" checkout --detach FETCH_HEAD || fail "checkout kernel commit"
else
  git clone --depth=1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$SRC_DIR" || fail "clone kernel"
fi

cd "$SRC_DIR"
COMMIT="$(git log -1 --pretty='%h %s')"
COMMIT_SHA="$(git rev-parse HEAD)"

# ---- Auto-detect architecture / defconfig / fragment ----
DETECT_ENV="$WORK/detection.env"
ARCH="$ARCH" DEVICE="$DEVICE" DEFCONFIG="$DEFCONFIG" CONFIG_FRAGMENT="$CONFIG_FRAGMENT" \
  "$SCRIPT_DIR/detect_defconfig.sh" --repo "$SRC_DIR" --arch "$ARCH" --device "$DEVICE" --defconfig "$DEFCONFIG" --fragment "$CONFIG_FRAGMENT" > "$DETECT_ENV" || fail "auto-detect"
source "$DETECT_ENV"

# Detection script returns paths relative to arch/$ARCH/configs.
SELECTED_FRAGMENT=""
if [[ -n "${DETECTED_FRAGMENT:-}" ]]; then
  SELECTED_FRAGMENT="$SRC_DIR/arch/$DETECTED_ARCH/configs/$DETECTED_FRAGMENT"
  [[ -f "$SELECTED_FRAGMENT" ]] || fail "detected fragment missing"
fi

# ---- Optional user build environment ----
if [[ -n "$BUILD_ENV" ]]; then eval "$BUILD_ENV"; fi

# ---- Toolchain resolution ----
TOOLCHAIN_ENV="$WORK/toolchain.env"
TOOLCHAIN="$TOOLCHAIN" TOOLCHAIN_VERSION="$TOOLCHAIN_VERSION" ARCH="$DETECTED_ARCH" \
  CLANG_URL="$CLANG_URL" GCC_URL="$GCC_URL" \
  "$SCRIPT_DIR/toolchain_resolver.sh" "$SRC_DIR" "$WORK" > "$TOOLCHAIN_ENV" || fail "toolchain resolution"
source "$TOOLCHAIN_ENV"

if [[ -n "${RESOLVED_TOOLCHAIN_BIN:-}" ]]; then
  export PATH="${RESOLVED_TOOLCHAIN_BIN}:$PATH"
fi
export PATH

if [[ -n "${CROSS_COMPILE:-}" && "$CROSS_COMPILE" != auto ]]; then
  CROSS_DEFAULT="$CROSS_COMPILE"
else
  CROSS_DEFAULT="$RESOLVED_CROSS_DEFAULT"
fi
CLANG_TRIPLE="${RESOLVED_CLANG_TRIPLE:-}"

LLVM_VALUE="${RESOLVED_LLVM:-1}"
LLVM_IAS_VALUE="${RESOLVED_LLVM_IAS:-1}"
[[ "$LLVM" != auto ]] && LLVM_VALUE="$LLVM"
[[ "$LLVM_IAS" != auto ]] && LLVM_IAS_VALUE="$LLVM_IAS"

# If explicit URLs are supplied for GCC/Clang, use them as a last-resort external archive.
# The resolver handles family-specific downloads; custom URLs are intentionally not guessed.

# ---- Build command ----
declare -a MAKE_BASE
MAKE_BASE=(make -j"$JOBS" O="$OUT" ARCH="$DETECTED_ARCH")
if [[ "$LLVM_VALUE" == 1 || "$LLVM_VALUE" == true ]]; then MAKE_BASE+=(LLVM=1); fi
if [[ "$LLVM_IAS_VALUE" == 1 || "$LLVM_IAS_VALUE" == true ]]; then MAKE_BASE+=(LLVM_IAS=1); fi
[[ -n "$CLANG_TRIPLE" && "$LLVM_VALUE" == 1 ]] && MAKE_BASE+=(CLANG_TRIPLE="$CLANG_TRIPLE")
[[ -n "$CROSS_DEFAULT" ]] && MAKE_BASE+=(CROSS_COMPILE="$CROSS_DEFAULT")
if [[ -n "$CROSS_COMPILE_ARM32" ]]; then MAKE_BASE+=(CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32"); fi
read -r -a EXTRA_ARGS <<< "$EXTRA_MAKE_ARGS"
MAKE_CMD=("${MAKE_BASE[@]}" "${EXTRA_ARGS[@]}")

MID="$(tg_msg "🚀 <b>Universal Kernel Build</b>
📱 Device: <code>$DEVICE</code>
🏗 ARCH: <code>$DETECTED_ARCH</code>
🐧 Kernel: <code>${DETECTED_KERNEL_VERSION}</code>
🌿 Branch: <code>$KERNEL_BRANCH</code>
⚙️ Defconfig: <code>$DETECTED_DEFCONFIG</code>
🧩 Fragment: <code>${DETECTED_FRAGMENT:-none}</code>
🛠 Toolchain: <code>$RESOLVED_TOOLCHAIN</code> <code>${RESOLVED_TOOLCHAIN_VERSION}</code>
🧵 Jobs: <code>$JOBS</code>
🔗 <a href=\"$RUN_URL\">CI log</a>")"

printf 'device=%s\narch=%s\nkernel_version=%s\nref_type=%s\nref=%s\ncommit=%s\ncommit_sha=%s\ndefconfig=%s\nfragment=%s\ntoolchain=%s\ntoolchain_version=%s\nllvm=%s\nllvm_ias=%s\nclang_triple=%s\ncross_compile=%s\nscheduler_profile=%s\n' \
  "$DEVICE" "$DETECTED_ARCH" "$DETECTED_KERNEL_VERSION" "$KERNEL_REF_TYPE" "$KERNEL_BRANCH" "$COMMIT" "$COMMIT_SHA" \
  "$DETECTED_DEFCONFIG" "${DETECTED_FRAGMENT:-}" "$RESOLVED_TOOLCHAIN" "$RESOLVED_TOOLCHAIN_VERSION" \
  "$LLVM_VALUE" "$LLVM_IAS_VALUE" "$CLANG_TRIPLE" "$CROSS_DEFAULT" "$SCHEDULER_PROFILE" > "$ARTIFACTS/build-info.txt"

echo "Kernel commit: $COMMIT" | tee -a "$BUILD_LOG"
echo "Make command: ${MAKE_CMD[*]}" | tee -a "$BUILD_LOG"

# ---- KernelSU ----
if [[ "$ENABLE_KSU" == "true" ]]; then
  if [[ -n "$KSU_REF" ]]; then
    curl -fLSs "https://raw.githubusercontent.com/tiann/KernelSU/${KSU_REF}/kernel/setup.sh" | bash - || fail "KernelSU setup"
  else
    curl -fLSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash - || fail "KernelSU setup"
  fi
fi

# ---- Configure ----
rm -rf "$OUT"
mkdir -p "$OUT"
"${MAKE_CMD[@]}" "$DETECTED_DEFCONFIG" > "$BUILD_LOG" 2>&1 || fail "defconfig"

if [[ -n "$SELECTED_FRAGMENT" ]]; then
  if [[ -x "$SRC_DIR/scripts/kconfig/merge_config.sh" ]]; then
    "$SRC_DIR/scripts/kconfig/merge_config.sh" -O "$OUT" "$OUT/.config" "$SELECTED_FRAGMENT" >> "$BUILD_LOG" 2>&1 || fail "config fragment"
  else
    cat "$SELECTED_FRAGMENT" >> "$OUT/.config"
    "${MAKE_CMD[@]}" olddefconfig >> "$BUILD_LOG" 2>&1 || fail "fragment olddefconfig"
  fi
elif [[ "$CONFIG_FRAGMENT" != none && "$CONFIG_FRAGMENT" != auto && -z "$SELECTED_FRAGMENT" ]]; then
  fail "config fragment not resolved"
fi

# ---- Scheduler evidence (never modifies source config) ----
SCHEDULER_DETECTED="none"
if grep -qE '^CONFIG_SCHED_HMP=y' "$OUT/.config" 2>/dev/null; then SCHEDULER_DETECTED="HMP"; fi
if grep -qE '^CONFIG_ENERGY_MODEL=y|^CONFIG_SCHED_TUNE=y' "$OUT/.config" 2>/dev/null; then
  [[ "$SCHEDULER_DETECTED" == none ]] && SCHEDULER_DETECTED="EAS-capable"
fi
if grep -qE '^CONFIG_SCHED_WALT=y' "$OUT/.config" 2>/dev/null; then
  [[ "$SCHEDULER_DETECTED" == none ]] && SCHEDULER_DETECTED="WALT"
fi
if [[ "$SCHEDULER_PROFILE" != auto && "$SCHEDULER_PROFILE" != none ]]; then
  echo "Requested scheduler profile: $SCHEDULER_PROFILE" >> "$BUILD_LOG"
fi
echo "Detected scheduler evidence: $SCHEDULER_DETECTED" >> "$ARTIFACTS/build-info.txt"

tg_edit "$MID" "🔨 <b>Compiling kernel…</b>
📱 $DEVICE | 🏗 $DETECTED_ARCH
⚙️ <code>$DETECTED_DEFCONFIG</code>
🛠 <code>$RESOLVED_TOOLCHAIN $RESOLVED_TOOLCHAIN_VERSION</code>
🧩 <code>${DETECTED_FRAGMENT:-no fragment}</code>
📊 Scheduler: <code>$SCHEDULER_DETECTED</code>"

if [[ -n "$KERNEL_TARGET" ]]; then
  "${MAKE_CMD[@]}" "$KERNEL_TARGET" >> "$BUILD_LOG" 2>&1 || fail "compile"
else
  "${MAKE_CMD[@]}" >> "$BUILD_LOG" 2>&1 || fail "compile"
fi

# ---- Collect artifacts ----
shopt -s nullglob
for item in \
  "$OUT/arch/$DETECTED_ARCH/boot/Image" \
  "$OUT/arch/$DETECTED_ARCH/boot/Image.gz" \
  "$OUT/arch/$DETECTED_ARCH/boot/Image.lz4" \
  "$OUT/arch/$DETECTED_ARCH/boot/Image.gz-dtb" \
  "$OUT/arch/$DETECTED_ARCH/boot/Image-dtb" \
  "$OUT/arch/$DETECTED_ARCH/boot/zImage" \
  "$OUT/arch/$DETECTED_ARCH/boot/dt.img" \
  "$OUT/arch/$DETECTED_ARCH/boot/dtb.img" \
  "$OUT/arch/$DETECTED_ARCH/boot/dtbo.img"; do
  [[ -f "$item" ]] && cp -f "$item" "$ARTIFACTS/"
done

if [[ -d "$OUT/arch/$DETECTED_ARCH/boot/dts" ]]; then
  tar -czf "$ARTIFACTS/dts.tar.gz" -C "$OUT/arch/$DETECTED_ARCH/boot" dts 2>/dev/null || true
fi
if find "$OUT" -type f -name '*.ko' -print -quit | grep -q .; then
  find "$OUT" -type f -name '*.ko' -print0 | tar --null -czf "$ARTIFACTS/modules.tar.gz" --files-from=- 2>/dev/null || true
fi
[[ -f "$OUT/.config" ]] && cp -f "$OUT/.config" "$ARTIFACTS/config"
[[ -f "$OUT/System.map" ]] && cp -f "$OUT/System.map" "$ARTIFACTS/System.map"
[[ -f "$OUT/vmlinux" ]] && cp -f "$OUT/vmlinux" "$ARTIFACTS/vmlinux"

IMAGE=""
for item in "$ARTIFACTS/Image" "$ARTIFACTS/Image.gz" "$ARTIFACTS/Image.lz4" "$ARTIFACTS/Image.gz-dtb" "$ARTIFACTS/Image-dtb" "$ARTIFACTS/zImage"; do
  if [[ -f "$item" ]]; then IMAGE="$item"; break; fi
done
[[ -n "$IMAGE" ]] || fail "kernel image not found"

# ---- Optional Custom AnyKernel3 ----
if [[ "$PACKAGE_ANYKERNEL" == "true" ]]; then
  [[ -x "$SCRIPT_DIR/build_anykernel.sh" ]] || fail "Custom AnyKernel packer missing"
  ARTIFACT_DIR="$ARTIFACTS" \
  OUTPUT_DIR="$ARTIFACTS" \
  WORK_DIR="$WORK" \
  DEVICE="$DEVICE" \
  KERNEL_VERSION="$DETECTED_KERNEL_VERSION" \
  ROM_FAMILY="$ROM_FAMILY" \
  ANYKERNEL_PROFILE="$ANYKERNEL_PROFILE" \
  ANYKERNEL3_REPO="$ANYKERNEL3_REPO" \
  ANYKERNEL3_REF="$ANYKERNEL3_REF" \
  KERNEL_IMAGE="$IMAGE" \
  "$SCRIPT_DIR/build_anykernel.sh" >> "$BUILD_LOG" 2>&1 || fail "AnyKernel package"
fi

ARCHIVE="$WORK/Kernel-${DEVICE}-$(date +%Y%m%d-%H%M).tar.gz"
tar -czf "$ARCHIVE" -C "$ARTIFACTS" . || fail "artifact archive"
DURATION=$(( $(date +%s) - START ))
SHA="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"
tg_edit "$MID" "✅ <b>Kernel build selesai</b>
📱 $DEVICE | 🏗 $DETECTED_ARCH
🐧 ${DETECTED_KERNEL_VERSION}
⚙️ <code>$DETECTED_DEFCONFIG</code>
🛠 <code>$RESOLVED_TOOLCHAIN $RESOLVED_TOOLCHAIN_VERSION</code>
📊 Scheduler: <code>$SCHEDULER_DETECTED</code>
⏱ $(fmt_dur "$DURATION")
📦 <code>$(basename "$ARCHIVE")</code>
🔐 SHA256: <code>${SHA:0:16}…</code>
🔗 <a href=\"$RUN_URL\">CI log</a>"
tg_file "$ARCHIVE" "📦 <b>Kernel artifacts — $DEVICE</b>"
echo "ARTIFACT_ARCHIVE=$ARCHIVE"
echo "ARTIFACT_SHA256=$SHA"
