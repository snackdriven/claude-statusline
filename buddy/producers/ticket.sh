#!/usr/bin/env bash
# ticket region producer — detects active TTOAD ticket from filesystem activity
# Region contract: {id, text, color, priority, ttl_sec, updated_at}

set -u

# shellcheck source=../lib/platform.sh
source "$(dirname "$0")/../lib/platform.sh" 2>/dev/null || true

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

mtime() { stat_mtime "$1"; }

# Walk today + last 6 days, newest first. First daily with detectable
# activity wins. Stale data is fine — caller sees idle timer + minutes.
DAILY_DIR=""
for back in 0 1 2 3 4 5 6; do
  d=$(date -v-${back}d +%Y-%m-%d 2>/dev/null || date -d "-${back} days" +%Y-%m-%d)
  candidate="$WORKSPACE_ROOT/dailies/$d"
  if [[ -d "$candidate" ]]; then
    # Has any of the signals we look for? (case-insensitive)
    shopt -s nocaseglob
    has_signal=0
    if [[ -d "$candidate/jira-comments" ]]; then has_signal=1; fi
    (( has_signal == 0 )) && compgen -G "$candidate/ttoad-*" >/dev/null 2>&1 && has_signal=1
    (( has_signal == 0 )) && compgen -G "$candidate/titan-*" >/dev/null 2>&1 && has_signal=1
    (( has_signal == 0 )) && compgen -G "$candidate/tickets/*ttoad-*" >/dev/null 2>&1 && has_signal=1
    (( has_signal == 0 )) && compgen -G "$candidate/tickets/*titan-*" >/dev/null 2>&1 && has_signal=1
    (( has_signal == 0 )) && compgen -G "$candidate/testing-steps-*.html" >/dev/null 2>&1 && has_signal=1
    shopt -u nocaseglob
    if (( has_signal == 1 )); then
      DAILY_DIR="$candidate"
      break
    fi
  fi
done

if [[ -z "$DAILY_DIR" ]]; then
  write_region "" ""
  exit 0
fi

# --- Active ticket extraction (ranked) ---
ticket=""
ticket_mtime=0

# Helper: extract KEY-N (TTOAD or TITAN) from a filename or path basename.
# Sets globals __key and __num on success; clears them otherwise.
extract_key() {
  local s="$1"
  __key=""; __num=""
  # Lowercased pattern, prefer the leftmost match
  local low
  low=$(echo "$s" | tr '[:upper:]' '[:lower:]')
  if [[ "$low" =~ (ttoad|titan)-([0-9]+) ]]; then
    __key=$(echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
    __num="${BASH_REMATCH[2]}"
  fi
}

# 0. daily-folder root: any (ttoad|titan)-N-* file or dir at the top of the
#    daily folder. Catches things like titan-47-pr-draft/, titan-47-ci-audit.md,
#    TTOAD-470-test-plan-DRAFT.md, etc.
shopt -s nullglob nocaseglob
best_m=0
best_f=""
for entry in "$DAILY_DIR"/ttoad-* "$DAILY_DIR"/titan-*; do
  [[ -e "$entry" ]] || continue
  m=$(mtime "$entry")
  if (( m > best_m )); then
    best_m=$m
    best_f=$entry
  fi
done
shopt -u nullglob nocaseglob
if [[ -n "$best_f" ]]; then
  extract_key "$(basename "$best_f")"
  if [[ -n "$__key" && -n "$__num" ]]; then
    ticket="${__key}-${__num}"
    ticket_mtime=$best_m
  fi
fi

# 1. jira-comments
if [[ -z "$ticket" && -d "$DAILY_DIR/jira-comments" ]]; then
  shopt -s nullglob nocaseglob
  best_m=0
  best_f=""
  for f in "$DAILY_DIR/jira-comments"/ttoad-*-*.md "$DAILY_DIR/jira-comments"/titan-*-*.md; do
    m=$(mtime "$f")
    if (( m > best_m )); then
      best_m=$m
      best_f=$f
    fi
  done
  shopt -u nullglob nocaseglob
  if [[ -n "$best_f" ]]; then
    extract_key "$(basename "$best_f")"
    if [[ -n "$__key" && -n "$__num" ]]; then
      ticket="${__key}-${__num}"
      ticket_mtime=$best_m
    fi
  fi
fi

# 2. *-repro/ folders
if [[ -z "$ticket" ]]; then
  shopt -s nullglob nocaseglob
  best_m=0
  best_f=""
  for d in "$DAILY_DIR"/ttoad-*-repro "$DAILY_DIR"/titan-*-repro; do
    [[ -d "$d" ]] || continue
    m=$(mtime "$d")
    if (( m > best_m )); then
      best_m=$m
      best_f=$d
    fi
  done
  shopt -u nullglob nocaseglob
  if [[ -n "$best_f" ]]; then
    extract_key "$(basename "$best_f")"
    if [[ -n "$__key" && -n "$__num" ]]; then
      ticket="${__key}-${__num}"
      ticket_mtime=$best_m
    fi
  fi
fi

# 3. tickets/*ttoad-N*.md or *titan-N*.md
if [[ -z "$ticket" && -d "$DAILY_DIR/tickets" ]]; then
  shopt -s nullglob nocaseglob
  best_m=0
  best_f=""
  for f in "$DAILY_DIR/tickets"/*ttoad-*.md "$DAILY_DIR/tickets"/*titan-*.md; do
    m=$(mtime "$f")
    if (( m > best_m )); then
      best_m=$m
      best_f=$f
    fi
  done
  shopt -u nullglob nocaseglob
  if [[ -n "$best_f" ]]; then
    extract_key "$(basename "$best_f")"
    if [[ -n "$__key" && -n "$__num" ]]; then
      ticket="${__key}-${__num}"
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
    # Try section id first (TTOAD or TITAN), then bare key fallback
    match=$(grep -oE 'ticket-(TTOAD|TITAN)-[0-9]+' "$ts_file" 2>/dev/null | head -1)
    if [[ -z "$match" ]]; then
      match=$(grep -oE '(TTOAD|TITAN)-[0-9]+' "$ts_file" 2>/dev/null | head -1)
    fi
    if [[ -n "$match" ]]; then
      extract_key "$match"
      if [[ -n "$__key" && -n "$__num" ]]; then
        ticket="${__key}-${__num}"
        ticket_mtime=$best_m
      fi
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

# (removed: "starting" rule keyed off daily-$today.html — the file persists
#  all day, so it falsely fired ☕ even after hours of real work. Falling back
#  to "idle … Nm" is more honest when no fresh writing/testing/parsing signal.)

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
_TKT_CLR=$'\033[0m'
_TKT_DIM=$'\033[90m'
if [[ "$step" == "idle" ]]; then
  if [[ -z "$ticket" ]]; then
    write_region "" ""
  else
    idle_min=$(( (now_ts - ticket_mtime) / 60 ))
    write_region "${_TKT_CLR}${ticket}${_TKT_DIM} … idle ${idle_min}m${_TKT_CLR}" "dim"
  fi
else
  if [[ -n "$progress" ]]; then
    write_region "${ticket} ${icon}${_TKT_CLR}${progress}" "magenta"
  else
    write_region "${ticket} ${icon}" "magenta"
  fi
fi
