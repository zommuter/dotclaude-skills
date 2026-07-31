#!/usr/bin/env bash
# roadmap:8af2
#
# RED SPEC — the pool silently works `actionable_routine_ids[0]` (id:b09e) and NOTHING says so.
# On 2026-07-31 this repo had 21 actionable [ROUTINE] items with the primary cadence fix mid-list;
# running the pool would have worked a different item and no surface would have recorded it.
#
# SCOPE: VISIBILITY only. This spec must NOT be satisfied by changing the selection rule, adding a
# priority field, or re-ordering actionable_routine_ids — clause (0) below pins the selection rule
# UNCHANGED, so an implementation that "fixes" ordering fails this test.
#
# CONTRACT (both surfaces must agree — the live view and the forensic log):
#   1. RELAY_STATUS.md's per-repo In-flight row carries the CHOSEN item id AND the eligible count.
#   2. The dispatch event in relay-events.jsonl carries the chosen id AND the eligible count.
#   3. The count is mandatory on BOTH — the id alone is what made the mid-list item invisible.
#   4. Non-execute units (no named item) fail OPEN: the row/event render exactly as before.
#
# Hermetic: static source assertions + node evaluation of the extracted pure helpers.
# No network, no ~/.claude writes, no Workflow engine (it cannot run hermetically).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOOP="$ROOT/relay/scripts/relay-loop.js"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT

[[ -f "$LOOP" ]] || { echo "FAIL: relay-loop.js not found at $LOOP" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

# ── (0) SCOPE GUARD — the selection rule stays `actionable_routine_ids[0]` (+ injection override).
grep -q "unit.inject_item || namedItemsFor(unit)\[0\] || ''" "$LOOP" \
  || note "(0) the id:b09e selection rule changed — id:8af2 is VISIBILITY only; changing which item is picked is out of scope"

# ── (1) a named CHOICE helper exists and reports rank + eligible count ──────────────────
awk '/^const dispatchChoiceFor = /,/^\}/' "$LOOP" > "$tmpdir/choice.js"
if ! grep -q 'dispatchChoiceFor' "$tmpdir/choice.js"; then
  note "(1) no dispatchChoiceFor helper in relay-loop.js — nothing computes the chosen id + eligible count"
else
  # the helper depends on namedItemsFor/dispatchItemFor; prepend them.
  {
    awk '/^const namedItemsFor = /,/^\}/' "$LOOP"
    awk "/^const dispatchItemFor = /{print}" "$LOOP"
    cat "$tmpdir/choice.js"
    cat <<'JS'
const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) { console.error('  ' + m + ' got ' + JSON.stringify(a)); process.exit(1) } }
// 21 eligible, classifier picks the first: "1 of 21".
const ids = Array.from({length: 21}, (_, i) => (0x1000 + i).toString(16))
const c = dispatchChoiceFor({ actionable_routine_ids: ids })
eq(c.item, ids[0], 'chosen item is not actionable_routine_ids[0]')
eq(c.itemRank, 1, 'itemRank is not 1 for the head pick')
eq(c.eligibleCount, 21, 'eligibleCount is not 21')
// suppression subtracts from the eligible set (id:b09e orphan-suppress).
const s = dispatchChoiceFor({ actionable_routine_ids: ['aaa1','aaa2'], suppressed_item_ids: ['aaa1'] })
eq(s.item, 'aaa2', 'suppressed id was chosen')
eq(s.eligibleCount, 1, 'suppressed id still counted as eligible')
// an injected item is NOT in the eligible list -> rank 0, but the count still reports.
const j = dispatchChoiceFor({ inject_item: 'bbbb', actionable_routine_ids: ['aaa1','aaa2'] })
eq(j.item, 'bbbb', 'injected item did not win')
eq(j.itemRank, 0, 'injected item must have rank 0 (not in the eligible order)')
eq(j.eligibleCount, 2, 'injected dispatch lost the eligible count')
// fail-open: no ids at all.
const n = dispatchChoiceFor({})
eq(n.item, '', 'no-ids unit must yield item ""')
eq(n.eligibleCount, 0, 'no-ids unit must yield eligibleCount 0')
JS
  } > "$tmpdir/choice-run.js"
  node "$tmpdir/choice-run.js" 2>&1 | sed 's/^/    /' >"$tmpdir/choice.out" || note "(1) dispatchChoiceFor is wrong:
$(cat "$tmpdir/choice.out")"
fi

# ── (1b) WIRING — the helper must be CALLED at the dispatch site, not merely defined.
# The banked [[relay-builtgreen-but-unreferenced]] class: built, tested, green, referenced by
# nothing. Pin the CALL, and pin that it sits in the same block as the inFlight/dispatch-event
# stamping (so both surfaces are fed from ONE computation and can never disagree).
grep -qE '^\s*(const|let)\s+\w+\s*=\s*dispatchChoiceFor\(unit\)' "$LOOP" \
  || note "(1b) dispatchChoiceFor is never CALLED on a unit — the choice is computed nowhere and neither surface can carry it"
awk '/= dispatchChoiceFor\(unit\)/{c=4} c&&c--{print}' "$LOOP" > "$tmpdir/callsite.txt"
grep -q 'state\.inFlight\.push' "$tmpdir/callsite.txt" \
  || note "(1b) the dispatchChoiceFor call is not adjacent to state.inFlight.push — the status row is not fed from it"
grep -q "pushEvent('dispatch'" "$tmpdir/callsite.txt" \
  || note "(1b) the dispatchChoiceFor call is not adjacent to pushEvent('dispatch') — the event is not fed from the same computation"

# ── (2) the dispatch EVENT carries the chosen id AND the eligible count ────────────────
ev="$(grep -n "pushEvent('dispatch'" "$LOOP" || true)"
[[ -n "$ev" ]] || note "(2) no pushEvent('dispatch', …) call site found"
grep -q "pushEvent('dispatch'.*item:" "$LOOP" \
  || note "(2) pushEvent('dispatch',…) does not carry an 'item:' field — the forensic log still cannot say which item was taken (id:8af2)"
grep -qE "pushEvent\('dispatch'.*(eligibleCount|eligible_count):" "$LOOP" \
  || note "(3) pushEvent('dispatch',…) does not carry the eligible COUNT — the id alone does not make a mid-list pick obvious (id:8af2)"
grep -qE "pushEvent\('dispatch'.*(itemRank|item_rank):" "$LOOP" \
  || note "(3) pushEvent('dispatch',…) does not carry the item RANK — '1 of 21' needs both halves"

# ── (4) the in-flight state row is stamped with the choice at dispatch ─────────────────
grep -qE "state\.inFlight\.push\(.*item" "$LOOP" \
  || note "(4) state.inFlight.push does not stamp the chosen item — buildRelayStatus has nothing to render"

# ── (5) RELAY_STATUS.md's per-repo row RENDERS the id and the count ────────────────────
# Extract buildStopReasonLine + buildRelayStatus and render a fixture snapshot.
awk '/^function buildStopReasonLine\(/,/^\}$/'  "$LOOP" >  "$tmpdir/status.js"
awk '/^function buildRelayStatus\(/,/^\}$/'     "$LOOP" >> "$tmpdir/status.js"
if ! grep -q 'function buildRelayStatus' "$tmpdir/status.js"; then
  note "(5) could not extract buildRelayStatus from relay-loop.js"
else
  cat >> "$tmpdir/status.js" <<'JS'
const out = buildRelayStatus({
  runId: 'r1', ts: 'T', round: 1, totalDispatched: 1,
  inFlight: [
    { repo: 'dotclaude-skills', mode: 'execute', agentId: 'unit-1', item: 'cbd2', itemRank: 1, eligibleCount: 21 },
    { repo: 'other-repo', mode: 'review', agentId: 'unit-2' },
  ],
  completed: [], queued: [], blocked: [], surfaced: [], handbacks: [],
  skipped: [], quota: [], reviewMe: [],
})
const bad = []
const row = out.split('\n').find(l => l.includes('dotclaude-skills')) || ''
if (!/id:cbd2/.test(row)) bad.push('In-flight row does not name the chosen item id: ' + JSON.stringify(row))
if (!/\b21\b/.test(row)) bad.push('In-flight row does not carry the ELIGIBLE COUNT (21) — the id alone is not enough: ' + JSON.stringify(row))
if (!/\b1\b/.test(row)) bad.push('In-flight row does not carry the rank (1 of 21): ' + JSON.stringify(row))
// (6) fail-open: a unit with no named item renders exactly as before (no dangling "id:" / "of ").
const row2 = out.split('\n').find(l => l.includes('other-repo')) || ''
if (/id:|actionable/.test(row2)) bad.push('a unit with no named item leaked choice decoration: ' + JSON.stringify(row2))
if (bad.length) { bad.forEach(b => console.error('  ' + b)); process.exit(1) }
JS
  node "$tmpdir/status.js" 2>&1 | sed 's/^/    /' >"$tmpdir/status.out" || note "(5/6) RELAY_STATUS In-flight row does not surface the choice:
$(cat "$tmpdir/status.out")"
fi

# ── (7) the engine still parses and lints clean (backtick-in-template hazard) ──────────
node --check "$LOOP" >/dev/null 2>&1 || note "(7) relay-loop.js fails node --check after the 8af2 edit"
LINT="$ROOT/relay/scripts/lint-workflow-templates.mjs"
if [[ -f "$LINT" ]]; then
  node "$LINT" "$LOOP" >/dev/null 2>&1 || note "(7) relay-loop.js has a template-literal violation after the 8af2 edit"
fi

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:8af2 not built yet" >&2; exit 1; }
echo "ALL PASS: dispatch choice (chosen id + eligible count) is surfaced in RELAY_STATUS and the dispatch event (id:8af2)"
