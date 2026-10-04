#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
check(){ grep -qE "$2" "$1" && echo "PASS: $3" || { echo "FAIL: $3" >&2; fail=1; }; }

SERIES="$ROOT/patches/root-manager/resukisu/4.19/host-series.conf"
RDIR="$ROOT/patches/root-manager/resukisu/4.19"
NDIR="$ROOT/patches/root-manager/kernelsu-next/4.19"

expected_series=$(cat <<'EOF_SERIES'
0001-selinux-static-export.patch
0002-manual-execve-hook.patch
0003-manual-faccessat-hook.patch
0004-manual-stat-hook.patch
0005-manual-reboot-hook.patch
EOF_SERIES
)
actual_series="$(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$SERIES")"
[[ "$actual_series" == "$expected_series" ]] && echo 'PASS: ReSukiSU 4.19 host patch series' || { echo 'FAIL: ReSukiSU 4.19 patch series' >&2; fail=1; }

check "$RDIR/config.fragment" '^CONFIG_KSU=y$' 'ReSukiSU 4.19 KSU enabled'
check "$RDIR/config.fragment" '^CONFIG_KSU_MANUAL_HOOK=y$' 'ReSukiSU 4.19 Manual Hook selected'
check "$RDIR/config.fragment" '^CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y$' 'ReSukiSU 4.19 LSM setuid hook enabled'
check "$RDIR/config.fragment" '^CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y$' 'ReSukiSU 4.19 LSM initrc hook enabled'
check "$RDIR/config.fragment" '^CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y$' 'ReSukiSU 4.19 input handler hook enabled'

check "$RDIR/0001-selinux-static-export.patch" 'sel_handle_status_ops = \{' 'SELinux status ops export patch'
check "$RDIR/0001-selinux-static-export.patch" 'ssize_t \(\*const write_op\[\]\)' 'SELinux write_op export patch'
check "$RDIR/0002-manual-execve-hook.patch" 'ksu_handle_execveat' 'execve manual hook'
check "$RDIR/0003-manual-faccessat-hook.patch" 'ksu_handle_faccessat' 'faccessat manual hook'
check "$RDIR/0004-manual-stat-hook.patch" 'ksu_handle_stat' 'stat manual hook'
check "$RDIR/0004-manual-stat-hook.patch" 'ksu_handle_newfstat_ret' 'newfstat return hook'
check "$RDIR/0004-manual-stat-hook.patch" 'ksu_handle_fstat64_ret' 'fstat64 return hook'
check "$RDIR/0005-manual-reboot-hook.patch" 'ksu_handle_sys_reboot' 'reboot manual hook'

! grep -RInE 'ksu_vfs_read_hook|ksu_input_hook' "$RDIR"/*.patch && echo 'PASS: obsolete hook shapes removed' || { echo 'FAIL: obsolete hook shapes remain' >&2; fail=1; }
check "$ROOT/scripts/apply_susfs.sh" 'ReSukiSU Lavender 4\.19 uses the validated Manual Hook profile' 'ReSukiSU 4.19 rejects incompatible external SUSFS mode'

check "$NDIR/config.fragment" '^CONFIG_MODULES=y$' 'KernelSU-Next 4.19 enables module dependency for KPROBES'
check "$NDIR/config.fragment" '^CONFIG_KPROBES=y$' 'KernelSU-Next 4.19 KPROBES enabled'
check "$NDIR/config.fragment" '^CONFIG_KPROBE_EVENTS=y$' 'KernelSU-Next 4.19 KPROBE_EVENTS enabled'
check "$NDIR/config.fragment" '^CONFIG_KSU=y$' 'KernelSU-Next 4.19 KSU enabled'
! grep -q '^CONFIG_HAVE_KPROBES=' "$NDIR/config.fragment" && echo 'PASS: hidden HAVE_KPROBES symbol is not force-set' || { echo 'FAIL: CONFIG_HAVE_KPROBES force-set' >&2; fail=1; }

# Remote applicability against the real SouthWest-NG tree lives in
# tests/root_manager_remote_test.sh.

exit "$fail"
