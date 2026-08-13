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

# ── THE two definitions, exported for NON-BASH readers (id:bb32) ───────────────────────
# `ef43739` claimed "one definition, no second parser" while a THIRD copy of the
# vocabulary lived in the python embedded in classify-repo.sh, because the guard grepped
# for the BASH FUNCTION NAME and a python copy never spells it. The copies had already
# DIVERGED on the heading-LINE recognizer: gather-repo-state.sh matched `#{1,6}` (H1
# included, leading whitespace allowed) while roadmap-lint.sh and classify-repo.sh matched
# `##+` only — so `# Gated / deferred` parked a section for the HARD counter and for
# nobody else. Reconciled toward the WIDER form: an H1 parked heading is honoured by every
# reader (the under-dispatch-safe direction, consistent with id:4b8f).
#
# Both patterns are exported as STRINGS so a python/node reader consumes THIS definition
# instead of retyping it. ERE (bash `=~`) and PCRE (python `re`) differ only in the
# whitespace class spelling — they must always describe the SAME language; the parity is
# covered end-to-end by tests/test_parked_heading_single_definition_bb32.sh, which mutates
# this file and asserts every reader follows.
ROADMAP_PARKED_HEADING_VOCAB='(gated|deferred|done|icebox|archive|parked)'
ROADMAP_HEADING_LINE_ERE='^[[:space:]]*#{1,6}[[:space:]]'
ROADMAP_HEADING_LINE_PCRE='^[ \t]*#{1,6}[ \t]'
export ROADMAP_PARKED_HEADING_VOCAB ROADMAP_HEADING_LINE_ERE ROADMAP_HEADING_LINE_PCRE

# is_heading_line <line> — exit 0 when the line is a markdown ATX heading (H1..H6).
# A heading RE-DECIDES the section for every line that follows it, so every caller's
# section walk must recognize headings identically or the "one predicate" is only half
# shared (that was exactly bb32's divergence).
is_heading_line() {
  [[ "$1" =~ $ROADMAP_HEADING_LINE_ERE ]]
}

# is_exempt_heading <heading-line> — exit 0 when the heading names a parked bucket.
# An item is EXEMPT when its nearest preceding heading matches. Matched
# case-insensitively on the heading TEXT (substring, not anchored): real headings vary
# ("## Gated / deferred", "### Gated on OPEN owner decisions", "## Done", "## Icebox").
# (The unanchored-substring false positive — "ungated" — is a KNOWN separate defect,
# TODO id:920b; do not fix it here, fix it in this one place when it is ruled.)
is_exempt_heading() {
  local h="$1"
  shopt -s nocasematch
  local exempt=1
  if [[ "$h" =~ $ROADMAP_PARKED_HEADING_VOCAB ]]; then
    exempt=0
  fi
  shopt -u nocasematch
  return $exempt
}
