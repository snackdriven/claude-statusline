#!/usr/bin/env bash
# build-conscience-index.sh — regenerate conscience-index.json from the hardcoded 18-rule list.
#
# Manual rebuild trigger. Feedback notes don't carry machine-readable trigger metadata yet,
# so the rule table lives here as the source of truth.
#
# Usage: bash ~/.claude/buddy/build-conscience-index.sh

set -euo pipefail

OUT="$HOME/.claude/buddy/conscience-index.json"

cat > "$OUT" <<'JSON'
[
  {
    "file": "feedback-gha-failure-not-deploy-truth.md",
    "hint": "gha red ≠ not deployed",
    "color": "yellow",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "bash_cmd", "pattern": "gh run|gh actions|workflow"},
      {"kind": "file_path", "pattern": "github\\.com.*actions"}
    ]
  },
  {
    "file": "feedback-test-in-dev-not-tilt.md",
    "hint": "test in dev not tilt",
    "color": "dim",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "bash_cmd", "pattern": "tilt"},
      {"kind": "cwd_path", "pattern": "nhha|client-intake"}
    ]
  },
  {
    "file": "feedback-dev-data-is-mutable.md",
    "hint": "dev data is mutable, no need to hedge",
    "color": "dim",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "file_path", "pattern": "nhha\\.development"},
      {"kind": "bash_cmd", "pattern": "nhha\\.development"}
    ]
  },
  {
    "file": "feedback-ac-literal-no-interpretation.md",
    "hint": "ac is literal — read comments for amendments",
    "color": "yellow",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "file_path", "pattern": "jira-comments/.*\\.md"}
    ]
  },
  {
    "file": "feedback-no-at-mention-ticket-assignee.md",
    "hint": "no @assignee on QA pass",
    "color": "yellow",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "tool_name", "pattern": "mcp__atlassian__addCommentToJiraIssue|mcp__plugin_atlassian_atlassian__addCommentToJiraIssue"}
    ]
  },
  {
    "file": "feedback-sonata-testing-flow.md",
    "hint": "sonata: test pages, not dev",
    "color": "dim",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "file_path", "pattern": "sud|tar|sonata|TITAN-|WRKA-"},
      {"kind": "bash_cmd", "pattern": "sud|sonata"}
    ]
  },
  {
    "file": "feedback-always-include-figma.md",
    "hint": "include figma link in test plan",
    "color": "dim",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "file_path", "pattern": "testing-steps-.*\\.html|test-plan.*\\.(html|md)"}
    ]
  },
  {
    "file": "feedback-jira-closer-variations.md",
    "hint": "vary your closer",
    "color": "dim",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "session_state", "pattern": "closer_phrases.last3_match"}
    ]
  },
  {
    "file": "feedback-wait-before-labeling-bugs.md",
    "hint": "wait 2-4s before calling bugs",
    "color": "yellow",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "tool_name", "pattern": "mcp__chrome-devtools.*take_snapshot|mcp__plugin_chrome-devtools.*take_snapshot|mcp__plugin_playwright_playwright__browser_snapshot"}
    ]
  },
  {
    "file": "feedback-local-only-by-default.md",
    "hint": "local only — no push without verb",
    "color": "dim",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "file_path", "pattern": "dailies/"}
    ]
  },
  {
    "file": "feedback-no-smoke-on-done-tickets.md",
    "hint": "done + your PASS = drop ticket",
    "color": "yellow",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "tool_name", "pattern": "mcp__atlassian__getJiraIssue|mcp__plugin_atlassian_atlassian__getJiraIssue"}
    ]
  },
  {
    "file": "feedback-race-condition-test-method.md",
    "hint": "dblClick: true, not .click().click()",
    "color": "yellow",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "bash_cmd", "pattern": "double.click|dblClick|\\.click\\(\\)\\.click\\(\\)"},
      {"kind": "file_path", "pattern": "double.click|dblClick"}
    ]
  },
  {
    "file": "feedback-transient-ui-detection.md",
    "hint": "mutationobserver, not sleep",
    "color": "yellow",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "bash_cmd", "pattern": "snackbar|toast|MuiSnackbar"},
      {"kind": "file_path", "pattern": "snackbar|toast"}
    ]
  },
  {
    "file": "feedback-jira-gh-temporal-investigation.md",
    "hint": "search jira + gh together for timeline",
    "color": "dim",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "bash_cmd", "pattern": "git log|git blame|gh pr list"},
      {"kind": "tool_name", "pattern": "mcp__atlassian__searchJiraIssuesUsingJql|mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql"}
    ]
  },
  {
    "file": "feedback-fix-or-plan-not-flag.md",
    "hint": "fix or plan, don't flag",
    "color": "dim",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "bash_cmd", "pattern": "TODO|FIXME|broken|not working"}
    ]
  },
  {
    "file": "feedback-proactive-tool-use.md",
    "hint": "search backpack first, then ask",
    "color": "dim",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "session_state", "pattern": "recent_searches.empty_for_active_ticket"}
    ]
  },
  {
    "file": "feedback-consult-style-memory-before-drafting.md",
    "hint": "read style memory before drafting",
    "color": "dim",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "file_path", "pattern": "jira-comments/.*\\.md|kickback.*\\.md|qa-comment.*\\.md"}
    ]
  },
  {
    "file": "feedback-fresh-assumptions-on-reverify.md",
    "hint": "re-test with ⏳, don't pre-mark",
    "color": "yellow",
    "cooldown_min": 30,
    "triggers": [
      {"kind": "session_state", "pattern": "pass_fail_log.ticket_in_log_and_being_refetched"}
    ]
  }
]
JSON

# Validate
if jq -e '. | length == 18' "$OUT" >/dev/null 2>&1; then
  echo "wrote $OUT (18 entries, valid JSON)"
else
  echo "ERROR: $OUT failed validation" >&2
  exit 1
fi
