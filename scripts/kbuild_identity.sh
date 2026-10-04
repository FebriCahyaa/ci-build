#!/usr/bin/env bash
set -Eeuo pipefail

# Reproducible kernel build identity. Override these environment variables
# when another project/user explicitly needs different metadata.
KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-FebriCahyaa}"
KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-ZairenkaiProject}"

export KBUILD_BUILD_USER
export KBUILD_BUILD_HOST