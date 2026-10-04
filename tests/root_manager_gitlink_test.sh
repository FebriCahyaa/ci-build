#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
for path in \
  third_party/root-managers/kernelsu \
  third_party/root-managers/kernelsu-next \
  third_party/root-managers/resukisu \
  third_party/root-managers/sukisu-ultra; do
  if git ls-files --stage -- "$path" | awk '$1 == "160000" {ok=1} END {exit ok ? 0 : 1}'; then
    echo "PASS: gitlink $path"
  else
    echo "FAIL: missing gitlink $path" >&2
    fail=1
  fi
done

[[ -f .gitmodules ]] || { echo 'FAIL: .gitmodules missing' >&2; fail=1; }

exit "$fail"
