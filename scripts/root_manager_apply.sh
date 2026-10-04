#!/usr/bin/env bash
set -Eeuo pipefail

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
ROOT_MANAGER_SOURCE_ROOT="${ROOT_MANAGER_SOURCE_ROOT:-}"
ROOT_MANAGER_SOURCE_MODE="${ROOT_MANAGER_SOURCE_MODE:-auto}"
PROVIDER_PATCH_DIR=""
PROVIDER_PATCH_SERIES="none"
PROVIDER_PATCHES_APPLIED="none"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CI_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ROOT_MANAGER_SOURCE_ROOT="${ROOT_MANAGER_SOURCE_ROOT:-$CI_ROOT/third_party/root-managers}"

fail() { echo "[root-manager] ERROR: $*" >&2; exit 1; }
log() { echo "[root-manager] $*" >&2; }

is_git_worktree() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

[[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR/.git" ]] || fail "SOURCE_DIR must be a git working tree"
[[ -n "$WORK_DIR" ]] || fail "WORK_DIR is required"

KERNEL_MAJOR="${KERNEL_VERSION%%.*}"
KERNEL_REST="${KERNEL_VERSION#*.}"
KERNEL_MINOR="${KERNEL_REST%%.*}"
KERNEL_MM="${KERNEL_MAJOR}.${KERNEL_MINOR}"

case "$ROOT_MANAGER" in
  none|"") exit 0 ;;
  official|kernelsu)
    PROVIDER="official"
    PROVIDER_REPO="${KSU_REPO:-https://github.com/tiann/KernelSU}"
    SOURCE_SUBDIR="kernelsu"
    if [[ "$KERNEL_MAJOR" -lt 5 || ( "$KERNEL_MAJOR" -eq 5 && "$KERNEL_MINOR" -lt 10 ) ]]; then
      if [[ "$KERNEL_MM" == "4.4" || "$KERNEL_MAJOR" -lt 4 || ( "$KERNEL_MAJOR" -eq 4 && "$KERNEL_MINOR" -lt 14 ) ]]; then
        fail "official KernelSU is not supported by upstream on Linux $KERNEL_MM; use KernelSU-Next/ReSukiSU/SukiSU Ultra for 4.4 non-GKI"
      fi
      if [[ "$KSU_REF" == "auto" || -z "$KSU_REF" ]]; then PROVIDER_REF="v0.9.5"
      elif [[ "$KSU_REF" == "v0.9.5" ]]; then PROVIDER_REF="$KSU_REF"
      else fail "official KernelSU ref '$KSU_REF' is not supported for Linux $KERNEL_MM; use v0.9.5"
      fi
    else
      PROVIDER_REF="$KSU_REF"
      [[ "$PROVIDER_REF" == "auto" || -z "$PROVIDER_REF" ]] && PROVIDER_REF="main"
    fi
    ;;
  kernelsu-next|ksu-next|next)
    PROVIDER="kernelsu-next"; PROVIDER_REPO="${KSU_REPO:-https://github.com/KernelSU-Next/KernelSU-Next}"; SOURCE_SUBDIR="kernelsu-next"
    if [[ "$KSU_REF" == "auto" || -z "$KSU_REF" ]]; then
      if [[ "$KERNEL_MM" == "4.4" ]]; then
        PROVIDER_REF="$KSU_NEXT_44_REF"
      elif [[ "$KERNEL_MAJOR" -gt 5 || ( "$KERNEL_MAJOR" -eq 5 && "$KERNEL_MINOR" -ge 10 ) ]]; then
        PROVIDER_REF="$KSU_NEXT_GKI_REF"
      else
        PROVIDER_REF="$KSU_NEXT_LEGACY_REF"
      fi
    else PROVIDER_REF="$KSU_REF"; fi
    ;;
  resukisu|re-sukisu)
    PROVIDER="resukisu"; PROVIDER_REPO="${KSU_REPO:-https://github.com/ReSukiSU/ReSukiSU}"; SOURCE_SUBDIR="resukisu"
    if [[ "$KSU_REF" == "auto" || -z "$KSU_REF" ]]; then PROVIDER_REF="$RESUKISU_REF_DEFAULT"; else PROVIDER_REF="$KSU_REF"; fi
    ;;
  sukisu-ultra|sukisu_ultra|sukisuultra)
    PROVIDER="sukisu-ultra"; PROVIDER_REPO="${KSU_REPO:-https://github.com/SukiSU-Ultra/SukiSU-Ultra}"; SOURCE_SUBDIR="sukisu-ultra"
    if [[ "$KSU_REF" == "auto" || -z "$KSU_REF" ]]; then PROVIDER_REF="$SUKISU_ULTRA_REF_DEFAULT"; else PROVIDER_REF="$KSU_REF"; fi
    ;;
  custom)
    [[ -n "$KSU_REPO" ]] || fail "KSU_PROVIDER=custom requires KSU_REPO"
    PROVIDER="custom"; PROVIDER_REPO="$KSU_REPO"; PROVIDER_REF="$KSU_REF"; SOURCE_SUBDIR=""
    [[ "$PROVIDER_REF" == "auto" || -z "$PROVIDER_REF" ]] && fail "custom provider requires KSU_REF"
    ;;
  *) fail "unsupported KSU_PROVIDER=$ROOT_MANAGER" ;;
esac

KSU_DIR="$WORK_DIR/KernelSU"
rm -rf "$KSU_DIR"; mkdir -p "$WORK_DIR"
SOURCE_MODE_RESOLVED="clone"
SUBMODULE_DIR=""
[[ -n "$SOURCE_SUBDIR" ]] && SUBMODULE_DIR="$ROOT_MANAGER_SOURCE_ROOT/$SOURCE_SUBDIR"

log "provider=$PROVIDER"
log "repo=$PROVIDER_REPO"
log "ref=$PROVIDER_REF"
log "source_root=$ROOT_MANAGER_SOURCE_ROOT"

clone_provider() {
  local ref="$1"
  if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ || "$ref" =~ ^[0-9a-fA-F]{64}$ ]]; then
    git init -q "$KSU_DIR"; git -C "$KSU_DIR" remote add origin "$PROVIDER_REPO"
    git -C "$KSU_DIR" fetch -q --depth=1 origin "$ref"; git -C "$KSU_DIR" checkout -q --detach FETCH_HEAD
  else
    git clone -q --depth=1 --branch "$ref" "$PROVIDER_REPO" "$KSU_DIR"
  fi
}

prepare_from_submodule() {
  is_git_worktree "$SUBMODULE_DIR" || return 1
  if [[ "$PROVIDER_REF" =~ ^[0-9a-fA-F]{40}$ || "$PROVIDER_REF" =~ ^[0-9a-fA-F]{64}$ ]]; then
    git -C "$SUBMODULE_DIR" cat-file -e "$PROVIDER_REF^{commit}" >/dev/null 2>&1 || git -C "$SUBMODULE_DIR" fetch -q --depth=1 origin "$PROVIDER_REF"
  elif git -C "$SUBMODULE_DIR" ls-remote --exit-code --heads origin "$PROVIDER_REF" >/dev/null 2>&1; then
    git -C "$SUBMODULE_DIR" fetch -q --depth=1 origin "refs/heads/$PROVIDER_REF:refs/remotes/origin/$PROVIDER_REF"
  elif git -C "$SUBMODULE_DIR" ls-remote --exit-code --tags origin "refs/tags/$PROVIDER_REF" >/dev/null 2>&1; then
    git -C "$SUBMODULE_DIR" fetch -q --depth=1 origin "refs/tags/$PROVIDER_REF:refs/tags/$PROVIDER_REF"
  fi
  git clone -q --local --no-hardlinks "$SUBMODULE_DIR" "$KSU_DIR"
  if [[ "$PROVIDER_REF" =~ ^[0-9a-fA-F]{40}$ || "$PROVIDER_REF" =~ ^[0-9a-fA-F]{64}$ ]]; then
    git -C "$KSU_DIR" checkout -q --detach "$PROVIDER_REF"
  elif git -C "$KSU_DIR" rev-parse --verify --quiet "refs/tags/$PROVIDER_REF^{commit}" >/dev/null; then
    git -C "$KSU_DIR" checkout -q --detach "refs/tags/$PROVIDER_REF"
  elif git -C "$KSU_DIR" rev-parse --verify --quiet "refs/remotes/origin/$PROVIDER_REF^{commit}" >/dev/null; then
    git -C "$KSU_DIR" checkout -q --detach "refs/remotes/origin/$PROVIDER_REF"
  elif git -C "$KSU_DIR" rev-parse --verify --quiet "$PROVIDER_REF^{commit}" >/dev/null; then
    git -C "$KSU_DIR" checkout -q --detach "$PROVIDER_REF"
  else return 1; fi
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
if [[ "$PROVIDER" == "kernelsu-next" && "$PROVIDER_REF" == "v3.4.0" ]]; then
  [[ "$PROVIDER_COMMIT" == "1a879d6a866f80b1fa1c1009a2ffa747873cbb5e" ]] ||
    fail "KernelSU-Next v3.4.0 resolved to unexpected commit $PROVIDER_COMMIT"
fi

# Provider-specific compatibility patches live in ci-build, not in the
# upstream submodule. Apply them only to the isolated provider checkout so the
# parent submodule remains a clean gitlink.
PROVIDER_PATCH_DIR="$CI_ROOT/patches/root-manager/$PROVIDER/$KERNEL_MM"
if [[ -f "$PROVIDER_PATCH_DIR/series.conf" ]]; then
  PROVIDER_PATCH_SERIES="$PROVIDER_PATCH_DIR/series.conf"
  PROVIDER_PATCHES_APPLIED=""
  while IFS= read -r patch_name || [[ -n "$patch_name" ]]; do
    [[ -z "$patch_name" || "$patch_name" == \#* ]] && continue
    patch_path="$PROVIDER_PATCH_DIR/$patch_name"
    [[ -f "$patch_path" ]] || fail "provider patch listed in $PROVIDER_PATCH_SERIES is missing: $patch_path"
    git -C "$KSU_DIR" apply --check --whitespace=error-all "$patch_path" ||
      fail "provider patch preflight failed: $patch_name for $PROVIDER Linux $KERNEL_MM"
    git -C "$KSU_DIR" apply --whitespace=error-all "$patch_path" ||
      fail "provider patch apply failed: $patch_name for $PROVIDER Linux $KERNEL_MM"
    if [[ -z "$PROVIDER_PATCHES_APPLIED" ]]; then PROVIDER_PATCHES_APPLIED="$patch_name"; else PROVIDER_PATCHES_APPLIED="$PROVIDER_PATCHES_APPLIED,$patch_name"; fi
    log "applied provider compatibility patch: $patch_name"
  done < "$PROVIDER_PATCH_SERIES"
fi

DRIVER_DIR="$SOURCE_DIR/drivers"
[[ -f "$DRIVER_DIR/Makefile" ]] || fail "drivers/Makefile missing"
[[ -f "$DRIVER_DIR/Kconfig" ]] || fail "drivers/Kconfig missing"
if [[ -e "$DRIVER_DIR/kernelsu" && ! -L "$DRIVER_DIR/kernelsu" ]]; then fail "existing drivers/kernelsu is a real directory; refusing to overwrite it"; fi
rm -f "$DRIVER_DIR/kernelsu"
REL="$(realpath --relative-to="$DRIVER_DIR" "$KSU_DIR/kernel")"
ln -s "$REL" "$DRIVER_DIR/kernelsu"
if ! grep -qE '^[[:space:]]*obj-\$\(CONFIG_KSU\)[[:space:]]*\+= kernelsu/' "$DRIVER_DIR/Makefile"; then printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$DRIVER_DIR/Makefile"; fi
if ! grep -qF 'source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig"; then sed -i '/^[[:space:]]*endmenu[[:space:]]*$/i source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig"; fi

case "$KSU_HOOK_MODE" in
  auto)
    case "$PROVIDER" in
      official) HOOK_MODE="kprobe" ;;
      resukisu) [[ "$KERNEL_MM" == "4.19" || "$KERNEL_MM" == "4.4" ]] && HOOK_MODE="manual" || HOOK_MODE="auto" ;;
      sukisu-ultra) [[ "$KERNEL_MAJOR" -lt 5 || ( "$KERNEL_MAJOR" -eq 5 && "$KERNEL_MINOR" -lt 10 ) ]] && HOOK_MODE="manual" || HOOK_MODE="kprobe" ;;
      *) HOOK_MODE="auto" ;;
    esac
    ;;
  kprobe|manual|susfs) HOOK_MODE="$KSU_HOOK_MODE" ;;
  *) fail "invalid KSU_HOOK_MODE=$KSU_HOOK_MODE" ;;
esac

if [[ "${ENABLE_SUSFS,,}" == true && "$PROVIDER" == "kernelsu-next" ]]; then
  if [[ "$KERNEL_MM" == "4.19" ]]; then fail "external SUSFS 4.19 patch set is based on official KernelSU, not KSU-Next"
  elif [[ "$KERNEL_MM" == "4.4" ]]; then fail "dedicated SUSFS 4.4 patch path is validated for official KernelSU/ReSukiSU; KSU-Next is intentionally blocked"; fi
fi
if [[ "${ENABLE_SUSFS,,}" == true && "$PROVIDER" == "sukisu-ultra" && "$KERNEL_MM" == "4.4" ]]; then
  fail "SukiSU Ultra 4.4 SUSFS is not enabled by this harness: supplied upstream Kconfig exposes KSU_MANUAL_SU but no verified KSU_SUSFS integration contract"
fi

cat > "$WORK_DIR/root-manager.env" <<EOF_ENV
KSU_PROVIDER=$PROVIDER
KSU_REPO=$PROVIDER_REPO
KSU_REF=$PROVIDER_REF
KSU_PROVIDER_COMMIT=$PROVIDER_COMMIT
KSU_PROVIDER_VERSION=$PROVIDER_VERSION
KSU_LAYOUT_RESOLVED=symlink
KSU_HOOK_MODE_RESOLVED=$HOOK_MODE
KSU_DIR=$KSU_DIR
ROOT_MANAGER_SOURCE_ROOT=$ROOT_MANAGER_SOURCE_ROOT
ROOT_MANAGER_SOURCE_MODE=$SOURCE_MODE_RESOLVED
ROOT_MANAGER_SUBMODULE_PATH=${SUBMODULE_DIR:-none}
ROOT_MANAGER_SUBMODULE_COMMIT=$PROVIDER_COMMIT
ROOT_MANAGER_PATCH_DIR=$PROVIDER_PATCH_DIR
ROOT_MANAGER_PATCH_SERIES=$PROVIDER_PATCH_SERIES
ROOT_MANAGER_PATCHES_APPLIED=$PROVIDER_PATCHES_APPLIED
EOF_ENV

log "integrated: drivers/kernelsu -> $REL"
log "version=$PROVIDER_VERSION"
log "commit=$PROVIDER_COMMIT"
log "hook_mode=$HOOK_MODE"
log "source_mode=$SOURCE_MODE_RESOLVED"
