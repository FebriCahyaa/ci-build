#!/usr/bin/env bash
# Apply the NonGKI hook layer from Lokitla/NonGKI_Kernel_Build_2nd.
#
# This is intentionally a source-time integration stage for legacy ARM64
# kernels. The upstream hook scripts are fetched from an immutable commit and
# verified against their Git blob SHA before execution.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "[nongki-4.4] ERROR: $*" >&2; exit 1; }
log() { echo "[nongki-4.4] $*" >&2; }

SOURCE_DIR="${SOURCE_DIR:-}"
WORK_DIR="${WORK_DIR:-}"
DEVICE="${DEVICE:-generic}"
KERNEL_VERSION="${KERNEL_VERSION:-0.0}"
ROOT_MANAGER="${ROOT_MANAGER:-none}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
NONGKI_4_4_HOOKS="${NONGKI_4_4_HOOKS:-auto}"
NONGKI_4_4_MODE="${NONGKI_4_4_MODE:-auto}"
KPM_ENABLE="${KPM_ENABLE:-false}"
NONGKI_SCRIPT_PATH="${NONGKI_SCRIPT_PATH:-}"

MANIFEST="$SCRIPT_DIR/../patches/upstream/lokitla-nongki/4.4/manifest.conf"
[[ -f "$MANIFEST" ]] || fail "NonGKI 4.4 manifest missing: $MANIFEST"
# shellcheck source=/dev/null
source "$MANIFEST"
UPSTREAM_REPO="$UPSTREAM_NONGKI_REPO"
UPSTREAM_COMMIT="$UPSTREAM_NONGKI_COMMIT"
SYSCALL_SCRIPT_BLOB="$UPSTREAM_SYSCALL_HOOK_BLOB"
INLINE_SCRIPT_BLOB="$UPSTREAM_INLINE_HOOK_BLOB"
SYSCALL_SCRIPT_URL="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${UPSTREAM_COMMIT}/Patches/syscall_hook_patches.sh"
INLINE_SCRIPT_URL="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${UPSTREAM_COMMIT}/Patches/susfs_inline_hook_patches.sh"

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

[[ "$DEVICE" == "lavender" ]] || exit 0
[[ "$KERNEL_VERSION" == 4.4* ]] || exit 0
[[ "$ROOT_MANAGER" != "none" && -n "$ROOT_MANAGER" ]] || exit 0
is_true "$NONGKI_4_4_HOOKS" || {
  log "disabled (NONGKI_4_4_HOOKS=$NONGKI_4_4_HOOKS)"
  exit 0
}

# ReSukiSU's manual hook path is the one that needs the pinned external source
# hook layer. KernelSU-Next and SukiSU Ultra already ship their own syscall
# table/kprobe based legacy hook implementation; running the external patch on
# top of those providers can double-hook the same paths. Their 4.4 compatibility
# is handled by patches/root-manager/<provider>/4.4 instead.
case "$ROOT_MANAGER" in
  resukisu) ;;
  kernelsu-next|sukisu-ultra)
    cat > "$WORK_DIR/nongki-4.4.env" <<EOF_ENV
NONGKI_4_4_ENABLED=true
NONGKI_4_4_DEVICE=lavender
NONGKI_4_4_KERNEL_VERSION=$KERNEL_VERSION
NONGKI_4_4_MODE=provider-native
NONGKI_4_4_UPSTREAM_REPO=https://github.com/$UPSTREAM_REPO
NONGKI_4_4_UPSTREAM_COMMIT=$UPSTREAM_COMMIT
NONGKI_4_4_HOOK_BLOB=provider-native
NONGKI_4_4_HOOK_URL=provider-native
EOF_ENV
    log "provider-native legacy hook path selected for $ROOT_MANAGER; external NonGKI source-hook script skipped"
    exit 0
    ;;
  *) fail "unsupported 4.4 non-GKI root provider: $ROOT_MANAGER" ;;
esac

[[ -d "$SOURCE_DIR/.git" ]] || fail "SOURCE_DIR must be a git working tree"
[[ -n "$WORK_DIR" ]] || fail "WORK_DIR is required"

case "$NONGKI_4_4_MODE" in
  auto)
    if is_true "$ENABLE_SUSFS"; then
      MODE="susfs-inline"
    else
      MODE="syscall"
    fi
    ;;
  syscall|susfs-inline)
    MODE="$NONGKI_4_4_MODE"
    ;;
  *)
    fail "unsupported NONGKI_4_4_MODE=$NONGKI_4_4_MODE"
    ;;
esac

if is_true "$ENABLE_SUSFS" && [[ "$MODE" != "susfs-inline" ]]; then
  fail "ENABLE_SUSFS=true requires NONGKI_4_4_MODE=auto or susfs-inline; syscall mode is incompatible with the SUSFS hook layer"
fi

case "$MODE" in
  syscall)
    EXPECTED_BLOB="$SYSCALL_SCRIPT_BLOB"
    URL="$SYSCALL_SCRIPT_URL"
    ;;
  susfs-inline)
    is_true "$ENABLE_SUSFS" || fail "susfs-inline mode requires ENABLE_SUSFS=true"
    EXPECTED_BLOB="$INLINE_SCRIPT_BLOB"
    URL="$INLINE_SCRIPT_URL"
    ;;
esac

mkdir -p "$WORK_DIR"
SCRIPT_OUT="$WORK_DIR/nongki-hook-patches.sh"

if [[ -n "$NONGKI_SCRIPT_PATH" ]]; then
  [[ -f "$NONGKI_SCRIPT_PATH" ]] || fail "NONGKI_SCRIPT_PATH does not exist: $NONGKI_SCRIPT_PATH"
  cp -f "$NONGKI_SCRIPT_PATH" "$SCRIPT_OUT"
  log "using local hook script: $NONGKI_SCRIPT_PATH"
else
  command -v curl >/dev/null 2>&1 || fail "curl is required to fetch the pinned NonGKI hook script"
  log "fetching $MODE hook script from ${UPSTREAM_REPO}@${UPSTREAM_COMMIT:0:12}"
  curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused \
    --connect-timeout 15 --max-time 180 "$URL" -o "$SCRIPT_OUT" ||
    fail "unable to fetch pinned NonGKI hook script"
fi

[[ -s "$SCRIPT_OUT" ]] || fail "downloaded NonGKI hook script is empty"
ACTUAL_BLOB="$(git hash-object "$SCRIPT_OUT")"
[[ "$ACTUAL_BLOB" == "$EXPECTED_BLOB" ]] ||
  fail "NonGKI hook SHA mismatch: expected $EXPECTED_BLOB, got $ACTUAL_BLOB"
chmod +x "$SCRIPT_OUT"

log "verified upstream commit=${UPSTREAM_COMMIT}"
log "verified hook blob=${ACTUAL_BLOB}"

# The upstream script is deliberately called exactly once. It detects the
# KernelSU API surface exposed by the provider checkout and applies only hooks
# that exist for this legacy kernel/provider combination.
pushd "$SOURCE_DIR" >/dev/null
bash "$SCRIPT_OUT" . || fail "NonGKI $MODE hook script failed"
popd >/dev/null

# Upstream scripts historically reported failed insertions through stdout and
# continued. Refuse to silently ship a no-op when the source tree has no KSU
# integration points at all.
if ! grep -Rqs --include='*.c' --include='*.h' -E 'ksu_(handle_|bprm_check|hide_setprocattr|file_permission)|CONFIG_KSU' "$SOURCE_DIR/drivers/kernelsu" "$SOURCE_DIR/fs" "$SOURCE_DIR/security" "$SOURCE_DIR/kernel" 2>/dev/null; then
  fail "NonGKI hook stage completed but no KernelSU integration symbols were detected"
fi

# Mirror the upstream no-kprobe action's legacy SELinux static-state fix.
# This is needed only for old KernelSU static-export checking and is skipped
# for KPM builds or trees that already expose both kallsyms modes.
if [[ -f "$SOURCE_DIR/drivers/kernelsu/tools/static_export_check.mk" ]] &&
   grep -q 'check_symbol_export' "$SOURCE_DIR/drivers/kernelsu/tools/static_export_check.mk" &&
   ! is_true "$KPM_ENABLE"; then
  DEFCONFIG_FILE="${DEFCONFIG_FILE:-}"
  KALLSYMS_ENABLED=false
  KALLSYMS_ALL_ENABLED=false
  if [[ -n "$DEFCONFIG_FILE" && -f "$DEFCONFIG_FILE" ]]; then
    grep -q '^CONFIG_KALLSYMS=y$' "$DEFCONFIG_FILE" && KALLSYMS_ENABLED=true || true
    grep -q '^CONFIG_KALLSYMS_ALL=y$' "$DEFCONFIG_FILE" && KALLSYMS_ALL_ENABLED=true || true
  fi

  if [[ "$KALLSYMS_ENABLED" != true || "$KALLSYMS_ALL_ENABLED" != true ]]; then
    SELINUXFS="$SOURCE_DIR/security/selinux/selinuxfs.c"
    if [[ -f "$SELINUXFS" ]]; then
      if grep -qE '^static ssize_t \(\*const write_op\[\]\)' "$SELINUXFS"; then
        sed -i 's/^static ssize_t (\*const write_op\[\])(struct file \*, char \*, size_t)/ssize_t (*const write_op[])(struct file *, char *, size_t)/' "$SELINUXFS"
      elif grep -qE '^static ssize_t \(\*write_op\[\]\)' "$SELINUXFS"; then
        sed -i 's/^static ssize_t (\*write_op\[\])(struct file \*, char \*, size_t)/ssize_t (*write_op[])(struct file *, char *, size_t)/' "$SELINUXFS"
      fi
      sed -i 's/^static const struct file_operations sel_handle_status_ops = {/const struct file_operations sel_handle_status_ops = {/' "$SELINUXFS"
    fi

    # Upstream 4.x handling: SELinux status state was static and therefore not
    # visible to the static export checker. Apply only when each symbol exists.
    if [[ -f "$SOURCE_DIR/security/selinux/ss/status.c" ]]; then
      sed -i 's/^static struct page \*selinux_status_page/struct page *selinux_status_page/' "$SOURCE_DIR/security/selinux/ss/status.c"
      sed -i 's/^static DEFINE_MUTEX(selinux_status_lock)/DEFINE_MUTEX(selinux_status_lock)/' "$SOURCE_DIR/security/selinux/ss/status.c"
    fi
    if [[ -f "$SOURCE_DIR/security/selinux/selinuxfs.c" ]]; then
      sed -i 's/^static DEFINE_MUTEX(sel_mutex)/DEFINE_MUTEX(sel_mutex)/' "$SOURCE_DIR/security/selinux/selinuxfs.c"
    fi
    # For 4.4 and older vendor trees, selinux_ops is commonly static too.
    if [[ -f "$SOURCE_DIR/security/selinux/hooks.c" ]]; then
      KERNEL_MINOR="${KERNEL_VERSION#*.}"
      KERNEL_MINOR="${KERNEL_MINOR%%.*}"
      if [[ "${KERNEL_VERSION%%.*}" -lt 4 || ( "${KERNEL_VERSION%%.*}" -eq 4 && "$KERNEL_MINOR" -lt 19 ) ]]; then
        sed -i 's/^static struct security_operations selinux_ops/struct security_operations selinux_ops/' "$SOURCE_DIR/security/selinux/hooks.c"
      fi
    fi
    log "legacy SELinux static-export cleanup evaluated"
  else
    log "both CONFIG_KALLSYMS and CONFIG_KALLSYMS_ALL enabled; static-export cleanup skipped"
  fi
else
  log "static-export cleanup not required"
fi

HOOK_MARKER="$(mktemp "$WORK_DIR/nongki-marker.XXXXXX")"
grep -Rhs --include='*.c' --include='*.h' -E 'ksu_(handle_execveat|handle_faccessat|handle_sys_read|handle_(newfstat_ret|fstat64_ret|stat)|handle_input_handle_event|bprm_check|handle_rename|handle_setuid|file_permission|hide_setprocattr|handle_sys_reboot|handle_setresuid)' \
  "$SOURCE_DIR/fs" "$SOURCE_DIR/drivers" "$SOURCE_DIR/security" "$SOURCE_DIR/kernel" 2>/dev/null | head -n 1 > "$HOOK_MARKER" || true
[[ -s "$HOOK_MARKER" ]] || fail "NonGKI hook verification found no expected KSU hook markers for mode=$MODE"
rm -f "$HOOK_MARKER"

cat > "$WORK_DIR/nongki-4.4.env" <<EOF_ENV
NONGKI_4_4_ENABLED=true
NONGKI_4_4_DEVICE=lavender
NONGKI_4_4_KERNEL_VERSION=$KERNEL_VERSION
NONGKI_4_4_MODE=$MODE
NONGKI_4_4_UPSTREAM_REPO=https://github.com/$UPSTREAM_REPO
NONGKI_4_4_UPSTREAM_COMMIT=$UPSTREAM_COMMIT
NONGKI_4_4_HOOK_BLOB=$ACTUAL_BLOB
NONGKI_4_4_HOOK_URL=$URL
EOF_ENV

log "completed: device=lavender kernel=$KERNEL_VERSION mode=$MODE"
