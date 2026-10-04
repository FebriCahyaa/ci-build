# KernelSU-Next 4.19 compatibility

KernelSU-Next v3.4.0 is used for Linux 4.19+. This directory contains only
provider-side compatibility patches for legacy VFS layouts.

`0003-seccomp-cache-linux-4.19-compat.patch` restores the missing
`SECCOMP_ARCH_NATIVE_NR` architecture contract expected by the v3.4.0
seccomp cache by mapping it to the kernel's existing `NR_syscalls` value.
This is provider-local and does not modify the host kernel's seccomp headers.

`0002-file-wrapper-linux-4.19-compat.patch` is generated against the exact
KernelSU-Next v3.4.0 (`1a879d6a866f80b1fa1c1009a2ffa747873cbb5e`) `kernel/infra/file_wrapper.c`
revision used by the provider and adapts it to Linux 4.19:

- `iopoll` is fenced to kernels `>= 5.1`.
- `remap_file_range` / `REMAP_FILE_DEDUP` is fenced to kernels `>= 4.20`.
- Linux 4.19 forwards its native `clone_file_range` and `dedupe_file_range`
  callbacks through provider-local wrappers.
- No newer VFS callback ABI is exposed on Linux 4.19.
- The patch does not modify the provider's upstream `struct file_operations`.

The patch is applied to the isolated KernelSU-Next provider checkout by
`scripts/root_manager_apply.sh`; the upstream provider gitlink is not modified.
