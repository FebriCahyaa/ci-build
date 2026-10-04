# KernelSU-Next / Linux 4.19

CI integrates the official KernelSU-Next repository through its upstream
setup layout and resolves `KSU_REF=auto` to the pinned legacy-compatible v1.1.1
release for this workflow.

The external SUSFS `kernel-4.19` patch set is intentionally not applied
to KernelSU-Next because that patch set is authored against official
KernelSU. CI fails closed rather than mixing unverified hook/API patches.