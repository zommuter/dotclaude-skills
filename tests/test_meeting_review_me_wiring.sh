#!/usr/bin/env bash
# (no roadmap token — feature from meeting design
#  docs/meeting-notes/2026-06-15-0715-meeting-fables-interaction.md D5, tracked in
#  TODO.md id:15d5, not ROADMAP.md; this test always counts.)
#
# Static contract: meeting/SKILL.md wires REVIEW_ME.md into the no-arg flow as a
# relay-detection-gated Class 3 candidate (read side) and a D5-invariant write-back
# (write side, bookkeeping only — no roadmap re-derivation).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/meeting/SKILL.md"

fail() { echo "FAIL: $1"; exit 1; }

# Read side: REVIEW_ME surfaced as a Class 3 candidate, gated on the file existing.
grep -q 'REVIEW_ME surface (D5' "$SKILL" || fail "no D5 REVIEW_ME surface step"
grep -qE 'REVIEW_ME\.md.*open box|count its open boxes' "$SKILL" || fail "no open-box count instruction"
grep -qE 'Class 3[*]* candidate' "$SKILL" || fail "REVIEW_ME not offered as a Class 3 candidate"

# Relay-detection gating: cross-ledger scan + REVIEW_ME + nudge all guard on ROADMAP.md.
grep -q 'cross-ledger' "$SKILL" || fail "no cross-ledger scan invocation"
grep -qE 'relay-managed repos only|ROADMAP\.md.*exists|exists.*relay-managed' "$SKILL" \
  || fail "relay-detection gating not stated"

# Write side: D5 write-back ticks REVIEW_ME + keeps TODO/ROADMAP checkbox state consistent.
grep -q 'Relay-ledger write-back (D5' "$SKILL" || fail "no D5 write-back step"
grep -q 'single-id-two-views' "$SKILL" || fail "write-back does not cite single-id-two-views"
grep -qE 'does NOT re-derive|bookkeeping only' "$SKILL" \
  || fail "write-back scope (no roadmap re-derivation) not bounded"

# Surface-only discipline: never auto-dispatch the REVIEW_ME candidate.
grep -qE 'never auto-dispatch|Surface-only' "$SKILL" || fail "REVIEW_ME surface not marked surface-only"

# Dispatch grounding: picking the candidate must run a meeting GROUNDED in the boxes,
# treating each open box as an agenda item with a confirm/correct decision — not an
# open-ended topic.
grep -q 'REVIEW_ME backlog candidate (D5' "$SKILL" || fail "no grounded REVIEW_ME dispatch in Class 3"
grep -qiE 'each open .*box as one agenda item|box.*as one agenda item' "$SKILL" \
  || fail "dispatch does not treat boxes as agenda items"
grep -qiE 'confirm.*tick the box|tick the box.*or.*correct' "$SKILL" \
  || fail "dispatch missing the confirm/correct decision shape"
grep -q 'step 2e' "$SKILL" || fail "dispatch does not connect to the step 2e write-back"

echo ok
