#!/usr/bin/env bash
# SUSFS integration (ENABLE_SUSFS=true).
#
#   official KernelSU / 4.19  upstream simonpunk/susfs4ksu kernel-4.19 files,
#                             applied here (provider + host)
#   ReSukiSU / 4.19           SUSFS v2.2.0 backport from the patch registry:
#                             root-manager/resukisu/4.19/susfs-series.conf is
#                             applied by apply_patch_series.sh after the host
#                             hooks; this stage validates and records it
#
# Every other provider/kernel combination fails closed (root_manager_apply.sh
# rejects them before cloning; this is the second line of defence).
# Output: $WORK_DIR/susfs.env (shell-quoted).
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
CI_LOG_TAG=susfs
PATCH_ROOT="${CI_PATCH_ROOT:-$CI_ROOT/patches}"

SOURCE_DIR="${SOURCE_DIR:-}"
WORK_DIR="${WORK_DIR:-}"
KERNEL_VERSION="${KERNEL_VERSION:-0.0}"
ROOT_MANAGER="${ROOT_MANAGER:-none}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
SUSFS_REF="${SUSFS_REF:-001e69919c6271f690fd00b17e4c721c9e599152}"

fail() { ci_die "$*"; }
log() { ci_log "$*"; }

# SUSFS_VERSION/SUSFS_SOURCE contain spaces and '/'; the env file must be quoted.
write_susfs_env() {
  write_env "$WORK_DIR/susfs.env" \
    "ENABLE_SUSFS=true" \
    "SUSFS_REPO=$SUSFS_REPO" \
    "SUSFS_REF=$SUSFS_REF" \
    "SUSFS_COMMIT=$SUSFS_COMMIT" \
    "SUSFS_VERSION=$SUSFS_VERSION" \
    "SUSFS_SOURCE=$SUSFS_SOURCE"
  log "source=$SUSFS_SOURCE"
  log "ref=$SUSFS_REF"
  log "version=$SUSFS_VERSION"
}

is_true "$ENABLE_SUSFS" || exit 0
[[ -e "$SOURCE_DIR/.git" ]] || fail "SOURCE_DIR is not a git working tree"
[[ -n "$WORK_DIR" ]] || fail "WORK_DIR is required"
MM="$(kernel_mm "$KERNEL_VERSION")"

case "$ROOT_MANAGER:$MM" in
  resukisu:4.19|re-sukisu:4.19)
    SERIES="$PATCH_ROOT/root-manager/resukisu/4.19/susfs-series.conf"
    [[ -f "$SERIES" ]] || fail "ReSukiSU 4.19 SUSFS series missing: $SERIES"
    KSU_KCONFIG="$SOURCE_DIR/drivers/kernelsu/Kconfig"
    [[ -f "$KSU_KCONFIG" ]] || fail "provider Kconfig missing: $KSU_KCONFIG (run root_manager_apply.sh first)"
    grep -qE '^config[[:space:]]+KSU_SUSFS([[:space:]]|$)' "$KSU_KCONFIG" ||
      fail "ReSukiSU provider does not expose the CONFIG_KSU_SUSFS hook mode"
    patch_file="$(dirname "$SERIES")/$(read_series "$SERIES" | head -n1)"
    SUSFS_VERSION="$(sed -n 's/^+#define[[:space:]]\{1,\}SUSFS_VERSION[[:space:]]\{1,\}"\(.*\)"/\1/p' "$patch_file" | head -n1)"
    [[ -n "$SUSFS_VERSION" ]] || fail "unable to read SUSFS_VERSION from $patch_file"
    SUSFS_REPO="https://github.com/LavenderLabz/kernel_xiaomi_sdm660"
    SUSFS_REF="e4c673c9db9cf84805c1febc4ecb5e3660dd4067"
    SUSFS_COMMIT="$SUSFS_REF"
    SUSFS_SOURCE="registry:root-manager/resukisu/4.19/susfs-series.conf"
    write_susfs_env
    exit 0
    ;;
  official:4.19|kernelsu:4.19) ;;
  *)
    fail "SUSFS is supported for ReSukiSU and official KernelSU on Linux 4.19 only (ROOT_MANAGER=$ROOT_MANAGER, Linux $MM)"
    ;;
esac

# Official KernelSU v0.9.5 + upstream susfs4ksu kernel-4.19 (SUSFS 1.5.5).
SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_DIR="$WORK_DIR/susfs4ksu"
git_fetch_ref "$SUSFS_REPO" "$SUSFS_REF" "$SUSFS_DIR" || fail "fetch SUSFS ref $SUSFS_REF"

SUSFS_COMMIT="$(git -C "$SUSFS_DIR" rev-parse HEAD)"
SUSFS_VERSION="$(grep -RhsE '^#define[[:space:]]+SUSFS_VERSION' "$SUSFS_DIR/include" "$SUSFS_DIR/kernel_patches" 2>/dev/null |
  head -n1 | sed -E 's/^#define[[:space:]]+SUSFS_VERSION[[:space:]]+//; s/"//g' || true)"
[[ -n "$SUSFS_VERSION" ]] || SUSFS_VERSION="1.5.5 / kernel-4.19"

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
git -C "$KSU_DIR" apply --check --whitespace=nowarn "$PATCH_KSU" ||
  fail "SUSFS KernelSU patch does not apply cleanly: 10_enable_susfs_for_ksu.patch"
git -C "$KSU_DIR" apply --whitespace=nowarn "$PATCH_KSU"

git -C "$SOURCE_DIR" apply --check --whitespace=nowarn "$PATCH_KERNEL" ||
  fail "SUSFS 4.19 kernel patch does not apply cleanly"
git -C "$SOURCE_DIR" apply --whitespace=nowarn "$PATCH_KERNEL"

for pair in "$SUSFS_C:fs/susfs.c" "$SUSFS_H:include/linux/susfs.h"; do
  src="${pair%%:*}" dst="$SOURCE_DIR/${pair#*:}"
  if [[ -e "$dst" ]] && ! cmp -s "$src" "$dst"; then
    fail "existing ${pair#*:} differs from pinned SUSFS source"
  fi
  cp -f "$src" "$dst"
done
SUSFS_SOURCE="simonpunk/susfs4ksu"
write_susfs_env
