#!/usr/bin/env bash
# incoming.sh — region producer for the "incoming queue" view.
#
# Reads cached JSON from scripts/incoming.ts --summary. If cache is missing
# or older than REFRESH_INTERVAL, kicks off a background refresh and uses the
# stale value this iteration (the next render gets the fresh number).
#
# Renderer self-cache TTL keeps us off the wire on most renders; the actual
# heavy work (gh + jira) happens at most every REFRESH_INTERVAL seconds and
# always in the background.
#
# Region: {id: "incoming", row: 0, priority: 70, color: varies, text: compact counts}

set -u

# shellcheck source=../lib/platform.sh
source "$(dirname "$0")/../lib/platform.sh" 2>/dev/null || true

REGION_FILE="$HOME/.claude/buddy/regions/incoming.json"
CACHE_FILE="$HOME/.claude/buddy/cache/incoming.json"
SCRIPT_PATH="$HOME/Desktop/personal/scripts/incoming.ts"
SCRIPT_CWD="$HOME/Desktop/personal"

ID="incoming"
ROW=0
PRIORITY=70
TTL_SEC=600          # region stays displayable for 10 min
REFRESH_INTERVAL=300 # bg-refresh the cache every 5 min
RENDER_CACHE_WINDOW=30  # don't even read cache more than once per 30s

NOW=$(date +%s)

mkdir -p "$(dirname "$REGION_FILE")" "$(dirname "$CACHE_FILE")"

# ─ Renderer-side self-cache: if region is fresh, exit fast ───────────────
if [[ -f "$REGION_FILE" ]]; then
  prev=$(jq -r '.updated_at // 0' "$REGION_FILE" 2>/dev/null || echo 0)
  age=$(( NOW - prev ))
  if (( age < RENDER_CACHE_WINDOW )); then
    exit 0
  fi
fi

# ─ Bail if the script isn't present (e.g. clean clone w/o scratch-pad) ───
if [[ ! -f "$SCRIPT_PATH" ]]; then
  exit 0
fi

# ─ Trigger background refresh if cache is stale or missing ───────────────
cache_age=999999
if [[ -f "$CACHE_FILE" ]]; then
  cache_mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  cache_age=$(( NOW - cache_mtime ))
fi

if (( cache_age >= REFRESH_INTERVAL )); then
  # Fire & forget. The shell that produced THIS region tick doesn't wait.
  # Path-load via shell rc fallback isn't reliable in launchd-style contexts,
  # so use the absolute npx from the active node bin if discoverable.
  (
    cd "$SCRIPT_CWD" || exit 0
    # Prefer the nvm-installed node if present; otherwise rely on PATH.
    NODE_BIN=""
    if [[ -d "$HOME/.nvm/versions/node" ]]; then
      NODE_BIN=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -1)
      [[ -n "$NODE_BIN" ]] && export PATH="$HOME/.nvm/versions/node/$NODE_BIN/bin:$PATH"
    fi
    npx tsx scripts/incoming.ts --summary > "$CACHE_FILE.tmp" 2>/dev/null \
      && mv "$CACHE_FILE.tmp" "$CACHE_FILE" \
      || rm -f "$CACHE_FILE.tmp"
  ) >/dev/null 2>&1 &
fi

# ─ Read whatever cache we have (possibly stale) ──────────────────────────
if [[ ! -f "$CACHE_FILE" ]]; then
  # No data yet — emit a placeholder so the user sees that work is pending,
  # but don't claim counts we don't have.
  jq -n --argjson now "$NOW" \
    '{id: "incoming", text: "incoming: …", color: "dim",
      priority: 70, row: 0, ttl_sec: 600, updated_at: $now}' \
    > "$REGION_FILE"
  exit 0
fi

ready=$(jq -r '.ready // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
blocked=$(jq -r '.blocked // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
merged=$(jq -r '.merged // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
unapproved=$(jq -r '.unapproved // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
sonata=$(jq -r '.sonata // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
generated_at=$(jq -r '.generated_at // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
data_age=$(( NOW - generated_at ))

# ─ Build the compact display text ────────────────────────────────────────
# Short text labels — easier to scan than emoji. Drop zero-count buckets.
# Each label colored inline by what it means; separator stays dim.
# Labels:
#   ready    — open PR, approved, mergeStateStatus=CLEAN (act-now)     [red]
#   blocked  — approved but not mergeable                              [yellow]
#   merged   — merged in last 24h, ready to QA                         [green]
#   review   — open PR awaiting review                                 [cyan]
#   sonata   — Sonata ticket in `In Review` status                     [magenta]
RED=$'\033[31m'
YLW=$'\033[33m'
CYN=$'\033[36m'
TEAL=$'\033[38;5;115m'
SKY=$'\033[38;5;117m'
MAUVE=$'\033[38;5;141m'
DIM=$'\033[90m'
RST=$'\033[0m'
BLD=$'\033[1m'

parts=()
(( ready > 0 ))      && parts+=("${BLD}${RED}ready $ready${RST}")
(( blocked > 0 ))    && parts+=("${BLD}${YLW}blocked $blocked${RST}")
(( merged > 0 ))     && parts+=("${BLD}${TEAL}merged $merged${RST}")
(( unapproved > 0 )) && parts+=("${BLD}${SKY}review $unapproved${RST}")
(( sonata > 0 ))     && parts+=("${BLD}${MAUVE}sonata $sonata${RST}")

if (( ${#parts[@]} == 0 )); then
  text="incoming: clear"
  color="dim"
else
  # Join with dim ` · ` separator (bash IFS only uses first char, so loop)
  text=""
  for p in "${parts[@]}"; do
    if [[ -z "$text" ]]; then text="$p"; else text="${text}${DIM} · ${RST}${p}"; fi
  done
  # Region-level color set to default; inline ANSI codes drive per-part color
  color="default"
fi

# If data is more than 30 min old, mark it visually
if (( data_age > 1800 )); then
  text="$text (stale)"
  color="yellow"
fi

jq -n \
  --arg id "$ID" \
  --arg t "$text" \
  --arg c "$color" \
  --argjson p "$PRIORITY" \
  --argjson r "$ROW" \
  --argjson ttl "$TTL_SEC" \
  --argjson now "$NOW" \
  '{id: $id, text: $t, color: $c, priority: $p, row: $r, ttl_sec: $ttl, updated_at: $now}' \
  > "$REGION_FILE"

exit 0
