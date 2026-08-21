#!/usr/bin/env bash
# roadmap:bfbf (routed:9371) — a handback claiming "zero dispatchable" must ENUMERATE the ids it
# considered, and that enumeration must be cross-checked against the RESOLVED pool set. The
# discriminator is SET DISJOINTNESS, not emptiness.
#
# WHY DISJOINTNESS AND NOT EMPTINESS (this is the load-bearing correction — ground truth from
# loderite run relay-20260814-133435-24323, confirmed against the run record):
#   - gather computed open_hard_pool = 5 ("Open [HARD -- pool] items: 5 -- pool-lane hard work
#     pending").
#   - the child handed back "There is NO pool-dispatchable [HARD — pool] item in loderite this
#     turn."
#   - its considered-id list was NOT EMPTY — it had FIFTEEN entries: containers 16b2, ca44,
#     d215, 5d76, 5d00, 9403, 23aa, 40ad and gated 3d11, 8452, 9a6b, c8ad, c2f3, 1a09, 55c7.
#     Every one correctly gated. NONE of them were the five items it should have looked at.
# So an empty-list check is a detector that would have stayed SILENT through the exact failure
# it was written for. Zero overlap between what the counter counted and what the child actually
# looked at is the signal; the empty list is a SUBSUMED instance (∅ ∩ anything = ∅).
#
# Accepting such a claim is actively harmful: it stamps the id:1432 no-work negative cache,
# which suppresses re-dispatch until work_sig changes — silently parking a repo that has work.
# Recurrence is three-for-three on 2026-08-14 (run relay-20260814-151838-12590 produced the
# identical refusal against 7 available items).
#
# ACCEPTANCE IMPLEMENTED: open_hard_pool > 0 AND (open_hard_pool_ids ∩ considered_ids) == ∅
# produces a LOUD alarm and is NOT recorded as a clean drain; a list that OVERLAPS the pool set
# (the child demonstrably reached the queue) is accepted.
#
# Logic lives in the pure helper relay/scripts/handback-guard.mjs (node-unit-testable);
# relay-loop.js carries a byte-equivalent inline copy (structural asserts pin the wiring).
# Hermetic: node-only, no git, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/handback-guard.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: handback-guard.mjs missing"; exit 1; }
[[ -f "$JS" ]]     || { echo "FAIL: relay-loop.js missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/drive.mjs" <<NODE
import * as G from 'file://$HELPER'
const out = []
if (typeof G.noWorkEnumerationAlarm !== 'function') {
  out.push('MISSING_EXPORT')
  console.log(out.join('\n'))
  process.exit(0)
}
const alarm = G.noWorkEnumerationAlarm

// The REAL loderite pool set the counter counted — the five bare-[HARD] items the child never
// looked at (ROADMAP.md@e68c143).
const POOL = ['c040', 'a728', '0873', '3890', 'ef07']
// The REAL considered list the child returned: 8 containers + 7 gated items, all correctly
// gated, none of them in POOL.
const CONSIDERED_REAL = ['16b2','ca44','d215','5d76','5d00','9403','23aa','40ad',
                         '3d11','8452','9a6b','c8ad','c2f3','1a09','55c7']

// (1) THE REAL BUG CASE — the one an emptiness check would MISS.
{
  const a = alarm({ repo: 'loderite', verdict: 'hard', openHardPool: 5, poolIds: POOL,
                    route: 'none', consideredIds: CONSIDERED_REAL })
  out.push('disjoint_alarm=' + (a ? '1' : '0'))
  if (a) {
    out.push('disjoint_clean_drain=' + (a.cleanDrain ? '1' : '0'))
    out.push('disjoint_overlap=' + a.overlap)
    out.push('disjoint_reason_names_considered=' + (String(a.reason).includes('15 considered') ? '1' : '0'))
    out.push('disjoint_reason_has_id=' + (String(a.reason).includes('id:bfbf') ? '1' : '0'))
  }
}

// (2) EMPTY considered list — a SUBSUMED instance of disjointness.
{
  const a = alarm({ repo: 'loderite', verdict: 'hard', openHardPool: 5, poolIds: POOL,
                    consideredIds: [], route: 'none' })
  out.push('empty_alarm=' + (a ? '1' : '0'))
}

// (3) Field entirely ABSENT (an older child that never learned to enumerate) — absence must be
// treated exactly like empty, never as "trust it".
{
  const a = alarm({ repo: 'loderite', verdict: 'hard', openHardPool: 5, poolIds: POOL, route: 'none' })
  out.push('absent_alarm=' + (a ? '1' : '0'))
}

// (4) THE ACCEPTED CASE: the sets OVERLAP — the child demonstrably looked at the real queue and
// rejected it on the merits. Accepted, no alarm, even though nothing was dispatched.
{
  const a = alarm({ repo: 'loderite', verdict: 'hard', openHardPool: 5, poolIds: POOL, route: 'none',
                    consideredIds: ['c040', 'a728', '3890', 'ef07', '0873'] })
  out.push('overlap_alarm=' + (a ? '1' : '0'))
}

// (5) PARTIAL overlap — one real pool item plus noise. The child reached the queue, so accepted:
// the detector's job is "looked in the WRONG PLACE entirely", not "did not look hard enough".
{
  const a = alarm({ repo: 'loderite', verdict: 'hard', openHardPool: 5, poolIds: POOL, route: 'none',
                    consideredIds: ['16b2', 'ca44', 'ef07'] })
  out.push('partial_overlap_alarm=' + (a ? '1' : '0'))
}

// (6) Genuinely empty backlog: open_hard_pool == 0 → no alarm (nothing to enumerate).
{
  const a = alarm({ repo: 'zelegator', verdict: 'hard', openHardPool: 0, poolIds: [],
                    consideredIds: [], route: 'none' })
  out.push('empty_backlog_alarm=' + (a ? '1' : '0'))
}

// (7) THE THIRD STATE — openHardPool > 0 but the pool LIST is unusable, so disjointness cannot
// be decided. Must be NEITHER a silent accept NOR a disjointness alarm: a distinctly-labelled
// 'enumeration-unevaluable', not a clean drain, overlap NOT faked as 0, and its message must
// name WHY it was unevaluable. Two upstream faults, distinguishable:
//   (7a) poolIds ABSENT/empty — an older queue entry or a producer that never emitted it.
{
  const a = alarm({ repo: 'loderite', verdict: 'hard', openHardPool: 5, poolIds: [], route: 'none',
                    consideredIds: ['16b2', 'ca44'] })
  out.push('unevaluable_absent_returned=' + (a ? '1' : '0'))
  if (a) {
    out.push('unevaluable_absent_kind=' + a.kind)
    out.push('unevaluable_absent_clean_drain=' + (a.cleanDrain ? '1' : '0'))
    out.push('unevaluable_absent_overlap_null=' + (a.overlap === null ? '1' : '0'))
    out.push('unevaluable_absent_says_why=' + (String(a.reason).includes('ABSENT or empty') ? '1' : '0'))
  }
}
//   (7b) poolIds PRESENT but every entry unnameable (routed:3ad9 multi-marker ambiguity — the
//        counter counted work it could not NAME). A different upstream fault, different wording.
{
  const a = alarm({ repo: 'loderite', verdict: 'hard', openHardPool: 2, poolIds: ['', ''], route: 'none',
                    consideredIds: ['16b2', 'ca44'] })
  out.push('unevaluable_unnameable_returned=' + (a ? '1' : '0'))
  if (a) {
    out.push('unevaluable_unnameable_kind=' + a.kind)
    out.push('unevaluable_unnameable_says_why=' + (String(a.reason).includes('PRESENT') ? '1' : '0'))
    out.push('unevaluable_unnameable_distinct=' + (String(a.reason).includes('ABSENT or empty') ? '0' : '1'))
  }
}
//   (7c) But an unusable pool list with NO enumeration at all is still a plain ALARM — the child
//        owed evidence and returned none, which is decidable without the pool set.
{
  const a = alarm({ repo: 'loderite', verdict: 'hard', openHardPool: 5, poolIds: [], route: 'none',
                    consideredIds: [] })
  out.push('unusable_and_no_enum_kind=' + (a ? a.kind : 'NONE'))
}

// (8) An ITEM-level handback (route=hard-split with a handback_item) is NOT a zero-dispatchable
// claim — id:3801 gates it durably. Never alarmed on for missing enumeration.
{
  const a = alarm({ repo: 'loderite', verdict: 'hard', openHardPool: 5, poolIds: POOL,
                    consideredIds: [], route: 'hard-split', handbackItem: 'c040' })
  out.push('item_level_alarm=' + (a ? '1' : '0'))
}

// (9) Case-insensitive / whitespace-tolerant matching: an uppercase-hex or padded id must still
// count as overlap, never as a wrong-place claim.
{
  const a = alarm({ repo: 'loderite', verdict: 'hard', openHardPool: 5, poolIds: POOL, route: 'none',
                    consideredIds: [' C040 '] })
  out.push('case_overlap_alarm=' + (a ? '1' : '0'))
}

console.log(out.join('\n'))
NODE

res="$(node "$TMP/drive.mjs")"
echo "--- helper output ---"; echo "$res"; echo "---------------------"
get() { printf '%s\n' "$res" | sed -n "s/^$1=//p"; }

if grep -q '^MISSING_EXPORT$' < <(printf '%s\n' "$res") ; then
  bad "handback-guard.mjs exports no noWorkEnumerationAlarm — the detector does not exist"
else
  [[ "$(get disjoint_alarm)" == "1" ]] \
    && ok "REAL incident: 15 considered ids, ZERO overlap with the 5-item pool set → LOUD alarm" \
    || bad "the real loderite handback (15 considered ids, none in the pool set) produced NO alarm — an emptiness-only check"
  [[ "$(get disjoint_clean_drain)" == "0" ]] \
    && ok "alarmed handback is NOT recorded as a clean drain" \
    || bad "alarmed handback was still marked cleanDrain — it would stamp the no-work negative cache"
  [[ "$(get disjoint_overlap)" == "0" ]] \
    && ok "alarm reports overlap=0" \
    || bad "alarm reported overlap='$(get disjoint_overlap)', expected 0"
  [[ "$(get disjoint_reason_names_considered)" == "1" ]] \
    && ok "alarm reason names how many ids the child considered" \
    || bad "alarm reason does not name the considered count (a loud alarm must say what it saw)"
  [[ "$(get disjoint_reason_has_id)" == "1" ]] \
    && ok "alarm reason carries id:bfbf provenance" \
    || bad "alarm reason lacks the id:bfbf token"
  [[ "$(get empty_alarm)" == "1" ]] \
    && ok "empty considered list still alarms (subsumed instance of disjointness)" \
    || bad "empty considered list produced no alarm"
  [[ "$(get absent_alarm)" == "1" ]] \
    && ok "an ABSENT considered-id list alarms exactly like an empty one" \
    || bad "an absent considered-id list was trusted — silence must never read as 'considered everything'"
  [[ "$(get overlap_alarm)" == "0" ]] \
    && ok "considered list OVERLAPPING the pool set IS accepted (the child reached the queue)" \
    || bad "a genuine, on-queue 'nothing dispatchable' was alarmed — false positive"
  [[ "$(get partial_overlap_alarm)" == "0" ]] \
    && ok "partial overlap is accepted (detector targets wrong-place, not not-hard-enough)" \
    || bad "partial overlap alarmed — false positive"
  [[ "$(get empty_backlog_alarm)" == "0" ]] \
    && ok "open_hard_pool=0 → no alarm (nothing to enumerate)" \
    || bad "alarmed on a genuinely empty backlog — false positive"
  [[ "$(get unevaluable_absent_returned)" == "1" ]] \
    && ok "unusable pool list is NOT silently accepted — the detector still says something" \
    || bad "unusable pool list returned null (silent accept) — the detector said nothing, a silent fallback"
  [[ "$(get unevaluable_absent_kind)" == "enumeration-unevaluable" ]] \
    && ok "third state is distinctly labelled 'enumeration-unevaluable'" \
    || bad "kind='$(get unevaluable_absent_kind)', expected enumeration-unevaluable (must not be reported as a disjointness alarm)"
  [[ "$(get unevaluable_absent_clean_drain)" == "0" ]] \
    && ok "unevaluable state is NOT recorded as a clean drain" \
    || bad "unevaluable state was marked cleanDrain — it would stamp the no-work negative cache"
  [[ "$(get unevaluable_absent_overlap_null)" == "1" ]] \
    && ok "overlap is null, not a faked 0 — disjointness was never computed" \
    || bad "unevaluable state reported a numeric overlap, faking a disjointness finding"
  [[ "$(get unevaluable_absent_says_why)" == "1" ]] \
    && ok "unevaluable message names the ABSENT-poolIds fault" \
    || bad "unevaluable message does not say WHY it was unevaluable"
  [[ "$(get unevaluable_unnameable_kind)" == "enumeration-unevaluable" ]] \
    && ok "present-but-unnameable poolIds also yields the third state" \
    || bad "present-but-unnameable poolIds gave kind='$(get unevaluable_unnameable_kind)'"
  [[ "$(get unevaluable_unnameable_says_why)" == "1" && "$(get unevaluable_unnameable_distinct)" == "1" ]] \
    && ok "the two upstream faults (absent vs present-but-unnameable) are distinguishable in the message" \
    || bad "the two unevaluable causes produce indistinguishable wording"
  [[ "$(get unusable_and_no_enum_kind)" == "unevidenced-no-enumeration" ]] \
    && ok "unusable pool list + NO enumeration is still a plain ALARM (decidable without the pool set)" \
    || bad "kind='$(get unusable_and_no_enum_kind)', expected unevidenced-no-enumeration"
  [[ "$(get item_level_alarm)" == "0" ]] \
    && ok "an item-level (route=hard-split) handback is not a zero-dispatchable claim → no alarm" \
    || bad "alarmed on an item-level handback; id:3801 already gates those durably"
  [[ "$(get case_overlap_alarm)" == "0" ]] \
    && ok "overlap matching is case/whitespace tolerant" \
    || bad "an uppercase/padded id failed to match the pool set — spurious wrong-place verdict"
fi

# --- structural wiring: relay-loop.js must carry the inline copy AND use it ---------
grep -q 'function noWorkEnumerationAlarm' "$JS" \
  && ok "relay-loop.js carries the inline noWorkEnumerationAlarm copy" \
  || bad "relay-loop.js has no inline noWorkEnumerationAlarm (the Workflow sandbox cannot import)"
grep -q 'noWorkEnumerationAlarm(' "$JS" \
  && ok "relay-loop.js CALLS noWorkEnumerationAlarm at the handback site" \
  || bad "relay-loop.js never calls noWorkEnumerationAlarm — built but unwired"
# The pool set must actually be HANDED to the detector — the disjointness check is inert without it.
grep -q 'poolIds: unit.open_hard_pool_ids' "$JS" \
  && ok "the resolved pool set (unit.open_hard_pool_ids) is passed to the detector" \
  || bad "noWorkEnumerationAlarm is called WITHOUT poolIds — the disjointness check can never fire"
# The child must be TOLD to return the enumeration, and the schema must accept it.
grep -q 'considered_ids' "$JS" \
  && ok "relay-loop.js report schema / brief carries considered_ids" \
  || bad "relay-loop.js never mentions considered_ids — the child is never asked to enumerate"

# --- inline copy must stay byte-equivalent with the .mjs source ---------------------
if python3 - "$HELPER" "$JS" <<'PY'
import sys
mjs = open(sys.argv[1]).read(); js = open(sys.argv[2]).read()
i = mjs.index('export function noWorkEnumerationAlarm'); j = mjs.index('\n}\n', i)
a = mjs[i:j+2].replace('export function', 'function', 1)
i2 = js.index('function noWorkEnumerationAlarm'); j2 = js.index('\n}\n', i2)
sys.exit(0 if a == js[i2:j2+2] else 1)
PY
then ok "inline copy is byte-equivalent to handback-guard.mjs"
else bad "inline copy has DRIFTED from handback-guard.mjs (the tested source is not the running code)"
fi

echo "---"
echo "test_handback_considered_ids: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
