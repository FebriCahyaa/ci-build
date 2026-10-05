# SukiSU Ultra provider integration

Upstream: https://github.com/SukiSU-Ultra/SukiSU-Ultra (branch `main`)

Supported on Linux 4.19 (`CONFIG_KSU_MANUAL_SU=y`) and 5.10 GKI. Upstream
`main` has no manual-hook mode (`KSU` depends on `KPROBES`), and kprobe hooks
are reported to bootloop on the SouthWest-NG Clang CFI + LTO tree, so
`lavender-4.19` builds it only when requested explicitly; ReSukiSU is the
SukiSU-family provider with manual hooks there. Linux 4.4 is
rejected by `root_manager_apply.sh` before cloning: both `main` (180 errors)
and the last flat-layout release `v3.2.0` (63 errors) fail to compile against
the lavender 4.4 tree (`selinux_state`, `linux/sched/*.h`,
`linux/compiler_types.h`, ...). `ALLOW_UNSUPPORTED_PROVIDER=true` bypasses the
gate for porting work.
