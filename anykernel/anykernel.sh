### AnyKernel3 - Zairenkai templated installer
## Generated from anykernel/profiles by ci-patch.sh. Keep PLACEHOLDER tokens tokens intact in this template.

properties() { '
kernel.string=@KERNEL_STRING@
do.devicecheck=@DO_DEVICECHECK@
do.modules=@DO_MODULES@
do.systemless=@DO_SYSTEMLESS@
do.cleanup=1
do.cleanuponabort=0
@DEVICE_PROPS@
supported.versions=@SUPPORTED_VERSIONS@
supported.patchlevels=
supported.vendorpatchlevels=
'; }

boot_attributes() {
  set_perm_recursive 0 0 755 644 $RAMDISK/*;
  set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
}

BLOCK=@BLOCK@;
IS_SLOT_DEVICE=@IS_SLOT_DEVICE@;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# Zairenkai package metadata.
# Dynamic-partition support is a flash-target policy; boot itself remains a named physical partition.
# GKI packages intentionally replace only the kernel Image and leave vendor ramdisk/DTBO untouched.

. tools/ak3-core.sh;

# Split/repack is the safe default for both legacy and GKI boot images.
dump_boot;

# @FLASH_DTBO@ is rendered only when the profile explicitly permits DTBO replacement.
if [ "@FLASH_DTBO@" = "1" ] && [ -f "$AKHOME/dtbo.img" ]; then
  flash_dtbo;
fi;

write_boot;

# Keep this marker stable for diagnostics.
printf '%s\n' 'Zairenkai AnyKernel3: @BUILD_LABEL@ / @PROFILE_ID@ / @ROOT@';
