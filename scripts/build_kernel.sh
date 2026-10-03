#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/tg.sh"

: "${KERNEL_REPO:?KERNEL_REPO is required}"
: "${KERNEL_BRANCH:?KERNEL_BRANCH is required}"
: "${DEFCONFIG:?DEFCONFIG is required}"

DEVICE="${DEVICE:-generic}"
ARCH="${ARCH:-arm64}"
JOBS="${JOBS:-0}"
TOOLCHAIN="${TOOLCHAIN:-auto}"
LLVM="${LLVM:-1}"
LLVM_IAS="${LLVM_IAS:-auto}"
CROSS_COMPILE="${CROSS_COMPILE:-}"
CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32:-}"
CLANG_URL="${CLANG_URL:-}"
GCC_URL="${GCC_URL:-}"
KERNEL_OUT="${KERNEL_OUT:-}"
ENABLE_KSU="${ENABLE_KSU:-false}"
KSU_REF="${KSU_REF:-}"
PACKAGE_ANYKERNEL="${PACKAGE_ANYKERNEL:-false}"
ANYKERNEL_REPO="${ANYKERNEL_REPO:-https://github.com/osm0sis/AnyKernel3}"
ANYKERNEL_BRANCH="${ANYKERNEL_BRANCH:-master}"
EXTRA_MAKE_ARGS="${EXTRA_MAKE_ARGS:-}"
SCHEDULER_PROFILE="${SCHEDULER_PROFILE:-auto}"
BUILD_ENV="${BUILD_ENV:-}"
RUN_URL="${RUN_URL:-}"

if [[ "$JOBS" == "0" || -z "$JOBS" ]]; then
  JOBS="$(nproc 2>/dev/null || echo 2)"
fi

START="$(date +%s)"
WORK="${WORK_DIR:-$PWD/work}"
SOURCE_DIR="$WORK/kernel"
OUT="${KERNEL_OUT:-$WORK/kernel-out}"
ARTIFACTS="$WORK/artifacts"
BUILD_LOG="$WORK/build.log"
TOOLCHAIN_DIR="$WORK/toolchain"
mkdir -p "$WORK" "$ARTIFACTS"

MID=""
fail() {
  local reason="${1:-unknown}"
  local duration=$(( $(date +%s) - START ))
  tg_edit "$MID" "❌ <b>Kernel build gagal</b>
📱 <code>$DEVICE</code> | 🏗 <code>$ARCH</code>
🧬 Kernel: <code>${KERNEL_VERSION:-unknown}</code>
🧩 <code>$reason</code>
⏱ $(fmt_dur "$duration")
🔗 <a href=\"$RUN_URL\">CI log</a>"
  if [[ -f "$BUILD_LOG" ]]; then
    tail -n 300 "$BUILD_LOG" > "$WORK/error_tail.log" || true
    tg_file "$WORK/error_tail.log" "📄 Last 300 build log lines — $DEVICE"
  fi
  exit 1
}
trap 'fail "unexpected error at line $LINENO"' ERR

# ---- Source ----
rm -rf "$SOURCE_DIR"
git clone --depth=1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$SOURCE_DIR" || fail "clone kernel"
cd "$SOURCE_DIR"

COMMIT="$(git rev-parse HEAD)"
SHORT_COMMIT="$(git rev-parse --short HEAD)"
COMMIT_TITLE="$(git log -1 --pretty='%s')"
KERNEL_MAJOR="$(awk -F'= *' '/^VERSION[[:space:]]*=/ {print $2; exit}' Makefile)"
KERNEL_MINOR="$(awk -F'= *' '/^PATCHLEVEL[[:space:]]*=/ {print $2; exit}' Makefile)"
KERNEL_SUBLEVEL="$(awk -F'= *' '/^SUBLEVEL[[:space:]]*=/ {print $2; exit}' Makefile)"
KERNEL_MAJOR="${KERNEL_MAJOR:-0}"
KERNEL_MINOR="${KERNEL_MINOR:-0}"
KERNEL_SUBLEVEL="${KERNEL_SUBLEVEL:-0}"
KERNEL_VERSION="${KERNEL_MAJOR}.${KERNEL_MINOR}.${KERNEL_SUBLEVEL}"

# ---- Architecture auto-detect ----
if [[ "$ARCH" == "auto" || -z "$ARCH" ]]; then
  if [[ -f "arch/arm64/configs/$DEFCONFIG" ]]; then
    ARCH="arm64"
  elif [[ -f "arch/arm/configs/$DEFCONFIG" ]]; then
    ARCH="arm"
  else
    case "${DEVICE,,}" in
      garnet|lavender|moonstone|parrot) ARCH="arm64" ;;
      *) fail "cannot detect ARCH; set ARCH explicitly" ;;
    esac
  fi
fi

case "$ARCH" in
  arm64)
    DEFAULT_CROSS_COMPILE="aarch64-linux-gnu-"
    DEFAULT_CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
    ;;
  arm)
    DEFAULT_CROSS_COMPILE="arm-linux-gnueabi-"
    DEFAULT_CROSS_COMPILE_ARM32=""
    ;;
  *)
    DEFAULT_CROSS_COMPILE=""
    DEFAULT_CROSS_COMPILE_ARM32=""
    ;;
esac

# 4.4/4.19 Android trees default to GCC; modern GKI 5.x trees default to Clang.
if [[ "$TOOLCHAIN" == "auto" ]]; then
  if (( KERNEL_MAJOR < 5 )); then TOOLCHAIN="gcc"; else TOOLCHAIN="clang"; fi
fi
[[ "$TOOLCHAIN" == "gcc" || "$TOOLCHAIN" == "clang" ]] || fail "TOOLCHAIN must be auto, gcc, or clang"

if [[ "$TOOLCHAIN" == "gcc" ]]; then
  [[ -n "$CROSS_COMPILE" ]] || CROSS_COMPILE="$DEFAULT_CROSS_COMPILE"
  if [[ -z "$CROSS_COMPILE_ARM32" && "$ARCH" == "arm64" ]]; then
    CROSS_COMPILE_ARM32="$DEFAULT_CROSS_COMPILE_ARM32"
  fi
elif [[ "$LLVM_IAS" == "auto" ]]; then
  if (( KERNEL_MAJOR < 5 )); then LLVM_IAS="0"; else LLVM_IAS="1"; fi
fi

# ---- Optional toolchain archives ----
if [[ -n "$CLANG_URL" ]]; then
  mkdir -p "$TOOLCHAIN_DIR/clang"
  curl -fL --retry 3 --retry-delay 2 "$CLANG_URL" -o "$WORK/clang.tar" || fail "download clang"
  tar -xf "$WORK/clang.tar" -C "$TOOLCHAIN_DIR/clang" || fail "extract clang"
  CLANG_BIN="$(find "$TOOLCHAIN_DIR/clang" -type f -path '*/bin/clang' -print -quit || true)"
  [[ -n "$CLANG_BIN" ]] || fail "clang binary not found"
  export PATH="$(dirname "$CLANG_BIN"):$PATH"
fi

if [[ -n "$GCC_URL" ]]; then
  mkdir -p "$TOOLCHAIN_DIR/gcc"
  curl -fL --retry 3 --retry-delay 2 "$GCC_URL" -o "$WORK/gcc.tar" || fail "download gcc"
  tar -xf "$WORK/gcc.tar" -C "$TOOLCHAIN_DIR/gcc" || fail "extract gcc"
  export PATH="$TOOLCHAIN_DIR/gcc/bin:$PATH"
fi

# ---- Optional caller environment ----
if [[ -n "$BUILD_ENV" ]]; then
  eval "$BUILD_ENV"
fi

# ---- Compiler check ----
if [[ "$TOOLCHAIN" == "clang" ]]; then
  command -v clang >/dev/null 2>&1 || fail "clang not found"
  COMPILER_VERSION="$(clang --version | head -n1)"
else
  command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 || fail "cross compiler not found: ${CROSS_COMPILE}gcc"
  COMPILER_VERSION="$("${CROSS_COMPILE}gcc" --version | head -n1)"
fi

# ---- Make command ----
declare -a MAKE_CMD
MAKE_CMD=(make -j"$JOBS" O="$OUT" ARCH="$ARCH")
if [[ "$TOOLCHAIN" == "clang" ]]; then
  [[ "$LLVM" == "1" || "$LLVM" == "true" ]] && MAKE_CMD+=(LLVM=1)
  [[ "$LLVM_IAS" == "1" || "$LLVM_IAS" == "true" ]] && MAKE_CMD+=(LLVM_IAS=1)
else
  [[ -n "$CROSS_COMPILE" ]] && MAKE_CMD+=(CROSS_COMPILE="$CROSS_COMPILE")
  [[ -n "$CROSS_COMPILE_ARM32" ]] && MAKE_CMD+=(CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32")
fi
read -r -a EXTRA_ARGS <<< "$EXTRA_MAKE_ARGS"
MAKE_CMD+=("${EXTRA_ARGS[@]}")

MID="$(tg_msg "🚀 <b>Universal Kernel Build</b>
📱 <code>$DEVICE</code>
🏗 <code>$ARCH</code>
🧬 <code>$KERNEL_VERSION</code>
⚙️ <code>$DEFCONFIG</code>
🛠 <code>$TOOLCHAIN</code>
🧭 <code>$SCHEDULER_PROFILE</code>
🔗 <a href=\"$RUN_URL\">CI log</a>")"

{
  echo "device=$DEVICE"
  echo "arch=$ARCH"
  echo "kernel_version=$KERNEL_VERSION"
  echo "kernel_repo=$KERNEL_REPO"
  echo "kernel_branch=$KERNEL_BRANCH"
  echo "commit=$COMMIT"
  echo "defconfig=$DEFCONFIG"
  echo "toolchain=$TOOLCHAIN"
  echo "compiler=$COMPILER_VERSION"
  echo "scheduler_profile=$SCHEDULER_PROFILE"
  echo "make=${MAKE_CMD[*]}"
} | tee "$WORK/source-info.txt" | tee -a "$BUILD_LOG"

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
"${MAKE_CMD[@]}" "$DEFCONFIG" > "$BUILD_LOG" 2>&1 || fail "defconfig"

if [[ "$ENABLE_KSU" == "true" ]]; then
  [[ -x ./scripts/config ]] || fail "scripts/config unavailable for KernelSU"
  ./scripts/config --file "$OUT/.config" -e KSU || fail "enable KSU"
  "${MAKE_CMD[@]}" olddefconfig >> "$BUILD_LOG" 2>&1 || fail "olddefconfig"
fi

# Report common EAS/HMP symbols without changing the source's scheduler design.
SCHED_FEATURES=()
grep -q '^CONFIG_ENERGY_MODEL=y' "$OUT/.config" && SCHED_FEATURES+=(EAS/energy_model)
grep -q '^CONFIG_SCHED_ENERGY=y' "$OUT/.config" && SCHED_FEATURES+=(sched_energy)
grep -q '^CONFIG_SCHED_TUNE=y' "$OUT/.config" && SCHED_FEATURES+=(sched_tune)
grep -q '^CONFIG_SCHED_HMP=y' "$OUT/.config" && SCHED_FEATURES+=(HMP)
grep -q '^CONFIG_SCHED_MC=y' "$OUT/.config" && SCHED_FEATURES+=(sched_mc)
grep -q '^CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y' "$OUT/.config" && SCHED_FEATURES+=(schedutil)
((${#SCHED_FEATURES[@]})) || SCHED_FEATURES=(none-detected)
SCHED_FEATURES_TEXT="$(IFS=,; echo "${SCHED_FEATURES[*]}")"

tg_edit "$MID" "🔨 <b>Compiling kernel…</b>
📱 <code>$DEVICE</code> | 🏗 <code>$ARCH</code> | 🧬 <code>$KERNEL_VERSION</code>
⚙️ <code>$DEFCONFIG</code>
🛠 <code>$COMPILER_VERSION</code>
🧭 <code>$SCHED_FEATURES_TEXT</code>"

# ---- Compile ----
if [[ -n "$KERNEL_TARGET" ]]; then
  "${MAKE_CMD[@]}" "$KERNEL_TARGET" >> "$BUILD_LOG" 2>&1 || fail "compile:$KERNEL_TARGET"
else
  "${MAKE_CMD[@]}" >> "$BUILD_LOG" 2>&1 || fail "compile"
fi

# ---- Collect outputs for 4.x and 5.x Android kernels ----
rm -rf "$ARTIFACTS"
mkdir -p "$ARTIFACTS"
FOUND=0
for item in \
  "$OUT/arch/$ARCH/boot/Image" \
  "$OUT/arch/$ARCH/boot/Image.gz" \
  "$OUT/arch/$ARCH/boot/Image.lz4" \
  "$OUT/arch/$ARCH/boot/Image.gz-dtb" \
  "$OUT/arch/$ARCH/boot/Image-dtb" \
  "$OUT/arch/$ARCH/boot/Image.lzo" \
  "$OUT/arch/$ARCH/boot/zImage" \
  "$OUT/arch/$ARCH/boot/dt.img" \
  "$OUT/arch/$ARCH/boot/dtbo.img"; do
  if [[ -f "$item" ]]; then cp -f "$item" "$ARTIFACTS/"; FOUND=1; fi
done

while IFS= read -r item; do
  cp -f "$item" "$ARTIFACTS/"
  FOUND=1
done < <(find "$OUT" -type f \( -name 'dtb.img' -o -name 'dtbo.img' \) -print 2>/dev/null | head -n 20)

[[ -f "$OUT/.config" ]] && cp -f "$OUT/.config" "$ARTIFACTS/kernel.config"
[[ -f "$OUT/System.map" ]] && cp -f "$OUT/System.map" "$ARTIFACTS/System.map"
[[ -f "$OUT/vmlinux" ]] && cp -f "$OUT/vmlinux" "$ARTIFACTS/vmlinux"
[[ -d "$OUT/arch/$ARCH/boot/dts" ]] && tar -czf "$ARTIFACTS/dts.tar.gz" -C "$OUT/arch/$ARCH/boot" dts 2>/dev/null || true
if find "$OUT" -type f -name '*.ko' -print -quit | grep -q .; then
  find "$OUT" -type f -name '*.ko' -print0 \
    | tar --null -czf "$ARTIFACTS/modules.tar.gz" --files-from=- 2>/dev/null || true
fi

[[ "$FOUND" -eq 1 ]] || fail "kernel image not found"

cat > "$ARTIFACTS/build-info.txt" <<INFO
device=$DEVICE
arch=$ARCH
kernel_version=$KERNEL_VERSION
kernel_repo=$KERNEL_REPO
kernel_branch=$KERNEL_BRANCH
commit=$COMMIT
defconfig=$DEFCONFIG
jobs=$JOBS
toolchain=$TOOLCHAIN
compiler=$COMPILER_VERSION
scheduler_profile=$SCHEDULER_PROFILE
scheduler_features=$SCHED_FEATURES_TEXT
enable_ksu=$ENABLE_KSU
INFO

# ---- Optional AnyKernel3 ZIP ----
if [[ "$PACKAGE_ANYKERNEL" == "true" ]]; then
  IMAGE=""
  for item in "$ARTIFACTS/Image" "$ARTIFACTS/Image.gz" "$ARTIFACTS/Image.lz4" \
              "$ARTIFACTS/Image.gz-dtb" "$ARTIFACTS/Image-dtb" "$ARTIFACTS/Image.lzo" \
              "$ARTIFACTS/zImage"; do
    if [[ -f "$item" ]]; then IMAGE="$item"; break; fi
  done
  [[ -n "$IMAGE" ]] || fail "AnyKernel image source not found"
  rm -rf "$WORK/AnyKernel3"
  git clone --depth=1 --branch "$ANYKERNEL_BRANCH" "$ANYKERNEL_REPO" "$WORK/AnyKernel3" \
    || fail "clone AnyKernel3"
  rm -f "$WORK/AnyKernel3"/Image "$WORK/AnyKernel3"/Image.gz \
        "$WORK/AnyKernel3"/Image.lz4 "$WORK/AnyKernel3"/Image.gz-dtb \
        "$WORK/AnyKernel3"/Image-dtb "$WORK/AnyKernel3"/Image.lzo "$WORK/AnyKernel3"/zImage
  cp "$IMAGE" "$WORK/AnyKernel3/$(basename "$IMAGE")"
  [[ -f "$ARTIFACTS/dtbo.img" ]] && cp "$ARTIFACTS/dtbo.img" "$WORK/AnyKernel3/"
  (
    cd "$WORK/AnyKernel3"
    rm -rf .git
    zip -r9 "$ARTIFACTS/Kernel-${DEVICE}-$(date +%Y%m%d-%H%M).zip" . -x '*.git*' > /dev/null
  ) || fail "AnyKernel package"
fi

ARCHIVE="$WORK/Kernel-${DEVICE}-$(date +%Y%m%d-%H%M).tar.gz"
tar -czf "$ARCHIVE" -C "$ARTIFACTS" . || fail "artifact archive"
DURATION=$(( $(date +%s) - START ))
SHA="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"

tg_edit "$MID" "✅ <b>Kernel build selesai</b>
📱 <code>$DEVICE</code> | 🏗 <code>$ARCH</code> | 🧬 <code>$KERNEL_VERSION</code>
⏱ $(fmt_dur "$DURATION")
🧱 <code>$SHORT_COMMIT</code>
🛠 <code>$TOOLCHAIN</code>
🧭 <code>$SCHED_FEATURES_TEXT</code>
📦 <code>$(basename "$ARCHIVE")</code>
🔐 SHA256: <code>${SHA:0:16}…</code>"

tg_file "$ARCHIVE" "📦 <b>Kernel artifacts — $DEVICE</b>"
echo "ARTIFACT_ARCHIVE=$ARCHIVE"
echo "ARTIFACT_SHA256=$SHA"
