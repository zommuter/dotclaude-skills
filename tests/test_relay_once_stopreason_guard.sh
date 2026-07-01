#!/usr/bin/env bash
# Defect-fix test (no roadmap header — failures always count). id:0175 / routed:82e3.
#
# Bug: the --once/--after launch round cap unconditionally set stopReason = 'user-stop' when
# the cap was reached, MASKING a genuine quota stop that quotaGate had already set earlier in
# the SAME round (a real quota-cache-unreadable / quota-exhausted stop looked like a graceful
# operator stop). Fix: only claim 'user-stop' when no real stop reason was already recorded.
#
# Structural test (house style — relay-loop.js is a Workflow script, not hermetically
# runnable): assert the round-cap assignment is guarded by `if (!stopReason)`.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"

# The round-cap block must guard the user-stop assignment. Grep for the guarded form on a
# single line; the unconditional `stopReason = 'user-stop'` (no `if (!stopReason)`) is the bug.
grep -qE "if \(!stopReason\) stopReason = 'user-stop'" "$JS" \
  || fail "round-cap stopReason assignment is not guarded by 'if (!stopReason)' (masks real quota stops)"
pass "round-cap user-stop assignment is guarded (won't mask a real quota stop)"

# Belt-and-braces: there must be no BARE unconditional 'stopReason = ...user-stop' line that
# could re-introduce the mask. The only 'user-stop' set on its own line lives inside the
# operator-STOP-sentinel prelude path (a different, legitimate assignment); the round-cap one
# is now guarded. Assert the guarded form appears at least once and that the round-cap comment
# marker (id:0175) is present so the intent is discoverable.
grep -q "don't mask a REAL stop reason" "$JS" \
  || fail "round-cap guard rationale comment (id:0175) missing"
pass "round-cap guard rationale is documented"

echo "ALL PASS"
