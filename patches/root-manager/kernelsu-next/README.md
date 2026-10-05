# KernelSU-Next provider integration

Upstream: https://github.com/KernelSU-Next/KernelSU-Next

| Kernel | Ref (pinned commit) | Hook mode | Registry |
|---|---|---|---|
| 4.4 (Nexus lavender) | `v3.4.0-legacy` (`8af3d4fe`) | manual | provider: Kbuild verify + 4.4 compat layer; host: VFS/seccomp/SELinux backports + hook upgrade |
| 4.19 (SouthWest-NG) | `v3.4.0-legacy` (`8af3d4fe`) | manual | provider: Kbuild verify; host: VFS/seccomp backports + manual hooks |
| 5.10 GKI | `v3.4.0` (`1a879d6a`) | kprobes | none |

Non-GKI kernels use the **legacy** line (`v3.x-legacy` tags / `legacy`
branch), the one KernelSU-Next maintains for `CONFIG_KSU_MANUAL_HOOK`.
The mainline `v3.x` tags rely on kprobe/syscall-table hooks, which bootloop on
the SouthWest-NG Clang CFI + LTO tree and do not compile on 4.4;
`root_manager_apply.sh` refuses a non-legacy ref below 5.10 unless
`ALLOW_UNSUPPORTED_PROVIDER=true`.

Files:

```text
common/provider-0001-kbuild-verify-host-backports.patch  provider: Kbuild checks host backports instead of sed-editing the host tree
4.4/provider-0002-linux-4.4-compat.patch                provider: <4.11 shims, kernel_read/write compat, full_name_hash, copy_to_iter
4.4/host-0001-vfs-seccomp-selinux-backports.patch       host: path_umount, seccomp filter_count, selinux_cred/selinux_inode
4.4/host-0002-manual-hooks.patch                        host: upgrade Nexus hooks (stat ABI, newfstat/fstat64, reboot, input, avc)
4.19/host-0001-vfs-seccomp-backports.patch              host: path_umount, seccomp filter_count
4.19/host-0002-manual-hooks.patch                       host: exec, faccessat, vfs_read, stat, newfstat/fstat64, reboot, input, avc
```

Verification: full pipeline builds (`build_variants.sh`, AnyKernel ZIP
included) pass on 4.4 (AOSP clang r365631c) and on 4.19 with the tree's full
LTO + CFI (clang r416183b); the manager-visible version is 33294.

Sources the hook layer was adapted from:
stanley0010/KSU-Next-Kernel-for-LineageOS-24-for-Redmi-Note-7-lavender
(`c083ee15`, `e4fd8a63`), rianrizkifauzi/C9-Kernel_xiaomi_lavender_44, and
maxsteeel/KernelSU-Next (`e7c5df60`, `ae334326` — the legacy compat work that
upstream merged into the `legacy` branch).
