#!/usr/bin/env bash
# platform.sh — cross-platform shims for macOS / Linux / Windows Git Bash
# Source this file: source "$(dirname "$0")/../lib/platform.sh"
# Provides: stat_mtime, date_days_ago, tail_reverse

# stat_mtime <path> — print file mtime as Unix timestamp, or 0 on failure
stat_mtime() {
  stat -f%m "$1" 2>/dev/null \
    || stat -c%Y "$1" 2>/dev/null \
    || echo 0
}

# date_days_ago <n> — print date N days ago as YYYY-MM-DD
date_days_ago() {
  local n="$1"
  date -v-"${n}d" +%Y-%m-%d 2>/dev/null \
    || date -d "-${n} days" +%Y-%m-%d 2>/dev/null \
    || echo ""
}

# tail_reverse <file> — print file lines in reverse order
tail_reverse() {
  tail -r "$1" 2>/dev/null \
    || tac "$1" 2>/dev/null \
    || awk 'BEGIN{i=0} {lines[i++]=$0} END{while(i-->0) print lines[i]}' "$1"
}
