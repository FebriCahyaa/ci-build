#!/usr/bin/env bash
set -euo pipefail

REPO="${GH_REPO:-FebriCahyaa/ci-build}"
WORKFLOW="${GH_WORKFLOW:-kernel.yml}"
REF="${GH_REF:-main}"

KERNEL_REPO="${KERNEL_REPO:-https://github.com/pix106/android_kernel_xiaomi_sdm660_southwest-ng}"
KERNEL_BRANCH="${KERNEL_BRANCH:-main}"
DEVICE="${DEVICE:-lavender}"
ARCH="${ARCH:-auto}"
DEFCONFIG="${DEFCONFIG:-auto}"
CONFIG_FRAGMENT="${CONFIG_FRAGMENT:-auto}"
JOBS="${JOBS:-0}"
TOOLCHAIN="${TOOLCHAIN:-auto}"
TOOLCHAIN_VERSION="${TOOLCHAIN_VERSION:-auto}"
LLVM_IAS="${LLVM_IAS:-auto}"
CROSS_COMPILE="${CROSS_COMPILE:-auto}"
CLANG_URL="${CLANG_URL:-}"
GCC_URL="${GCC_URL:-}"
APT_PACKAGES="${APT_PACKAGES:-}"
EXTRA_MAKE_ARGS="${EXTRA_MAKE_ARGS:-}"
ENABLE_KSU="${ENABLE_KSU:-false}"
KSU_REF="${KSU_REF:-main}"
PATCH_PROFILE="${PATCH_PROFILE:-none}"
UPSTREAM_PROFILE="${UPSTREAM_PROFILE:-none}"
LTO_PLUS="${LTO_PLUS:-false}"
KERNEL_NAME="${KERNEL_NAME:-}"
PACKAGE_ANYKERNEL="${PACKAGE_ANYKERNEL:-false}"
ROM_FAMILY="${ROM_FAMILY:-auto}"
ANYKERNEL_PROFILE="${ANYKERNEL_PROFILE:-auto}"
ANYKERNEL3_REF="${ANYKERNEL3_REF:-master}"

command -v gh >/dev/null 2>&1 || {
  echo "ERROR: GitHub CLI (gh) belum terpasang." >&2
  exit 127
}

gh auth status >/dev/null 2>&1 || {
  echo "ERROR: login GitHub belum aktif. Jalankan: gh auth login" >&2
  exit 1
}

printf '%s\n' \
  "=== Local -> GitHub Actions ===" \
  "Repo       : ${REPO}" \
  "Workflow   : ${WORKFLOW}" \
  "Ref        : ${REF}" \
  "Kernel repo: ${KERNEL_REPO}" \
  "Kernel ref : ${KERNEL_BRANCH}" \
  "Device     : ${DEVICE}" \
  "KSU        : ${ENABLE_KSU}" \
  "Patch      : ${PATCH_PROFILE}" \
  "Upstream   : ${UPSTREAM_PROFILE}" \
  "LTO+       : ${LTO_PLUS}" \
  "Kernel name: ${KERNEL_NAME:-<from kernel-name>}"

echo

gh workflow run "${WORKFLOW}" \
  --repo "${REPO}" \
  --ref "${REF}" \
  -f kernel_repo="${KERNEL_REPO}" \
  -f kernel_branch="${KERNEL_BRANCH}" \
  -f device="${DEVICE}" \
  -f arch="${ARCH}" \
  -f defconfig="${DEFCONFIG}" \
  -f config_fragment="${CONFIG_FRAGMENT}" \
  -f jobs="${JOBS}" \
  -f toolchain="${TOOLCHAIN}" \
  -f toolchain_version="${TOOLCHAIN_VERSION}" \
  -f llvm_ias="${LLVM_IAS}" \
  -f cross_compile="${CROSS_COMPILE}" \
  -f clang_url="${CLANG_URL}" \
  -f gcc_url="${GCC_URL}" \
  -f apt_packages="${APT_PACKAGES}" \
  -f extra_make_args="${EXTRA_MAKE_ARGS}" \
  -f enable_ksu="${ENABLE_KSU}" \
  -f ksu_ref="${KSU_REF}" \
  -f patch_profile="${PATCH_PROFILE}" \
  -f upstream_profile="${UPSTREAM_PROFILE}" \
  -f lto_plus="${LTO_PLUS}" \
  -f kernel_name="${KERNEL_NAME}" \
  -f package_anykernel="${PACKAGE_ANYKERNEL}" \
  -f rom_family="${ROM_FAMILY}" \
  -f anykernel_profile="${ANYKERNEL_PROFILE}" \
  -f anykernel3_ref="${ANYKERNEL3_REF}"

echo
echo "Workflow berhasil dikirim ke GitHub Actions."
gh run list --repo "${REPO}" --workflow "${WORKFLOW}" --limit 5
