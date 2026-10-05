#!/usr/bin/env bash
# Offline behavioral test of the root-manager patch registry contract:
#   provider-series.conf -> isolated provider checkout only (root_manager_apply.sh)
#   host-series.conf     -> host kernel tree only           (apply_patch_series.sh)
#   config.fragment      -> .config, values preserved verbatim
# Uses a local file:// provider and a temporary registry (CI_PATCH_ROOT), with a
# space in the work path to prove the generated env files are shell-safe.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
gitc() { git -c user.name=ci -c user.email=ci@example.invalid -c init.defaultBranch=main "$@"; }

# --- static registry lint ----------------------------------------------------
if find "$ROOT/patches/root-manager" -name series.conf | grep -q .; then
  fail "patches/root-manager must use provider-series.conf/host-series.conf, not series.conf"
fi
while IFS= read -r series; do
  while IFS= read -r patch; do
    file="$(dirname "$series")/$patch"
    [[ -f "$file" ]] || fail "missing provider patch $file"
    if grep -E '^diff --git a/' "$file" | grep -vqE '^diff --git a/kernel/'; then
      fail "provider patch $file touches paths outside the provider kernel/ tree"
    fi
  done < <(read_series "$series")
done < <(find "$ROOT/patches/root-manager" -name provider-series.conf)
pass "registry layout: provider patches only target provider kernel/ paths"

# --- fake provider (file://) and host kernel ----------------------------------
PROV="$TMP/provider"
mkdir -p "$PROV/kernel"
printf 'menu "KernelSU"\nconfig KSU\n\ttristate "KSU"\nendmenu\n' > "$PROV/kernel/Kconfig"
printf 'obj-$(CONFIG_KSU) += ksu.o\n' > "$PROV/kernel/Makefile"
printf 'int provider_value = 1;\n' > "$PROV/kernel/ksu.c"
gitc -C "$PROV" init -q && gitc -C "$PROV" add -A && gitc -C "$PROV" commit -qm provider && gitc -C "$PROV" tag v9.9.9

HOST="$TMP/host"
mkdir -p "$HOST/drivers/kernelsu" "$HOST/fs"
rmdir "$HOST/drivers/kernelsu"
printf 'obj-y += base/\nobj-y += kernelsu/\n' > "$HOST/drivers/Makefile"
printf 'menu "Device Drivers"\nmenu "Nested"\nendmenu\nsource "drivers/base/Kconfig"\nendmenu\n' > "$HOST/drivers/Kconfig"
printf 'int host_value = 1;\n' > "$HOST/fs/hook.c"
gitc -C "$HOST" init -q && gitc -C "$HOST" add -A && gitc -C "$HOST" commit -qm host

# --- temporary registry -------------------------------------------------------
REG="$TMP/patches"
mkdir -p "$REG/root-manager/custom/4.19" "$REG/root-manager/none/common"
cp "$ROOT/patches/root-manager/none/common/config.fragment" "$REG/root-manager/none/common/"
(cd "$PROV" && sed -i 's/= 1;/= 2;/' kernel/ksu.c && git diff > "$REG/root-manager/custom/4.19/0001-provider.patch" && git checkout -q -- kernel/ksu.c)
(cd "$HOST" && sed -i 's/= 1;/= 2;/' fs/hook.c && git diff > "$REG/root-manager/custom/4.19/0001-host.patch" && git checkout -q -- fs/hook.c)
printf '# provider\n0001-provider.patch\r\n' > "$REG/root-manager/custom/4.19/provider-series.conf"
printf '  0001-host.patch  \n' > "$REG/root-manager/custom/4.19/host-series.conf"
printf 'CONFIG_KSU=y\nCONFIG_LOCALVERSION="-a&b|c\\\\d"\n# CONFIG_FOO is not set\nCONFIG_BAR=m\n' > "$REG/root-manager/custom/4.19/config.fragment"

WORK="$TMP/work dir"
CI_PATCH_ROOT="$REG" SOURCE_DIR="$HOST" WORK_DIR="$WORK" KERNEL_VERSION=4.19 \
  ROOT_MANAGER=custom KSU_REPO="file://$PROV" KSU_REF=v9.9.9 ROOT_MANAGER_SOURCE_MODE=clone \
  bash "$ROOT/scripts/root_manager_apply.sh" >/dev/null 2>"$TMP/apply.log" || { cat "$TMP/apply.log" >&2; fail "root_manager_apply.sh"; }

(
  # shellcheck source=/dev/null
  source "$WORK/root-manager.env"
  [[ "$KSU_DIR" == "$WORK/KernelSU" ]] || fail "KSU_DIR with a space did not round-trip: $KSU_DIR"
  [[ "$ROOT_MANAGER_PATCHES_APPLIED" == "0001-provider.patch" ]] || fail "provider patch list: $ROOT_MANAGER_PATCHES_APPLIED"
) || exit 1
pass "root-manager.env is shell-safe (path with a space round-trips)"

grep -q 'provider_value = 2' "$WORK/KernelSU/kernel/ksu.c" || fail "provider patch not applied to provider checkout"
grep -q 'provider_value = 1' "$PROV/kernel/ksu.c" || fail "provider patch leaked into the provider source repository"
grep -q 'host_value = 1' "$HOST/fs/hook.c" || fail "root_manager_apply.sh modified host sources"
pass "provider-series.conf is applied to the isolated provider checkout only"

[[ "$(grep -c 'kernelsu/' "$HOST/drivers/Makefile")" == 1 ]] || fail "pre-integrated obj-y kernelsu/ entry was duplicated"
[[ "$(grep -c 'source "drivers/kernelsu/Kconfig"' "$HOST/drivers/Kconfig")" == 1 ]] || fail "provider Kconfig sourced more than once"
[[ "$(tail -n 2 "$HOST/drivers/Kconfig" | head -n 1)" == 'source "drivers/kernelsu/Kconfig"' ]] || fail "provider Kconfig not inserted before the last endmenu"
[[ -f "$HOST/drivers/kernelsu/Makefile" ]] || fail "drivers/kernelsu symlink does not resolve"
pass "host wiring: single Makefile entry, Kconfig sourced once before the outer endmenu"

CI_PATCH_ROOT="$REG" SOURCE_DIR="$HOST" KERNEL_VERSION=4.19 ROOT_MANAGER=custom KSU_REQUIRED=true \
  PATCH_PROFILE=none UPSTREAM_PROFILE=none PHASE=source bash "$ROOT/scripts/apply_patch_series.sh" >/dev/null
grep -q 'host_value = 2' "$HOST/fs/hook.c" || fail "host-series.conf not applied to host tree"
pass "host-series.conf is applied to the host kernel tree"

mkdir -p "$TMP/out"
printf 'CONFIG_KSU=m\nCONFIG_FOO=y\nCONFIG_LOCALVERSION="-old"\nCONFIG_LOCALVERSION="-dup"\n# CONFIG_BAR is not set\n' > "$TMP/out/.config"
CI_PATCH_ROOT="$REG" SOURCE_DIR="$HOST" KERNEL_VERSION=4.19 ROOT_MANAGER=custom KERNEL_OUT="$TMP/out" \
  PHASE=config bash "$ROOT/scripts/apply_patch_series.sh" >/dev/null
expected=$'CONFIG_KSU=y\n# CONFIG_FOO is not set\nCONFIG_LOCALVERSION="-a&b|c\\\\d"\nCONFIG_BAR=m'
[[ "$(cat "$TMP/out/.config")" == "$expected" ]] || { diff <(printf '%s\n' "$expected") "$TMP/out/.config" >&2; fail "config fragment merge"; }
pass "config fragments preserve '&', '|' and '\\' and collapse duplicate symbols"

# --- policy gates ---------------------------------------------------------------
mkdir -p "$TMP/gate"
if out="$(SOURCE_DIR="$HOST" WORK_DIR="$TMP/gate" KERNEL_VERSION=4.4 ROOT_MANAGER=sukisu-ultra \
    ROOT_MANAGER_SOURCE_MODE=clone bash "$ROOT/scripts/root_manager_apply.sh" 2>&1)"; then
  fail "SukiSU Ultra on Linux 4.4 must fail closed"
fi
grep -q 'SukiSU Ultra does not support Linux 4.4' <<<"$out" || fail "unexpected SukiSU 4.4 message: $out"
[[ ! -d "$TMP/gate/KernelSU" ]] || fail "SukiSU 4.4 gate ran after cloning"
pass "SukiSU Ultra on Linux 4.4 fails closed before any network access"

if out="$(SOURCE_DIR="$HOST" WORK_DIR="$TMP/gate" KERNEL_VERSION=4.4 ROOT_MANAGER=kernelsu \
    bash "$ROOT/scripts/root_manager_apply.sh" 2>&1)"; then
  fail "official KernelSU on Linux 4.4 must fail closed"
fi
pass "official KernelSU on Linux 4.4 fails closed"

if out="$(SOURCE_DIR="$HOST" WORK_DIR="$TMP/gate" KERNEL_VERSION=4.19 ROOT_MANAGER=kernelsu-next KSU_REF=v3.4.0 \
    ROOT_MANAGER_SOURCE_MODE=clone bash "$ROOT/scripts/root_manager_apply.sh" 2>&1)"; then
  fail "non-legacy KernelSU-Next on Linux 4.19 must fail closed"
fi
grep -q 'is not a legacy ref' <<<"$out" || fail "unexpected KernelSU-Next ref gate message: $out"
[[ ! -d "$TMP/gate/KernelSU" ]] || fail "KernelSU-Next ref gate ran after cloning"
pass "non-legacy KernelSU-Next refs fail closed below 5.10 before any network access"

for combo in "kernelsu-next 4.19" "kernelsu-next 4.4" "resukisu 4.4"; do
  set -- $combo
  if SOURCE_DIR="$HOST" WORK_DIR="$TMP/gate" KERNEL_VERSION="$2" ROOT_MANAGER="$1" ENABLE_SUSFS=true \
      ROOT_MANAGER_SOURCE_MODE=clone bash "$ROOT/scripts/root_manager_apply.sh" >/dev/null 2>&1; then
    fail "$1 + SUSFS on Linux $2 must fail closed"
  fi
done
pass "SUSFS fails closed for KernelSU-Next and for ReSukiSU on 4.4"

# --- susfs-series.conf / susfs.fragment (ENABLE_SUSFS only) --------------------
HOST2="$TMP/host2"
mkdir -p "$HOST2/fs"
printf 'int susfs_value = 1;\n' > "$HOST2/fs/susfs_hook.c"
gitc -C "$HOST2" init -q && gitc -C "$HOST2" add -A && gitc -C "$HOST2" commit -qm host2
(cd "$HOST2" && sed -i 's/= 1;/= 2;/' fs/susfs_hook.c && git diff > "$REG/root-manager/custom/4.19/0101-susfs.patch" && git checkout -q -- fs/susfs_hook.c)
printf '0101-susfs.patch\n' > "$REG/root-manager/custom/4.19/susfs-series.conf"
: > "$REG/root-manager/custom/4.19/host-series.conf"
printf '# CONFIG_KSU_MANUAL_HOOK is not set\nCONFIG_KSU_SUSFS=y\n' > "$REG/root-manager/custom/4.19/susfs.fragment"
run_source() { CI_PATCH_ROOT="$REG" SOURCE_DIR="$HOST2" KERNEL_VERSION=4.19 ROOT_MANAGER=custom KSU_REQUIRED=true \
  PATCH_PROFILE=none UPSTREAM_PROFILE=none PHASE=source ENABLE_SUSFS="$1" bash "$ROOT/scripts/apply_patch_series.sh" >/dev/null; }
run_source false
grep -q 'susfs_value = 1' "$HOST2/fs/susfs_hook.c" || fail "susfs-series.conf applied without ENABLE_SUSFS"
run_source true
grep -q 'susfs_value = 2' "$HOST2/fs/susfs_hook.c" || fail "susfs-series.conf not applied with ENABLE_SUSFS=true"
pass "susfs-series.conf is applied only with ENABLE_SUSFS=true"

printf 'CONFIG_KSU=y\nCONFIG_KSU_MANUAL_HOOK=y\n' > "$REG/root-manager/custom/4.19/config.fragment"
printf 'CONFIG_KSU_MANUAL_HOOK=y\n' > "$TMP/out/.config"
CI_PATCH_ROOT="$REG" SOURCE_DIR="$HOST2" KERNEL_VERSION=4.19 ROOT_MANAGER=custom KERNEL_OUT="$TMP/out" \
  ENABLE_SUSFS=true PHASE=config bash "$ROOT/scripts/apply_patch_series.sh" >/dev/null
expected=$'# CONFIG_KSU_MANUAL_HOOK is not set\nCONFIG_KSU=y\nCONFIG_KSU_SUSFS=y'
[[ "$(cat "$TMP/out/.config")" == "$expected" ]] || { diff <(printf '%s\n' "$expected") "$TMP/out/.config" >&2; fail "susfs.fragment merge"; }
pass "susfs.fragment overrides the provider fragment's hook mode"
