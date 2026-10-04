# Official KernelSU provider integration

Upstream: https://github.com/tiann/KernelSU

Linux 4.14 – 5.9 resolve to `v0.9.5`, the last official non-GKI release (other
refs are rejected); Linux 5.10+ uses `main`; Linux 4.4 fails closed (upstream
legacy support starts at 4.14). With `ENABLE_SUSFS=true` on 4.19 the pinned
susfs4ksu `kernel-4.19` set is applied with strict `git apply --check`.
Not part of the default release matrix.
