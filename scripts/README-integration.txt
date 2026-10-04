# Zairenkai integration notes

The canonical integration path is:

1. Resolve `BUILD_PROFILE` with `scripts/resolve_build_profile.sh`.
2. Build one root variant with `scripts/build_kernel.sh`, or all release variants with `scripts/build_variants.sh`.
3. Package AnyKernel3 through `scripts/build_anykernel.sh` using `anykernel/profiles/`.
4. Render the release changelog with `scripts/generate_changelog.sh`.
5. Publish the assets with `scripts/publish_ci_release.sh`.

`render_banner.sh` is retained as a compatibility helper and now uses the same
AnyKernel template renderer instead of a second banner-template directory.
