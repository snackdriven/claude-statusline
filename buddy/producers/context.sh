#!/usr/bin/env bash
# context.sh — real context-window usage from the live transcript.
#
# Reads stdin (Claude Code statusline JSON):
#   .transcript_path  — path to current session JSONL (preferred)
#   .workspace.current_dir + .session_id — fallback to derive path
#   .model.id         — used to pick limit (200k vs 1m)
#
# Sums the LAST assistant turn's usage:
#   input + cache_creation + cache_read + output
# That's the size of the conversation as it stood when the model last replied —
# i.e. roughly what the next request will send.
#
# Region: row 0, hides itself when transcript missing or under threshold (dim).

set -u

REGION_FILE="$HOME/.claude/buddy/regions/context.json"
CACHE_WINDOW=5
PRIORITY=80   # row 0, after buddy (priority 90)
TTL_SEC=15
ID="context"

# Self-cache
if [[ -f "$REGION_FILE" ]]; then
  prev=$(stat -f%m "$REGION_FILE" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - prev ))
  (( age < CACHE_WINDOW )) && exit 0
fi

mkdir -p "$(dirname "$REGION_FILE")"
now=$(date +%s)

write_empty() {
  jq -n --argjson now "$now" --argjson p "$PRIORITY" --argjson ttl "$TTL_SEC" \
    '{id: "context", text: "", color: "dim", priority: $p, row: 0, ttl_sec: $ttl, updated_at: $now}' \
    > "$REGION_FILE"
  exit 0
}

# Read stdin if available
stdin_json=""
if [[ ! -t 0 ]]; then
  stdin_json=$(cat 2>/dev/null || true)
fi

# Resolve transcript path
transcript=""
model_id=""
if [[ -n "$stdin_json" ]]; then
  transcript=$(jq -r '.transcript_path // empty' <<<"$stdin_json" 2>/dev/null)
  model_id=$(jq -r '.model.id // empty' <<<"$stdin_json" 2>/dev/null)

  # Fallback: derive from cwd + session_id
  if [[ -z "$transcript" ]]; then
    cwd=$(jq -r '.workspace.current_dir // empty' <<<"$stdin_json" 2>/dev/null)
    sid=$(jq -r '.session_id // empty' <<<"$stdin_json" 2>/dev/null)
    if [[ -n "$cwd" && -n "$sid" ]]; then
      slug=$(echo "$cwd" | sed 's|/|-|g')
      transcript="$HOME/.claude/projects/${slug}/${sid}.jsonl"
    fi
  fi
fi

# Last-resort fallback: most recent JSONL in current project dir
if [[ -z "$transcript" || ! -f "$transcript" ]]; then
  cwd_fallback="${PWD}"
  if [[ -n "$stdin_json" ]]; then
    cwd_fallback=$(jq -r '.workspace.current_dir // empty' <<<"$stdin_json" 2>/dev/null)
    [[ -z "$cwd_fallback" ]] && cwd_fallback="$PWD"
  fi
  slug=$(echo "$cwd_fallback" | sed 's|/|-|g')
  proj_dir="$HOME/.claude/projects/${slug}"
  if [[ -d "$proj_dir" ]]; then
    transcript=$(ls -t "$proj_dir"/*.jsonl 2>/dev/null | head -1)
  fi
fi

[[ -z "$transcript" || ! -f "$transcript" ]] && write_empty

# Pick limit by model — 1m variant detection
limit=200000
if [[ "$model_id" == *"1m"* || "$model_id" == *"[1m]"* ]]; then
  limit=1000000
fi

# Tail and find last assistant message with usage. Sum the four token fields.
# Walking tail backwards keeps this O(small) even on big sessions.
usage_line=$(tail -r "$transcript" 2>/dev/null | head -200 | \
  jq -rc 'select(.type=="assistant") | .message.usage // empty | select(. != null)' 2>/dev/null | head -1)

if [[ -z "$usage_line" ]]; then
  write_empty
fi

used=$(jq -r '
  ((.input_tokens // 0) +
   (.cache_creation_input_tokens // 0) +
   (.cache_read_input_tokens // 0) +
   (.output_tokens // 0))
' <<<"$usage_line" 2>/dev/null)

[[ -z "$used" || "$used" == "null" ]] && write_empty

# Compute %
pct=$(( used * 100 / limit ))
used_k=$(( used / 1000 ))
limit_k=$(( limit / 1000 ))

# Threshold → emoji + color
if (( pct >= 90 )); then
  emoji="🔴"; color="red"
elif (( pct >= 85 )); then
  emoji="🔶"; color="red"
elif (( pct >= 75 )); then
  emoji="⚠️"; color="yellow"
elif (( pct >= 50 )); then
  emoji=""; color="default"
else
  emoji=""; color="dim"
fi

if [[ -n "$emoji" ]]; then
  text="${emoji} ${used_k}k/${limit_k}k (${pct}%)"
else
  text="ctx ${pct}%"
fi

jq -n \
  --arg t "$text" --arg c "$color" \
  --argjson p "$PRIORITY" --argjson ttl "$TTL_SEC" --argjson now "$now" \
  '{id: "context", text: $t, color: $c, priority: $p, row: 0, ttl_sec: $ttl, updated_at: $now}' \
  > "$REGION_FILE"
