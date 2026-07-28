#!/usr/bin/env bash
# roadmap:3906
#
# RED SPEC — authored 2026-07-28 (handoff C3), NOT implemented. EXPECTED-RED while id:3906 is
# unticked.
#
# WHY: id:1432 surfaces `repeatHandbacks` (an item handed back >=2x in one run) as "a bug signal".
# On a loderite run it fired x3 — and reading the three handbacks showed it was not a bug at all:
# three INDEPENDENT executors each surveyed the whole ROADMAP and reached the same correct
# conclusion, that every remaining item was unsafe to land in one session. classify-repo.sh still
# reported 6 actionable; three children looked at those 6 and judged all 6 undoable. That is the
# pool correctly reporting THE CHEAP WORK IS DONE — the most useful thing it can tell an operator —
# and the detector labels it a bug.
#
# WHY IT MATTERS MORE THAN WORDING: the two states are operationally OPPOSITE. "Bug signal" says
# investigate the machinery; "queue exhausted" says the machinery is fine, bring the human or
# re-spec the items. Mislabelling sends the operator to debug a pool that is working perfectly and
# buries the real message under an alarm — and it trains the reader to discount repeatHandbacks,
# so it fails to alarm when something IS broken.
#
# THE DISCRIMINATOR IS MECHANICAL — this need not stay a judgment call. The structured handback
# fields (handback_item, route, gate_reason) already carry everything needed since id:3801:
#   genuine bug  = the SAME item handed back repeatedly for the same/incoherent reason
#   exhaustion   = DIFFERENT items, DIFFERENT children, each citing a legitimate size-out/gate
#                  reason (route in {hard-split, decision-gate, human})
#
# CONTRACT: a pure exported classifier in drain.mjs —
#   classifyRepeatHandbacks(handbacks) -> { kind: 'queue-exhausted'|'bug-signal'|'mixed', ... }
# so both substrates share one implementation (the isDryRound/isBlockedRound precedent, id:4ca8).
#
# NOT in scope: changing WHEN a handback is emitted, or the id:3801 follow-up machinery — this is
# purely how a REPEAT is interpreted and surfaced.
#
# Hermetic: unit-tests a pure function; no repo, network, or fs writes.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRAIN="$ROOT/relay/scripts/drain.mjs"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }
[[ -f "$DRAIN" ]] || { echo "FAIL: drain.mjs not found" >&2; exit 1; }

node --input-type=module -e "
import * as m from '$DRAIN'
if (typeof m.classifyRepeatHandbacks !== 'function') {
  console.error('FAIL: MISSING classifyRepeatHandbacks() in drain.mjs — the id:3906 deliverable')
  process.exit(1)
}
let bad = 0
const t = (name, hbs, wantKind) => {
  const got = m.classifyRepeatHandbacks(hbs)
  const ok = got && got.kind === wantKind
  if (!ok) { bad++; console.error('FAIL: ' + name + ' → ' + JSON.stringify(got) + ' want kind=' + wantKind) }
  else console.log('OK   ' + name + ' → ' + got.kind)
}

// (a) THE OBSERVED CASE — 3 different items, 3 different children, all legitimate routes.
t('a:queue-exhausted', [
  { repo:'loderite', handback_item:'7db1', route:'hard-split',    child:'c1', gate_reason:'too large' },
  { repo:'loderite', handback_item:'9403', route:'hard-split',    child:'c2', gate_reason:'1470-line fn' },
  { repo:'loderite', handback_item:'5d76', route:'decision-gate', child:'c3', gate_reason:'needs a meeting' },
], 'queue-exhausted')

// (b) THE REAL ALARM must still fire — same item, repeatedly. Do NOT weaken this.
t('b:bug-signal', [
  { repo:'loderite', handback_item:'7db1', route:'none', child:'c1', gate_reason:'failed' },
  { repo:'loderite', handback_item:'7db1', route:'none', child:'c1', gate_reason:'failed' },
  { repo:'loderite', handback_item:'7db1', route:'none', child:'c2', gate_reason:'failed' },
], 'bug-signal')

// (c) mixed ⇒ report BOTH, never silently pick one.
t('c:mixed', [
  { repo:'a', handback_item:'1111', route:'hard-split', child:'c1', gate_reason:'big' },
  { repo:'a', handback_item:'2222', route:'none',       child:'c2', gate_reason:'x' },
  { repo:'a', handback_item:'2222', route:'none',       child:'c3', gate_reason:'x' },
], 'mixed')

// (d) an exhaustion verdict must carry what each remaining item NEEDS — that is the useful
// sentence for the operator, and the whole point of distinguishing the two states.
const ex = m.classifyRepeatHandbacks([
  { repo:'r', handback_item:'aaaa', route:'hard-split',    child:'c1', gate_reason:'big' },
  { repo:'r', handback_item:'bbbb', route:'decision-gate', child:'c2', gate_reason:'meeting' },
])
const blob = JSON.stringify(ex)
if (!/hard-split/.test(blob) || !/decision-gate/.test(blob)) {
  bad++; console.error('FAIL: (d) exhaustion verdict does not name what each remaining item needs → ' + blob)
} else console.log('OK   d:names-what-each-item-needs')

if (bad) process.exit(1)
" || { echo "EXPECTED-RED: id:3906 not built yet" >&2; exit 1; }

echo "ALL PASS: repeatHandbacks distinguishes queue-exhaustion from a bug signal (id:3906)"
