# Zairenkai / ZKFC — lavender 4.19

This feature integrates Zairenkai's Kernel Framework Core (ZKFC) into the
`pix106/android_kernel_xiaomi_sdm660_southwest-ng` Linux 4.19 tree.

The CI integration runs Zairenkai's `kernel/setup.sh` to wire `drivers/zkfc`,
then applies a small manual-hook patch to the host kernel. The patch includes
`include/linux/zkfc_hooks.h`, calls `ZKFC_HOOK_EXEC()` immediately before
`exec_binprm()`, and calls `ZKFC_HOOK_NEW_TASK()` at the beginning of
`wake_up_new_task()`.

The profile enables:

```text
CONFIG_ZKFC=y
CONFIG_ZKFC_HOOK_MANUAL=y
CONFIG_ZKFC_LICENSEE_TAG="zairenkai-sdm660-lavender"
```

The owner-issued `zkfc_license.inc` is optional for local builds and is injected
only through CI secrets for licensed builds. Runtime `.zkl` tokens and signing
material must never be committed or uploaded as artifacts.
