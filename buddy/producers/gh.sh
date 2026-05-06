#!/usr/bin/env bash
# gh region producer — current active gh CLI account
# Region contract: {id, text, color, priority, row, ttl_sec, updated_at}
#
# Color signals which account is active so a personal-vs-work mix-up is
# loud at a glance:
#   kayla-at-chorus → green   (work)
#   snackdriven     → magenta (personal)
#   anything else   → yellow  (unknown / not authed / gh not installed)

set -u

# shellcheck source=../lib/platform.sh
source "$(dirname "$0")/../lib/platform.sh" 2>/dev/null || true

REGION_FILE="$HOME/.claude/buddy/regions/gh.json"
CACHE_WINDOW=30
PRIORITY=55
TTL_SEC=60
ID="gh"
ROW=1

# Self-cache
if [[ -f "$REGION_FILE" ]]; then
  prev=$(stat_mtime "$REGION_FILE")
  age=$(( $(date +%s) - prev ))
  (( age < CACHE_WINDOW )) && exit 0
fi

# Bail if gh isn't on PATH — emit nothing rather than a confusing message
command -v gh >/dev/null 2>&1 || exit 0

# Parse `gh auth status`. Active account line:
#   ✓ Logged in to github.com account <name> (keyring)
#   - Active account: true
account=""
if status=$(gh auth status 2>/dev/null); then
  account=$(awk '
    /Logged in to github.com account/ {
      match($0, /account [^ ]+/)
      cand = substr($0, RSTART+8, RLENGTH-8)
    }
    /Active account: true/ { print cand; exit }
  ' <<<"$status")
fi

if [[ -z "$account" ]]; then
  text="gh:?"
  color="yellow"
else
  text="gh:${account}"
  case "$account" in
    kayla-at-chorus) color="green"   ;;
    snackdriven)     color="magenta" ;;
    *)               color="yellow"  ;;
  esac
fi

now=$(date +%s)
jq -n \
  --arg id "$ID" \
  --arg t "$text" \
  --arg c "$color" \
  --argjson p "$PRIORITY" \
  --argjson r "$ROW" \
  --argjson ttl "$TTL_SEC" \
  --argjson now "$now" \
  '{id: $id, text: $t, color: $c, priority: $p, row: $r, ttl_sec: $ttl, updated_at: $now}' \
  > "$REGION_FILE"
