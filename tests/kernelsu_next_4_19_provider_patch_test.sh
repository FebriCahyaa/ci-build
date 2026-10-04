#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/third_party/root-managers/kernelsu-next"
PATCH="$ROOT/patches/root-manager/kernelsu-next/4.19/0002-file-wrapper-linux-4.19-compat.patch"

if [[ ! -d "$SOURCE/.git" ]]; then
  echo 'SKIP: KernelSU-Next submodule is not initialized'
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git -C "$SOURCE" fetch -q --depth=1 origin refs/tags/v3.4.0:refs/tags/v3.4.0
git clone -q --local --no-hardlinks "$SOURCE" "$TMP/provider"
git -C "$TMP/provider" checkout -q --detach refs/tags/v3.4.0
git -C "$TMP/provider" apply --check --whitespace=error-all "$PATCH"
echo 'PASS: KernelSU-Next v3.4.0 4.19 file_wrapper patch applies cleanly'
