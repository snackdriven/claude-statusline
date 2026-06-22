#!/usr/bin/env bash
# cron.sh — info region: scheduled-job (launchd/cron) failures TODAY.
#
# Sources the trusted shared failure surface ~/.claude/logs/cron-failures.log
# (written by ~/.local/bin/cron-alert.sh on any non-zero exit) — the same
# surface the daily-note 🚨 block reads. Display-only, not an alert: empty when
# clean, red "⚙ N jobs ✗" when ≥1 distinct job failed today. Deliberately does
# NOT judge health from `launchctl list` exit codes — those report 0 while a job
# errors every run (see memory: reference-launchd-cron-fails-invisibly-…).
#
# Region contract: {id, text, color, priority, row, ttl_sec, updated_at}

set -u

REGION_FILE="${BUDDY_REGION_DIR:-$HOME/.claude/buddy/regions}/cron.json"
LOG="$HOME/.claude/logs/cron-failures.log"
ID="cron"
PRIORITY=85          # a real failure outranks ctx neighbours (project 60, gh 55)
TTL_SEC=120
COLOR="red"
CACHE_WINDOW=60

# Self-cache: skip work if region was refreshed <CACHE_WINDOW ago
if [[ -f "$REGION_FILE" ]]; then
  prev=$(jq -r '.updated_at // 0' "$REGION_FILE" 2>/dev/null)
  age=$(( $(date +%s) - prev ))
  (( age < CACHE_WINDOW )) && exit 0
fi
mkdir -p "$(dirname "$REGION_FILE")"

today=$(date +%F)
text=""
if [[ -f "$LOG" ]]; then
  jobs=$(grep -E "^\[$today .*\] FAIL job=" "$LOG" 2>/dev/null \
           | sed -E 's/.* job=([^ ]+).*/\1/' | sort -u)
  n=$(printf '%s' "$jobs" | grep -c . 2>/dev/null | tr -d '[:space:]')
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if (( n == 1 )); then
    text="⚙ $(printf '%s' "$jobs" | head -1) ✗"
  elif (( n > 1 )); then
    text="⚙ ${n} jobs ✗"
  fi
fi

now=$(date +%s)
jq -n \
  --arg id "$ID" \
  --arg t "$text" \
  --arg c "$COLOR" \
  --argjson p "$PRIORITY" \
  --argjson ttl "$TTL_SEC" \
  --argjson now "$now" \
  '{id: $id, text: $t, color: $c, priority: $p, row: 0, ttl_sec: $ttl, updated_at: $now}' \
  > "$REGION_FILE"
