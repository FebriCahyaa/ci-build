#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PIPE="$ROOT/harness/kernel-pipeline.yaml"
WF="$ROOT/.github/workflows/harness-kernel.yml"
BUILD="$ROOT/scripts/build_kernel.sh"
FETCH="$ROOT/scripts/fetch_harness_staging_assets.sh"

# Harness must stage artifacts regardless of public release publication and must
# not send bulky build files directly to Telegram from the ephemeral runner.
grep -q 'TG_SEND_ARTIFACTS: "false"' "$PIPE"
grep -q 'TG_SEND_FAILURE_ARTIFACTS: "false"' "$PIPE"
grep -q 'CI_ARTIFACT_STAGE: "true"' "$PIPE"
grep -q 'trap .*finalize_handoff' "$PIPE"
grep -q 'handoff_release=harness-' "$PIPE"
grep -q 'bash scripts/stage_ci_release_assets.sh' "$PIPE"
grep -q 'CLEAN_PREFIX="staging-"' "$PIPE"
# Finalization must execute assemble_release_assets with environment assignments.
grep -q 'SOURCE_ROOT="$PWD/work"' "$PIPE"
grep -q 'ASSET_DIR="$PWD/release/assets"' "$PIPE"
grep -q 'bash scripts/assemble_release_assets.sh' "$PIPE"

# The handoff is a draft release, so the consuming Actions job needs push-level
# contents access; contents: read cannot enumerate draft releases and appears as 404.
grep -A6 '^  trigger-harness:' "$WF" | grep -q 'contents: write'

# GitHub Actions must materialize the per-execution handoff, retain it as an
# Actions artifact, and relay the same files to Telegram after the monitor exits.
grep -q 'Materialize Harness artifacts into GitHub Actions' "$WF"
grep -q 'scripts/fetch_harness_staging_assets.sh' "$WF"
grep -q 'actions/upload-artifact@v4' "$WF"
grep -q 'name: harness-${{ inputs.build_profile }}-${{ steps.trigger.outputs.plan_execution_id }}' "$WF"
grep -q 'TG_SKIP_ASSET_UPLOAD: "false"' "$WF"

# Failure reports are copied into the persistent artifact directory before fail() exits.
grep -q 'cp -f "\$summary" "\$ARTIFACTS/failure-summary.txt"' "$BUILD"
grep -q 'cp -f "\$compressed" "\$ARTIFACTS/failure-build.log.gz"' "$BUILD"
grep -q 'stage_artifacts "\$ARTIFACTS"' "$BUILD"

bash -n "$FETCH"
echo 'PASS Harness artifact handoff contract'
