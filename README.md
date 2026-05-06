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
| `gh.sh` | active gh account | 1 | 55 | 60s | `gh:<account>` — color-coded so personal/work mix-ups are loud. Edit the case statement to change the color map. |
| `spotify.sh` | now playing | 3 | 45 | 20s | `♪ Artist – Track` from Spotify desktop app (macOS osascript / Linux playerctl). Own row so it never gets evicted when row 1 is tight. |
| `meeting.sh` | next meeting | 1 | 50 | 60s | From `~/.claude/next-meeting.txt` |
| `conscience.sh` | rule hint | 2 | 40 | 60s | Match recent activity against feedback rules, surface one hint |
| `op_core.sh` | op-co-mi bridge | 0–2 | 30–70 | 60s | 4 regions sourced from [operator-core-mini](https://github.com/snackdriven/operator-core-mini) (carry-state, today's meeting, freshness nudge, consent-gate banner) |
| `qa_state.sh` | qa-brain bridge | 0–1 | 55–75 | 45s | Today's TTOAD ticket counts (`in-review`, `in-progress`) and optional next in-scope release date, sourced from [qa-brain](https://github.com/snackdriven/qa-brain) at `localhost:3737` |

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

## op-co-mi + qa-brain bridges

Two optional producers that surface facts from the broader QA stack. Both fail open (write empty regions) when their data source isn't reachable, so they're safe to keep installed.

### `op_core.sh` — operator-core-mini

Calls [operator-core-mini](https://github.com/snackdriven/operator-core-mini)'s `renderers/statusline.py --json` once per cycle and fans the result into 4 regions:

| Region | Row | Priority | Color | What it shows |
|---|---|---|---|---|
| `op_carry`   | 0 | 70 | default | Top current Backpack item summary (loses to `ticket.sh` on row 0 when width is tight) |
| `op_meeting` | 1 | 50 | yellow  | Today's `q2`/`sync`/`meeting`-tagged Backpack item |
| `op_verify`  | 1 | 65 | yellow  | `<N> stale` — items needing verification per the freshness policy |
| `op_consent` | 2 | 30 | dim     | Short consent-gate banner (e.g. `1 held: health`) — never names suppressed items |

All filtering (consent gate, `surfaces` allowlist, `never_surface_in` denylist, freshness budget) lives in op-co-mi per ADR 0003 + 0004; this producer is a dumb projector.

**Setup:**

```bash
export OPERATOR_ROOT="$HOME/.operator-core"          # default
export OP_CORE_REPO="$HOME/code/operator-core-mini"  # default
```

If `$OPERATOR_ROOT/doctrine` is missing, `op_core.sh` falls back to qa-brain's legacy flat backpack at `$QA_BRAIN_URL/api/backpack` (default `http://localhost:3737`) and surfaces the most-recent date-suffixed entry as `op_carry`. Other regions stay empty in fallback mode — there is no consent gate or verify policy in the legacy flat backpack.

### `qa_state.sh` — qa-brain

Reads from [qa-brain](https://github.com/snackdriven/qa-brain) (`/api/tickets/state`, `/api/today`, `/api/manifest`) and emits:

| Region | Row | Priority | What it shows |
|---|---|---|---|
| `qa_states`  | 0 | 75 | `<n> in-review · <n> in-progress` — counts scoped to today's TTOAD set from the manifest. Other states stay silent. Color is `default` if any are in-progress, `dim` otherwise. |
| `qa_release` | 1 | 55 | `CHG-689 in 2d` — soonest in-scope release. Empty unless the toggle is on. |

**Toggles:**

```bash
export QA_BRAIN_URL="http://localhost:3737"  # default
export QA_SHOW_RELEASE_OPS=1                 # default 0 — show qa_release
export QA_STATE_CACHE_SECONDS=15             # default 15
```

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
