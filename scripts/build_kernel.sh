#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/tg.sh"

: "${KERNEL_REPO:?}" "${KERNEL_BRANCH:?}" "${DEFCONFIG:?}"
DEVICE="${DEVICE:-garnet}"
ANYKERNEL_REPO="${ANYKERNEL_REPO:-https://github.com/osm0sis/AnyKernel3}"
ANYKERNEL_BRANCH="${ANYKERNEL_BRANCH:-master}"
ENABLE_KSU="${ENABLE_KSU:-false}"
CLANG_URL="${CLANG_URL:-}"
RUN_URL="${RUN_URL:-}"
START=$(date +%s)
WORK="$PWD/work"; mkdir -p "$WORK"; cd "$WORK"

MID=$(tg_msg "🚀 <b>Build Kernel dimulai</b>
📱 Device: <code>$DEVICE</code>
🌿 Repo: <code>$KERNEL_REPO</code>
🔀 Branch: <code>$KERNEL_BRANCH</code>
⚙️ Defconfig: <code>$DEFCONFIG</code>
🛡 KernelSU: <code>$ENABLE_KSU</code>
🔗 <a href=\"$RUN_URL\">Lihat log CI</a>")

fail() {
  local d=$(( $(date +%s) - START ))
  tg_edit "$MID" "❌ <b>Build Kernel GAGAL</b> pada tahap: <code>$1</code>
📱 $DEVICE | ⏱ $(fmt_dur $d)
🔗 <a href=\"$RUN_URL\">Log CI</a>"
  if [ -f "$WORK/build.log" ]; then
    tail -n 300 "$WORK/build.log" > "$WORK/error_tail.log"
    tg_file "$WORK/error_tail.log" "📄 300 baris terakhir log — $DEVICE"
  fi
  exit 1
}

# ---- Toolchain ----
if [ -n "$CLANG_URL" ]; then
  mkdir -p clang && curl -sL "$CLANG_URL" | tar -xz -C clang || fail "download clang"
  export PATH="$PWD/clang/bin:$PATH"
fi
clang --version | head -n1 > clang_ver.txt || fail "clang tidak ditemukan"

# ---- Source ----
git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" kernel || fail "clone kernel"
cd kernel
if [ "$ENABLE_KSU" = "true" ]; then
  curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash - || fail "setup KernelSU"
fi
COMMIT=$(git log -1 --pretty='%h %s')

# ---- Build ----
MK=(make -j"$(nproc)" O=out ARCH=arm64 LLVM=1 LLVM_IAS=1
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-)
"${MK[@]}" "$DEFCONFIG" > "$WORK/build.log" 2>&1 || fail "defconfig"
if [ "$ENABLE_KSU" = "true" ]; then
  ./scripts/config --file out/.config -e KSU
  "${MK[@]}" olddefconfig >> "$WORK/build.log" 2>&1
fi
tg_edit "$MID" "🔨 <b>Compiling kernel…</b> 📱 $DEVICE
🧱 <code>$COMMIT</code>
🛠 <code>$(cat "$WORK/clang_ver.txt")</code>"
"${MK[@]}" >> "$WORK/build.log" 2>&1 || fail "compile"

IMG=out/arch/arm64/boot/Image
[ -f "$IMG.gz-dtb" ] && IMG="$IMG.gz-dtb"
[ -f "$IMG" ] || fail "Image tidak ditemukan"

# ---- Package ----
git clone --depth=1 -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_REPO" "$WORK/AK3" || fail "clone AnyKernel3"
cp "$IMG" "$WORK/AK3/"
[ -f out/arch/arm64/boot/dtbo.img ] && cp out/arch/arm64/boot/dtbo.img "$WORK/AK3/"
cd "$WORK/AK3" && rm -rf .git
ZIP="Kernel-${DEVICE}-$(date +%Y%m%d-%H%M).zip"
zip -r9 "$WORK/$ZIP" . -x "*.git*" > /dev/null || fail "zip"

D=$(( $(date +%s) - START ))
SHA=$(sha256sum "$WORK/$ZIP" | cut -d' ' -f1)
tg_edit "$MID" "✅ <b>Build Kernel SELESAI</b>
📱 $DEVICE | ⏱ $(fmt_dur $D)
🧱 <code>$COMMIT</code>
🛠 <code>$(cat "$WORK/clang_ver.txt")</code>
🛡 KernelSU: $ENABLE_KSU
🔐 SHA256: <code>${SHA:0:16}…</code>"
tg_file "$WORK/$ZIP" "📦 <b>$ZIP</b>"
