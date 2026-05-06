#!/usr/bin/env bash
# spotify.sh — now playing region from Spotify desktop app
# macOS: osascript (queries running app directly, no auth/API key needed)
# Linux: playerctl fallback

set -u

REGION_FILE="$HOME/.claude/buddy/regions/spotify.json"
CACHE_WINDOW=10   # short so track changes appear within ~10s
PRIORITY=45
TTL_SEC=20
ID="spotify"
ROW=2

# Self-cache
if [[ -f "$REGION_FILE" ]]; then
  prev=$(jq -r '.updated_at // 0' "$REGION_FILE" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - prev ))
  (( age < CACHE_WINDOW )) && exit 0
fi

mkdir -p "$(dirname "$REGION_FILE")"
now=$(date +%s)

write_region() {
  jq -n \
    --arg id   "$ID" \
    --arg t    "$1" \
    --arg c    "$2" \
    --argjson p   "$PRIORITY" \
    --argjson row "$ROW" \
    --argjson ttl "$TTL_SEC" \
    --argjson now "$now" \
    '{id: $id, text: $t, color: $c, priority: $p, row: $row, ttl_sec: $ttl, updated_at: $now}' \
    > "$REGION_FILE"
}

track=""

# macOS — "if running" guard prevents launching Spotify when it's closed
if command -v osascript >/dev/null 2>&1; then
  track=$(osascript -e \
    'if application "Spotify" is running then tell application "Spotify" to if player state is playing then return (artist of current track) & " – " & (name of current track)' \
    2>/dev/null || true)
fi

# Linux fallback — playerctl
if [[ -z "$track" ]] && command -v playerctl >/dev/null 2>&1; then
  if [[ "$(playerctl -p spotify status 2>/dev/null)" == "Playing" ]]; then
    artist=$(playerctl -p spotify metadata artist 2>/dev/null || true)
    title=$(playerctl -p spotify metadata title 2>/dev/null || true)
    [[ -n "$artist" && -n "$title" ]] && track="${artist} – ${title}"
  fi
fi

if [[ -z "$track" ]]; then
  write_region "" "dim"
  exit 0
fi

# Trim long titles
(( ${#track} > 50 )) && track="${track:0:49}…"

write_region "♪ ${track}" "green"
