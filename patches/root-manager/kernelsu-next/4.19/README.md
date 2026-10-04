# KernelSU-Next / Linux 4.19

CI integrates the official KernelSU-Next repository through its upstream
setup layout and resolves `KSU_REF=auto` to pinned `v3.4.0` for Linux 4.19.

The Linux 4.19 profile intentionally uses the same KernelSU-Next `v3.4.0`
line used by the GKI profile. Linux 4.4 remains pinned separately to `v1.1.1`
because its provider-local compatibility patch targets that older API surface.

The 4.19 configuration enables `CONFIG_MODULES`, `CONFIG_KPROBES`,
`CONFIG_KPROBE_EVENTS`, and `CONFIG_KSU`; no provider patch series is required
for 4.19 at this stage. The provider is still copied into an isolated checkout
so the parent submodule remains clean.
