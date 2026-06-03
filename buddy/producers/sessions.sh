#!/usr/bin/env bash
# sessions region producer — live activity of OTHER concurrent Claude sessions
#
# Reads per-session status files stamped by hooks/agent-status-stamp.sh:
#   ~/.claude/cache/session-status/<session_id>.json
# Excludes the rendering session itself. Shows sessions stamped within the
# last 300s: "🖥 platform:Bash npm test | personal:Read foo.ts +1"
# Region contract: {id, text, color, priority, row, ttl_sec, updated_at}

set -u

REGION_FILE="$HOME/.claude/buddy/regions/sessions.json"
STATUS_ROOT="$HOME/.claude/cache/session-status"
FRESH_SEC=300   # session considered live if stamped within this window
MAX_SHOWN=2     # named sessions before collapsing to +N

NOW=$(date +%s)
mkdir -p "$(dirname "$REGION_FILE")"

STDIN_JSON=$(cat 2>/dev/null || echo '{}')
self_id=$(echo "$STDIN_JSON" | jq -r '.session_id // empty' 2>/dev/null)

emit_empty() {
  jq -n --argjson now "$NOW" \
    '{id: "sessions", text: "", color: "magenta", priority: 77, row: 0, ttl_sec: 15, updated_at: $now}' \
    > "$REGION_FILE" 2>/dev/null
  exit 0
}

[[ -d "$STATUS_ROOT" ]] || emit_empty

shopt -s nullglob
files=()
for f in "$STATUS_ROOT"/*.json; do
  [[ "$(basename "$f" .json)" == "$self_id" ]] && continue
  files+=("$f")
done
shopt -u nullglob
(( ${#files[@]} == 0 )) && emit_empty

# Collect fresh sessions: "cwd_base:tool detail" per line, newest first
entries=$(jq -rs --argjson now "$NOW" --argjson fresh "$FRESH_SEC" '
  [ .[]
    | select(type == "object")
    | select(($now - (.updated_at // 0)) <= $fresh)
  ]
  | sort_by(-(.updated_at // 0))
  | .[]
  | ((.cwd_base // "?") | if . == "-" then "?" else . end) + ": "
    + ((.tool // "?") | split("__") | last)
    + (if (.detail // "") != "" then " " + (.detail | .[0:28]) else "" end)
' "${files[@]}" 2>/dev/null)

[[ -z "$entries" ]] && emit_empty

total=$(echo "$entries" | wc -l | tr -d '[:space:]')
shown=$(echo "$entries" | head -n "$MAX_SHOWN" | paste -sd '|' - | sed 's/|/   │   /g')
extra=$(( total - MAX_SHOWN ))
text="🖥  $shown"
(( extra > 0 )) && text="$text +$extra"

jq -n --arg text "$text" --argjson now "$NOW" \
  '{id: "sessions", text: $text, color: "magenta", priority: 77, row: 0, ttl_sec: 15, updated_at: $now}' \
  > "$REGION_FILE" 2>/dev/null

exit 0
