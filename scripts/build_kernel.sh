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

# Normalize full Git refs so --branch/--tag receives the short ref.
case "$KERNEL_REF_TYPE" in
  branch)
    KERNEL_BRANCH="${KERNEL_BRANCH#refs/heads/}"
    ;;
  tag)
    KERNEL_BRANCH="${KERNEL_BRANCH#refs/tags/}"
    ;;
  auto)
    KERNEL_BRANCH="${KERNEL_BRANCH#refs/heads/}"
    KERNEL_BRANCH="${KERNEL_BRANCH#refs/tags/}"
    ;;
esac

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

# KernelSU:
#   false = never install missing KernelSU
#   true  = install when required/missing
#   auto  = install only when the source/defconfig indicates KSU is required
ENABLE_KSU="${ENABLE_KSU:-auto}"
KSU_PROVIDER="${KSU_PROVIDER:-auto}"
KSU_PROVIDER_ORIGINAL="$KSU_PROVIDER"
KSU_REPO="${KSU_REPO:-}"
KSU_REF="${KSU_REF:-}"
KSU_LAYOUT="${KSU_LAYOUT:-auto}"
KSU_HOOK_MODE="${KSU_HOOK_MODE:-auto}"

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

FAIL_HANDLED=false

fail() {
  local reason="$1"

  if [[ "$FAIL_HANDLED" == true ]]; then
    exit 1
  fi
  FAIL_HANDLED=true

  local duration=$(( $(date +%s) - START ))

  tg_edit "${MID:-}" "❌ <b>Kernel build gagal</b>
📱 $DEVICE | 🏗 ${DETECTED_ARCH:-$ARCH}
🧩 Tahap: <code>$reason</code>
⏱ $(fmt_dur "$duration")
🔗 <a href=\"$RUN_URL\">CI log</a>"

  if [[ -f "$BUILD_LOG" ]]; then
    tail -n 300 "$BUILD_LOG" > "$WORK/error_tail.log" || true
    tg_file "$WORK/error_tail.log" "📄 Last 300 build log lines — $DEVICE"
  fi

  exit 1
}

trap 'fail "unexpected error at line $LINENO"' ERR

if [[ "$JOBS" == "0" || -z "$JOBS" ]]; then
  JOBS="$(nproc 2>/dev/null || echo 2)"
fi

# ------------------------------------------------------------
# Basic input validation
# ------------------------------------------------------------

if [[ -z "$KERNEL_BRANCH" ]]; then
  fail "KERNEL_BRANCH is empty"
fi

if [[ -z "$DEVICE" || "$DEVICE" == "generic" ]]; then
  fail "DEVICE is missing or still 'generic'"
fi

case "$ENABLE_KSU" in
  true|false|auto)
    ;;
  *)
    fail "invalid ENABLE_KSU=$ENABLE_KSU"
    ;;
esac

# ------------------------------------------------------------
# Source checkout
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Auto-detect architecture / defconfig / fragment
# ------------------------------------------------------------

DETECT_ENV="$WORK/detection.env"

ARCH="$ARCH" DEVICE="$DEVICE" DEFCONFIG="$DEFCONFIG" CONFIG_FRAGMENT="$CONFIG_FRAGMENT" \
  "$SCRIPT_DIR/detect_defconfig.sh" \
  --repo "$SRC_DIR" \
  --arch "$ARCH" \
  --device "$DEVICE" \
  --defconfig "$DEFCONFIG" \
  --fragment "$CONFIG_FRAGMENT" \
  > "$DETECT_ENV" || fail "auto-detect"

source "$DETECT_ENV"

# Detection script returns paths relative to arch/$ARCH/configs.
SELECTED_FRAGMENT=""

if [[ -n "${DETECTED_FRAGMENT:-}" ]]; then
  SELECTED_FRAGMENT="$SRC_DIR/arch/$DETECTED_ARCH/configs/$DETECTED_FRAGMENT"
  [[ -f "$SELECTED_FRAGMENT" ]] || fail "detected fragment missing"
fi

# ------------------------------------------------------------
# Optional user build environment
# ------------------------------------------------------------

if [[ -n "$BUILD_ENV" ]]; then
  eval "$BUILD_ENV"
fi

# ------------------------------------------------------------
# KernelSU provider detection / integration
# ------------------------------------------------------------

KSU_REQUIRED=false

# Source-level KSU integration marker.
if grep -qE 'source "[^"]*kernelsu[^"]*/Kconfig"|obj-\$\(CONFIG_KSU\).*kernelsu' \
    "$SRC_DIR/drivers/Kconfig" "$SRC_DIR/drivers/Makefile" 2>/dev/null; then
  KSU_REQUIRED=true
fi

# Defconfig/fragment-level KSU requirement.
if grep -qE '^CONFIG_KSU(=y|=m)' \
    "$SRC_DIR/arch/$DETECTED_ARCH/configs/$DETECTED_DEFCONFIG" 2>/dev/null; then
  KSU_REQUIRED=true
fi

if [[ -n "$SELECTED_FRAGMENT" ]] && grep -qE '^CONFIG_KSU(=y|=m)' \
    "$SELECTED_FRAGMENT" 2>/dev/null; then
  KSU_REQUIRED=true
fi

KSU_SUSFS_REQUIRED=false

if grep -qE '^CONFIG_KSU_SUSFS(=y|=m)' \
    "$SRC_DIR/arch/$DETECTED_ARCH/configs/$DETECTED_DEFCONFIG" 2>/dev/null; then
  KSU_SUSFS_REQUIRED=true
fi

if [[ -n "$SELECTED_FRAGMENT" ]] && grep -qE '^CONFIG_KSU_SUSFS(=y|=m)' \
    "$SELECTED_FRAGMENT" 2>/dev/null; then
  KSU_SUSFS_REQUIRED=true
fi

# Detect the layout already expected by the kernel source.
KSU_NESTED_EXPECTED=false

if grep -q 'source "drivers/kernelsu/kernel/Kconfig"' \
    "$SRC_DIR/drivers/Kconfig" 2>/dev/null ||
   grep -qE 'obj-\$\(CONFIG_KSU\).*kernelsu/kernel/' \
    "$SRC_DIR/drivers/Makefile" 2>/dev/null; then
  KSU_NESTED_EXPECTED=true
fi

case "$KSU_LAYOUT" in
  nested)
    KSU_NESTED_EXPECTED=true
    ;;
  symlink)
    KSU_NESTED_EXPECTED=false
    ;;
  auto)
    ;;
  *)
    fail "invalid KSU_LAYOUT=$KSU_LAYOUT"
    ;;
esac

KSU_KCONFIG=""
KSU_PROVIDER_VERSION="none"
KSU_PROVIDER_COMMIT="none"

if [[ "$KSU_NESTED_EXPECTED" == true && -f "$SRC_DIR/drivers/kernelsu/kernel/Kconfig" ]]; then
  KSU_KCONFIG="$SRC_DIR/drivers/kernelsu/kernel/Kconfig"
elif [[ -f "$SRC_DIR/drivers/kernelsu/Kconfig" ]]; then
  KSU_KCONFIG="$SRC_DIR/drivers/kernelsu/Kconfig"
fi

resolve_ksu_provider() {
  case "$KSU_PROVIDER" in
    official|kernelsu)
      KSU_PROVIDER="official"
      KSU_REPO="https://github.com/tiann/KernelSU"
      # Official KernelSU documents v0.9.5 as the final non-GKI release.
      KSU_REF="${KSU_REF:-v0.9.5}"
      ;;
    kernelsu-next|ksu-next|next)
      KSU_PROVIDER="kernelsu-next"
      KSU_REPO="https://github.com/KernelSU-Next/KernelSU-Next"
      # The upstream setup entrypoint is on the "next" branch; legacy is
      # the explicit non-GKI/legacy mode used by current examples.
      KSU_REF="${KSU_REF:-legacy}"
      ;;
    resukisu|re-sukisu)
      KSU_PROVIDER="resukisu"
      KSU_REPO="https://github.com/ReSukiSU/ReSukiSU"
      KSU_REF="${KSU_REF:-main}"
      ;;
    custom)
      [[ -n "$KSU_REPO" ]] || fail "KSU_PROVIDER=custom requires KSU_REPO"
      ;;
    auto)
      # When the kernel explicitly asks for SUSFS, select ReSukiSU by default
      # because its current documentation advertises SUSFS + non-GKI support.
      # Otherwise use KernelSU-Next for the generic KSU provider path.
      if [[ "$KSU_SUSFS_REQUIRED" == true ]]; then
        KSU_PROVIDER="resukisu"
        KSU_REPO="${KSU_REPO:-https://github.com/ReSukiSU/ReSukiSU}"
        KSU_REF="${KSU_REF:-main}"
      else
        KSU_PROVIDER="kernelsu-next"
        KSU_REPO="${KSU_REPO:-https://github.com/KernelSU-Next/KernelSU-Next}"
        KSU_REF="${KSU_REF:-legacy}"
      fi
      ;;
    *)
      fail "invalid KSU_PROVIDER=$KSU_PROVIDER"
      ;;
  esac
}

if [[ "$KSU_REQUIRED" == true ]]; then
  resolve_ksu_provider

  echo "[ksu] required=true" >&2
  echo "[ksu] provider=$KSU_PROVIDER" >&2
  echo "[ksu] repo=$KSU_REPO" >&2
  echo "[ksu] ref=$KSU_REF" >&2
  echo "[ksu] hook_mode=$KSU_HOOK_MODE" >&2
  echo "[ksu] layout=$([[ "$KSU_NESTED_EXPECTED" == true ]] && echo nested || echo symlink)" >&2

  # We need a provider checkout when KSU is missing, or when the user
  # explicitly selected a provider. Existing in-tree KSU is otherwise kept.
  if [[ -z "$KSU_KCONFIG" || "$KSU_PROVIDER_ORIGINAL" != auto ]]; then
    if [[ "$ENABLE_KSU" == false ]]; then
      echo "ERROR: kernel source/defconfig requires KernelSU, but ENABLE_KSU=false." >&2
      fail "KernelSU disabled"
    fi

    KSU_DIR="$WORK/KernelSU"
    rm -rf "$KSU_DIR"

    echo "[ksu] cloning provider..." >&2
    git clone --depth=1 "$KSU_REPO" "$KSU_DIR" || fail "KernelSU provider clone"

    if [[ -n "$KSU_REF" ]]; then
      git -C "$KSU_DIR" fetch --depth=1 origin "$KSU_REF" || fail "KernelSU provider ref fetch"
      git -C "$KSU_DIR" checkout --detach FETCH_HEAD || fail "KernelSU provider ref checkout"
    fi

    KSU_SOURCE_KERNEL="$KSU_DIR/kernel"
    [[ -d "$KSU_SOURCE_KERNEL" ]] || fail "KernelSU provider has no kernel/ directory"

    KSU_PROVIDER_COMMIT="$(git -C "$KSU_DIR" rev-parse HEAD)"
    KSU_PROVIDER_VERSION="$(git -C "$KSU_DIR" describe --tags --always --dirty 2>/dev/null || \
      git -C "$KSU_DIR" rev-parse --short HEAD)"

    # Both KernelSU-Next and ReSukiSU use kernel/setup.sh to wire their
    # driver into a GKI/non-GKI kernel. For this universal builder we
    # reproduce the same wiring while also supporting legacy nested trees
    # such as drivers/kernelsu/kernel/.
    if [[ "$KSU_NESTED_EXPECTED" == true ]]; then
      echo "[ksu] installing provider repository at drivers/kernelsu -> $KSU_DIR" >&2
      rm -rf "$SRC_DIR/drivers/kernelsu"
      ln -s "$KSU_DIR" "$SRC_DIR/drivers/kernelsu"
    else
      echo "[ksu] installing symlink layout drivers/kernelsu -> provider/kernel" >&2
      rm -rf "$SRC_DIR/drivers/kernelsu"
      ln -s "$KSU_SOURCE_KERNEL" "$SRC_DIR/drivers/kernelsu"
    fi

    if [[ "$KSU_NESTED_EXPECTED" == true ]]; then
      KSU_KCONFIG="$SRC_DIR/drivers/kernelsu/kernel/Kconfig"
    else
      KSU_KCONFIG="$SRC_DIR/drivers/kernelsu/Kconfig"
    fi
  else
    KSU_PROVIDER_COMMIT="pre-integrated"
    KSU_PROVIDER_VERSION="source-tree"
  fi

  [[ -f "$KSU_KCONFIG" ]] || fail "KernelSU Kconfig missing after integration"

  # ReSukiSU/KernelSU-Next provide different hook modes across kernel
  # generations. We do not silently apply core-kernel patches here.
  # "auto" preserves the provider's normal setup behavior.
  case "$KSU_HOOK_MODE" in
    auto|kprobe|manual|susfs)
      ;;
    *)
      fail "invalid KSU_HOOK_MODE=$KSU_HOOK_MODE"
      ;;
  esac

  if [[ "$KSU_SUSFS_REQUIRED" == true ]]; then
    if ! grep -RqsE 'config[[:space:]]+KSU_SUSFS([[:space:]]|$)' \
        "$SRC_DIR/drivers/kernelsu" 2>/dev/null; then
      echo "ERROR: CONFIG_KSU_SUSFS is required, but provider '$KSU_PROVIDER' does not define it." >&2
      echo "Use a SUSFS-capable provider/ref or a kernel tree with matching SUSFS patches." >&2
      fail "KernelSU/SUSFS provider mismatch"
    fi
  fi
else
  KSU_PROVIDER="none"
  KSU_REPO=""
  KSU_REF=""
  KSU_PROVIDER_COMMIT="none"
  KSU_PROVIDER_VERSION="none"
fi

KSU_LAYOUT_RESOLVED="$([[ "$KSU_NESTED_EXPECTED" == true ]] && echo nested || echo symlink)"

# ------------------------------------------------------------
# Toolchain resolution
# ------------------------------------------------------------

TOOLCHAIN_ENV="$WORK/toolchain.env"

TOOLCHAIN="$TOOLCHAIN" \
TOOLCHAIN_VERSION="$TOOLCHAIN_VERSION" \
ARCH="$DETECTED_ARCH" \
CLANG_URL="$CLANG_URL" \
GCC_URL="$GCC_URL" \
"$SCRIPT_DIR/toolchain_resolver.sh" \
  "$SRC_DIR" "$WORK" \
  > "$TOOLCHAIN_ENV" || fail "toolchain resolution"

source "$TOOLCHAIN_ENV"

# ------------------------------------------------------------
# Sanitize inherited compiler overrides.
#
# Kernel Makefile selects the actual compiler when LLVM=1.
# Environment values such as CC=autogcc or CROSS_COMPILE=auto
# must not override that logic.
# ------------------------------------------------------------

unset CC CXX CPP LD AS AR NM OBJCOPY OBJDUMP READELF OBJSIZE STRIP
unset HOSTCC HOSTCXX
unset MAKEFLAGS MAKEOVERRIDES

# "auto" is a CI selector, not a valid compiler prefix.
if [[ "${CROSS_COMPILE:-}" == "auto" ]]; then
  unset CROSS_COMPILE
fi

# Empty ARM32 prefix is valid; keep it defined for set -u safety.
if [[ "${CROSS_COMPILE_ARM32:-}" == "auto" ]]; then
  CROSS_COMPILE_ARM32=""
fi

if [[ "${CLANG_TRIPLE:-}" == "auto" ]]; then
  unset CLANG_TRIPLE
fi

echo "[toolchain] sanitized environment" >&2
echo "[toolchain] clang=$(command -v clang || true)" >&2
echo "[toolchain] ld.lld=$(command -v ld.lld || true)" >&2
echo "[toolchain] aarch64-gcc=$(command -v aarch64-linux-gnu-gcc || true)" >&2
echo "[toolchain] arm32-gcc=$(command -v arm-linux-gnueabi-gcc || true)" >&2

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

# ------------------------------------------------------------
# Build command
# ------------------------------------------------------------

declare -a MAKE_BASE

MAKE_BASE=(
  make
  -j"$JOBS"
  O="$OUT"
  ARCH="$DETECTED_ARCH"
)

if [[ "$LLVM_VALUE" == 1 || "$LLVM_VALUE" == true ]]; then
  MAKE_BASE+=(LLVM=1)
fi

if [[ "$LLVM_IAS_VALUE" == 1 || "$LLVM_IAS_VALUE" == true ]]; then
  MAKE_BASE+=(LLVM_IAS=1)
fi

# CLANG_TRIPLE is for the LLVM driver. Keep it separate from
# CROSS_COMPILE and CROSS_COMPILE_ARM32.
if [[ -n "$CLANG_TRIPLE" && "$LLVM_VALUE" == 1 ]]; then
  MAKE_BASE+=(CLANG_TRIPLE="$CLANG_TRIPLE")
fi

if [[ -n "$CROSS_DEFAULT" ]]; then
  MAKE_BASE+=(CROSS_COMPILE="$CROSS_DEFAULT")
fi

if [[ -n "$CROSS_COMPILE_ARM32" && "$CROSS_COMPILE_ARM32" != auto ]]; then
  MAKE_BASE+=(CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32")
fi

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
🔀 CLANG_TRIPLE: <code>${CLANG_TRIPLE:-none}</code>
🔧 CROSS_COMPILE: <code>${CROSS_DEFAULT:-none}</code>
🔧 CROSS_COMPILE_ARM32: <code>${CROSS_COMPILE_ARM32:-none}</code>
🔐 KernelSU: <code>${KSU_PROVIDER:-none}</code>
📦 KSU ref: <code>${KSU_REF:-none}</code>
🔗 <a href=\"$RUN_URL\">CI log</a>")"

printf 'device=%s\n' "$DEVICE" > "$ARTIFACTS/build-info.txt"
printf 'arch=%s\n' "$DETECTED_ARCH" >> "$ARTIFACTS/build-info.txt"
printf 'kernel_version=%s\n' "$DETECTED_KERNEL_VERSION" >> "$ARTIFACTS/build-info.txt"
printf 'ref_type=%s\n' "$KERNEL_REF_TYPE" >> "$ARTIFACTS/build-info.txt"
printf 'ref=%s\n' "$KERNEL_BRANCH" >> "$ARTIFACTS/build-info.txt"
printf 'commit=%s\n' "$COMMIT" >> "$ARTIFACTS/build-info.txt"
printf 'commit_sha=%s\n' "$COMMIT_SHA" >> "$ARTIFACTS/build-info.txt"
printf 'defconfig=%s\n' "$DETECTED_DEFCONFIG" >> "$ARTIFACTS/build-info.txt"
printf 'fragment=%s\n' "${DETECTED_FRAGMENT:-}" >> "$ARTIFACTS/build-info.txt"
printf 'toolchain=%s\n' "$RESOLVED_TOOLCHAIN" >> "$ARTIFACTS/build-info.txt"
printf 'toolchain_version=%s\n' "$RESOLVED_TOOLCHAIN_VERSION" >> "$ARTIFACTS/build-info.txt"
printf 'llvm=%s\n' "$LLVM_VALUE" >> "$ARTIFACTS/build-info.txt"
printf 'llvm_ias=%s\n' "$LLVM_IAS_VALUE" >> "$ARTIFACTS/build-info.txt"
printf 'clang_triple=%s\n' "$CLANG_TRIPLE" >> "$ARTIFACTS/build-info.txt"
printf 'cross_compile=%s\n' "$CROSS_DEFAULT" >> "$ARTIFACTS/build-info.txt"
printf 'cross_compile_arm32=%s\n' "$CROSS_COMPILE_ARM32" >> "$ARTIFACTS/build-info.txt"
printf 'scheduler_profile=%s\n' "$SCHEDULER_PROFILE" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_required=%s\n' "$KSU_REQUIRED" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_susfs_required=%s\n' "$KSU_SUSFS_REQUIRED" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_repo=%s\n' "$KSU_REPO" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_ref=%s\n' "${KSU_REF:-}" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_layout=%s\n' "$KSU_LAYOUT" >> "$ARTIFACTS/build-info.txt"

echo "Kernel commit: $COMMIT" | tee -a "$BUILD_LOG"
echo "Make command: ${MAKE_CMD[*]}" | tee -a "$BUILD_LOG"

printf 'ksu_required=%s\n' "$KSU_REQUIRED" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_susfs_required=%s\n' "$KSU_SUSFS_REQUIRED" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_provider=%s\n' "$KSU_PROVIDER" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_repo=%s\n' "${KSU_REPO:-}" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_ref=%s\n' "${KSU_REF:-}" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_version=%s\n' "${KSU_PROVIDER_VERSION:-none}" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_commit=%s\n' "${KSU_PROVIDER_COMMIT:-none}" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_layout=%s\n' "$KSU_LAYOUT_RESOLVED" >> "$ARTIFACTS/build-info.txt"
printf 'ksu_hook_mode=%s\n' "$KSU_HOOK_MODE" >> "$ARTIFACTS/build-info.txt"

# ------------------------------------------------------------
# Configure
# ------------------------------------------------------------

rm -rf "$OUT"
mkdir -p "$OUT"

"${MAKE_CMD[@]}" "$DETECTED_DEFCONFIG" > "$BUILD_LOG" 2>&1 || fail "defconfig"

if [[ -n "$SELECTED_FRAGMENT" ]]; then
  if [[ -x "$SRC_DIR/scripts/kconfig/merge_config.sh" ]]; then
    "$SRC_DIR/scripts/kconfig/merge_config.sh" \
      -O "$OUT" \
      "$OUT/.config" \
      "$SELECTED_FRAGMENT" \
      >> "$BUILD_LOG" 2>&1 || fail "config fragment"
  else
    cat "$SELECTED_FRAGMENT" >> "$OUT/.config"
    "${MAKE_CMD[@]}" olddefconfig >> "$BUILD_LOG" 2>&1 || fail "fragment olddefconfig"
  fi
elif [[ "$CONFIG_FRAGMENT" != none && "$CONFIG_FRAGMENT" != auto && -z "$SELECTED_FRAGMENT" ]]; then
  fail "config fragment not resolved"
fi

# ------------------------------------------------------------
# Verify required KernelSU/SUSFS symbols AFTER config merge.
# ------------------------------------------------------------

if [[ "$KSU_REQUIRED" == true ]]; then
  if ! grep -qE '^CONFIG_KSU=(y|m)' "$OUT/.config" 2>/dev/null; then
    echo "ERROR: kernel source indicates KernelSU is required but final .config has CONFIG_KSU disabled." >&2
    fail "KernelSU config disabled"
  fi
fi

if [[ "$KSU_SUSFS_REQUIRED" == true ]]; then
  if ! grep -qE '^CONFIG_KSU_SUSFS=(y|m)' "$OUT/.config" 2>/dev/null; then
    echo "ERROR: kernel config requires SUSFS but final .config has CONFIG_KSU_SUSFS disabled." >&2
    fail "SUSFS config disabled"
  fi
fi

# ------------------------------------------------------------
# Scheduler evidence (never modifies source config)
# ------------------------------------------------------------

SCHEDULER_DETECTED="none"

if grep -qE '^CONFIG_SCHED_HMP=y' "$OUT/.config" 2>/dev/null; then
  SCHEDULER_DETECTED="HMP"
fi

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
📊 Scheduler: <code>$SCHEDULER_DETECTED</code>
🔐 KSU: <code>$KSU_REQUIRED</code>
🧵 Jobs: <code>$JOBS</code>"

# ------------------------------------------------------------
# Compile
# ------------------------------------------------------------

if [[ -n "$KERNEL_TARGET" ]]; then
  "${MAKE_CMD[@]}" "$KERNEL_TARGET" >> "$BUILD_LOG" 2>&1 || fail "compile"
else
  "${MAKE_CMD[@]}" >> "$BUILD_LOG" 2>&1 || fail "compile"
fi

# ------------------------------------------------------------
# Collect artifacts
# ------------------------------------------------------------

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
  "$OUT/arch/$DETECTED_ARCH/boot/dtbo.img"
do
  [[ -f "$item" ]] && cp -f "$item" "$ARTIFACTS/"
done

if [[ -d "$OUT/arch/$DETECTED_ARCH/boot/dts" ]]; then
  tar -czf "$ARTIFACTS/dts.tar.gz" \
    -C "$OUT/arch/$DETECTED_ARCH/boot" \
    dts 2>/dev/null || true
fi

if find "$OUT" -type f -name '*.ko' -print -quit | grep -q .; then
  find "$OUT" -type f -name '*.ko' -print0 |
    tar --null -czf "$ARTIFACTS/modules.tar.gz" \
      --files-from=- 2>/dev/null || true
fi

[[ -f "$OUT/.config" ]] && cp -f "$OUT/.config" "$ARTIFACTS/config"
[[ -f "$OUT/System.map" ]] && cp -f "$OUT/System.map" "$ARTIFACTS/System.map"
[[ -f "$OUT/vmlinux" ]] && cp -f "$OUT/vmlinux" "$ARTIFACTS/vmlinux"

IMAGE=""

for item in \
  "$ARTIFACTS/Image" \
  "$ARTIFACTS/Image.gz" \
  "$ARTIFACTS/Image.lz4" \
  "$ARTIFACTS/Image.gz-dtb" \
  "$ARTIFACTS/Image-dtb" \
  "$ARTIFACTS/zImage"
do
  if [[ -f "$item" ]]; then
    IMAGE="$item"
    break
  fi
done

[[ -n "$IMAGE" ]] || fail "kernel image not found"

# ------------------------------------------------------------
# Optional Custom AnyKernel3
# ------------------------------------------------------------

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
  "$SCRIPT_DIR/build_anykernel.sh" \
  >> "$BUILD_LOG" 2>&1 || fail "AnyKernel package"
fi

# ------------------------------------------------------------
# Final archive
# ------------------------------------------------------------

ARCHIVE="$WORK/Kernel-${DEVICE}-$(date +%Y%m%d-%H%M).tar.gz"

tar -czf "$ARCHIVE" \
  -C "$ARTIFACTS" . || fail "artifact archive"

DURATION=$(( $(date +%s) - START ))
SHA="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"

tg_edit "$MID" "✅ <b>Kernel build selesai</b>
📱 $DEVICE | 🏗 $DETECTED_ARCH
🐧 ${DETECTED_KERNEL_VERSION}
⚙️ <code>$DETECTED_DEFCONFIG</code>
🛠 <code>$RESOLVED_TOOLCHAIN $RESOLVED_TOOLCHAIN_VERSION</code>
📊 Scheduler: <code>$SCHEDULER_DETECTED</code>
🔐 KSU: <code>$KSU_REQUIRED</code>
⏱ $(fmt_dur "$DURATION")
📦 <code>$(basename "$ARCHIVE")</code>
🔐 SHA256: <code>${SHA:0:16}…</code>
🔗 <a href=\"$RUN_URL\">CI log</a>"

tg_file "$ARCHIVE" "📦 <b>Kernel artifacts — $DEVICE</b>"

echo "ARTIFACT_ARCHIVE=$ARCHIVE"
echo "ARTIFACT_SHA256=$SHA"
