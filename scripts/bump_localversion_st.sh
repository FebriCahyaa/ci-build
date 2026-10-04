#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
REPO_ROOT="$CI_ROOT"
FILE="${LOCALVERSION_ST_FILE:-$REPO_ROOT/localversion-st}"
CODENAME_FILE="${KERNEL_CODENAME_FILE:-$REPO_ROOT/kernel-codename}"
BUILD_FILE="${KERNEL_BUILD_FILE:-$REPO_ROOT/kernel-build}"
CODENAME="${KERNEL_CODENAME:-}"
BUILD="${KERNEL_BUILD:-}"
BUMP=false

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/bump_localversion_st.sh --codename VEGA --build 1
  ./scripts/bump_localversion_st.sh --bump

Formats localversion-st as:
  -<CODENAME><BUILD>

Examples:
  -VEGA1 -> -VEGA2 when --bump is used.
USAGE
}

while (($#)); do
  case "$1" in
    --codename) CODENAME="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --bump) BUMP=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

current="$(read_value_file "$FILE")"
[[ -n "$CODENAME" ]] || CODENAME="$(read_value_file "$CODENAME_FILE")"
[[ -n "$BUILD" ]] || BUILD="$(read_value_file "$BUILD_FILE")"

if [[ "$BUMP" == true ]]; then
  [[ -n "$current" ]] || { echo "ERROR: cannot bump missing/empty $FILE" >&2; exit 1; }
  [[ "$current" =~ ^-([A-Za-z0-9][A-Za-z0-9._-]*)([0-9]+)$ ]] || {
    echo "ERROR: unsupported localversion-st format: $current" >&2
    exit 1
  }
  CODENAME="${BASH_REMATCH[1]}"
  BUILD="$((10#${BASH_REMATCH[2]} + 1))"
fi

[[ -n "$CODENAME" ]] || { echo "ERROR: codename is required" >&2; exit 1; }
[[ "$CODENAME" =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]] || { echo "ERROR: invalid codename: $CODENAME" >&2; exit 1; }
[[ -n "$BUILD" && "$BUILD" =~ ^[0-9]+$ ]] || { echo "ERROR: build must be a non-negative integer" >&2; exit 1; }

BUILD_NUM="$((10#$BUILD))"
printf '%s\n' "$CODENAME" > "$CODENAME_FILE"
printf '%s\n' "$BUILD_NUM" > "$BUILD_FILE"
printf -- '-%s%s\n' "$CODENAME" "$BUILD_NUM" > "$FILE"
printf '[localversion-st] %s (codename=%s build=%s)\n' "$(cat "$FILE")" "$CODENAME" "$BUILD_NUM"