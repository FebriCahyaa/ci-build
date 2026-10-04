#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
MODE="${1:-status}"
git submodule sync --recursive; git submodule update --init --recursive
case "$MODE" in
  status) git submodule status --recursive ;;
  remote)
    git submodule foreach --recursive '
      branch="$(git config -f "$toplevel/.gitmodules" --get "submodule.$name.branch" 2>/dev/null || true)"
      if [[ -n "$branch" ]]; then git fetch --depth=1 origin "$branch"; git checkout -q --detach "origin/$branch"; else git fetch --depth=1 origin; fi
    '
    echo "Updated working submodules. Commit the resulting gitlink changes in ci-build."
    git submodule status --recursive
    ;;
  *) echo "Usage: $0 [status|remote]" >&2; exit 2 ;;
esac
