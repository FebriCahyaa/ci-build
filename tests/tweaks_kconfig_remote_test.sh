#!/usr/bin/env bash
# Network test: every tweak level must fully survive `olddefconfig` on the real
# target trees (Kconfig-only sparse checkouts), and the garnet device patch must
# make gki_defconfig resolvable. Requires clang + an aarch64 cross toolchain.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

for profile_file in "$ROOT"/profiles/targets/*.conf; do
  profile="$(basename "$profile_file" .conf)"
  (
    load_profile "$profile"
    tree="$TMP/$profile"
    git clone -q --depth=1 --filter=blob:none --sparse --branch "$PROFILE_KERNEL_REF" "$PROFILE_KERNEL_REPO" "$tree"
    git -C "$tree" sparse-checkout set --no-cone '/scripts/' '/Makefile' 'Kconfig*' '/arch/arm64/' '/include/' '/usr/' '/tools/' \
      '/drivers/misc/Makefile'
    SOURCE_DIR="$tree" KERNEL_VERSION="$PROFILE_KERNEL_FAMILY" DEVICE="$PROFILE_DEVICE" KERNEL_REPO="$PROFILE_KERNEL_REPO" \
      PATCH_PROFILE="$PROFILE_PATCH_PROFILE" UPSTREAM_PROFILE="$PROFILE_UPSTREAM_PROFILE" PHASE=source \
      bash "$ROOT/scripts/apply_patch_series.sh" >/dev/null
    for level in balanced performance; do
      out="$TMP/out-$profile-$level"
      make_cmd=(make -s -C "$tree" O="$out" ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE=aarch64-linux-gnu-
                CROSS_COMPILE_COMPAT=arm-linux-gnueabi- "HOSTCC=gcc -fcommon")
      "${make_cmd[@]}" "$PROFILE_DEFCONFIG" >"$out.log" 2>&1 || { tail -5 "$out.log" >&2; echo "FAIL: $profile defconfig" >&2; exit 1; }
      [[ "$PROFILE_CONFIG_FRAGMENT" == none ]] || cat "$tree/arch/arm64/configs/$PROFILE_CONFIG_FRAGMENT" >> "$out/.config"
      KERNEL_OUT="$out" SOURCE_DIR="$tree" KERNEL_VERSION="$PROFILE_KERNEL_FAMILY" DEVICE="$PROFILE_DEVICE" \
        ROOT_MANAGER=none TWEAKS="$level" PHASE=config bash "$ROOT/scripts/apply_patch_series.sh" >/dev/null
      "${make_cmd[@]}" olddefconfig >>"$out.log" 2>&1
      report="$(KERNEL_OUT="$out" SOURCE_DIR="$tree" KERNEL_VERSION="$PROFILE_KERNEL_FAMILY" PHASE=verify \
        bash "$ROOT/scripts/apply_patch_series.sh")"
      echo "$report" | sed "s/^/$profile: /"
      ! grep -q 'not applied' <<<"$report" || { echo "FAIL: $profile $level tweaks dropped by Kconfig" >&2; exit 1; }
    done
  ) || fail=1
done
exit "$fail"
