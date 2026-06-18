#!/usr/bin/env bash
# roadmap:2425 — relay quota stop-reason must attribute the ACTUALLY-crossed bucket, not
# fall through to `quota-exhausted:unknown`. Static-structural, matching
# test_relay_loop_structure.sh / test_relay_quota_stop_reason.sh (id:8c35).
#
# Bug (observed 2026-06-18): on an exit-1 (real exhaustion) stop, relay-loop.js (~line 935)
# picks the culprit bucket with a hardcoded `(v.buckets||[]).find(b => b.pctRemaining <= 10)` —
# the OLD 90%-cap assumption. A stop triggered by a decayed/overridden threshold below 90%
# utilization (e.g. seven_day_sonnet=34% remaining vs a 0.3353 cap) matches NO bucket via the
# <=10 finder → stopReason falls through to `quota-exhausted:unknown`, hiding the real cause.
#
# Fix: the quota agent / quota-stop.sh returns the bucket that crossed its (possibly
# decayed/overridden) threshold plus the threshold value, and relay-loop.js uses THAT for
# stopReason (`quota-exhausted:<bucket>`). The <=10 finder survives only as a last-resort
# fallback.
#
# RED until id:2425 is implemented (checkbox in ROADMAP.md still unticked → EXPECTED-RED).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
pass "relay-loop.js exists"

# (1) The QUOTA_SCHEMA bucket entry must carry the crossed-threshold signal returned by the
#     agent (so relay-loop can name the culprit without the <=10 heuristic). Assert a
#     crossed/threshold field exists on the schema (not just pctRemaining).
grep -qE "crossed|crossedThreshold|stopBucket|exhaustedBucket: \{|thresholdCrossed|threshold:" "$JS" \
  || fail "QUOTA_SCHEMA carries no crossed-bucket/threshold signal — stop-reason still relies on the <=10 heuristic (id:2425)"
pass "schema carries a crossed-bucket / threshold signal from the quota agent"

# (2) stopReason on exit-1 must derive from the agent-returned crossed bucket, NOT solely from
#     the pctRemaining<=10 finder. Assert the <=10 finder is no longer the SOLE source: the
#     stopReason assignment must reference a non-heuristic bucket source in the exit-1 branch.
#     We require an explicit "crossed"-style attribution to feed stopReason.
awk '
  /quota-exhausted:/ { window = 8; seen = 1 }
  window > 0 {
    if (/crossed/ || /stopBucket/ || /v\.bucket\b/ || /v\.crossedBucket/) attributed = 1
    window--
  }
  END { exit (seen && attributed) ? 0 : 1 }
' "$JS" \
  || fail "stopReason still attributed only via the pctRemaining<=10 heuristic — a below-90% decayed/overridden crossing yields :unknown (id:2425)"
pass "stopReason attributes the agent-returned crossed bucket (not just the <=10 heuristic)"

# (3) The <=10 finder is retained only as a documented fallback (defense in depth), not removed
#     outright — a genuine ≥90%-utilization exhaustion with no explicit crossed field still names
#     a bucket. Assert the heuristic still exists AND that an explicit fallback comment/ordering
#     marks it as last-resort.
grep -q "pctRemaining <= 10" "$JS" \
  || fail "the <=10 heuristic was removed entirely — keep it as a last-resort fallback (id:2425)"
grep -qiE "fallback|last.resort|last resort" "$JS" \
  || fail "no fallback marker — the <=10 finder must be demoted to a documented last-resort, not the primary path (id:2425)"
pass "<=10 heuristic retained as a documented last-resort fallback"
