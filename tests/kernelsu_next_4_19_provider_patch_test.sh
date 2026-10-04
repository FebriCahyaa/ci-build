#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/third_party/root-managers/kernelsu-next"
REMOTE="https://github.com/KernelSU-Next/KernelSU-Next.git"
PATCH="$ROOT/patches/root-manager/kernelsu-next/4.19/0002-file-wrapper-linux-4.19-compat.patch"
EXPECTED_COMMIT="1a879d6a866f80b1fa1c1009a2ffa747873cbb5e"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -d "$SOURCE/.git" ]] && git -C "$SOURCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$SOURCE" fetch -q --depth=1 origin refs/tags/v3.4.0:refs/tags/v3.4.0
  git clone -q --local --no-hardlinks "$SOURCE" "$TMP/provider"
else
  git clone -q --depth=1 --branch v3.4.0 "$REMOTE" "$TMP/provider"
fi

git -C "$TMP/provider" checkout -q --detach refs/tags/v3.4.0 2>/dev/null || true
ACTUAL_COMMIT="$(git -C "$TMP/provider" rev-parse HEAD)"
[[ "$ACTUAL_COMMIT" == "$EXPECTED_COMMIT" ]] || {
  echo "FAIL: KernelSU-Next v3.4.0 resolved to $ACTUAL_COMMIT, expected $EXPECTED_COMMIT" >&2
  exit 1
}
git -C "$TMP/provider" apply --check --whitespace=error-all "$PATCH"
echo 'PASS: KernelSU-Next v3.4.0 4.19 file_wrapper patch applies cleanly'
