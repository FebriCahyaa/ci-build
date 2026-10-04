# KernelSU-Next provider integration

Upstream: https://github.com/KernelSU-Next/KernelSU-Next (submodule branch `dev`)

| Kernel | Ref | Notes |
|---|---|---|
| 4.4 | `v1.1.1` | Compiles unmodified on the Nexus lavender tree (kprobes hook mode). |
| 4.19 | `v3.4.0` (`1a879d6a`) | `provider-series.conf`: file-wrapper VFS compat; `host-series.conf`: `path_umount()` backport. |
| 5.10 GKI | `v3.4.0` | No patches. |

The v3.x code base does not compile on Linux 4.4 (LSM hlist API, sched headers,
`syscall_fn_t`, ... — 149 errors on lavender 4.4), so 4.4 stays on `v1.1.1`
until a full backport exists. `v3.4.0` is verified to resolve to `1a879d6a`
before any provider patch is applied.
