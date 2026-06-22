#!/usr/bin/env bash
# sessions region producer — the OTHER live Claude sessions (a presence ROSTER, not
# just an activity feed). 2026-06-15: switched the source of "who's a worker" from
# session-status freshness to real liveness, so idle-but-alive workers stop vanishing
# after 300s. The roster comes from `sync-name-assign.py --live-roster` (daemon roster
# ∪ presence files with a live claude pid — the pid-reuse-hardened liveness — ∩ today's
# named ledger). Each live session shows its sync-name; ones that stamped a tool within
# FRESH_SEC also show ": <tool> <detail>" (active), the rest show name-only (idle).
# Excludes the rendering session. Region contract: {id,text,color,priority,row,ttl_sec,updated_at}.
set -u

REGION_FILE="${BUDDY_REGION_DIR:-$HOME/.claude/buddy/regions}/sessions.json"
STATUS_ROOT="$HOME/.claude/cache/session-status"
SCRIPT="$HOME/.claude/scripts/sync-name-assign.py"
FRESH_SEC=300   # tool-activity annotation window; idle-but-live sessions still show (name only)
MAX_SHOWN=3     # entries before collapsing to +N

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

# Who's live (sid<TAB>name). The ledger/liveness logic lives in the one engine.
roster=$(python3 "$SCRIPT" --live-roster 2>/dev/null)
[[ -z "$roster" ]] && emit_empty

active=()   # "updated_at <styled line>" — sessions that tool-acted within FRESH_SEC
idle=()     # "<styled line>" — alive but quiet
while IFS=$'\t' read -r sid name; do
  [[ -z "$sid" || -z "$name" ]] && continue
  [[ "$sid" == "$self_id" ]] && continue
  task=""
  f="$STATUS_ROOT/$sid.json"
  if [[ -f "$f" ]]; then
    IFS=$'\t' read -r u tool detail < <(jq -r '[(.updated_at // 0), ((.tool // "?") | split("__") | last), ((.detail // "") | .[0:24])] | @tsv' "$f" 2>/dev/null)
    if [[ -n "${u:-}" ]] && (( NOW - u <= FRESH_SEC )); then
      task="$tool"; [[ -n "$detail" ]] && task="$task $detail"
    fi
  fi
  if [[ -n "$task" ]]; then
    # name = bold pink (WHO); ": task" = italic dim gray (WHAT, ambient)
    line=$'\033[1m\033[38;5;212m'"${name}"$'\033[0m\033[3m\033[90m'": ${task}"$'\033[0m'
    active+=("${u} ${line}")
  else
    line=$'\033[1m\033[38;5;212m'"${name}"$'\033[0m'
    idle+=("${line}")
  fi
done <<< "$roster"

# active first (most-recent activity → oldest), then idle (ledger order)
ordered=()
if (( ${#active[@]} > 0 )); then
  while IFS= read -r l; do ordered+=("$l"); done < <(printf '%s\n' "${active[@]}" | sort -rn | sed 's/^[0-9]* //')
fi
if (( ${#idle[@]} > 0 )); then
  ordered+=("${idle[@]}")
fi
(( ${#ordered[@]} == 0 )) && emit_empty

total=${#ordered[@]}
shown=$(printf '%s\n' "${ordered[@]}" | head -n "$MAX_SHOWN" | paste -sd '|' - | sed 's/|/   │   /g')
extra=$(( total - MAX_SHOWN ))
text="🖥  $shown"
(( extra > 0 )) && text="$text +$extra"

jq -n --arg text "$text" --argjson now "$NOW" \
  '{id: "sessions", text: $text, color: "magenta", priority: 77, row: 0, ttl_sec: 15, updated_at: $now}' \
  > "$REGION_FILE" 2>/dev/null

exit 0
