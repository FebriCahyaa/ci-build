#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/tg.sh"

: "${MANIFEST_URL:?}" "${MANIFEST_BRANCH:?}" "${LUNCH_TARGET:?}" "${DEVICE:?}"
LOCAL_MANIFEST_URL="${LOCAL_MANIFEST_URL:-}"
LOCAL_MANIFEST_BRANCH="${LOCAL_MANIFEST_BRANCH:-}"
BUILD_CMD="${BUILD_CMD:-mka bacon}"
RUN_URL="${RUN_URL:-}"
SRC="${ROM_DIR:-$HOME/rom}"
START=$(date +%s)
mkdir -p "$SRC" && cd "$SRC"

MID=$(tg_msg "🚀 <b>Build ROM dimulai</b>
📱 Device: <code>$DEVICE</code>
📦 Manifest: <code>$MANIFEST_URL</code> (<code>$MANIFEST_BRANCH</code>)
🎯 Lunch: <code>$LUNCH_TARGET</code>
🔗 <a href=\"$RUN_URL\">Log CI</a>") || MID=""

fail() {
  local d=$(( $(date +%s) - START ))
  tg_edit "$MID" "❌ <b>Build ROM GAGAL</b> pada tahap: <code>$1</code>
📱 $DEVICE | ⏱ $(fmt_dur $d)
🔗 <a href=\"$RUN_URL\">Log CI</a>" || true
  [ -f "$SRC/out/error.log" ] && tg_file "$SRC/out/error.log" "📄 error.log — $DEVICE" || true
  if [ -f "$SRC/build.log" ]; then
    tail -n 300 "$SRC/build.log" > "$SRC/tail.log"
    tg_file "$SRC/tail.log" "📄 300 baris terakhir" || true
  fi
  exit 1
}

# ---- Sync ----
git config --global user.name  "${GIT_NAME:-ci-bot}"
git config --global user.email "${GIT_EMAIL:-ci@example.com}"
[ -d .repo ] || repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" --depth=1 || fail "repo init"
if [ -n "$LOCAL_MANIFEST_URL" ]; then
  rm -rf .repo/local_manifests
  git clone "$LOCAL_MANIFEST_URL" ${LOCAL_MANIFEST_BRANCH:+-b "$LOCAL_MANIFEST_BRANCH"} .repo/local_manifests || fail "local manifest"
fi
tg_edit "$MID" "🔄 <b>Sync source…</b> 📱 $DEVICE" || true
repo sync -c -j"$(nproc --all)" --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune > "$SRC/sync.log" 2>&1 \
  || repo sync -c -j4 --force-sync --no-clone-bundle --no-tags > "$SRC/sync.log" 2>&1 || fail "repo sync"

# ---- Build ----
export USE_CCACHE=1 CCACHE_EXEC="$(command -v ccache || true)"
ccache -M "${CCACHE_SIZE:-50G}" >/dev/null 2>&1 || true
tg_edit "$MID" "🔨 <b>Compiling ROM…</b> 📱 $DEVICE
🎯 <code>$LUNCH_TARGET</code>" || true
set +u; source build/envsetup.sh; set -u
lunch "$LUNCH_TARGET" > "$SRC/build.log" 2>&1 || fail "lunch"
( eval "$BUILD_CMD" ) >> "$SRC/build.log" 2>&1 || fail "compile"

# ---- Hasil ----
OUT="$SRC/out/target/product/$DEVICE"
ZIP=$(ls -t "$OUT"/*.zip 2>/dev/null | grep -v -E 'ota|target_files|symbols' | head -n1)
[ -n "$ZIP" ] || fail "zip ROM tidak ditemukan"
SIZE=$(du -h "$ZIP" | cut -f1)
SHA=$(sha256sum "$ZIP" | cut -d' ' -f1)

LINK="(file ada di server build)"
if [ -n "${RCLONE_REMOTE:-}" ] && command -v rclone >/dev/null; then
  rclone copy "$ZIP" "$RCLONE_REMOTE" >/dev/null 2>&1 \
    && LINK=$(rclone link "$RCLONE_REMOTE/$(basename "$ZIP")" 2>/dev/null || echo "terupload ke $RCLONE_REMOTE")
fi
D=$(( $(date +%s) - START ))
tg_edit "$MID" "✅ <b>Build ROM SELESAI</b>
📱 $DEVICE | ⏱ $(fmt_dur $D)
📦 <code>$(basename "$ZIP")</code> ($SIZE)
🔐 SHA256: <code>${SHA:0:16}…</code>
⬇️ $LINK" || true