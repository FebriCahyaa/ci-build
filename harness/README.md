# Harness CI

The Harness kernel pipeline is the same build implementation used by GitHub Actions and local execution.

## Kernel pipeline

Use `harness/kernel-pipeline.yaml` as a Remote Pipeline. The important variables are:

```text
BUILD_PROFILE   = lavender-4.4 | lavender-4.19 | garnet-gki
ROOT_VARIANTS   = vanilla,kernelsu-next,resukisu | subset | all
PUBLISH_RELEASE = false | true
```

The remaining variables are optional build overrides and are intentionally aligned with the GitHub Actions bridge.

### Progressive artifact persistence and failure diagnostics

Each completed variant is staged immediately into a per-execution draft GitHub Release named `harness-<executionId>`. This happens before the next variant starts, so artifacts from successful variants remain downloadable even if a later variant fails. When `PUBLISH_RELEASE=true`, the same draft release is finalized only after the complete build succeeds.

On failure, the builder writes both `failure-summary.txt` (extracted diagnostics plus the last 300 log lines) and `failure-build.log.gz` (the full build log) and stages them into the same draft release. The GitHub bridge monitor reads the staged failure summary for the final Telegram error message.

The pipeline:

```text
ci-build checkout
   -> dependency installation
   -> target profile resolution
   -> one kernel source seed
   -> 3 root variants
   -> AnyKernel3 + changelog
   -> optional GitHub release
```

## GitHub bridge

`.github/workflows/harness-kernel.yml` triggers `Universal_Kernel_Build`, monitors the execution, and relays the release to Telegram when requested.

Required Harness secret:

```text
github_token
```

Telegram credentials are only needed for Telegram notification/relay behavior.

## ROM pipeline

`harness/rom-pipeline.yaml` remains separate because AOSP/ROM builds require a self-managed runner with substantially more disk and memory than the universal kernel pipeline.
