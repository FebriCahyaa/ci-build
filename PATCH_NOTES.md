## ReSukiSU / Lavender 4.19 manual hook

- Replaced the stale SUSFS-specific 4.19 root-provider patches with the official ReSukiSU manual integration shape for this exact SouthWest-NG layout.
- Added required execve, faccessat, stat and reboot hooks plus SELinux static exports.
- Explicitly enabled ReSukiSU automatic LSM/input hooks for setuid, initrc and input paths.
- Removed obsolete `ksu_vfs_read_hook` / `ksu_input_hook` compatibility code and the incomplete legacy SUSFS process-state patch.
- KernelSU-Next 4.19 now enables `CONFIG_MODULES=y` because this kernel's `CONFIG_KPROBES` requires it.

# Root-manager and SUSFS integration

## Southwest-NG 4.19 balanced profile

The explicit `PATCH_PROFILE=southwest-ng` profile carries two source patches:

- repair the unreachable exported `sched_set_boost()` control path;
- move the SDM660 vendor defconfig to 250 Hz and make `schedutil` the default CPUFreq governor.

The profile intentionally keeps the existing WALT scheduler, thermal limits, CPU idle, and 64 ms devfreq input boost unchanged. It is not selected automatically because `PATCH_PROFILE=auto` remains patch-free for the Southwest-NG source.

The CI uses provider-native integration and strict compatibility gates.

## Linux 4.19

- Official KernelSU: `tiann/KernelSU@v0.9.5`. KernelSU's own documentation states
  v0.9.5 is the final non-GKI release.
- KernelSU-Next: `v1.1.1` for legacy 4.x builds and `v3.4.0` for the 5.10 GKI build; the provider resolver selects the family-specific ref.
- ReSukiSU: `ReSukiSU/ReSukiSU@v4.2.0-rc3`, which documents older-kernel support and a
  SUSFS inline-hook mode.

## SUSFS

The dedicated upstream `kernel-4.19` SUSFS branch is pinned to
`001e69919c6271f690fd00b17e4c721c9e599152`, whose tree reports SUSFS 1.5.5.
The CI uses the upstream 4.19 patch set only for official KernelSU and applies
it with `git apply --check` before changing the source tree.

ReSukiSU uses its own integrated SUSFS hook path and is not mixed with the
official-KernelSU SUSFS patch set.

KernelSU-Next + the external official-KernelSU 4.19 SUSFS patch set is blocked
instead of applying an unverified API combination.

## Lavender 4.4 NonGKI

The `lavender-4.4` target now uses the 4.4-tested NonGKI syscall hook layer
from `Lokitla/NonGKI_Kernel_Build_2nd`, pinned to commit
`ab5b09509bcdf7a077468b0ab30bfe3cc86a0c77`. Enabling SUSFS switches to the
upstream inline hook implementation and the dedicated SUSFS v2.3.0 4.4
config surface. The full SUSFS source patch remains strict and refuses fuzzy
application on divergent vendor trees.


## Telegram delivery and build identity hardening

- Route new build messages and AnyKernel documents through `TG_TOPIC_ID`; main build workflows now require the topic and refuse to fall back to General when it is absent.
- Include the canonical target profile (`lavender-4.4`, `lavender-4.19`, or `garnet-gki`) in Telegram build status and package captions.
- Enable immediate AnyKernel ZIP delivery in the Harness pipeline independently of GitHub Release publication; release relay skips duplicate asset uploads.
- Validate Telegram Bot API response bodies, retry document uploads, report failed delivery, and split large documents into chunks below the Bot API upload limit.
- Set Kbuild defaults to `FebriCahyaa@Zairenkai`; write `CONFIG_LOCALVERSION="-Zairenkai"` explicitly and clear the duplicate `localversion-cip` suffix.
- Set the AnyKernel maintainer banner to `Febrian Rahmad Cahya`.
- Bridge the GitHub `TG_TOPIC_ID` secret into the remote Harness execution without exceeding its 25-variable runtime limit; optional kernel-name and apt-package overrides are bundled in one JSON runtime variable, while the exact CI commit pin is preserved.
- Keep the target profile visible in the live progress message, not only the initial/final notification.


## Root-manager submodule integration

- Added Git submodules for KernelSU, KernelSU-Next, ReSukiSU, and SukiSU Ultra under `third_party/root-managers/`.
- Provider sources are copied into isolated build checkouts before source patches are applied.
- Added bootstrap/sync helpers for upstream synchronization.

## SukiSU Ultra / Linux 4.4

- Added `sukisu-ultra` as a first-class variant.
- Added 4.4, 4.19, and 5.10 config fragments.
- Linux 4.4 uses `CONFIG_KSU_MANUAL_SU=y` and the pinned NonGKI hook stage.
- SukiSU Ultra + SUSFS is fail-closed on 4.4 until a verified upstream-compatible SUSFS contract is available.

## Telegram release routing

- Build progress remains on `TG_TOPIC_ID`.
- Published releases use `TG_RELEASE_TOPIC_ID` from `tg_release_topic_id`.
- Release message and release asset uploads are separate from build-completion notifications.


## 4.4 provider compatibility layer

- Added strict provider patch series for KernelSU-Next and SukiSU Ultra on Linux 4.4.
- Added local shims for pre-4.8 user-copy APIs, pre-4.11 `refcount_t`, pre-4.12 `kvmalloc`/`kvfree`, and pre-P4D ARM64 page-table walking.
- Added a SukiSU Ultra KPM `set_memory.h` compatibility shim for the documented sub-4.19 requirement.
- ReSukiSU remains the only provider using the pinned external source-hook script in the Lavender 4.4 stage; KSU-Next/SukiSU Ultra use provider-native hook paths.
