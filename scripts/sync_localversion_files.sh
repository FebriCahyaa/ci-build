#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SRC_ROOT="${1:-${KERNEL_SRC:-}}"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/sync_localversion_files.sh /path/to/kernel/source

Validates the CI localversion inputs and clears source localversion files.
The canonical combined project/build suffix is written into CONFIG_LOCALVERSION
by set_kernel_name.sh so the project name stays before the build suffix.
USAGE
}

[[ -n "$SRC_ROOT" ]] || { usage >&2; exit 2; }
[[ -d "$SRC_ROOT" ]] || { echo "ERROR: kernel source directory does not exist: $SRC_ROOT" >&2; exit 1; }

validate_suffix_file() {
  local file="$1"
  local label="$2"
  local allow_empty="${3:-false}"
  [[ -f "$file" ]] || { echo "ERROR: missing $label file: $file" >&2; exit 1; }

  mapfile -t lines < <(sed -e 's/\r$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$file")
  if ((${#lines[@]} == 0)) && [[ "$allow_empty" == true ]]; then
    printf '\n'
    return 0
  fi
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

# Validate the CI inputs (exit on malformed files); the values themselves are
# consumed by set_kernel_name.sh.
validate_suffix_file "$REPO_ROOT/localversion-cip" localversion-cip true >/dev/null
validate_suffix_file "$REPO_ROOT/localversion-st" localversion-st >/dev/null

# The complete suffix is already stored in CONFIG_LOCALVERSION by set_kernel_name.sh.
# Clear both source files because Linux 4.4 appends them before CONFIG_LOCALVERSION.
: > "$SRC_ROOT/localversion-cip"
: > "$SRC_ROOT/localversion-st"

printf '[localversion] source localversion files cleared; suffix is controlled by .config -> %s\n' "$SRC_ROOT"
