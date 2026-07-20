#!/usr/bin/env bash
# roadmap:864e — front-door reversal: `/relay .` MEANS the off-Workflow drain (id:93fe child).
# Owner-ratified 2026-07-19 (meeting 2026-07-19-2035 Amendment, supersedes id:7633 acceptance
# #4): a bare `/relay .` no longer launches the single-repo Workflow pool — it runs the lean
# off-Workflow drain (driver calls classify-repo.sh directly, one agent per unit, no Workflow
# prelude/discovery agents). The front door is SKILL.md prose the apex model follows, so —
# exactly like tests/test_relay_drain_flag.sh (the Phase-1 alias guard, which STAYS) — the
# definition-of-done is documentation the model cannot miss, guarded here against silent drift.
# Hermetic: greps relay/SKILL.md only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/relay/SKILL.md"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]] || fail "relay/SKILL.md not found"

# (1) the off-Workflow drain is documented at all
grep -qi 'off-Workflow' "$SKILL" \
  || fail "SKILL.md never says 'off-Workflow' — the reversed /relay . meaning is undocumented"
pass "off-Workflow drain mentioned"

# (2) the driver script is named (the thing the front door invokes / the apex drives)
grep -q 'drain-driver' "$SKILL" \
  || fail "SKILL.md does not name the drain-driver — front door has nothing to route to"
pass "drain-driver named"

# (3) the reversal is explicit: the id:7633 acceptance-#4 meaning is marked superseded/reversed
grep -qiE '7633[^.]*\b(supersed|revers)' "$SKILL" \
  || grep -qiE '\b(supersed|revers)\w*[^.]*7633' "$SKILL" \
  || fail "SKILL.md does not mark the id:7633 '/relay . = Workflow pool' meaning as superseded/reversed"
pass "id:7633 acceptance #4 marked superseded"

# (4) `/relay .` and the drain are tied together in one breath (same line), so the apex
#     model reading the invocation table resolves a bare `.` to the DRAIN, not the pool
grep -qiE '/relay `?\.`?.*drain|drain.*`/relay \.`' "$SKILL" \
  || fail "no line ties '/relay .' to the drain — the reversed meaning is not discoverable"
pass "/relay . tied to the drain meaning"

echo "all assertions passed"
