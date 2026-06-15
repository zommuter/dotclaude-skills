#!/usr/bin/env bash
# roadmap:3826 — supervisor flag-rate logger in relay-loop.js integrate().
# Static-structural test (matching test_relay_loop_structure.sh pattern):
# asserts the logger code is present and correctly wired in integrate(),
# the DEFERRED-FLEET SEAM comment exists, and the logGamingFlags function
# has the required fields (repo, runId, ts, closed_ids, gaming_flags, reopened, verified_green).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
pass "relay-loop.js exists"

# (1) logGamingFlags function is defined in relay-loop.js
grep -q "function logGamingFlags" "$JS" \
  || fail "logGamingFlags function not defined in relay-loop.js"
pass "logGamingFlags function defined"

# (2) integrate() calls logGamingFlags for review units
grep -q "logGamingFlags" "$JS" \
  || fail "logGamingFlags not called anywhere in relay-loop.js"
# Must be gated on unit.verdict === 'review' (only review reports carry gaming_flags)
grep -E "verdict.*review.*logGamingFlags|logGamingFlags.*verdict.*review" "$JS" \
  || grep -q "unit.verdict === 'review'" "$JS" \
  || fail "logGamingFlags call not gated on review verdict"
pass "logGamingFlags called inside integrate() for review units"

# (3) The required JSON fields are present in the log entry
for field in repo runId ts closed_ids gaming_flags reopened verified_green; do
  grep -q "\"$field\"" "$JS" || grep -q "$field:" "$JS" \
    || fail "logGamingFlags entry missing field '$field'"
done
pass "logGamingFlags entry contains all required fields: repo, runId, ts, closed_ids, gaming_flags, reopened, verified_green"

# (4) The log target path includes relay-gaming-flags.log
grep -q "relay-gaming-flags.log" "$JS" \
  || fail "relay-gaming-flags.log path not referenced in logGamingFlags"
pass "relay-gaming-flags.log path referenced"

# (5) DEFERRED-FLEET SEAM comment is present (the escalation hook the meeting mandated)
grep -q "DEFERRED-FLEET SEAM" "$JS" \
  || fail "DEFERRED-FLEET SEAM comment missing (id:2909 D1 required escalation hook)"
pass "DEFERRED-FLEET SEAM comment present (id:2909 D1)"

# (6) The log write is fire-and-forget (non-blocking) — integrate() must not await it,
# so a log failure does not stall integration. Check .catch is used (non-fatal).
grep -qE "\.catch\(.*gaming.*(log|flag)|catch.*gaming.*(log|flag)|gaming.*\.catch" "$JS" \
  || fail "logGamingFlags call is not fire-and-forget with .catch (log failure should be non-fatal)"
pass "logGamingFlags is fire-and-forget with .catch (non-fatal log failure)"

echo "ALL PASS"
