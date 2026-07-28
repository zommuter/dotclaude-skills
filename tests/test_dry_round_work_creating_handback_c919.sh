#!/usr/bin/env bash
# roadmap:c919
#
# id:c919 — a WORK-CREATING handback must not be scored as a dry (no-progress) round.
#
# THE BUG (loderite run relay-20260728-155041-20282, wf_d71b9496-7d8, rounds=11): a
# `route:hard-split` handback with a non-empty `proposed_split` makes handback-followup.py write
# those seams into ROADMAP.md as pickable [ROUTINE] units — the round GREW the backlog. But it
# scored `substantive===0` (unitIsSubstantive is by its own docstring "only ever called for units
# that integrated (contract_met)", drain.mjs) AND `surfaced===0` (surfaced.push fires only on
# DISCOVERY paths — shard failure / queue-sig drop / finished-repo / gated-HARD — never on a
# handback). So `isDryRound` returned true; two such rounds ended the run with
# stopReason:"drained" while 4 seams (id:8f6c/2435/4bbf/0d97) had just been filed, and a fresh
# classify-repo.sh immediately after reported verdict=execute with actionable work.
#
# THE FIX: a `workCreated` term on the round result, excluded from isDryRound.
#
# DELIBERATE NARROWING of routed:b945's proposal, which said `route` in {hard-split,
# decision-gate}: **decision-gate creates NOTHING**. It re-tags the parent into the
# classifier-EXCLUDED "[HARD — decision gate]" lane, which REMOVES work from the actionable pool.
# Counting it as work-creating would keep the loop spinning on a shrinking backlog — the exact
# failure id:2d20/id:d58f exist to prevent. Only hard-split-with-seams counts.
#
# Keyed on the emitted INTENT (route + proposed_split length) rather than the followup's actual
# write count, because durableHandbackFollowup is fire-and-forget and reports nothing back.
# Over-counting is the safe direction and matches relay-loop.js's own stated principle:
# "under-draining merely runs an extra round, over-draining could strand work."
#
# PROVENANCE, stated honestly: this file was written AFTER the fix, not before it, so it is not a
# RED-first spec in the C3 sense. To stop it being a tautology it was VERIFIED RED against the
# unfixed predicate — a scratch copy of drain.mjs with `&& (r.workCreated || 0) === 0` removed
# returns isDryRound === true for case (a), i.e. case (a) FAILS without the fix:
#     node --input-type=module -e "import {isDryRound} from './drain-OLD.mjs';
#       console.log(isDryRound({substantive:0,surfaced:0,workCreated:1}))"   # → true (bug present)
# Re-run that check if this file is ever edited; a test that cannot fail is worse than no test.
#
# Hermetic: unit-tests the PURE predicates in drain.mjs; no repo, network, or fs writes.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRAIN="$ROOT/relay/scripts/drain.mjs"
LOOP="$ROOT/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$DRAIN" ]] || fail "drain.mjs not found at $DRAIN"
[[ -f "$LOOP"  ]] || fail "relay-loop.js not found at $LOOP"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

out="$(node --input-type=module -e "
import { isDryRound, isBlockedRound } from '$DRAIN'
const t = (name, r, wantDry) => {
  const got = isDryRound(r)
  console.log((got === wantDry ? 'OK   ' : 'BAD  ') + name + ' dry=' + got + ' want=' + wantDry)
}
// (a) hard-split handback with seams ⇒ work was created ⇒ NOT dry
t('a:hard-split-with-seams', { actionable: 1, produced: 0, substantive: 0, surfaced: 0, workCreated: 1 }, false)
// (b) hard-split whose seams were all rejected (nothing written) ⇒ still dry
t('b:hard-split-no-seams',   { actionable: 1, produced: 0, substantive: 0, surfaced: 0, workCreated: 0 }, true)
// (c) a genuinely empty round ⇒ still dry (the drain path must still work)
t('c:genuinely-empty',       { actionable: 0, produced: 0, substantive: 0, surfaced: 0 }, true)
// (d) real integrated progress ⇒ not dry (unchanged)
t('d:substantive',           { actionable: 1, produced: 1, substantive: 1, surfaced: 0 }, false)
// (e) blocked round is still BLOCKED, not dry — workCreated must not disturb id:4ca8
const b = { actionable: 0, produced: 0, substantive: 0, surfaced: 2 }
console.log((isBlockedRound(b) && !isDryRound(b) ? 'OK   ' : 'BAD  ') + 'e:blocked-unchanged')
// (f) absent workCreated field (older callers / off-Workflow driver) must behave as before
t('f:field-absent',          { actionable: 0, produced: 0, substantive: 0, surfaced: 0 }, true)
")"
echo "$out"
grep -q 'BAD' <<<"$out" && fail "predicate cases failed:
$out"
pass "(a-f) isDryRound excludes work-creating handbacks; empty/blocked/substantive rounds unchanged"

# ── SYNC INVARIANT (id:4ca8): relay-loop.js carries a BYTE-IDENTICAL inline copy, because the
# Workflow sandbox cannot `import`. A fix landing in only one file silently forks the drain
# contract between the Workflow and off-Workflow substrates — the failure this guard exists for.
norm() { grep -A2 "^\(export \)\?function $1(r) {" "$2" | sed 's/^export //' | tr -d ' \n'; }
for fn in isDryRound isBlockedRound; do
  a="$(norm "$fn" "$DRAIN")"; b="$(norm "$fn" "$LOOP")"
  [[ -n "$a" && -n "$b" ]] || fail "could not extract $fn from both files (drain='$a' loop='$b')"
  [[ "$a" == "$b" ]] \
    || fail "$fn has DIVERGED between drain.mjs and relay-loop.js (id:4ca8 requires byte-identical inline copies):
  drain.mjs : $a
  relay-loop: $b"
  pass "$fn is identical in drain.mjs and relay-loop.js (id:4ca8 sync invariant)"
done

echo "ALL PASS: work-creating handback is not a dry round (id:c919)"
