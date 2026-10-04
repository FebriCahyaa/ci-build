#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
ORIGINAL="$TMP/localversion-cip.original"
cp "$ROOT/localversion-cip" "$ORIGINAL"
cleanup() { cp "$ORIGINAL" "$ROOT/localversion-cip"; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/out" "$TMP/kernel"
printf 'CONFIG_LOCALVERSION="-old"\nCONFIG_LOCALVERSION_AUTO=y\n' > "$TMP/out/.config"
KERNEL_NAME=Zairenkai CONFIG_FILE="$TMP/out/.config" bash "$ROOT/scripts/set_kernel_name.sh"
grep -Fx 'CONFIG_LOCALVERSION="-Zairenkai-VEGA1"' "$TMP/out/.config"
test ! -s "$ROOT/localversion-cip"
bash "$ROOT/scripts/sync_localversion_files.sh" "$TMP/kernel"
test ! -s "$TMP/kernel/localversion-cip"
test ! -s "$TMP/kernel/localversion-st"
grep -Fq 'KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-FebriCahyaa}"' "$ROOT/scripts/kbuild_identity.sh"
grep -Fq 'KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-Zairenkai}"' "$ROOT/scripts/kbuild_identity.sh"
grep -Fq 'Febrian Rahmad Cahya' "$ROOT/anykernel/ci-patch.sh"
printf 'PASS kernel config name, Kbuild identity, and AnyKernel maintainer\n'
