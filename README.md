<div align="center">

# claude-statusline

**a small perch for the things you keep checking.**

🍪 &nbsp; Claude Code · terminal · optional company

</div>

<sub>README edited by Codex (GPT-6 AI agent).</sub>

A status bar for Claude Code. It shows session details, such as context use, the active ticket, and the current branch.

Add [better-buddy](https://github.com/snackdriven/better-buddy) for a terminal companion.

```text
(•ω•) ★ Bandit ❤❤❤ · ctx 13% · TTOAD-44 … idle 99m
client-intake on main+5 · meet Task Toads Release @ Apr 30 11:30a
sonata: test pages, not dev
```

## Install

Use macOS or Linux with Bash, jq, and Python 3. WSL and Windows are untested.

Back up `~/.claude/` before installation. The installer replaces its scripts and changes `settings.json`.

```bash
git clone https://github.com/snackdriven/claude-statusline.git
cd claude-statusline
./install.sh
```

Restart Claude Code.

The installer sets the `statusLine` command and removes legacy buddy hooks. Get the buddy plugin from the `dotclaude` backup for `/buddy` and its hooks.

## Choose what appears

The information bar and companion bar are on by default. Add the applicable setting to your shell configuration:

```bash
export STATUSLINE_INFO=0    # Hide the information bar.
export STATUSLINE_BUDDY=0   # Hide the companion bar.
```

To disable one producer, rename its installed file from `<name>.sh` to `<name>.sh.disabled` in `~/.claude/buddy/producers/`.

To set the terminal width, set `CLAUDE_STATUSLINE_WIDTH` to a column count.

## Producers

A **producer** is a script that supplies one or more display regions. Some producers need separate tools, hooks, or local services.

| Script | Shows |
| --- | --- |
| `agents.sh` | Agents running in this session |
| `buddy.sh` | The optional companion |
| `cron.sh` | Recorded job failures; display only |
| `context.sh` | Context use |
| `ticket.sh` | The active ticket and idle time |
| `incoming.sh` | Cached review and readiness counts |
| `pr.sh` | The active pull request |
| `coord.sh` | Coordinator activity |
| `sessions.sh` | Other session activity |
| `project.sh` | The directory, branch, and changed-file count |
| `gh.sh` | The active GitHub account |
| `meeting.sh` | The next meeting |
| `spotify.sh` | The current track |
| `conscience.sh` | A rule reminder |
| `op_core.sh` | Data from operator-core-mini |
| `qa_state.sh` | Ticket counts and optional release data |

The companion bar uses `buddy.sh`, `conscience.sh`, and `spotify.sh`. The information bar uses the other producers.

## Technical reference

See [the reference](docs/reference.md) for:

- [Display rules and region fields](docs/reference.md#architecture).
- [Data sources and producer settings](docs/reference.md#producers).
- [Terminal links](docs/reference.md#clickable-regions-osc-8-links).
- [Optional QA services](docs/reference.md#op-co-mi--qa-brain-bridges).
- [Custom producers and rule reminders](docs/reference.md#customizing).
