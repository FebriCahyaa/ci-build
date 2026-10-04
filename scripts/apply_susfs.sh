#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="${SOURCE_DIR:-}"
WORK_DIR="${WORK_DIR:-}"
KERNEL_VERSION="${KERNEL_VERSION:-0.0}"
ROOT_MANAGER="${ROOT_MANAGER:-none}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
SUSFS_REF="${SUSFS_REF:-001e69919c6271f690fd00b17e4c721c9e599152}"

fail() { echo "[susfs] ERROR: $*" >&2; exit 1; }
log() { echo "[susfs] $*" >&2; }

[[ "$ENABLE_SUSFS" == "true" || "$ENABLE_SUSFS" == "1" ]] || exit 0
[[ -d "$SOURCE_DIR/.git" ]] || fail "SOURCE_DIR is not a git working tree"
[[ -n "$WORK_DIR" ]] || fail "WORK_DIR is required"

MAJOR="${KERNEL_VERSION%%.*}"
REST="${KERNEL_VERSION#*.}"
MINOR="${REST%%.*}"
MM="${MAJOR}.${MINOR}"

[[ "$MM" == "4.19" ]] || fail "this SUSFS profile is only for Linux 4.19"

case "$ROOT_MANAGER" in
  official|kernelsu)
    PROVIDER="official"
    ;;
  resukisu|re-sukisu)
    PROVIDER="resukisu"
    ;;
  kernelsu-next|ksu-next|next)
    fail "SUSFS 4.19 upstream patch set is based on official KernelSU; KSU-Next integration is intentionally blocked"
    ;;
  *)
    fail "SUSFS requires a supported root provider; ROOT_MANAGER=$ROOT_MANAGER"
    ;;
esac

SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_DIR="$WORK_DIR/susfs4ksu"
rm -rf "$SUSFS_DIR"

git init "$SUSFS_DIR" >/dev/null
git -C "$SUSFS_DIR" remote add origin "$SUSFS_REPO"
git -C "$SUSFS_DIR" fetch --depth=1 origin "$SUSFS_REF" || fail "fetch SUSFS ref $SUSFS_REF"
git -C "$SUSFS_DIR" checkout --detach FETCH_HEAD >/dev/null

SUSFS_COMMIT="$(git -C "$SUSFS_DIR" rev-parse HEAD)"
SUSFS_VERSION="$(grep -RhsE '^#define[[:space:]]+SUSFS_VERSION|Bump version to' "$SUSFS_DIR/include" "$SUSFS_DIR/kernel_patches" 2>/dev/null | head -n1 || true)"
[[ -n "$SUSFS_VERSION" ]] || SUSFS_VERSION="1.5.5 / kernel-4.19"

if [[ "$PROVIDER" == "resukisu" ]]; then
  # ReSukiSU provides its SUSFS path itself. We only verify the Kconfig
  # surface exists; no official-KernelSU-only patch is mixed into it.
  KSU_KCONFIG="$SOURCE_DIR/drivers/kernelsu/kernel/Kconfig"
  [[ -f "$KSU_KCONFIG" ]] || KSU_KCONFIG="$SOURCE_DIR/drivers/kernelsu/Kconfig"
  grep -qE 'config[[:space:]]+KSU_SUSFS([[:space:]]|$)' "$KSU_KCONFIG" ||
    fail "ReSukiSU provider does not expose CONFIG_KSU_SUSFS"
  SUSFS_SOURCE="resukisu-integrated"
else
  PATCH_KSU="$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
  PATCH_KERNEL="$SUSFS_DIR/kernel_patches/50_add_susfs_in_kernel-4.19.patch"
  SUSFS_C="$SUSFS_DIR/kernel_patches/fs/susfs.c"
  SUSFS_H="$SUSFS_DIR/kernel_patches/include/linux/susfs.h"

  for f in "$PATCH_KSU" "$PATCH_KERNEL" "$SUSFS_C" "$SUSFS_H"; do
    [[ -f "$f" ]] || fail "missing upstream SUSFS file: $f"
  done

  # root_manager_apply.sh checks the provider out under WORK_DIR and links
  # drivers/kernelsu -> <provider>/kernel; the KernelSU patch targets that checkout.
  KSU_DIR="${KSU_DIR:-$WORK_DIR/KernelSU}"
  [[ -d "$KSU_DIR/.git" ]] || fail "official KernelSU provider checkout missing: $KSU_DIR"

  pushd "$KSU_DIR" >/dev/null
  git apply --check --whitespace=nowarn "$PATCH_KSU" ||
    fail "SUSFS KernelSU patch does not apply cleanly: 10_enable_susfs_for_ksu.patch"
  git apply --whitespace=nowarn "$PATCH_KSU"
  popd >/dev/null

  git -C "$SOURCE_DIR" apply --check --whitespace=nowarn "$PATCH_KERNEL" ||
    fail "SUSFS 4.19 kernel patch does not apply cleanly"
  git -C "$SOURCE_DIR" apply --whitespace=nowarn "$PATCH_KERNEL"

  if [[ -e "$SOURCE_DIR/fs/susfs.c" ]]; then
    cmp -s "$SUSFS_C" "$SOURCE_DIR/fs/susfs.c" ||
      fail "existing fs/susfs.c differs from pinned SUSFS source"
  fi
  if [[ -e "$SOURCE_DIR/include/linux/susfs.h" ]]; then
    cmp -s "$SUSFS_H" "$SOURCE_DIR/include/linux/susfs.h" ||
      fail "existing include/linux/susfs.h differs from pinned SUSFS source"
  fi

  cp -f "$SUSFS_C" "$SOURCE_DIR/fs/susfs.c"
  cp -f "$SUSFS_H" "$SOURCE_DIR/include/linux/susfs.h"
  SUSFS_SOURCE="simonpunk/susfs4ksu"
fi

cat > "$WORK_DIR/susfs.env" <<EOF
ENABLE_SUSFS=true
SUSFS_REPO=$SUSFS_REPO
SUSFS_REF=$SUSFS_REF
SUSFS_COMMIT=$SUSFS_COMMIT
SUSFS_VERSION=$SUSFS_VERSION
SUSFS_SOURCE=$SUSFS_SOURCE
EOF

log "source=$SUSFS_SOURCE"
log "ref=$SUSFS_REF"
log "commit=$SUSFS_COMMIT"
log "version=$SUSFS_VERSION"