#!/usr/bin/env bash
# ReSukiSU on lavender: 4.19 manual hooks (LavenderLabz setup) + optional SUSFS
# v2.2.0 inline hooks, and 4.4 hooks adapted to the Nexus pre-integrated tree.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
R="$ROOT/patches/root-manager/resukisu"
fail=0
ok() { echo "PASS: $*"; }
bad() { echo "FAIL: $*" >&2; fail=1; }
has() { grep -qE -- "$2" "$1" && ok "$3" || bad "$3"; }

[[ "$(read_series "$R/4.19/host-series.conf")" == host-0001-manual-hooks.patch ]] && ok '4.19 host series' || bad '4.19 host series'
[[ "$(read_series "$R/4.19/susfs-series.conf")" == susfs-0101-susfs-v2.2.0-backport.patch ]] && ok '4.19 SUSFS series' || bad '4.19 SUSFS series'
[[ "$(read_series "$R/4.4/host-series.conf")" == host-0001-manual-hooks.patch ]] && ok '4.4 host series' || bad '4.4 host series'

h="$R/4.19/host-0001-manual-hooks.patch"
for sym in ksu_handle_execveat ksu_handle_faccessat ksu_handle_stat ksu_handle_newfstat_ret ksu_handle_fstat64_ret \
           ksu_handle_sys_reboot ksu_handle_sys_read ksu_handle_setresuid ksu_handle_input_handle_event; do
  has "$h" "^\+.*$sym\(" "4.19 hook $sym"
done
has "$h" '^\+extern __attribute__\(\(cold\)\) int ksu_handle_sys_read\(unsigned int fd,$' '4.19 sys_read uses the real ReSukiSU prototype'
has "$h" '^\+const struct file_operations sel_handle_status_ops = \{' '4.19 sel_handle_status_ops export'
has "$h" '^\+ssize_t \(\*const write_op\[\]\)' '4.19 write_op export'
# ReSukiSU's hook checks reject these words in the hooked files.
! grep -qwE 'ksu_vfs_read_hook|ksu_input_hook|ksu_init_rc_hook|ksu_execveat_hook' "$R"/4.19/*.patch "$R"/4.4/*.patch &&
  ok 'no hook names that ReSukiSU flags as incompatible' || bad 'ReSukiSU-incompatible hook names present'
# Manual mode must not reference the SUSFS-only static keys (undefined at link time).
awk '/^\+#elif defined\(CONFIG_KSU_MANUAL_HOOK\)/{m=1;next} /^\+#endif/{m=0} m&&/ksu_is_(input|init_rc)_hook_enabled/{bad=1} END{exit bad}' "$h" &&
  ok 'manual mode does not use SUSFS-only static keys' || bad 'manual mode references SUSFS-only static keys'

s="$R/4.19/susfs-0101-susfs-v2.2.0-backport.patch"
has "$s" '^\+#define SUSFS_VERSION "v2\.2\.0"$' 'SUSFS v2.2.0'
for f in fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h; do
  has "$s" "^\+\+\+ b/$f$" "SUSFS adds $f"
done
! grep -qE '^\+\+\+ b/fs/Kconfig$' "$s" && ok 'no duplicate SUSFS Kconfig menu' || bad 'SUSFS patch duplicates ReSukiSU Kconfig symbols'
has "$R/4.19/susfs.fragment" '^CONFIG_KSU_SUSFS=y$' 'SUSFS hook mode selected'
has "$R/4.19/susfs.fragment" '^# CONFIG_KSU_MANUAL_HOOK is not set$' 'manual hook mode deselected with SUSFS'
for f in 4.4 4.19; do
  has "$R/$f/config.fragment" '^CONFIG_KSU_MANUAL_HOOK=y$' "$f manual hook"
  for a in SETUID INITRC INPUT; do has "$R/$f/config.fragment" "^CONFIG_KSU_MANUAL_HOOK_AUTO_${a}_HOOK=y$" "$f auto $a hook"; done
done

h4="$R/4.4/host-0001-manual-hooks.patch"
has "$h4" '^\+.*ksu_handle_stat\(&dfd, &filename, &flag\)' '4.4 stat hook uses the 3-argument ABI'
has "$h4" '^-.*ksu_handle_vfs_read\(&file' '4.4 drops the vfs_read hook ReSukiSU does not provide'
for v in 'DEFINE_MUTEX\(sel_mutex\)' 'struct page \*selinux_status_page' 'DEFINE_MUTEX\(selinux_status_lock\)' 'DEFINE_RWLOCK\(policy_rwlock\)'; do
  has "$h4" "^\+$v;" "4.4 exports ${v//\\/}"
done

has "$ROOT/scripts/apply_patch_series.sh" 'susfs-series\.conf' 'source phase applies susfs-series.conf'
has "$ROOT/scripts/apply_patch_series.sh" 'root_file "\$ROOT_MANAGER" susfs\.fragment' 'config phase prefers the provider SUSFS fragment'
has "$ROOT/scripts/apply_susfs.sh" 'resukisu:4\.19' 'apply_susfs accepts ReSukiSU 4.19 via the registry'
[[ "$(normalize_variant resukisu+susfs)" == resukisu-susfs && "$(variant_provider resukisu-susfs)" == resukisu &&
   "$(variant_label resukisu-susfs)" == ReSukiSU-SUSFS ]] && variant_susfs resukisu-susfs && ! variant_susfs resukisu &&
  ok 'resukisu-susfs variant maps to provider resukisu + SUSFS' || bad 'resukisu-susfs variant mapping'
has "$ROOT/scripts/build_kernel.sh" 'ROOT_MANAGER="\$ROOT_PROVIDER"' 'build_kernel integrates the variant provider, not the variant id'
has "$ROOT/anykernel/ci-patch.sh" 'resukisu-susfs\)' 'AnyKernel templates know resukisu-susfs'
exit "$fail"
