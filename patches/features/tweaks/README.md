# Kernel tweaks (`TWEAKS=none|balanced|performance`)

Opt-in Kconfig tweaks merged in the config phase, after the defconfig and the
root-manager fragment, then resolved by `olddefconfig`. Every symbol is
validated against the real target trees (`tests/tweaks_kconfig_remote_test.sh`);
the build log reports which requested values survived dependency resolution.

| Level | Linux 4.4 (lavender) | Linux 4.19 (lavender) | Linux 5.10 GKI (garnet) |
|---|---|---|---|
| `balanced` | Westwood+ TCP, `fq`, deadline I/O, zram LZ4 | BBR + `fq` default qdisc, zram LZ4 | BBR (KMI-safe only) |
| `performance` | balanced + 300 Hz | balanced + 300 Hz | same as balanced |

GKI kernels only receive tweaks that cannot break the stock vendor modules
(no tick rate, scheduler or memory-model changes). `PATCH_PROFILE=southwest-ng`
sets 250 Hz in the defconfig; `TWEAKS=performance` intentionally overrides it.
