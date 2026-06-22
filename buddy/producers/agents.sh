#!/usr/bin/env bash
# agents region producer — live subagent activity for THIS session
#
# Reads per-agent status files stamped by hooks/agent-status-stamp.sh:
#   ~/.claude/cache/agent-status/<session_id>/<agent_id>.json
# Shows agents stamped within the last 120s: "↳ Explore:Grep auth.ts | qa-video:Bash"
# Region contract: {id, text, color, priority, row, ttl_sec, updated_at}

set -u

REGION_FILE="${BUDDY_REGION_DIR:-$HOME/.claude/buddy/regions}/agents.json"
STATUS_ROOT="$HOME/.claude/cache/agent-status"
FRESH_SEC=120   # agent considered live if stamped within this window
MAX_SHOWN=2     # named agents before collapsing to +N

NOW=$(date +%s)
mkdir -p "$(dirname "$REGION_FILE")"

STDIN_JSON=$(cat 2>/dev/null || echo '{}')
session_id=$(echo "$STDIN_JSON" | jq -r '.session_id // empty' 2>/dev/null)

emit_empty() {
  jq -n --argjson now "$NOW" \
    '{id: "agents", text: "", color: "cyan", priority: 78, row: 0, ttl_sec: 10, updated_at: $now}' \
    > "$REGION_FILE" 2>/dev/null
  exit 0
}

[[ -z "$session_id" ]] && emit_empty
dir="$STATUS_ROOT/$session_id"
[[ -d "$dir" ]] || emit_empty

shopt -s nullglob
files=("$dir"/*.json)
shopt -u nullglob
(( ${#files[@]} == 0 )) && emit_empty

# Collect fresh agents: "type:tool detail" per line, newest first
entries=$(jq -rs --argjson now "$NOW" --argjson fresh "$FRESH_SEC" '
  [ .[]
    | select(type == "object")
    | select(($now - (.updated_at // 0)) <= $fresh)
  ]
  | sort_by(-(.updated_at // 0))
  | .[]
  | ((.agent_type // "agent") | if . == "-" then "agent" else . end) + ": "
    + ((.tool // "?") | split("__") | last)
    + (if (.detail // "") != "" then " " + (.detail | .[0:28]) else "" end)
' "${files[@]}" 2>/dev/null)

[[ -z "$entries" ]] && emit_empty

total=$(echo "$entries" | wc -l | tr -d '[:space:]')
shown=$(echo "$entries" | head -n "$MAX_SHOWN" | paste -sd '|' - | sed 's/|/   │   /g')
extra=$(( total - MAX_SHOWN ))
text="↳ $shown"
(( extra > 0 )) && text="$text +$extra"

jq -n --arg text "$text" --argjson now "$NOW" \
  '{id: "agents", text: $text, color: "cyan", priority: 78, row: 0, ttl_sec: 10, updated_at: $now}' \
  > "$REGION_FILE" 2>/dev/null

exit 0
