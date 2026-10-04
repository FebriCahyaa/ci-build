# KernelSU-Next / Linux 4.4

`lavender-4.4` pins KernelSU-Next `v1.1.1` (`KSU_NEXT_44_REF`). That release
builds unmodified against the Nexus lavender 4.4 tree with
`CONFIG_KSU_KPROBES_HOOK=y`, so no provider patch is registered here.

The previous `0001-linux-4.4-compat.patch` targeted the v3.x layout
(`kernel/Kbuild`, `kernel/hook/...`) and could never apply to `v1.1.1`; applied
to v3.4.0 it still left 149 compile errors, so it was removed.

Note: the Nexus tree already calls the old KernelSU manual hooks in `fs/*.c`;
with kprobes enabled both paths are active. They are idempotent for the su
path translation, but verify on device after provider upgrades.
