#!/usr/bin/env bash
# roadmap:3eb5 — relay-doctor front-door wiring: /relay health mode in SKILL.md
# + a /relay review sub-step surfacing findings to REVIEW_ME (never a hard block).
#
# These are STATIC-STRUCTURAL tests (the doctor script itself is tested in
# test_relay_doctor.sh for id:9bec). This test asserts the wiring:
#   (1) SKILL.md invocation block contains `/relay health`
#   (2) The health section in SKILL.md documents the relay-doctor.sh call and
#       the report-only / --strict note
#   (3) relay/references/review.md contains a sub-step (4b) that:
#       (a) calls relay-doctor.sh
#       (b) routes findings to REVIEW_ME
#       (c) is explicitly NEVER a hard block (report-only at review time)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/relay/SKILL.md"
REVIEW="$ROOT/relay/references/review.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]] || fail "relay/SKILL.md not found at $SKILL"
[[ -f "$REVIEW" ]] || fail "relay/references/review.md not found at $REVIEW"

# --- SKILL.md checks ---

# (1) The invocation block lists /relay health
grep -qE '^/relay health' "$SKILL" || fail "SKILL.md invocation block must list /relay health"
pass "SKILL.md lists /relay health in invocation block"

# (2) A ## health section (or equivalent) exists and documents relay-doctor.sh
grep -qiE '## .*(health|relay-doctor)' "$SKILL" || fail "SKILL.md must have a ## health section documenting relay-doctor"
pass "SKILL.md has a health section"

# (3) The health section references relay-doctor.sh
grep -q 'relay-doctor' "$SKILL" || fail "SKILL.md health section must reference relay-doctor.sh"
pass "SKILL.md health section references relay-doctor.sh"

# (4) The health section mentions id:3eb5 (the wiring item's self-reference)
grep -q '3eb5' "$SKILL" || fail "SKILL.md health section must carry id:3eb5 self-reference"
pass "SKILL.md health section carries id:3eb5 self-reference"

# --- review.md checks ---

# (5) review.md contains a step 4b (relay-health check)
grep -qE '## 4b\.' "$REVIEW" || fail "relay/references/review.md must contain a ## 4b. relay-health check sub-step"
pass "review.md contains step 4b (relay-health check)"

# (6) That sub-step calls relay-doctor.sh
grep -q 'relay-doctor' "$REVIEW" || fail "review.md step 4b must call relay-doctor.sh"
pass "review.md step 4b calls relay-doctor.sh"

# (7) The step surfaces findings to REVIEW_ME
grep -q 'REVIEW_ME' "$REVIEW" || fail "review.md step 4b must mention surfacing findings to REVIEW_ME"
pass "review.md step 4b surfaces findings to REVIEW_ME"

# (8) The step is explicitly report-only / never a hard block
grep -qiE 'never a hard block|report.only|never.*block' "$REVIEW" || \
  fail "review.md step 4b must state it is never a hard block (report-only)"
pass "review.md step 4b is explicitly not a hard block"

# (9) id:3eb5 is referenced in review.md (the wiring item's marker)
grep -q '3eb5' "$REVIEW" || fail "review.md step 4b must carry id:3eb5 reference"
pass "review.md step 4b carries id:3eb5 reference"

echo "ALL PASS: id:3eb5 relay-doctor front-door wiring (SKILL.md health mode + review sub-step)"
