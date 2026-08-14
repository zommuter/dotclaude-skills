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
# ── TWO HALVES, deliberately separate (id:f391) ───────────────────────────────────────
# `ROADMAP_PARKED_HEADING_VOCAB` — the pattern every reader consumes — is COMPOSED from
# two independently-defined halves. They are separate because id:6446 will anchor ONE of
# them and must not be able to reach the other:
#
#   MARKERS  first-class, explicitly-named dispatch-exclusion markers. These are TOKENS a
#            heading carries on purpose (like `@manual`/`@container` at item level), not
#            descriptive prose, so they are ALREADY standalone-anchored here.
#   WORDS    the descriptive parking VOCABULARY ("Gated / deferred", "Done", "Icebox").
#            Matched UNANCHORED today; making that match intentional is id:6446's whole
#            job (a heading merely MENTIONING `archive` must stop parking its section).
#
# WHY THE SPLIT EXISTS — read before touching either half. Until 2026-08-14 `@owner-gated`
# appeared NOWHERE in this file: a heading like loderite's
#     ### `@owner-gated` — an executor CANNOT discharge these
# was parked ONLY because the literal string `@owner-gated` CONTAINS the vocab word
# `gated`. Three open loderite items (f303, d385, 6e7a) had their dispatch protection
# resting on that coincidence. Anchoring the vocabulary — exactly what id:6446 does —
# would have removed the coincidence in the same edit and made owner-gated work
# executor-dispatchable: an owner-gate breach (the failure class id:540f/id:c179's owner
# holds exist to prevent). The owner RULED 2026-08-14 that `@owner-gated` IS a dispatch
# exclusion, on the same footing as `@manual`/`@container`.
#
# ⚠️  id:6446 IMPLEMENTER: anchor `ROADMAP_PARKED_HEADING_WORDS` ONLY. Do NOT wrap or
#     anchor the composed `ROADMAP_PARKED_HEADING_VOCAB` — that would re-capture the
#     marker half and silently un-protect owner-gated sections again.
#     tests/test_owner_gated_first_class_f391.sh enforces this: it rewrites the WORDS
#     line into an anchored form and asserts `@owner-gated` STILL parks, for the bash
#     predicate AND for classify-repo.sh / gather-repo-state.sh.
#
# Marker grammar: a STANDALONE `@owner-gated` token — a preceding/following word char
# means it is a different word (`@owner-gatedness` does NOT match). Spelled with explicit
# `[^A-Za-z0-9_…]` classes rather than `[[:alnum:]]`/`\w` so the ONE exported string is
# valid as BOTH an ERE (bash `=~`) and a Python `re` pattern — python's `re` does not
# understand POSIX bracket expressions, and this string is consumed by both.
ROADMAP_PARKED_HEADING_MARKERS='(^|[^A-Za-z0-9_])@owner-gated([^A-Za-z0-9_-]|$)'
ROADMAP_PARKED_HEADING_WORDS='(gated|deferred|done|icebox|archive|parked)'
ROADMAP_PARKED_HEADING_VOCAB="(${ROADMAP_PARKED_HEADING_MARKERS}|${ROADMAP_PARKED_HEADING_WORDS})"
ROADMAP_HEADING_LINE_ERE='^[[:space:]]*#{1,6}[[:space:]]'
ROADMAP_HEADING_LINE_PCRE='^[ \t]*#{1,6}[ \t]'
export ROADMAP_PARKED_HEADING_MARKERS ROADMAP_PARKED_HEADING_WORDS
export ROADMAP_PARKED_HEADING_VOCAB ROADMAP_HEADING_LINE_ERE ROADMAP_HEADING_LINE_PCRE

# is_heading_line <line> — exit 0 when the line is a markdown ATX heading (H1..H6).
# A heading RE-DECIDES the section for every line that follows it, so every caller's
# section walk must recognize headings identically or the "one predicate" is only half
# shared (that was exactly bb32's divergence).
is_heading_line() {
  [[ "$1" =~ $ROADMAP_HEADING_LINE_ERE ]]
}

# is_exempt_heading <heading-line> — exit 0 when the heading names a parked bucket,
# EITHER by carrying a first-class exclusion MARKER (`@owner-gated`, standalone-anchored)
# OR by matching the descriptive parking WORD vocabulary. An item is EXEMPT when its
# nearest preceding heading matches. Matched case-insensitively on the heading TEXT; the
# WORD half is substring, not anchored — real headings vary ("## Gated / deferred",
# "### Gated on OPEN owner decisions", "## Done", "## Icebox").
# (The unanchored-substring false positive on the WORD half — "ungated" — is a KNOWN
# separate defect, TODO id:920b / ROADMAP id:6446; do not fix it here, fix it in this one
# place when it is ruled, and see the ⚠️ note above before you do.)
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
