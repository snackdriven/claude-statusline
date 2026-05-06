#!/usr/bin/env bash
# op_core.sh — bridge: operator-core-mini → multiple statusline regions
#
# Calls op-co-mi's statusline renderer once per cycle and fans the
# already-filtered token payload out into independent regions, each with
# its own row, priority, color, and TTL. Filtering authority stays in
# op-co-mi (consent gate, surfaces allowlist, never_surface_in, freshness)
# per ADR 0003 + 0004; this producer is a dumb projector.
#
# Region layout:
#   op_carry    row 0, prio 70  — top current Backpack item summary
#                                 (loses to ticket.sh's prio 80 in the same
#                                 row when the row is width-tight, which is
#                                 what we want: live workflow > queue summary)
#   op_meeting  row 1, prio 50  — today's q2/sync/meeting summary
#                                 (parallel to meeting.sh; if both fire,
#                                 higher priority wins per row sort)
#   op_verify   row 1, prio 65  — "<N> stale" freshness nudge
#   op_consent  row 2, prio 30  — short consent-gate banner (never names
#                                 suppressed items per ADR 0004)
#
# Inputs (in order of preference):
#   1. $OPERATOR_ROOT (default ~/.operator-core) — if it has doctrine/,
#      shell out to:
#        python3 $OP_CORE_REPO/renderers/statusline.py "$OPERATOR_ROOT" --json
#      $OP_CORE_REPO defaults to $HOME/code/operator-core-mini.
#   2. Fallback to qa-brain's legacy backpack at http://localhost:3737/api/backpack:
#      pick the most-recent date-suffixed entry as op_carry, leave the
#      other regions empty. This keeps the bar useful during the migration
#      from the flat backpack.json to op-co-mi's per-file substrate.
#
# Failure modes are silent — if neither source resolves we write empty
# regions so the renderer simply skips the slot rather than dimming the
# whole line.

set -u

BUDDY_DIR="$HOME/.claude/buddy"
REGIONS="$BUDDY_DIR/regions"
NOW=$(date +%s)

OPERATOR_ROOT="${OPERATOR_ROOT:-$HOME/.operator-core}"
OP_CORE_REPO="${OP_CORE_REPO:-$HOME/Desktop/projects/operator-core-mini}"
QA_BRAIN_URL="${QA_BRAIN_URL:-http://localhost:3737}"
CACHE_WINDOW="${OP_CORE_CACHE_SECONDS:-30}"

mkdir -p "$REGIONS"

# ── Self-cache: bail if all four op_*.json regions are < CACHE_WINDOW old ──
# Using updated_at from the JSON (not file mtime) so the cache key matches
# what the renderer's freshness check uses.
cache_fresh=true
for r in op_carry op_meeting op_verify op_consent; do
  f="$REGIONS/${r}.json"
  if [[ ! -f "$f" ]]; then
    cache_fresh=false; break
  fi
  prev=$(jq -r '.updated_at // 0' "$f" 2>/dev/null || echo 0)
  if (( NOW - prev >= CACHE_WINDOW )); then
    cache_fresh=false; break
  fi
done
$cache_fresh && exit 0

# ── Region writer ──
# Args: id row priority color text
write_region() {
  local id="$1" row="$2" priority="$3" color="$4" text="$5"
  jq -n \
    --arg id "$id" \
    --argjson row "$row" \
    --argjson priority "$priority" \
    --arg color "$color" \
    --arg text "$text" \
    --argjson now "$NOW" \
    '{
       id: $id,
       text: $text,
       color: $color,
       row: $row,
       priority: $priority,
       ttl_sec: 60,
       updated_at: $now
     }' \
    > "$REGIONS/${id}.json"
}

write_empty_all() {
  write_region op_carry   0 70 magenta ""
  write_region op_meeting 1 50 yellow  ""
  write_region op_verify  1 65 dim     ""
  write_region op_consent 2 30 dim     ""
}

# ── Path 1: op-co-mi if doctrine/ exists ──
if [[ -d "$OPERATOR_ROOT/doctrine" ]] \
   && [[ -f "$OP_CORE_REPO/renderers/statusline.py" ]] \
   && command -v python3 >/dev/null 2>&1; then

  payload=$(python3 "$OP_CORE_REPO/renderers/statusline.py" \
              "$OPERATOR_ROOT" --json 2>/dev/null) || payload=""

  if [[ -n "$payload" ]] && jq -e . <<<"$payload" >/dev/null 2>&1; then
    carry=$(jq -r '.carry        // ""' <<<"$payload")
    meet=$( jq -r '.today_event  // ""' <<<"$payload")
    vcount=$(jq -r '.verify_count // 0'  <<<"$payload")
    gate=$(  jq -r '.gate_short   // ""' <<<"$payload")

    write_region op_carry   0 70 magenta "$carry"
    write_region op_meeting 1 50 yellow  "$meet"

    if (( vcount > 0 )); then
      write_region op_verify 1 65 yellow "${vcount} stale"
    else
      write_region op_verify 1 65 dim ""
    fi

    write_region op_consent 2 30 dim "$gate"
    exit 0
  fi
  # Fall through to fallback if the Python call failed mid-way.
fi

# ── Path 2: qa-brain legacy backpack fallback ──
# Surface the most-recent date-suffixed entry as op_carry only.
# Other regions stay empty (no consent gate, no verify policy in the legacy
# flat backpack — those concepts only exist in op-co-mi).
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  raw=$(curl -fsS --max-time 1 "${QA_BRAIN_URL}/api/backpack" 2>/dev/null) || raw=""
  if [[ -n "$raw" ]] && jq -e . <<<"$raw" >/dev/null 2>&1; then
    # The legacy shape is {key: value, "_config:ttl": "<json>", ...}.
    # Pick the entry whose key has the most-recent YYYY-MM-DD suffix.
    # If no entries match, leave carry empty.
    fallback=$(jq -r '
      to_entries
      | map(select(.key | test("-\\d{4}-\\d{2}-\\d{2}$")))
      | map({
          key: .key,
          # Extract the trailing date for sort.
          date: (.key | capture("-(?<d>\\d{4}-\\d{2}-\\d{2})$") | .d),
          # Use the first non-empty line of value as the displayed text.
          text: (.value | split("\n") | map(select(length > 0)) | (.[0] // ""))
        })
      | sort_by(.date)
      | reverse
      | (.[0].text // "")
    ' <<<"$raw")

    # Trim to the same 60-char budget op-co-mi uses for statusline.
    if [[ -n "$fallback" ]]; then
      if (( ${#fallback} > 60 )); then
        fallback="${fallback:0:59}…"
      fi
    fi

    write_region op_carry   0 70 default "$fallback"
    write_region op_meeting 1 50 yellow  ""
    write_region op_verify  1 65 dim     ""
    write_region op_consent 2 30 dim     ""
    exit 0
  fi
fi

# ── No source resolved — write empty regions silently ──
write_empty_all
exit 0
