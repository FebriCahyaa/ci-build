# Root-manager source registry

| Provider | Upstream | Branch | 4.4 policy |
|---|---|---|---|
| KernelSU | https://github.com/tiann/KernelSU | `main` | blocked upstream below 4.14 |
| KernelSU-Next | https://github.com/KernelSU-Next/KernelSU-Next | `dev` | supported via legacy + NonGKI |
| ReSukiSU | https://github.com/ReSukiSU/ReSukiSU | `main` | supported via manual hook + NonGKI |
| SukiSU Ultra | https://github.com/SukiSU-Ultra/SukiSU-Ultra | `main` | supported via manual `CONFIG_KSU_MANUAL_SU` |

Verified current upstream commits on 2026-10-04:
- KernelSU `cd4af89c43005f33df91ba7cb66e00e67a4d0c1b`
- KernelSU-Next source is pinned at build time to `v3.4.0` for Linux 4.19+;
  Linux 4.4 uses the separately pinned `v1.1.1` compatibility snapshot.
- ReSukiSU `8770c7e324a22895703c4916b8a16520e0b81c79`
- SukiSU Ultra `7fbbb1f12e2410b69c8ebf958be84f165b8d0c93`

## Submodule integrity

`.gitmodules` declares the upstream locations, but Git requires a `160000` gitlink in the ci-build index for each provider. If the repository was imported from a ZIP or another format that dropped gitlinks, repair the checkout with:

```bash
bash scripts/bootstrap_root_manager_submodules.sh
git ls-files --stage -- third_party/root-managers
```

The bootstrap helper is idempotent. It creates missing gitlinks from the canonical upstream URLs, initializes the provider worktrees, and refuses to overwrite a tracked non-submodule path. After running it locally, commit the four gitlinks so normal `git clone --recurse-submodules` and GitHub Actions checkout can initialize them without the repair step.
