# CI Build v8 Patch Notes

## KernelSU-Next v3.4.0 / Linux 4.19

The previous `0002-file-wrapper-linux-4.19-compat.patch` failed provider
preflight at `kernel/infra/file_wrapper.c:390` because its fifth hunk omitted
the legacy `p->ops.write` context line and used an incorrect hunk location.

The patch is corrected against KernelSU-Next v3.4.0 commit:
`1a879d6a866f80b1fa1c1009a2ffa747873cbb5e`.

Compatibility policy:
- `iopoll` is compiled only for kernels >= 5.1.
- `remap_file_range` is compiled/registered only for kernels >= 4.20.
- Linux 4.19 uses the native `clone_file_range` and `dedupe_file_range`
  operations through provider-local wrappers.

The root-manager script also verifies that `v3.4.0` resolves to the expected
commit before provider patches are applied.

## Telegram topic isolation

Build progress and all build/failure diagnostics use `TG_TOPIC_ID` only.
`TG_RELEASE_TOPIC_ID` is intentionally restricted to successful release
relay logic.

Changes:
- removed release-topic fallback from `scripts/tg.sh`;
- build failure fallback uses `TG_TOPIC_ID`;
- Harness trigger failure fallback uses `TG_TOPIC_ID`;
- Harness build step no longer receives `TG_RELEASE_TOPIC_ID`;
- release relay skips failed Harness executions instead of posting errors to
  the Release topic;
- added regression tests for strict topic separation.

Expected routing:

`Kernel build / progress / failure -> topic 13 (TG_TOPIC_ID)`

`Successful published release -> release topic (TG_RELEASE_TOPIC_ID)`

The 4.19 provider preflight test now falls back to cloning the exact upstream
`v3.4.0` tag when the local submodule is not initialized, so CI cannot silently
skip the most important provider patch applicability check.
