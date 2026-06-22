#!/usr/bin/env bash
# pr.sh — region producer for the active PR (from Claude Code stdin .pr).
# Emits a clickable "PR #N" chip → the PR on GitHub, only when stdin carries a
# pr object. No PR on stdin → removes any stale chip and exits (no dead link).
# Region contract: {id, text, short, color, href, priority, row, ttl_sec, updated_at}

set -u

REGION_FILE="${BUDDY_REGION_DIR:-$HOME/.claude/buddy/regions}/pr.json"
ID="pr"; ROW=0; PRIORITY=58; TTL_SEC=120
NOW=$(date +%s)
mkdir -p "$(dirname "$REGION_FILE")"

json="{}"
if [[ ! -t 0 ]]; then json=$(cat 2>/dev/null || echo '{}'); fi

num=$(jq -r '.pr.number // empty' <<<"$json" 2>/dev/null || true)
url=$(jq -r '.pr.url // empty' <<<"$json" 2>/dev/null || true)

if [[ -z "$num" || -z "$url" ]]; then
  rm -f "$REGION_FILE" 2>/dev/null
  exit 0
fi

jq -n \
  --arg id "$ID" --arg t "PR #$num" --arg s "#$num" --arg h "$url" \
  --argjson p "$PRIORITY" --argjson r "$ROW" --argjson ttl "$TTL_SEC" --argjson now "$NOW" \
  '{id:$id, text:$t, short:$s, color:"cyan", href:$h, priority:$p, row:$r, ttl_sec:$ttl, updated_at:$now}' \
  > "$REGION_FILE"
