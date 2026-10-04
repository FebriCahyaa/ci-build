#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PATCH_ROOT="$REPO_ROOT/patches"

SOURCE_DIR="${SOURCE_DIR:-}"
DEVICE="${DEVICE:-generic}"
KERNEL_VERSION="${KERNEL_VERSION:-0.0}"
PATCH_PROFILE="${PATCH_PROFILE:-auto}"
UPSTREAM_PROFILE="${UPSTREAM_PROFILE:-auto}"
ROOT_MANAGER="${ROOT_MANAGER:-none}"
KSU_REQUIRED="${KSU_REQUIRED:-false}"
KSU_SUSFS_REQUIRED="${KSU_SUSFS_REQUIRED:-false}"
KERNEL_REPO="${KERNEL_REPO:-}"
PHASE="${PHASE:-source}"
LTO_PLUS="${LTO_PLUS:-false}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
KSU_PREINTEGRATED="${KSU_PREINTEGRATED:-false}"

# root_manager_apply.sh reports official KernelSU as "official"; the patch
# registry stores it under root-manager/kernelsu.
case "$ROOT_MANAGER" in
  official) ROOT_MANAGER=kernelsu ;;
  ""|vanilla) ROOT_MANAGER=none ;;
esac

# root_file <name>: version-specific registry file, falling back to common/.
root_file() {
  local provider="$1" name="$2"
  if [[ -f "$PATCH_ROOT/root-manager/$provider/$KERNEL_MM/$name" ]]; then
    printf '%s\n' "$PATCH_ROOT/root-manager/$provider/$KERNEL_MM/$name"
  elif [[ -f "$PATCH_ROOT/root-manager/$provider/common/$name" ]]; then
    printf '%s\n' "$PATCH_ROOT/root-manager/$provider/common/$name"
  fi
}

fail() {
  echo "[patches] ERROR: $*" >&2
  exit 1
}

[[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR/.git" ]] ||
  fail "SOURCE_DIR must point to a git working tree: ${SOURCE_DIR:-<empty>}"

major="${KERNEL_VERSION%%.*}"
minor="${KERNEL_VERSION#*.}"
minor="${minor%%.*}"
KERNEL_MM="${major}.${minor}"

series_apply() {
  local series="$1"
  [[ -f "$series" ]] || return 0

  echo "[patches] series=$series"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    local patch="$line"
    [[ "$patch" = /* ]] || patch="$(dirname "$series")/$patch"
    [[ -f "$patch" ]] || fail "patch listed by series is missing: $patch"

    # Some vendor kernels already contain an upstream commit represented by
    # this patch, but later changes may make a strict reverse applicability
    # check fail. Prefer the patch commit metadata when the source history
    # proves that exact commit is already an ancestor.
    patch_commit="$(sed -n '1{/^From [0-9a-fA-F]\{40\} /{s/^From \([0-9a-fA-F]\{40\}\) .*/\1/p;};}' "$patch")"
    if [[ -n "$patch_commit" ]] &&
       git -C "$SOURCE_DIR" cat-file -e "${patch_commit}^{commit}" 2>/dev/null &&
       git -C "$SOURCE_DIR" merge-base --is-ancestor "$patch_commit" HEAD 2>/dev/null; then
      echo "[patches] ALREADY APPLIED $patch (commit ${patch_commit:0:12} is an ancestor)"
      continue
    fi

    if git -C "$SOURCE_DIR" apply --check --whitespace=nowarn "$patch" >/dev/null 2>&1; then
      echo "[patches] APPLY $patch"
      git -C "$SOURCE_DIR" apply --whitespace=nowarn "$patch"
    elif git -C "$SOURCE_DIR" apply -R --check --whitespace=nowarn "$patch" >/dev/null 2>&1; then
      echo "[patches] ALREADY APPLIED $patch"
    elif python3 "$REPO_ROOT/scripts/patch_content_check.py" "$SOURCE_DIR" "$patch" >/dev/null 2>&1; then
      echo "[patches] ALREADY APPLIED $patch (content already present)"
    else
      echo "[patches] FAILED CHECK $patch" >&2
      git -C "$SOURCE_DIR" apply --check --whitespace=nowarn "$patch" || true
      fail "patch does not apply cleanly: $patch"
    fi
  done < "$series"
}

config_apply() {
  local fragment="$1"
  [[ -f "$fragment" ]] || fail "config fragment missing: $fragment"
  [[ -f "$KERNEL_OUT/.config" ]] || fail "kernel output .config missing: $KERNEL_OUT/.config"

  echo "[patches] CONFIG $fragment"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    # Keep "# CONFIG_FOO is not set" (a real directive); skip other comments.
    [[ "${line:0:1}" == "#" && ! "$line" =~ ^\#\ CONFIG_[A-Za-z0-9_]+\ is\ not\ set$ ]] && continue

    case "$line" in
      CONFIG_*=y|CONFIG_*=m|CONFIG_*="\""*"\""|CONFIG_*=*)
        key="${line%%=*}"
        value="${line#*=}"
        if grep -qE "^${key}=" "$KERNEL_OUT/.config"; then
          sed -i -E "s|^${key}=.*$|${key}=${value}|" "$KERNEL_OUT/.config"
        elif grep -qE "^# ${key} is not set$" "$KERNEL_OUT/.config"; then
          sed -i -E "s|^# ${key} is not set$|${key}=${value}|" "$KERNEL_OUT/.config"
        else
          printf '%s\n' "${key}=${value}" >> "$KERNEL_OUT/.config"
        fi
        ;;
      "# CONFIG_"*" is not set")
        key="$(printf '%s' "$line" | sed -E 's/^# (CONFIG_[A-Za-z0-9_]+) is not set$/\1/')"
        if grep -qE "^${key}=" "$KERNEL_OUT/.config"; then
          sed -i -E "s|^${key}=.*$|# ${key} is not set|" "$KERNEL_OUT/.config"
        elif ! grep -qE "^# ${key} is not set$" "$KERNEL_OUT/.config"; then
          printf '# %s is not set\n' "$key" >> "$KERNEL_OUT/.config"
        fi
        ;;
      *)
        fail "unsupported config fragment line: $line"
        ;;
    esac
  done < "$fragment"
}

if [[ "$PHASE" == "source" ]]; then
  case "$PATCH_PROFILE" in
    none|off|false|"")
      echo "[patches] device profile disabled (PATCH_PROFILE=$PATCH_PROFILE)"
      ;;
    auto)
      # The Southwest-NG source is already a complete SDM660/Lavender-capable
      # tree. Do not apply legacy SUSFS-only Lavender patches to it.
      if [[ "$KERNEL_REPO" == *"pix106/android_kernel_xiaomi_sdm660_southwest-ng"* ]]; then
        echo "[patches] auto device profile: southwest-ng (no device source patch)"
      else
        device_series="$PATCH_ROOT/devices/$DEVICE/$KERNEL_MM/series.conf"
        series_apply "$device_series"
      fi
      ;;
    *)
      device_series="$PATCH_ROOT/devices/$PATCH_PROFILE/$KERNEL_MM/series.conf"
      series_apply "$device_series"
      ;;
  esac

  if [[ "$KSU_REQUIRED" == "true" && "$ROOT_MANAGER" != "none" ]]; then
    # Provider patches target the isolated provider checkout and are handled
    # by root_manager_apply.sh. Some provider versions additionally require a
    # small compatibility backport in the host kernel tree itself. Keep those
    # patches in a separate host-series registry so they never touch the
    # provider gitlink/submodule.
    if [[ "$ROOT_MANAGER" == "kernelsu-next" ]]; then
      # KernelSU-Next provider patches are applied inside the isolated
      # provider checkout by root_manager_apply.sh. Only host-series.conf
      # is allowed to touch the host kernel tree.
      host_series="$PATCH_ROOT/root-manager/kernelsu-next/$KERNEL_MM/host-series.conf"
      [[ -f "$host_series" ]] && series_apply "$host_series"
    else
      root_series="$(root_file "$ROOT_MANAGER" series.conf)"
      [[ -n "$root_series" ]] && series_apply "$root_series"
    fi
  fi

  case "$UPSTREAM_PROFILE" in
    auto)
      if [[ "$DEVICE" == "lavender" && "$KERNEL_MM" == "4.19" ]]; then
        if [[ "$KERNEL_REPO" == *"pix106/android_kernel_xiaomi_sdm660_southwest-ng"* ]]; then
          echo "[patches] auto upstream profile: southwest-ng (no legacy CodeLinaro patch set)"
        else
          series_apply "$PATCH_ROOT/upstream/codelinaro/sdm660-4.19/series.conf"
        fi
      fi
      ;;
    codelinaro-sdm660)
      if [[ "$DEVICE" == "lavender" && "$KERNEL_MM" == "4.19" ]]; then
        series_apply "$PATCH_ROOT/upstream/codelinaro/sdm660-4.19/series.conf"
      fi
      ;;
    none|"")
      ;;
    *)
      series_apply "$PATCH_ROOT/upstream/$UPSTREAM_PROFILE/$KERNEL_MM/series.conf"
      ;;
  esac

elif [[ "$PHASE" == "config" ]]; then
  KERNEL_OUT="${KERNEL_OUT:-}"
  [[ -n "$KERNEL_OUT" ]] || fail "KERNEL_OUT is required during config phase"

  if [[ "$LTO_PLUS" == "true" || "$LTO_PLUS" == "1" ]]; then
    if [[ "$DEVICE" == "lavender" && "$KERNEL_MM" == "4.19" ]]; then
      config_apply "$PATCH_ROOT/features/lto-plus/lavender-4.19/thinlto.config"
    fi
  fi

  if [[ "$ROOT_MANAGER" != "none" ]]; then
    root_config="$(root_file "$ROOT_MANAGER" config.fragment)"
    [[ -n "$root_config" ]] && config_apply "$root_config"
  elif [[ "$KSU_PREINTEGRATED" == "true" ]]; then
    # Vanilla build of a tree that already carries a root provider.
    config_apply "$PATCH_ROOT/root-manager/none/common/config.fragment"
  fi

  if [[ "$ENABLE_SUSFS" == "true" || "$ENABLE_SUSFS" == "1" ]]; then
    susfs_config="$PATCH_ROOT/features/susfs/kernel-$KERNEL_MM/config.fragment"
    [[ -f "$susfs_config" ]] || fail "SUSFS config fragment missing: $susfs_config"
    config_apply "$susfs_config"
  fi
else
  fail "invalid PHASE=$PHASE"
fi