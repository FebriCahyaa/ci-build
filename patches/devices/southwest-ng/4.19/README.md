# Southwest-NG 4.19 Performance Profile

This profile contains only the conservative scheduler/configuration changes
validated against `pix106/android_kernel_xiaomi_sdm660_southwest-ng` `main`.

## Changes

1. Fix the unreachable `sched_set_boost()` API path in `kernel/sched/boost.c`.
   The previous `return 0` made the validated boost transition code dead for
   callers of the exported C API. The existing proc/sysctl handler remains
   unchanged.
2. Move the SDM660 vendor defconfig from 100 Hz to 250 Hz and select
   `schedutil` as the default CPUFreq governor. Both governors and the existing
   WALT integration remain intact.

## Deliberately not included

This profile does not disable thermal protection, force all CPUs online,
remove idle states, raise GPU/DDR limits, replace WALT, or add a second input
boost path. The source already has an existing 64 ms devfreq input boost, so
it is left unchanged.

## CI selection

For the Southwest-NG source, select:

```text
PATCH_PROFILE=southwest-ng
```

The source tree is intentionally left patch-free when `PATCH_PROFILE=auto`,
matching the CI registry policy for this repository.