#!/usr/bin/env bash
# Sourced by build_kernel.sh. Do not change the caller's shell options here.

# Reproducible kernel build identity. Override these environment variables
# when another project/user explicitly needs different metadata.
KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-FebriCahyaa}"
KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-Zairenkai}"

export KBUILD_BUILD_USER
export KBUILD_BUILD_HOST
