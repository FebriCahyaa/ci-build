# ReSukiSU / Lavender 4.19

ReSukiSU + SUSFS is the root-manager path used by the current Lavender
build configuration.

The current source exposes the handler calls expected by ReSukiSU, but
the tree still carries two legacy boolean guards and uses static SELinux
file-operation objects. The following patches provide the narrow 4.19
compatibility changes required by the current ReSukiSU SUSFS checks:

1. SELinux static exports
2. `ksu_vfs_read_hook` legacy guard removal
3. `ksu_input_hook` legacy guard removal
4. C90-safe `ksu_handle_setresuid` insertion
5. Restore the missing SUSFS process-state helpers and deferred work item
   required by the current ReSukiSU provider on this 4.19 tree

These patches are narrow and only alter the ephemeral CI kernel checkout.