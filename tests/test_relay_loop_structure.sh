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

# (1b) id:7d1e — finer-grained progress buckets: work units route to per-verdict phases
# (Execute/Review/Hard/Handoff) instead of one crowded "Dispatch" group; support agents
# (quota/release/inject) go to "Support". Lock the routing so it can't silently collapse back.
grep -q "phase: unitPhase(unit.verdict)" "$JS" \
  || fail "id:7d1e: work unit agent must route to a per-verdict phase (phase: unitPhase(unit.verdict))"
for p in Execute Review Hard Handoff Support; do
  grep -qE "title: '$p'" "$JS" || fail "id:7d1e: meta.phases missing the '$p' bucket"
done
grep -qE "phase: 'Dispatch'" "$JS" \
  && fail "id:7d1e: no agent should still use the monolithic 'Dispatch' phase"
pass "id:7d1e: per-verdict + Support progress buckets wired"

# (1c) id:e107 — executor-actionable guard: a [ROUTINE] item that is @manual/human-only must
# be excluded from the execute verdict, so a repo whose only open [ROUTINE] items are all
# @manual does NOT get an executor dispatched every round (the no-op checkpoint thrash loop).
# The old LLM discovery prompt's guard was mechanized into classify-repo.sh's --emit unit mode.
CLASSIFY="$SRC_DIR/relay/scripts/classify-repo.sh"
[[ -f "$CLASSIFY" ]] || fail "classify-repo.sh not found at $CLASSIFY"
grep -q "@manual" "$CLASSIFY" \
  || fail "id:e107: classify-repo.sh missing the @manual human-only exclusion"
grep -q "HUMAN_GATES" "$CLASSIFY" \
  || fail "id:e107: classify-repo.sh missing the HUMAN_GATES human-only exclusion set"
pass "id:e107: @manual/human-only [ROUTINE] excluded from the execute verdict (classify-repo.sh)"

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

# id:087b RELOCATION — the integrator chain moved from relay-loop.js's LLM prompt into
# relay/scripts/integrate.sh, dispatched from here as ONE mechanical relay-mech hop. The
# per-repo serialization above is unchanged (it still wraps integrate()); only the chain's
# implementation moved, so the chain assertions read integrate.sh and the dispatch is
# asserted here.
INTEG="$SRC_DIR/relay/scripts/integrate.sh"
[[ -x "$INTEG" ]] || fail "integrate.sh not found/executable — the integrator chain has no home"
grep -q 'relay/scripts/integrate.sh' "$JS" || fail "relay-loop.js does not dispatch integrate.sh"
grep -q -- "--no-ff" "$INTEG" || fail "integrator does not document/perform --no-ff merge"
grep -q "ckpt-tag.sh" "$INTEG" || fail "integrator does not call ckpt-tag.sh"
# id:4d44 — the push argv is now BUILT (`push_args=(--ff-only "$path")`, plus `--remote NAME`
# per selected remote) instead of being one literal invocation, because a SUBSTANTIVE unit
# pushes only its PRIVATE/LAN remotes. Both halves of the contract still hold and are still
# asserted: the push goes through $GIT_LOCK_PUSH, and it is --ff-only.
grep -qE -- 'push_args=\(--ff-only' "$INTEG" || fail "integrator does not build a --ff-only push invocation"
grep -qE -- 'GIT_LOCK_PUSH" "\$\{push_args\[@\]\}"' "$INTEG" || fail "integrator does not push via git-lock-push.sh"
pass "integrator chain: --no-ff merge, ckpt-tag.sh, git-lock-push.sh --ff-only (in integrate.sh, dispatched from relay-loop.js)"

# (3b) id:087b — the integrator dispatch must be MECHANICAL, never an LLM agent. A
# `model: 'sonnet'`/'haiku'/'opus' integrate dispatch would put an LLM back on the
# merge-to-main critical path, which is exactly what this item removed.
if grep -qvE "model: MECH_MODEL" < <(grep -nE "label: \`integrate:\\\$\{unit\.repo\}\`" "$JS") ; then
  fail "id:087b: the integrate dispatch is not model: MECH_MODEL — an LLM is back on the merge-to-main path"
fi
grep -qE "label: \`integrate:\\\$\{unit\.repo\}\`, phase: 'Integrate', model: MECH_MODEL" "$JS" \
  || fail "id:087b: no mechanical (MECH_MODEL) integrate dispatch found in relay-loop.js"
pass "id:087b: the integrator is dispatched mechanically (MECH_MODEL), not as an LLM agent"

# No bare parallel() over the integration step
if grep -qv "^\s*//" < <(grep -E "parallel\(.*[Ii]ntegrat" "$JS") ; then
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

# (13) Review→execute AND execute→execute chaining (id:cc90): a review OR an execute unit
#      with open [ROUTINE] work re-enqueues an execute unit, bounded by a depth counter.
grep -q "routine_open: { type: 'number' }" "$JS" || fail "REPORT_SCHEMA missing routine_open"
grep -q "unit.verdict === 'review' || unit.verdict === 'execute'" "$JS" || fail "no review/execute→execute re-enqueue guard (id:cc90)"
grep -q "verdict: 'execute'" "$JS" || fail "re-enqueue does not push an execute unit"
pass "review/execute→execute re-enqueue present"

# (14) No unbounded ping-pong: the re-enqueue is bounded by a chainDepth counter (id:cc90 —
#      replaces the old one-shot !unit.rechained boolean, which could not bound a multi-hop chain).
grep -q "unit.chainDepth || 0) < MAX_CHAIN_DEPTH" "$JS" || fail "re-enqueue lacks the chainDepth bound guard (id:cc90)"
grep -q "chainDepth = (unit.chainDepth || 0) + 1" "$JS" || fail "re-enqueued unit does not carry an incremented chainDepth (id:cc90)"
pass "review/execute→execute re-enqueue is depth-bounded (no unbounded ping-pong)"

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
# id:a615 added a THIRD guard — userStopMidRound — because the operator STOP sentinel is now
# consumed at a dispatch decision INSIDE the round (a chaining round never reaches the round
# boundary where the prelude used to read it), so the lanes must stop pulling on it too.
grep -q "while (!quotaStopped && !roundCapHit && !userStopMidRound)" "$JS" || fail "lane loop missing quotaStopped/roundCapHit/userStopMidRound guard"
grep -q "if (!queue.length)" "$JS" || fail "lane loop missing queue-drain branch (id:6e9d injection poll)"
# state + quotaStopped must be module-level accumulators (declared before runRound), not reset per round
grep -q "^let quotaStopped = false" "$JS" || fail "quotaStopped not a cross-round accumulator"
pass "per-round cap distinct from run-ending quotaStopped"

# ── (18) HARD-execute verdict (id:da26): Opus-apex one-item HARD work ──────────────

# 'hard' is in the DISCOVER_SCHEMA verdict enum, alongside an openHard count field.
# id:5eb3: 'human' was added to the enum (surface-only verdict, rank 5).
# id:7616: 'mechanical' was added to the enum (pool-inert MECHANICAL-only backlog, rank 6) so
# classify-verdict.sh's mechanical verdict validates against the shard schema (round-trip).
grep -qF "verdict: { enum: ['execute', 'review', 'hard', 'handoff', 'human', 'mechanical', 'idle'] }" "$JS" \
  || fail "DISCOVER_SCHEMA verdict enum missing 'hard'/'human'/'mechanical'"
grep -q "openHard:" "$JS" || fail "DISCOVER_SCHEMA missing openHard count"
pass "hard verdict + openHard count in DISCOVER_SCHEMA"

# PRIORITY ordering: execute < review < hard < handoff < human < mechanical
# (id:5eb3: human=5; id:7616: mechanical=6, pool-inert, matches classify-verdict.sh priority_rank).
grep -qF "const PRIORITY = { execute: 0, review: 1, hard: 2, handoff: 3, human: 5, mechanical: 6 }" "$JS" \
  || fail "PRIORITY ordering not exactly execute:0 review:1 hard:2 handoff:3 human:5 mechanical:6"
pass "PRIORITY ranks hard after execute+review, before handoff; human < mechanical (pool-inert) lowest"

# Apex + --afk gate (id:7986/da51): hard units are dropped/deferred unless BOTH
# STRONG_TIER is apex ('opus') AND the run was launched --afk. The gate is the extractable
# enforceApexGate (relay/scripts/apex-gate.mjs) — it must be wired in by NAME (not just any
# STRONG_MODEL-keyed conditional: a model-id comparison here IS the da51 regression, since
# bumping the pin would silently change dispatch) and it must be fed the boolean STRONG_TIER
# check plus AFK, never a raw model-id comparison.
grep -qF "const { plan: gatedActionable, hardDeferred } = enforceApexGate(actionable, { strongTier: STRONG_TIER, afk: AFK })" "$JS" \
  || fail "no apex+afk gate call wiring enforceApexGate(actionable, { strongTier: STRONG_TIER, afk: AFK })"
grep -qE "STRONG_MODEL\s*(!==|===)\s*'claude-opus" "$JS" \
  && fail "hard gate still compares STRONG_MODEL to a model-id literal (da51 regression) — must ask STRONG_TIER === 'opus' instead"
grep -q "hardDeferred" "$JS" || fail "no hardDeferred surface for non-apex/non-afk hard units"
pass "hard dispatch gated on apex Opus AND --afk via enforceApexGate (id:7986/da51); non-apex/non-afk hard surfaced as deferred, gate is model-id-blind"

# Sonnet-never-HARD: hard maps to the 'strong' tier, never 'sonnet'. The tier derivation
# sends only verdict==='execute' to sonnet; everything else (incl. hard) to strong.
grep -qF "const tier = unit.verdict === 'execute' ? 'sonnet' : 'strong'" "$JS" \
  || fail "tier derivation does not keep non-execute (incl. hard) off the sonnet tier"
# and the model override only pins sonnet for execute — hard gets STRONG_MODEL. Since id:10dc
# the mapping is resolved ONCE into `unitModel`, above the prompt-size gate (which is keyed off
# the resolved model, not the verdict), and `opts.model` reuses it — so there is exactly one
# copy of verdict→model and the gate can never size a unit against a tier it is not run on.
grep -qF "const unitModel = unit.verdict === 'execute' ? 'sonnet' : STRONG_MODEL" "$JS" \
  || fail "sonnet model override is not execute-only (hard must not run on Sonnet)"
grep -qF "opts.model = unitModel" "$JS" \
  || fail "opts.model no longer reuses the resolved unitModel (a second verdict→model copy can drift)"
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

# id:2d20 + id:d58f — drain keys on per-round SUBSTANTIVE progress (id:d58f tightened id:2d20's
# `produced`-based check): `produced` is still computed from completions this round, but the
# drain detector now keys on `substantive` (execute/hard/handoff checkpoints + reviews that
# reopened/surfaced-routine/flagged) so an all-handback round AND a confirming-only-review round
# both count as no-progress and the loop drains instead of spinning to MAX_ROUNDS.
grep -q "const produced = state.completed.length - completedBefore" "$JS" \
  || fail "id:2d20: runRound does not compute `produced` from completions this round"
grep -q "completedBefore = state.completed.length" "$JS" \
  || fail "id:2d20: missing completedBefore baseline at runRound start"
grep -q "(r.substantive || 0) === 0" "$JS" \
  || fail "id:2d20+d58f: outer loop drain check does not key on r.substantive (the id:d58f refinement of the produced check)"
pass "id:2d20+d58f: drain keys on per-round SUBSTANTIVE progress (not just any checkpoint)"

# id:2d20 — discovery classifier excludes GATED HARD items from the hard verdict + openHard,
# so already-known-gated repos are surfaced (needs /meeting), not re-dispatched every round.
# The gated-item exclusion + openHard narrowing were mechanized into gather-repo-state.sh's
# id:9973 open_hard_pool count (exact "[HARD — pool]" tag match, excludes meeting/hands/
# decision-gate); the surfaced needs-/meeting reason stays in relay-loop.js's demote guard.
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
[[ -f "$GATHER" ]] || fail "gather-repo-state.sh not found at $GATHER"
grep -q "EXECUTABLE-HARD test" "$GATHER" \
  || fail "id:2d20: gather-repo-state.sh missing the EXECUTABLE-HARD test rationale (gated-item exclusion)"
grep -q "HARD backlog is gated" "$JS" \
  || fail "id:2d20: classifier does not surface all-gated-HARD repos with a needs-/meeting reason"
grep -q "tagged EXACTLY" "$GATHER" \
  || fail "id:2d20: openHard count not narrowed to executable items (exact [HARD — pool] tag match)"
pass "id:2d20: classifier excludes gated HARD items (surfaced for /meeting, not dispatched)"

# id:8b1f — a SIZE-OUT/gated refusal must leave the worktree CLEAN (no commit), else the
# handback-note commit strands forever (the integrator never merges a handback). The hard
# unitPrompt must say so explicitly so children stop committing RELAY_LOG handback notes.
grep -q "SIZE-OUT / GATED refusal" "$JS" \
  || fail "id:8b1f: hard unitPrompt does not instruct a clean (no-commit) worktree on a size-out refusal"
grep -q "integrator never merges a handback" "$JS" \
  || fail "id:8b1f: hard unitPrompt does not explain WHY a refusal commit strands (orphan worktree)"
pass "id:8b1f: size-out handback leaves a clean (auto-reapable) worktree — no stranded commit"

# id:4267 — the quota-stop agent-count seatbelt (quota-stop.sh hard-caps at --agents >= 200,
# a runaway-spawn guard spanning the WHOLE self-feeding run) must be fed the RUN-TOTAL count
# (totalDispatched), NOT the per-round unitsDispatched (which resets to 0 each round → with
# MAX_UNITS=20 it never reaches 200, so the seatbelt could never fire across a multi-round run).
grep -qF -- '--agents ${totalDispatched}' "$JS" \
  || fail "id:4267: quota gate does not pass the run-total agent count (--agents \${totalDispatched})"
grep -qF -- '--agents ${unitsDispatched}' "$JS" \
  && fail "id:4267: quota gate still passes the per-round unitsDispatched (resets each round → 200-agent seatbelt never fires)"
pass "id:4267: quota agent-count seatbelt fed the run-total (totalDispatched), not per-round count"

# id:7570 — the cross-session lease must be released in a per-unit FINALLY path that runs
# after the child settles with ANY outcome (merged/handback/null/error), NOT only inside the
# integrator agent. Before this fix, a child that returned null/threw/handed back never reached
# the integrator's step-0 release, so the lease leaked for the full 1800s TTL (observed live
# 2026-06-16). Assert a releaseLease() helper exists, runUnit calls it after the child settles,
# and it carries the id:7570 marker so the rationale can't be silently dropped.
grep -q "async function releaseLease" "$JS" \
  || fail "id:7570: no releaseLease() helper — lease release is still coupled to the integrator only"
grep -q "id:7570" "$JS" \
  || fail "id:7570: no id:7570 marker in relay-loop.js (per-unit finally-release rationale missing)"
grep -q "claim.sh release \${unit.repo} --run \${state.runId}" "$JS" \
  || fail "id:7570: releaseLease does not run-scope release the repo lease"
# runUnit must invoke the finally release after the child settles (not only the integrator).
grep -q "releaseLease(unit)" "$JS" \
  || fail "id:7570: runUnit never calls releaseLease(unit) — leaked-lease fix not wired"
# Steal-window guard: a same-repo review→execute re-chain must NOT release in the gap before
# the re-chain re-acquires (the re-entrant claim window).
grep -q "rechainedSameRepo" "$JS" \
  || fail "id:7570: no re-chain guard — releasing before a same-repo re-acquire opens a steal window"
grep -q "if (!rechainedSameRepo) await releaseLease(unit)" "$JS" \
  || fail "id:7570: finally-release not guarded by the re-chain flag (steal-window risk)"
pass "id:7570: per-unit finally release (run-scoped, re-chain-guarded) frees a leaked lease"

# id:7570 — the integrator's step-0 release stays (idempotent vs. the per-unit release) so a
# merged unit still releases even if the per-unit path somehow didn't (defense in depth).
# id:087b RELOCATION — step 0 now lives in integrate.sh as an executed command rather than a
# prompt instruction; the defense-in-depth invariant is unchanged.
grep -qE '"\$CLAIM" release "\$repo" --run "\$run"' "$INTEG" \
  || fail "id:7570: integrator step-0 lease release was removed (must stay idempotent)"
grep -q "step 0: lease-release" "$INTEG" \
  || fail "id:7570: integrator step-0 lease release is no longer identified as step 0 (ordering rationale lost)"
pass "id:7570: integrator step-0 release retained (idempotent, defense-in-depth)"

# id:7570 — long-child liveness: the work child anchors its claim to the held worktree so a
# >TTL child isn't stolen mid-work (claim.sh worktree-anchored staleness, converse of id:3ac8).
grep -qF -- 'claim.sh acquire ${unit.repo} --run ${state.runId} --mode ${unit.verdict} --worktree' "$JS" \
  || fail "id:7570: unitPrompt does not pass --worktree to the acquire (long-child liveness anchor missing)"
pass "id:7570: work child anchors its lease to the worktree (long child keeps its lease)"

# id:000d — deterministic is_finished demote guard (anti-false-handoff).
# When is_finished is true the repo is NEVER dispatched as execute/hard/handoff — it goes
# to surfaced. This prevents the pool from burning strong/opus dispatches on already-finished
# repos (incident 2026-06-23: recurheb/echoAI/collaib all-ticked ROADMAPs still got handoff).
grep -q "id:000d" "$JS" \
  || fail "id:000d: no id:000d marker in relay-loop.js (is_finished guard rationale missing)"
# The old shard-prompt instruction was mechanized: gather-repo-state.sh now computes
# is_finished deterministically (no LLM judgment needed).
grep -q "id:000d — deterministic is_finished guard" "$SRC_DIR/relay/scripts/gather-repo-state.sh" \
  || fail "id:000d: gather-repo-state.sh missing the deterministic is_finished guard"
grep -q "is_finished demote" "$JS" \
  || fail "id:000d: no JS-side is_finished demote block in relay-loop.js"
grep -q "FINISHED_DEMOTE_VERDICTS" "$JS" \
  || fail "id:000d: JS-side demote guard does not define FINISHED_DEMOTE_VERDICTS set"
grep -q "finished repo (0 open items, clean, no unaudited commits)" "$JS" \
  || fail "id:000d: demoted unit does not carry the canonical finished-repo surfaced reason"
grep -q "anti-false-handoff guard id:000d" "$JS" \
  || fail "id:000d: surfaced reason does not cite the guard id (id:000d)"
# The guard must be demote-only: review verdict must NOT be in the demoted set.
grep -qF "new Set(['execute', 'hard', 'handoff'])" "$JS" \
  || fail "id:000d: FINISHED_DEMOTE_VERDICTS must be exactly {execute, hard, handoff} — review is unaffected"
# id:401c Run 45 — the JS-side guard reads u.is_finished, so the value must actually REACH
# the unit: (a) the DISCOVER_SCHEMA must declare is_finished as a unit property (else the
# validated unit drops it), and (b) classify-repo.sh's --emit unit mode must copy it verbatim
# from gather (the old shard-prompt instruction was mechanized). Without BOTH, u.is_finished
# is always undefined and the deterministic backstop is DEAD code.
grep -q "is_finished: { type: 'boolean' }" "$JS" \
  || fail "id:401c: DISCOVER_SCHEMA does not declare unit.is_finished — the JS-side guard's u.is_finished is always undefined (dead guard)"
grep -q '"is_finished": bool(base.get("is_finished"' "$SRC_DIR/relay/scripts/classify-repo.sh" \
  || fail "id:401c: classify-repo.sh does not copy is_finished onto the unit — the deterministic value never reaches the JS guard"
pass "id:000d/401c: is_finished demote guard present + the deterministic value actually reaches the unit (schema + classify-repo.sh)"

# id:5c00 — quota PRE-GATE before the per-round discovery fan-out
# (Incident 2026-06-25: 5 shard agents ~94k tokens spent before the quota-stop gate fired post-sharding)
grep -q "id:5c00" "$JS" \
  || fail "id:5c00: no PRE-GATE marker in relay-loop.js"
grep -q "quota PRE-GATE" "$JS" \
  || fail "id:5c00: quota PRE-GATE comment missing in relay-loop.js"
# Assert ordering: the PRE-GATE (id:5c00) appears BEFORE 'discover-prelude' in runRound()
python3 - "$JS" <<'PYEOF'
import sys
js = open(sys.argv[1]).read()
rr = js.find('async function runRound()')
if rr < 0: sys.exit('no runRound() found')
body = js[rr:]
gate = body.find('id:5c00')
prelude = body.find("'discover-prelude'")
if gate < 0: sys.exit('no id:5c00 marker inside runRound()')
if prelude < 0: sys.exit("no 'discover-prelude' inside runRound()")
if gate > prelude: sys.exit('id:5c00 PRE-GATE appears AFTER discover-prelude in runRound — ordering wrong (shard agents still fire before quota check)')
PYEOF
pass "id:5c00: quota PRE-GATE precedes discover-prelude in runRound (no wasted shard agents on a quota-stop round)"

# id:4860 — discovery-queue verdict/state coherence: the CASE A queue copy is content-addressed
# (queue_sig == live sig) with a JS-side mangle canary that DROPS+surfaces any sig-mismatched
# queue-sourced unit and gates the discoverCache write on the match (fixes stale-cache poisoning).
grep -q "id:4860" "$JS" \
  || fail "id:4860: no id:4860 marker in relay-loop.js (discovery-queue sig canary missing)"
# (a) the schema must declare unit.queue_sig, else the validated CASE A unit drops it and the
#     canary's u.queue_sig is always undefined (dead guard, mirrors the id:401c is_finished lesson).
grep -q "queue_sig: { type: 'string' }" "$JS" \
  || fail "id:4860: DISCOVER_SCHEMA does not declare unit.queue_sig — the canary's u.queue_sig is always undefined (dead guard)"
# (b) the chunk JSON carries each repo's LIVE sig so the runner can content-address the copy.
grep -Eq "sig: sigByRepo\[r\.repo\]" "$JS" \
  || fail "id:4860: chunk does not carry each repo's live sig (sigByRepo) — the runner can't compare queue_sig to the live sig"
# (c) the canary DROPS + SURFACES a sig-mismatched queue unit (never dispatches on stale state).
grep -q "discovery-queue sig canary" "$JS" \
  || fail "id:4860: no 'discovery-queue sig canary' log line"
grep -q "u.queue_sig !== undefined && (u.queue_sig === '' || u.queue_sig !== (sigByRepo\[u.repo\] || ''))" "$JS" \
  || fail "id:4860: canary condition missing/incorrect — must drop queue-sourced (queue_sig-bearing) units whose sig is EMPTY (fail-open sentinel; '' === '' must not pass) or != live sig; CASE B/live units (no queue_sig) exempt"
grep -q "content-addressed mangle canary id:4860" "$JS" \
  || fail "id:4860: dropped unit does not carry the canonical sig-mismatch surfaced reason"
# (d) the canary must run BEFORE the discoverCache write, so a stale verdict can never be cached
#     under the NEW live sig (the stale-cache-poisoning fix). Assert ordering in runRound().
python3 - "$JS" <<'PYEOF'
import sys
js = open(sys.argv[1]).read()
canary = js.find('id:4860 discovery-queue sig canary')
# the discoverCache write for freshly-classified units (the id:c3a6 loop)
cache = js.find('if (sig) state.discoverCache[u.repo] = { sig, unit: u }')
if canary < 0: sys.exit('no id:4860 canary block found')
if cache < 0: sys.exit('no discoverCache write loop found')
if canary > cache: sys.exit('id:4860 sig canary appears AFTER the discoverCache write — a stale verdict could poison the cache before being dropped (ordering wrong)')
PYEOF
pass "id:4860: CASE A queue copy is content-addressed (queue_sig == live sig) with a JS mangle canary that drops+surfaces mismatches and gates the discoverCache write on the match"
