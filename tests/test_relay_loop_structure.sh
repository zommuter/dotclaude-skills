#!/usr/bin/env bash
# roadmap:83c9 — relay-loop.js priority-mixed autonomous pool: static structure checks.
# Integration-behaviour tests are deferred to the id:1ad7 pilot (live integration is
# too expensive for unit tests) — this file pins the structural invariants from
# meeting D2/D3/D5: pool shape, serialized integrator, quota gate, graceful drain.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

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

# (3) Per-repo serialized integrator (D5/D6 restated, id:bc9d: same-repo serialized to
# preserve review→execute ordering; distinct repos integrate concurrently — distinct remotes
# don't conflict; the bottleneck fix that stopped checkpoints landing ~1-2 min apart)
grep -q "enqueueIntegration" "$JS" || fail "missing enqueueIntegration serializer"
grep -qE "enqueueIntegration\([^,)]+," "$JS" || fail "enqueueIntegration not keyed by repo (per-repo serialization)"
grep -q "integrationChains" "$JS" || fail "missing per-repo integration chain map (integrationChains)"
pass "per-repo integration serializer (enqueueIntegration keyed by repo) present"

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

# (5) Per-repo classifier with all five verdicts (D3 + da26 hard-execute)
for verdict in execute review hard handoff idle; do
  grep -q "'$verdict'" "$JS" || fail "classifier verdict '$verdict' not referenced"
done
pass "classifier verdicts execute/review/hard/handoff/idle present"

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

# (9) RELAY_STATUS writer is actually invoked, not just defined (id:80e2 wiring). Since id:cb50
# the write is OFF the critical path: call sites schedule it (scheduleStatusWrite) and the
# scheduler invokes writeRelayStatus on the serialized tail (see test_relay_status_offcrit.sh).
grep -q "scheduleStatusWrite(state)" "$JS" || fail "RELAY_STATUS writer is never invoked (no scheduleStatusWrite call)"
grep -q "writeRelayStatus(snap" "$JS" || fail "scheduleStatusWrite does not invoke writeRelayStatus on the tail"
pass "writeRelayStatus invoked off-critical-path via scheduleStatusWrite (id:80e2 + id:cb50)"

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

# (15) Self-feeding loop: runRound() + outer while re-discovering until drained/capped
grep -q "async function runRound()" "$JS" || fail "no runRound() — not self-feeding"
grep -q "while (!quotaStopped && round < MAX_ROUNDS)" "$JS" || fail "no outer self-feeding loop"
grep -q "MAX_ROUNDS = A.MAX_ROUNDS" "$JS" || fail "no MAX_ROUNDS seatbelt"
pass "self-feeding outer loop present (runRound + MAX_ROUNDS)"

# (16) Drained termination: two consecutive empty discoveries stop the run
grep -q "dry >= 2" "$JS" || fail "no drained-termination (2 dry rounds)"
pass "drained-termination (2 empty discoveries) present"

# (17) Per-round cap ≠ run-ending stop: MAX_UNITS sets roundCapHit, not quotaStopped
grep -q "roundCapHit = true" "$JS" || fail "MAX_UNITS does not use a per-round flag"
# The lane loop guards on quotaStopped + roundCapHit. Since id:6e9d the queue.length check
# moved INSIDE the loop (a drained lane polls injections before breaking — see
# test_relay_midround_inject.sh), so the while-condition is now (!quotaStopped && !roundCapHit)
# with an `if (!queue.length)` drain/poll/break inside.
grep -q "while (!quotaStopped && !roundCapHit)" "$JS" || fail "lane loop missing quotaStopped/roundCapHit guard"
grep -q "if (!queue.length)" "$JS" || fail "lane loop missing queue-drain branch (id:6e9d injection poll)"
# state + quotaStopped must be module-level accumulators (declared before runRound), not reset per round
grep -q "^let quotaStopped = false" "$JS" || fail "quotaStopped not a cross-round accumulator"
pass "per-round cap distinct from run-ending quotaStopped"

# ── (18) HARD-execute verdict (id:da26): Opus-apex one-item HARD work ──────────────

# 'hard' is in the DISCOVER_SCHEMA verdict enum, alongside an openHard count field.
grep -qF "verdict: { enum: ['execute', 'review', 'hard', 'handoff', 'idle'] }" "$JS" \
  || fail "DISCOVER_SCHEMA verdict enum missing 'hard'"
grep -q "openHard:" "$JS" || fail "DISCOVER_SCHEMA missing openHard count"
pass "hard verdict + openHard count in DISCOVER_SCHEMA"

# PRIORITY ordering: execute < review < hard < handoff (review still beats fresh strong work).
grep -qF "const PRIORITY = { execute: 0, review: 1, hard: 2, handoff: 3 }" "$JS" \
  || fail "PRIORITY ordering not exactly execute:0 review:1 hard:2 handoff:3"
pass "PRIORITY ranks hard after execute+review, before handoff"

# Opus-only gate: hard units are dropped/deferred unless STRONG_MODEL is apex Opus.
grep -qF "if (STRONG_MODEL !== 'claude-opus-4-8') {" "$JS" \
  || fail "no opus-only gate guarding hard dispatch (STRONG_MODEL !== 'claude-opus-4-8')"
grep -q "hardDeferred" "$JS" || fail "no hardDeferred surface for non-apex hard units"
pass "hard dispatch gated on apex Opus (claude-opus-4-8); non-apex hard surfaced as deferred"

# Sonnet-never-HARD: hard maps to the 'strong' tier, never 'sonnet'. The tier derivation
# sends only verdict==='execute' to sonnet; everything else (incl. hard) to strong.
grep -qF "const tier = unit.verdict === 'execute' ? 'sonnet' : 'strong'" "$JS" \
  || fail "tier derivation does not keep non-execute (incl. hard) off the sonnet tier"
# and the model override only pins sonnet for execute — hard gets STRONG_MODEL.
grep -qF "if (unit.verdict === 'execute') opts.model = 'sonnet'" "$JS" \
  || fail "sonnet model override is not execute-only (hard must not run on Sonnet)"
pass "Sonnet-never-HARD: hard runs on the strong tier, never Sonnet"

# Checkpoint label: hard integrates with a strong-execute label carrying fable-standin.
grep -q "strong-execute (\${STRONG_MODEL}\${standInSuffix}, relay-loop)" "$JS" \
  || fail "hard unit does not use the 'strong-execute (...)' checkpoint label"
pass "hard unit checkpoint label is strong-execute (model, fable-standin, relay-loop)"

# refDoc: hard branch reuses handoff.md (its C5 HARD section), no required new ref file.
grep -q "if (verdict === 'hard') return" "$JS" || fail "refDoc has no hard branch"
pass "refDoc has a hard branch (reuses handoff.md C5)"

# ── (19) Gaming-flag logger feed is alive (id:3826 audit finding 2026-06-15) ────────
# logGamingFlags() reads report.gaming_flags / verified_green / reopened, but a review
# child only returns a field if the DISPATCH PROMPT (unitPrompt) asks for it. The prompt
# must request all three for review units, or the logger silently records empty arrays
# forever (dead telemetry — the base-rate signal id:2909 mandated). Guard the contract↔
# consumer link so this contradiction can't reappear.
for field in gaming_flags verified_green reopened; do
  grep -q "$field: report.$field" "$JS" \
    || fail "logGamingFlags does not read report.$field (logger/consumer drift)"
  grep -q "$field" "$JS" || fail "$field never mentioned in relay-loop.js"
done
# The review-unit return contract in unitPrompt must name all three (so the child returns them).
awk "/Return: contract_met/ && /verified_green/ && /gaming_flags/ && /reopened/ {found=1} END{exit found?0:1}" "$JS" \
  || fail "review-unit return contract (unitPrompt) does not request verified_green/gaming_flags/reopened — logGamingFlags would log empty arrays (id:3826 dead-feed)"
pass "review return contract feeds the gaming-flag logger (verified_green/gaming_flags/reopened requested)"
