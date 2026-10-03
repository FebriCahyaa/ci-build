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
