# Changelog

All notable changes, reconstructed from git history on 2026-06-16 (no prior changelog existed). Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

Uncommitted working-tree changes (not yet in git history) — modifications across the renderer + producers: `buddy/assemble.py`, `buddy/render.sh`, `statusline.sh`, `install.sh`, `README.md`, `.gitignore`, and producers `agents.sh` / `meeting.sh` / `op_core.sh` / `project.sh` / `qa_state.sh` / `sessions.sh` / `spotify.sh`; plus new untracked `buddy/producers/cron.sh`, `buddy/producers/pr.sh`, `buddy/check-readme.py`, and `.githooks/`.

## 2026-06-09

### Fixed
- Concurrent-terminal flicker — per-session region dirs (9dba15b).

### Changed
- Declutter + restyle the statusline (7551b8f).

## 2026-06-05

### Changed
- New installer wiring: a neutral `statusline.sh` shim; strip the legacy `settings.json` buddy hooks (68c0f19).

## 2026-06-03

### Added
- 3-row statusline layout with stable height (558c298).
- `sessions.sh` producer — cross-terminal live session activity (4b7c6bc).
- `agents.sh` producer — live subagent activity, paired with the `agent-status-stamp.sh` hook (3f418b8).

### Changed
- Spacing/zone polish: roomier line-2 gaps, reversed row-0 zone order, de-densified live entries (498addb, 5d491fd, ec2ede7, a73e726).

## 2026-05-28

### Added
- `commits.sh` producer — today's commit count (93e0126).

### Changed
- Place commits next to the buddy on row 1; move the commits producer to row 3 (be12421, a987475).

## 2026-05-27

### Changed
- Dial-aware buddy expressions (cf8127d).

## 2026-05-26

### Changed
- Zoned + adaptive statusline layout with a bash fallback (PR #2) (c2fd688).

## 2026-05-21

### Added
- Per-species color + eye-cycle ports for the buddy (a3802df).

### Changed
- gitignore `.DS_Store` (c6f9bd6).

## 2026-05-20

### Added
- `incoming.sh` producer — surfaces NHHA PR + Sonata QA counts (eaa27cc).

### Changed
- Text labels + Catppuccin per-part colors; row reshuffle (f1a63bc, e9df540).

## 2026-05-06

### Added
- Spotify "now playing" region (110ccf4); gh active-account region (782d848).
- `CLAUDE_STATUSLINE_WIDTH` env override (bdeb33a); cross-platform shims via `buddy/lib/platform.sh` (5598379); inline ANSI color in all region text (6b997b3).

### Changed
- Restructure rows (ambient → row 2, rule hints → row 3; spotify to its own row) (9ddfcde, 3b23103).
- Width-aware rendering + TITAN detection + label cleanup (8093257); walk back 7 days for the ticket-daily region (b96d710).

### Fixed
- Terminal width parsing + emoji display-width accounting (e128555).

## 2026-04-29

### Added
- `op_core.sh` + `qa_state.sh` bridge producers (PR #1) (bb0d41d).
- Initial multi-region Claude Code statusline composer (62ec827).
