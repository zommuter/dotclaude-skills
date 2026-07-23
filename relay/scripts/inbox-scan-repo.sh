#!/usr/bin/env bash
# inbox-scan-repo.sh — per-repo FILTERED view of the shared cross-project inbox
# (default ~/.claude/projects/todo-inbox.md, id:9fdb), for REPO-SCOPED relay runs
# (`/relay human .`, `/relay <repo>`, `/relay . --drain`, `/relay next`) that would
# otherwise skip the inbox entirely (SKILL.md invariant-1). id:ce50.
#
# WHY: a repo-scoped run currently never touches the global inbox, so a
# `[<repo>]`-targeted inbox item is invisible to it (gap hit 2026-07-20: `/relay
# human .` on chidiai skipped the inbox while routed:4975 sat unrouted). This is a
# report-only VISIBILITY surface — distinct from scan-routed.sh's `--all`
# dead-letter RECONCILE, which this script does NOT reimplement or replace.
#
# WHAT IT DOES: prints every OPEN `- [ ] [<repo>] …` inbox line whose TARGET
# bracket (the first `[...]` right after the checkbox) matches <repo> exactly —
# anchored on the target bracket, never a repo-name substring anywhere in the
# line's prose (the id:be0e/1bbd anchoring-not-substring class). `[x]` done items
# are never surfaced. Report-only: never writes, never mutates the inbox.
#
# Usage: inbox-scan-repo.sh <repo>
#   <repo> required — missing arg is misuse (nonzero exit).
#   Inbox path: $RELAY_INBOX if set, else the documented default
#   ~/.claude/projects/todo-inbox.md. Does NOT perform scan-routed.sh's legacy
#   ~/.claude/todo-inbox.md migration — that stays scan-routed's job; if a caller
#   needs migration to have happened first, run scan-routed.sh (or let it run).
#
# Exit codes:
#   0  success (with or without findings printed to stdout)
#   2  misuse (missing repo arg) or LOUD failure (inbox present but unreadable —
#      e.g. a directory — never silently swallowed)
#   A MISSING inbox file is BENIGN (exit 0, nothing printed): the inbox is
#   optional and often absent for a directed run; this is a visibility surface,
#   not a reconcile, so absence is not a dead-letter error.
set -uo pipefail

repo="${1:-}"
if [[ -z "$repo" ]]; then
  echo "inbox-scan-repo.sh: usage: inbox-scan-repo.sh <repo>" >&2
  exit 2
fi

inbox="${RELAY_INBOX:-$HOME/.claude/projects/todo-inbox.md}"

if [[ ! -e "$inbox" ]]; then
  # Missing inbox is benign — optional file, often absent for a directed run.
  exit 0
fi

if [[ ! -f "$inbox" || ! -r "$inbox" ]]; then
  # Present but not a readable regular file (e.g. a directory) — LOUD, never a
  # silent 2>/dev/null swallow.
  echo "inbox-scan-repo.sh: inbox is not a readable regular file: $inbox" >&2
  exit 2
fi

# Anchor on the TARGET bracket only: the first `[...]` immediately after the
# open checkbox `- [ ] `. grep -F would substring-match repo names inside other
# brackets or prose; -P + a literal-quoted repo name via printf avoids regex
# metacharacter surprises in repo names (e.g. a literal `.`).
esc_repo="$(printf '%s' "$repo" | sed 's/[.[\*^$()+?{|\\]/\\&/g')"
grep -E "^- \[ \] \[${esc_repo}\]" "$inbox" || true
exit 0
