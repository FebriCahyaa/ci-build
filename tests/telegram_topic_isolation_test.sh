#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TG="$ROOT/scripts/tg.sh"
FAIL="$ROOT/scripts/send_harness_failure_to_telegram.sh"
WF="$ROOT/.github/workflows/harness-kernel.yml"
PIPE="$ROOT/harness/kernel-pipeline.yaml"

grep -q 'local topic="${TG_TOPIC_ID:-}"' "$TG" || { echo 'FAIL: regular Telegram messages do not use build topic only' >&2; exit 1; }
! grep -q 'TG_RELEASE_TOPIC_ID' "$TG" || { echo 'FAIL: build Telegram helper references release topic' >&2; exit 1; }
grep -q -- '-z "${TG_TOPIC_ID:-}"' "$FAIL" || { echo 'FAIL: Harness failure script is not bound to build topic' >&2; exit 1; }
grep -q 'message_thread_id=$TG_TOPIC_ID' "$FAIL" || { echo 'FAIL: Harness failure script does not post to TG_TOPIC_ID' >&2; exit 1; }
! grep -q 'TG_RELEASE_TOPIC_ID' "$FAIL" || { echo 'FAIL: Harness failure script references release topic' >&2; exit 1; }

a=$(sed -n '/- name: Telegram Harness trigger failure fallback/,/- name: Live monitor Harness execution/p' "$WF")
grep -q 'TG_TOPIC_ID:.*TG_TOPIC_ID' <<<"$a" || { echo 'FAIL: trigger failure fallback is not bound to build topic' >&2; exit 1; }
! grep -q 'TG_RELEASE_TOPIC_ID' <<<"$a" || { echo 'FAIL: trigger failure fallback references release topic' >&2; exit 1; }

a=$(sed -n '/- name: Telegram Harness failure fallback/,/- name: Relay published Harness release to Telegram release topic/p' "$WF")
grep -q 'TG_TOPIC_ID:.*TG_TOPIC_ID' <<<"$a" || { echo 'FAIL: build failure fallback is not bound to build topic' >&2; exit 1; }
! grep -q 'TG_RELEASE_TOPIC_ID' <<<"$a" || { echo 'FAIL: build failure fallback references release topic' >&2; exit 1; }

[[ "$(grep -c 'TG_RELEASE_TOPIC_ID:' "$PIPE")" -eq 0 ]] || { echo 'FAIL: Harness build step still injects release topic' >&2; exit 1; }
grep -q 'TG_RELEASE_TOPIC_ID:.*TG_RELEASE_TOPIC_ID' "$WF" || { echo 'FAIL: release relay is missing release topic' >&2; exit 1; }
echo 'PASS: Telegram build/failure notifications are isolated to TG_TOPIC_ID'
