#!/usr/bin/env bash
# Defect-fix test (no roadmap item -- deliberately no `# roadmap:` header, so its failures
# always count).
#
# id:ffc4 -- an execute unit whose ENTIRE permitted set has been subtracted away must be
# handed back BEFORE the ledger slice and the id:4f9b prompt-size gate, with a message that
# names the suppressed ids and the reconcile remedy.
#
# THE DEFECT, measured in pool run relay-20260910-234645-16942 (two distinct symptoms, one
# mechanism -- "empty after suppression"):
#
#   (i)  code.lawless: actionable_routine_ids=['a736'] minus suppressed {a736,f272} leaves
#        namedItemsFor(unit) === []. The unit dispatched anyway with a closed permitted set of
#        NOTHING and the child correctly refused: 2 of that run's 7 id:c076 handbacks.
#
#   (ii) dotclaude-skills: b437 was this repo's only actionable [ROUTINE] id and it was
#        orphan-suppressed. With no named item, dispatchItemFor() returns "", sliceLedgerForUnit
#        takes its no-item branch and writes NO slice, and the size gate therefore fell back to
#        sizing the WHOLE ledgers -- refusing five execute units at ~650,104 tok against a
#        100,000 budget and sending the operator to ledger-slice.sh and the archivers. The
#        refusal was real; the MESSAGE was wrong. A normal b437 slice measures ~5.4 KB.
#
# CONTRACT
#   1. verdict=execute + actionable_routine_open>0 + namedItemsFor()==[] ⇒ NO dispatch, exactly
#      one handback, on BOTH surfaces (accumulator + event, the id:4a46 bidirectional invariant).
#   2. The reason NAMES the subtracted ids and the reconcile remedy, and must NOT send the
#      operator after ledger size. (ii) is the whole reason this is asserted on the text.
#   3. It runs BEFORE sliceLedgerForUnit and the size gate, so the misleading byte-count
#      refusal is unreachable in this state. Asserted by observing that the slicer is never
#      called, not by reading the source order.
#   4. FAIL-CLOSED only on a COMPLETE observation. A unit that never carried
#      actionable_routine_open (an injected unit, an older queue entry, the rechain literal at
#      relay-loop.js:4744 which builds a 7-field unit by hand) falls through UNCHANGED -- the
#      guard must not turn a missing field into a refusal.
#
# METHOD -- behavioural, over the REAL dispatch-path source, same technique as
# tests/test_dd7d_item_scoped_skip_a360.sh (id:2ec4: relay-loop.js is a Workflow module that
# cannot be imported hermetically). The region between the dd7d guard marker and the id:34b7
# provisioning marker is extracted verbatim and evaluated against stubbed I/O.
#
# Hermetic: node + mktemp -d only. No git, no network, no ~/.claude or ~/.cache/relay writes.
#
# NEGATIVE CASE: neuter the guard's own trigger so the unit falls through to the slice/size
# path exactly as it did in the incident. Cases (D), (E) and (F) are fall-through cases and
# stay green under it, and so do (E2) and (F).
#
# The node driver is a NON-EXITING ACCUMULATOR: nine FAIL lines fire under this mutation, from
# (A), (B) and (C), in source order. Per the runner's rule the declaration below must name the
# LAST of them, which is case (C) -- the stranded-subtraction route into the identical empty
# permitted set. Measured, not assumed. If a later edit reorders or adds a case, this stops
# matching and `make verify-negatives` reports WRONG REASON loudly rather than silently
# degrading to an any-of match; re-measure and re-declare rather than loosening the string.
# fails-against-mutation: sed -i 's/^    namedItemsFor(unit).length === 0$/    false/' relay/scripts/relay-loop.js
# fails-against-assertion: (C) STRANDED-SUBTRACTED EMPTY SET NOT HANDED BACK

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-workflow-check.sh"  # id:62c9 workflow_node_check
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOOP="$ROOT/relay/scripts/relay-loop.js"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home"; mkdir -p "$HOME"

[[ -f "$LOOP" ]] || { echo "FAIL: relay-loop.js not found at $LOOP" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not available (this spec needs it)" >&2; exit 1; }

# --- extract the real helpers the dispatch path uses ----------------------------------------
{
  awk '/^const namedItemsFor = /,/^\}/'          "$LOOP"
  awk "/^const dispatchItemFor = /{print}"       "$LOOP"
  awk "/^const strandedIdsOf = /{print}"         "$LOOP"
  awk '/^async function strandedDispatchGate\(/,/^\}/' "$LOOP"
  awk '/^const strandedDispatchReason = /,/^\}/' "$LOOP"
} > "$tmpdir/helpers.js"

# --- extract the dispatch-path REGION under test (dd7d guard ... id:34b7 provisioning) ------
awk '/pre-dispatch stranded-branch guard \(b\)/{f=1} /id:34b7 . the parent creates/{f=0} f' \
  "$LOOP" > "$tmpdir/region.js"
[[ -s "$tmpdir/region.js" ]] \
  || note "could not extract the dispatch-path region from relay-loop.js (markers moved?)"

# CALIBRATION on the extracted text, BEFORE anything is asserted about behaviour. An extraction
# that silently missed the guard would make every case below a fall-through pass, i.e. vacuous.
grep -q 'id:ffc4' "$tmpdir/region.js" \
  || note "CALIBRATION: the extracted region does not contain the id:ffc4 guard -- every behavioural case below would be vacuous"
grep -q 'sliceLedgerForUnit(unit)' "$tmpdir/region.js" \
  || note "CALIBRATION: the extracted region does not reach sliceLedgerForUnit -- contract 3 (guard runs BEFORE the slice) is untestable here"

cat > "$tmpdir/drive.js" <<'JS'
let state, events, logs, STRANDED, sliceCalls, sizeGateCalls
const log = (m) => logs.push(String(m))
const pushEvent = (kind, payload) => events.push(Object.assign({ kind }, payload))
const scheduleStatusWrite = () => {}
const sliceLedgerForUnit = async () => { sliceCalls++; return null }
// Stands in for the id:4f9b size gate. In the real incident this is what produced the
// "~650,104 tok" refusal; here it just records that control reached it.
const oversizeDispatchReason = () => { sizeGateCalls++; return '' }
const unitPrompt = () => ''
const STRONG_MODEL = 'claude-opus-5'
const dispatchBudgetForModel = () => 100000
const strandedBranchesFor = async (unit) => {
  const item = dispatchItemFor(unit)
  if (!item) return []
  return STRANDED[item] || []
}

async function dispatchPath(unit) {
  REGION_PLACEHOLDER
  return { dispatched: true, item: dispatchItemFor(unit) }
}

const reset = () => { state = { handbacks: [], inFlight: [] }; events = []; logs = []; STRANDED = {}; sliceCalls = 0; sizeGateCalls = 0 }
const bad = []

// --- (A) the code.lawless shape: one actionable id, both it and a sibling suppressed --------
{
  reset()
  const unit = {
    repo: 'code.lawless', verdict: 'execute', path: '/tmp/code.lawless',
    actionable_routine_ids: ['a736'],
    actionable_routine_open: 1,
    suppressed_item_ids: ['a736', 'f272'],
  }
  if (namedItemsFor(unit).length !== 0) {
    bad.push('(A) FIXTURE CALIBRATION: namedItemsFor must be EMPTY on this unit, got '
      + JSON.stringify(namedItemsFor(unit)) + ' -- the fixture no longer models the defect')
  }
  const r = await dispatchPath(unit)
  if (r && r.dispatched) {
    bad.push('(A) EMPTY PERMITTED SET DISPATCHED: every actionable id was subtracted before '
      + 'dispatch, so the child is handed a closed permitted set of nothing and can only refuse '
      + '(id:c076). The unit must be handed back at the dispatch site instead. sliceCalls='
      + sliceCalls + ' sizeGateCalls=' + sizeGateCalls)
  }
  if (state.handbacks.length !== 1) {
    bad.push('(A/1) expected exactly one handback, got ' + state.handbacks.length + ': '
      + JSON.stringify(state.handbacks.map(h => h.reason)))
  } else {
    const reason = String(state.handbacks[0].reason)
    if (!reason.includes('id:a736') || !reason.includes('id:f272')) {
      bad.push('(A/2) the handback reason must NAME the subtracted ids (a736, f272): ' + reason)
    }
    if (!/reconcile/i.test(reason)) {
      bad.push('(A/2) the handback reason must name the RECONCILE remedy: ' + reason)
    }
    // The dotclaude-skills half of this defect was a confidently-stated WRONG LEVER, so the
    // message must actively rule ledger size out. Note the check is for an explicit DENIAL,
    // not for the absence of the word: naming an archiver in order to say "do not run it" is
    // the correct thing to do, and a bare substring ban would forbid exactly that.
    if (!/not a ledger-size problem/i.test(reason)) {
      bad.push('(A/2) the handback reason must explicitly rule ledger size out. The five '
        + 'dotclaude-skills refusals in this run blamed ~650,104 tok and named ledger-slice.sh '
        + 'and the archivers; none of those was the lever: ' + reason)
    }
    if (/tok against|too large|exceeds .*budget/i.test(reason)) {
      bad.push('(A/2) the handback reason still reads as a SIZE refusal: ' + reason)
    }
  }
  if (!events.some(e => e.kind === 'handback')) {
    bad.push('(A/1) no handback EVENT emitted (id:4a46 bidirectional surface)')
  }
  // contract 3 -- observed, not read off the source order
  if (sliceCalls !== 0) {
    bad.push('(A/3) sliceLedgerForUnit ran before the guard fired. With no named item it writes '
      + 'no slice, so the size gate then sizes the WHOLE ledgers and refuses with a byte count '
      + '-- the ~650,104 tok misreport. The guard must run FIRST.')
  }
  if (sizeGateCalls !== 0) {
    bad.push('(A/3) the id:4f9b size gate was reached on an empty-permitted-set unit')
  }
}

// --- (B) the dotclaude-skills shape: a single suppressed id, no stranded set -----------------
{
  reset()
  const unit = {
    repo: 'dotclaude-skills', verdict: 'execute', path: '/tmp/dotclaude-skills',
    actionable_routine_ids: ['b437'],
    actionable_routine_open: 1,
    suppressed_item_ids: ['b437'],
    roadmap_bytes: 1500000, todo_bytes: 838549,
  }
  const r = await dispatchPath(unit)
  if (r && r.dispatched) bad.push('(B) the dotclaude-skills shape still dispatched')
  if (sizeGateCalls !== 0) {
    bad.push('(B) the size gate was reached even with huge *_bytes present -- this is exactly '
      + 'the run where five execute units were refused on ledger size for a suppression problem')
  }
  if (state.handbacks.length === 1 && !/b437/.test(String(state.handbacks[0].reason))) {
    bad.push('(B) the handback does not name id:b437: ' + state.handbacks[0].reason)
  }
}

// --- (C) STRANDED subtraction reaches the same state (namedItemsFor subtracts both sets) ----
{
  reset()
  STRANDED = {}
  const unit = {
    repo: 'r_stranded', verdict: 'execute', path: '/tmp/r_stranded',
    actionable_routine_ids: ['c111'],
    actionable_routine_open: 1,
    stranded_item_ids: ['c111'],
  }
  const r = await dispatchPath(unit)
  if (r && r.dispatched) bad.push('(C) an all-stranded-subtracted unit dispatched with an empty permitted set')
  if (state.handbacks.length !== 1) {
    bad.push('(C) STRANDED-SUBTRACTED EMPTY SET NOT HANDED BACK: namedItemsFor subtracts '
      + 'stranded_item_ids as well as suppressed_item_ids, so a unit whose every actionable id '
      + 'is stranded reaches dispatch with the same closed permitted set of nothing. Expected '
      + 'exactly one handback, got ' + state.handbacks.length)
  } else if (!/c111/.test(String(state.handbacks[0].reason))) {
    bad.push('(C) the handback does not name the stranded id:c111: ' + state.handbacks[0].reason)
  }
}

// --- (D) FALL-THROUGH: a normal execute unit with a free item is untouched ------------------
{
  reset()
  const unit = {
    repo: 'r_ok', verdict: 'execute', path: '/tmp/r_ok',
    actionable_routine_ids: ['a736', 'b111'],
    actionable_routine_open: 2,
    suppressed_item_ids: ['a736'],
  }
  const r = await dispatchPath(unit)
  if (!r || !r.dispatched) {
    bad.push('(D) a unit with a FREE actionable item (b111) was blocked by the ffc4 guard -- '
      + 'over-refusal: ' + JSON.stringify(state.handbacks.map(h => h.reason)))
  } else if (r.item !== 'b111') {
    bad.push('(D) expected dispatch of the free id:b111, got id:' + r.item)
  }
  if (state.handbacks.length) bad.push('(D) handback filed on a dispatchable unit: ' + JSON.stringify(state.handbacks))
  if (sliceCalls !== 1) bad.push('(D) the normal path must still reach sliceLedgerForUnit exactly once, got ' + sliceCalls)
}

// --- (E) FALL-THROUGH (contract 4): a hand-built unit carrying NO id fields ------------------
// The rechain path at relay-loop.js:4744 pushes a hand-built 7-field unit literal carrying no
// actionable_routine_ids, no sig and no *_bytes; injected units and older discovery-queue
// entries are the same shape. A missing field is a MISSING OBSERVATION, never a refusal.
{
  reset()
  const unit = { repo: 'r_rechain', verdict: 'execute', path: '/tmp/r_rechain', reason: 'rechain' }
  const r = await dispatchPath(unit)
  if (!r || !r.dispatched) {
    bad.push('(E) a unit carrying NO id fields was refused. The ffc4 guard is fail-closed only '
      + 'on a COMPLETE observation; a missing field must fall through: '
      + JSON.stringify(state.handbacks.map(h => h.reason)))
  }
  if (state.handbacks.length) bad.push('(E) handback filed on a field-less unit: ' + JSON.stringify(state.handbacks))
}

// --- (E2) FALL-THROUGH: the COUNT without the LIST ------------------------------------------
// classify-repo.sh:725 documents actionable_routine_ids as "ABSENT/[] on an older discovery-
// queue entry or an injected unit => relay-loop fails OPEN to the unsliced brief, unchanged",
// while actionable_routine_open may still be present. namedItemsFor() is [] here for a reason
// that is NOT suppression -- there is simply nothing to name -- so the guard must not fire.
// This exact shape is what tests/test_chain_end_widen_verdict_set_4e84.sh's one-round harness
// pushes, and keying the guard on the count instead of the list starved it across that whole
// file (7 of its 10 cases). Pinned here so the keying cannot regress silently.
{
  reset()
  const unit = {
    repo: 'alpha', verdict: 'execute', path: '/tmp/harness/alpha',
    open_hard_pool: 2, roadmap_actionable_open: 3, actionable_routine_open: 1,
  }
  if (namedItemsFor(unit).length !== 0) {
    bad.push('(E2) FIXTURE CALIBRATION: this shape must yield an EMPTY namedItemsFor for a '
      + 'reason other than suppression, else the case proves nothing')
  }
  const r = await dispatchPath(unit)
  if (!r || !r.dispatched) {
    bad.push('(E2) a unit carrying actionable_routine_open WITHOUT actionable_routine_ids was '
      + 'refused. That is the documented fail-open state (classify-repo.sh:725), not an empty '
      + 'permitted set: the guard must key on the ID LIST, never on the count: '
      + JSON.stringify(state.handbacks.map(h => h.reason)))
  }
  if (state.handbacks.length) bad.push('(E2) handback filed on a count-without-list unit: ' + JSON.stringify(state.handbacks))
}

// --- (F) FALL-THROUGH: a non-execute (review) unit is untouched -----------------------------
{
  reset()
  const unit = { repo: 'r_review', verdict: 'review', path: '/tmp/r_review', actionable_routine_open: 3 }
  const r = await dispatchPath(unit)
  if (!r || !r.dispatched) bad.push('(F) a review unit was caught by the execute-only ffc4 guard')
  if (state.handbacks.length) bad.push('(F) handback filed on a review unit: ' + JSON.stringify(state.handbacks))
}

if (bad.length) { bad.forEach(b => console.error('  ' + b)); process.exit(1) }
JS

python3 - "$tmpdir/drive.js" "$tmpdir/region.js" "$tmpdir/helpers.js" "$tmpdir/run.js" <<'PY'
import sys
drive, region, helpers, out = sys.argv[1:5]
body = open(region, encoding='utf-8').read()
src = open(drive, encoding='utf-8').read().replace('  REGION_PLACEHOLDER', body)
open(out, 'w', encoding='utf-8').write(open(helpers, encoding='utf-8').read() + '\n' + src + '\n')
PY

# Each accumulated case failure is re-emitted as its OWN line-leading `FAIL:` line. The
# node driver is a non-exiting accumulator, so a single multi-line note would collapse every
# case into one opaque header line that no `# fails-against-assertion:` declaration could
# discriminate (measured: the runner rejected exactly that shape as WRONG REASON).
if ! node "$tmpdir/run.js" >"$tmpdir/run.out" 2>&1; then
  _any=""
  while IFS= read -r _l; do
    [[ -n "${_l//[[:space:]]/}" ]] || continue
    _any=1
    note "id:ffc4 dispatch guard: ${_l#  }"
  done < "$tmpdir/run.out"
  [[ -n "$_any" ]] || note "id:ffc4 dispatch guard: node exited non-zero with NO output (harness broken, not a finding)"
fi

# --- (G) the engine still parses + lints clean ----------------------------------------------
workflow_node_check "$LOOP" >/dev/null 2>&1 || note "(G) relay-loop.js fails the Workflow node --check after the ffc4 edit"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
if [[ -f "$LINT" ]]; then
  node "$LINT" "$LOOP" >/dev/null 2>&1 || note "(G) relay-loop.js has a template-literal violation after the ffc4 edit"
fi

[[ $fail -eq 0 ]] || exit 1
echo "ALL PASS: an execute unit with an empty permitted set hands back naming the suppressed ids, before the slice and the size gate (id:ffc4)"
