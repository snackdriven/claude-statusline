#!/usr/bin/env bash
# commits region producer — today's commit count in scratch-pad repo
#
# Counts commits authored today (since local midnight) in ~/Desktop/personal.
# Color tiers: dim 0 · default 1-10 · green 11-24 · yellow 25+.
#
# Region contract: {id, text, color, priority, ttl_sec, updated_at}

set -u

# shellcheck source=../lib/platform.sh
source "$(dirname "$0")/../lib/platform.sh" 2>/dev/null || true

REGION_FILE="$HOME/.claude/buddy/regions/commits.json"
REPO="$HOME/Desktop/personal"

ID="commits"
PRIORITY=40
TTL_SEC=300         # region stays displayable for 5 min
CACHE_WINDOW=60     # don't re-count more than once per 60s (git log is cheap but no need)

NOW=$(date +%s)
mkdir -p "$(dirname "$REGION_FILE")"

# Self-cache: skip if region file mtime is fresher than CACHE_WINDOW
if [[ -f "$REGION_FILE" ]]; then
  prev=$(stat_mtime "$REGION_FILE" 2>/dev/null || stat -f%m "$REGION_FILE" 2>/dev/null || echo 0)
  age=$(( NOW - prev ))
  (( age < CACHE_WINDOW )) && exit 0
fi

# Bail silently if the repo isn't there (clean clone, different machine)
if [[ ! -d "$REPO/.git" ]]; then
  exit 0
fi

# Count today's commits (since midnight local)
count=$(git -C "$REPO" log --since="$(date '+%Y-%m-%d 00:00:00')" --oneline 2>/dev/null | wc -l | tr -d ' ')

# Color tier by volume
if (( count == 0 )); then
  color="dim"
elif (( count >= 25 )); then
  color="yellow"
elif (( count >= 11 )); then
  color="green"
else
  color="default"
fi

text="📝 ${count}"

# Emit region JSON
jq -n \
  --arg id "$ID" \
  --arg text "$text" \
  --arg color "$color" \
  --argjson row 1 \
  --argjson priority "$PRIORITY" \
  --argjson ttl "$TTL_SEC" \
  --argjson updated "$NOW" \
  '{id: $id, text: $text, color: $color, priority: $priority, row: $row, ttl_sec: $ttl, updated_at: $updated}' \
  > "$REGION_FILE"
