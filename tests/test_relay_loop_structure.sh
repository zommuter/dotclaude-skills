#!/usr/bin/env bash
# roadmap:83c9 — relay-loop.js priority-mixed autonomous pool: static structure checks.
# Integration-behaviour tests are deferred to the id:1ad7 pilot (live integration is
# too expensive for unit tests) — this file pins the structural invariants from
# meeting D2/D3/D5: pool shape, serialized integrator, quota gate, graceful drain.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/fables-turn/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
pass "relay-loop.js exists"

# (1) meta block present with required fields
grep -q "export const meta" "$JS" || fail "relay-loop.js missing 'export const meta'"
grep -q "name: 'relay-loop'" "$JS" || fail "meta block missing name: 'relay-loop'"
grep -q "phases:" "$JS" || fail "meta block missing phases"
pass "meta block present with name and phases"

# (2) Unattended invariant: the Workflow never prompts
if grep -q "AskUserQuestion" "$JS"; then
  fail "relay-loop.js must never call AskUserQuestion (unattended Workflow, D2)"
fi
pass "no AskUserQuestion call"

# (3) Serialized integrator (D5/D6 discipline: one push per repo, never concurrent)
grep -q "enqueueIntegration" "$JS" || fail "missing enqueueIntegration serializer"
pass "integration serializer (enqueueIntegration) present"

grep -q -- "--no-ff" "$JS" || fail "integrator does not document/perform --no-ff merge"
grep -q "ckpt-tag.sh" "$JS" || fail "integrator does not call ckpt-tag.sh"
grep -q -- "git-lock-push.sh --ff-only" "$JS" || fail "integrator does not push via git-lock-push.sh --ff-only"
pass "integrator chain: --no-ff merge, ckpt-tag.sh, git-lock-push.sh --ff-only"

# No bare parallel() over the integration step
if grep -E "parallel\(.*[Ii]ntegrat" "$JS" | grep -qv "^\s*//"; then
  fail "integration step appears inside a parallel() call (must be serialized)"
fi
pass "no parallel() over the integration step"

# (4) STRONG_TIER referenced (tier dispatch, D4)
grep -q "STRONG_TIER" "$JS" || fail "relay-loop.js does not reference STRONG_TIER"
pass "STRONG_TIER referenced"

# (5) Per-repo classifier with all four verdicts (D3)
for verdict in execute review handoff idle; do
  grep -q "'$verdict'" "$JS" || fail "classifier verdict '$verdict' not referenced"
done
pass "classifier verdicts execute/review/handoff/idle present"

# Priority mixing: execute first, review above handoff (D3 policy invariant)
grep -q "PRIORITY" "$JS" || fail "no PRIORITY ordering for unit dispatch"
pass "PRIORITY dispatch ordering present"

# Income preference: income repos win slot contention within a class (user 2026-06-12)
grep -q "income" "$JS" || fail "no income-preference key in unit ordering"
pass "income preference present in scheduler"

# (6) Pool width: default 5, overridable via args.POOL_WIDTH (D3)
grep -q "POOL_WIDTH = A.POOL_WIDTH || 5" "$JS" || fail "POOL_WIDTH not configurable (expected 'A.POOL_WIDTH || 5')"
pass "POOL_WIDTH configurable (default 5)"

# (7) Quota gate is tier-aware and uses the id:9934 helper (D5)
grep -q "quota-stop.sh" "$JS" || fail "quota-stop.sh helper not referenced"
grep -qF -- '--tier ${tier}' "$JS" || fail "quota gate does not pass a per-unit tier"
grep -qF -- "'sonnet' : 'strong'" "$JS" || fail "tier derivation (execute→sonnet, else strong) missing"
pass "tier-aware quota-stop gate present"

# (8) Graceful drain: in-flight + integration debt finish before return (D5)
grep -qi "drain" "$JS" || fail "no graceful-drain handling"
pass "graceful drain present"

# (9) RELAY_STATUS writer is actually invoked, not just defined (id:80e2 wiring)
grep -q "await writeRelayStatus(" "$JS" || fail "writeRelayStatus is defined but never awaited"
pass "writeRelayStatus invoked"

# (10) Structured output: child reports and classifier use schemas (no text parsing)
grep -q "schema:" "$JS" || fail "no schema-typed agent() calls (structured output required)"
pass "schema-typed agent() calls present"

# (11) API-error failsafe: child dispatch is wrapped in try/catch (no orphaned worktrees)
grep -q "try {" "$JS" || fail "child agent() dispatch not wrapped in try/catch"
grep -q "function resumePrompt" "$JS" || fail "no resumePrompt (auto-resume) defined"
grep -q "auto-resuming handoff" "$JS" || fail "no auto-resume dispatch for failed handoff"
pass "API-error failsafe: try/catch + handoff auto-resume present"

# (12) Failed-child handback is recoverable: records the real deterministic worktree
#      path (the legitimate worktreePath:'-' on line ~367 is for *surfaced* repos that
#      were never dispatched, so we assert the positive, not the absence of '-').
grep -q "worktreePath: worktreePathFor(unit)" "$JS" || fail "null-report handback does not record the real worktree path"
pass "failed-child handback records recoverable worktree path"

# (13) Review→execute chaining: review with open [ROUTINE] re-enqueues an execute unit
grep -q "routine_open: { type: 'number' }" "$JS" || fail "REPORT_SCHEMA missing routine_open"
grep -q "unit.verdict === 'review' && report && report.contract_met" "$JS" || fail "no review→execute re-enqueue guard"
grep -q "verdict: 'execute'" "$JS" || fail "re-enqueue does not push an execute unit"
pass "review→execute re-enqueue present"

# (14) No intra-pool ping-pong: the re-enqueue is guarded so an execute never re-chains
grep -q "!unit.rechained" "$JS" || fail "re-enqueue lacks the rechained ping-pong guard"
grep -q "rechained: true" "$JS" || fail "re-enqueued unit not marked rechained"
pass "review→execute re-enqueue is single-hop (no ping-pong)"
