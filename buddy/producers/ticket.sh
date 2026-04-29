#!/usr/bin/env bash
# ticket region producer — detects active TTOAD ticket from filesystem activity
# Region contract: {id, text, color, priority, ttl_sec, updated_at}

set -u

REGION_FILE="$HOME/.claude/buddy/regions/ticket.json"
CACHE_WINDOW=30
PRIORITY=80
TTL_SEC=60
ID="ticket"
CONFIG="$HOME/.qa-brain/config.json"

# Self-cache
if [[ -f "$REGION_FILE" ]]; then
  prev=$(jq -r '.updated_at // 0' "$REGION_FILE" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - prev ))
  (( age < CACHE_WINDOW )) && exit 0
fi

now_ts=$(date +%s)

write_region() {
  local text="$1"
  local color="$2"
  jq -n \
    --arg id "$ID" \
    --arg t "$text" \
    --arg c "$color" \
    --argjson p "$PRIORITY" \
    --argjson ttl "$TTL_SEC" \
    --argjson now "$now_ts" \
    '{id: $id, text: $t, color: $c, priority: $p, row: 0, ttl_sec: $ttl, updated_at: $now}' \
    > "$REGION_FILE"
}

# Resolve workspace root
WORKSPACE_ROOT=""
if [[ -f "$CONFIG" ]]; then
  WORKSPACE_ROOT=$(jq -r '.workspaceRoot // empty' "$CONFIG" 2>/dev/null)
fi
if [[ -z "$WORKSPACE_ROOT" || ! -d "$WORKSPACE_ROOT" ]]; then
  write_region "" ""
  exit 0
fi

today=$(date +%Y-%m-%d)
DAILY_DIR="$WORKSPACE_ROOT/dailies/$today"

if [[ ! -d "$DAILY_DIR" ]]; then
  write_region "" ""
  exit 0
fi

# Helper: macOS mtime
mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }

# --- Active ticket extraction (ranked) ---
ticket=""
ticket_mtime=0

# 1. jira-comments
if [[ -d "$DAILY_DIR/jira-comments" ]]; then
  shopt -s nullglob
  best_m=0
  best_f=""
  for f in "$DAILY_DIR/jira-comments"/ttoad-*-*.md; do
    m=$(mtime "$f")
    if (( m > best_m )); then
      best_m=$m
      best_f=$f
    fi
  done
  shopt -u nullglob
  if [[ -n "$best_f" ]]; then
    base=$(basename "$best_f")
    # ttoad-N-... or ttoad-N-ptX-...
    num=$(echo "$base" | sed -E 's/^ttoad-([0-9]+).*/\1/i')
    if [[ -n "$num" && "$num" =~ ^[0-9]+$ ]]; then
      ticket="TTOAD-$num"
      ticket_mtime=$best_m
    fi
  fi
fi

# 2. *-repro/ folders
if [[ -z "$ticket" ]]; then
  shopt -s nullglob
  best_m=0
  best_f=""
  for d in "$DAILY_DIR"/ttoad-*-repro; do
    [[ -d "$d" ]] || continue
    m=$(mtime "$d")
    if (( m > best_m )); then
      best_m=$m
      best_f=$d
    fi
  done
  shopt -u nullglob
  if [[ -n "$best_f" ]]; then
    base=$(basename "$best_f")
    num=$(echo "$base" | sed -E 's/^ttoad-([0-9]+)-repro$/\1/i')
    if [[ -n "$num" && "$num" =~ ^[0-9]+$ ]]; then
      ticket="TTOAD-$num"
      ticket_mtime=$best_m
    fi
  fi
fi

# 3. tickets/*ttoad-N*.md
if [[ -z "$ticket" && -d "$DAILY_DIR/tickets" ]]; then
  shopt -s nullglob
  best_m=0
  best_f=""
  for f in "$DAILY_DIR/tickets"/*ttoad-*.md; do
    m=$(mtime "$f")
    if (( m > best_m )); then
      best_m=$m
      best_f=$f
    fi
  done
  shopt -u nullglob
  if [[ -n "$best_f" ]]; then
    base=$(basename "$best_f")
    num=$(echo "$base" | sed -nE 's/.*ttoad-([0-9]+).*/\1/ip')
    if [[ -n "$num" && "$num" =~ ^[0-9]+$ ]]; then
      ticket="TTOAD-$num"
      ticket_mtime=$best_m
    fi
  fi
fi

# 4. testing-steps HTML — topmost ticket-card
ts_file=""
if [[ -z "$ticket" ]]; then
  shopt -s nullglob
  best_m=0
  for f in "$DAILY_DIR"/testing-steps-*.html; do
    m=$(mtime "$f")
    if (( m > best_m )); then
      best_m=$m
      ts_file=$f
    fi
  done
  shopt -u nullglob
  if [[ -n "$ts_file" ]]; then
    # Try section id first, then h3 fallback
    num=$(grep -oE 'ticket-TTOAD-[0-9]+' "$ts_file" 2>/dev/null | head -1 | sed -E 's/.*TTOAD-([0-9]+).*/\1/')
    if [[ -z "$num" ]]; then
      num=$(grep -oE 'TTOAD-[0-9]+' "$ts_file" 2>/dev/null | head -1 | sed -E 's/TTOAD-([0-9]+)/\1/')
    fi
    if [[ -n "$num" && "$num" =~ ^[0-9]+$ ]]; then
      ticket="TTOAD-$num"
      ticket_mtime=$best_m
    fi
  fi
fi

# Find testing-steps file even if ticket came from earlier rank (for AC progress)
if [[ -z "$ts_file" ]]; then
  shopt -s nullglob
  best_m=0
  for f in "$DAILY_DIR"/testing-steps-*.html; do
    m=$(mtime "$f")
    if (( m > best_m )); then
      best_m=$m
      ts_file=$f
    fi
  done
  shopt -u nullglob
fi

# No ticket found → empty
if [[ -z "$ticket" ]]; then
  write_region "" ""
  exit 0
fi

# --- Workflow step detection (most-specific signal wins) ---
step="idle"
icon="…"

# writing — jira-comments mtime within 5 min
if [[ -d "$DAILY_DIR/jira-comments" ]]; then
  shopt -s nullglob
  for f in "$DAILY_DIR/jira-comments"/*.md; do
    m=$(mtime "$f")
    if (( now_ts - m < 300 )); then
      step="writing"; icon="✏"
      break
    fi
  done
  shopt -u nullglob
fi

# testing — *-repro/ mtime within 10 min (overrides if more recent than writing trigger? per spec: most-specific wins. Order: writing, testing, parsing-acs, starting, idle. We respect first match in priority order: writing first.)
if [[ "$step" == "idle" ]]; then
  shopt -s nullglob
  for d in "$DAILY_DIR"/*-repro; do
    [[ -d "$d" ]] || continue
    m=$(mtime "$d")
    if (( now_ts - m < 600 )); then
      step="testing"; icon="🧪"
      break
    fi
  done
  shopt -u nullglob
fi

# parsing-acs — testing-steps-*.html mtime within 5 min
if [[ "$step" == "idle" ]]; then
  shopt -s nullglob
  for f in "$DAILY_DIR"/testing-steps-*.html; do
    m=$(mtime "$f")
    if (( now_ts - m < 300 )); then
      step="parsing-acs"; icon="📋"
      break
    fi
  done
  shopt -u nullglob
fi

# starting — daily-$today.html exists, no other recent activity
if [[ "$step" == "idle" && -f "$DAILY_DIR/daily-$today.html" ]]; then
  step="starting"; icon="☕"
fi

# --- AC progress ---
progress=""
if [[ -n "$ts_file" && -f "$ts_file" ]]; then
  num="${ticket##*-}"
  total=$(grep -c "type=\"checkbox\" id=\"t${num}-" "$ts_file" 2>/dev/null || echo 0)
  done_n=$(grep -c "type=\"checkbox\" id=\"t${num}-[^\"]*\" checked" "$ts_file" 2>/dev/null || echo 0)
  total=${total//[^0-9]/}
  done_n=${done_n//[^0-9]/}
  total=${total:-0}
  done_n=${done_n:-0}
  if (( total > 0 )); then
    progress=" ${done_n}/${total}"
  fi
fi

# --- Compose ---
if [[ "$step" == "idle" ]]; then
  if [[ -z "$ticket" ]]; then
    write_region "" ""
  else
    idle_min=$(( (now_ts - ticket_mtime) / 60 ))
    write_region "${ticket} … idle ${idle_min}m" "dim"
  fi
else
  write_region "${ticket} ${icon}${progress}" "magenta"
fi
