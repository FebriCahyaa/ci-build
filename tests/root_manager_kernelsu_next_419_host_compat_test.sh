#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SERIES="$ROOT_DIR/patches/root-manager/kernelsu-next/4.19/host-series.conf"
PATCH="$ROOT_DIR/patches/root-manager/kernelsu-next/4.19/0001-path-umount-backport-linux-4.19.patch"

test -f "$SERIES"
test -f "$PATCH"
grep -q '^0001-path-umount-backport-linux-4.19\.patch$' "$SERIES"
grep -q '^+int path_umount(struct path \*path, int flags)$' "$PATCH"
grep -q 'KernelSU-Next v3\.4\.0' "$ROOT_DIR/patches/root-manager/kernelsu-next/4.19/README.md"
grep -q 'host-series\.conf' "$ROOT_DIR/scripts/apply_patch_series.sh"
echo "PASS: KernelSU-Next 4.19 host compatibility registry"
