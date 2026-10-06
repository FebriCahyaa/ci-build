#!/usr/bin/env bash
# Integrate Zairenkai / ZKFC into the Lavender 4.19 kernel source tree.
#
# Build-time token embedding is opt-in for local builds and is supplied by CI
# through ZAIRENKAI_LICENSE_INC_FILE. The runtime .zkl token is never stored
# in the repository or release artifacts.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
CI_LOG_TAG=zairenkai

SOURCE_DIR="${SOURCE_DIR:-}"
KERNEL_VERSION="${KERNEL_VERSION:-0.0}"
DEVICE="${DEVICE:-generic}"
ZAIRENKAI="${ZAIRENKAI:-false}"
ZAIRENKAI_REPO="${ZAIRENKAI_REPO:-https://github.com/FebriCahyaa/Zairenkai.git}"
ZAIRENKAI_REF="${ZAIRENKAI_REF:-main}"
ZAIRENKAI_TAG="${ZAIRENKAI_TAG:-}"
ZAIRENKAI_HOOK_MODE="${ZAIRENKAI_HOOK_MODE:-manual}"
ZAIRENKAI_LICENSE_INC_FILE="${ZAIRENKAI_LICENSE_INC_FILE:-}"

is_true "$ZAIRENKAI" || exit 0
[[ -n "$SOURCE_DIR" && -e "$SOURCE_DIR/.git" ]] || ci_die "SOURCE_DIR must point to a git working tree"
[[ "$DEVICE" == lavender && "$(kernel_mm "$KERNEL_VERSION")" == 4.19 ]] || ci_die "Zairenkai integration is currently limited to lavender Linux 4.19"
[[ -n "$ZAIRENKAI_TAG" ]] || ci_die "ZAIRENKAI_TAG is required"
[[ "$ZAIRENKAI_HOOK_MODE" == manual ]] || ci_die "lavender-4.19 Zairenkai integration requires ZAIRENKAI_HOOK_MODE=manual"

ZKFC_DIR="$SOURCE_DIR/Zairenkai"
if [[ -d "$ZKFC_DIR/.git" ]]; then
  ci_log "refreshing Zairenkai checkout: $ZAIRENKAI_REF"
  git -C "$ZKFC_DIR" fetch --tags origin "$ZAIRENKAI_REF" >/dev/null 2>&1 || ci_die "unable to fetch Zairenkai ref $ZAIRENKAI_REF"
  git -C "$ZKFC_DIR" -c advice.detachedHead=false checkout -q "$ZAIRENKAI_REF" || ci_die "unable to checkout Zairenkai ref $ZAIRENKAI_REF"
elif [[ -d "$ZKFC_DIR/kernel" ]]; then
  ci_log "using existing Zairenkai directory"
else
  rm -rf "$ZKFC_DIR"
  ci_log "cloning Zairenkai: $ZAIRENKAI_REPO @ $ZAIRENKAI_REF"
  git_fetch_ref "$ZAIRENKAI_REPO" "$ZAIRENKAI_REF" "$ZKFC_DIR" 1 || ci_die "unable to clone Zairenkai"
fi

[[ -f "$ZKFC_DIR/kernel/setup.sh" ]] || ci_die "Zairenkai/kernel/setup.sh is missing"
[[ -f "$ZKFC_DIR/kernel/Kconfig" ]] || ci_die "Zairenkai/kernel/Kconfig is missing"
[[ -f "$ZKFC_DIR/kernel/Makefile" ]] || ci_die "Zairenkai/kernel/Makefile is missing"
[[ -f "$ZKFC_DIR/kernel/hooks/manual/zkfc_hooks.h" ]] || ci_die "Zairenkai manual hook header is missing"

ci_log "wiring ZKFC into kernel tree"
(
  cd "$SOURCE_DIR"
  bash "$ZKFC_DIR/kernel/setup.sh" "$ZAIRENKAI_REF"
)

if [[ -n "$ZAIRENKAI_LICENSE_INC_FILE" ]]; then
  [[ -f "$ZAIRENKAI_LICENSE_INC_FILE" ]] || ci_die "ZKFC license .inc file not found: $ZAIRENKAI_LICENSE_INC_FILE"
  count="$(grep -oE '0x[0-9A-Fa-f]{2}' "$ZAIRENKAI_LICENSE_INC_FILE" | wc -l | tr -d ' ')"
  [[ "$count" == 200 ]] || ci_die "invalid ZKFC .inc file: expected 200 bytes, found $count"
  mkdir -p "$ZKFC_DIR/kernel/license"
  install -m 0600 "$ZAIRENKAI_LICENSE_INC_FILE" "$ZKFC_DIR/kernel/license/zkfc_license.inc"
  ci_log "embedded ZKFC license enabled for tag $ZAIRENKAI_TAG"
else
  ci_log "no embedded ZKFC license; runtime token installation remains enabled"
fi

printf 'ZAIRENKAI_ENABLED=%q\n' true
printf 'ZAIRENKAI_REPO=%q\n' "$ZAIRENKAI_REPO"
printf 'ZAIRENKAI_REF=%q\n' "$ZAIRENKAI_REF"
printf 'ZAIRENKAI_TAG=%q\n' "$ZAIRENKAI_TAG"
printf 'ZAIRENKAI_HOOK_MODE=%q\n' "$ZAIRENKAI_HOOK_MODE"
printf 'ZAIRENKAI_ZKFC_DIR=%q\n' "$ZKFC_DIR"
