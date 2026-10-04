#!/usr/bin/env bash
# Universal kernel builder: one kernel source + one root variant -> artifacts + AnyKernel3 ZIP.
# Shared by GitHub Actions, Harness, and local builds. Multi-variant builds use build_variants.sh.
#
# Required: KERNEL_REPO
# Main options (all optional):
#   KERNEL_BRANCH KERNEL_REF_TYPE DEVICE ARCH DEFCONFIG CONFIG_FRAGMENT JOBS KERNEL_TARGET
#   ROOT_VARIANT=vanilla|kernelsu|kernelsu-next|resukisu|sukisu-ultra   (preferred over ENABLE_KSU/KSU_PROVIDER)
#   KSU_REF ENABLE_SUSFS SUSFS_REF KSU_REPO KSU_HOOK_MODE
#   NONGKI_4_4_HOOKS NONGKI_4_4_MODE
#   TOOLCHAIN TOOLCHAIN_VERSION LLVM LLVM_IAS CROSS_COMPILE CROSS_COMPILE_ARM32 CLANG_URL GCC_URL
#   PATCH_PROFILE UPSTREAM_PROFILE LTO_PLUS SCHEDULER_PROFILE KERNEL_NAME EXTRA_MAKE_ARGS
#   PACKAGE_ANYKERNEL ANYKERNEL_PROFILE ANYKERNEL3_REPO ANYKERNEL3_REF
#   USE_CCACHE CCACHE_DIR TOOLCHAIN_CACHE_DIR KERNEL_SOURCE_SEED WORK_DIR
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/tg.sh"
CI_LOG_TAG=build

# Resolve a canonical target profile once; explicit environment overrides remain authoritative.
if [[ -n "${BUILD_PROFILE:-}" ]]; then
  eval "$(BUILD_PROFILE="$BUILD_PROFILE" DEVICE="${DEVICE:-generic}" KERNEL_FAMILY="${KERNEL_FAMILY:-}" "$SCRIPT_DIR/resolve_build_profile.sh")"
elif [[ -z "${PROFILE_ID:-}" ]]; then
  # Auto-select when DEVICE/FAMILY identify one canonical target.
  if [[ -n "${DEVICE:-}" && "${DEVICE:-generic}" != generic ]]; then
    BUILD_PROFILE="auto"
    eval "$(BUILD_PROFILE=auto DEVICE="$DEVICE" KERNEL_FAMILY="${KERNEL_FAMILY:-}" "$SCRIPT_DIR/resolve_build_profile.sh")"
  fi
fi
BUILD_PROFILE_LABEL="${PROFILE_ID:-${BUILD_PROFILE:-unknown}}"
BUILD_PROFILE="$BUILD_PROFILE_LABEL"

KERNEL_REPO="${KERNEL_REPO:-${PROFILE_KERNEL_REPO:-}}"
: "${KERNEL_REPO:?KERNEL_REPO is required}"

KERNEL_BRANCH="${KERNEL_BRANCH:-${PROFILE_KERNEL_REF:-main}}"
KERNEL_BRANCH="${KERNEL_BRANCH#refs/heads/}"
KERNEL_BRANCH="${KERNEL_BRANCH#refs/tags/}"
KERNEL_REF_TYPE="${KERNEL_REF_TYPE:-${PROFILE_KERNEL_REF_TYPE:-auto}}"
DEVICE="${DEVICE:-${PROFILE_DEVICE:-generic}}"
KERNEL_FAMILY="${KERNEL_FAMILY:-${PROFILE_KERNEL_FAMILY:-}}"
ARCH="${ARCH:-${PROFILE_ARCH:-auto}}"
DEFCONFIG="${DEFCONFIG:-${PROFILE_DEFCONFIG:-auto}}"
CONFIG_FRAGMENT="${CONFIG_FRAGMENT:-${PROFILE_CONFIG_FRAGMENT:-auto}}"
JOBS="${JOBS:-0}"
KERNEL_TARGET="${KERNEL_TARGET:-}"

TOOLCHAIN="${TOOLCHAIN:-auto}"
TOOLCHAIN_VERSION="${TOOLCHAIN_VERSION:-auto}"
LLVM="${LLVM:-auto}"
LLVM_IAS="${LLVM_IAS:-auto}"
CROSS_COMPILE="${CROSS_COMPILE:-auto}"
CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32:-}"
CLANG_URL="${CLANG_URL:-}"
GCC_URL="${GCC_URL:-}"
EXTRA_MAKE_ARGS="${EXTRA_MAKE_ARGS:-}"

SCHEDULER_PROFILE="${SCHEDULER_PROFILE:-${PROFILE_SCHEDULER_PROFILE:-auto}}"
PATCH_PROFILE="${PATCH_PROFILE:-${PROFILE_PATCH_PROFILE:-auto}}"
UPSTREAM_PROFILE="${UPSTREAM_PROFILE:-${PROFILE_UPSTREAM_PROFILE:-auto}}"
LTO_PLUS="${LTO_PLUS:-${PROFILE_LTO_PLUS:-false}}"
KERNEL_NAME="${KERNEL_NAME:-}"
# PATCH_PROFILE=southwest-ng also labels the scheduler profile (keeps workflow inputs <= 25).
if [[ "$PATCH_PROFILE" == "southwest-ng" && "$SCHEDULER_PROFILE" == "auto" ]]; then
  SCHEDULER_PROFILE="southwest-ng"
fi

# Root variant. ROOT_VARIANT is the single switch; ENABLE_KSU/KSU_PROVIDER stay
# accepted for older callers.
if [[ -n "${ROOT_VARIANT:-}" ]]; then
  ROOT_VARIANT="$(normalize_variant "$ROOT_VARIANT")" || ci_die "invalid ROOT_VARIANT=$ROOT_VARIANT"
else
  case "${ENABLE_KSU:-false}:${KSU_PROVIDER:-auto}" in
    false:*|0:*|"":*) ROOT_VARIANT=vanilla ;;
    *:auto) ROOT_VARIANT=kernelsu-next ;;
    *) ROOT_VARIANT="$(normalize_variant "$KSU_PROVIDER")" || ci_die "invalid KSU_PROVIDER=$KSU_PROVIDER" ;;
  esac
fi
KSU_REPO="${KSU_REPO:-}"
KSU_REF="${KSU_REF:-auto}"
KSU_HOOK_MODE="${KSU_HOOK_MODE:-auto}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
SUSFS_REF="${SUSFS_REF:-001e69919c6271f690fd00b17e4c721c9e599152}"
[[ "$ROOT_VARIANT" == vanilla ]] && ENABLE_SUSFS=false

PACKAGE_ANYKERNEL="${PACKAGE_ANYKERNEL:-${PROFILE_PACKAGE_ANYKERNEL:-true}}"
ANYKERNEL_PROFILE="${ANYKERNEL_PROFILE:-${PROFILE_ANYKERNEL_PROFILE:-auto}}"
ANYKERNEL3_REPO="${ANYKERNEL3_REPO:-local}"
ANYKERNEL3_REF="${ANYKERNEL3_REF:-${PROFILE_ANYKERNEL3_REF:-master}}"
USE_CCACHE="${USE_CCACHE:-true}"
ROM_FAMILY="${ROM_FAMILY:-${PROFILE_ROM_FAMILY:-auto}}"
DYNAMIC_PARTITION="${DYNAMIC_PARTITION:-${PROFILE_DYNAMIC_PARTITION:-false}}"
GKI="${GKI:-${PROFILE_GKI:-false}}"
SOURCE_LABEL="${SOURCE_LABEL:-${PROFILE_SOURCE_LABEL:-}}"
KSU_NEXT_4_4_REF="${KSU_NEXT_4_4_REF:-${PROFILE_KSU_NEXT_4_4_REF:-v1.1.1}}"
KSU_NEXT_LEGACY_REF="${KSU_NEXT_LEGACY_REF:-${PROFILE_KSU_NEXT_LEGACY_REF:-v3.4.0}}"
KSU_NEXT_GKI_REF="${KSU_NEXT_GKI_REF:-${PROFILE_KSU_NEXT_GKI_REF:-v3.4.0}}"
RESUKISU_REF_DEFAULT="${RESUKISU_REF_DEFAULT:-${PROFILE_RESUKISU_REF:-v4.2.0-rc3}}"
SUKISU_ULTRA_REF_DEFAULT="${SUKISU_ULTRA_REF_DEFAULT:-${PROFILE_SUKISU_ULTRA_REF:-main}}"
ROOT_MANAGER_SOURCE_ROOT="${ROOT_MANAGER_SOURCE_ROOT:-$CI_ROOT/third_party/root-managers}"
ROOT_MANAGER_SOURCE_MODE="${ROOT_MANAGER_SOURCE_MODE:-auto}"
NONGKI_4_4_HOOKS="${NONGKI_4_4_HOOKS:-${PROFILE_NONGKI_4_4_HOOKS:-auto}}"
NONGKI_4_4_MODE="${NONGKI_4_4_MODE:-${PROFILE_NONGKI_4_4_MODE:-auto}}"

BUILD_ENV="${BUILD_ENV:-}"
RUN_URL="${RUN_URL:-}"

START="$(date +%s)"
WORK="${WORK_DIR:-$PWD/work}"
SRC_DIR="$WORK/kernel"
OUT="${KERNEL_OUT:-$WORK/kernel-out}"
ARTIFACTS="$WORK/artifacts"
BUILD_LOG="$WORK/build.log"
INFO="$ARTIFACTS/build-info.txt"
CI_BUILD_SHA="${CI_BUILD_SHA:-$(git -C "$CI_ROOT" rev-parse HEAD 2>/dev/null || true)}"
HARNESS_EXECUTION_ID="${HARNESS_EXECUTION_ID:-}"
GH_TOKEN="${GH_TOKEN:-}"
GH_REPOSITORY="${GH_REPOSITORY:-}"
CI_ARTIFACT_STAGE="${CI_ARTIFACT_STAGE:-false}"
CI_ARTIFACT_RELEASE_TAG="${CI_ARTIFACT_RELEASE_TAG:-}"
PROGRESS_SCRIPT="$SCRIPT_DIR/progress_beacon.sh"

rm -rf "$ARTIFACTS"
mkdir -p "$WORK" "$ARTIFACTS"
: > "$BUILD_LOG"
export CI_HEARTBEAT_SECONDS="${CI_HEARTBEAT_SECONDS:-15}"

# Harness workspaces can lose executable bits; every helper is invoked via bash anyway.
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

# Kbuild identity (KBUILD_BUILD_USER/HOST) and kernel name.
source "$SCRIPT_DIR/kbuild_identity.sh"
if [[ -z "$KERNEL_NAME" || "$KERNEL_NAME" == "auto" ]]; then
  KERNEL_NAME="$(read_value_file "$CI_ROOT/kernel-name")"
fi

ci_phase() { echo "[CI-PHASE] $1" | tee -a "$BUILD_LOG"; }

progress_update() {
  local pct="$1" phase="$2" detail="$3" state="${4:-pending}"
  [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" && -n "${TG_MESSAGE_ID:-}" ]] || \
    { [[ "${CI_GITHUB_STATUS_ENABLED:-false}" == "true" && -n "$GH_TOKEN" && -n "$GH_REPOSITORY" && -n "$CI_BUILD_SHA" ]] || return 0; }
  TG_BOT_TOKEN="$TG_BOT_TOKEN" TG_CHAT_ID="$TG_CHAT_ID" TG_TOPIC_ID="$TG_TOPIC_ID" TG_REQUIRE_TOPIC="${TG_REQUIRE_TOPIC:-false}" TG_MESSAGE_ID="$TG_MESSAGE_ID" \
  TG_START_TIME="$START" GH_TOKEN="$GH_TOKEN" GH_REPOSITORY="$GH_REPOSITORY" CI_BUILD_SHA="$CI_BUILD_SHA" \
  CI_GITHUB_STATUS_ENABLED="${CI_GITHUB_STATUS_ENABLED:-false}" HARNESS_EXECUTION_ID="$HARNESS_EXECUTION_ID" \
  RUN_URL="$RUN_URL" WORK_DIR="$WORK" BUILD_LOG="$BUILD_LOG" BUILD_PROFILE="$BUILD_PROFILE_LABEL" DEVICE="$DEVICE" ROOT_VARIANT="$ROOT_VARIANT" \
    bash "$PROGRESS_SCRIPT" "$pct" "$state" "$phase${VARIANT_TAG:+ [$VARIANT_TAG]}" "$detail" || true
}
VARIANT_TAG="${VARIANT_PROGRESS_TAG:-}"

stage_artifacts() {
  local dir="$1"
  if ! is_true "$CI_ARTIFACT_STAGE"; then
    return 0
  fi
  if [[ -z "$GH_TOKEN" || -z "$GH_REPOSITORY" || -z "$CI_ARTIFACT_RELEASE_TAG" ]]; then
    echo "[release-stage] skipped: GitHub release staging credentials/tag unavailable" >> "$BUILD_LOG"
    return 0
  fi
  GH_TOKEN="$GH_TOKEN" GH_REPOSITORY="$GH_REPOSITORY" RELEASE_TAG="$CI_ARTIFACT_RELEASE_TAG" \
    ASSET_DIR="$dir" \
    ASSET_PREFIX="staging-${BUILD_PROFILE}-${ROOT_VARIANT}" \
    CI_RELEASE_STATE_DIR="${CI_RELEASE_STATE_DIR:-$WORK/zairenkai-release-state}" \
    bash "$SCRIPT_DIR/stage_ci_release_assets.sh" >> "$BUILD_LOG" 2>&1 || \
    echo "[release-stage] warning: immediate artifact staging failed for $(basename "$dir")" | tee -a "$BUILD_LOG" >&2
}

run_live() {
  local label="$1"
  shift
  bash "$SCRIPT_DIR/run_with_heartbeat.sh" "$label" "$BUILD_LOG" "$@" 2> >(tee -a "$BUILD_LOG" >&2)
}

# run_helper <script> [VAR=value...]: run a helper script, logging its output.
run_helper() {
  local script="$1"
  shift
  env "$@" bash "$SCRIPT_DIR/$script" 2>&1 | tee -a "$BUILD_LOG"
  return "${PIPESTATUS[0]}"
}

info() { printf '%s=%s\n' "$1" "$2" >> "$INFO"; }

FAIL_HANDLED=false
write_failure_reports() {
  local reason="$1"
  local summary="$WORK/failure-summary.txt"
  local full_log="$WORK/failure-build.log"
  local compressed="$WORK/failure-build.log.gz"
  {
    printf 'Zairenkai kernel build failure\n'
    printf 'profile=%s\n' "${BUILD_PROFILE:-unknown}"
    printf 'device=%s\n' "${DEVICE:-unknown}"
    printf 'kernel_family=%s\n' "${KERNEL_FAMILY:-unknown}"
    printf 'variant=%s\n' "${ROOT_VARIANT:-unknown}"
    printf 'kernel_repo=%s\n' "${KERNEL_REPO:-unknown}"
    printf 'kernel_ref=%s\n' "${KERNEL_BRANCH:-unknown}"
    printf 'reason=%s\n' "$reason"
    printf 'exit_context=see full build log\n\n'
    echo '=== Extracted diagnostics ==='
    if ! grep -nEi '(fatal error:|error:|undefined reference|no rule to make target|recipe for target.*failed|killed|out of memory|oom|segmentation fault|cannot find|not found|permission denied|make(\[[0-9]+\])?: \\*\*\*|error [0-9]+)' "$BUILD_LOG" | tail -n 120; then
      echo '(no canonical compiler/make diagnostic matched)'
    fi
    echo
    echo '=== Last 500 log lines ==='
    tail -n 500 "$BUILD_LOG" || true
  } > "$summary" 2>/dev/null || true
  cp -f "$BUILD_LOG" "$full_log" 2>/dev/null || true
  if [[ -f "$full_log" ]]; then
    gzip -c "$full_log" > "$compressed" 2>/dev/null || true
  fi

  # Mirror failure diagnostics into ARTIFACTS so Harness persistence and the
  # GitHub Actions handoff can retrieve failed-build evidence exactly like a
  # successful package. The build itself remains failed.
  mkdir -p "$ARTIFACTS"
  cp -f "$summary" "$ARTIFACTS/failure-summary.txt" 2>/dev/null || true
  [[ -f "$compressed" ]] && cp -f "$compressed" "$ARTIFACTS/failure-build.log.gz" 2>/dev/null || true
  printf 'status=FAILED\nprofile=%s\ndevice=%s\nvariant=%s\nreason=%s\n' \
    "${BUILD_PROFILE:-unknown}" "${DEVICE:-unknown}" "${ROOT_VARIANT:-unknown}" "$reason" \
    > "$ARTIFACTS/build-result.txt" 2>/dev/null || true
}

fail() {
  local reason="$1"
  [[ "$FAIL_HANDLED" == true ]] && exit 1
  FAIL_HANDLED=true
  local duration=$(( $(date +%s) - START ))
  echo "[build] FAILED: $reason" | tee -a "$BUILD_LOG" >&2
  write_failure_reports "$reason"
  # Persist failure artifacts immediately. This must not depend on the final
  # matrix status or release-publication flag.
  stage_artifacts "$ARTIFACTS" || true
  echo "===== FAILURE DIAGNOSTICS =====" | tee -a "$BUILD_LOG" >&2
  cat "$WORK/failure-summary.txt" 2>/dev/null | tee -a "$BUILD_LOG" >&2 || true
  local diag
  diag="$(grep -nEi '(fatal error:|error:|undefined reference|no rule to make target|recipe for target.*failed|killed|out of memory|oom|cannot find|not found|permission denied|make(\[[0-9]+\])?: \\*\*\*)' "$WORK/failure-summary.txt" 2>/dev/null | tail -n 8 | sed -E 's/^[0-9]+://g' | tr '\n' ' ' | cut -c1-900 || true)"
  [[ -n "$diag" ]] || diag="${reason}"
  tg_edit "${MID:-}" "❌ <b>Zairenkai Build gagal</b>
🧭 Target: <code>${BUILD_PROFILE:-unknown}</code>
📱 <code>$DEVICE</code> | 🔐 <code>$(variant_label "$ROOT_VARIANT")</code>
🧩 Tahap: <code>$reason</code>
🚨 <code>$(printf '%s' "$diag" | python3 -c 'import html,sys; print(html.escape(sys.stdin.read()))')</code>
⏱ $(fmt_dur "$duration")
🔗 <a href=\"$RUN_URL\">CI log</a>" || true
  if is_true "${TG_SEND_FAILURE_ARTIFACTS:-true}"; then
    tg_file "$WORK/failure-summary.txt" "🚨 Failure diagnostics — ${BUILD_PROFILE_LABEL} — $DEVICE $(variant_label "$ROOT_VARIANT")" || true
    if [[ -f "$WORK/failure-build.log.gz" ]]; then
      tg_file "$WORK/failure-build.log.gz" "📦 Full build log (gzip) — ${BUILD_PROFILE_LABEL} — $DEVICE $(variant_label "$ROOT_VARIANT")" || true
    fi
  fi
  exit 1
}
trap 'fail "unexpected error at line $LINENO"' ERR

[[ "$JOBS" == "0" || -z "$JOBS" ]] && JOBS="$(nproc 2>/dev/null || echo 2)"
[[ -n "$KERNEL_BRANCH" ]] || fail "KERNEL_BRANCH is empty"
[[ -n "$DEVICE" && "$DEVICE" != "generic" ]] || fail "DEVICE is missing or still 'generic'"

# ------------------------------------------------------------
# Source checkout (KERNEL_SOURCE_SEED = pristine clone shared by variants)
# ------------------------------------------------------------
rm -rf "$SRC_DIR"
if [[ "$KERNEL_REF_TYPE" == auto ]]; then
  if is_commit_ref "$KERNEL_BRANCH"; then KERNEL_REF_TYPE=commit; else KERNEL_REF_TYPE=branch; fi
fi
case "$KERNEL_REF_TYPE" in branch|tag|commit) ;; *) fail "invalid KERNEL_REF_TYPE=$KERNEL_REF_TYPE" ;; esac

if [[ -n "${KERNEL_SOURCE_SEED:-}" && -d "$KERNEL_SOURCE_SEED/.git" ]]; then
  cp -a "$KERNEL_SOURCE_SEED" "$SRC_DIR"
  git -C "$SRC_DIR" reset -q --hard
  git -C "$SRC_DIR" clean -qfdx
else
  git_fetch_ref "$KERNEL_REPO" "$KERNEL_BRANCH" "$SRC_DIR" || fail "clone kernel"
fi

cd "$SRC_DIR"
ci_phase "source-checkout"
progress_update 5 "source" "checkout complete"
COMMIT="$(git log -1 --pretty='%h %s')"
COMMIT_SHA="$(git rev-parse HEAD)"

# ------------------------------------------------------------
# Auto-detect architecture / defconfig / fragment
# ------------------------------------------------------------
DETECT_ENV="$WORK/detection.env"
bash "$SCRIPT_DIR/detect_defconfig.sh" \
  --repo "$SRC_DIR" --arch "$ARCH" --device "$DEVICE" \
  --defconfig "$DEFCONFIG" --fragment "$CONFIG_FRAGMENT" \
  > "$DETECT_ENV" 2> >(tee -a "$BUILD_LOG" >&2) || fail "auto-detect"
source "$DETECT_ENV"
KMM="$DETECTED_KERNEL_VERSION"

SELECTED_FRAGMENT=""
if [[ -n "${DETECTED_FRAGMENT:-}" ]]; then
  SELECTED_FRAGMENT="$SRC_DIR/arch/$DETECTED_ARCH/configs/$DETECTED_FRAGMENT"
  [[ -f "$SELECTED_FRAGMENT" ]] || fail "detected fragment missing"
fi

if [[ -n "$BUILD_ENV" ]]; then
  eval "$BUILD_ENV"
fi

# ------------------------------------------------------------
# Root provider integration
#
# Root integration is explicit. A tree that already carries a provider is
# built with it compiled out for the vanilla variant, and has it replaced by
# the requested provider for root variants.
# ------------------------------------------------------------
KSU_PREINTEGRATED=false
if grep -qE 'kernelsu' "$SRC_DIR/drivers/Makefile" 2>/dev/null ||
   grep -qE '^CONFIG_KSU=(y|m)' "$SRC_DIR/arch/$DETECTED_ARCH/configs/$DETECTED_DEFCONFIG" ${SELECTED_FRAGMENT:+"$SELECTED_FRAGMENT"} 2>/dev/null; then
  KSU_PREINTEGRATED=true
fi

if [[ "$ROOT_VARIANT" == vanilla ]]; then
  KSU_REQUIRED=false
  KSU_PROVIDER=none
  KSU_REPO="" KSU_REF="" KSU_PROVIDER_COMMIT=none KSU_PROVIDER_VERSION=none KSU_LAYOUT_RESOLVED=none
else
  KSU_REQUIRED=true
  ci_phase "root-provider"
  run_helper root_manager_apply.sh \
    SOURCE_DIR="$SRC_DIR" WORK_DIR="$WORK" KERNEL_VERSION="$KMM" ROOT_MANAGER="$ROOT_VARIANT" \
    KSU_REPO="$KSU_REPO" KSU_REF="$KSU_REF" ENABLE_SUSFS="$ENABLE_SUSFS" KSU_HOOK_MODE="$KSU_HOOK_MODE" \
    KSU_NEXT_4_4_REF="$KSU_NEXT_4_4_REF" KSU_NEXT_LEGACY_REF="$KSU_NEXT_LEGACY_REF" KSU_NEXT_GKI_REF="$KSU_NEXT_GKI_REF" \
    RESUKISU_REF_DEFAULT="$RESUKISU_REF_DEFAULT" SUKISU_ULTRA_REF_DEFAULT="$SUKISU_ULTRA_REF_DEFAULT" \
    ROOT_MANAGER_SOURCE_ROOT="$ROOT_MANAGER_SOURCE_ROOT" ROOT_MANAGER_SOURCE_MODE="$ROOT_MANAGER_SOURCE_MODE" ||
    fail "root provider integration ($ROOT_VARIANT)"
  source "$WORK/root-manager.env"
  KSU_HOOK_MODE="$KSU_HOOK_MODE_RESOLVED"
fi

SUSFS_COMMIT=none SUSFS_VERSION=none SUSFS_SOURCE=none
NONGKI_4_4_ENABLED=false NONGKI_4_4_UPSTREAM_COMMIT=none NONGKI_4_4_MODE_RESOLVED=none NONGKI_4_4_HOOK_BLOB=none
if is_true "$ENABLE_SUSFS"; then
  ENABLE_SUSFS=true
  run_helper apply_susfs.sh \
    SOURCE_DIR="$SRC_DIR" WORK_DIR="$WORK" KERNEL_VERSION="$KMM" ROOT_MANAGER="$KSU_PROVIDER" \
    ENABLE_SUSFS=true SUSFS_REF="$SUSFS_REF" KSU_DIR="${KSU_DIR:-}" || fail "SUSFS integration"
  source "$WORK/susfs.env"
else
  ENABLE_SUSFS=false
fi

# ------------------------------------------------------------
# Legacy NonGKI hook integration
#
# Lavender 4.4 is non-GKI. Root variants receive the upstream 4.4-tested
# syscall hook layer automatically; SUSFS switches the hook layer to the
# upstream inline implementation after the dedicated SUSFS patch succeeds.
# ------------------------------------------------------------
if [[ "$DEVICE" == "lavender" && "$KMM" == 4.4* && "$ROOT_VARIANT" != "vanilla" ]] && is_true "$NONGKI_4_4_HOOKS"; then
  ci_phase "nongki-4.4-hooks"
  run_helper apply_nongki_4_4.sh \
    SOURCE_DIR="$SRC_DIR" WORK_DIR="$WORK" DEVICE="$DEVICE" KERNEL_VERSION="$KMM" \
    ROOT_MANAGER="$KSU_PROVIDER" ENABLE_SUSFS="$ENABLE_SUSFS" \
    NONGKI_4_4_HOOKS="$NONGKI_4_4_HOOKS" NONGKI_4_4_MODE="$NONGKI_4_4_MODE" \
    DEFCONFIG_FILE="$SRC_DIR/arch/$DETECTED_ARCH/configs/$DETECTED_DEFCONFIG" \
    KPM_ENABLE="${KPM_ENABLE:-false}" || fail "NonGKI 4.4 hook integration"
  source "$WORK/nongki-4.4.env"
  NONGKI_4_4_ENABLED=true
  NONGKI_4_4_UPSTREAM_COMMIT="$NONGKI_4_4_UPSTREAM_COMMIT"
  NONGKI_4_4_MODE_RESOLVED="$NONGKI_4_4_MODE"
else
  NONGKI_4_4_ENABLED=false
fi

# ------------------------------------------------------------
# Modular patch registry (source phase)
# ------------------------------------------------------------
PATCH_ENV=(
  SOURCE_DIR="$SRC_DIR" DEVICE="$DEVICE" KERNEL_VERSION="$KMM" KERNEL_REPO="$KERNEL_REPO"
  PATCH_PROFILE="$PATCH_PROFILE" UPSTREAM_PROFILE="$UPSTREAM_PROFILE"
  ROOT_MANAGER="$KSU_PROVIDER" KSU_REQUIRED="$KSU_REQUIRED" KSU_PREINTEGRATED="$KSU_PREINTEGRATED"
  ENABLE_SUSFS="$ENABLE_SUSFS" KSU_SUSFS_REQUIRED="$ENABLE_SUSFS" LTO_PLUS="$LTO_PLUS"
)
ci_phase "config-patches"
run_helper apply_patch_series.sh "${PATCH_ENV[@]}" PHASE=source || fail "source patch series"
progress_update 12 "config" "patch selection complete"

# ------------------------------------------------------------
# Toolchain
# ------------------------------------------------------------
TOOLCHAIN_ENV="$WORK/toolchain.env"
TOOLCHAIN="$TOOLCHAIN" TOOLCHAIN_VERSION="$TOOLCHAIN_VERSION" ARCH="$DETECTED_ARCH" \
CLANG_URL="$CLANG_URL" GCC_URL="$GCC_URL" \
  bash "$SCRIPT_DIR/toolchain_resolver.sh" "$SRC_DIR" "$WORK" \
  > "$TOOLCHAIN_ENV" 2> >(tee -a "$BUILD_LOG" >&2) || fail "toolchain resolution"
source "$TOOLCHAIN_ENV"
progress_update 24 "toolchain" "$RESOLVED_TOOLCHAIN $RESOLVED_TOOLCHAIN_VERSION"

# Inherited compiler overrides must not leak into Kbuild.
unset CC CXX CPP LD AS AR NM OBJCOPY OBJDUMP READELF OBJSIZE STRIP HOSTCC HOSTCXX MAKEFLAGS MAKEOVERRIDES
[[ -n "${RESOLVED_TOOLCHAIN_BIN:-}" ]] && export PATH="$RESOLVED_TOOLCHAIN_BIN:$PATH"

if [[ -n "$CROSS_COMPILE" && "$CROSS_COMPILE" != auto ]]; then
  CROSS_DEFAULT="$CROSS_COMPILE"
else
  CROSS_DEFAULT="$RESOLVED_CROSS_DEFAULT"
fi
CLANG_TRIPLE="${RESOLVED_CLANG_TRIPLE:-}"
[[ "$CROSS_COMPILE_ARM32" == auto ]] && CROSS_COMPILE_ARM32=""
if [[ "$DETECTED_ARCH" == arm64 && -z "$CROSS_COMPILE_ARM32" ]] && command -v arm-linux-gnueabi-gcc >/dev/null 2>&1; then
  CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
fi

LLVM_VALUE="${RESOLVED_LLVM:-1}"
LLVM_IAS_VALUE="${RESOLVED_LLVM_IAS:-0}"
[[ "$LLVM" != auto ]] && LLVM_VALUE="$LLVM"
[[ "$LLVM_IAS" != auto ]] && LLVM_IAS_VALUE="$LLVM_IAS"
is_true "$LLVM_VALUE" && LLVM_VALUE=1 || LLVM_VALUE=0
is_true "$LLVM_IAS_VALUE" && LLVM_IAS_VALUE=1 || LLVM_IAS_VALUE=0

# ccache (shared CCACHE_DIR lets KernelSU variants reuse the vanilla objects).
CCACHE_PREFIX=""
if is_true "$USE_CCACHE" && command -v ccache >/dev/null 2>&1; then
  export CCACHE_DIR="${CCACHE_DIR:-$WORK/.ccache}"
  export CCACHE_BASEDIR="${CCACHE_BASEDIR:-$WORK}"
  export CCACHE_NOHASHDIR=true CCACHE_COMPILERCHECK=content
  export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-$(git -C "$SRC_DIR" log -1 --format=%cd --date=rfc2822)}"
  ccache -M "${CCACHE_MAXSIZE:-5G}" >/dev/null 2>&1 || true
  CCACHE_PREFIX="ccache "
fi

# ------------------------------------------------------------
# Make command
#
# Kernels with LLVM=1 support (5.7+, or backported) select every LLVM tool
# themselves. Older trees (4.4/4.9/4.14/4.19) need CC=clang explicitly; 4.19
# can also use LLVM binutils, while 4.4-4.14 keep GNU binutils from CROSS_COMPILE.
# ------------------------------------------------------------
MAKE_CMD=(make -j"$JOBS" O="$OUT" ARCH="$DETECTED_ARCH")
if [[ "$LLVM_VALUE" == 1 ]]; then
  if grep -qE '\$\(LLVM\)' "$SRC_DIR/Makefile"; then
    MAKE_CMD+=(LLVM=1)
    [[ "$LLVM_IAS_VALUE" == 1 ]] && MAKE_CMD+=(LLVM_IAS=1)
    [[ -n "$CCACHE_PREFIX" ]] && MAKE_CMD+=(CC="${CCACHE_PREFIX}clang")
  else
    MAKE_CMD+=(CC="${CCACHE_PREFIX}clang")
    if kernel_ge "$KMM" 4 19; then
      MAKE_CMD+=(LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip)
    fi
  fi
  [[ -n "$CLANG_TRIPLE" ]] && MAKE_CMD+=(CLANG_TRIPLE="$CLANG_TRIPLE")
elif [[ -n "$CCACHE_PREFIX" ]]; then
  MAKE_CMD+=(CC="${CCACHE_PREFIX}${CROSS_DEFAULT}gcc")
fi
[[ -n "$CROSS_DEFAULT" ]] && MAKE_CMD+=(CROSS_COMPILE="$CROSS_DEFAULT")
[[ -n "$CROSS_COMPILE_ARM32" ]] && MAKE_CMD+=(CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" CROSS_COMPILE_COMPAT="$CROSS_COMPILE_ARM32")
# GCC 10+ defaults to -fno-common, which breaks the dtc lexer in older trees.
kernel_ge "$KMM" 5 4 || MAKE_CMD+=(HOSTCC="gcc -fcommon")
read -r -a EXTRA_ARGS <<< "$EXTRA_MAKE_ARGS"
MAKE_CMD+=("${EXTRA_ARGS[@]}")

VARIANT_LABEL="$(variant_label "$ROOT_VARIANT")"
PROJECT_MAINTAINER="${MAINTAINER:-Febrian Rahmad Cahya}"
MID="$(tg_msg "🚀 <b>Zairenkai Kernel Build</b>
🧭 Target: <code>$BUILD_PROFILE_LABEL</code>
📱 Device: <code>$DEVICE</code> | 🔐 <code>$VARIANT_LABEL</code>
🐧 Kernel: <code>$DETECTED_KERNEL_FULL_VERSION</code> (<code>$DETECTED_ARCH</code>)
🌿 Branch: <code>$KERNEL_BRANCH</code>
⚙️ Defconfig: <code>$DETECTED_DEFCONFIG</code>
🧩 Fragment: <code>${DETECTED_FRAGMENT:-none}</code>
🛠 Toolchain: <code>$RESOLVED_TOOLCHAIN $RESOLVED_TOOLCHAIN_VERSION</code>
🧵 Jobs: <code>$JOBS</code>
🔗 <a href=\"$RUN_URL\">CI log</a>")" || MID=""

for kv in \
  "device=$DEVICE" "arch=$DETECTED_ARCH" "kernel_version=$KMM" "kernel_full_version=$DETECTED_KERNEL_FULL_VERSION" \
  "kernel_repo=$KERNEL_REPO" "ref_type=$KERNEL_REF_TYPE" "ref=$KERNEL_BRANCH" "commit=$COMMIT" "commit_sha=$COMMIT_SHA" \
  "ci_build_sha=$CI_BUILD_SHA" "build_profile=${BUILD_PROFILE:-$PROFILE_ID}" "kernel_family=$KERNEL_FAMILY" \
  "dynamic_partition=$DYNAMIC_PARTITION" "gki=$GKI" "source_label=$SOURCE_LABEL" \
  "defconfig=$DETECTED_DEFCONFIG" "fragment=${DETECTED_FRAGMENT:-}" \
  "toolchain=$RESOLVED_TOOLCHAIN" "toolchain_version=$RESOLVED_TOOLCHAIN_VERSION" "compiler=$RESOLVED_COMPILER_STRING" \
  "llvm=$LLVM_VALUE" "llvm_ias=$LLVM_IAS_VALUE" "clang_triple=$CLANG_TRIPLE" "cross_compile=$CROSS_DEFAULT" \
  "cross_compile_arm32=$CROSS_COMPILE_ARM32" "ccache=${CCACHE_PREFIX:+true}" \
  "scheduler_profile=$SCHEDULER_PROFILE" "patch_profile=$PATCH_PROFILE" "upstream_profile=$UPSTREAM_PROFILE" \
  "lto_plus=$LTO_PLUS" "kernel_name=$KERNEL_NAME" "build_user=$KBUILD_BUILD_USER" "build_host=$KBUILD_BUILD_HOST" "maintainer=$PROJECT_MAINTAINER" \
  "root_variant=$ROOT_VARIANT" "ksu_preintegrated=$KSU_PREINTEGRATED" "ksu_provider=$KSU_PROVIDER" \
  "ksu_repo=${KSU_REPO:-}" "ksu_ref=${KSU_REF:-}" "ksu_version=${KSU_PROVIDER_VERSION:-none}" \
  "ksu_commit=${KSU_PROVIDER_COMMIT:-none}" "ksu_layout=${KSU_LAYOUT_RESOLVED:-none}" "ksu_hook_mode=$KSU_HOOK_MODE" \
  "susfs_enabled=$ENABLE_SUSFS" "susfs_source=$SUSFS_SOURCE" "susfs_ref=$SUSFS_REF" \
  "nongki_4_4_enabled=$NONGKI_4_4_ENABLED" "nongki_4_4_mode=$NONGKI_4_4_MODE_RESOLVED" "nongki_4_4_commit=$NONGKI_4_4_UPSTREAM_COMMIT" "nongki_4_4_hook_blob=$NONGKI_4_4_HOOK_BLOB" \
  "susfs_commit=$SUSFS_COMMIT" "susfs_version=$SUSFS_VERSION"; do
  info "${kv%%=*}" "${kv#*=}"
done

echo "Kernel commit: $COMMIT" | tee -a "$BUILD_LOG"
echo "Make command: ${MAKE_CMD[*]}" | tee -a "$BUILD_LOG"

# ------------------------------------------------------------
# Configure
# ------------------------------------------------------------
rm -rf "$OUT"
mkdir -p "$OUT"

ci_phase "defconfig"
run_live "defconfig" "${MAKE_CMD[@]}" "$DETECTED_DEFCONFIG" || fail "defconfig"
progress_update 30 "defconfig" "$DETECTED_DEFCONFIG"

if [[ -n "$SELECTED_FRAGMENT" ]]; then
  if [[ -x "$SRC_DIR/scripts/kconfig/merge_config.sh" ]]; then
    # merge only (-m); dependencies are resolved by olddefconfig with the real toolchain.
    run_live "config-fragment-merge" "$SRC_DIR/scripts/kconfig/merge_config.sh" -m -O "$OUT" \
      "$OUT/.config" "$SELECTED_FRAGMENT" || fail "config fragment merge"
  else
    cat "$SELECTED_FRAGMENT" >> "$OUT/.config"
  fi
  run_live "config-fragment-olddefconfig" "${MAKE_CMD[@]}" olddefconfig || fail "config fragment olddefconfig"
  progress_update 35 "config" "fragment resolved"
elif [[ "$CONFIG_FRAGMENT" != none && "$CONFIG_FRAGMENT" != auto ]]; then
  fail "config fragment not resolved"
fi

run_helper apply_patch_series.sh "${PATCH_ENV[@]}" PHASE=config KERNEL_OUT="$OUT" || fail "config patch profile"
run_live "config-resolve" "${MAKE_CMD[@]}" olddefconfig || fail "olddefconfig after config patches"

# The selected provider/SUSFS symbols must survive config resolution.
if [[ "$KSU_REQUIRED" == true ]]; then
  grep -qE '^CONFIG_KSU=(y|m)' "$OUT/.config" || fail "CONFIG_KSU is not enabled after config resolution"
else
  ! grep -qE '^CONFIG_KSU=(y|m)' "$OUT/.config" || fail "vanilla variant still has CONFIG_KSU enabled"
fi
if [[ "$ENABLE_SUSFS" == true ]]; then
  grep -qE '^CONFIG_KSU_SUSFS=(y|m)' "$OUT/.config" || fail "CONFIG_KSU_SUSFS is not enabled after config resolution"
fi

ci_phase "kernel-name"
run_helper set_kernel_name.sh CONFIG_FILE="$OUT/.config" KERNEL_NAME="$KERNEL_NAME" || fail "kernel name"
run_helper sync_localversion_files.sh KERNEL_SRC="$SRC_DIR" || fail "localversion sync"
progress_update 41 "identity" "kernel name synchronized"

# Scheduler evidence (reporting only; the source/defconfig stays authoritative).
SCHEDULER_DETECTED="none"
if grep -qE '^CONFIG_SCHED_HMP=y' "$OUT/.config"; then
  SCHEDULER_DETECTED="HMP"
elif grep -qE '^CONFIG_SCHED_WALT=y' "$OUT/.config" && ! kernel_ge "$KMM" 4 14; then
  SCHEDULER_DETECTED="EAS"
elif grep -qE '^CONFIG_ENERGY_MODEL=y|^CONFIG_SCHED_TUNE=y|^CONFIG_SCHED_WALT=y|^CONFIG_UCLAMP_TASK=y' "$OUT/.config"; then
  SCHEDULER_DETECTED="EAS"
fi
info scheduler "$SCHEDULER_DETECTED"

# ------------------------------------------------------------
# Compile
# ------------------------------------------------------------
ci_phase "compile"
progress_update 44 "compile" "starting"
tg_edit "$MID" "🔨 <b>Compiling kernel…</b>
🧭 Target: <code>${BUILD_PROFILE_LABEL}</code>
📱 $DEVICE | 🔐 $VARIANT_LABEL | 🏗 $DETECTED_ARCH
⚙️ <code>$DETECTED_DEFCONFIG</code>
🛠 <code>$RESOLVED_TOOLCHAIN $RESOLVED_TOOLCHAIN_VERSION</code>
📊 Scheduler: <code>$SCHEDULER_DETECTED</code>
🧵 Jobs: <code>$JOBS</code>" || true

# Progress denominator: source-file estimate (never an unrestricted `make -n`).
COMPILE_TOTAL="$(git -C "$SRC_DIR" ls-files -- '*.c' '*.S' '*.s' 2>/dev/null | wc -l | tr -d ' ')"
info compile_plan_total "$COMPILE_TOTAL"
rm -f "$WORK/.stop-compile-telemetry"
TG_BOT_TOKEN="$TG_BOT_TOKEN" TG_CHAT_ID="$TG_CHAT_ID" TG_TOPIC_ID="$TG_TOPIC_ID" TG_REQUIRE_TOPIC="${TG_REQUIRE_TOPIC:-false}" TG_MESSAGE_ID="$MID" \
TG_START_TIME="$START" GH_TOKEN="$GH_TOKEN" GH_REPOSITORY="$GH_REPOSITORY" CI_BUILD_SHA="$CI_BUILD_SHA" \
BUILD_PROFILE="$BUILD_PROFILE_LABEL" CI_GITHUB_STATUS_ENABLED="${CI_GITHUB_STATUS_ENABLED:-false}" RUN_URL="$RUN_URL" \
DEVICE="$DEVICE" ROOT_VARIANT="$ROOT_VARIANT" VARIANT_LABEL="$VARIANT_LABEL" BUILD_LOG="$BUILD_LOG" \
  bash "$SCRIPT_DIR/compile_progress.sh" "$BUILD_LOG" "$COMPILE_TOTAL" "$WORK" "$PROGRESS_SCRIPT" &
COMPILE_TELEMETRY_PID=$!

# `if` keeps the ERR trap from firing so the telemetry cleanup below always runs.
if run_live "compile" "${MAKE_CMD[@]}" ${KERNEL_TARGET:+"$KERNEL_TARGET"}; then
  COMPILE_RC=0
else
  COMPILE_RC=$?
fi
touch "$WORK/.stop-compile-telemetry"
kill "$COMPILE_TELEMETRY_PID" 2>/dev/null || true
wait "$COMPILE_TELEMETRY_PID" 2>/dev/null || true
rm -f "$WORK/.stop-compile-telemetry"

if (( COMPILE_RC != 0 )); then
  progress_update 45 "compile" "kernel compilation failed" failure
  fail "compile: kernel compilation returned exit ${COMPILE_RC}"
fi
progress_update 90 "compile" "kernel compilation complete"

# ------------------------------------------------------------
# Collect artifacts
# ------------------------------------------------------------
ci_phase "artifacts"
BOOT_DIR="$OUT/arch/$DETECTED_ARCH/boot"
found_image=false
for img in Image.gz-dtb Image-dtb Image.gz Image.lz4 Image zImage-dtb zImage dtbo.img dtb.img; do
  if [[ -f "$BOOT_DIR/$img" ]]; then
    cp -f "$BOOT_DIR/$img" "$ARTIFACTS/$img"
    [[ "$img" == dtb* ]] || found_image=true
  fi
done
[[ "$found_image" == true ]] || fail "no kernel image produced in $BOOT_DIR"
# Separate DTB for trees that do not append it to the image.
if [[ ! -f "$ARTIFACTS/Image.gz-dtb" && ! -f "$ARTIFACTS/Image-dtb" && -d "$BOOT_DIR/dts" ]]; then
  mapfile -t DTBS < <(find "$BOOT_DIR/dts" -name "*${DEVICE}*.dtb" | sort)
  ((${#DTBS[@]})) && cat "${DTBS[@]}" > "$ARTIFACTS/dtb"
fi
cp -f "$OUT/.config" "$ARTIFACTS/kernel.config"
[[ -f "$OUT/System.map" ]] && cp -f "$OUT/System.map" "$ARTIFACTS/System.map"

KERNEL_RELEASE="$(cat "$OUT/include/config/kernel.release" 2>/dev/null || true)"
info kernel_release "$KERNEL_RELEASE"
info duration_seconds "$(( $(date +%s) - START ))"

# Per-variant changelog is part of every build artifact.
CHANGELOG="$ARTIFACTS/changelog.md"
BUILD_INFO="$INFO" SOURCE_DIR="$SRC_DIR" VARIANT="$ROOT_VARIANT" OUT_FILE="$CHANGELOG" \
  bash "$SCRIPT_DIR/generate_changelog.sh" single

ARCHIVE_NAME="Kernel-$DEVICE-$KMM-$ROOT_VARIANT-$(date -u +%Y%m%d).tar.gz"
ARCHIVE_TMP="$WORK/$ARCHIVE_NAME"
ARCHIVE="$ARTIFACTS/$ARCHIVE_NAME"
rm -f "$ARCHIVE_TMP" "$ARCHIVE"
tar -czf "$ARCHIVE_TMP" -C "$ARTIFACTS" .
cp -f "$ARCHIVE_TMP" "$ARCHIVE"
rm -f "$ARCHIVE_TMP"
progress_update 94 "artifacts" "collected"

# ------------------------------------------------------------
# AnyKernel3 package
# ------------------------------------------------------------
ANYKERNEL_ZIP=""
if is_true "$PACKAGE_ANYKERNEL"; then
  ci_phase "anykernel"
  AK_ENV="$WORK/anykernel.env"
  WORK_DIR="$WORK" ARTIFACT_DIR="$ARTIFACTS" OUTPUT_DIR="$ARTIFACTS" DEVICE="$DEVICE" KERNEL_VERSION="$KMM" \
  ANYKERNEL_PROFILE="$ANYKERNEL_PROFILE" ROOT_VARIANT="$ROOT_VARIANT" KERNEL_NAME="$KERNEL_NAME" \
  KERNEL_RELEASE="$KERNEL_RELEASE" SCHEDULER="$SCHEDULER_DETECTED" TOOLCHAIN="$RESOLVED_COMPILER_STRING" \
  MAINTAINER="$PROJECT_MAINTAINER" KBUILD_BUILD_USER="$KBUILD_BUILD_USER" KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST" \
  SOURCE="$(basename "$KERNEL_REPO" .git)" ANYKERNEL3_REPO="$ANYKERNEL3_REPO" ANYKERNEL3_REF="$ANYKERNEL3_REF" \
    bash "$SCRIPT_DIR/build_anykernel.sh" > "$AK_ENV" 2> >(tee -a "$BUILD_LOG" >&2) || fail "AnyKernel3 packaging"
  source "$AK_ENV"
  info anykernel_profile "$ANYKERNEL_PROFILE"
  info anykernel_zip "$(basename "$ANYKERNEL_ZIP")"
  info anykernel_sha256 "$ANYKERNEL_SHA256"
fi
if [[ "$ROOT_VARIANT" != "vanilla" ]]; then
  info root_manager_source_root "${ROOT_MANAGER_SOURCE_ROOT:-none}"
  info root_manager_source_mode "${ROOT_MANAGER_SOURCE_MODE:-none}"
  info root_manager_submodule_path "${ROOT_MANAGER_SUBMODULE_PATH:-none}"
  info root_manager_submodule_commit "${ROOT_MANAGER_SUBMODULE_COMMIT:-none}"
  info root_manager_patch_series "${ROOT_MANAGER_PATCH_SERIES:-none}"
  info root_manager_patches_applied "${ROOT_MANAGER_PATCHES_APPLIED:-none}"
fi

# Persist the completed variant immediately so later matrix failures do not
# discard artifacts already produced by this execution.
printf 'status=SUCCEEDED\nprofile=%s\ndevice=%s\nvariant=%s\nkernel=%s\n' \
  "$BUILD_PROFILE" "$DEVICE" "$ROOT_VARIANT" "${KERNEL_RELEASE:-$KMM}" > "$ARTIFACTS/build-result.txt"
stage_artifacts "$ARTIFACTS"

DURATION=$(( $(date +%s) - START ))
progress_update 100 "done" "$VARIANT_LABEL ready" success
tg_edit "$MID" "✅ <b>Zairenkai build selesai</b>
🧭 Target: <code>${BUILD_PROFILE_LABEL}</code>
📱 $DEVICE | 🔐 $VARIANT_LABEL
🐧 <code>${KERNEL_RELEASE:-$KMM}</code> | 📊 $SCHEDULER_DETECTED
📦 <code>$(basename "${ANYKERNEL_ZIP:-$ARCHIVE}")</code>
⏱ $(fmt_dur "$DURATION")
🔗 <a href=\"$RUN_URL\">CI log</a>" || true
if is_true "${TG_SEND_ARTIFACTS:-false}"; then
  if [[ -n "$ANYKERNEL_ZIP" && -f "$ANYKERNEL_ZIP" ]]; then
    if ! tg_file "$ANYKERNEL_ZIP" "📦 <b>${BUILD_PROFILE_LABEL}</b> — <code>$(basename "$ANYKERNEL_ZIP")</code>"; then
      echo "[telegram] ERROR: failed to upload AnyKernel package for ${BUILD_PROFILE_LABEL}" | tee -a "$BUILD_LOG" >&2
      tg_msg "⚠️ <b>${BUILD_PROFILE_LABEL}</b>: ZIP gagal dikirim ke Telegram. Artifact tetap tersedia di GitHub Actions." || true
    fi
  fi
fi

echo "[build] OK $VARIANT_LABEL kernel=${KERNEL_RELEASE:-$KMM} zip=${ANYKERNEL_ZIP:-none} ($(fmt_dur "$DURATION"))" | tee -a "$BUILD_LOG"