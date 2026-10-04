#!/usr/bin/env bash
# Unified local trigger for GitHub kernel builds and the GitHub -> Harness bridge.
set -Eeuo pipefail

TARGET="${TARGET:-github}"
REPO="${REPO:-FebriCahyaa/ci-build}"
REF="${REF:-main}"
BUILD_PROFILE="${BUILD_PROFILE:-lavender-4.4}"
VARIANTS="${VARIANTS:-default}"
KERNEL_REPO_OVERRIDE="${KERNEL_REPO_OVERRIDE:-${KERNEL_REPO:-}}"
KERNEL_REF_OVERRIDE="${KERNEL_REF_OVERRIDE:-${KERNEL_BRANCH:-}}"
DEFCONFIG_OVERRIDE="${DEFCONFIG_OVERRIDE:-${DEFCONFIG:-}}"
CONFIG_FRAGMENT_OVERRIDE="${CONFIG_FRAGMENT_OVERRIDE:-${CONFIG_FRAGMENT:-}}"
JOBS="${JOBS:-0}"
TOOLCHAIN="${TOOLCHAIN:-auto}"
TOOLCHAIN_VERSION="${TOOLCHAIN_VERSION:-auto}"
LLVM_IAS="${LLVM_IAS:-auto}"
TOOLCHAIN_URL="${TOOLCHAIN_URL:-${CLANG_URL:-${GCC_URL:-}}}"
TWEAKS="${TWEAKS:-none}"
EXTRA_MAKE_ARGS="${EXTRA_MAKE_ARGS:-}"
PATCH_PROFILE="${PATCH_PROFILE:-auto}"
UPSTREAM_PROFILE="${UPSTREAM_PROFILE:-auto}"
LTO_PLUS="${LTO_PLUS:-false}"
KSU_REF="${KSU_REF:-auto}"
PACKAGE_ANYKERNEL="${PACKAGE_ANYKERNEL:-true}"
ROM_FAMILY="${ROM_FAMILY:-auto}"
ANYKERNEL_PROFILE="${ANYKERNEL_PROFILE:-auto}"
ANYKERNEL3_REF="${ANYKERNEL3_REF:-master}"
KERNEL_NAME="${KERNEL_NAME:-}"
APT_PACKAGES="${APT_PACKAGES:-}"
RELEASE="${RELEASE:-false}"
RELEASE_TAG="${RELEASE_TAG:-}"

require_gh() {
  command -v gh >/dev/null 2>&1 || { echo 'ERROR: gh CLI is required' >&2; exit 1; }
}

usage() {
  cat <<USAGE
Usage: TARGET=github|harness $0

Common:
  BUILD_PROFILE=lavender-4.4|lavender-4.19|garnet-gki
  VARIANTS=default|all|vanilla,kernelsu-next,resukisu,sukisu-ultra
  TOOLCHAIN=auto|aosp|aosp-r416183b|zyc-10|proton|llvm-18|neutron|llvm|gcc|system
  TOOLCHAIN_URL=<custom archive>  TWEAKS=none|balanced|performance
  REPO=owner/repo REF=branch
  RELEASE=true RELEASE_TAG=optional

TARGET=github runs .github/workflows/kernel.yml.
TARGET=harness runs .github/workflows/harness-kernel.yml, which triggers Harness.
USAGE
}

run_github() {
  require_gh
  gh workflow run kernel.yml -R "$REPO" -r "$REF" \
    -f build_profile="$BUILD_PROFILE" \
    -f variants="$VARIANTS" \
    -f kernel_repo_override="$KERNEL_REPO_OVERRIDE" \
    -f kernel_ref_override="$KERNEL_REF_OVERRIDE" \
    -f defconfig_override="$DEFCONFIG_OVERRIDE" \
    -f config_fragment_override="$CONFIG_FRAGMENT_OVERRIDE" \
    -f jobs="$JOBS" \
    -f toolchain="$TOOLCHAIN" \
    -f toolchain_version="$TOOLCHAIN_VERSION" \
    -f llvm_ias="$LLVM_IAS" \
    -f toolchain_url="$TOOLCHAIN_URL" \
    -f extra_make_args="$EXTRA_MAKE_ARGS" \
    -f patch_profile="$PATCH_PROFILE" \
    -f upstream_profile="$UPSTREAM_PROFILE" \
    -f tweaks="$TWEAKS" \
    -f lto_plus="$LTO_PLUS" \
    -f ksu_ref="$KSU_REF" \
    -f package_anykernel="$PACKAGE_ANYKERNEL" \
    -f rom_family="$ROM_FAMILY" \
    -f anykernel_profile="$ANYKERNEL_PROFILE" \
    -f anykernel3_ref="$ANYKERNEL3_REF" \
    -f kernel_name="$KERNEL_NAME" \
    -f apt_packages="$APT_PACKAGES" \
    -f release="$RELEASE" \
    -f release_tag="$RELEASE_TAG"
}

run_harness() {
  require_gh
  gh workflow run harness-kernel.yml -R "$REPO" -r "$REF" \
    -f build_profile="$BUILD_PROFILE" \
    -f root_variants="$VARIANTS" \
    -f kernel_repo_override="$KERNEL_REPO_OVERRIDE" \
    -f kernel_ref_override="$KERNEL_REF_OVERRIDE" \
    -f defconfig_override="$DEFCONFIG_OVERRIDE" \
    -f config_fragment_override="$CONFIG_FRAGMENT_OVERRIDE" \
    -f jobs="$JOBS" \
    -f toolchain="$TOOLCHAIN" \
    -f toolchain_version="$TOOLCHAIN_VERSION" \
    -f llvm_ias="$LLVM_IAS" \
    -f toolchain_url="$TOOLCHAIN_URL" \
    -f extra_make_args="$EXTRA_MAKE_ARGS" \
    -f patch_profile="$PATCH_PROFILE" \
    -f upstream_profile="$UPSTREAM_PROFILE" \
    -f tweaks="$TWEAKS" \
    -f lto_plus="$LTO_PLUS" \
    -f ksu_ref="$KSU_REF" \
    -f package_anykernel="$PACKAGE_ANYKERNEL" \
    -f rom_family="$ROM_FAMILY" \
    -f anykernel_profile="$ANYKERNEL_PROFILE" \
    -f anykernel3_ref="$ANYKERNEL3_REF" \
    -f kernel_name="$KERNEL_NAME" \
    -f apt_packages="$APT_PACKAGES" \
    -f publish_release="$RELEASE"
}

case "$TARGET" in
  github) run_github ;;
  harness) run_harness ;;
  -h|--help) usage ;;
  *) echo "ERROR: TARGET must be github or harness" >&2; exit 2 ;;
esac
