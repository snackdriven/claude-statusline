#!/usr/bin/env bash
# conscience.sh — match recent tool activity against feedback-rule index, surface one hint.
#
# Inputs:
#   ~/.claude/buddy/events.log               (one line per event: <ts> <tool> <cmd> <cwd> <file>)
#   ~/.claude/buddy/conscience-index.json    (18 rules)
#   ~/.claude/buddy/.cooldowns.json          ({rule_file: last_fired_unix_ts})
#   ~/.claude/buddy/session-state.json       (closer_phrases, pass_fail_log, recent_searches)
#   ~/.claude/buddy/regions/ticket.json      (active ticket text, for proactive-tool-use rule)
#   stdin                                    (Claude Code workspace JSON; we read .workspace.current_dir)
#
# Output: writes ~/.claude/buddy/regions/conscience.json (always — empty text on no-match)

set -u

BUDDY_DIR="$HOME/.claude/buddy"
REGION_FILE="$BUDDY_DIR/regions/conscience.json"
EVENTS_LOG="$BUDDY_DIR/events.log"
INDEX="$BUDDY_DIR/conscience-index.json"
COOLDOWNS="$BUDDY_DIR/.cooldowns.json"
SESSION_STATE="$BUDDY_DIR/session-state.json"
TICKET_REGION="$BUDDY_DIR/regions/ticket.json"

NOW=$(date +%s)

# ── Self-cache: skip if region file is fresh (<10s old) ──
if [[ -f "$REGION_FILE" ]]; then
  prev=$(jq -r '.updated_at // 0' "$REGION_FILE" 2>/dev/null)
  age=$(( NOW - prev ))
  (( age < 10 )) && exit 0
fi

mkdir -p "$BUDDY_DIR/regions"

# ── Helpers ──

write_region() {
  local text="$1" color="$2"
  jq -n \
    --arg id "conscience" \
    --arg text "$text" \
    --arg color "$color" \
    --argjson priority 40 \
    --argjson ttl_sec 60 \
    --argjson updated_at "$NOW" \
    '{id:$id, text:$text, color:$color, priority:$priority, row:2, ttl_sec:$ttl_sec, updated_at:$updated_at}' \
    > "$REGION_FILE"
}

write_empty_region() {
  write_region "" "default"
}

# ── Read stdin (best-effort; producers are forked with stdin piped) ──
STDIN_JSON=$(cat 2>/dev/null || echo '{}')
CWD=$(jq -r '.workspace.current_dir // .cwd // ""' <<<"$STDIN_JSON" 2>/dev/null)

# ── Initialize cooldowns + session-state if missing ──
[[ -f "$COOLDOWNS" ]] || echo '{}' > "$COOLDOWNS"
[[ -f "$SESSION_STATE" ]] || echo '{"closer_phrases":[],"pass_fail_log":{},"recent_searches":[]}' > "$SESSION_STATE"

# ── Bail early if index missing ──
if [[ ! -f "$INDEX" ]] || ! jq -e . "$INDEX" >/dev/null 2>&1; then
  write_empty_region
  exit 0
fi

# ── Read events from last 5 min ──
EVENTS=""
if [[ -f "$EVENTS_LOG" ]]; then
  cutoff=$(( NOW - 300 ))
  EVENTS=$(tail -n 200 "$EVENTS_LOG" 2>/dev/null \
    | awk -v c="$cutoff" '$1 ~ /^[0-9]+$/ && $1 >= c')
fi

# Pre-compute event field strings (newline-separated) for fast grep
# Format per line: <ts> <tool> <cmd> <cwd> <file>
EVENT_TOOLS=$(awk '{print $2}' <<<"$EVENTS")
# cmd / cwd / file may contain spaces — use cut -d' ' -f3- and split heuristically.
# Hook writes via printf '%s %s %s %s %s\n' so each is single-token unless quoted.
# We treat field 3 as cmd, field 4 as cwd, field 5 as file — best-effort.
EVENT_CMDS=$(awk '{ $1=""; $2=""; sub(/^  /,""); print }' <<<"$EVENTS")
EVENT_CWDS=$(awk '{print $4}' <<<"$EVENTS")
EVENT_FILES=$(awk '{print $5}' <<<"$EVENTS")

# ── Session-state matchers ──

normalize_closer() {
  # lowercase, strip trailing emoji/punctuation/whitespace
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[[:space:][:punct:]]+$//' \
    | sed -E 's/[^[:print:][:space:]]+$//'
}

match_closer_phrases_last3() {
  # True if last 3 closer_phrases entries normalize-equal.
  local count
  count=$(jq -r '.closer_phrases | length' "$SESSION_STATE" 2>/dev/null || echo 0)
  (( count < 3 )) && return 1
  local p1 p2 p3
  p1=$(jq -r '.closer_phrases[-1] // ""' "$SESSION_STATE")
  p2=$(jq -r '.closer_phrases[-2] // ""' "$SESSION_STATE")
  p3=$(jq -r '.closer_phrases[-3] // ""' "$SESSION_STATE")
  local n1 n2 n3
  n1=$(normalize_closer "$p1")
  n2=$(normalize_closer "$p2")
  n3=$(normalize_closer "$p3")
  [[ -n "$n1" && "$n1" == "$n2" && "$n2" == "$n3" ]]
}

match_pass_fail_refetched() {
  # True if any ticket key in pass_fail_log appears as subject of a getJiraIssue event.
  local tickets
  tickets=$(jq -r '.pass_fail_log | keys[]' "$SESSION_STATE" 2>/dev/null)
  [[ -z "$tickets" ]] && return 1
  # Look for getJiraIssue events whose cmd/file mentions the ticket
  local jira_lines
  jira_lines=$(grep -E 'getJiraIssue' <<<"$EVENTS" 2>/dev/null)
  [[ -z "$jira_lines" ]] && return 1
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if grep -qE "\\b${t}\\b" <<<"$jira_lines"; then
      return 0
    fi
  done <<<"$tickets"
  return 1
}

match_searches_empty_for_active_ticket() {
  # Active ticket from ticket region text; e.g. "TTOAD-429 …" — extract ticket key.
  local ticket_text active_key
  ticket_text=$(jq -r '.text // ""' "$TICKET_REGION" 2>/dev/null)
  active_key=$(grep -oE '[A-Z]+-[0-9]+' <<<"$ticket_text" | head -1)
  [[ -z "$active_key" ]] && return 1
  # Ticket appears in events as file path?
  if ! grep -qE "\\b${active_key}\\b" <<<"$EVENTS"; then
    return 1
  fi
  # Any search tool call this session for that ticket?
  local has_search
  has_search=$(jq -r --arg k "$active_key" \
    '[.recent_searches[]? | select(.query // "" | test($k))] | length' \
    "$SESSION_STATE" 2>/dev/null)
  [[ "${has_search:-0}" -gt 0 ]] && return 1
  return 0
}

# ── Match a single trigger (kind + pattern) against events ──
match_trigger() {
  local kind="$1" pattern="$2"
  case "$kind" in
    bash_cmd)
      # Match against cmd field, but only on Bash tool events
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local tool cmdline
        tool=$(awk '{print $2}' <<<"$line")
        [[ "$tool" != "Bash" ]] && continue
        cmdline=$(awk '{ $1=""; $2=""; sub(/^  /,""); print }' <<<"$line")
        if grep -qE "$pattern" <<<"$cmdline"; then
          return 0
        fi
      done <<<"$EVENTS"
      return 1
      ;;
    file_path)
      # Match against file field OR cmd field
      grep -qE "$pattern" <<<"$EVENT_FILES" && return 0
      grep -qE "$pattern" <<<"$EVENT_CMDS" && return 0
      return 1
      ;;
    tool_name)
      grep -qE "^($pattern)$" <<<"$EVENT_TOOLS" && return 0
      return 1
      ;;
    cwd_path)
      [[ -n "$CWD" ]] && grep -qE "$pattern" <<<"$CWD" && return 0
      grep -qE "$pattern" <<<"$EVENT_CWDS" && return 0
      return 1
      ;;
    session_state)
      case "$pattern" in
        closer_phrases.last3_match)
          match_closer_phrases_last3 && return 0 ;;
        pass_fail_log.ticket_in_log_and_being_refetched)
          match_pass_fail_refetched && return 0 ;;
        recent_searches.empty_for_active_ticket)
          match_searches_empty_for_active_ticket && return 0 ;;
      esac
      return 1
      ;;
  esac
  return 1
}

# ── Iterate rules, score each, track best ──
best_file=""
best_hint=""
best_color=""
best_score=0
best_cooldown_remaining=999999

cooldowns_json=$(cat "$COOLDOWNS")

while IFS= read -r rule; do
  [[ -z "$rule" ]] && continue
  rule_file=$(jq -r '.file' <<<"$rule")
  cooldown_min=$(jq -r '.cooldown_min // 30' <<<"$rule")
  last=$(jq -r --arg k "$rule_file" '.[$k] // 0' <<<"$cooldowns_json")
  remaining=$(( last + cooldown_min*60 - NOW ))
  (( remaining > 0 )) && continue   # cooldown active

  score=0
  while IFS= read -r trig; do
    [[ -z "$trig" ]] && continue
    kind=$(jq -r '.kind' <<<"$trig")
    pattern=$(jq -r '.pattern' <<<"$trig")
    if match_trigger "$kind" "$pattern"; then
      score=$(( score + 1 ))
    fi
  done < <(jq -c '.triggers[]' <<<"$rule")

  if (( score > best_score )); then
    best_score=$score
    best_file="$rule_file"
    best_hint=$(jq -r '.hint' <<<"$rule")
    best_color=$(jq -r '.color // "dim"' <<<"$rule")
    best_cooldown_remaining=$remaining
  elif (( score == best_score && score > 0 )); then
    # Tiebreaker: shortest cooldown remaining (most "due to fire")
    if (( remaining < best_cooldown_remaining )); then
      best_file="$rule_file"
      best_hint=$(jq -r '.hint' <<<"$rule")
      best_color=$(jq -r '.color // "dim"' <<<"$rule")
      best_cooldown_remaining=$remaining
    fi
  fi
done < <(jq -c '.[]' "$INDEX")

if (( best_score > 0 )) && [[ -n "$best_file" ]]; then
  # Strip ANSI just in case (defensive)
  clean_hint=$(printf '%s' "$best_hint" | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g')
  write_region "$clean_hint" "$best_color"
  # Bump cooldown atomically
  tmp=$(mktemp)
  jq --arg k "$best_file" --argjson ts "$NOW" '.[$k] = $ts' "$COOLDOWNS" > "$tmp" \
    && mv "$tmp" "$COOLDOWNS"
else
  write_empty_region
fi

exit 0
