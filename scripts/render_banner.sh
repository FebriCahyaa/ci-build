#!/usr/bin/env bash
# Compatibility banner renderer. Uses the canonical AnyKernel template through ci-patch.sh.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-banner}"
PROFILE="${PROFILE_ID:-${ANYKERNEL_PROFILE:-lavender-4.19}}"
VARIANT="${ROOT_VARIANT:-${ROOT_PROVIDER:-${KSU_PROVIDER:-vanilla}}}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp -a "$ROOT_DIR/anykernel/." "$TMP/"
KERNEL_NAME="${KERNEL_NAME:-Zairenkai}" \
  KERNEL_CODENAME="${KERNEL_CODENAME:-VEGA}" \
  KERNEL_BUILD="${KERNEL_BUILD:-1}" \
  BUILD_LABEL="${BUILD_LABEL:-Zairenkai-VEGA1}" \
  bash "$TMP/ci-patch.sh" --profile "$PROFILE" --variant "$VARIANT" --dir "$TMP" >/dev/null

mkdir -p "$(dirname "$OUT")"
cp -f "$TMP/banner" "$OUT"
printf '%s\n' "$OUT"
