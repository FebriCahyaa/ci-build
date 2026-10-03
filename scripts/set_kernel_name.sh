#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
KERNEL_NAME_FILE="${KERNEL_NAME_FILE:-$REPO_ROOT/kernel-name}"
CONFIG_FILE="${CONFIG_FILE:-}"
KERNEL_NAME="${KERNEL_NAME:-}"

usage() {
  cat <<'EOF'
Usage:
  CONFIG_FILE=out/.config KERNEL_NAME="-MyKernel" ./scripts/set_kernel_name.sh
  ./scripts/set_kernel_name.sh --config out/.config --name "-MyKernel"

Behavior:
  empty/auto name -> read from kernel-name in the CI repository
  blank/missing kernel-name -> no-op
  name without leading '-' -> '-'<name>
EOF
}

while (($#)); do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --name) KERNEL_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$CONFIG_FILE" ]] || {
  echo "ERROR: CONFIG_FILE is required" >&2
  exit 1
}
[[ -f "$CONFIG_FILE" ]] || {
  echo "ERROR: config file does not exist: $CONFIG_FILE" >&2
  exit 1
}

if [[ -z "$KERNEL_NAME" || "$KERNEL_NAME" == "auto" ]]; then
  if [[ -f "$KERNEL_NAME_FILE" ]]; then
    mapfile -t _kernel_name_lines < <(sed -e 's/\r$//' \
      -e '/^[[:space:]]*#/d' \
      -e '/^[[:space:]]*$/d' \
      "$KERNEL_NAME_FILE")

    if ((${#_kernel_name_lines[@]} > 1)); then
      echo "ERROR: $KERNEL_NAME_FILE must contain exactly one non-empty value" >&2
      exit 1
    fi

    if ((${#_kernel_name_lines[@]} == 1)); then
      KERNEL_NAME="${_kernel_name_lines[0]}"
    fi
  fi
fi

[[ -n "$KERNEL_NAME" && "$KERNEL_NAME" != "auto" ]] || {
  echo "[kernel-name] unchanged (no explicit name and kernel-name is empty/missing)"
  exit 0
}

case "$KERNEL_NAME" in
  -*) ;;
  *) KERNEL_NAME="-$KERNEL_NAME" ;;
esac

case "$KERNEL_NAME" in
  *$'\n'*|*$'\r'*|*[[:cntrl:]]*)
    echo "ERROR: kernel name contains control characters" >&2
    exit 1
    ;;
esac

export KERNEL_NAME

python3 - "$CONFIG_FILE" <<'PY'
from pathlib import Path
import os
import re
import sys

path = Path(sys.argv[1])
name = os.environ["KERNEL_NAME"]

text = path.read_text(encoding="utf-8")
line = f'CONFIG_LOCALVERSION="{name}"'

if re.search(r'^CONFIG_LOCALVERSION=', text, flags=re.MULTILINE):
    text = re.sub(r'^CONFIG_LOCALVERSION=.*$', line, text, count=1, flags=re.MULTILINE)
else:
    text += ("\n" if text and not text.endswith("\n") else "") + line + "\n"

path.write_text(text, encoding="utf-8")
print(f"[kernel-name] CONFIG_LOCALVERSION={line.removeprefix('CONFIG_LOCALVERSION=')}")
PY
