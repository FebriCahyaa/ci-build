#!/usr/bin/env bash
# AnyKernel3 selector, template rendering (every profile x variant) and one real
# fail-closed package per profile through anykernel/build.sh.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Selector contract.
[[ "$(bash "$ROOT/scripts/select_anykernel_profile.sh" lavender 4.4.356)" == "$ROOT/anykernel/profiles/lavender-4.4.conf" ]] || fail "selector lavender 4.4"
[[ "$(bash "$ROOT/scripts/select_anykernel_profile.sh" lavender 4.19.325)" == "$ROOT/anykernel/profiles/lavender-4.19.conf" ]] || fail "selector lavender 4.19"
[[ "$(bash "$ROOT/scripts/select_anykernel_profile.sh" garnet 5.10.160)" == "$ROOT/anykernel/profiles/garnet-gki.conf" ]] || fail "selector garnet 5.10"
echo "PASS AnyKernel selector"

first_image() { sed -n 's/^KERNEL_IMAGES="\(.*\)"/\1/p' "$1" | awk '{print $1}'; }

for profile_conf in "$ROOT"/anykernel/profiles/*.conf; do
  profile="$(basename "$profile_conf" .conf)"
  image="$(first_image "$profile_conf")"
  for variant in vanilla kernelsu kernelsu-next resukisu sukisu-ultra; do
    dir="$TMP/render-$profile-$variant"
    mkdir -p "$dir/profiles" "$dir/tools"
    cp -a "$ROOT"/anykernel/{anykernel.sh,banner,ci-patch.sh,version.conf} "$dir/"
    cp -a "$profile_conf" "$dir/profiles/"
    printf 'fake kernel payload' > "$dir/$image"
    KERNEL_NAME='Zai&<ren>' bash "$dir/ci-patch.sh" --profile "$profile" --variant "$variant" --dir "$dir" >/dev/null
    # @RT_ANDROID@/@RT_ROM@ are resolved on the device by update-binary, everything else must be rendered.
    ! grep -hE '@[A-Z_]+@' "$dir/anykernel.sh" "$dir/banner" | grep -vE '@RT_(ANDROID|ROM)@' | grep -q . || fail "unresolved placeholder: $profile/$variant"
    grep -q '@RT_ANDROID@' "$dir/banner" && grep -q '@RT_ROM@' "$dir/banner" || fail "runtime tokens missing from banner: $profile/$variant"
    ! awk 'length($0) > 46 { bad = 1 } END { exit !bad }' "$dir/banner" || fail "banner line wider than 46 columns: $profile/$variant"
    grep -qF 'Zai&<ren>' "$dir/banner" || fail "'&' in values must render literally ($profile/$variant)"
    bash -n "$dir/anykernel.sh" || fail "rendered anykernel.sh syntax: $profile/$variant"
  done
  echo "PASS render $profile x 5 variants"

  pkg="$TMP/pkg-$profile"
  mkdir -p "$pkg"
  cp -a "$ROOT/anykernel/." "$pkg/"
  rm -rf "$pkg/images" "$pkg/out"
  if (cd "$pkg" && OUT="$pkg/out" bash ./build.sh "$profile" vanilla >/dev/null 2>&1); then
    fail "packager must refuse to build without a kernel image ($profile)"
  fi
  for variant in vanilla sukisu-ultra; do
    mkdir -p "$pkg/images/$variant"
    printf 'fake kernel payload' > "$pkg/images/$variant/$image"
  done
  (cd "$pkg" && OUT="$pkg/out" bash ./build.sh "$profile" vanilla sukisu-ultra >/dev/null)
  mapfile -t zips < <(find "$pkg/out" -name '*.zip' | sort)
  ((${#zips[@]} == 2)) || fail "expected 2 packages for $profile, got ${#zips[@]}"
  for zip in "${zips[@]}"; do
    unzip -tq "$zip" >/dev/null
    unzip -p "$zip" anykernel.sh | bash -n
    listing="$(unzip -l "$zip")"
    grep -q "tools/ak3-core.sh" <<<"$listing" || fail "$zip lacks tools/ak3-core.sh"
    grep -q "META-INF/com/google/android/update-binary" <<<"$listing" || fail "$zip lacks update-binary"
  done
  echo "PASS package $profile (fail-closed + vanilla/sukisu-ultra)"
done
