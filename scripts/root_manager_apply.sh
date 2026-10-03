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

fail() { echo "[root-manager] ERROR: $*" >&2; exit 1; }
log() { echo "[root-manager] $*" >&2; }

[[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR/.git" ]] || fail "SOURCE_DIR must be a git working tree"
[[ -n "$WORK_DIR" ]] || fail "WORK_DIR is required"

KERNEL_MAJOR="${KERNEL_VERSION%%.*}"
KERNEL_REST="${KERNEL_VERSION#*.}"
KERNEL_MINOR="${KERNEL_REST%%.*}"
KERNEL_MM="${KERNEL_MAJOR}.${KERNEL_MINOR}"

case "$ROOT_MANAGER" in
  none|"")
    exit 0
    ;;
  official|kernelsu)
    PROVIDER="official"
    PROVIDER_REPO="${KSU_REPO:-https://github.com/tiann/KernelSU}"
    if [[ "$KERNEL_MAJOR" -lt 5 || ( "$KERNEL_MAJOR" -eq 5 && "$KERNEL_MINOR" -lt 10 ) ]]; then
      # Official KernelSU documents v0.9.5 as the final non-GKI release.
      if [[ "$KSU_REF" == "auto" || -z "$KSU_REF" ]]; then
        PROVIDER_REF="v0.9.5"
      elif [[ "$KSU_REF" == "v0.9.5" ]]; then
        PROVIDER_REF="$KSU_REF"
      else
        fail "official KernelSU ref '$KSU_REF' is not supported for Linux $KERNEL_MM; use v0.9.5"
      fi
    else
      PROVIDER_REF="$KSU_REF"
      [[ "$PROVIDER_REF" == "auto" || -z "$PROVIDER_REF" ]] && PROVIDER_REF="latest"
    fi
    ;;
  kernelsu-next|ksu-next|next)
    PROVIDER="kernelsu-next"
    PROVIDER_REPO="${KSU_REPO:-https://github.com/KernelSU-Next/KernelSU-Next}"
    if [[ "$KSU_REF" == "auto" || -z "$KSU_REF" ]]; then
      PROVIDER_REF="v3.4.0"
    else
      PROVIDER_REF="$KSU_REF"
    fi
    ;;
  resukisu|re-sukisu)
    PROVIDER="resukisu"
    PROVIDER_REPO="${KSU_REPO:-https://github.com/ReSukiSU/ReSukiSU}"
    if [[ "$KSU_REF" == "auto" || -z "$KSU_REF" ]]; then
      PROVIDER_REF="main"
    else
      PROVIDER_REF="$KSU_REF"
    fi
    ;;
  custom)
    [[ -n "$KSU_REPO" ]] || fail "KSU_PROVIDER=custom requires KSU_REPO"
    PROVIDER="custom"
    PROVIDER_REPO="$KSU_REPO"
    PROVIDER_REF="$KSU_REF"
    [[ "$PROVIDER_REF" == "auto" || -z "$PROVIDER_REF" ]] && fail "custom provider requires KSU_REF"
    ;;
  *)
    fail "unsupported KSU_PROVIDER=$ROOT_MANAGER"
    ;;
esac

# The upstream setup.sh scripts for all three providers use this exact
# non-GKI layout: provider/kernel -> drivers/kernelsu plus Kconfig/Makefile.
KSU_DIR="$WORK_DIR/KernelSU"
rm -rf "$KSU_DIR"
mkdir -p "$WORK_DIR"

log "provider=$PROVIDER"
log "repo=$PROVIDER_REPO"
log "ref=$PROVIDER_REF"

if [[ "$PROVIDER_REF" =~ ^[0-9a-fA-F]{40}$ || "$PROVIDER_REF" =~ ^[0-9a-fA-F]{64}$ ]]; then
  git init "$KSU_DIR" >/dev/null
  git -C "$KSU_DIR" remote add origin "$PROVIDER_REPO"
  git -C "$KSU_DIR" fetch --depth=1 origin "$PROVIDER_REF" || fail "fetch provider commit"
  git -C "$KSU_DIR" checkout --detach FETCH_HEAD >/dev/null
else
  git clone --depth=1 --branch "$PROVIDER_REF" "$PROVIDER_REPO" "$KSU_DIR" >/dev/null 2>&1 ||
    fail "clone provider $PROVIDER_REPO@$PROVIDER_REF"
fi

[[ -d "$KSU_DIR/kernel" ]] || fail "provider has no kernel/ directory"
PROVIDER_COMMIT="$(git -C "$KSU_DIR" rev-parse HEAD)"
PROVIDER_VERSION="$(git -C "$KSU_DIR" describe --tags --always --dirty 2>/dev/null || git -C "$KSU_DIR" rev-parse --short HEAD)"

DRIVER_DIR="$SOURCE_DIR/drivers"
[[ -f "$DRIVER_DIR/Makefile" ]] || fail "drivers/Makefile missing"
[[ -f "$DRIVER_DIR/Kconfig" ]] || fail "drivers/Kconfig missing"

if [[ -e "$DRIVER_DIR/kernelsu" && ! -L "$DRIVER_DIR/kernelsu" ]]; then
  fail "existing drivers/kernelsu is a real directory; refusing to overwrite it"
fi
rm -f "$DRIVER_DIR/kernelsu"

REL="$(realpath --relative-to="$DRIVER_DIR" "$KSU_DIR/kernel")"
ln -s "$REL" "$DRIVER_DIR/kernelsu"

if ! grep -qE '^[[:space:]]*obj-\$\(CONFIG_KSU\)[[:space:]]*\+= kernelsu/' "$DRIVER_DIR/Makefile"; then
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$DRIVER_DIR/Makefile"
fi

if ! grep -qF 'source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig"; then
  sed -i '/^[[:space:]]*endmenu[[:space:]]*$/i source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig"
fi

case "$KSU_HOOK_MODE" in
  auto)
    case "$PROVIDER" in
      official) HOOK_MODE="kprobe" ;;
      *) HOOK_MODE="auto" ;;
    esac
    ;;
  kprobe|manual|susfs)
    HOOK_MODE="$KSU_HOOK_MODE"
    ;;
  *)
    fail "invalid KSU_HOOK_MODE=$KSU_HOOK_MODE"
    ;;
esac

# KSU-Next + external SUSFS 4.19 is deliberately rejected by the SUSFS stage.
if [[ "${ENABLE_SUSFS,,}" == "true" ]] && [[ "$PROVIDER" == "kernelsu-next" ]]; then
  fail "external SUSFS 4.19 patch set is based on official KernelSU, not KSU-Next"
fi

cat > "$WORK_DIR/root-manager.env" <<EOF
KSU_PROVIDER=$PROVIDER
KSU_REPO=$PROVIDER_REPO
KSU_REF=$PROVIDER_REF
KSU_PROVIDER_COMMIT=$PROVIDER_COMMIT
KSU_PROVIDER_VERSION=$PROVIDER_VERSION
KSU_LAYOUT_RESOLVED=symlink
KSU_HOOK_MODE_RESOLVED=$HOOK_MODE
KSU_DIR=$KSU_DIR
EOF

log "integrated: drivers/kernelsu -> $REL"
log "version=$PROVIDER_VERSION"
log "commit=$PROVIDER_COMMIT"
log "hook_mode=$HOOK_MODE"
