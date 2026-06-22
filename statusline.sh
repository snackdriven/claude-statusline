#!/usr/bin/env bash
# statusline.sh — statusline entry point (settings.json points here).
#
# Composes the bar from TWO independent render passes over disjoint producer
# sets (see buddy/render.sh "Renderer set"):
#   • info  — work / context / live-activity regions  (render.sh info)
#   • buddy — the companion creature + conscience + ambient  (render.sh buddy)
# Each is gated by its own flag so either side can be turned off alone:
#   STATUSLINE_INFO=0   → hide the info bar
#   STATUSLINE_BUDDY=0  → hide the companion
# Then prepends this terminal's daily "sync-name" (EDI / Miranda Lawson / … —
# the same per-day pool the cross-terminal daily-sync doc uses) to the first
# line. Name lookup is best-effort: on any miss the line is just the body.
INPUT=$(cat)

NAME=""
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$SID" ]; then
  LEDGER="$HOME/.claude/cache/sync-names/$(date +%F).tsv"
  NAME=$(grep -m1 "^$SID"$'\t' "$LEDGER" 2>/dev/null | cut -f2)
  [ -z "$NAME" ] && NAME=$(python3 "$HOME/.claude/scripts/sync-name-assign.py" "$SID" 2>/dev/null)
fi

# Shrink the render width budget by the name's footprint so line 1 doesn't overflow.
if [ -n "$NAME" ]; then
  W=$(printf '%s' "$INPUT" | jq -r '.terminal.width // empty' 2>/dev/null)
  [[ "$W" =~ ^[0-9]+$ ]] || W=$(tput cols 2>/dev/null || echo 120)
  [[ "$W" =~ ^[0-9]+$ ]] || W=120
  budget=$(( W - ${#NAME} - 3 ))
  (( budget >= 40 )) && export CLAUDE_STATUSLINE_WIDTH="$budget"
fi

# Two independent passes; each may be toggled off or come back empty.
INFO_ON="${STATUSLINE_INFO:-1}"
BUDDY_ON="${STATUSLINE_BUDDY:-1}"
INFO=""
BUDDY=""
[ "$INFO_ON"  != "0" ] && INFO=$(printf '%s' "$INPUT" | bash "$HOME/.claude/buddy/render.sh" info)
[ "$BUDDY_ON" != "0" ] && BUDDY=$(printf '%s' "$INPUT" | bash "$HOME/.claude/buddy/render.sh" buddy)

# Stack info line(s) on top, buddy line(s) below.
BODY="$INFO"
if [ -n "$BUDDY" ]; then
  if [ -n "$BODY" ]; then BODY="$BODY"$'\n'"$BUDDY"; else BODY="$BUDDY"; fi
fi

# Link the sync-name to today's cross-terminal daily-sync doc (Obsidian).
NAME_HREF=""
if [ -n "$NAME" ]; then
  _sync="$HOME/Desktop/personal/dailies/$(date +%Y-%m)/$(date +%Y-%m-%d)/daily-sync.md"
  NAME_HREF="obsidian://open?path=$(jq -rn --arg p "$_sync" '$p|@uri')"
fi

if [ -n "$NAME" ] && [ -n "$BODY" ]; then
  printf '\033]8;;%s\a\033[1;38;5;141m%s\033[0m\033]8;;\a · %s' "$NAME_HREF" "$NAME" "$BODY"
elif [ -n "$NAME" ]; then
  printf '\033]8;;%s\a\033[1;38;5;141m%s\033[0m\033]8;;\a' "$NAME_HREF" "$NAME"
else
  printf '%s' "$BODY"
fi
