#!/usr/bin/env bash
# Modular patch registry runner.
#
#   PHASE=source  apply host-kernel source patches (device, root-manager host, upstream)
#   PHASE=config  merge Kconfig fragments into $KERNEL_OUT/.config
#   PHASE=verify  after olddefconfig: report which fragment values survived
#
# Root-manager registry contract (patches/root-manager/<provider>/<mm>|common/):
#   host-series.conf      host-kernel patches — applied HERE
#   susfs-series.conf     host-kernel SUSFS patches, after host-series (ENABLE_SUSFS)
#   provider-series.conf  provider-tree patches — applied by root_manager_apply.sh
#   config.fragment       Kconfig overrides — applied HERE in the config phase
#   susfs.fragment        Kconfig overrides for ENABLE_SUSFS, after config.fragment
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
CI_LOG_TAG=patches
PATCH_ROOT="${CI_PATCH_ROOT:-$CI_ROOT/patches}"

SOURCE_DIR="${SOURCE_DIR:-}"
DEVICE="${DEVICE:-generic}"
KERNEL_VERSION="${KERNEL_VERSION:-0.0}"
PATCH_PROFILE="${PATCH_PROFILE:-auto}"
UPSTREAM_PROFILE="${UPSTREAM_PROFILE:-auto}"
ROOT_MANAGER="${ROOT_MANAGER:-none}"
KSU_REQUIRED="${KSU_REQUIRED:-false}"
KERNEL_REPO="${KERNEL_REPO:-}"
PHASE="${PHASE:-source}"
LTO_PLUS="${LTO_PLUS:-false}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
KSU_PREINTEGRATED="${KSU_PREINTEGRATED:-false}"
TWEAKS="${TWEAKS:-none}"
SOUTHWEST_NG_REPO="pix106/android_kernel_xiaomi_sdm660_southwest-ng"

# root_manager_apply.sh reports official KernelSU as "official"; the patch
# registry stores it under root-manager/kernelsu.
case "$ROOT_MANAGER" in
  official) ROOT_MANAGER=kernelsu ;;
  ""|vanilla) ROOT_MANAGER=none ;;
esac

fail() { ci_die "$*"; }

[[ -n "$SOURCE_DIR" && -e "$SOURCE_DIR/.git" ]] ||
  fail "SOURCE_DIR must point to a git working tree: ${SOURCE_DIR:-<empty>}"

KERNEL_MM="$(kernel_mm "$KERNEL_VERSION")"

# root_file <provider> <name>: version-specific registry file, falling back to common/.
root_file() {
  local provider="$1" name="$2" candidate
  for candidate in "$PATCH_ROOT/root-manager/$provider/$KERNEL_MM/$name" \
                   "$PATCH_ROOT/root-manager/$provider/common/$name"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
}

series_apply() {
  local series="$1" entry patch patch_commit
  [[ -f "$series" ]] || return 0

  echo "[patches] series=$series"
  while IFS= read -r entry; do
    patch="$entry"
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
    elif python3 "$SCRIPT_DIR/patch_content_check.py" "$SOURCE_DIR" "$patch" >/dev/null 2>&1; then
      echo "[patches] ALREADY APPLIED $patch (content already present)"
    else
      echo "[patches] FAILED CHECK $patch" >&2
      git -C "$SOURCE_DIR" apply --check --whitespace=nowarn "$patch" || true
      fail "patch does not apply cleanly: $patch"
    fi
  done < <(read_series "$series")
}

# config_apply <fragment>: set/unset Kconfig symbols in $KERNEL_OUT/.config.
# Values are passed through the environment, never interpolated into sed/awk
# programs, so '&', '|', '\' and quotes in string options are preserved.
config_apply() {
  local fragment="$1" line key value
  [[ -f "$fragment" ]] || fail "config fragment missing: $fragment"
  [[ -f "$KERNEL_OUT/.config" ]] || fail "kernel output .config missing: $KERNEL_OUT/.config"

  echo "[patches] CONFIG $fragment"
  printf '%s\n' "$fragment" >> "$KERNEL_OUT/.ci-config-fragments"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ "$line" =~ ^\#\ (CONFIG_[A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
      key="${BASH_REMATCH[1]}"
      value=""
    elif [[ "$line" == \#* ]]; then
      continue
    elif [[ "$line" =~ ^(CONFIG_[A-Za-z0-9_]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
    else
      fail "unsupported config fragment line in $fragment: $line"
    fi

    CFG_KEY="$key" CFG_VALUE="$value" awk '
      BEGIN {
        key = ENVIRON["CFG_KEY"]; value = ENVIRON["CFG_VALUE"]
        want = (value == "") ? "# " key " is not set" : key "=" value
        done = 0
      }
      ($0 == "# " key " is not set") || (index($0, key "=") == 1) {
        if (!done) { print want; done = 1 }
        next
      }
      { print }
      END { if (!done) print want }
    ' "$KERNEL_OUT/.config" > "$KERNEL_OUT/.config.ci-tmp"
    mv -f "$KERNEL_OUT/.config.ci-tmp" "$KERNEL_OUT/.config"
  done < "$fragment"
}

# config_verify: compare every merged fragment with the resolved .config.
# Kconfig silently drops values whose dependencies are unmet; report them.
config_verify() {
  local list="$KERNEL_OUT/.ci-config-fragments"
  [[ -f "$list" ]] || { echo "[patches] VERIFY no config fragments were merged"; return 0; }
  # Fragments are checked in merge order: a symbol that a later fragment sets
  # again (e.g. susfs.fragment switching the hook mode) is reported as
  # overridden, not as dropped by Kconfig.
  awk '!seen[$0]++' "$list" | python3 -c '
import re, sys
cfg = sys.argv[1]
frags = [l.strip() for l in sys.stdin if l.strip()]
SET = re.compile(r"^(CONFIG_[A-Za-z0-9_]+)=(.*)$")
UNSET = re.compile(r"^# (CONFIG_[A-Za-z0-9_]+) is not set$")
have = {}
for line in open(cfg, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    m = SET.match(line)
    if m:
        have[m.group(1)] = m.group(2)
    m = UNSET.match(line)
    if m:
        have[m.group(1)] = ""
def entries(frag):
    for line in open(frag, encoding="utf-8"):
        line = line.rstrip("\r\n")
        m = SET.match(line)
        if m:
            yield m.group(1), m.group(2)
            continue
        m = UNSET.match(line)
        if m:
            yield m.group(1), ""
parsed = [(f, list(entries(f))) for f in frags]
short = lambda f: f.split("/patches/", 1)[-1]
for i, (frag, items) in enumerate(parsed):
    later = {}
    for f2, it2 in parsed[i + 1:]:
        for k, _ in it2:
            later.setdefault(k, short(f2))
    dropped, overridden = [], []
    for key, value in items:
        if key in later:
            overridden.append(key + " (by " + later[key] + ")")
        elif have.get(key, "") != value:
            shown = key + "=" + value if value else key + " unset"
            dropped.append(shown + " -> " + (have.get(key) or "unset"))
    want = len(items) - len(overridden)
    msg = "[patches] VERIFY %s: %d/%d applied" % (short(frag), want - len(dropped), want)
    if overridden:
        msg += "; overridden: " + ", ".join(overridden)
    if dropped:
        msg += "; not applied: " + ", ".join(dropped)
    print(msg)
' "$KERNEL_OUT/.config"
}

case "$PHASE" in
  source)
    case "$PATCH_PROFILE" in
      none|off|false|"")
        echo "[patches] device profile disabled (PATCH_PROFILE=$PATCH_PROFILE)"
        ;;
      auto)
        # The Southwest-NG source is already a complete SDM660/Lavender-capable
        # tree. Do not apply legacy SUSFS-only Lavender patches to it.
        if [[ "$KERNEL_REPO" == *"$SOUTHWEST_NG_REPO"* ]]; then
          echo "[patches] auto device profile: southwest-ng (no device source patch)"
        else
          series_apply "$PATCH_ROOT/devices/$DEVICE/$KERNEL_MM/series.conf"
        fi
        ;;
      *)
        series_apply "$PATCH_ROOT/devices/$PATCH_PROFILE/$KERNEL_MM/series.conf"
        ;;
    esac

    # Provider-tree patches are applied to the isolated provider checkout by
    # root_manager_apply.sh. Only host-series.conf may touch the host kernel.
    if is_true "$KSU_REQUIRED" && [[ "$ROOT_MANAGER" != "none" ]]; then
      host_series="$(root_file "$ROOT_MANAGER" host-series.conf)"
      if [[ -n "$host_series" ]]; then
        series_apply "$host_series"
      else
        echo "[patches] no host-kernel series for $ROOT_MANAGER Linux $KERNEL_MM"
      fi
      if is_true "$ENABLE_SUSFS"; then
        susfs_series="$(root_file "$ROOT_MANAGER" susfs-series.conf)"
        [[ -n "$susfs_series" ]] && series_apply "$susfs_series"
      fi
    fi

    case "$UPSTREAM_PROFILE" in
      auto)
        if [[ "$DEVICE" == "lavender" && "$KERNEL_MM" == "4.19" ]]; then
          if [[ "$KERNEL_REPO" == *"$SOUTHWEST_NG_REPO"* ]]; then
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
      none|"") ;;
      *) series_apply "$PATCH_ROOT/upstream/$UPSTREAM_PROFILE/$KERNEL_MM/series.conf" ;;
    esac
    ;;

  config)
    KERNEL_OUT="${KERNEL_OUT:-}"
    [[ -n "$KERNEL_OUT" ]] || fail "KERNEL_OUT is required during config phase"

    rm -f "$KERNEL_OUT/.ci-config-fragments"
    if is_true "$LTO_PLUS" && [[ "$DEVICE" == "lavender" && "$KERNEL_MM" == "4.19" ]]; then
      config_apply "$PATCH_ROOT/features/lto-plus/lavender-4.19/thinlto.config"
    fi

    if [[ "$ROOT_MANAGER" != "none" ]]; then
      root_config="$(root_file "$ROOT_MANAGER" config.fragment)"
      [[ -n "$root_config" ]] && config_apply "$root_config"
    elif is_true "$KSU_PREINTEGRATED"; then
      # Vanilla build of a tree that already carries a root provider.
      config_apply "$PATCH_ROOT/root-manager/none/common/config.fragment"
    fi

    if is_true "$ENABLE_SUSFS"; then
      # Provider-specific SUSFS hook mode first (ReSukiSU 4.19), else the
      # generic upstream SUSFS surface (official KernelSU 4.19).
      susfs_config="$(root_file "$ROOT_MANAGER" susfs.fragment)"
      [[ -n "$susfs_config" ]] || susfs_config="$PATCH_ROOT/features/susfs/kernel-$KERNEL_MM/config.fragment"
      [[ -f "$susfs_config" ]] || fail "SUSFS config fragment missing: $susfs_config"
      config_apply "$susfs_config"
    fi

    # Tweaks go last so they are the final word before olddefconfig.
    case "${TWEAKS,,}" in
      none|off|false|"") ;;
      balanced|performance)
        for level in balanced $([[ "${TWEAKS,,}" == performance ]] && echo performance); do
          tweak="$PATCH_ROOT/features/tweaks/$level/$KERNEL_MM.config"
          if [[ -f "$tweak" ]]; then
            config_apply "$tweak"
          else
            echo "[patches] no $level tweaks for Linux $KERNEL_MM"
          fi
        done
        ;;
      *) fail "invalid TWEAKS=$TWEAKS (use none, balanced or performance)" ;;
    esac
    ;;

  verify)
    KERNEL_OUT="${KERNEL_OUT:-}"
    [[ -n "$KERNEL_OUT" && -f "$KERNEL_OUT/.config" ]] || fail "KERNEL_OUT/.config is required during verify phase"
    config_verify
    ;;

  *) fail "invalid PHASE=$PHASE" ;;
esac
