# ReSukiSU provider integration

Upstream: https://github.com/ReSukiSU/ReSukiSU (pinned `v4.2.0-rc3`)

| Kernel | Hook mode | Host integration |
|---|---|---|
| 4.4 | manual | NonGKI syscall hook stage (`patches/upstream/lokitla-nongki/4.4`) |
| 4.19 | manual | `4.19/host-series.conf` (execve, faccessat, stat/newfstat/fstat64, reboot, SELinux exports) |
| 5.10 GKI | tracepoint | none |

On the KernelSU-preintegrated Nexus 4.4 tree the existing `fs/stat.c` hook
lacks `ksu_handle_newfstat_ret`/`ksu_handle_fstat64_ret`, which ReSukiSU's
`manual_hook_check.mk` requires; port those hooks before expecting a 4.4
ReSukiSU build to pass.
