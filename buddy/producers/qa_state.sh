#!/usr/bin/env bash
# qa_state.sh — qa-brain ticket state + release context
#
# Reads from the qa-brain local API (default http://localhost:3737):
#   GET /api/tickets/state   — {tickets: {KEY: {state, stateUpdatedAt, ...}}}
#   GET /api/today           — {date, testingStepsPath}
#   GET /api/manifest        — full days/tickets/releases
#
# Cross-references tickets present in today's daily folder against their
# server-recorded QA state, and emits short ambient counts.
#
# Region layout:
#   qa_states   row 0, prio 75  — "<n> in-review · <n> in-progress"
#                                 (only the two states actually kicked
#                                 back to; others stay silent)
#   qa_release  row 1, prio 55  — "CHG-689 in 3d" — soonest in-scope
#                                 release. Emitted only when the env
#                                 toggle QA_SHOW_RELEASE_OPS is set
#                                 truthy (1, true, yes, on); otherwise
#                                 the region is written empty.
#
# Failure modes are silent — if qa-brain isn't running or returns
# garbage, we write empty regions so the rest of the statusline keeps
# rendering normally.

set -u

BUDDY_DIR="$HOME/.claude/buddy"
REGIONS="$BUDDY_DIR/regions"
NOW=$(date +%s)
TODAY=$(date +%Y-%m-%d)

QA_BRAIN_URL="${QA_BRAIN_URL:-http://localhost:3737}"
CACHE_WINDOW="${QA_STATE_CACHE_SECONDS:-15}"
SHOW_RELEASE_OPS="${QA_SHOW_RELEASE_OPS:-0}"

mkdir -p "$REGIONS"

# ── Self-cache ──
cache_fresh=true
for r in qa_states qa_release; do
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
       ttl_sec: 45,
       updated_at: $now
     }' \
    > "$REGIONS/${id}.json"
}

write_empty_all() {
  write_region qa_states  0 75 default ""
  write_region qa_release 1 55 cyan    ""
}

# Bail early if curl/jq missing — fail open, not loud.
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  write_empty_all
  exit 0
fi

# Truthy toggle helper — accept 1/true/yes/on (case-insensitive).
truthy() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *)             return 1 ;;
  esac
}

# ── Fetch ticket state ──
state_json=$(curl -fsS --max-time 1 "${QA_BRAIN_URL}/api/tickets/state" 2>/dev/null) || state_json=""

# ── Fetch today's manifest entry to scope counts to TODAY's tickets ──
# /api/today only carries date + testingStepsPath; for the ticket set we
# need /api/manifest and walk days[date == TODAY].tickets keys.
today_keys=""
manifest_json=$(curl -fsS --max-time 1 "${QA_BRAIN_URL}/api/manifest" 2>/dev/null) || manifest_json=""
if [[ -n "$manifest_json" ]] && jq -e . <<<"$manifest_json" >/dev/null 2>&1; then
  today_keys=$(jq -r --arg d "$TODAY" '
    (.days // [])
    | map(select(.date == $d))
    | (.[0].tickets // {})
    | keys[]?
  ' <<<"$manifest_json" 2>/dev/null)
fi

# ── Compute state counts ──
in_review=0
in_progress=0

if [[ -n "$state_json" ]] && jq -e . <<<"$state_json" >/dev/null 2>&1; then
  # If we have today's keys, scope to them. Otherwise count across the
  # whole tickets.json (still useful, just less narrow).
  if [[ -n "$today_keys" ]]; then
    keys_arr=$(jq -Rsc 'split("\n") | map(select(length > 0))' <<<"$today_keys")
    counts=$(jq -c --argjson keys "$keys_arr" '
      .tickets // {}
      | to_entries
      | map(select(.key as $k | $keys | index($k)))
      | map(.value.state // "")
      | {
          in_review:   (map(select(. == "in-review"))   | length),
          in_progress: (map(select(. == "in-progress")) | length)
        }
    ' <<<"$state_json")
  else
    counts=$(jq -c '
      .tickets // {}
      | to_entries
      | map(.value.state // "")
      | {
          in_review:   (map(select(. == "in-review"))   | length),
          in_progress: (map(select(. == "in-progress")) | length)
        }
    ' <<<"$state_json")
  fi

  in_review=$(  jq -r '.in_review'   <<<"$counts" 2>/dev/null || echo 0)
  in_progress=$(jq -r '.in_progress' <<<"$counts" 2>/dev/null || echo 0)
fi

# ── Compose qa_states ──
_QA_DIM=$'\033[90m'
_QA_CYN=$'\033[36m'
_QA_CLR=$'\033[0m'
parts=()
(( in_review   > 0 )) && parts+=("${_QA_DIM}${in_review} in-review${_QA_CLR}")
(( in_progress > 0 )) && parts+=("${_QA_CYN}${in_progress} in-progress${_QA_CLR}")

if (( ${#parts[@]} == 0 )); then
  write_region qa_states 0 75 default ""
else
  text="${parts[0]}"
  for ((i=1; i<${#parts[@]}; i++)); do
    text+=" · ${parts[i]}"
  done
  write_region qa_states 0 75 default "$text"
fi

# ── qa_release (toggleable) ──
if truthy "$SHOW_RELEASE_OPS" && [[ -n "$manifest_json" ]] \
   && jq -e . <<<"$manifest_json" >/dev/null 2>&1; then
  # Pick the soonest in-scope release with date >= today.
  soonest=$(jq -r --arg d "$TODAY" '
    (.releases // [])
    | map(select(.inScope == true and (.date // "") >= $d))
    | sort_by(.date)
    | (.[0] // empty)
    | if . == null or . == "" then "" else "\(.chgKey // .title)|\(.date)" end
  ' <<<"$manifest_json")

  if [[ -n "$soonest" && "$soonest" != "|" ]]; then
    key="${soonest%%|*}"
    date_str="${soonest##*|}"
    # Days-until math, GNU vs BSD compatible.
    if target_epoch=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null); then
      :
    else
      target_epoch=$(date -d "$date_str" +%s 2>/dev/null || echo 0)
    fi
    if (( target_epoch > 0 )); then
      days=$(( (target_epoch - NOW) / 86400 ))
      if (( days <= 0 )); then
        text="${key} today"
        color="yellow"
      elif (( days == 1 )); then
        text="${key} tmrw"
        color="yellow"
      else
        text="${key} in ${days}d"
        color="cyan"
      fi
      write_region qa_release 1 55 "$color" "$text"
    else
      write_region qa_release 1 55 cyan ""
    fi
  else
    write_region qa_release 1 55 cyan ""
  fi
else
  write_region qa_release 1 55 cyan ""
fi

exit 0
