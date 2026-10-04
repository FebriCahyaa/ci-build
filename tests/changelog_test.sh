#!/usr/bin/env bash
# Per-variant and aggregate changelog generation from build-info.txt keys that
# scripts/build_kernel.sh actually writes.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

git -C "$TMP" init -q source
printf 'source\n' > "$TMP/source/file.c"
git -C "$TMP/source" add file.c
git -C "$TMP/source" -c user.name=ci -c user.email=ci@example.invalid commit -qm 'test: changelog source'
sha="$(git -C "$TMP/source" rev-parse HEAD)"

for v in vanilla kernelsu-next resukisu sukisu-ultra; do
  mkdir -p "$TMP/info/$v"
  cat > "$TMP/info/$v/build-info.txt" <<EOF_INFO
build_profile=garnet-gki
device=garnet
kernel_version=5.10
kernel_family=5.10
defconfig=gki_defconfig
scheduler=EAS
dynamic_partition=true
gki=true
anykernel_profile=garnet-gki
kernel_repo=test/source
ref=garnet-t-oss
commit=${sha:0:7} test: changelog source
commit_sha=$sha
commit_subject=test: changelog source
toolchain=aosp
toolchain_version=clang-r450784e
llvm_ias=1
root_variant=$v
ksu_provider=$v
ksu_version=test
ksu_commit=test
kernel_image=Image
EOF_INFO
  BUILD_INFO="$TMP/info/$v/build-info.txt" SOURCE_DIR="$TMP/source" VARIANT="$v" \
    OUT_FILE="$TMP/info/$v/changelog.md" bash "$ROOT/scripts/generate_changelog.sh" single
done
INFO_ROOT="$TMP/info" OUT_FILE="$TMP/CHANGELOG.md" bash "$ROOT/scripts/generate_changelog.sh" aggregate

for needle in 'KernelSU-Next' 'ReSukiSU' 'SukiSU Ultra' 'Vanilla' '- Scheduler: `EAS`' '- HEAD: test: changelog source' '- Kernel image: `Image`' 'test: changelog source'; do
  grep -qF -- "$needle" "$TMP/CHANGELOG.md" || fail "aggregate changelog lacks: $needle"
done
grep -qE 'contains the .*, .* builds' "$TMP/CHANGELOG.md" || fail "variant list must be comma+space separated"
! grep -q '``' "$TMP/CHANGELOG.md" || fail "empty inline-code fields in changelog"
echo "PASS changelog single + aggregate"
