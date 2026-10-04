#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
grep -q 'CI_GITHUB_STATUS_ENABLED' "$ROOT/scripts/progress_beacon.sh"
grep -q 'Telegram is the primary live UI.' "$ROOT/scripts/progress_beacon.sh"
grep -q 'CI_GITHUB_STATUS_ENABLED' "$ROOT/scripts/harness_monitor.py"
echo 'PASS commit status progress is opt-in'
