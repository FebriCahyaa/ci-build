# SukiSU Ultra provider integration

Upstream source: https://github.com/SukiSU-Ultra/SukiSU-Ultra
Tracked branch: `main`

The CI uses the upstream `kernel/` tree through the standard `drivers/kernelsu`
layout. The full manager/application source remains in the upstream submodule.

For Linux 4.4 non-GKI, this harness uses `CONFIG_KSU_MANUAL_SU=y` plus a
provider-local compatibility patch. SukiSU Ultra's own legacy hook path is
used; the external ReSukiSU/NonGKI source-hook script is intentionally not
stacked on top of it. KPM/SUSFS is not enabled for the
4.4 SukiSU Ultra path because the supplied upstream Kconfig does not expose a
verified 4.4 `KSU_SUSFS` contract. The upstream documentation additionally
states that KPM on kernels below 4.19 needs a `set_memory.h` backport.

The 4.4 patch also provides a local `set_memory.h` compatibility shim for the optional KPM files.
