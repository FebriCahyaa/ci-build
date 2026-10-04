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
    git -C "$dir" checkout -q --detach FETCH_HEAD
  else
    git clone -q --depth="$depth" --branch "$ref" "$url" "$dir"
  fi
}

# normalize_variant <name>: canonical root variant id.
#   vanilla | kernelsu | kernelsu-next | resukisu | sukisu-ultra
normalize_variant() {
  case "${1,,}" in
    ""|vanilla|none|false|0|no|off|disabled) echo "vanilla" ;;
    ksu|kernelsu|official|kernel-su) echo "kernelsu" ;;
    ksun|kernelsu-next|ksu-next|next) echo "kernelsu-next" ;;
    suki|sukisu|sukisu-ultra|sukisu_ultra|sukisuultra) echo "sukisu-ultra" ;;
    resukisu|re-sukisu) echo "resukisu" ;;
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
    sukisu-ultra|sukisu_ultra|sukisuultra) echo "SukiSU Ultra" ;;
    *) echo "$1" ;;
  esac
}

# expand_variants <list>: "all", comma or space separated list -> one canonical id per line.
expand_variants() {
  local raw="${1:-$DEFAULT_VARIANTS}" item v seen=" "
  [[ "${raw,,}" == "all" ]] && raw="$DEFAULT_VARIANTS"
  for item in ${raw//,/ }; do
    v="$(normalize_variant "$item")" || ci_die "unknown variant: $item (use vanilla, kernelsu, kernelsu-next, resukisu, sukisu-ultra)"
    [[ "$seen" == *" $v "* ]] && continue
    seen+="$v "
    echo "$v"
  done
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