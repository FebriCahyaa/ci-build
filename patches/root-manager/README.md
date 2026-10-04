# Root-manager integration patches

Provider sources come from upstream (submodule snapshot or clone) and are never
vendored here. Per provider and kernel generation:

| File | Applied to | By |
|---|---|---|
| `provider-series.conf` | isolated provider checkout (`$WORK/KernelSU`) | `root_manager_apply.sh` |
| `host-series.conf` | host kernel tree | `apply_patch_series.sh` (source phase) |
| `config.fragment` | `$KERNEL_OUT/.config` | `apply_patch_series.sh` (config phase) |

Provider patches may only touch `kernel/` paths of the provider tree (enforced
by `tests/root_manager_registry_test.sh`). `tests/root_manager_remote_test.sh`
resolves every profile's pinned refs and applies each series to the real
upstream sources, so a patch written for a different provider ref than the
profile pins is caught in CI.
