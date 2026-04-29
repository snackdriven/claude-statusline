#!/usr/bin/env bash
# meeting region producer — next meeting from ~/.claude/next-meeting.txt
# Region contract: {id, text, color, priority, ttl_sec, updated_at}

set -u

REGION_FILE="$HOME/.claude/buddy/regions/meeting.json"
CACHE_WINDOW=30
PRIORITY=50
TTL_SEC=60
COLOR="yellow"
ID="meeting"

NEXT_FILE="$HOME/.claude/next-meeting.txt"

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

# File missing → empty
if [[ ! -f "$NEXT_FILE" ]]; then
  write_region ""
  exit 0
fi

# First line, trimmed of leading/trailing whitespace
content=$(head -n 1 "$NEXT_FILE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

if [[ -z "$content" ]]; then
  write_region ""
  exit 0
fi

write_region "meet ${content}"
