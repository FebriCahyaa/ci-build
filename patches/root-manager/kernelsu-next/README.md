# KernelSU-Next provider integration

Upstream source: https://github.com/KernelSU-Next/KernelSU-Next
Tracked submodule branch: `dev`

For Linux 4.4 non-GKI, the profile pins KernelSU-Next to `v1.1.1` because
the existing 4.4 compatibility layer is authored and validated for that API
surface. Linux 4.19 legacy builds use `v3.4.0`; GKI 5.10+ builds also use
`v3.4.0`.

For Linux 4.4 non-GKI, `4.4/series.conf` applies a provider-local compatibility
layer for missing pre-4.12 APIs (`*_nofault`, `kvmalloc`/`kvfree`, legacy
`refcount_t`, and the pre-P4D ARM64 page-table walk). The patch is applied to
an isolated checkout, never to the parent submodule working tree.
