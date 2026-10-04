#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
before="$(sha256sum "$ROOT/localversion-cip" "$ROOT/localversion-st" "$ROOT/kernel-name")"
mkdir -p "$TMP/out" "$TMP/kernel"
printf 'CONFIG_LOCALVERSION="-old"\nCONFIG_LOCALVERSION_AUTO=y\n' > "$TMP/out/.config"
KERNEL_NAME=Zairenkai CONFIG_FILE="$TMP/out/.config" bash "$ROOT/scripts/set_kernel_name.sh"
grep -Fx 'CONFIG_LOCALVERSION="-Zairenkai-VEGA1"' "$TMP/out/.config"
printf -- '-stale\n' > "$TMP/kernel/localversion-st"
bash "$ROOT/scripts/sync_localversion_files.sh" "$TMP/kernel"
test ! -s "$TMP/kernel/localversion-cip"
test ! -s "$TMP/kernel/localversion-st"
# The CI repository's own identity files are inputs and must never be modified.
[[ "$(sha256sum "$ROOT/localversion-cip" "$ROOT/localversion-st" "$ROOT/kernel-name")" == "$before" ]] ||
  { echo 'FAIL: kernel identity scripts modified the CI repository' >&2; exit 1; }
grep -Fq 'KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-FebriCahyaa}"' "$ROOT/scripts/kbuild_identity.sh"
grep -Fq 'KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-Zairenkai}"' "$ROOT/scripts/kbuild_identity.sh"
grep -Fq 'Febrian Rahmad Cahya' "$ROOT/anykernel/ci-patch.sh"
# bump_localversion_st.sh keeps the whole build number ("-VEGA19" -> "-VEGA20").
for pair in -VEGA1:-VEGA2 -VEGA9:-VEGA10 -VEGA19:-VEGA20 -X3:-X4; do
  printf '%s\n' "${pair%%:*}" > "$TMP/st"
  LOCALVERSION_ST_FILE="$TMP/st" KERNEL_CODENAME_FILE="$TMP/codename" KERNEL_BUILD_FILE="$TMP/build" \
    bash "$ROOT/scripts/bump_localversion_st.sh" --bump >/dev/null
  [[ "$(cat "$TMP/st")" == "${pair#*:}" ]] || { echo "FAIL: bump ${pair%%:*} -> $(cat "$TMP/st")" >&2; exit 1; }
done
printf 'PASS kernel config name, Kbuild identity, localversion bump, and AnyKernel maintainer\n'
