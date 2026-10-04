# KernelSU-Next 4.19 compatibility

KernelSU-Next v3.4.0 is used for Linux 4.19+. This directory contains only
provider-side compatibility patches for legacy VFS layouts.

`0002-file-wrapper-linux-4.19-compat.patch` is generated against the exact
KernelSU-Next v3.4.0 `kernel/infra/file_wrapper.c` revision used by the
provider and adapts it to Linux 4.19 without emulating newer VFS operations:

- `iopoll` integration is fenced to kernels `>= 5.1`.
- `remap_file_range` / `REMAP_FILE_DEDUP` integration is fenced to kernels
  `>= 4.20`.
- Linux 4.19 leaves the newer remap callback unset instead of inventing an
  incompatible VFS callback ABI.
- The patch does not modify the provider's upstream `struct file_operations`.

The patch is applied to the isolated KernelSU-Next provider checkout by
`scripts/root_manager_apply.sh`; the upstream provider gitlink is not modified.
