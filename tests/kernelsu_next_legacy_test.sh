#!/usr/bin/env bash
# KernelSU-Next on non-GKI lavender (4.4 / 4.19): legacy line + manual hooks.
# Static contract of the registry; compile/link verification is documented in
# patches/root-manager/kernelsu-next/README.md and the remote applicability
# check lives in tests/root_manager_remote_test.sh.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
R="$ROOT/patches/root-manager/kernelsu-next"
fail=0
ok() { echo "PASS: $*"; }
bad() { echo "FAIL: $*" >&2; fail=1; }
has() { grep -qE -- "$2" "$1" && ok "$3" || bad "$3"; }

series_is() { # <series> <expected entries...>
  local series="$1"; shift
  [[ "$(read_series "$series" | paste -sd' ')" == "$*" ]] && ok "$(basename "$(dirname "$series")")/$(basename "$series"): $*" ||
    bad "$series lists '$(read_series "$series" | paste -sd' ')', expected '$*'"
}

series_is "$R/4.4/provider-series.conf" ../common/provider-0001-kbuild-verify-host-backports.patch provider-0002-linux-4.4-compat.patch
series_is "$R/4.4/host-series.conf" host-0001-vfs-seccomp-selinux-backports.patch host-0002-manual-hooks.patch
series_is "$R/4.19/provider-series.conf" ../common/provider-0001-kbuild-verify-host-backports.patch
series_is "$R/4.19/host-series.conf" host-0001-vfs-seccomp-backports.patch host-0002-manual-hooks.patch

for mm in 4.4 4.19; do
  has "$R/$mm/config.fragment" '^CONFIG_KSU_MANUAL_HOOK=y$' "$mm fragment selects manual hooks"
  ! grep -qE '^CONFIG_(KPROBES|MODULES)=y$' "$R/$mm/config.fragment" && ok "$mm fragment does not force kprobes/modules" ||
    bad "$mm fragment must not force kprobes/modules (bootloop on CFI+LTO)"
  hooks="$R/$mm/host-0002-manual-hooks.patch"
  for sym in ksu_handle_stat ksu_handle_newfstat_ret ksu_handle_fstat64_ret ksu_handle_sys_reboot \
             ksu_handle_input_handle_event ksu_handle_slow_avc_audit ksu_handle_vfs_read; do
    has "$hooks" "^\+.*$sym\(" "$mm hook $sym"
  done
  has "$hooks" '^\+.*unlikely\(ksu_init_rc_hook\)' "$mm vfs_read hook is gated on ksu_init_rc_hook"
  has "$hooks" '^\+#ifdef CONFIG_KSU_MANUAL_HOOK$' "$mm hooks are compiled only with CONFIG_KSU_MANUAL_HOOK"
done
has "$R/4.19/host-0002-manual-hooks.patch" '^\+.*ksu_handle_execveat\(&fd, &filename' '4.19 execveat hook'
has "$R/4.19/host-0002-manual-hooks.patch" '^\+.*ksu_handle_faccessat\(&dfd, &filename' '4.19 faccessat hook'
has "$R/4.4/host-0002-manual-hooks.patch" '^\+.*ksu_handle_stat\(&dfd, &filename, &flag\)' '4.4 stat hook uses the 3-argument ABI'
has "$R/4.4/host-0001-vfs-seccomp-selinux-backports.patch" '^\+static inline struct task_security_struct \*selinux_cred' '4.4 selinux_cred accessor'

for mm in 4.4 4.19; do
  b="$(ls "$R/$mm"/host-0001-*.patch)"
  has "$b" '^\+int path_umount\(struct path \*path, int flags\)$' "$mm path_umount backport"
  has "$b" '^\+int path_umount\(struct path \*path, int flags\);$' "$mm path_umount prototype in fs/internal.h"
  has "$b" '^\+	atomic_t filter_count;$' "$mm struct seccomp filter_count"
done

kb="$R/common/provider-0001-kbuild-verify-host-backports.patch"
has "$kb" '^-\$\(shell sed -i' 'Kbuild no longer rewrites host sources'
has "$kb" '^\+\$\(eval \$\(call ksu_require_host,\^int path_umount' 'Kbuild verifies host backports'
compat="$R/4.4/provider-0002-linux-4.4-compat.patch"
for f in linux/sched/signal.h linux/sched/task.h linux/compiler_types.h; do
  has "$compat" "^\+\+\+ b/kernel/compat/linux-4.4/include/$f$" "4.4 shim $f"
done
! grep -qE '^\+.*[^_]kernel_(read|write)\(' "$compat" && ok '4.4 driver uses ksu_kernel_{read,write}_compat only' ||
  bad '4.4 compat patch adds direct kernel_read/kernel_write calls'

has "$ROOT/scripts/root_manager_apply.sh" 'KSU_NEXT_44_REF="\$\{KSU_NEXT_44_REF:-v3\.4\.0-legacy\}"' 'script default for 4.4 is v3.4.0-legacy'
has "$ROOT/scripts/root_manager_apply.sh" 'sukisu-ultra\|kernelsu-next\)' 'auto hook mode resolves to manual below 5.10'
exit "$fail"
