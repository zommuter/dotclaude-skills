#!/usr/bin/env bash
# (no roadmap token — feature from meeting design
#  docs/meeting-notes/2026-06-15-0715-meeting-fables-interaction.md D6, tracked in
#  TODO.md id:7c23, not ROADMAP.md; this test always counts.)
#
# Reverse-handoff (D6): the relay review (and handoff) must detect ledger items added
# by /meeting or manual edits that lack [ROUTINE]/[HARD] qualifiers and qualify+size
# them (mini-handoff), reusing their id. Static contract on the reference docs + the
# review-unit prompt; also asserts relay-loop.js still parses.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REVIEW="$ROOT/fables-turn/references/review.md"
HANDOFF="$ROOT/fables-turn/references/handoff.md"
LOOP="$ROOT/fables-turn/scripts/relay-loop.js"

fail() { echo "FAIL: $1"; exit 1; }

# review.md §5b reverse-handoff step
grep -qE '5b\..*Qualify unqualified|Qualify unqualified ledger additions' "$REVIEW" \
  || fail "review.md missing §5b qualify step"
grep -q 'reverse-handoff' "$REVIEW" || fail "review.md does not name reverse-handoff"
grep -qE 'git diff .*\$LAST.*TODO\.md' "$REVIEW" || fail "review.md §5b missing diff-since-checkpoint detection"
grep -qE 'mini-handoff' "$REVIEW" || fail "review.md §5b missing mini-handoff promotion"
grep -q 'REUSING' "$REVIEW" && grep -q 'existing TODO' "$REVIEW" \
  || fail "review.md §5b must reuse the existing id (D2)"
# the three triage outcomes: promote / leave-as-meeting / skip-deferred
grep -qiE 'design-judgment' "$REVIEW" || fail "review.md §5b missing design-judgment carve-out"
grep -qiE 'Deferred / gated|deferred.*gated' "$REVIEW" || fail "review.md §5b missing deferred/gated skip"

# handoff C2 points at the same unqualified-item triage
grep -q 'Unqualified TODO items' "$HANDOFF" || fail "handoff.md C2 missing unqualified-item promotion"

# review-unit prompt mentions the reverse-handoff
grep -q 'Reverse-handoff' "$LOOP" || fail "relay-loop.js review prompt missing reverse-handoff clause"

# relay-loop.js still parses
if command -v node >/dev/null 2>&1; then
  node --check "$LOOP" || fail "relay-loop.js failed node --check after edit"
fi

echo ok
