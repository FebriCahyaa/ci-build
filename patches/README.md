# CI-Build Patch Registry

The patch registry is intentionally outside `scripts/build_kernel.sh`.

## Layout

```text
patches/
├── devices/
│   └── lavender/
│       └── 4.19/
├── root-manager/
│   ├── kernelsu/
│   │   └── 4.19/
│   ├── kernelsu-next/
│   │   └── 4.19/
│   └── resukisu/
│       └── 4.19/
├── upstream/
│   ├── codelinaro/
│   │   └── sdm660-4.19/
│   └── linux-stable/
│       └── 4.19/
└── features/
    └── lto-plus/
        └── lavender-4.19/
```

`*.patch` files are source patches and are applied with `git apply`.

`*.config` files are optional Kconfig fragments and are merged into the
generated `.config` during the config phase.

Every patch is idempotent: the patch runner reports `ALREADY APPLIED` and
continues when the reverse patch matches the source.

## Selection policy

For `PATCH_PROFILE=auto` the builder selects the device profile from
`DEVICE` + kernel major/minor.

Root-manager patches are selected only when `KSU_REQUIRED=true` and a
recognized `KSU_PROVIDER` is active.

The CodeLinaro set is enabled for the Lavender 4.19 profile. The current
Lavender branch already contains the enclosing CodeLinaro merge, so those
atomic patches normally show as `ALREADY APPLIED`.

LTO+ is optional and disabled by default. Enable it with:

```bash
LTO_PLUS=true
```

The current Lavender 4.19 tree already has `CONFIG_LTO_CLANG=y` and
declares `ARCH_SUPPORTS_THINLTO`; the optional profile only adds
`CONFIG_THINLTO=y`. This is deliberately not forced by default.
