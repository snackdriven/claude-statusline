#!/usr/bin/env bash
# install.sh — claude-statusline installer
# Copies statusline.sh + buddy/ tree into ~/.claude/ and wires the statusLine.
# Migration-aware: strips legacy buddy hook entries from settings.json (those
# now come from the buddy@skills-dir plugin, owned by the dotclaude backup repo).

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "→ Installing claude-statusline..."

mkdir -p "$CLAUDE_DIR/buddy/producers" "$CLAUDE_DIR/buddy/regions" "$CLAUDE_DIR/buddy/lib"

# Shim
cp "$REPO_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh"

# Renderer + producers + tooling
cp "$REPO_DIR/buddy/render.sh" "$CLAUDE_DIR/buddy/render.sh"
cp "$REPO_DIR/buddy/assemble.py" "$CLAUDE_DIR/buddy/assemble.py"
cp "$REPO_DIR/buddy/session-reset.sh" "$CLAUDE_DIR/buddy/session-reset.sh"
cp "$REPO_DIR/buddy/build-conscience-index.sh" "$CLAUDE_DIR/buddy/build-conscience-index.sh"
cp "$REPO_DIR/buddy/conscience-index.json" "$CLAUDE_DIR/buddy/conscience-index.json"
cp "$REPO_DIR/buddy/producers/"*.sh "$CLAUDE_DIR/buddy/producers/"
cp "$REPO_DIR/buddy/lib/"*.sh "$CLAUDE_DIR/buddy/lib/"
chmod +x "$CLAUDE_DIR/statusline.sh" \
         "$CLAUDE_DIR/buddy/render.sh" \
         "$CLAUDE_DIR/buddy/session-reset.sh" \
         "$CLAUDE_DIR/buddy/build-conscience-index.sh" \
         "$CLAUDE_DIR/buddy/producers/"*.sh \
         "$CLAUDE_DIR/buddy/lib/"*.sh

echo "  ✓ scripts → ~/.claude/buddy/"

# Retire the pre-2026-06 shim if it's still around
if [[ -f "$CLAUDE_DIR/buddy-status.sh" ]]; then
  rm "$CLAUDE_DIR/buddy-status.sh"
  echo "  ✓ removed legacy ~/.claude/buddy-status.sh"
fi

# Optional bridges to operator-core-mini and qa-brain.
# These are no-ops at runtime unless OPERATOR_ROOT or QA_BRAIN_URL resolves
# to something real, so they're safe to install by default.
if [[ -f "$REPO_DIR/buddy/producers/op_core.sh" ]]; then
  echo "  ✓ op_core.sh installed (set OPERATOR_ROOT + OP_CORE_REPO to enable)"
fi
if [[ -f "$REPO_DIR/buddy/producers/qa_state.sh" ]]; then
  echo "  ✓ qa_state.sh installed (auto-detects qa-brain at localhost:3737)"
fi

# Wire statusLine in settings.json + strip legacy buddy hook entries
if ! command -v python3 &>/dev/null; then
  echo ""
  echo "  ⚠  python3 not found. Add manually to $SETTINGS:"
  echo ""
  cat <<'JSON'
  "statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" }
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
    "command": "bash ~/.claude/statusline.sh"
}

# Legacy settings.json-wired buddy hooks — provided by the buddy@skills-dir
# plugin since 2026-06-05, so any copies here would double-fire.
legacy = {
    "npx buddy-reroll --apply-hook",
    "bash ~/.claude/buddy/session-reset.sh",
    "bash ~/.claude/buddy-hook.sh",
    "bash ~/.claude/buddy-stop.sh",
}
hooks = settings.get("hooks", {})
removed = 0
for event in list(hooks):
    blocks = []
    for block in hooks[event]:
        kept = [h for h in block.get("hooks", []) if h.get("command") not in legacy]
        removed += len(block.get("hooks", [])) - len(kept)
        if kept:
            block["hooks"] = kept
            blocks.append(block)
    if blocks:
        hooks[event] = blocks
    else:
        del hooks[event]
if hooks:
    settings["hooks"] = hooks
else:
    settings.pop("hooks", None)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
print("  ok: settings.json updated" + (f" ({removed} legacy buddy hook entries removed)" if removed else ""))
PYEOF

# Buddy's hooks + /buddy command live in the buddy@skills-dir plugin, not here.
if [[ ! -f "$CLAUDE_DIR/skills/buddy/hooks/hooks.json" ]]; then
  echo ""
  echo "  ⚠  buddy plugin not found at ~/.claude/skills/buddy/."
  echo "     The statusline works without it, but buddy state hooks + /buddy won't run."
  echo "     Restore ~/.claude from the dotclaude backup repo to get it."
fi

echo ""
echo "  ✓ Done. Restart Claude Code to pick up the new statusline."
