#!/usr/bin/env bash
# Resolve the requested root variants for one target profile.
#
#   BUILD_PROFILE=lavender-4.4 VARIANTS=default scripts/resolve_variants.sh [--json]
#
# VARIANTS accepts "default"/"all"/"" (profile default set) or an explicit
# comma/space separated list. Aliases are normalized and duplicates removed
# while preserving order. --json prints a compact JSON array for CI matrices.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
CI_LOG_TAG=variants

FORMAT=lines
case "${1:-}" in
  --json) FORMAT=json ;;
  "") ;;
  *) ci_die "usage: resolve_variants.sh [--json]" ;;
esac

load_profile "${BUILD_PROFILE:?BUILD_PROFILE is required}"
# Command substitution (not process substitution) so an unknown variant fails the script.
resolved="$(expand_variants "${VARIANTS:-default}" "${PROFILE_DEFAULT_VARIANTS:-}")" || exit 1
mapfile -t variants <<< "$resolved"
[[ -n "$resolved" ]] || ci_die "no root variants selected"

if [[ "$FORMAT" == json ]]; then
  printf '%s\n' "${variants[@]}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().split(), separators=(",", ":")))'
else
  printf '%s\n' "${variants[@]}"
fi
