# Lavender 4.4 NonGKI integration

This profile integrates the NonGKI hook layer from `Lokitla/NonGKI_Kernel_Build_2nd`.

The CI intentionally pins the upstream repository to commit
`ab5b09509bcdf7a077468b0ab30bfe3cc86a0c77` and verifies the downloaded hook
script against its Git blob SHA before execution.

For `lavender-4.4` root variants:

- `ENABLE_SUSFS=false` -> `syscall_hook_patches.sh`
- `ENABLE_SUSFS=true` -> `susfs_inline_hook_patches.sh`, after the dedicated
  SUSFS 4.4 source patch succeeds

The upstream repository states that both hook scripts are tested for Linux
4.4. The dedicated `susfs_patch_to_4.4.patch` is tracked separately because
vendor trees can diverge from the patch's exact base blobs; this CI therefore
refuses to apply it fuzzily.
