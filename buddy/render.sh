#!/usr/bin/env bash
# render.sh — multi-region statusline composer
#
# Forks all producers in parallel (each self-caches via TTL),
# reads regions/*.json, drops stale, sorts by priority desc,
# fits within width budget, applies color, prints one line.
#
# Region contract:
#   {id, text, color, priority, ttl_sec, updated_at, tooltip?}
# Color names → ANSI map below.
#
# Stdin: Claude Code passes JSON (workspace.current_dir, etc) — passed through to producers.
# Stdout: single line, ANSI-colored.

set -u  # no -e: producer failures shouldn't kill the renderer

BUDDY_DIR="$HOME/.claude/buddy"
REGIONS_DIR="$BUDDY_DIR/regions"
PRODUCERS_DIR="$BUDDY_DIR/producers"
WIDTH_BUDGET=120
SEPARATOR=" · "

# Read stdin so producers can also consume it
STDIN_JSON=$(cat 2>/dev/null || echo '{}')

# Fork all producers in parallel; each producer self-caches
# IMPORTANT: bare `&` (not `(... &)`) so parent shell can `wait` on the jobs
if [[ -d "$PRODUCERS_DIR" ]]; then
  shopt -s nullglob
  for p in "$PRODUCERS_DIR"/*.sh; do
    [[ -f "$p" ]] || continue
    echo "$STDIN_JSON" | bash "$p" >/dev/null 2>&1 &
  done
  shopt -u nullglob
  wait
fi

# Bail early if no regions exist yet (fresh install)
shopt -s nullglob
region_files=("$REGIONS_DIR"/*.json)
shopt -u nullglob
(( ${#region_files[@]} == 0 )) && exit 0

# Read + filter + sort regions in a single jq pass; emit TSV: row\ttext\tcolor
# Sort first by row asc, then within-row by priority desc.
now=$(date +%s)
tsv=$(jq -rs --argjson now "$now" '
  [
    .[]
    | select(type == "object")
    | select(.text != null and .text != "")
    | select(($now - (.updated_at // 0)) <= (.ttl_sec // 60))
  ]
  | sort_by((.row // 0), -(.priority // 0))
  | .[]
  | "\(.row // 0)\t\(.text)\t\(.color // "default")"
' "${region_files[@]}" 2>/dev/null)

[[ -z "$tsv" ]] && exit 0

# Group by row; each row gets its own width budget.
# Empty rows are skipped (no blank lines between rendered rows).
RESET=$'\033[0m'
output=""
current_row=""
row_buffer=""
row_len=0
first_in_row=1

flush_row() {
  if [[ -n "$row_buffer" ]]; then
    [[ -n "$output" ]] && output+=$'\n'
    output+="$row_buffer"
  fi
  row_buffer=""
  row_len=0
  first_in_row=1
}

while IFS=$'\t' read -r row text color; do
  [[ -z "$text" ]] && continue
  if [[ "$row" != "$current_row" ]]; then
    flush_row
    current_row="$row"
  fi
  add_len=${#text}
  (( first_in_row == 0 )) && add_len=$(( add_len + ${#SEPARATOR} ))
  if (( row_len + add_len > WIDTH_BUDGET )); then
    continue
  fi
  case "$color" in
    dim)     ansi=$'\033[90m' ;;
    cyan)    ansi=$'\033[36m' ;;
    magenta) ansi=$'\033[35m' ;;
    yellow)  ansi=$'\033[33m' ;;
    red)     ansi=$'\033[31m' ;;
    green)   ansi=$'\033[32m' ;;
    *)       ansi=$'\033[0m'  ;;
  esac
  if (( first_in_row == 1 )); then
    row_buffer+="${ansi}${text}${RESET}"
    first_in_row=0
  else
    row_buffer+="${SEPARATOR}${ansi}${text}${RESET}"
  fi
  row_len=$(( row_len + add_len ))
done <<< "$tsv"
flush_row

printf "%s" "$output"
