# Zairenkai CI-Build

Universal Android kernel CI for the Zairenkai targets. One shared `scripts/`
implementation drives GitHub Actions, Harness, and local builds.

| Profile | Kernel | Source | Default root variants |
|---|---|---|---|
| `lavender-4.4` | Linux 4.4 non-GKI, HMP/EAS | `projects-nexus/nexus_kernel_xiaomi_lavender@13` | vanilla, kernelsu-next, resukisu |
| `lavender-4.19` | Linux 4.19 non-GKI | `pix106/android_kernel_xiaomi_sdm660_southwest-ng@main` | vanilla, kernelsu-next, resukisu, resukisu-susfs |
| `garnet-gki` | Linux 5.10 GKI, A/B | `FebriCahyaa/kernel_xiaomi_garnet@garnet-t-oss` | vanilla, kernelsu-next, resukisu, sukisu-ultra |

Profiles live in `profiles/targets/`; AnyKernel flash metadata in
`anykernel/profiles/`. `VARIANTS=default` (or `all`) expands to the profile's
`PROFILE_DEFAULT_VARIANTS`; an explicit list is honoured as given.

## Repository layout

```text
.github/workflows/   kernel.yml (build), harness-kernel.yml (Harness bridge),
                     rom.yml (ROM), ci-validation.yml (tests)
harness/             Harness pipelines (kernel, ROM)
profiles/targets/    one file per target: source, defconfig, pins, default variants
patches/             patch registry (devices, root-manager, upstream, features)
anykernel/           vendored AnyKernel3 + templates (anykernel.sh, banner) + profiles
scripts/             build, release, Telegram, and helper scripts (entry points below)
scripts/lib/         shared shell library (common.sh)
tests/               test suite: bash tests/run_all.sh [--remote|--remote-only]
third_party/         root-manager submodules (optional source snapshots)
aws/                 ephemeral self-hosted runner for ROM builds
```

Entry points: `build_variants.sh` (matrix of variants from one source seed),
`build_kernel.sh` (one variant), `assemble_release_assets.sh` +
`publish_ci_release.sh` (release), `start_local_ci.sh` (trigger from a shell).

## Build flow

```text
profiles/targets/<target>.conf ─▶ resolve_build_profile.sh / resolve_variants.sh
                                              │
                         ┌────────────────────┴───────────────────┐
                  GitHub matrix (one job/variant)      Harness/local build_variants.sh
                         └────────────────────┬───────────────────┘
                                              ▼
build_kernel.sh: checkout ─▶ root_manager_apply.sh ─▶ apply_patch_series.sh (source)
  ─▶ toolchain_resolver.sh ─▶ defconfig + fragments + tweaks ─▶ compile
  ─▶ artifacts + changelog ─▶ build_anykernel.sh ─▶ release staging
```

## Running builds

GitHub: run **Build Kernel** (`kernel.yml`). Harness: run **Harness Kernel
Build** (`harness-kernel.yml`). From a shell with `gh` authenticated:

```bash
BUILD_PROFILE=lavender-4.19 VARIANTS=default TWEAKS=balanced ./scripts/start_local_ci.sh
TARGET=harness BUILD_PROFILE=garnet-gki ./scripts/start_local_ci.sh
```

Directly on a Linux host (same code path as Harness):

```bash
bash scripts/install_deps.sh
BUILD_PROFILE=lavender-4.4 ROOT_VARIANTS=vanilla,kernelsu-next bash scripts/build_variants.sh
```

Release creation is opt-in (`release` / `publish_release`). New tags are created
on the built commit. A release contains one kernel archive and one AnyKernel3
ZIP per completed variant, `CHANGELOG.md`, and `SHA256SUMS`; partial matrix
results keep completed variants and failure diagnostics.

## Toolchains

`toolchain` selects a family or a validated preset. Each preset fails fast on
kernel generations it is not known to build (`TOOLCHAIN_FORCE=true` overrides).

| `toolchain` | Compiler | Linux 4.4 | 4.19 | 5.10 GKI |
|---|---|:-:|:-:|:-:|
| `auto` | build.config AOSP clang, else per-kernel default | ✓ | ✓ | ✓ |
| `aosp` | AOSP prebuilt (`toolchain_version=clang-rXXXXXX`) | ✓ | ✓ | ✓ |
| `aosp-r416183b` | AOSP Clang 12 (LineageOS mirror) — GKI 5.10 reference | ✓ | ✓ | ✓ |
| `zyc-10` | ZyC Clang 10.0.1 | ✓ | ✓ | – |
| `proton` | Proton Clang 13 | – | ✓ | ✓ |
| `llvm-18` | LLVM 18.1.8 release | – | ✓ | ✓ |
| `neutron` | Neutron Clang (latest or tag), sha256-verified | – | ✓ | ✓ |
| `llvm` / `system` | distro clang | | | |
| `gcc` | distro GNU cross compiler | ✓ | | |

`toolchain_url` builds with a custom archive (clang, or GCC when
`toolchain=gcc`). Downloads are cached per profile/toolchain
(`actions/cache` on GitHub, shared by all variants of a Harness matrix).

## Tweaks

`tweaks=none|balanced|performance` merges validated Kconfig tweaks last in the
config phase; the build log reports which values survived `olddefconfig`. GKI
receives only KMI-safe tweaks so the stock vendor modules keep loading. See
[`patches/features/tweaks/README.md`](patches/features/tweaks/README.md).

## Root managers

| Provider | Linux 4.4 (Nexus) | Linux 4.19 (SouthWest-NG) | Linux 5.10 GKI |
|---|---|---|---|
| KernelSU-Next | `v3.4.0-legacy`, manual hooks | `v3.4.0-legacy`, manual hooks | `v3.4.0` (kprobes) |
| ReSukiSU | `v4.2.0-rc3`, manual hooks | `v4.2.0-rc3`, manual hooks, optional SUSFS v2.2.0 | `v4.2.0-rc3` (tracepoint) |
| SukiSU Ultra | not supported (fails closed) | `main` (kprobes only; not in the default matrix) | `main` |
| KernelSU (official) | not supported (fails closed) | `v0.9.5` (+ SUSFS 1.5.5) | `main` |

Non-GKI kernels use manual hooks only: kprobe/tracepoint hooks bootloop on the
SouthWest-NG Clang CFI + LTO tree, and the Nexus 4.4 tree already carries
manual hook call sites. The host-side hooks live in
`patches/root-manager/<provider>/<mm>/host-series.conf`, are applied to root
variants only and are guarded by the provider's manual-hook option.
`ENABLE_SUSFS=true` is available for ReSukiSU and official KernelSU on 4.19;
other combinations fail before any clone. See
[`patches/root-manager/kernelsu-next/README.md`](patches/root-manager/kernelsu-next/README.md)
and [`patches/root-manager/resukisu/README.md`](patches/root-manager/resukisu/README.md).

Provider sources come from the `third_party/root-managers/` submodules when
initialized, otherwise from an upstream clone; either way patches are applied
to an isolated copy. The patch registry contract is:

```text
patches/root-manager/<provider>/<kernel-mm>/
  provider-series.conf   applied to the isolated provider checkout (root_manager_apply.sh)
  host-series.conf       applied to the host kernel tree           (apply_patch_series.sh)
  susfs-series.conf      host tree, after host-series, ENABLE_SUSFS (apply_patch_series.sh)
  config.fragment        Kconfig overrides                         (config phase)
  susfs.fragment         Kconfig overrides with ENABLE_SUSFS       (config phase)
```

Bootstrap / update the submodules:

```bash
bash scripts/bootstrap_root_manager_submodules.sh
bash scripts/sync_root_managers.sh remote
```

### Known source-tree constraints

* **lavender-4.4 (Nexus `13`) ships a vendored KernelSU** wired with
  `obj-y += kernelsu/` and unconditional hook calls in `fs/*.c`. The *vanilla*
  variant therefore still contains that KernelSU copy; a truly root-free build
  needs a source branch without it.
* **garnet** source release omits `drivers/misc/hwid` and carries
  `drivers/misc/plaid` as an orphan gitlink; `patches/devices/garnet/5.10`
  drops those references so `gki_defconfig` and the Image build work.

## Telegram

Optional secrets: `TG_BOT_TOKEN`, `TG_CHAT_ID`, `TG_TOPIC_ID` (build topic),
`TG_RELEASE_TOPIC_ID` (release topic). Without them every Telegram step is a
no-op.

* **Live dashboard** (`scripts/tg_dashboard.py`): each variant build owns one
  message redrawn at a steady cadence — spinner, eased progress bar, stage
  checklist, ETA and object rate during compilation, runner load, live log
  tail. HTTP 429 `retry_after` is honoured with gradual back-off.
* **Failures**: the final frame shows the failing stage and the first real
  compiler/make error with context; `failure-summary.txt` (first error, unique
  errors, log tail) and the gzip full log are attached.
* **Releases** are relayed only to the release topic, and only on success.

## Harness

`harness/kernel-pipeline.yaml` is the Harness Cloud pipeline
(`Universal_Kernel_Build`, 25 runtime inputs); required secret: `github_token`.
Each variant is staged into the per-execution `harness-<executionId>`
prerelease as soon as it finishes; the GitHub bridge materializes that handoff
as an Actions artifact, relays Telegram, then removes transient assets. See
[`harness/README.md`](harness/README.md).

## Zairenkai / ZKFC

`lavender-4.19` integrates Zairenkai Kernel Framework Core (ZKFC) from the
owner-maintained repository at build time. The profile pins the reviewed
Zairenkai source revision, runs `kernel/setup.sh`, and applies the manual hook
series for `fs/exec.c` and `kernel/sched/core.c`.

The Lavender profile enables:

```text
CONFIG_ZKFC=y
CONFIG_ZKFC_HOOK_MANUAL=y
CONFIG_ZKFC_LICENSEE_TAG="zairenkai-sdm660-lavender"
```

The signed owner-issued `zkfc_license.inc` is never committed to this
repository. GitHub Actions reads it from the `ZAIRENKAI_LICENSE_INC` repository
secret, while Harness reads the same material from the
`zairenkai_license_inc` Harness secret. CI validates the embedded token as the
200-byte ZKFC license structure, stages it only in temporary storage, and
removes both the temporary file and any copied license from the build tree
after the build. Runtime `.zkl` tokens and signing/private key material must
remain outside the repository and release artifacts.

## Kernel identity

`kernel-name`, `kernel-codename`, `kernel-build`, and `localversion-st` define
`CONFIG_LOCALVERSION` (e.g. `-Zairenkai-VEGA1`). Bump with
`bash scripts/bump_localversion_st.sh --bump`.

## Tests

```bash
bash tests/run_all.sh                # offline: static checks, contracts, behavior
bash tests/run_all.sh --remote-only  # upstream provider/kernel applicability
```

## Upstream copyright and license notices

This repository does not relicense upstream submodule contents. Their own
LICENSE files remain authoritative:

- **KernelSU** — https://github.com/tiann/KernelSU — authored by **weishu (tiann)**; `/kernel` is GPL-2.0-only, other files GPL-3.0-or-later.
- **KernelSU-Next** — https://github.com/KernelSU-Next/KernelSU-Next — `/kernel` GPL-2.0-only, other files GPL-3.0-or-later.
- **ReSukiSU** — https://github.com/ReSukiSU/ReSukiSU — `/kernel` GPL-2.0-only, other files GPL-3.0-or-later; `LICENSE_icon_English` / `LICENSE_icon_SC` govern the artwork (vectorization by **@MiRinChan**, brand IP of **明风 OuO**, also referencing **怡子曰曰**).
- **SukiSU Ultra** — https://github.com/SukiSU-Ultra/SukiSU-Ultra — `/kernel` GPL-2.0-only, other files GPL-3.0-or-later; same icon license notices as above.
- **AnyKernel3** — https://github.com/osm0sis/AnyKernel3 — see `anykernel/LICENSE`.
