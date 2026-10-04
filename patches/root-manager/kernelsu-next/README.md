# KernelSU-Next provider integration

Upstream source: https://github.com/KernelSU-Next/KernelSU-Next
Tracked submodule branch: `dev`

For Linux 4.4 non-GKI, `4.4/series.conf` applies a provider-local compatibility
layer for missing pre-4.12 APIs (`*_nofault`, `kvmalloc`/`kvfree`, legacy
`refcount_t`, and the pre-P4D ARM64 page-table walk). The patch is applied to
an isolated checkout, never to the parent submodule working tree.
