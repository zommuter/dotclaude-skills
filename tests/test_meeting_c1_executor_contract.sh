#!/usr/bin/env bash
# (no roadmap token — feature from meeting design
#  docs/meeting-notes/2026-06-15-0715-meeting-fables-interaction.md D7, tracked in
#  TODO.md id:a21b, not ROADMAP.md; this test always counts.)
#
# D7: in a relay-managed repo, a no-arg /meeting Class 1 dispatch follows the
# /relay executor contract (test integrity, full suite green, RELAY_LOG self-report),
# gated on ROADMAP.md existing; non-relay repos behave as before.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/meeting/SKILL.md"

fail() { echo "FAIL: $1"; exit 1; }

# The C1 dispatch line must reference the executor contract under a relay gate.
c1="$(grep -nE 'Class 1 .*proceed to implementation' "$SKILL" | head -1 | cut -d: -f1)"
[[ -n "$c1" ]] || fail "could not find the Class 1 dispatch line"
seg="$(sed -n "${c1}p" "$SKILL")"

grep -q 'D7' <<<"$seg" || fail "Class 1 line missing D7 marker"
grep -q '/relay executor' <<<"$seg" || fail "Class 1 does not reference the /relay executor contract"
grep -qE 'ROADMAP\.md' <<<"$seg" || fail "D7 not gated on ROADMAP.md (relay-detection)"
grep -qiE 'never weaken|test integrity|weaken, skip, delete' <<<"$seg" || fail "D7 missing test-integrity rule"
grep -q 'RELAY_LOG' <<<"$seg" || fail "D7 missing RELAY_LOG self-report"
grep -qiE 'full suite|make test' <<<"$seg" || fail "D7 missing full-suite-green done condition"
grep -qiE 'non-relay repos|no ROADMAP\.md' <<<"$seg" || fail "D7 must preserve non-relay behavior"

echo ok
