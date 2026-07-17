#!/usr/bin/env bash
# roadmap:1735 — relay-loop's returned handback SUMMARY must be reconciled against the event
# stream, not silently lose entries. Root cause (proven on run relay-20260717-100452-13146,
# loderite): `state.blocked` was REASSIGNED wholesale every round (`state.blocked =
# discovery.surfaced.map(...)`) while five handback sites pushed into it as if it accumulated
# across rounds — a handback recorded in round N was destroyed by round N+1's reassignment, so
# the run's final `handbacks` summary (derived by filtering state.blocked) came back empty even
# though the event log (relay-events.jsonl) had a real `kind:"handback"` entry for it.
#
# The fix splits the two incompatible jobs into two arrays with two different lifetimes: a
# per-round SURFACED VIEW (rebuilt fresh every round — reassignment here is correct) and a
# PERSISTENT HANDBACK ACCUMULATOR (only ever pushed to, never reassigned). The pure logic lives
# in relay/scripts/handback-summary.mjs so it is node-unit-testable; relay-loop.js carries
# byte-equivalent inline copies (the Workflow sandbox cannot `import` — no filesystem/require).
#
# HONEST COVERAGE LIMIT (same as id:f980/id:365b precedent): relay-loop.js is a Workflow module
# that cannot be imported or executed in this harness (id:2ec4). The pure-helper tests below
# (cases via handback-summary.mjs, driven directly through node) cover the real LOGIC — the
# accumulate/reconcile/invariant behaviour. The structural greps only cover that relay-loop.js
# WIRES the fixed shape (no `state.blocked` field survives, all 5 push sites target the
# persistent accumulator, the invariant assertion exists) — they do NOT prove the wiring executes
# correctly end-to-end inside a live pool round, which is unreachable from this harness.
#
# Hermetic: node-only, no git, no network, no ~/.claude writes.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/handback-summary.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: handback-summary.mjs missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── Case 4 (the real spec): drive the pure helper through a simulated 2-round run ──────────
cat > "$TMP/drive.mjs" <<NODE
import { buildSurfacedView, reconcileHandbacks, assertHandbackInvariant } from 'file://$HELPER'
const out = []

// Round 1: a real handback is pushed into the persistent accumulator + an event is emitted
// for it. The per-round surfaced view is also rebuilt (unrelated repos, e.g. suppressed ones).
const accumulator = []
const emittedEvents = []
let surfacedView = buildSurfacedView([{ repo: 'other-repo', reason: 'gated [HARD]' }])
accumulator.push({ repo: 'loderite', reason: 'Merge conflict in ROADMAP.md', worktreePath: '/cache/relay/worktrees/loderite/run1-execute' })
emittedEvents.push({ repo: 'loderite', reason: 'Merge conflict in ROADMAP.md' })

// Round 2: discovery reclassifies — the surfaced view is REASSIGNED (this is the per-round
// view's correct, intentional behaviour). The accumulator must NOT be touched by this.
surfacedView = buildSurfacedView([{ repo: 'other-repo', reason: 'suppressed re-dispatch: parked partial work' }])

// Round 3 (the run ends here): derive the final summary from the accumulator, not the view.
const handbacks = reconcileHandbacks(accumulator)
out.push('handback_survives_round_boundary=' + (handbacks.length === 1 ? '1' : '0'))
out.push('handback_repo=' + (handbacks[0] ? handbacks[0].repo : ''))
out.push('surfaced_view_reassigned_ok=' + (surfacedView.length === 1 && surfacedView[0].repo === 'other-repo' ? '1' : '0'))
out.push('surfaced_view_worktree_dash=' + (surfacedView[0].worktreePath === '-' ? '1' : '0'))

// The invariant: the emitted event has a matching accumulator entry ⇒ reconcile passes.
const inv1 = assertHandbackInvariant(emittedEvents, accumulator)
out.push('invariant_ok_when_matched=' + (inv1.ok ? '1' : '0'))
out.push('invariant_violations_when_matched=' + inv1.violations.length)

// Now feed a handback event with NO accumulator entry (simulates the ORIGINAL bug reappearing —
// an event was emitted but the accumulator never got the matching push). The reconcile must
// report the violation non-silently, not silently return the smaller list.
const orphanEvents = [...emittedEvents, { repo: 'ghost-repo', reason: 'never recorded' }]
const inv2 = assertHandbackInvariant(orphanEvents, accumulator)
out.push('invariant_ok_when_orphaned=' + (inv2.ok ? '1' : '0'))
out.push('invariant_violations_when_orphaned=' + inv2.violations.length)
out.push('invariant_violation_repo=' + (inv2.violations[0] ? inv2.violations[0].repo : ''))

// reconcileHandbacks must filter out entries with no real worktree (worktreePath '-' or absent)
// — e.g. the id:5ac6 INTENSIVE fail-closed skip, which is accumulator-pushed but never dispatched.
const mixedAcc = [
  { repo: 'a', reason: 'real handback', worktreePath: '/cache/relay/worktrees/a/run1' },
  { repo: 'b', reason: 'INTENSIVE fail-closed (id:5ac6)', worktreePath: '-' },
]
out.push('reconcile_filters_dash_worktree=' + (reconcileHandbacks(mixedAcc).length === 1 ? '1' : '0'))

console.log(out.join('\n'))
NODE

node "$TMP/drive.mjs" > "$TMP/res" 2>"$TMP/err" || { echo "FAIL: driver errored:"; cat "$TMP/err"; exit 1; }
get() { grep -E "^$1=" "$TMP/res" | head -1 | cut -d= -f2-; }

[[ "$(get handback_survives_round_boundary)" == "1" ]] && ok "a handback pushed in round 1 SURVIVES a round-2 surfaced-view reassignment" || bad "handback should survive the round boundary"
[[ "$(get handback_repo)" == "loderite" ]] && ok "the surviving handback is the real one (loderite)" || bad "wrong handback survived"
[[ "$(get surfaced_view_reassigned_ok)" == "1" ]] && ok "the per-round surfaced view IS correctly reassigned each round (that part is intentional)" || bad "surfaced view reassignment broken"
[[ "$(get surfaced_view_worktree_dash)" == "1" ]] && ok "surfaced-view entries carry worktreePath:'-' (never dispatched)" || bad "surfaced view worktreePath wrong"
[[ "$(get invariant_ok_when_matched)" == "1" && "$(get invariant_violations_when_matched)" == "0" ]] && ok "invariant passes when every emitted event has a matching accumulator entry" || bad "invariant should pass when matched"
[[ "$(get invariant_ok_when_orphaned)" == "0" && "$(get invariant_violations_when_orphaned)" == "1" ]] && ok "invariant reports the violation (non-silently) when an event has no accumulator match" || bad "invariant should trip on an orphaned event"
[[ "$(get invariant_violation_repo)" == "ghost-repo" ]] && ok "the violation identifies the orphaned repo" || bad "violation should name ghost-repo"
[[ "$(get reconcile_filters_dash_worktree)" == "1" ]] && ok "reconcileHandbacks filters out entries with no real worktree (worktreePath:'-')" || bad "reconcile should filter dash-worktree entries"

# ── Case 1 (structural backstop): state.blocked must not exist as a reassignable/pushable field
#    in relay-loop.js at all — it is fully retired in favour of state.surfaced (per-round view)
#    + state.handbacks (persistent accumulator, never reassigned). ─────────────────────────────
blocked_assignments=$(grep -cE '^\s*state\.blocked\s*=' "$JS" || true)
[[ "$blocked_assignments" -eq 0 ]] && ok "state.blocked is never assigned in relay-loop.js (retired)" || bad "state.blocked still assigned $blocked_assignments time(s) — the reassignment bug is still reachable"

blocked_pushes=$(grep -cE 'state\.blocked\.push\(' "$JS" || true)
[[ "$blocked_pushes" -eq 0 ]] && ok "no handback site pushes into state.blocked" || bad "$blocked_pushes handback site(s) still push into state.blocked instead of the persistent accumulator"

# ── Case 2 (structural backstop): all 5 known handback push sites target state.handbacks.push( ─
handbacks_pushes=$(grep -cE 'state\.handbacks\.push\(' "$JS" || true)
[[ "$handbacks_pushes" -ge 5 ]] && ok "state.handbacks.push( appears at >=5 sites ($handbacks_pushes found)" || bad "expected >=5 state.handbacks.push( sites, found $handbacks_pushes"

if grep -qE 'handbacks\s*:\s*\[\]' "$JS"; then ok "state init declares handbacks: []"; else bad "relay-loop.js state init missing a handbacks: [] field"; fi

# ── Case 3 (structural backstop): the loud invariant assertion is wired before return ──────────
grep -q "assertHandbackInvariant" "$JS" || bad "relay-loop.js does not call assertHandbackInvariant before return"
grep -qi "INVARIANT VIOLATED" "$JS" || bad "relay-loop.js does not log an INVARIANT VIOLATED line on a trip"
grep -q "reconcileHandbacks" "$JS" || bad "relay-loop.js does not derive the returned handbacks via reconcileHandbacks"
grep -q "buildSurfacedView" "$JS" || bad "relay-loop.js does not rebuild the per-round surfaced view via buildSurfacedView"
grep -q "handbackInvariantViolations" "$JS" || bad "relay-loop.js does not include invariant violations in the returned summary object"

echo "test_relay_loop_handback_summary: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
