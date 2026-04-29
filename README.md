# claude-statusline

Multi-region statusline composer for Claude Code. Forks producers in parallel, reads region snapshots, drops stale entries, sorts by priority, fits within a per-row width budget, and prints one or more colored rows.

Pairs nicely with [better-buddy](https://github.com/snackdriven/better-buddy) — the buddy producer reads `~/.claude/buddy.json` if you have a companion.

## Install

```bash
git clone https://github.com/snackdriven/claude-statusline.git
cd claude-statusline
./install.sh
```

`install.sh` copies the shim + `buddy/` tree into `~/.claude/`, sets the `statusLine` command in `~/.claude/settings.json` to `bash ~/.claude/buddy-status.sh`, and wires a `SessionStart` hook that runs `session-reset.sh`.

Restart Claude Code to pick up the change.

## What it looks like

```
(•ω•) ★ Bandit ❤❤❤ · ctx 13% · TTOAD-44 … idle 99m
client-intake on main+5 · meet Task Toads Release @ Apr 30 11:30a
sonata: test pages, not dev
```

Three rows. Each region produced by its own script, written to a JSON snapshot file, composed by the renderer.

## Architecture

```
Claude Code → buddy-status.sh (shim) → buddy/render.sh
                                         ├─ forks all producers/*.sh in parallel (each self-caches via TTL)
                                         └─ reads regions/*.json, sorts, fits, colors, prints
```

**Region contract** (each producer writes one):

```json
{
  "id": "ticket",
  "text": "TTOAD-44 · idle 99m",
  "color": "dim",
  "row": 0,
  "priority": 80,
  "ttl_sec": 60,
  "updated_at": 1777497903
}
```

**Render rules** (`buddy/render.sh`):
- Sort by `row` asc, then `priority` desc within row
- Drop entries where `now - updated_at > ttl_sec`
- 120-char width budget per row, separator ` · `, ANSI colors (dim / cyan / magenta / yellow / red / green)
- Width overflow drops the next region silently, no truncation
- Empty rows skipped

## Producers

| File | Region | Row | Priority | TTL | What it shows |
|---|---|---|---|---|---|
| `buddy.sh` | buddy companion | 0 | 90 | 30s | Pet face from `~/.claude/buddy.json` (better-buddy state, optional) |
| `context.sh` | context window | 0 | 80 | 15s | `ctx 13%` from the live transcript JSONL |
| `ticket.sh` | active ticket | 0 | 80 | 60s | Detected TTOAD ticket from filesystem activity, with idle timer |
| `coord.sh` | coordinator | 1 | 75 | 30s | Multi-session coordinator heartbeat + worker dots |
| `project.sh` | project | 1 | 60 | 30s | `client-intake on main+5` (basename + branch + dirty count) |
| `meeting.sh` | next meeting | 1 | 50 | 60s | From `~/.claude/next-meeting.txt` |
| `conscience.sh` | rule hint | 2 | 40 | 60s | Match recent activity against feedback rules, surface one hint |

Each producer runs as `bash producer.sh` with the Claude Code statusline JSON piped to stdin (`workspace.current_dir`, `transcript_path`, etc). Producers self-cache by checking their region file's `updated_at` against TTL, so the renderer parallelism is cheap.

## Conscience system

The conscience producer matches recent tool activity against an 18-rule feedback index and surfaces one hint inline. Files:

- `buddy/build-conscience-index.sh` — rebuilds `conscience-index.json` from a hardcoded rule list. Run this after edits.
- `buddy/conscience-index.json` — generated rule table (file → hint, color, cooldown_min, triggers[]).
- `buddy/.cooldowns.json` — per-rule last-shown timestamps so the same hint doesn't spam (gitignored).
- `buddy/events.log` — append-only ledger of recent tool calls (`<ts> <tool> <cmd> <cwd> <file>`). Populated by a hook elsewhere; not provided by this repo (gitignored).

**Trigger kinds** in the rule table:
- `bash_cmd` — regex against the bash command string
- `file_path` — regex against the tool target path
- `cwd_path` — regex against the working directory
- `tool_name` — regex against the tool name

To add a rule, edit `build-conscience-index.sh` and run it. Cooldown is per-rule.

## Session state

- `buddy/session-state.json` — short-lived per-session counters (closer_phrases, pass_fail_log, recent_searches). Gitignored.
- `buddy/session-reset.sh` — wired by the installer to the SessionStart hook. Resets the file so each new session starts clean.

## Customizing

- **Add a region** → write `buddy/producers/<name>.sh` that emits `buddy/regions/<name>.json`. Pick a row + priority that doesn't fight the existing producers. Set TTL to whatever cadence the data updates at. No renderer changes needed.
- **Add a conscience rule** → edit `buddy/build-conscience-index.sh`, run it.
- **Renderer changes** (width budget, separator, color map) → `buddy/render.sh`.
- **Wiring changes** → `~/.claude/settings.json`.

## Implementation notes

- `set -u` not `-e` in the renderer — producer failures shouldn't kill the line.
- Bare `&` (not subshell-fork) for producer parallelism so the parent can `wait` on the jobs.
- A single `jq -rs` pass does the filter + sort, output is TSV, then bash groups by row.
- The shim is intentionally three lines so the indirection is obvious in `settings.json` reads.

## Requires

- bash, jq, python3 (only for installer)
- macOS or Linux. Not tested on WSL or Windows.
