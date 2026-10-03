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
