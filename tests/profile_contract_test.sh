#!/usr/bin/env bash
# Target profile registry, variant resolution and toolchain resolver contracts.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for profile in lavender-4.4 lavender-4.19 garnet-gki; do
  (
    eval "$(BUILD_PROFILE="$profile" bash "$ROOT/scripts/resolve_build_profile.sh")"
    [[ "$PROFILE_ID" == "$profile" ]] || fail "$profile: PROFILE_ID"
    for key in PROFILE_DEVICE PROFILE_KERNEL_FAMILY PROFILE_KERNEL_REPO PROFILE_DEFCONFIG PROFILE_DEFAULT_VARIANTS; do
      [[ -n "${!key}" ]] || fail "$profile: $key is empty"
    done
    [[ -f "$ROOT/anykernel/profiles/$PROFILE_ANYKERNEL_PROFILE.conf" ]] || fail "$profile: AnyKernel profile missing"
    case "$profile" in
      lavender-4.4) [[ "$PROFILE_DEFCONFIG" == lavender_defconfig && "$PROFILE_CONFIG_FRAGMENT" == none ]] || fail "$profile defconfig" ;;
      lavender-4.19) [[ "$PROFILE_DEFCONFIG" == vendor/xiaomi/sdm660_defconfig && "$PROFILE_CONFIG_FRAGMENT" == vendor/xiaomi/lavender.config ]] || fail "$profile defconfig" ;;
      garnet-gki) [[ "$PROFILE_GKI" == true ]] || fail "$profile GKI" ;;
    esac
  ) || exit 1
  echo "PASS profile $profile"
done
if BUILD_PROFILE=does-not-exist bash "$ROOT/scripts/resolve_build_profile.sh" >/dev/null 2>&1; then
  fail "unknown profile must be rejected"
fi
! grep -RInE 'garnet-(oss|hyperos)' "$ROOT/.github" "$ROOT/anykernel" "$ROOT/profiles" "$ROOT/harness" "$ROOT/scripts" || fail "stale garnet profile names"

[[ "$(BUILD_PROFILE=lavender-4.4 VARIANTS=default bash "$ROOT/scripts/resolve_variants.sh" --json)" == '["vanilla","kernelsu-next","resukisu"]' ]] || fail "lavender-4.4 default variants"
[[ "$(BUILD_PROFILE=garnet-gki VARIANTS=all bash "$ROOT/scripts/resolve_variants.sh" --json)" == '["vanilla","kernelsu-next","resukisu","sukisu-ultra"]' ]] || fail "garnet all variants"
[[ "$(BUILD_PROFILE=lavender-4.19 VARIANTS='ksun, vanilla ksun' bash "$ROOT/scripts/resolve_variants.sh" --json)" == '["kernelsu-next","vanilla"]' ]] || fail "alias/dedupe"
if BUILD_PROFILE=lavender-4.19 VARIANTS='vanilla,bogus' bash "$ROOT/scripts/resolve_variants.sh" >/dev/null 2>&1; then
  fail "unknown variant must fail the resolver"
fi
echo "PASS variant resolution"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' 'VERSION = 5' 'PATCHLEVEL = 10' 'SUBLEVEL = 160' > "$tmp/Makefile"
TOOLCHAIN=system ARCH=arm64 bash "$ROOT/scripts/toolchain_resolver.sh" "$tmp" "$tmp/work" > "$tmp/toolchain.env"
grep -q '^RESOLVED_COMPILER_STRING=' "$tmp/toolchain.env" || fail "toolchain: compiler string"
grep -Eq '^RESOLVED_CROSS_DEFAULT=[^[:space:]]+$' "$tmp/toolchain.env" || fail "toolchain: cross prefix"
grep -Eq '^RESOLVED_CLANG_TRIPLE=[^[:space:]]+$' "$tmp/toolchain.env" || fail "toolchain: clang triple"
echo "PASS toolchain resolver output contract"

# Preset compatibility gates fail before any download.
mk() { mkdir -p "$tmp/k$1$2"; printf '%s\n' "VERSION = $1" "PATCHLEVEL = $2" 'SUBLEVEL = 0' > "$tmp/k$1$2/Makefile"; echo "$tmp/k$1$2"; }
for case in "neutron 4 4" "llvm-18 4 4" "zyc-10 5 10" "proton 4 4"; do
  set -- $case
  if out="$(TOOLCHAIN=$1 ARCH=arm64 bash "$ROOT/scripts/toolchain_resolver.sh" "$(mk "$2" "$3")" "$tmp/w" 2>&1)"; then
    fail "TOOLCHAIN=$1 must be rejected on Linux $2.$3"
  fi
  grep -q "not validated for Linux $2.$3" <<<"$out" || fail "unexpected message for $1 on $2.$3: $out"
done
if TOOLCHAIN=bogus ARCH=arm64 bash "$ROOT/scripts/toolchain_resolver.sh" "$(mk 4 19)" "$tmp/w" >/dev/null 2>&1; then
  fail "unknown toolchain family must be rejected"
fi
echo "PASS toolchain preset kernel-range gates"
