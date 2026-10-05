#!/usr/bin/env bash
# Shared helpers for ci-build scripts. Source this file; it never exits on its own.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CI_ROOT="${CI_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEFAULT_VARIANTS="vanilla,kernelsu-next,resukisu,sukisu-ultra"

ci_log() { printf '[%s] %s\n' "${CI_LOG_TAG:-ci}" "$*" >&2; }
ci_die() { printf '[%s] ERROR: %s\n' "${CI_LOG_TAG:-ci}" "$*" >&2; exit 1; }

# is_true <value>: accepts true/1/yes/on (case-insensitive).
is_true() {
  case "${1,,}" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# read_value_file <file>: print the single non-comment, non-empty line of a
# value file (kernel-name, kernel-codename, ...). Empty output if missing.
read_value_file() {
  local file="$1" lines
  [[ -f "$file" ]] || return 0
  mapfile -t lines < <(sed -e 's/\r$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$file")
  if ((${#lines[@]} > 1)); then
    ci_die "$file must contain exactly one non-empty value"
  fi
  ((${#lines[@]} == 1)) && printf '%s\n' "${lines[0]}"
  return 0
}

# kernel_mm <version>: "4.19.325" -> "4.19"
kernel_mm() {
  local v="$1" major rest minor
  major="${v%%.*}"
  rest="${v#*.}"
  minor="${rest%%.*}"
  printf '%s.%s\n' "$major" "$minor"
}

# kernel_ge <version> <major> <minor>: true if version >= major.minor
kernel_ge() {
  local v="$1" major rest minor
  major="${v%%.*}"
  rest="${v#*.}"
  minor="${rest%%.*}"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
  (( major > $2 || (major == $2 && minor >= $3) ))
}

# cross_prefix <arch>: GNU triple prefix used for CROSS_COMPILE/CLANG_TRIPLE.
cross_prefix() {
  case "$1" in
    arm64) echo "aarch64-linux-gnu-" ;;
    arm) echo "arm-linux-gnueabi-" ;;
    riscv) echo "riscv64-linux-gnu-" ;;
    *) echo "" ;;
  esac
}

is_commit_ref() {
  [[ "$1" =~ ^[0-9a-fA-F]{40}$ || "$1" =~ ^[0-9a-fA-F]{64}$ ]]
}

# git_fetch_ref <url> <ref> <dir> [depth]: shallow checkout of a branch, tag, or commit.
git_fetch_ref() {
  local url="$1" ref="$2" dir="$3" depth="${4:-1}"
  rm -rf "$dir"
  if is_commit_ref "$ref"; then
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch -q --depth="$depth" origin "$ref"
    git -C "$dir" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
  else
    git -c advice.detachedHead=false clone -q --depth="$depth" --branch "$ref" "$url" "$dir"
  fi
}

# write_env <file> KEY=VALUE...: write shell-quoted assignments that are safe to
# `source`, even when a value contains spaces, '/', '#', quotes, or '$'.
write_env() {
  local file="$1" kv key
  shift
  : > "$file"
  for kv in "$@"; do
    key="${kv%%=*}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || ci_die "write_env: invalid key '$key'"
    printf '%s=%q\n' "$key" "${kv#*=}" >> "$file"
  done
}

# read_series <file>: print the patch entries of a series file, one per line,
# with comments, blank lines, CR line endings and surrounding blanks removed.
read_series() {
  [[ -f "$1" ]] || return 0
  sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "$1"
}

# normalize_variant <name>: canonical root variant id.
#   vanilla | kernelsu | kernelsu-next | resukisu | resukisu-susfs | sukisu-ultra
# "<provider>-susfs" is the provider built with ENABLE_SUSFS=true.
normalize_variant() {
  case "${1,,}" in
    ""|vanilla|none|false|0|no|off|disabled) echo "vanilla" ;;
    ksu|kernelsu|official|kernel-su) echo "kernelsu" ;;
    ksun|kernelsu-next|ksu-next|next) echo "kernelsu-next" ;;
    suki|sukisu|sukisu-ultra|sukisu_ultra|sukisuultra) echo "sukisu-ultra" ;;
    resukisu|re-sukisu) echo "resukisu" ;;
    resukisu-susfs|resukisu+susfs|re-sukisu-susfs) echo "resukisu-susfs" ;;
    *) return 1 ;;
  esac
}

# variant_label <variant>: human label used in zip names, banners, releases.
variant_label() {
  case "$1" in
    vanilla) echo "Vanilla" ;;
    kernelsu) echo "KernelSU" ;;
    kernelsu-next) echo "KernelSU-Next" ;;
    resukisu) echo "ReSukiSU" ;;
    resukisu-susfs) echo "ReSukiSU-SUSFS" ;;
    sukisu-ultra|sukisu_ultra|sukisuultra) echo "SukiSU Ultra" ;;
    *) echo "$1" ;;
  esac
}

# variant_provider <variant>: root provider of a variant ("resukisu-susfs" -> "resukisu").
variant_provider() { printf '%s\n' "${1%-susfs}"; }

# variant_susfs <variant>: true when the variant is built with SUSFS.
variant_susfs() { [[ "$1" == *-susfs ]]; }

# expand_variants <list> [profile-default]: comma/space separated list -> one
# canonical id per line. "", "all" and "default" select the profile default
# (PROFILE_DEFAULT_VARIANTS), falling back to the global release matrix.
expand_variants() {
  local fallback="${2:-$DEFAULT_VARIANTS}"
  local raw="${1:-$fallback}" item v seen=" "
  case "${raw,,}" in all|default|auto) raw="$fallback" ;; esac
  for item in ${raw//,/ }; do
    v="$(normalize_variant "$item")" || ci_die "unknown variant: $item (use vanilla, kernelsu, kernelsu-next, resukisu, resukisu-susfs, sukisu-ultra)"
    [[ "$seen" == *" $v "* ]] && continue
    seen+="$v "
    echo "$v"
  done
}

# load_profile <profile|auto> [device] [kernel-family]: import PROFILE_* from
# profiles/targets. Fails loudly; `eval "$(resolver)"` alone would silently
# evaluate an empty string when the resolver exits non-zero.
load_profile() {
  local profile_env
  profile_env="$(BUILD_PROFILE="$1" DEVICE="${2:-${DEVICE:-}}" KERNEL_FAMILY="${3:-${KERNEL_FAMILY:-}}" \
    bash "$CI_ROOT/scripts/resolve_build_profile.sh")" || ci_die "unable to resolve build profile: $1"
  eval "$profile_env"
}

# kv_get <file> <key>: read key=value files such as build-info.txt.
kv_get() {
  [[ -f "$1" ]] || return 0
  sed -n "s/^$2=//p" "$1" | tail -n1
}

# sudo_if_needed <cmd...>
sudo_if_needed() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}
