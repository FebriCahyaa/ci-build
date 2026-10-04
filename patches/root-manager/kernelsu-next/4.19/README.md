# KernelSU-Next / Linux 4.19

CI integrates the upstream KernelSU-Next repository through its upstream
setup layout and resolves `KSU_REF=auto` to **v3.4.0** for Linux 4.19.
This is the current pinned KernelSU-Next release for all 4.19+/GKI profiles.

KernelSU-Next v3.4.0 expects `path_umount()`, an API added upstream in Linux
5.9. CI therefore applies the small host-kernel backport in
`host-series.conf` to the 4.19 source tree before the provider is built. This
is deliberately separate from the provider-local series so the upstream
KernelSU-Next checkout remains clean.

The external SUSFS `kernel-4.19` patch set is intentionally not applied to
KernelSU-Next because that patch set is authored against official KernelSU.
CI fails closed rather than mixing unverified hook/API patches.
