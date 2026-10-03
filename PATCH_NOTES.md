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
- KernelSU-Next: `KernelSU-Next/KernelSU-Next@v3.4.0`, which currently documents
  4.4 through 6.6 support.
- ReSukiSU: `ReSukiSU/ReSukiSU@main`, which documents older-kernel support and a
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


## Compile telemetry safety

The compile stage no longer performs an unrestricted `make -n` dry-run.
Large Android kernel trees can spend substantial time expanding the dry-run
command graph before the real compiler starts. CI now records a lightweight
source-file estimate and computes live progress from actual Kbuild CC/AS
actions, preserving build startup reliability and diagnostics.
