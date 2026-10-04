#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="$ROOT_DIR/patches/root-manager/kernelsu-next/4.19/0002-file-wrapper-linux-4.19-compat.patch"
README="$ROOT_DIR/patches/root-manager/kernelsu-next/4.19/README.md"

grep -qF '+#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)' "$PATCH"
grep -qF '+#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 20, 0)' "$PATCH"
grep -qF ' p->ops.remap_file_range =' "$PATCH"
! grep -q 'ksu_wrapper_clone_file_range' "$PATCH"
! grep -q 'ksu_wrapper_dedupe_file_range' "$PATCH"
grep -q 'Linux 4.19 leaves the newer remap callback unset' "$README"
echo 'PASS: KernelSU-Next 4.19 file_wrapper uses legacy-safe feature fences'
