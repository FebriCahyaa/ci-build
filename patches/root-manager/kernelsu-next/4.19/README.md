# KernelSU-Next 4.19 compatibility

KernelSU-Next v3.4.0 is used for Linux 4.19+. This directory contains only provider-side compatibility patches for legacy VFS layouts.

`0002-file-wrapper-linux-4.19-compat.patch` adapts the v3.4.0 file wrapper to the Linux 4.19 `struct file_operations` layout:

- `iopoll` is fenced to mainline >= 5.1.
- `remap_file_range` is fenced to mainline >= 4.20.
- Linux 4.19 keeps the native `clone_file_range` and `dedupe_file_range` callbacks.

The patch is applied to the isolated KernelSU-Next provider checkout by `scripts/root_manager_apply.sh`; the upstream provider gitlink is not modified.
