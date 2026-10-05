#!/usr/bin/env bash
# Network test: resolve every (profile x default root variant) exactly as a CI
# build does and run scripts/root_manager_apply.sh against the real upstream
# provider source, then apply every host-kernel series to the real kernel tree.
#
# This is the guard that catches a provider patch written for a different
# provider ref than the one the profile pins (e.g. a v3.x-layout patch with a
# v1.x pin), which static contract tests cannot detect.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

fake_host_tree() {
  local dir="$1"
  mkdir -p "$dir/drivers"
  printf 'obj-y += base/\n' > "$dir/drivers/Makefile"
  printf 'menu "Device Drivers"\nsource "drivers/base/Kconfig"\nendmenu\n' > "$dir/drivers/Kconfig"
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.name=ci -c user.email=ci@example.invalid commit -qm host
}

for profile_file in "$ROOT"/profiles/targets/*.conf; do
  profile="$(basename "$profile_file" .conf)"
  (
    load_profile "$profile"
    mapfile -t variants < <(expand_variants default "$PROFILE_DEFAULT_VARIANTS")
    for variant in "${variants[@]}"; do
      [[ "$variant" == vanilla ]] && continue
      case_dir="$TMP/$profile-$variant"
      fake_host_tree "$case_dir/host"
      susfs=false; variant_susfs "$variant" && susfs=true
      if SOURCE_DIR="$case_dir/host" WORK_DIR="$case_dir/work" KERNEL_VERSION="$PROFILE_KERNEL_FAMILY" \
          ROOT_MANAGER="$(variant_provider "$variant")" ENABLE_SUSFS="$susfs" KSU_REF=auto ROOT_MANAGER_SOURCE_MODE=clone \
          KSU_NEXT_44_REF="$PROFILE_KSU_NEXT_44_REF" KSU_NEXT_LEGACY_REF="$PROFILE_KSU_NEXT_LEGACY_REF" \
          KSU_NEXT_GKI_REF="$PROFILE_KSU_NEXT_GKI_REF" RESUKISU_REF_DEFAULT="$PROFILE_RESUKISU_REF" \
          SUKISU_ULTRA_REF_DEFAULT="$PROFILE_SUKISU_ULTRA_REF" \
          bash "$ROOT/scripts/root_manager_apply.sh" > "$case_dir.log" 2>&1; then
        # shellcheck source=/dev/null
        source "$case_dir/work/root-manager.env"
        [[ -L "$case_dir/host/drivers/kernelsu" && -f "$case_dir/host/drivers/kernelsu/Kconfig" ]] ||
          { echo "FAIL: $profile/$variant drivers/kernelsu symlink is broken" >&2; exit 1; }
        echo "PASS: $profile/$variant -> $KSU_REF ($KSU_PROVIDER_COMMIT) patches=$ROOT_MANAGER_PATCHES_APPLIED"
      else
        echo "FAIL: $profile/$variant root-manager integration" >&2
        tail -n 15 "$case_dir.log" >&2
        exit 1
      fi
    done
  ) || fail=1
done

# Host-kernel series (host-series.conf, then susfs-series.conf) against the
# real kernel trees, sparse-checked-out to exactly the files the patches touch.
patched_paths() {
  local mm="$1" series patch
  for series in "$ROOT"/patches/root-manager/*/"$mm"/{host,susfs}-series.conf; do
    [[ -f "$series" ]] || continue
    while IFS= read -r patch; do
      sed -n 's|^diff --git a/\([^ ]*\) b/.*|/\1|p' "$(dirname "$series")/$patch"
    done < <(read_series "$series")
  done | sort -u
}

check_tree() {
  local mm="$1" url="$2" ref="$3" label="$4" tree="$TMP/tree-$1" series provider work patch
  git clone --quiet --depth=1 --filter=blob:none --sparse --branch "$ref" "$url" "$tree"
  mapfile -t paths < <(patched_paths "$mm")
  git -C "$tree" sparse-checkout set --no-cone "${paths[@]}"
  for series in "$ROOT"/patches/root-manager/*/"$mm"/host-series.conf; do
    provider="$(basename "$(dirname "$(dirname "$series")")")"
    work="$TMP/host-$provider-$mm"
    rm -rf "$work"
    cp -a "$tree" "$work"
    for s in "$series" "$(dirname "$series")/susfs-series.conf"; do
      [[ -f "$s" ]] || continue
      while IFS= read -r patch; do
        if git -C "$work" apply --check --whitespace=nowarn "$(dirname "$s")/$patch"; then
          git -C "$work" apply --whitespace=nowarn "$(dirname "$s")/$patch"
          echo "PASS: $provider $mm $(basename "$s") $patch applies to $label"
        else
          echo "FAIL: $provider $mm $(basename "$s") $patch does not apply to $label" >&2
          fail=1
        fi
      done < <(read_series "$s")
    done
  done
}

check_tree 4.19 https://github.com/pix106/android_kernel_xiaomi_sdm660_southwest-ng.git main "SouthWest-NG"
check_tree 4.4 https://github.com/projects-nexus/nexus_kernel_xiaomi_lavender.git 13 "Nexus lavender"

exit "$fail"
