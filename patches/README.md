# CI-Build Patch Registry

The patch registry is intentionally outside `scripts/build_kernel.sh`.

## Layout

```text
patches/
├── devices/
│   ├── lavender/
│   │   └── 4.19/
│   └── southwest-ng/
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

For `PATCH_PROFILE=none`, no device source patch is applied. This is the default
for the Southwest-NG source because its Lavender device support is already in the
source tree. For `PATCH_PROFILE=auto` the builder selects a device profile from
`DEVICE` + kernel major/minor, except that the Southwest-NG source is recognized
and kept patch-free.

Root-manager patches are selected only when `KSU_REQUIRED=true` and a
recognized `KSU_PROVIDER` is active.

The CodeLinaro set remains available for legacy Lavender 4.19 builds. It is not
enabled by default for Southwest-NG; use an explicit upstream profile only after
verifying that the selected commits are absent from the source.

The explicit `southwest-ng` device profile contains the conservative
scheduler/performance patch pair validated against the SouthWest-NG source.
Select it with `PATCH_PROFILE=southwest-ng`; `PATCH_PROFILE=auto` remains
patch-free for this repository.

LTO+ is optional and disabled by default. Enable it with:

```bash
LTO_PLUS=true
```

The current Lavender 4.19 tree already has `CONFIG_LTO_CLANG=y` and
declares `ARCH_SUPPORTS_THINLTO`; the optional profile only adds
`CONFIG_THINLTO=y`. This is deliberately not forced by default.


## Root manager + SUSFS policy

Root providers are integrated through `scripts/root_manager_apply.sh` using
the upstream `drivers/kernelsu` integration layout.

Linux 4.19 pins official KernelSU to `v0.9.5`, the last official non-GKI
release. KernelSU-Next defaults to `v3.4.0`. ReSukiSU defaults to `main`.

SUSFS for Linux 4.19 uses upstream `simonpunk/susfs4ksu` revision
`001e69919c6271f690fd00b17e4c721c9e599152` (the dedicated `kernel-4.19` branch's latest compatible
revision). The CI applies it with strict `git apply --check` gates.

SUSFS + ReSukiSU uses ReSukiSU's integrated SUSFS hook instead of mixing
the official-KernelSU SUSFS patch set into another provider.

SUSFS + KernelSU-Next is intentionally blocked by the CI because the
available upstream 4.19 SUSFS patch set is based on official KernelSU and
is not a verified KernelSU-Next patch set.
