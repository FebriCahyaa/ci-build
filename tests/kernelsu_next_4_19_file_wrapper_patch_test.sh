#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="$ROOT_DIR/patches/root-manager/kernelsu-next/4.19/0002-file-wrapper-linux-4.19-compat.patch"
README="$ROOT_DIR/patches/root-manager/kernelsu-next/4.19/README.md"

fail(){ echo "FAIL: $*" >&2; exit 1; }
pass(){ echo "PASS: $*"; }

grep -qF '+#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)' "$PATCH" || fail 'iopoll guard missing'
grep -qF '+#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 20, 0)' "$PATCH" || fail 'remap guard missing'
grep -qF 'ksu_wrapper_clone_file_range' "$PATCH" || fail 'clone_file_range wrapper missing'
grep -qF 'ksu_wrapper_dedupe_file_range' "$PATCH" || fail 'dedupe_file_range wrapper missing'
grep -qF ' p->ops.clone_file_range =' "$PATCH" || fail 'clone_file_range registration missing'
grep -qF ' p->ops.dedupe_file_range =' "$PATCH" || fail 'dedupe_file_range registration missing'
grep -q 'Linux 4.19 forwards its native `clone_file_range` and `dedupe_file_range`' "$README" || fail 'README contract missing'
pass 'KernelSU-Next 4.19 file_wrapper uses legacy-safe feature fences and native clone/dedupe wrappers'
