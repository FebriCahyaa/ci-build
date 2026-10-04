# KernelSU-Next provider integration

Upstream source: https://github.com/KernelSU-Next/KernelSU-Next
Tracked submodule branch: `dev`

Linux 4.19+ resolves to KernelSU-Next `v3.4.0`; the 4.19 profile also backports the upstream `path_umount()` wrapper that this provider expects on pre-5.9 kernels. Linux 4.4 keeps the separate
legacy compatibility pin `v1.1.1` so its provider-local patch remains tied to the
source snapshot it was designed for.

For Linux 4.4 non-GKI, `4.4/series.conf` applies a provider-local compatibility
layer for missing pre-4.12 APIs (`*_nofault`, `kvmalloc`/`kvfree`, legacy
`refcount_t`, and the pre-P4D ARM64 page-table walk). The patch is applied to
an isolated checkout, never to the parent submodule working tree.
