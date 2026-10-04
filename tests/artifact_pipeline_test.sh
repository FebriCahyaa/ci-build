#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/work/lavender-4.19/vanilla/artifacts" "$TMP/work/lavender-4.19/kernelsu-next/artifacts"
printf 'vanilla archive' > "$TMP/work/lavender-4.19/vanilla/artifacts/Kernel-lavender-vanilla.tar.gz"
printf 'vanilla zip' > "$TMP/work/lavender-4.19/vanilla/artifacts/Kernel-lavender-Vanilla.zip"
printf 'next archive' > "$TMP/work/lavender-4.19/kernelsu-next/artifacts/Kernel-lavender-next.tar.gz"
printf 'next info' > "$TMP/work/lavender-4.19/kernelsu-next/artifacts/build-info.txt"
printf 'variant\tPASS\t0\t10' > "$TMP/work/matrix-summary.txt"
printf 'failure' > "$TMP/work/lavender-4.19/kernelsu-next/failure-summary.txt"

cat > "$TMP/work/lavender-4.19/vanilla/artifacts/build-info.txt" <<EOF_INFO
build_profile=lavender-4.19
device=lavender
kernel_version=4.19.325
kernel_family=4.19
commit_sha=$(printf '%064d' 1)
commit_subject=test: artifact assembly
root_variant=vanilla
EOF_INFO

SOURCE_ROOT="$TMP/work" ASSET_DIR="$TMP/assets" CHANGELOG_OUT="$TMP/CHANGELOG.md" \
  BUILD_PROFILE=lavender-4.19 MATRIX_SUMMARY="$TMP/work/matrix-summary.txt" \
  bash "$ROOT/scripts/assemble_release_assets.sh"

test -f "$TMP/assets/CHANGELOG.md"
test -f "$TMP/assets/SHA256SUMS"
test -f "$TMP/assets/Kernel-lavender-vanilla.tar.gz"
test -f "$TMP/assets/Kernel-lavender-next.tar.gz"
test -f "$TMP/assets/MATRIX-SUMMARY.txt"
test -f "$TMP/assets/lavender-4.19-kernelsu-next-failure-summary.txt"

echo 'PASS release asset assembly and failure retention'

# Total-failure workspace: diagnostics/changelog remain assembleable, while no checksum is emitted.
mkdir -p "$TMP/failed/variant"
printf 'fatal compiler error' > "$TMP/failed/variant/failure-summary.txt"
SOURCE_ROOT="$TMP/failed" ASSET_DIR="$TMP/failed-assets" CHANGELOG_OUT="$TMP/failed-CHANGELOG.md" \
  BUILD_PROFILE=lavender-4.19 bash "$ROOT/scripts/assemble_release_assets.sh"
test -f "$TMP/failed-assets/CHANGELOG.md"
test -f "$TMP/failed-assets/variant-failure-summary.txt"
! test -f "$TMP/failed-assets/SHA256SUMS"
echo 'PASS total-failure release workspace is diagnostic-only'
