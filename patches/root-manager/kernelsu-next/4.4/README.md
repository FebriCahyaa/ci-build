# KernelSU-Next Linux 4.4 compatibility policy

`lavender-4.4` intentionally remains on the separately pinned `v1.1.1` provider
ref while the v3.4.0 source is used for all 4.19+ profiles. KernelSU-Next
currently advertises support down to Linux 4.4, but the current v3.4.0 tree has
substantially newer kernel API usage; the small compatibility patch below was
written and previously validated for the older 4.4 provider snapshot, so treating
it as a v3.4.0 compatibility proof would be unsafe without a fresh 4.4 compile.

`0001-linux-4.4-compat.patch` is provider-local and does not modify the host
kernel tree. It covers nofault user/kernel copies, `refcount_t`,
`kvmalloc`/`kvfree`, `MODULE_IMPORT_NS`, and the pre-P4D ARM64 page-table walk
needed by the pinned 4.4 source.

The 4.4 ref is separately overridable with `KSU_NEXT_44_REF`; once a complete
v3.4.0-on-4.4 compatibility layer is validated, the profile can be advanced
without changing the 4.19+/GKI policy.
