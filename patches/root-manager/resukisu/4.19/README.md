# ReSukiSU / Linux 4.19 / Lavender

This profile targets the non-GKI Xiaomi Lavender 4.19 tree
`pix106/android_kernel_xiaomi_sdm660_southwest-ng`.

ReSukiSU is integrated through its built-in `CONFIG_KSU_MANUAL_HOOK` path.
The source series contains only the hooks that the upstream ReSukiSU 4.19
manual integration requires for this kernel layout:

- execve / post-execve hook in `fs/exec.c`
- faccessat hook in `fs/open.c`
- stat/newfstat/fstat64 hooks in `fs/stat.c`
- reboot hook in `kernel/reboot.c`
- SELinux static symbol exports required when `CONFIG_KALLSYMS_ALL` is off

`sys_read`, input and setresuid are intentionally left to ReSukiSU's automatic
Manual Hook integrations, which are enabled explicitly in `config.fragment`.

The previous SUSFS-specific read/input/setresuid compatibility patches were
removed because they targeted an incompatible older hook shape and are not
applied by this profile.

For Lavender 4.19, do not combine this Manual Hook profile with the external
`ENABLE_SUSFS=true` 4.19 config. A separate SUSFS-inline source integration is
required for that mode.
