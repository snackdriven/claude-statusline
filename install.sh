#!/usr/bin/env bash
# install.sh — claude-statusline installer
# Copies buddy-status.sh + buddy/ tree into ~/.claude/ and wires the statusLine.

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "→ Installing claude-statusline..."

mkdir -p "$CLAUDE_DIR/buddy/producers" "$CLAUDE_DIR/buddy/regions"

# Shim
cp "$REPO_DIR/buddy-status.sh" "$CLAUDE_DIR/buddy-status.sh"
chmod +x "$CLAUDE_DIR/buddy-status.sh"

# Renderer + producers + tooling
cp "$REPO_DIR/buddy/render.sh" "$CLAUDE_DIR/buddy/render.sh"
cp "$REPO_DIR/buddy/session-reset.sh" "$CLAUDE_DIR/buddy/session-reset.sh"
cp "$REPO_DIR/buddy/build-conscience-index.sh" "$CLAUDE_DIR/buddy/build-conscience-index.sh"
cp "$REPO_DIR/buddy/conscience-index.json" "$CLAUDE_DIR/buddy/conscience-index.json"
cp "$REPO_DIR/buddy/producers/"*.sh "$CLAUDE_DIR/buddy/producers/"
chmod +x "$CLAUDE_DIR/buddy/render.sh" \
         "$CLAUDE_DIR/buddy/session-reset.sh" \
         "$CLAUDE_DIR/buddy/build-conscience-index.sh" \
         "$CLAUDE_DIR/buddy/producers/"*.sh

echo "  ✓ scripts → ~/.claude/buddy/"

# Wire statusLine + SessionStart hook in settings.json
if ! command -v python3 &>/dev/null; then
  echo ""
  echo "  ⚠  python3 not found. Add manually to $SETTINGS:"
  echo ""
  cat <<'JSON'
  "statusLine": { "type": "command", "command": "bash ~/.claude/buddy-status.sh" },
  "hooks": {
    "SessionStart": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.claude/buddy/session-reset.sh" }] }
    ]
  }
JSON
  exit 0
fi

PYTHONUTF8=1 python3 - <<PYEOF
import json, os
settings_path = os.path.join(os.path.expanduser("~"), ".claude", "settings.json")
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            settings = {}

settings["statusLine"] = {
    "type": "command",
    "command": "bash ~/.claude/buddy-status.sh"
}

reset_cmd = "bash ~/.claude/buddy/session-reset.sh"
hooks = settings.get("hooks", {})
session_start = hooks.get("SessionStart", [])
already = any(
    any(h.get("command") == reset_cmd for h in block.get("hooks", []))
    for block in session_start
)
if not already:
    session_start.append({"matcher": "", "hooks": [{"type": "command", "command": reset_cmd}]})
hooks["SessionStart"] = session_start
settings["hooks"] = hooks

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
print("  ok: settings.json updated")
PYEOF

echo ""
echo "  ✓ Done. Restart Claude Code to pick up the new statusline."
