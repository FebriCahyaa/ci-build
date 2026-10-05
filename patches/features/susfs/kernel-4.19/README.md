# SUSFS / Linux 4.19

Upstream: https://gitlab.com/simonpunk/susfs4ksu
Compatibility branch: `kernel-4.19`
Pinned revision: `001e69919c6271f690fd00b17e4c721c9e599152`
SUSFS generation: 1.5.5

This is the latest upstream SUSFS revision exposed by the dedicated
`kernel-4.19` branch. Newer overall SUSFS 2.x revisions are maintained in
GKI branches and are not substituted into this non-GKI 4.19 patch path.

The CI applies the upstream files exactly:
  kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch
  kernel_patches/50_add_susfs_in_kernel-4.19.patch
  kernel_patches/fs/susfs.c
  kernel_patches/include/linux/susfs.h

The CI uses `git apply --check` first and aborts on a non-clean patch.
It never falls back to fuzzy/manual application.

Provider matrix:
  - official KernelSU 4.19 + SUSFS: this upstream 1.5.5 set, with official
    KernelSU v0.9.5.
  - ReSukiSU 4.19 + SUSFS: SUSFS v2.2.0 backport from the root-manager
    registry (`root-manager/resukisu/4.19/susfs-series.conf`), not this set.
  - KernelSU-Next: blocked; the legacy manual-hook line has no SUSFS mode.
