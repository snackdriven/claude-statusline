<div align="center">

# claude-statusline

**a small perch for the things you keep checking.**

context, tickets, the current branch.<br>
room for a creature with opinions.

🍪 &nbsp; Claude Code · terminal · optional company

</div>

---

A status bar for Claude Code that keeps session details in view between messages. Context use, the active ticket, and the project branch share the terminal with optional meeting, music, and companion regions.

Pairs with [better-buddy](https://github.com/snackdriven/better-buddy) if you'd like company. The buddy producer reads `~/.claude/buddy.json`; hatching the creature belongs to better-buddy.

## What it looks like

```
(•ω•) ★ Bandit ❤❤❤ · ctx 13% · TTOAD-44 … idle 99m
client-intake on main+5 · meet Task Toads Release @ Apr 30 11:30a
sonata: test pages, not dev
```

Three rows. Each region produced by its own script, written to a JSON snapshot file, composed by the renderer.

## Find your corner

| Looking for | Start here |
| --- | --- |
| Put it in the terminal | [Requirements](#requires), then [Install](#install) |
| Keep the information bar, the companion, or both | [Two renderers](#two-renderers-info--buddy) |
| See what each little region reads | [Producers](#producers) |
| Choose what stays visible | [Customizing](#customizing) |
| Follow a link from the bar | [Clickable regions](#clickable-regions-osc-8-links) |
| Look under the floorboards | [Architecture](#architecture) |

## Install

```bash
git clone https://github.com/snackdriven/claude-statusline.git
cd claude-statusline
./install.sh
```

`install.sh` copies the shim + `buddy/` tree into `~/.claude/`, sets the `statusLine` command in `~/.claude/settings.json` to `bash ~/.claude/statusline.sh`, and strips any legacy settings.json-wired buddy hook entries (hooks + the `/buddy` command come from the `buddy@skills-dir` plugin at `~/.claude/skills/buddy/`, owned by the dotclaude backup repo — not this installer).

Restart Claude Code to pick up the change.

## Architecture

```
Claude Code → statusline.sh (shim) ┬→ render.sh info   (work / context / live regions)
                                   └→ render.sh buddy  (companion creature + conscience + ambient)

   each pass: forks ONLY its set's producers/*.sh in parallel (TTL self-cache)
              → reads its own regions/<sid>/<set>/*.json
              → assemble.py lays out the zones, fits the width, colors
              → prints its line(s); the shim stacks info on top, buddy below
```

The shim runs the two passes independently and stacks them. Either side can be turned off on its own (see "Two renderers" below), and `render.sh <set>` is callable standalone if you want one set somewhere else (a tmux bar, a shell prompt).

**Region contract** (each producer writes one):

```json
{
  "id": "ticket",
  "text": "TTOAD-44 · idle 99m",
  "color": "dim",
  "row": 0,
  "priority": 80,
  "ttl_sec": 60,
  "updated_at": 1777497903,
  "short": "TTOAD-44",
  "href": "https://chorusapp.atlassian.net/browse/TTOAD-44"
}
```

Required: `id` and `text`. Optional: `short` (a compact variant the layout swaps to when a row won't fit), `group` (zone grouping for `assemble.py`), `href` (makes the region a clickable link — see [Clickable regions](#clickable-regions-osc-8-links)), plus `color` / `row` / `priority` / `ttl_sec`, all defaulted.

**Render rules** (`buddy/render.sh` + `buddy/assemble.py`):
- Sort by `row` asc, then `priority` desc within row
- Drop entries where `now - updated_at > ttl_sec`
- Width budget per row defaults from `.terminal.width` (Claude Code stdin JSON), falls back to `tput cols`, then 120. Separator ` · `, ANSI colors (dim / cyan / magenta / yellow / red / green)
- **Override:** set `CLAUDE_STATUSLINE_WIDTH=<n>` in your shell rc to force a width. Useful when Claude Code under-reports terminal size (or you want a fixed budget regardless of which app is hosting).
- Width overflow drops the next region silently, no truncation
- Empty rows skipped

## Two renderers (info + buddy)

The bar is two independent passes over disjoint producer sets, sharing the one `render.sh` composer + `assemble.py` layout engine:

- **info** — everything that's work/context: project, gh, coord, tickets, incoming, sessions, agents, cron, the op-co-mi / qa-brain bridges.
- **buddy** — the companion: the creature (`buddy.sh`), its `conscience.sh` hint, and ambient `spotify.sh`.

Set membership lives in one variable at the top of `render.sh` (`BUDDY_PRODUCERS`); everything not listed there is info. Each pass writes to its own `regions/<sid>/<set>/` dir so the two never read each other's snapshots.

**Toggles** (set in your shell rc, default both on):

```bash
export STATUSLINE_INFO=0    # hide the info bar, keep the companion
export STATUSLINE_BUDDY=0   # hide the companion, keep the info bar
```

`render.sh info` / `render.sh buddy` also run standalone, so you can drop one set into a different host (tmux status, shell prompt) without the other. `render.sh` with no arg is the legacy all-producers mode.

## Producers

Set: `buddy.sh`, `conscience.sh`, and `spotify.sh` render in the companion pass; every other producer is info.



| File | Region | Row | Priority | TTL | What it shows |
|---|---|---|---|---|---|
| `agents.sh` | live subagents | 0 | 78 | 10s | `🤖 Explore:Read CHANGELOG.md` — running subagents in THIS session, from status files stamped by a PostToolUse/SubagentStop hook (`agent-status-stamp.sh`, lives in `~/.claude/hooks/`, not this repo). Empty region when no hook or no agents. |
| `buddy.sh` | buddy companion | 0 | 90 | 30s | Pet face from `~/.claude/buddy.json` (better-buddy state, optional) |
| `cron.sh` | scheduled-job health | 0 | 85 | 120s | `⚙ N jobs ✗` (red) when launchd/cron jobs failed today, read from `~/.claude/logs/cron-failures.log`. Empty when clean, so it's invisible until something breaks. Display-only, not an alert. |
| `context.sh` | context window | 0 | 80 | 15s | `ctx 13%` from the live transcript JSONL |
| `ticket.sh` | active ticket | 0 | 80 | 60s | Detected TTOAD ticket from filesystem activity, with idle timer |
| `incoming.sh` | incoming queue | 0 | 70 | 10m | `ready 3 · review 1 · sonata 2` — open-PR readiness + Sonata In-Review counts from `scripts/incoming.ts --summary`. Refreshes in the background and renders the cached value. |
| `pr.sh` | active PR | 0 | 58 | 2m | `PR #4378` from Claude Code stdin `.pr`, only when the branch has an open PR. Clickable to the PR (see [Clickable regions](#clickable-regions-osc-8-links)). |
| `coord.sh` | coordinator | 1 | 75 | 30s | Multi-session coordinator heartbeat + worker dots |
| `sessions.sh` | other sessions | 1 | 77 | 15s | Live activity of OTHER concurrent Claude sessions (their sync-names + last action) |
| `project.sh` | project | 1 | 60 | 30s | `client-intake on main+5` (basename + branch + dirty count) |
| `gh.sh` | active gh account | 1 | 55 | 60s | `gh:<account>` — color-coded so personal/work mix-ups are loud. Edit the case statement to change the color map. |
| `meeting.sh` | next meeting | 2 | 50 | 60s | From `~/.claude/next-meeting.txt` |
| `spotify.sh` | now playing | 2 | 45 | 20s | `♪ Artist – Track` from Spotify desktop app (macOS osascript / Linux playerctl). |
| `conscience.sh` | rule hint | 3 | 40 | 60s | Match recent activity against feedback rules, surface one hint |
| `op_core.sh` | op-co-mi bridge | 0–2 | 30–70 | 60s | 4 regions sourced from [operator-core-mini](https://github.com/snackdriven/operator-core-mini) (carry-state on row 0, today's meeting + freshness nudge on row 2, consent-gate banner on row 2) |
| `qa_state.sh` | qa-brain bridge | 0,2 | 55–75 | 45s | Today's TTOAD ticket counts (`in-review`, `in-progress`) on row 0 and optional next in-scope release date on row 2, sourced from [qa-brain](https://github.com/snackdriven/qa-brain) at `localhost:3737` |

**Row layout:** row 0 = critical at-a-glance (buddy, context, ticket, op_carry, qa_states), row 1 = active session context (coord, project, gh), row 2 = ambient (meeting, op_meeting, op_verify, qa_release, op_consent, spotify), row 3 = rule hints (conscience). Final placement is set by the `LAYOUT` map in `buddy/assemble.py`, which overrides a producer's declared `row` for listed regions and groups them into `◆`-separated zones; regions not in `LAYOUT` keep their own `row`.

**Enabled vs disabled:** every producer above ships in the repo, but each install turns them on or off independently. In `~/.claude/buddy/producers/`, a producer is active as `<name>.sh` and off as `<name>.sh.disabled` (the renderer only globs `*.sh`).

Each producer runs as `bash producer.sh` with the Claude Code statusline JSON piped to stdin (`workspace.current_dir`, `transcript_path`, etc). Producers self-cache by checking their region file's `updated_at` against TTL, so the renderer parallelism is cheap.

## Clickable regions (OSC 8 links)

Any region can be a clickable link. Set an `href` on the region JSON and `assemble.py` wraps the rendered text in an [OSC 8 hyperlink](https://en.wikipedia.org/wiki/ANSI_escape_code#OSC) as the final layout step, so the URL never counts against the width budget and never gets cut when a row is shortened. Cmd+click (macOS) or Ctrl+click (Linux/Windows) opens it.

The click is a terminal-level open, not a Claude Code action: the terminal hands the URL to the OS, so it can target any scheme the OS resolves (`https://`, `obsidian://`, `file://`, `spotify://`). It needs a terminal that supports OSC 8 hyperlinks (iTerm2, Kitty, WezTerm). Terminal.app doesn't; tmux strips the sequence unless `set -g allow-passthrough on`.

| Region | Click opens |
|---|---|
| `pr` | the active PR on GitHub |
| `project` | the current directory (Obsidian for the vault, Finder otherwise) |
| `spotify` | the Spotify app (`spotify://`) |
| `meeting` | Google Calendar (in your default browser) |
| sync-name (prepended in `statusline.sh`) | today's cross-terminal daily-sync doc |

To make any other region clickable, set `href` in its producer's JSON.

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
- **Enable / disable a producer** → rename its symlink in `~/.claude/buddy/producers/` between `<name>.sh` and `<name>.sh.disabled`. No repo change.
- **Make a region clickable** → set `href` in its producer's JSON ([Clickable regions](#clickable-regions-osc-8-links)).
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
