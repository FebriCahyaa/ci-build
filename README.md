# CI-Build (Kernel + Custom ROM)

## Struktur
- `.github/workflows/kernel.yml` — build kernel + zip AnyKernel3 (opsi KernelSU, GitHub Release)
- `.github/workflows/rom.yml` — build custom ROM (wajib self-hosted runner untuk AOSP)
- `scripts/` — logika build + helper Telegram (dipakai bersama oleh GitHub Actions & Harness)
- `harness/` — pipeline YAML Harness

## Setup Telegram
1. @BotFather -> `/newbot` -> simpan token.
2. Tambahkan bot ke grup/channel (admin untuk channel), ambil chat id.
3. GitHub: Settings -> Secrets and variables -> Actions: `TG_BOT_TOKEN`, `TG_CHAT_ID` (opsional `TG_TOPIC_ID`).
4. Harness: buat Secret `tg_bot_token` dan `tg_chat_id`.

## GitHub Actions
- Actions -> pilih workflow -> Run workflow -> isi input.
- Kernel muat di runner GitHub gratis. Fork AnyKernel3 dan sesuaikan `anykernel.sh` untuk device.
- ROM: runner GitHub (disk terbatas, maks 6 jam) tidak cukup untuk AOSP. Pasang self-hosted runner
  (Settings -> Actions -> Runners) di mesin 32GB+ RAM, 300GB+ SSD, lalu pakai label `self-hosted`.
- Bot Telegram dibatasi 50MB per file: zip kernel dikirim langsung, ROM dikirim berupa link (set variable
  `RCLONE_REMOTE`, mis. `gdrive:ROM`, dan konfigurasikan rclone di mesin runner).

## Harness

The repository contains reusable Harness Pipeline YAML under `harness/`.

### Project configuration

```text
Organization        : default
Project Identifier  : ci_build
GitHub Connector    : github_connector
```

### Secrets

Create these encrypted text secrets in the Harness project:

```text
tg_bot_token
tg_chat_id
```

### Universal kernel pipeline

Use `harness/kernel-pipeline.yaml` as a Remote Pipeline. It is parameterized for:

- repository and branch/ref
- architecture
- defconfig
- parallel jobs
- LLVM/LLVM IAS
- cross compiler prefixes
- optional external Clang tarball
- optional additional apt packages for non-ARM or custom toolchains
- optional KernelSU
- optional AnyKernel3 packaging
- extra `make` arguments

The build script is shared with GitHub Actions in `scripts/build_kernel.sh`.

### ROM pipeline

Use `harness/rom-pipeline.yaml` with a self-managed Harness Docker Runner. It uses `ubuntu:22.04` and installs the AOSP dependencies inside the same build step, then invokes `scripts/build_rom.sh`.

## AWS (kredit $200) sebagai runner ROM
1. Upgrade akun ke Paid plan (kredit tetap berlaku), ajukan kenaikan quota vCPU (On-Demand/Spot) di Service Quotas,
   pasang AWS Budgets.
2. Di PC/Termux: pasang `aws` CLI + `gh` CLI, lalu `aws configure` dan `gh auth login`.
3. `GH_REPO=USER/ci-build TG_BOT_TOKEN=... TG_CHAT_ID=... ./aws/launch_ec2.sh`
   (variabel opsional: `REGION`, `TYPE`, `DISK`, `SPOT`, `IDLE_MINUTES`, `MAX_HOURS`, `KEY_NAME`).
4. Setelah runner muncul di GitHub (Settings -> Actions -> Runners), jalankan workflow "Build Custom ROM"
   dengan `runner: self-hosted`.
5. Server mati sendiri setelah 1 job selesai, idle `IDLE_MINUTES`, atau umur `MAX_HOURS`.
   Dengan `terminate` ccache ikut hilang; pakai `SPOT=false BEHAVIOR=stop` bila ingin menyimpan cache (disk tetap ditagih).

# CI-Build update

Files are ready to replace in `FebriCahyaa/ci-build`:

- `harness/kernel-pipeline.yaml`
- `scripts/build_kernel.sh`
- `.github/workflows/harness-kernel.yml`

Key changes:
- Harness stage no longer asks for a Codebase checkout, avoiding the manual-codebase branch/commit error.
- Harness clones `ci-build` explicitly to obtain the build script, then clones the requested kernel repository.
- Universal toolchain mode: `auto`, `clang`, `gcc`.
- Kernel-version detection and architecture auto-detection.
- Supports old 4.x kernels (including 4.4/4.19) and modern 5.x/GKI kernels such as Garnet workflows.
- Optional custom Clang/GCC tarballs.
- Scheduler profile is reporting-only: the source/defconfig remains authoritative for EAS/HMP.
- Artifact collection covers Image, compressed images, dt/dtbo, modules, vmlinux, System.map, and config.
- GitHub Actions uses the current Harness pipeline identifier and sends runtime variables with safe JSON construction.

Suggested commit:
`feat(ci): support universal 4.x and 5.x kernel builds via Harness`

## Kernel CI hardening

The kernel builder is shared by GitHub Actions and Harness Cloud. The intended execution path is:

```text
GitHub Actions inputs
        |
        v
Harness API
        |
        v
Harness Cloud
        |
        v
ci-build/scripts/build_kernel.sh
        |
        +--> external kernel repository
        +--> auto ARCH / defconfig / fragment
        +--> resolved toolchain
        +--> kernel artifacts
```

Kernel refs support `auto`, `branch`, `tag`, and `commit`. In `auto` mode, a 40- or 64-character hexadecimal ref is treated as a commit and any other ref is treated as a branch/tag ref.

The toolchain resolver now returns the selected compiler directory to the caller, so downloaded AOSP, Proton, Neutron, and custom toolchains are actually placed first on `PATH` during compilation. The selected LLVM and LLVM IAS mode is also propagated from the resolver.

The validation workflow checks Bash syntax, ShellCheck errors, and YAML parseability before a kernel build is attempted.


## Custom AnyKernel3

Kernel packaging uses reusable profiles under `anykernel/profiles/`:

- `lavender-4.4`
- `lavender-4.19`
- `garnet-oss`
- `garnet-hyperos`

Set `ANYKERNEL_PROFILE=auto` to select a profile from the device, kernel version, and ROM family. Set `ANYKERNEL3_REF` to a branch, tag, or commit to pin the AnyKernel3 backend revision. The backend is fetched at packaging time; it is not vendored into this repository.

Profile selection is packaging metadata only and does not guarantee boot or flashing compatibility. Validate the exact boot format, AVB/vbmeta state, slot behavior, rollback requirements, kernel, DTBO, and target ROM before flashing.


## Modular kernel patch registry

Kernel source fixes are maintained under `patches/` instead of being embedded
in `scripts/build_kernel.sh`.

```text
patches/
├── devices/lavender/4.19/
├── root-manager/{kernelsu,kernelsu-next,resukisu}/4.19/
├── upstream/codelinaro/sdm660-4.19/
├── upstream/linux-stable/4.19/
└── features/lto-plus/lavender-4.19/
```

The build selects device, root-manager, and upstream patch series automatically.
Patches are idempotent and report `ALREADY APPLIED` when the source already
contains the change.

Optional environment variables:

```text
PATCH_PROFILE=auto
UPSTREAM_PROFILE=auto
LTO_PLUS=false
KERNEL_NAME=""
```

`KERNEL_NAME` resolves to the CI repository's `kernel-name` and is written to
`localversion-cip`. The generated `CONFIG_LOCALVERSION` is cleared so the
source-style `localversion*` files remain authoritative.

Harness also exposes `PATCH_PROFILE`, `UPSTREAM_PROFILE`, `LTO_PLUS`, and
`KERNEL_NAME` as pipeline variables.

### Install the modular patch registry

From a checkout containing this bundle:

```bash
./scripts/install_modular_patch_registry.sh /path/to/ci-build
```

The installer backs up modified files under `.ci-build-backup-YYYYMMDD-HHMMSS/`.

## Kernel name and codename

This repository mirrors the SouthWest-NG source's `localversion-cip` /
`localversion-st` mechanism. The first Zairenkai build is configured as:

```text
kernel-name    = Zairenkai
localversion-cip = -Zairenkai
kernel-codename = VEGA
kernel-build    = 1
localversion-st  = -VEGA1
```

During a build, `scripts/set_kernel_name.sh` keeps `kernel-name` and
`localversion-cip` aligned, then `scripts/sync_localversion_files.sh` copies
`localversion-cip` and `localversion-st` into the kernel source tree.
The resulting Kbuild release suffix is therefore `-Zairenkai-VEGA1` before
any source-controlled SCM suffix is added.

To bump the codename build number:

```bash
./scripts/bump_localversion_st.sh --bump
```

To explicitly set the first build:

```bash
./scripts/bump_localversion_st.sh --codename VEGA --build 1
```

## Local trigger

The `kernel.yml` workflow is exposed through `workflow_dispatch`, so it can be started directly from a local Ubuntu/Termux environment with GitHub CLI.

Use the helper below to send the complete kernel build parameter set from local to GitHub Actions:

```bash
./scripts/start_local_kernel.sh
```

Override values with environment variables, for example:

```bash
KERNEL_NAME=Zairenkai \
ENABLE_KSU=false \
PATCH_PROFILE=none \
UPSTREAM_PROFILE=none \
./scripts/start_local_kernel.sh
```

The default kernel source is `pix106/android_kernel_xiaomi_sdm660_southwest-ng` on `main` (Xiaomi SDM660 / Lavender-capable SouthWest-NG 0.20.1 tree). The default build uses the source tree as-is: `ENABLE_KSU=false`, `PATCH_PROFILE=none`, and `UPSTREAM_PROFILE=none`.

## Trigger Harness dari local

Untuk menjalankan pipeline Harness melalui GitHub Actions bridge:

```bash
chmod +x scripts/start_local_harness.sh
./scripts/start_local_harness.sh
```

GitHub Actions menyimpan secret `HARNESS_API_KEY`, `HARNESS_ACCOUNT_ID`, dan Telegram secrets. Local hanya mengirim input workflow, jadi secret tidak perlu ditaruh di Termux/Ubuntu.


## Packaging and live build telemetry

The CI repository remains the source of truth for universal build orchestration,
device packaging profiles, and Harness/Telegram integration. The build emits a
flashable AnyKernel3 ZIP as a normal release artifact.

A separate Zairenkai packaging repository can be introduced later for a
standalone distribution channel, but duplicating the packager here now would
create two sources of truth.

Live build telemetry uses a unique GitHub commit-status context per Harness
execution. Phase milestones are real build milestones; compile progress is
derived from the Kbuild dry-run compile plan versus observed CC/AS actions.
Telegram refreshes its presentation once per second while Harness API polling
remains at three-second intervals.
