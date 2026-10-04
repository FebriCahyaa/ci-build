#!/usr/bin/env bash
# Telegram helper + live build dashboard. Notifications are optional; builds
# must still work when Telegram is not configured.
set +u

TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT_ID="${TG_CHAT_ID:-}"
TG_TOPIC_ID="${TG_TOPIC_ID:-}"
TG_MESSAGE_ID="${TG_MESSAGE_ID:-}"
TG_START_TIME="${TG_START_TIME:-$(date +%s)}"
TG_PROGRESS_INTERVAL="${TG_PROGRESS_INTERVAL:-5}"
TG_PROGRESS_WIDTH="${TG_PROGRESS_WIDTH:-20}"
TG_PROGRESS_STATE_FILE="${TG_PROGRESS_STATE_FILE:-${WORK_DIR:-/tmp}/.tg-progress-last}"
TG_HTTP_TIMEOUT="${TG_HTTP_TIMEOUT:-8}"
TG_MAX_RETRIES="${TG_MAX_RETRIES:-3}"

if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
  API="https://api.telegram.org/bot${TG_BOT_TOKEN}"
  TG_ENABLED=true
else
  API=""
  TG_ENABLED=false
fi

tg_msg() {
  [[ "$TG_ENABLED" == true ]] || return 0
  local response="/tmp/tg_last_${TG_CHAT_ID//[^A-Za-z0-9_-]/_}.json"
  curl -fsS --connect-timeout "$TG_HTTP_TIMEOUT" --max-time "$TG_HTTP_TIMEOUT" -X POST "$API/sendMessage" \
    -d chat_id="$TG_CHAT_ID" \
    ${TG_TOPIC_ID:+-d message_thread_id="$TG_TOPIC_ID"} \
    -d parse_mode=HTML \
    -d disable_web_page_preview=true \
    --data-urlencode "text=$1" > "$response" || return 0
  python3 - "$response" <<'PYTG'
import json,sys
try:
    print(json.load(open(sys.argv[1], encoding='utf-8')).get('result',{}).get('message_id',''))
except Exception:
    pass
PYTG
}

tg_edit() {
  [[ "$TG_ENABLED" == true ]] || return 0
  local message_id="${1:-}"
  local message="${2:-}"
  [[ -n "$message_id" ]] || return 0
  local delay=1 attempt response
  for ((attempt=1; attempt<=TG_MAX_RETRIES; attempt++)); do
    response="$(curl -sS --connect-timeout "$TG_HTTP_TIMEOUT" --max-time "$TG_HTTP_TIMEOUT" -X POST "$API/editMessageText" \
      -d chat_id="$TG_CHAT_ID" \
      -d message_id="$message_id" \
      -d parse_mode=HTML \
      -d disable_web_page_preview=true \
      --data-urlencode "text=$message" 2>/dev/null || true)"
    if [[ "$response" == *'"ok":true'* || "$response" == *'message is not modified'* ]]; then
      return 0
    fi
    [[ -n "$response" ]] || {
      [[ "$attempt" -lt "$TG_MAX_RETRIES" ]] && { sleep "$delay"; delay=$((delay * 2)); continue; }
      return 1
    }
    if [[ "$response" == *'retry after'* || "$response" == *'RetryAfter'* ]]; then
      sleep "$delay"
      delay=$((delay * 2))
    else
      return 0
    fi
  done
  return 0
}

tg_file() {
  [[ "$TG_ENABLED" == true ]] || return 0
  local file="${1:-}"
  local caption="${2:-}"
  [[ -f "$file" ]] || return 0
  curl -fsS --connect-timeout "$TG_HTTP_TIMEOUT" --max-time "$TG_HTTP_TIMEOUT" -F chat_id="$TG_CHAT_ID" \
    ${TG_TOPIC_ID:+-F message_thread_id="$TG_TOPIC_ID"} \
    -F "document=@${file}" \
    -F parse_mode=HTML \
    -F "caption=${caption}" \
    "$API/sendDocument" > /dev/null 2>&1 || true
}

tg_escape_html() {
  python3 - "$1" <<'PYTG'
import html,sys
print(html.escape(sys.argv[1]), end='')
PYTG
}

tg_progress_bar() {
  local pct="${1:-0}" width="${2:-20}" i
  ((pct<0)) && pct=0
  ((pct>100)) && pct=100
  local filled=$((pct * width / 100))
  local empty=$((width - filled))
  for ((i=0; i<filled; i++)); do printf '█'; done
  for ((i=0; i<empty; i++)); do printf '░'; done
}

tg_runner_stats() {
  local load cores cpu mem_used mem_total mem_pct
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
  cores="$(nproc 2>/dev/null || echo 1)"
  cpu="$(awk -v l="$load" -v c="$cores" 'BEGIN { v=(l/c)*100; if(v>100)v=100; if(v<0)v=0; printf "%.0f",v }')"
  if command -v free >/dev/null 2>&1; then
    read -r mem_total mem_used < <(free -m | awk '/^Mem:/ {print $2, $3}')
    if [[ "${mem_total:-0}" =~ ^[0-9]+$ ]] && ((mem_total>0)); then
      mem_pct=$((mem_used * 100 / mem_total))
    else
      mem_pct=0
    fi
  else
    mem_pct=0
  fi
  printf '%s|%s|%s' "$cpu" "$mem_pct" "$load"
}

tg_log_tail() {
  local log_file="${1:-}"
  if [[ ! -f "$log_file" ]]; then
    printf '%s' 'Waiting for build output...'
    return 0
  fi
  tail -n 8 "$log_file" 2>/dev/null \
    | tr '\r' '\n' \
    | sed -E $'s/\\x1B\\[[0-9;]*[[:alpha:]]//g' \
    | tail -n 8 \
    | python3 -c 'import html,sys; s=sys.stdin.read().strip(); print(html.escape(s) if s else "Waiting for build output...", end="")' 2>/dev/null || printf '%s' 'Waiting for build output...'
}

tg_progress_update() {
  [[ "$TG_ENABLED" == true ]] || return 0
  local message_id="${TG_MESSAGE_ID:-}"
  [[ -n "$message_id" ]] || return 0
  local pct="${1:-0}" state="${2:-pending}" phase="${3:-build}" detail="${4:-working}" log_file="${5:-${BUILD_LOG:-}}"
  [[ "$pct" =~ ^[0-9]+$ ]] || return 0
  ((pct<0)) && pct=0
  ((pct>100)) && pct=100

  mkdir -p "$(dirname -- "$TG_PROGRESS_STATE_FILE")"
  local now last mtime signature
  now="$(date +%s)"
  last=""
  [[ -f "$TG_PROGRESS_STATE_FILE" ]] && last="$(cat "$TG_PROGRESS_STATE_FILE" 2>/dev/null || true)"
  signature="${pct}|${state}|${phase}|${detail}"
  if [[ "$signature" == "$last" && -z "${CI_PROGRESS_FORCE:-}" ]]; then
    return 0
  fi
  if [[ -f "$TG_PROGRESS_STATE_FILE" && -z "${CI_PROGRESS_FORCE:-}" ]]; then
    mtime="$(stat -c %Y "$TG_PROGRESS_STATE_FILE" 2>/dev/null || echo 0)"
    (( now - mtime < TG_PROGRESS_INTERVAL )) && return 0
  fi

  local elapsed cpu ram load bar tail
  elapsed=$((now - TG_START_TIME))
  IFS='|' read -r cpu ram load <<< "$(tg_runner_stats)"
  bar="$(tg_progress_bar "$pct" "$TG_PROGRESS_WIDTH")"
  tail="$(tg_log_tail "$log_file")"

  local icon safe_phase safe_detail safe_tail text
  case "$state" in
    success|passed) icon='✅' ;;
    failure|failed|error) icon='❌' ;;
    *) icon='🔨' ;;
  esac
  safe_phase="$(tg_escape_html "$phase")"
  safe_detail="$(tg_escape_html "$detail")"
  safe_tail="$tail"
  [[ -n "$safe_tail" ]] || safe_tail='Waiting for build output...'
  # Telegram caps message text at 4096 characters. Bound only the log tail so
  # the structural HTML is never truncated or left with a malformed </pre>.
  safe_tail="${safe_tail:0:2500}"

  text="${icon} <b>Zairenkai Kernel Build</b>"$'\n'
  text+="📱 <code>${DEVICE:-unknown}</code> | 🔐 <code>${VARIANT_LABEL:-${ROOT_VARIANT:-unknown}}</code>"$'\n'
  text+="📊 <code>${pct}%</code> [<code>${bar}</code>]"$'\n'
  text+="🧩 <b>${safe_phase}</b> — ${safe_detail}"$'\n'
  text+="⏱ <code>$(fmt_dur "$elapsed")</code> | 🖥 CPU ~<code>${cpu}%</code> | RAM <code>${ram}%</code> | Load <code>${load}</code>"$'\n'
  if [[ -n "${RUN_URL:-}" ]]; then
    text+="🔗 <a href=\"${RUN_URL}\">GitHub Actions</a>"$'\n'
  fi
  text+=$'\n'"📜 <b>Live log</b>"$'\n'"<pre>${safe_tail}</pre>"

  if tg_edit "$message_id" "$text"; then
    printf '%s\n' "$signature" > "$TG_PROGRESS_STATE_FILE"
  fi
}

fmt_dur() {
  local seconds="${1:-0}"
  if ((seconds >= 3600)); then
    printf '%dh %dm %ds' "$((seconds/3600))" "$(((seconds%3600)/60))" "$((seconds%60))"
  else
    printf '%dm %ds' "$((seconds/60))" "$((seconds%60))"
  fi
}

set -u
