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
  - official KernelSU 4.19 + SUSFS: supported using official KSU v0.9.5
  - KernelSU-Next 4.19 + external SUSFS 1.5.5 patch set: blocked because
    the upstream 4.19 SUSFS patch set is based on official KernelSU and
    does not constitute a verified KSU-Next patch.
  - ReSukiSU + SUSFS: supported through ReSukiSU's integrated SUSFS
    inline-hook path; no foreign SUSFS patch is mixed into ReSukiSU.
