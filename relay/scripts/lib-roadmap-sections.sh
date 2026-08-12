#!/usr/bin/env bash
# lib-roadmap-sections.sh — the SINGLE definition of "is this ROADMAP heading a parked
# bucket?", shared by every reader that must not treat explicitly-parked items as live work.
#
# Extracted from roadmap-lint.sh (id:4b8f, 2026-08-12), which had the only copy. It was a
# LINT-ONLY concept, so the dispatch counters never learned it: gather-repo-state.sh's
# open_hard_pool walked ROADMAP.md line-by-line with no notion of the heading a line sits
# under, and therefore counted items the linter (and the ROADMAP's own prose) call parked.
#
# Live consequence, zkWhale 2026-08-12 (run relay-20260812-122721-23819): all 6 of its open
# `[HARD]` items sit under `## Gated / deferred` — each already carrying a gate note and an
# explicitly OPEN owner decision (id:320b, id:b3c4, id:638e) — and there are ZERO `[HARD]`
# items under the active `## Items` heading. The classifier nevertheless reported
# "Open [HARD — pool] items: 6" and dispatched an Opus HARD child EVERY round, each of which
# read the ledger, correctly concluded there was nothing executable, and handed back. That
# repeated until the id:1432 no-work suppression caught it.
#
# The rule this encodes is the ROADMAP's own, quoted from zkWhale's gated heading:
#   "Items parked here are explicitly deferred — the linter exempts gated-heading items.
#    Do not pick up; a reviewer re-promotes them into `## Items` with a lane tag."
# A counter that ignores it re-picks them up on the reviewer's behalf, every round.
#
# NOTE for callers: this answers a question about ONE heading line. Tracking which heading
# is currently in effect (and resetting on the next heading) is the caller's loop — see
# roadmap-lint.sh's `in_exempt_section` and gather-repo-state.sh's open_hard_pool walk.

# is_exempt_heading <heading-line> — exit 0 when the heading names a parked bucket.
# An item is EXEMPT when its nearest preceding `## ` / `### ` heading matches. Matched
# case-insensitively on the heading TEXT (substring, not anchored): real headings vary
# ("## Gated / deferred", "### Gated on OPEN owner decisions", "## Done", "## Icebox").
is_exempt_heading() {
  local h="$1"
  shopt -s nocasematch
  local exempt=1
  if [[ "$h" =~ (gated|deferred|done|icebox|archive|parked) ]]; then
    exempt=0
  fi
  shopt -u nocasematch
  return $exempt
}
