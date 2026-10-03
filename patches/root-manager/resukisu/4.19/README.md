# ReSukiSU / Linux 4.19

ReSukiSU is integrated from its upstream `kernel/setup.sh` layout.
For SUSFS builds the `KSU_SUSFS` hook is provided by ReSukiSU itself, so
CI does not layer the official-KernelSU-only SUSFS 4.19 patch set on top.

This keeps the provider and its SUSFS hook implementation coherent.
