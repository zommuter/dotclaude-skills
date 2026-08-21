#!/usr/bin/env bash
# roadmap:3222 — a blocked/failed agent() dispatch must be counted in state.agentFailures.
#
# RED SPEC authored at handoff 2026-08-12. Slice (c) of id:83c2 only — the cheap,
# strictly-improving half. It does NOT attempt (a) self-attesting hops or (b) moving hops off
# the agent dispatcher; both need an owner decision and stay open on id:83c2.
#
# Run relay-20260812-001727-5554 had 39 agents blocked by the harness safety classifier
# (release x17, write-relay-status x6, inject-take x6, provision x1, gaming-log x1) while
# RELAY_STATUS.md reported `agent-failures=8`. Two disjoint channels: id:a104 wired the three
# PARSE sites, but a dispatch that resolves null/empty or throws at the agent() boundary is
# counted nowhere the operator can see. 39 invisible failures beside 8 visible ones is id:4347.
#
# VISIBILITY ONLY — fail-soft semantics must not change. A hop that continues on failure today
# must still continue; it just stops being invisible.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ── (1) a single guarded-dispatch helper exists ────────────────────────────────────────────
# One wrapper, not a hand-rolled try/catch at each of ~12 hops: duplicated failure handling is
# how three of these sites drifted apart in the first place.
grep -Eq "function (dispatchGuarded|agentGuarded|safeAgent)\b" "$JS" \
  || fail "no guarded-dispatch helper (dispatchGuarded/agentGuarded/safeAgent) — each hop would hand-roll its own failure path"
pass "a single guarded-dispatch helper exists"

helper="$(awk '/^(async )?function (dispatchGuarded|agentGuarded|safeAgent)\(/,/^\}$/' "$JS")"
[[ -n "$helper" ]] || fail "could not extract the guarded-dispatch helper"

# ── (2) it records BOTH the throw case and the null/empty-resolution case ──────────────────
# The incident's one observable (provision round 3: `no PROVISION-OK token: ""`) suggests an
# empty-string resolution rather than a throw — but one observation is not the contract, so both
# must be handled.
grep -q "catch" <<<"$helper" || fail "the helper does not catch a THROWN agent() failure"
grep -Eq "== *null|=== *null|!res|!raw|!out|== *''|=== *''|\.trim\(\)" <<<"$helper" \
  || fail "the helper does not treat a null/empty resolution as a failure — the observed classifier-block shape would slip through"
grep -q "recordAgentFailure" <<<"$helper" || fail "the helper never calls recordAgentFailure"
pass "the helper records both the throw and the null/empty-resolution cases"

# ── (3) the fire-and-forget hops actually USE it ───────────────────────────────────────────
# These are the classes that produced real damage: blocked releases stranded two leases, blocked
# status writes left RELAY_STATUS hours stale.
# STRENGTHENED (reviewer, 2026-08-12): the original form grepped a ±12-line window and could be
# satisfied by a COMMENT mentioning the guard — the id:3222 executor flagged exactly that, since
# the real dispatch carries `label: 'write-relay-status'` in SINGLE quotes (pinned by
# test_relay_phase_buckets.sh:31) while the item's prose used a template literal. Require a
# NON-COMMENT line that actually calls the guard AND names the label, so a comment cannot pass.
for label in "release:" "write-relay-status" "gaming-log"; do
  hit="$(grep -nE "(dispatchGuarded|agentGuarded|safeAgent)\(" "$JS" \
        | grep -v "^[0-9]*: *//" \
        | while IFS=: read -r ln _; do
            grep -q "${label}" < <(sed -n "${ln},$((ln+4))p" "$JS") && echo "$ln"
          done | head -1 || true)"
  [[ -n "$hit" ]] \
    || fail "the '${label}' hop does not go through the guarded dispatcher on a real (non-comment) call line — its failures stay invisible (this class stranded leases / staled RELAY_STATUS in run relay-20260812-001727-5554)"
done
pass "the release / write-relay-status / gaming-log hops dispatch through the guard (real call sites, not comments)"

# ── (4) NO DOUBLE-COUNTING: provisionWorktree already records its own failure (id:66d9) ────
prov="$(awk '/^async function provisionWorktree/,/^}/' "$JS")"
n_record="$(grep -c "recordAgentFailure" <<<"$prov" || true)"
n_guard="$(grep -Ec "dispatchGuarded|agentGuarded|safeAgent" <<<"$prov" || true)"
if [[ "$n_guard" -gt 0 && "$n_record" -gt 0 ]]; then
  fail "provisionWorktree both calls the guard AND records directly — one provisioning failure would produce TWO agentFailures entries"
fi
pass "provisioning records exactly one failure entry (no double-count with id:66d9)"

# ── (5) fail-soft preserved: the guard returns a value, it does not rethrow ────────────────
grep -Eq "throw " <<<"$helper" \
  && fail "the guarded dispatcher RETHROWS — that converts today's fail-soft hops into fail-closed ones, which is out of scope for this item (id:66d9 owns fail-closed for provision)"
pass "the guard does not rethrow — fail-soft semantics preserved"

# ── (6) end-to-end on the renderer: a recorded block reaches RELAY_STATUS ──────────────────
awk '/^function recordAgentFailure\(/,/^\}$/'  "$JS" >  "$tmpdir/render.js"
awk '/^function buildStopReasonLine\(/,/^\}$/' "$JS" >> "$tmpdir/render.js"
awk '/^function buildRelayStatus\(/,/^\}$/'    "$JS" >> "$tmpdir/render.js"
cat >> "$tmpdir/render.js" <<'JS'
const state = { agentFailures: [] }
const round = 1
const bad = []
recordAgentFailure('release:it-infra', 'it-infra', 'Leases', 'blocked by safety classifier')
if (state.agentFailures.length !== 1) bad.push('recordAgentFailure did not accumulate the entry')
const out = buildRelayStatus({
  runId: 'r1', ts: 'T', round: 1, totalDispatched: 0,
  inFlight: [], completed: [], queued: [], blocked: [], surfaced: [], handbacks: [],
  skipped: [], quota: [], reviewMe: [], agentFailures: state.agentFailures,
})
if (!/release:it-infra/.test(out)) bad.push('a recorded blocked hop does not reach RELAY_STATUS')
if (!/blocked by safety classifier/.test(out)) bad.push('the block reason does not reach RELAY_STATUS')
if (bad.length) { bad.forEach(b => console.error('  ' + b)); process.exit(1) }
JS
node "$tmpdir/render.js" >"$tmpdir/out" 2>&1 \
  || { echo "FAIL: a blocked hop does not surface in RELAY_STATUS:"; sed 's/^/    /' "$tmpdir/out"; exit 1; }
pass "a recorded blocked hop reaches RELAY_STATUS end to end"

echo "ALL PASS: blocked/failed dispatches are counted (3222)"
