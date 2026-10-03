# Harness CI

This directory contains Harness Pipeline YAML files.

## Pipelines

- `kernel-pipeline.yaml` — universal kernel build; runs on Harness Cloud.
- `rom-pipeline.yaml` — Android ROM build; runs through a self-managed Harness Docker Runner.

## Project settings used by the current CI Build project

```yaml
orgIdentifier: default
projectIdentifier: ci_build
connectorRef: github_connector
```

## Required Harness secrets

Create these encrypted text secrets in the project:

- `tg_bot_token`
- `tg_chat_id`

## Remote Pipeline setup

For a Remote Pipeline, store the pipeline YAML in this directory and configure Harness to use:

```text
Repository: FebriCahyaa/ci-build
Path:
  harness/kernel-pipeline.yaml
```

or:

```text
Repository: FebriCahyaa/ci-build
Path:
  harness/rom-pipeline.yaml
```

The pipeline's own codebase is the `ci-build` repository. The kernel pipeline then clones the selected `KERNEL_REPO` and builds it according to the supplied parameters.
