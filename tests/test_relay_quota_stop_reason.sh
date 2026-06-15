#!/usr/bin/env bash
# roadmap:8c35 — surface the REAL quota-stop reason (visual feedback). Static-structural,
# matching test_relay_loop_structure.sh: assert relay-loop.js's quotaGate no longer collapses
# every stop into the opaque `quotaStopped` flag, but distinguishes the quota-stop CATEGORY
# (real bucket exhaustion vs stale-cache/refresh-failure vs budget/drain) and surfaces it in
# the log() drain reason, the returned run result (stopReason), and RELAY_STATUS.md.
# RED until id:8c35 is implemented (checkbox in ROADMAP.md still unticked).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
pass "relay-loop.js exists"

# (1) quota-stop.sh's exit-2 (uncertain/stale-cache) vs exit-1 (at/above threshold) distinction
# must be CARRIED through quotaGate, not collapsed. The acceptance: "surface that distinction
# instead of collapsing both to quotaStopped". Today both exit codes set the same flag with no
# category recorded.
grep -qE "exitCode === 2|exitCode == 2|exit.?2" "$JS" \
  || fail "quotaGate does not branch on quota-stop.sh exit 2 (stale-cache) vs exit 1 (exhaustion)"
pass "quotaGate distinguishes exit 2 (stale-cache) from exit 1 (exhaustion)"

# (2) A machine-readable stopReason is captured and returned in the run result, with the
# acceptance's category vocabulary (quota-exhausted:<bucket> | quota-stale-cache | budget |
# drained | max-rounds).
grep -q "stopReason" "$JS" || fail "run result does not carry a stopReason field"
pass "stopReason captured"
grep -q "quota-stale-cache" "$JS" \
  || fail "stopReason vocabulary missing 'quota-stale-cache' (the refresh-failure category)"
grep -qE "quota-exhausted" "$JS" \
  || fail "stopReason vocabulary missing 'quota-exhausted:<bucket>' (real-exhaustion category)"
pass "stopReason vocabulary includes quota-stale-cache and quota-exhausted:<bucket>"

# (3) The drain-reason log() line names the category, not just a generic STOP — an operator
# must read WHY from the log without grepping quota-stop.sh's own stderr.
grep -qE "log\(.*stale.?cache|log\(.*stopReason|log\(.*reason" "$JS" \
  || fail "drain-reason log() does not surface the stop CATEGORY (still opaque)"
pass "drain-reason log() surfaces the stop category"

# (4) RELAY_STATUS.md gains the stop reason (a '## Stop reason' line or an annotation of the
# existing '## Quota remaining' section) so the operator sees it in the status artifact.
grep -qE "Stop reason|Stop Reason|stopReason" "$JS" \
  || fail "RELAY_STATUS rendering does not surface the stop reason"
# Anchor it to the status-writing path: the '## Quota remaining' section already lives in
# writeRelayStatus's section list; the stop-reason surface must sit alongside it.
grep -q "## Quota remaining" "$JS" || fail "lost the '## Quota remaining' status section anchor"
pass "RELAY_STATUS surfaces the stop reason alongside Quota remaining"

echo "ALL PASS"
