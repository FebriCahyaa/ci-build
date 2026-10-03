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
if [[ "$JOBS" == "0" || -z "$JOBS" ]]; then
  JOBS="$(nproc 2>/dev/null || echo 2)"
fi
KERNEL_TARGET="${KERNEL_TARGET:-}"
LLVM="${LLVM:-1}"
LLVM_IAS="${LLVM_IAS:-1}"
CROSS_COMPILE="${CROSS_COMPILE:-}"
CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32:-}"
CLANG_URL="${CLANG_URL:-}"
KERNEL_OUT="${KERNEL_OUT:-}"
ENABLE_KSU="${ENABLE_KSU:-false}"
KSU_REF="${KSU_REF:-}"
PACKAGE_ANYKERNEL="${PACKAGE_ANYKERNEL:-false}"
ANYKERNEL_REPO="${ANYKERNEL_REPO:-https://github.com/osm0sis/AnyKernel3}"
ANYKERNEL_BRANCH="${ANYKERNEL_BRANCH:-master}"
EXTRA_MAKE_ARGS="${EXTRA_MAKE_ARGS:-}"
BUILD_ENV="${BUILD_ENV:-}"
RUN_URL="${RUN_URL:-}"

START="$(date +%s)"
WORK="${WORK_DIR:-$PWD/work}"
mkdir -p "$WORK" "$WORK/artifacts"
BUILD_LOG="$WORK/build.log"
TOOLCHAIN_DIR="$WORK/toolchain"
OUT="${KERNEL_OUT:-$WORK/kernel-out}"

# Preserve a single, deterministic make invocation.
declare -a MAKE_BASE
MAKE_BASE=(make -j"$JOBS" O="$OUT" ARCH="$ARCH")

if [[ "$LLVM" == "1" || "$LLVM" == "true" ]]; then
  MAKE_BASE+=(LLVM=1)
fi
if [[ "$LLVM_IAS" == "1" || "$LLVM_IAS" == "true" ]]; then
  MAKE_BASE+=(LLVM_IAS=1)
fi
[[ -n "$CROSS_COMPILE" ]] && MAKE_BASE+=(CROSS_COMPILE="$CROSS_COMPILE")
[[ -n "$CROSS_COMPILE_ARM32" ]] && MAKE_BASE+=(CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32")

read -r -a EXTRA_ARGS <<< "$EXTRA_MAKE_ARGS"
MAKE_CMD=("${MAKE_BASE[@]}" "${EXTRA_ARGS[@]}")

MID="$(tg_msg "🚀 <b>Universal Kernel Build</b>
📱 Device: <code>$DEVICE</code>
🏗 ARCH: <code>$ARCH</code>
🌿 Repo: <code>$KERNEL_REPO</code>
🔀 Ref: <code>$KERNEL_BRANCH</code>
⚙️ Defconfig: <code>$DEFCONFIG</code>
🧵 Jobs: <code>$JOBS</code>
🛡 KSU: <code>$ENABLE_KSU</code>
🔗 <a href=\"$RUN_URL\">CI log</a>")"

fail() {
  local reason="$1"
  local duration=$(( $(date +%s) - START ))

  tg_edit "$MID" "❌ <b>Kernel build gagal</b>
📱 $DEVICE | 🏗 $ARCH
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

# ---- Optional custom toolchain ----
if [[ -n "$CLANG_URL" ]]; then
  mkdir -p "$TOOLCHAIN_DIR"
  curl -fL --retry 3 --retry-delay 2 "$CLANG_URL" -o "$WORK/clang.tar.gz" || fail "download clang"
  tar -xzf "$WORK/clang.tar.gz" -C "$TOOLCHAIN_DIR" || fail "extract clang"

  CLANG_BIN="$(find "$TOOLCHAIN_DIR" -type f -path '*/bin/clang' -print -quit || true)"
  [[ -n "$CLANG_BIN" ]] || fail "clang binary not found in toolchain"
  export PATH="$(dirname "$CLANG_BIN"):$PATH"
fi

if command -v clang >/dev/null 2>&1; then
  clang --version | head -n1 > "$WORK/clang_version.txt"
else
  fail "clang not found"
fi

# ---- Source ----
cd "$WORK"
git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" kernel || fail "clone kernel"
cd "$WORK/kernel"

COMMIT="$(git log -1 --pretty='%h %s')"
echo "Kernel commit: $COMMIT" | tee -a "$BUILD_LOG"
echo "Make command: ${MAKE_CMD[*]}" | tee -a "$BUILD_LOG"

if [[ -n "$BUILD_ENV" ]]; then
  # BUILD_ENV is intentionally opt-in for user-supplied build environments.
  eval "$BUILD_ENV"
fi

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
  ./scripts/config --file "$OUT/.config" -e KSU || fail "enable KSU"
  "${MAKE_CMD[@]}" olddefconfig >> "$BUILD_LOG" 2>&1 || fail "olddefconfig"
fi

tg_edit "$MID" "🔨 <b>Compiling kernel…</b>
📱 $DEVICE | 🏗 $ARCH
🧱 <code>$COMMIT</code>
🛠 <code>$(cat "$WORK/clang_version.txt")</code>"

if [[ -n "$KERNEL_TARGET" ]]; then
  "${MAKE_CMD[@]}" "$KERNEL_TARGET" >> "$BUILD_LOG" 2>&1 || fail "compile"
else
  "${MAKE_CMD[@]}" >> "$BUILD_LOG" 2>&1 || fail "compile"
fi

# ---- Collect artifacts ----
ARTIFACTS="$WORK/artifacts"
shopt -s nullglob

declare -a CANDIDATES=(
  "$OUT/arch/$ARCH/boot/Image"
  "$OUT/arch/$ARCH/boot/Image.gz"
  "$OUT/arch/$ARCH/boot/Image.lz4"
  "$OUT/arch/$ARCH/boot/Image.gz-dtb"
  "$OUT/arch/$ARCH/boot/zImage"
  "$OUT/arch/$ARCH/boot/dtbo.img"
)

FOUND=0
for item in "${CANDIDATES[@]}"; do
  if [[ -f "$item" ]]; then
    cp -f "$item" "$ARTIFACTS/"
    FOUND=1
  fi
done

# dtb/dtbo and modules are optional; collect anything useful without failing.
if [[ -d "$OUT/arch/$ARCH/boot/dts" ]]; then
  tar -czf "$ARTIFACTS/dts.tar.gz" -C "$OUT/arch/$ARCH/boot" dts 2>/dev/null || true
fi

if find "$OUT" -type f -name '*.ko' -print -quit | grep -q .; then
  find "$OUT" -type f -name '*.ko' -print0 | tar --null -czf "$ARTIFACTS/modules.tar.gz" --files-from=- 2>/dev/null || true
fi

[[ "$FOUND" -eq 1 ]] || fail "kernel image not found"

cat > "$ARTIFACTS/build-info.txt" <<INFO
device=$DEVICE
arch=$ARCH
kernel_repo=$KERNEL_REPO
kernel_branch=$KERNEL_BRANCH
commit=$COMMIT
defconfig=$DEFCONFIG
jobs=$JOBS
kernel_target=$KERNEL_TARGET
llvm=$LLVM
llvm_ias=$LLVM_IAS
enable_ksu=$ENABLE_KSU
INFO

# ---- Optional AnyKernel3 package ----
if [[ "$PACKAGE_ANYKERNEL" == "true" ]]; then
  IMAGE=""
  for item in "$ARTIFACTS/Image" "$ARTIFACTS/Image.gz" "$ARTIFACTS/Image.lz4" "$ARTIFACTS/Image.gz-dtb" "$ARTIFACTS/zImage"; do
    [[ -f "$item" ]] && { IMAGE="$item"; break; }
  done

  [[ -n "$IMAGE" ]] || fail "AnyKernel image source not found"

  rm -rf "$WORK/AnyKernel3"
  git clone --depth=1 -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_REPO" "$WORK/AnyKernel3" \
    || fail "clone AnyKernel3"

  rm -f "$WORK/AnyKernel3"/Image "$WORK/AnyKernel3"/Image.gz \
        "$WORK/AnyKernel3"/Image.lz4 "$WORK/AnyKernel3"/Image.gz-dtb \
        "$WORK/AnyKernel3"/zImage

  cp "$IMAGE" "$WORK/AnyKernel3/$(basename "$IMAGE")"
  [[ -f "$ARTIFACTS/dtbo.img" ]] && cp "$ARTIFACTS/dtbo.img" "$WORK/AnyKernel3/"

  (
    cd "$WORK/AnyKernel3"
    rm -rf .git
    zip -r9 "$ARTIFACTS/Kernel-${DEVICE}-$(date +%Y%m%d-%H%M).zip" . -x '*.git*' > /dev/null
  ) || fail "AnyKernel package"
fi

# ---- Final archive ----
ARCHIVE="$WORK/Kernel-${DEVICE}-$(date +%Y%m%d-%H%M).tar.gz"
tar -czf "$ARCHIVE" -C "$ARTIFACTS" . || fail "artifact archive"

DURATION=$(( $(date +%s) - START ))
SHA="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"

tg_edit "$MID" "✅ <b>Kernel build selesai</b>
📱 $DEVICE | 🏗 $ARCH
⏱ $(fmt_dur "$DURATION")
🧱 <code>$COMMIT</code>
🛠 <code>$(cat "$WORK/clang_version.txt")</code>
🛡 KSU: $ENABLE_KSU
📦 <code>$(basename "$ARCHIVE")</code>
🔐 SHA256: <code>${SHA:0:16}…</code>"

tg_file "$ARCHIVE" "📦 <b>Kernel artifacts — $DEVICE</b>"

echo "ARTIFACT_ARCHIVE=$ARCHIVE"
echo "ARTIFACT_SHA256=$SHA"
