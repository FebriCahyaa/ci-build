# KernelSU-Next Linux 4.4 compatibility patch

`0001-linux-4.4-compat.patch` is a provider-local CI patch against the pinned
KernelSU-Next `v1.1.1` source. It does not modify the host kernel tree. The patch covers
legacy APIs used by the current provider source: nofault user/kernel copies,
`refcount_t`, `kvmalloc`/`kvfree`, `MODULE_IMPORT_NS`, and the pre-P4D ARM64
page-table walk.

The patch must be revalidated when the tracked KernelSU-Next submodule changes.
