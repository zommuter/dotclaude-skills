#!/usr/bin/env bash
# roadmap:a360
#
# RED SPEC for id:a360 — the id:dd7d pre-dispatch stranded-branch guard is ITEM-scoped in its
# MESSAGE ("… for <repo> item <id> …") but REPO-scoped in its ACTION (a bare `return` that
# aborts the whole unit and files a repo-level handback). Combined with the id:b09e head-of-list
# selection rule and one-unit-per-repo-per-round (dc5b C2) that is a closed, deterministic loop:
# the round picks actionable_routine_ids[0], the guard refuses, the repo gets ZERO dispatch, and
# the next round makes the identical choice.
#
# OBSERVED LIVE, loderite run relay-20260822-102233-32252 (third consecutive run):
#   classify-repo.sh --repo loderite → verdict=execute, priority_rank=1,
#   actionable_routine_open=6, actionable_routine_ids=[57d1,6612,084f,c8a7,55a4,5adb]
#   Only 57d1 carried a stranded branch (relay/orphan/relay-20260820-180056-4594-execute-57d1-0,
#   1 commit). The other five were unencumbered and unreachable forever.
# Those exact ids and that exact branch name are used as the fixture below — real data.
#
# CONTRACT
#   1. One stranded item + ≥1 clean actionable item ⇒ DISPATCH the clean one. No repo-level
#      handback, no handback event.
#   2. EVERY actionable item stranded ⇒ still hand back, naming every branch found AND its
#      commit count (the dd7d surface a human dispositions from).
#   3. The stranded item is NEVER the dispatched item, and must not survive in the unit's
#      nameable set (so it cannot reach the child as a named alternate either). This is the
#      dd7d no-blind-redispatch guarantee (lodelore id:15d2) — a360 changes WHICH item is
#      dispatched, never the protection on the stranded one.
#   4. An INJECTED item (id:baf1 --item) is NOT skipped — the user asked for that specific
#      item, so a stranded branch on it still hands back rather than silently working something
#      else.
#
# METHOD — behavioural, not shape. relay-loop.js is a Workflow module that cannot be imported or
# executed hermetically (id:2ec4), so this spec EXTRACTS the real dispatch-path source between
# the dd7d guard marker and the id:34b7 provisioning marker, evaluates it inside an async
# wrapper against stubbed I/O (log/state/pushEvent/slice/size-gate), and drives it with a fake
# stranded-branch scanner. The extracted text IS production code, and the extraction works
# against BOTH the pre-fix and post-fix layouts — so this file is a genuine negative control:
# on the unmodified tree case (A) fails with "expected dispatch of id:6612, unit was ABORTED".
#
# Hermetic: node + mktemp -d only. No git, no network, no ~/.claude writes.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOOP="$ROOT/relay/scripts/relay-loop.js"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT

[[ -f "$LOOP" ]] || { echo "FAIL: relay-loop.js not found at $LOOP" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not available (this spec needs it)" >&2; exit 1; }

# ── extract the real helpers the dispatch path uses ────────────────────────────────────────
{
  awk '/^const namedItemsFor = /,/^\}/'          "$LOOP"
  awk "/^const dispatchItemFor = /{print}"       "$LOOP"
  awk "/^const strandedIdsOf = /{print}"         "$LOOP"
  awk '/^async function strandedDispatchGate\(/,/^\}/' "$LOOP"
  awk '/^const strandedDispatchReason = /,/^\}/' "$LOOP"
} > "$tmpdir/helpers.js"

# ── extract the dispatch-path REGION under test (dd7d guard … id:34b7 provisioning) ────────
awk '/pre-dispatch stranded-branch guard \(b\)/{f=1} /id:34b7 . the parent creates/{f=0} f' \
  "$LOOP" > "$tmpdir/region.js"
[[ -s "$tmpdir/region.js" ]] \
  || note "could not extract the dd7d dispatch-path region from relay-loop.js (markers moved?)"
grep -q 'strandedBranchesFor' "$tmpdir/region.js" \
  || note "the extracted region does not consult strandedBranchesFor — the dd7d guard is not in it"

cat > "$tmpdir/drive.js" <<'JS'
// ── stubs for everything the region touches other than the decision under test ───────────
let state, events, logs, STRANDED
const log = (m) => logs.push(String(m))
const pushEvent = (kind, payload) => events.push(Object.assign({ kind }, payload))
const scheduleStatusWrite = () => {}
const emittedHandbackEvents = []
const sliceLedgerForUnit = async () => null
const oversizeDispatchReason = () => ''
const unitPrompt = () => ''
// The fake scanner: keyed on the item the region is CURRENTLY selecting, exactly as the real
// strandedBranchesFor is (it calls dispatchItemFor(unit) itself).
// Mirrors the real one's contract: repo-scoped units (no item id) always return [].
const strandedBranchesFor = async (unit) => {
  const item = dispatchItemFor(unit)
  if (!item) return []
  return STRANDED[item] || []
}

async function dispatchPath(unit) {
  // eslint-disable-next-line no-eval
  REGION_PLACEHOLDER
  // Falling off the end = the unit reached provisioning, i.e. it DISPATCHES.
  return { dispatched: true, item: dispatchItemFor(unit) }
}

const reset = () => { state = { handbacks: [], inFlight: [] }; events = []; logs = []; STRANDED = {} }
const bad = []
const LODERITE = ['57d1', '6612', '084f', 'c8a7', '55a4', '5adb']
const B57D1 = 'relay/orphan/relay-20260820-180056-4594-execute-57d1-0\t1'

// ── (A) ONE stranded item + five clean ones ⇒ dispatch the next actionable id ─────────────
{
  reset()
  STRANDED = { '57d1': [B57D1] }
  const unit = { repo: 'loderite', verdict: 'execute', path: '/tmp/loderite', actionable_routine_ids: LODERITE.slice() }
  const r = await dispatchPath(unit)
  if (!r || !r.dispatched) {
    bad.push('(A) expected dispatch of id:6612, unit was ABORTED (repo-level handback) — this is the '
      + 'a360 starvation: handbacks=' + JSON.stringify(state.handbacks.map(h => h.reason)))
  } else if (r.item !== '6612') {
    bad.push('(A) dispatched id:' + r.item + ', expected the next actionable id:6612')
  }
  if (state.handbacks.length !== 0) {
    bad.push('(A) a repo-level handback was filed even though five actionable items are clean: '
      + JSON.stringify(state.handbacks.map(h => h.reason)))
  }
  if (events.some(e => e.kind === 'handback')) {
    bad.push('(A) a handback EVENT was emitted for a repo that still had clean actionable work')
  }
  // (3) the stranded item must not be dispatched, nor remain nameable to the child
  if (r && r.item === '57d1') bad.push('(A/3) the STRANDED item was dispatched — dd7d no-blind-redispatch broken')
  if (namedItemsFor(unit).includes('57d1')) {
    bad.push('(A/3) the stranded id:57d1 is still in the unit\'s nameable set, so it can reach the child '
      + 'as a named alternate: ' + JSON.stringify(namedItemsFor(unit)))
  }
}

// ── (B) EVERY actionable item stranded ⇒ still hand back, naming every branch + count ─────
{
  reset()
  STRANDED = {}
  const lines = {}
  for (const id of LODERITE) {
    const l = 'relay/orphan/relay-20260820-180056-4594-execute-' + id + '-0\t' + (LODERITE.indexOf(id) + 1)
    STRANDED[id] = [l]; lines[id] = l
  }
  const unit = { repo: 'loderite', verdict: 'execute', path: '/tmp/loderite', actionable_routine_ids: LODERITE.slice() }
  const r = await dispatchPath(unit)
  if (r && r.dispatched) bad.push('(B) an all-stranded repo DISPATCHED — every item carries committed work (dd7d)')
  if (state.handbacks.length !== 1) {
    bad.push('(B) expected exactly one handback, got ' + state.handbacks.length)
  } else {
    const reason = String(state.handbacks[0].reason)
    for (const id of LODERITE) {
      if (!reason.includes(lines[id])) {
        bad.push('(B) the handback reason does not name branch+commit-count "' + lines[id] + '": ' + reason)
      }
    }
    if (!/id:dd7d/.test(reason)) bad.push('(B) the handback reason no longer cites id:dd7d: ' + reason)
    if (!/15d2/.test(reason)) bad.push('(B) the handback reason dropped the lodelore id:15d2 citation: ' + reason)
  }
  if (!events.some(e => e.kind === 'handback')) bad.push('(B) no handback EVENT emitted (id:4a46 bidirectional surface)')
}

// ── (C) nothing stranded ⇒ unchanged behaviour: head of the list dispatches, no handback ──
{
  reset()
  const unit = { repo: 'loderite', verdict: 'execute', path: '/tmp/loderite', actionable_routine_ids: LODERITE.slice() }
  const r = await dispatchPath(unit)
  if (!r || !r.dispatched) bad.push('(C) a repo with NO stranded branch failed to dispatch — the gate is not fail-open')
  else if (r.item !== '57d1') bad.push('(C) selection rule changed: expected the head id:57d1, got id:' + r.item)
  if (state.handbacks.length) bad.push('(C) handback filed with nothing stranded: ' + JSON.stringify(state.handbacks))
}

// ── (D) an INJECTED stranded item still hands back (never silently re-aimed) ──────────────
{
  reset()
  STRANDED = { '57d1': [B57D1] }
  const unit = { repo: 'loderite', verdict: 'execute', path: '/tmp/loderite', inject_item: '57d1', actionable_routine_ids: LODERITE.slice() }
  const r = await dispatchPath(unit)
  if (r && r.dispatched) {
    bad.push('(D) an INJECTED stranded item was silently re-aimed at id:' + r.item
      + ' — the user asked for id:57d1; a stranded injection must hand back')
  }
  if (state.handbacks.length !== 1) bad.push('(D) expected a handback for the stranded injected item, got ' + state.handbacks.length)
}

// ── (E) a repo-scoped unit (no item id) is untouched ──────────────────────────────────────
{
  reset()
  const unit = { repo: 'loderite', verdict: 'review', path: '/tmp/loderite' }
  const r = await dispatchPath(unit)
  if (!r || !r.dispatched) bad.push('(E) a repo-scoped unit (no item id) was blocked by the stranded gate')
  if (state.handbacks.length) bad.push('(E) repo-scoped unit filed a stranded handback: ' + JSON.stringify(state.handbacks))
}

if (bad.length) { bad.forEach(b => console.error('  ' + b)); process.exit(1) }
JS

# splice the extracted region into the driver (python3: no shell-quoting hazards on the source)
python3 - "$tmpdir/drive.js" "$tmpdir/region.js" "$tmpdir/helpers.js" "$tmpdir/run.js" <<'PY'
import sys
drive, region, helpers, out = sys.argv[1:5]
body = open(region, encoding='utf-8').read()
src = open(drive, encoding='utf-8').read().replace('  // eslint-disable-next-line no-eval\n  REGION_PLACEHOLDER', body)
open(out, 'w', encoding='utf-8').write(open(helpers, encoding='utf-8').read() + '\n' + src + '\n')
PY

node "$tmpdir/run.js" >"$tmpdir/run.out" 2>&1 \
  || note "the dd7d dispatch path is REPO-scoped in action (id:a360):
$(sed 's/^/    /' "$tmpdir/run.out")"

# ── (F) the engine still parses + lints clean after the a360 edit ─────────────────────────
node --check "$LOOP" >/dev/null 2>&1 || note "(F) relay-loop.js fails node --check after the a360 edit"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
if [[ -f "$LINT" ]]; then
  node "$LINT" "$LOOP" >/dev/null 2>&1 || note "(F) relay-loop.js has a template-literal violation after the a360 edit"
fi

[[ $fail -eq 0 ]] || exit 1
echo "ALL PASS: dd7d skips the STRANDED item and dispatches the next actionable one; hands back only when every item is stranded (id:a360)"
