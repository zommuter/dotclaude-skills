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

# ── (4) the engine still lints (backtick-in-template hazard, the id:5bac crash class) ─────
LINT="$SRC_DIR/relay/scripts/lint-workflow-templates.mjs"
if [[ -f "$LINT" ]]; then
  node "$LINT" "$LOOP" >/dev/null 2>&1 || fail "relay-loop.js has a template-literal violation after the 06a1 edit"
  pass "relay-loop.js passes the workflow-template lint"
fi

echo "ALL PASS: per-agent failures are visible in RELAY_STATUS (06a1)"
