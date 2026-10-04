# SUSFS 4.4 configuration surface

This fragment mirrors the SUSFS v2.3.0 symbols enabled by the 4.4 path in
`Lokitla/NonGKI_Kernel_Build_2nd`. It is applied only after the dedicated
`Patches/Patch/susfs_patch_to_4.4.patch` has passed strict `git apply --check`.

The current `lavender-4.4` Nexus tree does not match every upstream patch
base blob, so this feature is intentionally opt-in and does not use fuzzy
patching.
