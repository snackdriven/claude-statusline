#!/usr/bin/env bash
# meeting region producer — next meeting from ~/.claude/next-meeting.txt
# Region contract: {id, text, color, priority, ttl_sec, updated_at}

set -u

# shellcheck source=../lib/platform.sh
source "$(dirname "$0")/../lib/platform.sh" 2>/dev/null || true

REGION_FILE="${BUDDY_REGION_DIR:-$HOME/.claude/buddy/regions}/meeting.json"
CACHE_WINDOW=30
PRIORITY=70
TTL_SEC=60
COLOR="default"
ID="meeting"

NEXT_FILE="$HOME/.claude/next-meeting.txt"

# Self-cache: skip if region file mtime is fresher than CACHE_WINDOW
if [[ -f "$REGION_FILE" ]]; then
  prev=$(stat_mtime "$REGION_FILE")
  age=$(( $(date +%s) - prev ))
  (( age < CACHE_WINDOW )) && exit 0
fi

write_region() {
  local text="$1"
  local short="${2:-$1}"
  local href="https://calendar.google.com/calendar/u/0/r"   # click → Google Calendar (default browser)
  local now
  now=$(date +%s)
  jq -n \
    --arg id "$ID" \
    --arg t "$text" \
    --arg s "$short" \
    --arg c "$COLOR" \
    --arg h "$href" \
    --argjson p "$PRIORITY" \
    --argjson ttl "$TTL_SEC" \
    --argjson now "$now" \
    '{id: $id, text: $t, short: $s, color: $c, href: $h, priority: $p, row: 2, ttl_sec: $ttl, updated_at: $now}' \
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

# Per-part coloring:
#   📅 emoji          default
#   meeting name      Catppuccin pink (256-color 218)
#   " @ "             bright neutral (256-color 252)
#   date/time         dim dark gray (90)
PINK=$'\033[38;5;218m'
BRIGHT=$'\033[38;5;252m'
DIM=$'\033[90m'
RST=$'\033[0m'
if [[ "$content" == *" @ "* ]]; then
  _name="${content% @ *}"
  _dt="${content##* @ }"
  # short variant: time-first + first word of the name → "📅 9:00a Deploy"
  _time="${_dt##* }"
  _word="${_name%% *}"
  write_region \
    "📅 ${PINK}${_name}${RST}${BRIGHT} @ ${RST}${DIM}${_dt}${RST}" \
    "📅 ${DIM}${_time}${RST} ${PINK}${_word}${RST}"
else
  write_region "📅 ${PINK}${content}${RST}"
fi
