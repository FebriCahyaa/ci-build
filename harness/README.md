# Harness CI

The Harness kernel pipeline is the same build implementation used by GitHub Actions and local execution.

## Kernel pipeline

Use `harness/kernel-pipeline.yaml` as a Remote Pipeline. The important variables are:

```text
BUILD_PROFILE   = lavender-4.4 | lavender-4.19 | garnet-gki
ROOT_VARIANTS   = vanilla,kernelsu-next,resukisu,sukisu-ultra | subset | all
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
   -> 4 root variants
   -> AnyKernel3 + changelog
   -> optional GitHub release
```

## GitHub bridge

`.github/workflows/harness-kernel.yml` triggers `Universal_Kernel_Build`, monitors the execution, and relays the release to Telegram when requested.

Required Harness secret:

```text
github_token
```

Telegram build progress uses `TG_TOPIC_ID`. Published releases use the separate `tg_release_topic_id` secret and are relayed to `TG_RELEASE_TOPIC_ID`; the two topics are intentionally isolated.

## ROM pipeline

`harness/rom-pipeline.yaml` remains separate because AOSP/ROM builds require a self-managed runner with substantially more disk and memory than the universal kernel pipeline.
