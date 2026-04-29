#!/usr/bin/env bash
# session-reset.sh — runs on SessionStart. Zeroes session-scoped buddy state.
SESSION_STATE="$HOME/.claude/buddy/session-state.json"
mkdir -p "$HOME/.claude/buddy" 2>/dev/null
echo '{"closer_phrases":[],"pass_fail_log":{},"recent_searches":[]}' > "$SESSION_STATE"
exit 0
