#!/usr/bin/env bash
# Integrate one root provider (KernelSU family) into a kernel source tree.
#
# The provider is checked out into an isolated $WORK_DIR/KernelSU tree, its
# provider-local compatibility patches are applied there, and the host kernel
# receives only a drivers/kernelsu symlink plus the Makefile/Kconfig hooks.
#
# Patch registry contract (patches/root-manager/<provider>/<kernel-mm>/):
#   provider-series.conf  patches applied to the isolated provider checkout (here)
#   host-series.conf      patches applied to the host kernel tree (apply_patch_series.sh)
#   config.fragment       Kconfig overrides (apply_patch_series.sh, config phase)
#
# Output: $WORK_DIR/root-manager.env (shell-quoted, safe to source).
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
CI_LOG_TAG=root-manager

SOURCE_DIR="${SOURCE_DIR:-}"
WORK_DIR="${WORK_DIR:-}"
KERNEL_VERSION="${KERNEL_VERSION:-0.0}"
ROOT_MANAGER="${ROOT_MANAGER:-none}"
KSU_REPO="${KSU_REPO:-}"
KSU_REF="${KSU_REF:-auto}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
KSU_HOOK_MODE="${KSU_HOOK_MODE:-auto}"
KSU_NEXT_44_REF="${KSU_NEXT_44_REF:-v1.1.1}"
KSU_NEXT_LEGACY_REF="${KSU_NEXT_LEGACY_REF:-v3.4.0}"
KSU_NEXT_GKI_REF="${KSU_NEXT_GKI_REF:-v3.4.0}"
RESUKISU_REF_DEFAULT="${RESUKISU_REF_DEFAULT:-v4.2.0-rc3}"
SUKISU_ULTRA_REF_DEFAULT="${SUKISU_ULTRA_REF_DEFAULT:-${PROFILE_SUKISU_ULTRA_REF:-main}}"
ROOT_MANAGER_SOURCE_ROOT="${ROOT_MANAGER_SOURCE_ROOT:-$CI_ROOT/third_party/root-managers}"
ROOT_MANAGER_SOURCE_MODE="${ROOT_MANAGER_SOURCE_MODE:-auto}"

# Release refs whose commit is verified before provider patches are applied.
# A moved/re-tagged upstream tag must never silently change what is patched.
declare -A PINNED_COMMITS=(
  [kernelsu-next@v3.4.0]=1a879d6a866f80b1fa1c1009a2ffa747873cbb5e
)

fail() { ci_die "$*"; }
log() { ci_log "$*"; }

is_git_worktree() {
  [[ -d "$1" ]] && git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

[[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR/.git" ]] || fail "SOURCE_DIR must be a git working tree"

KERNEL_MAJOR="${KERNEL_VERSION%%.*}"
KERNEL_REST="${KERNEL_VERSION#*.}"
KERNEL_MINOR="${KERNEL_REST%%.*}"
KERNEL_MM="${KERNEL_MAJOR}.${KERNEL_MINOR}"

case "$ROOT_MANAGER" in none|"") exit 0 ;; esac
[[ -n "$WORK_DIR" ]] || fail "WORK_DIR is required"

# ------------------------------------------------------------
# Provider and ref resolution
# ------------------------------------------------------------
case "$ROOT_MANAGER" in
  official|kernelsu)
    PROVIDER="official"
    PROVIDER_REPO="${KSU_REPO:-https://github.com/tiann/KernelSU}"
    SOURCE_SUBDIR="kernelsu"
    if ! kernel_ge "$KERNEL_VERSION" 5 10; then
      kernel_ge "$KERNEL_VERSION" 4 14 ||
        fail "official KernelSU is not supported by upstream on Linux $KERNEL_MM; use KernelSU-Next/ReSukiSU/SukiSU Ultra for 4.4 non-GKI"
      case "$KSU_REF" in
        auto|""|v0.9.5) PROVIDER_REF="v0.9.5" ;;
        *) fail "official KernelSU ref '$KSU_REF' is not supported for Linux $KERNEL_MM; use v0.9.5" ;;
      esac
    else
      PROVIDER_REF="$KSU_REF"
      [[ "$PROVIDER_REF" == "auto" || -z "$PROVIDER_REF" ]] && PROVIDER_REF="main"
    fi
    ;;
  kernelsu-next|ksu-next|next)
    PROVIDER="kernelsu-next"
    PROVIDER_REPO="${KSU_REPO:-https://github.com/KernelSU-Next/KernelSU-Next}"
    SOURCE_SUBDIR="kernelsu-next"
    if [[ "$KSU_REF" == "auto" || -z "$KSU_REF" ]]; then
      if [[ "$KERNEL_MM" == "4.4" ]]; then
        PROVIDER_REF="$KSU_NEXT_44_REF"
      elif kernel_ge "$KERNEL_VERSION" 5 10; then
        PROVIDER_REF="$KSU_NEXT_GKI_REF"
      else
        PROVIDER_REF="$KSU_NEXT_LEGACY_REF"
      fi
    else
      PROVIDER_REF="$KSU_REF"
    fi
    ;;
  resukisu|re-sukisu)
    PROVIDER="resukisu"
    PROVIDER_REPO="${KSU_REPO:-https://github.com/ReSukiSU/ReSukiSU}"
    SOURCE_SUBDIR="resukisu"
    if [[ "$KSU_REF" == "auto" || -z "$KSU_REF" ]]; then PROVIDER_REF="$RESUKISU_REF_DEFAULT"; else PROVIDER_REF="$KSU_REF"; fi
    ;;
  sukisu-ultra|sukisu_ultra|sukisuultra)
    PROVIDER="sukisu-ultra"
    PROVIDER_REPO="${KSU_REPO:-https://github.com/SukiSU-Ultra/SukiSU-Ultra}"
    SOURCE_SUBDIR="sukisu-ultra"
    # Current SukiSU Ultra (main) and the last flat-layout release (v3.2.0)
    # both fail to compile against Linux 4.4 (selinux_state, sched/*.h,
    # compiler_types.h, LSM hlist API, ...). Fail before cloning instead of
    # after a full kernel compile. ALLOW_UNSUPPORTED_PROVIDER=true overrides.
    if ! kernel_ge "$KERNEL_VERSION" 4 19 && ! is_true "${ALLOW_UNSUPPORTED_PROVIDER:-false}"; then
      fail "SukiSU Ultra does not support Linux $KERNEL_MM (upstream sources do not compile below 4.19); use KernelSU-Next or ReSukiSU"
    fi
    if [[ "$KSU_REF" == "auto" || -z "$KSU_REF" ]]; then PROVIDER_REF="$SUKISU_ULTRA_REF_DEFAULT"; else PROVIDER_REF="$KSU_REF"; fi
    ;;
  custom)
    [[ -n "$KSU_REPO" ]] || fail "KSU_PROVIDER=custom requires KSU_REPO"
    PROVIDER="custom"; PROVIDER_REPO="$KSU_REPO"; PROVIDER_REF="$KSU_REF"; SOURCE_SUBDIR=""
    [[ "$PROVIDER_REF" == "auto" || -z "$PROVIDER_REF" ]] && fail "custom provider requires KSU_REF"
    ;;
  *) fail "unsupported KSU_PROVIDER=$ROOT_MANAGER" ;;
esac

# SUSFS policy gates run before any network access so unsupported
# combinations fail fast with an actionable message.
if is_true "$ENABLE_SUSFS"; then
  case "$PROVIDER:$KERNEL_MM" in
    kernelsu-next:4.19) fail "external SUSFS 4.19 patch set is based on official KernelSU, not KSU-Next" ;;
    kernelsu-next:4.4) fail "dedicated SUSFS 4.4 patch path is validated for official KernelSU/ReSukiSU; KSU-Next is intentionally blocked" ;;
    sukisu-ultra:4.4) fail "SukiSU Ultra 4.4 SUSFS is not enabled by this harness: supplied upstream Kconfig exposes KSU_MANUAL_SU but no verified KSU_SUSFS integration contract" ;;
  esac
fi

KSU_DIR="$WORK_DIR/KernelSU"
rm -rf "$KSU_DIR"
mkdir -p "$WORK_DIR"
SOURCE_MODE_RESOLVED="clone"
SUBMODULE_DIR=""
[[ -n "$SOURCE_SUBDIR" ]] && SUBMODULE_DIR="$ROOT_MANAGER_SOURCE_ROOT/$SOURCE_SUBDIR"

log "provider=$PROVIDER"
log "repo=$PROVIDER_REPO"
log "ref=$PROVIDER_REF"
log "source_root=$ROOT_MANAGER_SOURCE_ROOT"

# ------------------------------------------------------------
# Provider checkout (initialized submodule snapshot, else upstream clone)
# ------------------------------------------------------------
clone_provider() {
  # Full history is kept on purpose: KernelSU-family Makefiles derive the
  # manager-visible version from `git rev-list --count HEAD`.
  local ref="$1"
  if is_commit_ref "$ref"; then
    git init -q "$KSU_DIR"
    git -C "$KSU_DIR" remote add origin "$PROVIDER_REPO"
    git -C "$KSU_DIR" fetch -q --tags origin "$ref"
    git -C "$KSU_DIR" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
  else
    git -c advice.detachedHead=false clone -q --branch "$ref" "$PROVIDER_REPO" "$KSU_DIR"
  fi
}

prepare_from_submodule() {
  is_git_worktree "$SUBMODULE_DIR" || return 1
  if is_commit_ref "$PROVIDER_REF"; then
    git -C "$SUBMODULE_DIR" cat-file -e "$PROVIDER_REF^{commit}" >/dev/null 2>&1 ||
      git -C "$SUBMODULE_DIR" fetch -q origin "$PROVIDER_REF" || return 1
  elif git -C "$SUBMODULE_DIR" ls-remote --exit-code --heads origin "$PROVIDER_REF" >/dev/null 2>&1; then
    git -C "$SUBMODULE_DIR" fetch -q origin "refs/heads/$PROVIDER_REF:refs/remotes/origin/$PROVIDER_REF" || return 1
  elif git -C "$SUBMODULE_DIR" ls-remote --exit-code --tags origin "refs/tags/$PROVIDER_REF" >/dev/null 2>&1; then
    git -C "$SUBMODULE_DIR" fetch -q origin "refs/tags/$PROVIDER_REF:refs/tags/$PROVIDER_REF" || return 1
  fi
  git clone -q --local --no-hardlinks "$SUBMODULE_DIR" "$KSU_DIR"
  local target=""
  if is_commit_ref "$PROVIDER_REF"; then
    target="$PROVIDER_REF"
  else
    for candidate in "refs/tags/$PROVIDER_REF" "refs/remotes/origin/$PROVIDER_REF" "$PROVIDER_REF"; do
      if git -C "$KSU_DIR" rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then
        target="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$target" ]]; then
    rm -rf "$KSU_DIR"
    return 1
  fi
  git -C "$KSU_DIR" -c advice.detachedHead=false checkout -q --detach "$target"
  SOURCE_MODE_RESOLVED="submodule"
}

case "${ROOT_MANAGER_SOURCE_MODE,,}" in
  auto|submodule)
    if [[ -n "$SUBMODULE_DIR" ]] && prepare_from_submodule; then
      log "provider source: initialized submodule snapshot ($SUBMODULE_DIR)"
    elif [[ "${ROOT_MANAGER_SOURCE_MODE,,}" == submodule ]]; then
      fail "required root-manager submodule is missing or unusable: $SUBMODULE_DIR"
    else
      log "provider submodule unavailable; falling back to upstream clone"
      clone_provider "$PROVIDER_REF" || fail "clone provider $PROVIDER_REPO@$PROVIDER_REF"
    fi
    ;;
  clone) clone_provider "$PROVIDER_REF" || fail "clone provider $PROVIDER_REPO@$PROVIDER_REF" ;;
  *) fail "invalid ROOT_MANAGER_SOURCE_MODE=$ROOT_MANAGER_SOURCE_MODE (use auto, submodule, or clone)" ;;
esac

[[ -d "$KSU_DIR/kernel" ]] || fail "provider has no kernel/ directory"
PROVIDER_COMMIT="$(git -C "$KSU_DIR" rev-parse HEAD)"
PROVIDER_VERSION="$(git -C "$KSU_DIR" describe --tags --always 2>/dev/null || git -C "$KSU_DIR" rev-parse --short HEAD)"
expected_commit="${PINNED_COMMITS[$PROVIDER@$PROVIDER_REF]:-}"
if [[ -n "$expected_commit" && "$PROVIDER_COMMIT" != "$expected_commit" ]]; then
  fail "$PROVIDER $PROVIDER_REF resolved to unexpected commit $PROVIDER_COMMIT (expected $expected_commit)"
fi

# ------------------------------------------------------------
# Provider-local compatibility patches (never touch the host tree or the
# parent submodule; only the isolated checkout above is modified).
# ------------------------------------------------------------
PROVIDER_PATCH_DIR="${CI_PATCH_ROOT:-$CI_ROOT/patches}/root-manager/$PROVIDER/$KERNEL_MM"
PROVIDER_PATCH_SERIES="none"
PROVIDER_PATCHES_APPLIED="none"
if [[ -f "$PROVIDER_PATCH_DIR/provider-series.conf" ]]; then
  PROVIDER_PATCH_SERIES="$PROVIDER_PATCH_DIR/provider-series.conf"
  applied=()
  while IFS= read -r patch_name; do
    patch_path="$PROVIDER_PATCH_DIR/$patch_name"
    [[ -f "$patch_path" ]] || fail "provider patch listed in $PROVIDER_PATCH_SERIES is missing: $patch_path"
    git -C "$KSU_DIR" apply --check --whitespace=error-all "$patch_path" ||
      fail "provider patch preflight failed: $patch_name for $PROVIDER@$PROVIDER_REF ($PROVIDER_COMMIT) on Linux $KERNEL_MM"
    git -C "$KSU_DIR" apply --whitespace=error-all "$patch_path" ||
      fail "provider patch apply failed: $patch_name for $PROVIDER Linux $KERNEL_MM"
    applied+=("$patch_name")
    log "applied provider compatibility patch: $patch_name"
  done < <(read_series "$PROVIDER_PATCH_SERIES")
  ((${#applied[@]} == 0)) || PROVIDER_PATCHES_APPLIED="$(IFS=,; echo "${applied[*]}")"
fi

# ------------------------------------------------------------
# Host kernel wiring: drivers/kernelsu -> provider kernel/
# ------------------------------------------------------------
DRIVER_DIR="$SOURCE_DIR/drivers"
[[ -f "$DRIVER_DIR/Makefile" ]] || fail "drivers/Makefile missing"
[[ -f "$DRIVER_DIR/Kconfig" ]] || fail "drivers/Kconfig missing"
if [[ -e "$DRIVER_DIR/kernelsu" && ! -L "$DRIVER_DIR/kernelsu" ]]; then
  fail "existing drivers/kernelsu is a real directory; refusing to overwrite it"
fi
rm -f "$DRIVER_DIR/kernelsu"
REL="$(realpath --relative-to="$DRIVER_DIR" "$KSU_DIR/kernel")"
ln -s "$REL" "$DRIVER_DIR/kernelsu"

# Pre-integrated trees may already carry `obj-y += kernelsu/` (with
# unconditional hook calls in fs/*.c); keep that line and do not add another.
if ! grep -qE '^[[:space:]]*obj-(y|\$\(CONFIG_KSU\))[[:space:]]*\+=[[:space:]]*kernelsu/' "$DRIVER_DIR/Makefile"; then
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$DRIVER_DIR/Makefile"
fi
if ! grep -qF 'source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig"; then
  # Insert before the *last* endmenu only. drivers/Kconfig may contain nested
  # menus, and sourcing the provider Kconfig twice breaks Kconfig parsing.
  last_endmenu="$(grep -nE '^[[:space:]]*endmenu[[:space:]]*$' "$DRIVER_DIR/Kconfig" | tail -n1 | cut -d: -f1)"
  if [[ -n "$last_endmenu" ]]; then
    sed -i "${last_endmenu}i source \"drivers/kernelsu/Kconfig\"" "$DRIVER_DIR/Kconfig"
  else
    printf '\nsource "drivers/kernelsu/Kconfig"\n' >> "$DRIVER_DIR/Kconfig"
  fi
fi
[[ "$(grep -cF 'source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig")" == 1 ]] ||
  fail "drivers/Kconfig must source drivers/kernelsu/Kconfig exactly once"

# ------------------------------------------------------------
# Hook mode
# ------------------------------------------------------------
case "$KSU_HOOK_MODE" in
  auto)
    case "$PROVIDER" in
      official) HOOK_MODE="kprobe" ;;
      resukisu)
        if [[ "$KERNEL_MM" == "4.19" || "$KERNEL_MM" == "4.4" ]]; then HOOK_MODE="manual"; else HOOK_MODE="auto"; fi
        ;;
      sukisu-ultra)
        if kernel_ge "$KERNEL_VERSION" 5 10; then HOOK_MODE="kprobe"; else HOOK_MODE="manual"; fi
        ;;
      *) HOOK_MODE="auto" ;;
    esac
    ;;
  kprobe|manual|susfs) HOOK_MODE="$KSU_HOOK_MODE" ;;
  *) fail "invalid KSU_HOOK_MODE=$KSU_HOOK_MODE" ;;
esac

write_env "$WORK_DIR/root-manager.env" \
  "KSU_PROVIDER=$PROVIDER" \
  "KSU_REPO=$PROVIDER_REPO" \
  "KSU_REF=$PROVIDER_REF" \
  "KSU_PROVIDER_COMMIT=$PROVIDER_COMMIT" \
  "KSU_PROVIDER_VERSION=$PROVIDER_VERSION" \
  "KSU_LAYOUT_RESOLVED=symlink" \
  "KSU_HOOK_MODE_RESOLVED=$HOOK_MODE" \
  "KSU_DIR=$KSU_DIR" \
  "ROOT_MANAGER_SOURCE_ROOT=$ROOT_MANAGER_SOURCE_ROOT" \
  "ROOT_MANAGER_SOURCE_MODE=$SOURCE_MODE_RESOLVED" \
  "ROOT_MANAGER_SUBMODULE_PATH=${SUBMODULE_DIR:-none}" \
  "ROOT_MANAGER_SUBMODULE_COMMIT=$PROVIDER_COMMIT" \
  "ROOT_MANAGER_PATCH_DIR=$PROVIDER_PATCH_DIR" \
  "ROOT_MANAGER_PATCH_SERIES=$PROVIDER_PATCH_SERIES" \
  "ROOT_MANAGER_PATCHES_APPLIED=$PROVIDER_PATCHES_APPLIED"

log "integrated: drivers/kernelsu -> $REL"
log "version=$PROVIDER_VERSION"
log "commit=$PROVIDER_COMMIT"
log "hook_mode=$HOOK_MODE"
log "source_mode=$SOURCE_MODE_RESOLVED"
