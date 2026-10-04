# Lavender 4.19 LTO+

Verified source support:

- `CONFIG_LTO_CLANG` exists in the build system.
- `CONFIG_LTO_CLANG=y` is already enabled in `vendor/xiaomi/sdm660_defconfig`.
- `ARCH_SUPPORTS_THINLTO` is selected by `arch/arm64/Kconfig`.
- The top-level Makefile contains the ThinLTO implementation.

This optional profile enables ThinLTO only. CFI is intentionally not
forced because the current Lavender device config does not establish a
clean CFI build baseline.

Enable with `LTO_PLUS=true`.