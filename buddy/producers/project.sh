#!/usr/bin/env bash
# project region producer — basename + branch + dirty count
# Region contract: {id, text, color, priority, ttl_sec, updated_at}

set -u

REGION_FILE="$HOME/.claude/buddy/regions/project.json"
CACHE_WINDOW=10
PRIORITY=60
TTL_SEC=30
COLOR="cyan"
ID="project"

# Self-cache: skip if region file mtime is fresher than CACHE_WINDOW
# Use stat (no jq fork) — wall-clock dominated by bash startup anyway
if [[ -f "$REGION_FILE" ]]; then
  prev=$(stat -f%m "$REGION_FILE" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - prev ))
  (( age < CACHE_WINDOW )) && exit 0
fi

# Resolve cwd: stdin JSON .workspace.current_dir wins, fallback to $PWD
cwd=""
if [[ ! -t 0 ]]; then
  stdin_json=$(cat 2>/dev/null || true)
  if [[ -n "$stdin_json" ]]; then
    cwd=$(jq -r '.workspace.current_dir // empty' <<<"$stdin_json" 2>/dev/null || true)
  fi
fi
[[ -z "$cwd" ]] && cwd="$PWD"

basename=$(basename "$cwd")

# Git probe — silent if not a repo
branch=""
dirty_count=0
if branch=$(cd "$cwd" 2>/dev/null && git symbolic-ref --short HEAD 2>/dev/null); then
  dirty_count=$(cd "$cwd" 2>/dev/null && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
fi

if [[ -n "$branch" ]]; then
  if (( dirty_count > 0 )); then
    text="${basename} on ${branch}+${dirty_count}"
  else
    text="${basename} on ${branch}"
  fi
else
  text="${basename}"
fi

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
