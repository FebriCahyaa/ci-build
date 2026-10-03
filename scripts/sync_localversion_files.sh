#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SRC_ROOT="${1:-${KERNEL_SRC:-}}"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/sync_localversion_files.sh /path/to/kernel/source

Copies the CI repository's source-style localversion files into the kernel
source tree so Kbuild's scripts/setlocalversion sees them during kernelrelease.
USAGE
}

[[ -n "$SRC_ROOT" ]] || { usage >&2; exit 2; }
[[ -d "$SRC_ROOT" ]] || { echo "ERROR: kernel source directory does not exist: $SRC_ROOT" >&2; exit 1; }

validate_suffix_file() {
  local file="$1"
  local label="$2"
  [[ -f "$file" ]] || { echo "ERROR: missing $label file: $file" >&2; exit 1; }

  mapfile -t lines < <(sed -e 's/\r$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$file")
  if ((${#lines[@]} != 1)); then
    echo "ERROR: $label must contain exactly one non-empty value: $file" >&2
    exit 1
  fi

  local value="${lines[0]}"
  [[ "$value" == -* ]] || {
    echo "ERROR: $label must be a localversion suffix beginning with '-': $value" >&2
    exit 1
  }
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || {
    echo "ERROR: $label contains a newline" >&2
    exit 1
  }
  printf '%s\n' "$value"
}

CIP="$(validate_suffix_file "$REPO_ROOT/localversion-cip" localversion-cip)"
ST="$(validate_suffix_file "$REPO_ROOT/localversion-st" localversion-st)"

install -m 0644 "$REPO_ROOT/localversion-cip" "$SRC_ROOT/localversion-cip"
install -m 0644 "$REPO_ROOT/localversion-st" "$SRC_ROOT/localversion-st"

printf '[localversion] synced: %s + %s -> %s\n' "$CIP" "$ST" "$SRC_ROOT"
