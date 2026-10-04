#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec env TARGET=github bash "$SCRIPT_DIR/start_local_ci.sh" "$@"
