#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$ROOT/patches/root-manager/kernelsu-next/4.19"
PATCH="$PATCH_DIR/0002-file-wrapper-linux-4.19-compat.patch"
SERIES="$PATCH_DIR/series.conf"

fail(){ echo "FAIL: $*" >&2; exit 1; }
pass(){ echo "PASS: $*"; }

[[ -f "$PATCH" ]] || fail "4.19 file-wrapper compatibility patch missing"
grep -q '0002-file-wrapper-linux-4.19-compat.patch' "$SERIES" || fail "4.19 provider series missing file-wrapper patch"
grep -q 'KERNEL_VERSION(5, 1, 0)' "$PATCH" || fail "iopoll 5.1 compatibility guard missing"
grep -q 'KERNEL_VERSION(4, 20, 0)' "$PATCH" || fail "remap 4.20 compatibility guard missing"
grep -q 'ksu_wrapper_clone_file_range' "$PATCH" || fail "clone_file_range wrapper missing"
grep -q 'ksu_wrapper_dedupe_file_range' "$PATCH" || fail "dedupe_file_range wrapper missing"
grep -q 'p->ops.clone_file_range' "$PATCH" || fail "clone_file_range registration missing"
grep -q 'p->ops.dedupe_file_range' "$PATCH" || fail "dedupe_file_range registration missing"
if grep -q 'REMAP_FILE_DEDUP' "$PATCH"; then
  grep -q '#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 20, 0)' "$PATCH" || fail "REMAP_FILE_DEDUP path is not fenced for 4.19"
fi
pass "KernelSU-Next 4.19 file-wrapper compatibility contract"
