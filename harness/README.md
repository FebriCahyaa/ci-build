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
