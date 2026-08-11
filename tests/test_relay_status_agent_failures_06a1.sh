#!/usr/bin/env bash
# roadmap:06a1 — RELAY_STATUS.md must surface per-agent/per-hop failures.
#
# RED SPEC authored at handoff 2026-08-11. buildRelayStatus (relay-loop.js:356-420) renders
# in-flight / completed / queued / blocked / skipped / quota / reviewMe / alerts, and :380 builds
# blockedRows from state.surfaced + state.handbacks ONLY. A hop or child that fails WITHOUT
# producing a handback has no representation anywhere in the file — it appears solely in the
# Workflow task-notification block, which an --afk operator never reads. In run
# relay-20260811-221747-12629 six agents failed and RELAY_STATUS.md said nothing. id:4347 class.
#
# SCOPE: this is the RENDERING half only. It does NOT change any hop's failure semantics —
# id:66d9 owns fail-closed for provision. A hop that fails soft keeps failing soft; it just
# stops being invisible.
#
# Uses the extract-and-render harness established by test_dispatch_choice_visible_8af2.sh:
# relay-loop.js has no importable surface, so the function is extracted and driven on a fixture.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOOP="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LOOP" ]] || fail "relay-loop.js not found at $LOOP"
node --check "$LOOP" || fail "relay-loop.js fails node --check"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ── (1) the state carries a dedicated failure accumulator ────────────────────────────────
grep -q "agentFailures" "$LOOP" \
  || fail "relay-loop.js has no state.agentFailures accumulator — a failed hop has nowhere to be recorded"
pass "state.agentFailures exists"

# ── (2) something PUSHES to it — an accumulator nothing writes is worse than none ─────────
grep -Eq "agentFailures\.push\(" "$LOOP" \
  || fail "nothing ever pushes to state.agentFailures — the section would always render empty (built-green-but-unwired)"
pass "failures are actually recorded"

# ── (3) buildRelayStatus RENDERS them ────────────────────────────────────────────────────
awk '/^function buildStopReasonLine\(/,/^\}$/'  "$LOOP" >  "$tmpdir/status.js"
awk '/^function buildRelayStatus\(/,/^\}$/'     "$LOOP" >> "$tmpdir/status.js"
grep -q 'function buildRelayStatus' "$tmpdir/status.js" \
  || fail "could not extract buildRelayStatus from relay-loop.js"

cat >> "$tmpdir/status.js" <<'JS'
const base = {
  runId: 'r1', ts: 'T', round: 1, totalDispatched: 1,
  inFlight: [], completed: [], queued: [], blocked: [], surfaced: [], handbacks: [],
  skipped: [], quota: [], reviewMe: [],
}
const bad = []

// A run where six mechanical hops failed — the incident's shape.
const withFailures = buildRelayStatus(Object.assign({}, base, {
  agentFailures: [
    { label: 'provision:escapement', repo: 'escapement', phase: 'Support', round: 1,
      reason: 'issue with the selected model (bash)' },
    { label: 'provision:relay-core', repo: 'relay-core', phase: 'Support', round: 2,
      reason: 'MECH-ERROR exit=1' },
  ],
}))
if (!/provision:escapement/.test(withFailures)) {
  bad.push('RELAY_STATUS does not name the failing agent label — an --afk operator cannot tell WHICH hop died')
}
if (!/issue with the selected model \(bash\)/.test(withFailures)) {
  bad.push('RELAY_STATUS does not carry the failure reason — a bare count is not actionable')
}
if (!/provision:relay-core/.test(withFailures)) {
  bad.push('only the first failure is rendered — the rest are still swallowed')
}
// It must be findable: a distinct labelled section, not smuggled into an unrelated one.
if (!/(fail|error)/i.test(withFailures.split('\n').filter(l => /^#{1,4}\s/.test(l)).join('\n'))) {
  bad.push('no section HEADING mentions failures — the rows exist but the operator has no way to find them')
}

// Quiet when there is nothing to report: no empty section, no false alarm (the id:8c85 cry-wolf lesson).
const clean = buildRelayStatus(Object.assign({}, base, { agentFailures: [] }))
const cleanHeads = clean.split('\n').filter(l => /^#{1,4}\s/.test(l) && /(fail|error)/i.test(l))
if (cleanHeads.length) {
  bad.push('an empty failure section is rendered on a clean run: ' + JSON.stringify(cleanHeads))
}
// Absent field (older state object) must not throw — fail-open on shape, like every sibling row.
try {
  buildRelayStatus(base)
} catch (e) {
  bad.push('buildRelayStatus throws when agentFailures is absent: ' + e.message)
}

if (bad.length) { bad.forEach(b => console.error('  ' + b)); process.exit(1) }
JS

node "$tmpdir/status.js" >"$tmpdir/out" 2>&1 \
  || { echo "FAIL: RELAY_STATUS does not surface agent failures:"; sed 's/^/    /' "$tmpdir/out"; exit 1; }
pass "buildRelayStatus renders a findable failure section, stays quiet when clean, tolerates an absent field"

# ── (3b) id:a104 — the three previously-unwired parse sites now push on a genuine failure ──
# recordAgentFailure + the three parse functions, driven directly on fixture bodies (extracted
# the same way (3) extracts buildRelayStatus — relay-loop.js has no importable surface).
awk '/^function recordAgentFailure\(/,/^\}$/'     "$LOOP" >  "$tmpdir/parse.js"
awk '/^function parseQuotaMechResult\(/,/^\}$/'   "$LOOP" >> "$tmpdir/parse.js"
awk '/^function parseInjectTake\(/,/^\}$/'        "$LOOP" >> "$tmpdir/parse.js"
awk '/^function parsePrelude\(/,/^\}$/'           "$LOOP" >> "$tmpdir/parse.js"
for fn in recordAgentFailure parseQuotaMechResult parseInjectTake parsePrelude; do
  grep -q "function $fn" "$tmpdir/parse.js" || fail "could not extract $fn from relay-loop.js"
done

cat >> "$tmpdir/parse.js" <<'JS'
const state = { agentFailures: [] }
const round = 1
const bad = []

// quota hop: MECH-ERROR body records, exit-code parsing is unchanged
{
  const before = state.agentFailures.length
  const v = parseQuotaMechResult('MECH-ERROR exit=1\nquota-stop: five_hour=92% >= threshold 90', 'five_hour')
  if (v.exitCode !== 1) bad.push('parseQuotaMechResult return value changed for a MECH-ERROR body (fail-soft broken)')
  if (state.agentFailures.length !== before + 1) bad.push('parseQuotaMechResult(MECH-ERROR) did not push to state.agentFailures')
  else if (!/quota:five_hour/.test(state.agentFailures[before].label)) bad.push('quota failure entry does not name the tier')
  // legitimate proceed (exit 0 sentinel, i.e. no MECH-ERROR prefix) must NOT record — no cry-wolf
  const before2 = state.agentFailures.length
  parseQuotaMechResult('', 'five_hour')
  if (state.agentFailures.length !== before2) bad.push('parseQuotaMechResult recorded a failure on a clean (non-MECH-ERROR) body')
}

// inject-take hop: MECH-ERROR records; MECH-OK / empty (legitimate "nothing pending") do not
{
  const before = state.agentFailures.length
  const units = parseInjectTake('MECH-ERROR exit=1\nboom', [])
  if (!Array.isArray(units) || units.length !== 0) bad.push('parseInjectTake return value changed for a MECH-ERROR body')
  if (state.agentFailures.length !== before + 1) bad.push('parseInjectTake(MECH-ERROR) did not push to state.agentFailures')
  const before2 = state.agentFailures.length
  parseInjectTake('MECH-OK exit=0', [])
  parseInjectTake('', [])
  if (state.agentFailures.length !== before2) bad.push('parseInjectTake recorded a failure on a legitimate empty/MECH-OK body (cry-wolf)')
}

// discover-prelude hop: MECH-ERROR records, and genuinely unparseable JSON also records
{
  const before = state.agentFailures.length
  const p1 = parsePrelude('MECH-ERROR exit=1\nboom')
  if (p1 !== null) bad.push('parsePrelude return value changed for a MECH-ERROR body')
  if (state.agentFailures.length !== before + 1) bad.push('parsePrelude(MECH-ERROR) did not push to state.agentFailures')
  const before2 = state.agentFailures.length
  const p2 = parsePrelude('{not json')
  if (p2 !== null) bad.push('parsePrelude return value changed for an unparseable body')
  if (state.agentFailures.length !== before2 + 1) bad.push('parsePrelude(unparseable) did not push to state.agentFailures')
  const before3 = state.agentFailures.length
  parsePrelude('MECH-OK exit=0')
  parsePrelude('')
  if (state.agentFailures.length !== before3) bad.push('parsePrelude recorded a failure on a legitimate empty/MECH-OK body (cry-wolf)')
}

if (bad.length) { bad.forEach(b => console.error('  ' + b)); process.exit(1) }
JS

node "$tmpdir/parse.js" >"$tmpdir/out2" 2>&1 \
  || { echo "FAIL: the three previously-unwired parse sites (id:a104) don't record agent failures:"; sed 's/^/    /' "$tmpdir/out2"; exit 1; }
pass "quota / inject-take / discover-prelude parse sites now record real failures without changing their return shape (id:a104)"

# ── (4) the engine still lints (backtick-in-template hazard, the id:5bac crash class) ─────
LINT="$SRC_DIR/relay/scripts/lint-workflow-templates.mjs"
if [[ -f "$LINT" ]]; then
  node "$LINT" "$LOOP" >/dev/null 2>&1 || fail "relay-loop.js has a template-literal violation after the 06a1 edit"
  pass "relay-loop.js passes the workflow-template lint"
fi

echo "ALL PASS: per-agent failures are visible in RELAY_STATUS (06a1)"
