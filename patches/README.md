# CI-Build patch registry

Source patches are applied with `git apply` by `scripts/apply_patch_series.sh`
(host kernel tree) or `scripts/root_manager_apply.sh` (isolated provider tree).
Every `.patch` must be listed by a series file; `scripts/validate_patch_format.py`
rejects malformed hunks, missing entries and unreferenced (orphan) patches.

```text
patches/
├── devices/<device|profile>/<mm>/series.conf     device source patches (PATCH_PROFILE)
├── root-manager/<provider>/<mm|common>/
│   ├── provider-series.conf                      → isolated provider checkout
│   ├── host-series.conf                          → host kernel tree
│   ├── susfs-series.conf                         → host kernel tree, after host-series (ENABLE_SUSFS)
│   ├── config.fragment                           → .config (config phase)
│   └── susfs.fragment                            → .config after config.fragment (ENABLE_SUSFS)
├── upstream/<source>/<mm>/series.conf            upstream backports (UPSTREAM_PROFILE)
└── features/
    ├── tweaks/{balanced,performance}/<mm>.config TWEAKS=balanced|performance
    ├── susfs/kernel-4.19/config.fragment         ENABLE_SUSFS=true (official KernelSU)
    └── lto-plus/lavender-4.19/thinlto.config     LTO_PLUS=true
```

## Selection

* `PATCH_PROFILE=auto` applies `devices/<DEVICE>/<mm>`; the SouthWest-NG 4.19
  source is recognized and kept patch-free. `PATCH_PROFILE=southwest-ng`
  selects its scheduler/performance pair; `none` disables device patches.
* Root-manager host/provider series and fragments apply only for root variants.
* `UPSTREAM_PROFILE=auto` applies the CodeLinaro SDM660 set to non-SouthWest-NG
  lavender 4.19 trees only.
* Patches are idempotent: an already-present change is reported as
  `ALREADY APPLIED` (ancestor commit, reverse-apply, or content match).

## Kconfig fragments

Fragments are merged in order (LTO+, root manager, SUSFS, tweaks) and then
resolved by `olddefconfig`; `PHASE=verify` reports any requested value that
Kconfig dropped because of unmet dependencies.

## SUSFS

| Provider | Linux 4.19 | Linux 4.4 |
|---|---|---|
| ReSukiSU | SUSFS v2.2.0 backport (LavenderLabz `e4c673c9`): `root-manager/resukisu/4.19/susfs-series.conf` + `susfs.fragment` | blocked (no backport for the pre-integrated Nexus tree) |
| official KernelSU | `simonpunk/susfs4ksu` `001e6991` (SUSFS 1.5.5), applied by `apply_susfs.sh` | blocked (KernelSU itself unsupported) |
| KernelSU-Next | blocked (the legacy line has no SUSFS hook mode) | blocked |

All SUSFS sources are applied with strict `git apply --check`; no fuzzy
application. Blocked combinations fail in `root_manager_apply.sh` before any
clone.
