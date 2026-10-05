# ReSukiSU provider integration

Upstream: https://github.com/ReSukiSU/ReSukiSU (pinned `v4.2.0-rc3`, `239e1e88`)

| Kernel | Hook mode | Registry |
|---|---|---|
| 4.4 (Nexus lavender) | manual | `4.4/host-series.conf`: adapt the tree's pre-integrated hooks (3-arg stat, newfstat/fstat64, reboot, SELinux static exports) |
| 4.19 (SouthWest-NG) | manual | `4.19/host-series.conf`: LavenderLabz manual hook setup |
| 4.19 + `ENABLE_SUSFS=true` | SUSFS inline | `4.19/susfs-series.conf` on top: SUSFS v2.2.0 backport; `4.19/susfs.fragment` |
| 5.10 GKI | tracepoint | none |

ReSukiSU checks every hook at compile time (`tools/manual_hook_check.mk`,
`tools/inline_hook_check.mk`, `tools/static_export_check.mk`), so a missing or
mismatched hook stops the build instead of producing a kernel without root.

## Linux 4.19

`host-0001-manual-hooks.patch` is LavenderLabz/kernel_xiaomi_sdm660
`5620850a` ported onto SouthWest-NG main with two fixes: the real
`ksu_handle_sys_read()` prototype, and no reference to the
`ksu_is_*_hook_enabled` static keys in manual mode (ReSukiSU defines them only
for `CONFIG_KSU_SUSFS`; the original commit fails to link in manual mode).
setuid, sys_read and input are also served by ReSukiSU's automatic hooks
(`CONFIG_KSU_MANUAL_HOOK_AUTO_*=y`); the host calls are no-ops then.

`susfs-0101-susfs-v2.2.0-backport.patch` is LavenderLabz `e4c673c9` (SUSFS
v2.2.0 for 4.19) on top of it, without the duplicate `fs/Kconfig` SUSFS menu.
With `ENABLE_SUSFS=true` the CI applies it after the host series and merges
`susfs.fragment` (`CONFIG_KSU_SUSFS=y` replaces `CONFIG_KSU_MANUAL_HOOK`).
The compile-time warnings "Detected KSU_MANUAL_HOOK guard" are expected: the
hook files carry both modes.

## Linux 4.4

The Nexus tree ships old KernelSU hooks; `host-0001-manual-hooks.patch` adapts
them to ReSukiSU's contract. SUSFS on 4.4 is not offered: no SUSFS backport
exists for this pre-integrated tree.

Verification: full pipeline builds (`build_variants.sh`, AnyKernel ZIP
included) pass for `resukisu` on 4.4 (AOSP clang r365631c) and for `resukisu`
and `resukisu-susfs` on 4.19 with the tree's full LTO + CFI (clang r416183b).
