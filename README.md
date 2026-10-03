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
1. Buat project Harness, aktifkan CI.
2. Buat connector GitHub (`github_connector`) dan secret Telegram.
3. Pipelines -> Create -> YAML -> tempel `harness/kernel-pipeline.yaml`.
4. Kernel boleh Harness Cloud. ROM: pasang Harness Docker Runner di server sendiri, lalu `harness/rom-pipeline.yaml`.
5. Sesuaikan `projectIdentifier`, `orgIdentifier`, `connectorRef`.

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
