# SukiSU Ultra Linux 4.4 compatibility patch

`0001-linux-4.4-compat.patch` is a provider-local CI patch against the pinned
SukiSU Ultra source. It covers legacy nofault copies, `refcount_t`,
`kvmalloc`/`kvfree`, the pre-P4D ARM64 page-table walk, and the KPM
`set_memory.h` include path required by kernels below 4.19.

The patch is applied only to an isolated provider checkout; the Git submodule
itself remains clean. Revalidate it whenever the tracked SukiSU Ultra submodule
moves to a new upstream commit.
