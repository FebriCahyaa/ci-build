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
│   └── config.fragment                           → .config (config phase)
├── upstream/<source>/<mm>/series.conf            upstream backports (UPSTREAM_PROFILE)
└── features/
    ├── tweaks/{balanced,performance}/<mm>.config TWEAKS=balanced|performance
    ├── susfs/kernel-<mm>/config.fragment         ENABLE_SUSFS=true
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

Linux 4.19 uses `simonpunk/susfs4ksu` at `001e69919c6271f690fd00b17e4c721c9e599152`
(official KernelSU only; KernelSU-Next and ReSukiSU manual-hook profiles are
blocked). Linux 4.4 uses the blob-verified NonGKI `susfs_patch_to_4.4.patch`.
Both use strict `git apply --check`; no fuzzy application.
