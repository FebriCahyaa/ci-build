#!/usr/bin/env bash
# Telegram helper + live build dashboard. Notifications are optional; builds
# must still work when Telegram is not configured.
set +u

TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT_ID="${TG_CHAT_ID:-}"
TG_TOPIC_ID="${TG_TOPIC_ID:-}"
TG_RELEASE_TOPIC_ID="${TG_RELEASE_TOPIC_ID:-}"
TG_REQUIRE_TOPIC="${TG_REQUIRE_TOPIC:-false}"
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

tg_api_ok() {
  python3 -c 'import json,sys
try:
 d=json.load(sys.stdin); sys.exit(0 if d.get("ok") is True else 1)
except Exception: sys.exit(1)' <<<"${1:-}"
}

tg_msg() {
  [[ "$TG_ENABLED" == true ]] || return 0
  if [[ "$TG_REQUIRE_TOPIC" == true && -z "$TG_TOPIC_ID" && -z "$TG_RELEASE_TOPIC_ID" ]]; then
    echo "[telegram] refusing to send: no Telegram topic configured" >&2
    return 1
  fi
  local message="${1:-}" response="" attempt delay=1
  local topic="${TG_TOPIC_ID:-}"
  if [[ -z "$topic" ]]; then topic="${TG_RELEASE_TOPIC_ID:-}"; fi

  _tg_send_message() {
    local current_topic="$1"
    local plain_mode="$2"
    local -a args=(-d "chat_id=$TG_CHAT_ID" -d "disable_web_page_preview=true")
    [[ -n "$current_topic" ]] && args+=(-d "message_thread_id=$current_topic")
    if [[ "$plain_mode" == true ]]; then
      args+=(--data-urlencode "text=$message")
    else
      args+=(-d "parse_mode=HTML" --data-urlencode "text=$message")
    fi
    curl -sS --connect-timeout "$TG_HTTP_TIMEOUT" --max-time "$TG_HTTP_TIMEOUT" \
      -X POST "$API/sendMessage" "${args[@]}" 2>/dev/null || true
  }

  for ((attempt=1; attempt<=TG_MAX_RETRIES; attempt++)); do
    response="$(_tg_send_message "$topic" false)"
    if tg_api_ok "$response"; then
      python3 -c 'import json,sys; print(json.load(sys.stdin).get("result",{}).get("message_id",""))' <<<"$response"
      return 0
    fi

    if [[ "$response" == *"can't parse entities"* || "$response" == *"parse entities"* ]]; then
      echo "[telegram] sendMessage HTML rejected; retrying once as plain text" >&2
      local plain
      plain="$(python3 - "$message" <<'PYTGPLAIN'
import html,re,sys
s=sys.argv[1]
s=re.sub(r'<[^>]+>', '', s)
print(html.unescape(s), end='')
PYTGPLAIN
)"
      local plain_args=(-d "chat_id=$TG_CHAT_ID" -d "disable_web_page_preview=true")
      [[ -n "$topic" ]] && plain_args+=(-d "message_thread_id=$topic")
      plain_args+=(--data-urlencode "text=$plain")
      response="$(curl -sS --connect-timeout "$TG_HTTP_TIMEOUT" --max-time "$TG_HTTP_TIMEOUT" \
        -X POST "$API/sendMessage" "${plain_args[@]}" 2>/dev/null || true)"
      if tg_api_ok "$response"; then
        python3 -c 'import json,sys; print(json.load(sys.stdin).get("result",{}).get("message_id",""))' <<<"$response"
        return 0
      fi
    fi

    # A stale/missing build topic must never suppress the notification.
    # Try the dedicated release topic and finally General (no thread id).
    if [[ -n "$TG_RELEASE_TOPIC_ID" && "$TG_RELEASE_TOPIC_ID" != "$topic" ]]; then
      echo "[telegram] primary topic delivery failed; retrying release topic" >&2
      topic="$TG_RELEASE_TOPIC_ID"
      response="$(_tg_send_message "$topic" true)"
      if tg_api_ok "$response"; then
        python3 -c 'import json,sys; print(json.load(sys.stdin).get("result",{}).get("message_id",""))' <<<"$response"
        return 0
      fi
    fi

    echo "[telegram] topic delivery failed; retrying General topic" >&2
    response="$(_tg_send_message "" true)"
    if tg_api_ok "$response"; then
      python3 -c 'import json,sys; print(json.load(sys.stdin).get("result",{}).get("message_id",""))' <<<"$response"
      return 0
    fi

    echo "[telegram] sendMessage failed (attempt $attempt/$TG_MAX_RETRIES): $(printf '%s' "$response" | head -c 500)" >&2
    (( attempt < TG_MAX_RETRIES )) && { sleep "$delay"; delay=$((delay * 2)); }
  done
  return 1
}

tg_edit() {
  [[ "$TG_ENABLED" == true ]] || return 0
  local message_id="${1:-}" message="${2:-}" response="" attempt delay=1
  [[ -n "$message_id" ]] || return 0
  local args=(-d "chat_id=$TG_CHAT_ID" -d "message_id=$message_id" -d "parse_mode=HTML" -d "disable_web_page_preview=true")
  args+=(--data-urlencode "text=$message")
  for ((attempt=1; attempt<=TG_MAX_RETRIES; attempt++)); do
    response="$(curl -sS --connect-timeout "$TG_HTTP_TIMEOUT" --max-time "$TG_HTTP_TIMEOUT" -X POST "$API/editMessageText" "${args[@]}" 2>/dev/null || true)"
    if tg_api_ok "$response" || [[ "$response" == *'message is not modified'* ]]; then return 0; fi
    if [[ "$response" == *"can't parse entities"* || "$response" == *"parse entities"* ]]; then
      echo "[telegram] editMessageText HTML rejected; retrying once as plain text" >&2
      local plain
      plain="$(python3 - "$message" <<'PYTGPLAINEDIT'
import html,re,sys
s=sys.argv[1]
s=re.sub(r'<[^>]+>', '', s)
print(html.unescape(s), end='')
PYTGPLAINEDIT
)"
      local plain_args=(-d "chat_id=$TG_CHAT_ID" -d "message_id=$message_id" -d "disable_web_page_preview=true")
      plain_args+=(--data-urlencode "text=$plain")
      response="$(curl -sS --connect-timeout "$TG_HTTP_TIMEOUT" --max-time "$TG_HTTP_TIMEOUT" -X POST "$API/editMessageText" "${plain_args[@]}" 2>/dev/null || true)"
      if tg_api_ok "$response" || [[ "$response" == *'message is not modified'* ]]; then return 0; fi
      break
    fi
    echo "[telegram] editMessageText failed (attempt $attempt/$TG_MAX_RETRIES): $(printf '%s' "$response" | head -c 300)" >&2
    (( attempt < TG_MAX_RETRIES )) && { sleep "$delay"; delay=$((delay * 2)); }
  done
  return 1
}

tg_send_document_once() {
  local file="$1" caption="$2" response="" attempt delay=1
  if [[ "$TG_REQUIRE_TOPIC" == true && -z "$TG_TOPIC_ID" && -z "$TG_RELEASE_TOPIC_ID" ]]; then
    echo "[telegram] refusing document upload: no Telegram topic is configured" >&2
    return 1
  fi
  local topic="${TG_TOPIC_ID:-}"
  if [[ -z "$topic" ]]; then topic="${TG_RELEASE_TOPIC_ID:-}"; fi
  local args=(-F "chat_id=$TG_CHAT_ID")
  [[ -n "$topic" ]] && args+=(-F "message_thread_id=$topic")
  args+=(-F "document=@$file" -F "parse_mode=HTML" -F "caption=$caption")
  for ((attempt=1; attempt<=TG_MAX_RETRIES; attempt++)); do
    response="$(curl -sS --connect-timeout "$TG_HTTP_TIMEOUT" --max-time 180 -X POST "$API/sendDocument" "${args[@]}" 2>/dev/null || true)"
    if tg_api_ok "$response"; then return 0; fi
    if [[ -n "$TG_RELEASE_TOPIC_ID" && "$TG_RELEASE_TOPIC_ID" != "$topic" ]]; then
      echo "[telegram] primary topic document delivery failed; retrying release topic" >&2
      local fallback_args=(
        -F "chat_id=$TG_CHAT_ID"
        -F "message_thread_id=$TG_RELEASE_TOPIC_ID"
        -F "document=@$file"
        -F "parse_mode=HTML"
        -F "caption=$caption"
      )
      response="$(curl -sS --connect-timeout "$TG_HTTP_TIMEOUT" --max-time 180         -X POST "$API/sendDocument" "${fallback_args[@]}" 2>/dev/null || true)"
      if tg_api_ok "$response"; then return 0; fi
    fi
    echo "[telegram] sendDocument failed (attempt $attempt/$TG_MAX_RETRIES): $(printf '%s' "$response" | head -c 500)" >&2
    (( attempt < TG_MAX_RETRIES )) && { sleep "$delay"; delay=$((delay * 2)); }
  done
  return 1
}

tg_file() {
  [[ "$TG_ENABLED" == true ]] || return 0
  local file="${1:-}" caption="${2:-}" size max_bytes=47185920 tempdir part count i
  [[ -f "$file" ]] || { echo "[telegram] file not found: $file" >&2; return 1; }
  size="$(stat -c%s "$file" 2>/dev/null || wc -c < "$file")"
  if (( size <= max_bytes )); then
    tg_send_document_once "$file" "$caption"
    return $?
  fi
  # Keep each chunk below Telegram Bot API's 50 MB document limit.
  tempdir="$(mktemp -d "${TMPDIR:-/tmp}/tg-parts.XXXXXX")" || return 1
  split -b 45M -d -a 3 "$file" "$tempdir/part-" || { rm -rf "$tempdir"; return 1; }
  count="$(find "$tempdir" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  i=1
  for part in "$tempdir"/part-*; do
    if ! tg_send_document_once "$part" "📦 ${caption} — part ${i}/${count}"; then
      rm -rf "$tempdir"
      return 1
    fi
    i=$((i+1))
  done
  rm -rf "$tempdir"
  return 0
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

  local icon safe_phase safe_detail safe_tail safe_run_url text
  case "$state" in
    success|passed) icon='✅' ;;
    failure|failed|error) icon='❌' ;;
    *) icon='🔨' ;;
  esac
  safe_phase="$(tg_escape_html "$phase")"
  safe_detail="$(tg_escape_html "$detail")"
  safe_run_url="$(tg_escape_html "${RUN_URL:-}")"
  safe_tail="$tail"
  [[ -n "$safe_tail" ]] || safe_tail='Waiting for build output...'
  # Telegram caps message text at 4096 characters. Bound only the log tail so
  # the structural HTML is never truncated or left with a malformed </pre>.
  safe_tail="${safe_tail:0:2500}"

  text="${icon} <b>Zairenkai Kernel Build</b>"$'\n'
  text+="🧭 Target: <code>${BUILD_PROFILE:-unknown}</code>"$'\n'
  text+="📱 <code>${DEVICE:-unknown}</code> | 🔐 <code>${VARIANT_LABEL:-${ROOT_VARIANT:-unknown}}</code>"$'\n'
  text+="📊 <code>${pct}%</code> [<code>${bar}</code>]"$'\n'
  text+="🧩 <b>${safe_phase}</b> — ${safe_detail}"$'\n'
  text+="⏱ <code>$(fmt_dur "$elapsed")</code> | 🖥 CPU ~<code>${cpu}%</code> | RAM <code>${ram}%</code> | Load <code>${load}</code>"$'\n'
  if [[ -n "${RUN_URL:-}" ]]; then
    text+="🔗 <a href=\"${safe_run_url}\">GitHub Actions</a>"$'\n'
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
