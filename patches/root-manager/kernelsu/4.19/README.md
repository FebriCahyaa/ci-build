# KernelSU / Linux 4.19

For Linux 4.19, the official KernelSU project documents v0.9.5 as the
last supported non-GKI release. CI therefore resolves `KSU_REF=auto` to
`v0.9.5` and rejects newer official KernelSU refs for this kernel family.

The provider is integrated using the same `drivers/kernelsu` symlink,
`drivers/Makefile`, and `drivers/Kconfig` layout used by upstream
`kernel/setup.sh`.

With SUSFS enabled, CI applies the upstream SUSFS `kernel-4.19` patch set
pinned to its latest compatible revision.