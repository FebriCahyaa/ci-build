# CI-Build Custom AnyKernel3 Profiles

This directory contains reusable, profile-driven AnyKernel3 packaging for the CI-Build kernel builder.

Supported profiles:

- `lavender-4.4`
- `lavender-4.19`
- `garnet-oss`
- `garnet-hyperos`

The repository intentionally does **not** vendor the AnyKernel3 backend binaries/scripts. `scripts/build_anykernel.sh` fetches the configured AnyKernel3 revision at packaging time, then overlays the selected profile, kernel image, DTBO (when present), modules (when enabled), banner, and build metadata.

## Profile selection

Use `ANYKERNEL_PROFILE=auto` to select from `DEVICE`, `KERNEL_VERSION`, and `ROM_FAMILY`:

- `lavender` + kernel `4.4.x` -> `lavender-4.4`
- `lavender` + kernel `4.19.x` -> `lavender-4.19`
- `garnet` + `ROM_FAMILY=hyperos` -> `garnet-hyperos`
- `garnet` + any other/OSS family -> `garnet-oss`

For deterministic builds, pin `ANYKERNEL3_REF` to an AnyKernel3 tag/commit instead of tracking `master`.

## Important

The profiles are packaging/install profiles, not a guarantee that a kernel is bootable on a target ROM. Before flashing, verify the exact device, boot image format, slot state, AVB/vbmeta behavior, rollback requirements, and kernel/DTBO compatibility for the ROM build being used.
