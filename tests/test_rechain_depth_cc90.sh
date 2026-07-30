#!/usr/bin/env bash
# roadmap:cc90
# RED SPEC for id:cc90 — L2 bounded execute->execute rechain (K<=3).
#
# Today relay-loop.js only rechains REVIEW units: the re-enqueue at :2443-2452 is gated on
# `unit.verdict === 'review' && … && !unit.rechained`, with the comment "Only reviews chain —
# an execute never re-enqueues". A repo with N open [ROUTINE] items therefore drains at ~1
# per round and pays one STRONG_MODEL review per Sonnet execute.
#
# The Workflow engine cannot be run hermetically (no sandbox, no API), so this is a
# SOURCE-SHAPE spec in the style of tests/test_dispatch_event_sig.sh — it asserts the shape
# of the change, not its runtime behaviour. Stated honestly: it guards that the depth counter,
# the K constant, the execute branch, the lease-hold exception and the three pre-registered
# answers are PRESENT; it cannot prove a live round drains 3 items with 1 review.
#
# TRIANGULATION (id:108e): six independent assertions over four distinct concerns (counter
# shape, bounded K, execute reachability, lease hold, pre-registration) so satisfying it by
# special-casing one grep is harder than doing the work.
#
# RED until relay-loop.js grows the depth counter. roadmap:cc90 unticked => EXPECTED-RED.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

# 1. A depth COUNTER exists on the unit (not the `rechained` boolean).
grep -Eq 'chainDepth' "$JS" \
  || fail "(1) no chainDepth counter in relay-loop.js — the rechain is still boolean-gated (id:cc90)"
pass "(1) unit carries a chainDepth counter"

# 2. The boolean no longer GATES the decision. `unit.rechained` must not appear in the
#    re-enqueue condition any more (it may survive nowhere else either — assert it is gone
#    from the gating expression specifically).
if grep -Eq '!unit\.rechained' "$JS"; then
  fail "(2) the rechain condition still tests !unit.rechained — the boolean still gates chaining (id:cc90)"
fi
pass "(2) !unit.rechained no longer gates the rechain"

# 3. K is a NAMED CONSTANT with value 3, not a magic literal at the comparison site.
kline="$(grep -Eo '(const|let)[[:space:]]+[A-Z_]*(CHAIN|RECHAIN)[A-Z_]*[[:space:]]*=[[:space:]]*3\b' "$JS" || true)"
[[ -n "$kline" ]] \
  || fail "(3) no named constant of the form CONST *CHAIN* = 3 — K must not be a magic literal (id:cc90)"
pass "(3) K is a named constant = 3 ($kline)"

# 4. The execute branch is REACHABLE: the rechain condition must no longer REQUIRE
#    verdict === 'review'. Any surviving `unit.verdict === 'review' &&` inside the rechain
#    gate means an execute can still never re-enqueue.
if grep -Eq "unit\.verdict === 'review' &&" "$JS"; then
  fail "(4) the rechain gate still requires unit.verdict === 'review' — an execute can never re-enqueue (id:cc90)"
fi
pass "(4) the rechain gate does not require verdict === 'review'"

# 5. The lease-hold exception covers the chained case: releaseLease must still be skipped
#    when this round re-chained the SAME repo (releasing in the gap lets another run steal it).
grep -Eq 'if \(!rechainedSameRepo\) await releaseLease' "$JS" \
  || fail "(5) the !rechainedSameRepo lease-hold exception at the per-unit release is gone (id:cc90)"
pass "(5) lease is held across a same-repo rechain"

# 6. All THREE pre-registered answers (amendment A2 / --fabled F1) are recorded at the site.
for token in 'per-chain' 'no unwind' 'greenlight'; do
  grep -qi -- "$token" "$JS" \
    || fail "(6) pre-registration answer missing from relay-loop.js: '$token' (review scope / reject-unwind / greenlight re-entry must all be recorded in-source, id:cc90)"
done
pass "(6) all three pre-registered answers are recorded in-source"

# 7. The engine still parses and still lints clean (relay-loop.js has 17 ```relay-mech fences,
#    some built by concatenation and one from a variable; a template-literal slip is silent).
node --check "$JS" >/dev/null 2>&1 || fail "(7) node --check failed on relay-loop.js after the cc90 edit"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
[[ -f "$LINT" ]] || fail "(7) lint-workflow-templates.mjs not found; cannot verify template safety"
if ! out="$(node "$LINT" "$JS" 2>&1)"; then
  fail "(7) relay-loop.js has a template-literal violation after the cc90 edit:
$out"
fi
pass "(7) relay-loop.js parses and lints clean"

echo "PASS test_rechain_depth_cc90"
