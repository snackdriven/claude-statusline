#!/usr/bin/env bash
# coord region producer — coordinator heartbeat + worker dots
# Region contract: {id, text, color, priority, ttl_sec, updated_at}

set -u

REGION_FILE="$HOME/.claude/buddy/regions/coord.json"
CACHE_WINDOW=10
PRIORITY=75
TTL_SEC=30
COLOR="cyan"
ID="coord"

HEARTBEAT="$HOME/.memory-keeper/coordinator-heartbeat.json"
REGISTRY="$HOME/.memory-keeper/session-registry.json"
HEARTBEAT_MAX_AGE=180

# Self-cache: skip if region file mtime is fresher than CACHE_WINDOW
if [[ -f "$REGION_FILE" ]]; then
  prev=$(stat -f%m "$REGION_FILE" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - prev ))
  (( age < CACHE_WINDOW )) && exit 0
fi

write_region() {
  local text="$1"
  local now
  now=$(date +%s)
  jq -n \
    --arg id "$ID" \
    --arg t "$text" \
    --arg c "$COLOR" \
    --argjson p "$PRIORITY" \
    --argjson ttl "$TTL_SEC" \
    --argjson now "$now" \
    '{id: $id, text: $t, color: $c, priority: $p, row: 1, ttl_sec: $ttl, updated_at: $now}' \
    > "$REGION_FILE"
}

# Heartbeat missing or stale → empty text
if [[ ! -f "$HEARTBEAT" ]]; then
  write_region ""
  exit 0
fi

# macOS stat -f%m for mtime
last=$(stat -f%m "$HEARTBEAT" 2>/dev/null || echo 0)
now_ts=$(date +%s)
hb_age=$(( now_ts - last ))

if (( hb_age >= HEARTBEAT_MAX_AGE )); then
  write_region ""
  exit 0
fi

# Active heartbeat — count workers from session-registry.json
total=0
active=0
if [[ -f "$REGISTRY" ]]; then
  total=$(jq '[.workers[]?] | length' "$REGISTRY" 2>/dev/null || echo 0)
  active=$(jq '[.workers[]? | select(.status == "active")] | length' "$REGISTRY" 2>/dev/null || echo 0)
fi

# Compose dots
if (( total == 0 )); then
  text="🎯"
elif (( total > 5 )); then
  text="🎯 +${total}"
else
  dots=""
  i=0
  while (( i < active )); do dots+="●"; i=$((i+1)); done
  while (( i < total )); do dots+="○"; i=$((i+1)); done
  text="🎯 ${dots}"
fi

write_region "$text"
