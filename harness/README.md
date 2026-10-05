# Harness CI

## Kernel pipeline

`kernel-pipeline.yaml` (`Universal_Kernel_Build`) runs the same
`scripts/build_variants.sh` used locally. It clones ci-build, checks out the
exact `CI_BUILD_SHA`, initializes the root-manager submodules for that commit,
and builds the requested variants from one kernel source seed with shared
ccache and a shared toolchain cache.

All 25 pipeline variables are runtime inputs supplied by
`.github/workflows/harness-kernel.yml`:

```text
BUILD_PROFILE   = lavender-4.4 | lavender-4.19 | garnet-gki
ROOT_VARIANTS   = default | all | vanilla,kernelsu-next,resukisu,resukisu-susfs,sukisu-ultra
PUBLISH_RELEASE = false | true
BUILD_CUSTOMIZATION = {"kernel_name": "...", "apt_packages": "...", "tweaks": "none|balanced|performance"}
```

Required Harness secret: `github_token` (contents: write on the repository).
Verify a token before storing it with
`GH_TOKEN=... GH_REPOSITORY=owner/ci-build bash scripts/github_harness_preflight.sh`
(creates and deletes a temporary draft release).
Optional: `tg_bot_token`, `tg_chat_id` for the live build dashboard.

### Artifact persistence and failure diagnostics

Each finished variant is staged immediately into the per-execution prerelease
`harness-<executionId>` (`staging-*` assets), so completed variants survive a
later failure. On exit the pipeline assembles the release set, re-stages it as
`handoff-*` assets plus a `handoff-HANDOFF-READY.txt` marker, and — when
`PUBLISH_RELEASE=true` and the matrix succeeded — publishes the final release.

Failed variants upload `failure-summary.txt` (first error with context, unique
error lines, log tail) and `failure-build.log.gz`.

## GitHub bridge

`harness-kernel.yml` triggers the pipeline, monitors it
(`scripts/harness_monitor.py`), materializes the handoff as a GitHub Actions
artifact, sends failures to `TG_TOPIC_ID`, relays a successful published
release to `TG_RELEASE_TOPIC_ID`, then removes the transient handoff assets.

## ROM pipeline

`rom-pipeline.yaml` stays separate: AOSP/ROM builds need a self-managed Docker
runner with far more disk and memory than the kernel pipeline.
