#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   ROOT_DIR=/path/to/ci-build \
#   ROOT_PROVIDER=kernelsu-next \
#   KERNEL_RELEASE=4.19.325-Zairenkai-VEGA1 \
#   BUILD_LABEL=Zairenkai-VEGA1 \
#   TOOLCHAIN="aosp clang-r416183b" \
#   KBUILD_BUILD_USER=FebriCahyaa \
#   KBUILD_BUILD_HOST=ZairenkaiProject \
#   scripts/render_banner.sh /path/to/anykernel/banner
#
# The resulting file is copied as the AnyKernel3 `banner`.
