#!/usr/bin/env bash
# Install kernel build dependencies. Shared by GitHub Actions, Harness, and local builds.
# libz3-4 is required by prebuilt clang releases such as ZyC Clang.
#   EXTRA: APT_PACKAGES="pkg1 pkg2"
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
CI_LOG_TAG=deps

export DEBIAN_FRONTEND=noninteractive

PACKAGES=(
  bc bison flex build-essential cpio git curl ca-certificates
  python3 zip unzip xz-utils zstd lz4 tar gzip ccache
  libssl-dev libelf-dev
  clang lld llvm
  libz3-4
  gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi binutils-aarch64-linux-gnu
)

read -r -a EXTRA <<< "${APT_PACKAGES:-}"

ci_log "installing ${#PACKAGES[@]} base packages ${EXTRA[*]:+(+ ${EXTRA[*]})}"
sudo_if_needed apt-get update -qq
sudo_if_needed apt-get install -y -qq --no-install-recommends "${PACKAGES[@]}" "${EXTRA[@]}"
