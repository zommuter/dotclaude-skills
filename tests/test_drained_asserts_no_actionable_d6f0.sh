#!/usr/bin/env bash
# roadmap:d6f0
#
# RED SPEC — authored 2026-07-28 by handoff (C3), NOT implemented. This test is EXPECTED-RED
# while ROADMAP id:d6f0 is unticked; that is the point. It is the executable specification of
# the fix, written before the code, so the implementer has an unambiguous target and cannot
# declare done without satisfying it.
#
# WHY (the general invariant behind id:c919's specific bug): `stopReason:"drained"` is a CLAIM
# that no dispatchable work remains. Today nothing checks it. The loop infers "drained" from
# 2 consecutive rounds it SCORED as dry — so any round-outcome the loop mis-scores silently
# becomes a false "drained". That has now happened three times, each a different unobserved
# transition:
#   id:c919 — a work-creating hard-split handback scored as no-progress  (FIXED, the specific case)
#   id:61fa — a null child report never stamps noWorkNegCache
#   id:3906 — repeatHandbacks reads queue-exhaustion as a bug signal
# Patching each instance leaves the NEXT one undetected. This spec closes the class: make the
# claim self-verifying, so "drained" can never mean "stuck" regardless of which transition was
# missed. Evidence it is needed: loderite run relay-20260728-155041-20282 returned
# stopReason:"drained" and a fresh classify-repo.sh IMMEDIATELY after reported verdict=execute
# with actionable work.
#
# CONTRACT the implementer must satisfy:
#   Before returning stopReason "drained", the loop re-derives actionability for the in-scope
#   repos (classify-repo.sh is the single source — do NOT re-implement the predicate) and:
#     - no actionable work  ⇒ return "drained" as today;
#     - actionable work     ⇒ MUST NOT return "drained". Either continue, or return a distinct,
#                             loud reason (suggested: "stuck-despite-actionable") naming the
#                             repos still actionable, so an operator sees a bug rather than a
#                             clean finish.
#   The assertion must be FAIL-CLOSED on its own failure: if the re-derivation cannot run
#   (script missing, non-zero exit, unparseable output), that is NOT evidence of drained-ness —
#   do not silently claim "drained".
#
# NOT in scope: changing when rounds are scored dry (that is id:c919, landed), the drain
# K=2 threshold, or the blocked-pending-human path (id:4ca8).
#
# Hermetic: stub classify-repo.sh in a temp dir; no repo, network, or real ~/.claude access.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRAIN="$ROOT/relay/scripts/drain.mjs"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }
[[ -f "$DRAIN" ]] || fail "drain.mjs not found at $DRAIN"

# The deliverable: a PURE, unit-testable decision function in drain.mjs so both substrates
# (Workflow relay-loop.js inline copy + off-Workflow driver) share one implementation, matching
# the isDryRound/isBlockedRound precedent (id:4ca8).
#
#   finalDrainVerdict({ dryStreak, actionableAfter, probeOk })
#     → { drained: bool, stopReason: string }
#
#   actionableAfter : number  — actionable units from the post-hoc re-derivation
#   probeOk         : bool    — did the re-derivation actually run and parse?
node --input-type=module -e "
import * as m from '$DRAIN'
if (typeof m.finalDrainVerdict !== 'function') {
  console.error('MISSING: drain.mjs does not export finalDrainVerdict() — the id:d6f0 deliverable')
  process.exit(3)
}
const cases = [
  // [name, input, wantDrained, wantReasonSubstring]
  ['clean drain',        { dryStreak: 2, actionableAfter: 0, probeOk: true  }, true,  'drained'],
  ['stuck not drained',  { dryStreak: 2, actionableAfter: 3, probeOk: true  }, false, 'stuck'],
  ['probe failed',       { dryStreak: 2, actionableAfter: 0, probeOk: false }, false, ''],
  ['streak not reached', { dryStreak: 1, actionableAfter: 0, probeOk: true  }, false, ''],
]
let bad = 0
for (const [name, input, wantDrained, wantSub] of cases) {
  const got = m.finalDrainVerdict(input)
  const okD = !!(got && got.drained) === wantDrained
  const okR = !wantSub || String((got && got.stopReason) || '').includes(wantSub)
  if (!okD || !okR) { bad++; console.error('BAD  ' + name + ' → ' + JSON.stringify(got)) }
  else console.log('OK   ' + name + ' → ' + JSON.stringify(got))
}
if (bad) process.exit(1)
" || fail "finalDrainVerdict() is missing or does not satisfy the contract (EXPECTED-RED until id:d6f0 is built)"

pass "finalDrainVerdict(): clean drain returns drained; actionable-after must NOT return drained; a failed probe is fail-closed; the K-streak still gates"
echo "ALL PASS: drained asserts no actionable work (id:d6f0)"
