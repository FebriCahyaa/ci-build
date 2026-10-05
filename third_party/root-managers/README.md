# Root-manager source registry

| Provider | Upstream | Submodule branch | Linux 4.4 |
|---|---|---|---|
| KernelSU | https://github.com/tiann/KernelSU | `main` | not supported upstream (< 4.14) |
| KernelSU-Next | https://github.com/KernelSU-Next/KernelSU-Next | `dev` | `v3.4.0-legacy` + manual hooks |
| ReSukiSU | https://github.com/ReSukiSU/ReSukiSU | `main` | `v4.2.0-rc3` + manual hooks |
| SukiSU Ultra | https://github.com/SukiSU-Ultra/SukiSU-Ultra | `main` | not supported (does not compile) |

Builds never use the submodule working tree directly: `root_manager_apply.sh`
clones the requested ref out of an initialized submodule (or from upstream
when the submodule is absent) into an isolated work directory and applies the
provider patches there, so the gitlinks stay clean.

## Submodule integrity

`.gitmodules` declares the upstream locations; Git additionally needs a
`160000` gitlink in the index for each provider. If the repository was
imported from a ZIP (which drops gitlinks and executable bits), repair it with:

```bash
bash scripts/bootstrap_root_manager_submodules.sh
git ls-files --stage -- third_party/root-managers
```

The helper is idempotent: it recreates missing gitlinks from the canonical
URLs, initializes the worktrees, and refuses to overwrite a tracked
non-submodule path. Commit the four gitlinks afterwards.
