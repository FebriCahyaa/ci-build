# Patch Notes — CI / Harness / KernelSU-Next Fix 5

## Harness runtime input API

The GitHub Actions Harness trigger now emits Runtime Input YAML with the
canonical `pipeline.identifier: Universal_Kernel_Build` field. This matches
the current Harness Runtime Input YAML API contract and prevents the HTTP 400
`Couldn't convert yaml to json node` failure seen during pipeline execution.

The generated runtime input is validated locally before the API request and a
regression test enforces the 25-variable contract and unique variable names.

## Telegram topics

`TG_TOPIC_ID` remains the live build/progress topic. `TG_RELEASE_TOPIC_ID` is
the dedicated release/failure topic. The duplicate `TG_RELEASE_TOPIC_ID`
environment mapping was removed from `harness/kernel-pipeline.yaml`.

Telegram delivery now falls back in this order when a configured topic is
invalid or unavailable:

1. release topic
2. build topic
3. General topic

HTML parsing failures are retried as plain text. Failure notifications no
longer require the release topic to be valid.

## KernelSU-Next 4.19 compatibility

KernelSU-Next v3.4.0 remains the provider for Linux 4.19+. The 4.19
`file_wrapper.c` compatibility patch was simplified to avoid emulating VFS
operations that do not exist on Linux 4.19:

- `iopoll` is fenced to Linux 5.1+
- `remap_file_range` and `REMAP_FILE_DEDUP` are fenced to Linux 4.20+
- Linux 4.19 does not register the newer remap callback
- no provider `struct file_operations` layout is modified

A provider preflight regression test is included to apply the patch to an
exact v3.4.0 KernelSU-Next checkout in CI.

## Validation

- Harness workflow YAML parses successfully
- Harness pipeline YAML parses successfully
- Runtime Input YAML identifier/shape test passes
- Telegram topic fallback test passes
- Telegram HTML escaping/fallback tests pass
- Telegram failure notifier test passes
- Telegram release relay test passes
- KernelSU-Next 4.19 file-wrapper compatibility contract passes
- Git diff whitespace checks pass in the repository
