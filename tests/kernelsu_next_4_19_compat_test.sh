#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$ROOT/patches/root-manager/kernelsu-next/4.19"
PATCH="$PATCH_DIR/0002-file-wrapper-linux-4.19-compat.patch"
SECCOMP_PATCH="$PATCH_DIR/0003-seccomp-cache-linux-4.19-compat.patch"
PROVIDER_SERIES="$PATCH_DIR/provider-series.conf"
HOST_SERIES="$PATCH_DIR/host-series.conf"

fail(){ echo "FAIL: $*" >&2; exit 1; }
pass(){ echo "PASS: $*"; }

[[ -f "$PATCH" ]] || fail "4.19 file-wrapper compatibility patch missing"
[[ -f "$SECCOMP_PATCH" ]] || fail "4.19 seccomp-cache compatibility patch missing"
grep -q '^diff --git a/kernel/infra/file_wrapper\.c b/kernel/infra/file_wrapper\.c$' "$PATCH" || fail "patch is missing canonical git diff header"
grep -q '^0002-file-wrapper-linux-4.19-compat.patch$' "$PROVIDER_SERIES" || fail "4.19 provider series missing file-wrapper patch"
grep -q '^0003-seccomp-cache-linux-4.19-compat.patch$' "$PROVIDER_SERIES" || fail "4.19 provider series missing seccomp-cache patch"
[[ ! -e "$PATCH_DIR/series.conf" ]] || fail "ambiguous series.conf must not exist next to provider/host series"
if grep -q '0002-file-wrapper-linux-4.19-compat.patch' "$HOST_SERIES"; then
  fail "provider patch incorrectly listed in host series"
fi
grep -q '^0001-path-umount-backport-linux-4.19.patch$' "$HOST_SERIES" || fail "4.19 host series missing host compatibility patch"
grep -q 'KERNEL_VERSION(5, 1, 0)' "$PATCH" || fail "iopoll 5.1 compatibility guard missing"
grep -q 'KERNEL_VERSION(4, 20, 0)' "$PATCH" || fail "remap 4.20 compatibility guard missing"
grep -q 'ksu_wrapper_clone_file_range' "$PATCH" || fail "clone_file_range wrapper missing"
grep -q 'ksu_wrapper_dedupe_file_range' "$PATCH" || fail "dedupe_file_range wrapper missing"
grep -q 'p->ops.clone_file_range' "$PATCH" || fail "clone_file_range registration missing"
grep -q 'p->ops.dedupe_file_range' "$PATCH" || fail "dedupe_file_range registration missing"
grep -q '^diff --git a/kernel/infra/seccomp_cache\.c b/kernel/infra/seccomp_cache\.c$' "$SECCOMP_PATCH" || fail "seccomp-cache patch has wrong provider path"
grep -q 'SECCOMP_ARCH_NATIVE_NR' "$SECCOMP_PATCH" || fail "seccomp-cache patch missing native syscall bound"
grep -q '#define SECCOMP_ARCH_NATIVE_NR NR_syscalls' "$SECCOMP_PATCH" || fail "seccomp-cache patch must use NR_syscalls fallback"
pass "KernelSU-Next 4.19 seccomp-cache compatibility contract"
pass "KernelSU-Next 4.19 file-wrapper compatibility contract"
