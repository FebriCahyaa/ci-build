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
      if SOURCE_DIR="$case_dir/host" WORK_DIR="$case_dir/work" KERNEL_VERSION="$PROFILE_KERNEL_FAMILY" \
          ROOT_MANAGER="$variant" KSU_REF=auto ROOT_MANAGER_SOURCE_MODE=clone \
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

# Host-kernel series against the real SouthWest-NG 4.19 tree (sparse checkout).
SW="$TMP/southwest-ng"
git clone --quiet --depth=1 --filter=blob:none --sparse --branch main \
  https://github.com/pix106/android_kernel_xiaomi_sdm660_southwest-ng.git "$SW"
git -C "$SW" sparse-checkout set --no-cone \
  /fs/exec.c /fs/open.c /fs/stat.c /fs/namespace.c /kernel/reboot.c \
  /security/selinux/selinuxfs.c /arch/Kconfig
for series in "$ROOT"/patches/root-manager/*/4.19/host-series.conf; do
  provider="$(basename "$(dirname "$(dirname "$series")")")"
  work="$TMP/host-$provider"
  rm -rf "$work"
  cp -a "$SW" "$work"
  while IFS= read -r patch; do
    if git -C "$work" apply --check --whitespace=nowarn "$(dirname "$series")/$patch"; then
      git -C "$work" apply --whitespace=nowarn "$(dirname "$series")/$patch"
      echo "PASS: $provider 4.19 host patch $patch applies to SouthWest-NG"
    else
      echo "FAIL: $provider 4.19 host patch $patch does not apply to SouthWest-NG" >&2
      fail=1
    fi
  done < <(read_series "$series")
done

# KernelSU-Next v3.4.0 on 4.19 depends on KPROBES, which depends on MODULES in
# this kernel generation; the 4.19 config fragment must keep both enabled.
grep -qE 'depends on MODULES' "$SW/arch/Kconfig" || { echo 'FAIL: target KPROBES MODULES dependency missing' >&2; fail=1; }
grep -q '^CONFIG_MODULES=y$' "$ROOT/patches/root-manager/kernelsu-next/4.19/config.fragment" ||
  { echo 'FAIL: KernelSU-Next 4.19 fragment must enable CONFIG_MODULES' >&2; fail=1; }

exit "$fail"
