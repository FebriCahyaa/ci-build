#!/usr/bin/env bash
# Run the ci-build test suite.
#
#   bash tests/run_all.sh                 offline tests (default; what CI gates on)
#   bash tests/run_all.sh --remote        offline + network tests (*_remote_test.sh)
#   bash tests/run_all.sh --remote-only   network tests only
#   bash tests/run_all.sh <name>...       selected tests (file names or basenames)
#
# Tests are discovered as tests/*_test.sh and tests/*_test.py. Tests that need
# network access (upstream clones) are named *_remote_test.*.
set -Euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=offline
declare -a selected=()
for arg in "$@"; do
  case "$arg" in
    --remote) MODE=all ;;
    --remote-only) MODE=remote ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) selected+=("$arg") ;;
  esac
done

mapfile -t all_tests < <(cd "$ROOT/tests" && ls -1 -- *_test.sh *_test.py 2>/dev/null | sort)
declare -a tests=()
if ((${#selected[@]})); then
  for name in "${selected[@]}"; do
    name="$(basename -- "$name")"
    [[ -f "$ROOT/tests/$name" ]] || { echo "unknown test: $name" >&2; exit 2; }
    tests+=("$name")
  done
else
  for name in "${all_tests[@]}"; do
    case "$MODE:$name" in
      offline:*_remote_test.*) ;;
      remote:*_remote_test.*|all:*) tests+=("$name") ;;
      offline:*) tests+=("$name") ;;
    esac
  done
fi

passed=0
declare -a failed=()
for name in "${tests[@]}"; do
  log="$(mktemp)"
  start="$(date +%s)"
  case "$name" in
    *.py) runner=(python3 "$ROOT/tests/$name") ;;
    *)    runner=(bash "$ROOT/tests/$name") ;;
  esac
  if "${runner[@]}" >"$log" 2>&1; then
    printf 'ok    %-58s %4ss\n' "$name" "$(( $(date +%s) - start ))"
    passed=$((passed + 1))
  else
    printf 'FAIL  %-58s %4ss\n' "$name" "$(( $(date +%s) - start ))"
    sed 's/^/      | /' "$log" | tail -n 40
    failed+=("$name")
  fi
  rm -f "$log"
done

echo
echo "passed=$passed failed=${#failed[@]} total=${#tests[@]}"
((${#failed[@]} == 0)) || { printf 'failed: %s\n' "${failed[@]}" >&2; exit 1; }
