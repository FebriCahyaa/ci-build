#!/usr/bin/env bash
# Build all canonical root variants from one pristine kernel source seed.
# Shared by Harness and local execution. GitHub Actions uses the same contract
# but fans the variants out as matrix jobs.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CI_LOG_TAG=matrix
BUILD_PROFILE="${BUILD_PROFILE:-auto}"
DEVICE="${DEVICE:-generic}"
KERNEL_FAMILY="${KERNEL_FAMILY:-}"
VARIANTS_INPUT="${ROOT_VARIANTS:-${VARIANTS:-$DEFAULT_VARIANTS}}"
MATRIX_WORK_DIR="${MATRIX_WORK_DIR:-${WORK_DIR:-$PWD/work}}"
SEED_DIR="${KERNEL_SOURCE_SEED:-$MATRIX_WORK_DIR/source-seed}"
CCACHE_DIR="${CCACHE_DIR:-$MATRIX_WORK_DIR/ccache}"

[[ -x "$SCRIPT_DIR/build_kernel.sh" ]] || ci_die "scripts/build_kernel.sh is missing"
[[ -x "$SCRIPT_DIR/resolve_build_profile.sh" ]] || ci_die "scripts/resolve_build_profile.sh is missing"

resolve_profile() {
  local selected="$BUILD_PROFILE"
  eval "$(BUILD_PROFILE="$selected" DEVICE="$DEVICE" KERNEL_FAMILY="$KERNEL_FAMILY" "$SCRIPT_DIR/resolve_build_profile.sh")"
  BUILD_PROFILE="$PROFILE_ID"
  DEVICE="${DEVICE_OVERRIDE:-${PROFILE_DEVICE}}"
  KERNEL_FAMILY="${KERNEL_FAMILY_OVERRIDE:-${PROFILE_KERNEL_FAMILY}}"
  export BUILD_PROFILE DEVICE KERNEL_FAMILY
}

resolve_profile
mapfile -t VARIANTS < <(expand_variants "$VARIANTS_INPUT")
((${#VARIANTS[@]} > 0)) || ci_die "no root variants requested"

KERNEL_REPO="${KERNEL_REPO:-$PROFILE_KERNEL_REPO}"
KERNEL_BRANCH="${KERNEL_BRANCH:-$PROFILE_KERNEL_REF}"
KERNEL_REF_TYPE="${KERNEL_REF_TYPE:-$PROFILE_KERNEL_REF_TYPE}"
export KERNEL_REPO KERNEL_BRANCH KERNEL_REF_TYPE

mkdir -p "$MATRIX_WORK_DIR" "$CCACHE_DIR"

prepare_seed() {
  if [[ -d "$SEED_DIR/.git" ]]; then
    ci_log "reuse source seed: $SEED_DIR"
    git -C "$SEED_DIR" reset -q --hard
    git -C "$SEED_DIR" clean -qfdx
    return 0
  fi

  rm -rf "$SEED_DIR"
  ci_log "clone source seed: $KERNEL_REPO @ $KERNEL_BRANCH"
  git_fetch_ref "$KERNEL_REPO" "$KERNEL_BRANCH" "$SEED_DIR" || ci_die "unable to prepare kernel source seed"
  git -C "$SEED_DIR" reset -q --hard
  git -C "$SEED_DIR" clean -qfdx
}

prepare_seed

# Harness uses one durable per-execution staging release whenever artifact staging
# is enabled. This is independent of public release publication so failures and
# partial matrix results remain recoverable by GitHub Actions.
if is_true "${CI_ARTIFACT_STAGE:-false}"; then
  if [[ -n "${HARNESS_EXECUTION_ID:-}" && -z "${CI_ARTIFACT_RELEASE_TAG:-}" ]]; then
    export CI_ARTIFACT_RELEASE_TAG="harness-${HARNESS_EXECUTION_ID}"
  fi
fi

SUMMARY="$MATRIX_WORK_DIR/matrix-summary.txt"
: > "$SUMMARY"
FAILURES=0
MATRIX_FAIL_FAST_INFRA="${MATRIX_FAIL_FAST_INFRA:-true}"

for variant in "${VARIANTS[@]}"; do
  ci_log "============================================================"
  ci_log "variant: $variant"
  ci_log "profile: $BUILD_PROFILE"
  ci_log "============================================================"

  VARIANT_WORK="$MATRIX_WORK_DIR/$BUILD_PROFILE/$variant"
  rm -rf "$VARIANT_WORK"
  mkdir -p "$VARIANT_WORK"

  # Each child gets an isolated source/output tree, while git objects and ccache
  # remain shared. This avoids cross-variant source contamination.
  export BUILD_PROFILE
  export ROOT_VARIANT="$variant"
  export KERNEL_VARIANT="$variant"
  export DEVICE
  export KERNEL_FAMILY
  export KERNEL_REPO
  export KERNEL_BRANCH
  export KERNEL_REF_TYPE
  export KERNEL_SOURCE_SEED="$SEED_DIR"
  export CCACHE_DIR
  export WORK_DIR="$VARIANT_WORK"
  export KERNEL_OUT="$VARIANT_WORK/kernel-out"
  export ARTIFACT_DIR="$VARIANT_WORK/artifacts"
  export PACKAGE_ANYKERNEL="${PACKAGE_ANYKERNEL:-$PROFILE_PACKAGE_ANYKERNEL}"
  export ANYKERNEL_PROFILE="${ANYKERNEL_PROFILE:-$PROFILE_ANYKERNEL_PROFILE}"
  export ANYKERNEL3_REF="${ANYKERNEL3_REF:-$PROFILE_ANYKERNEL3_REF}"
  export SCHEDULER_PROFILE="${SCHEDULER_PROFILE:-$PROFILE_SCHEDULER_PROFILE}"
  export PATCH_PROFILE="${PATCH_PROFILE:-$PROFILE_PATCH_PROFILE}"
  export UPSTREAM_PROFILE="${UPSTREAM_PROFILE:-$PROFILE_UPSTREAM_PROFILE}"
  export LTO_PLUS="${LTO_PLUS:-$PROFILE_LTO_PLUS}"
  export NONGKI_4_4_HOOKS="${NONGKI_4_4_HOOKS:-${PROFILE_NONGKI_4_4_HOOKS:-auto}}"
  export NONGKI_4_4_MODE="${NONGKI_4_4_MODE:-${PROFILE_NONGKI_4_4_MODE:-auto}}"

  started="$(date +%s)"
  if "$SCRIPT_DIR/build_kernel.sh"; then
    rc=0
    state=PASS
  else
    rc=$?
    state=FAIL
    FAILURES=$((FAILURES + 1))
  fi
  elapsed=$(( $(date +%s) - started ))
  printf '%s\t%s\t%s\t%s\n' "$variant" "$state" "$rc" "$elapsed" | tee -a "$SUMMARY"

  # These failures happen before meaningful variant-specific compilation and
  # therefore affect every variant from the same source/profile. Do not waste
  # time repeating the same infrastructure failure three times.
  if [[ "$state" == FAIL && "$MATRIX_FAIL_FAST_INFRA" == true ]]; then
    build_log="$VARIANT_WORK/build.log"
    if [[ -f "$build_log" ]] && grep -qE '\[build\] FAILED: (toolchain resolution|auto-detect|defconfig|config fragment merge|config fragment olddefconfig|olddefconfig after config patches)' "$build_log"; then
      ci_log "shared infrastructure failure detected for $variant; stopping remaining variants"
      break
    fi
  fi
done

if (( FAILURES > 0 )); then
  ci_log "matrix completed with $FAILURES failed variant(s)"
  exit 1
fi

ci_log "matrix completed successfully: ${#VARIANTS[@]} variants"
