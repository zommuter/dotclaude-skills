#!/usr/bin/env bash
# roadmap:c563 — relay-loop.js integrate(): verify no Sonnet agent is spawned for
# no-op/handback cases (null report or contract_met=false), and that genuine merges
# (contract_met=true) always reach the Sonnet agent. Static structural checks only —
# live integration throughput is out of scope per task scope (high blast-radius guard).
#
# Findings from id:c563 investigation + meeting 2026-06-17-0812:
#
#   PART 1 — "skip no-op integrates" lever does NOT exist:
#   - integrate() has TWO early-return guards before the agent() call (lines 940-958)
#   - !report → pushes to state.handbacks, returns without spawning any LLM agent
#   - !report.contract_met → pushes to state.handbacks, returns without spawning any LLM agent
#   - The Sonnet agent() call is only reachable when contract_met === true
#   - Event-log evidence (relay-events.jsonl, 2026-06-16): 168 dispatches → 119 merges
#     (integrate events, Sonnet ran + merged=true) + 8 handbacks (Sonnet ran + merged=false,
#     i.e. conflict at merge step) + 41 silent early-returns (null/contract_met=false, no Sonnet)
#   - No wasteful Sonnet agents: 100% of spawned integrators had work to attempt
#   - No safe skip exists: conflict detection requires attempting the merge (no prior knowledge)
#   Verdict (part 1): CLOSED — lever does not exist. 127/168 Sonnet integrators were genuine;
#   41 were already correctly early-returned without spawning an agent.
#
#   PART 2 — batching is infeasible (sequential cross-round dependency):
#   - Per-repo integrations are one-per-round; each branch is built on the prior round's ckpt.
#   - Empirical span (2026-06-16): up to 8 integrations for one repo in one run, spanning
#     a median ~100 min (max 3.5 h) — one per round, NOT co-ready in the same wave.
#   - Intra-repo batching: impossible — later work physically descends from earlier checkpoints.
#   - Cross-repo batching: the only co-ready window (repos A/B/C/D finishing the same wave),
#     but would reverse the line-465 parallel-per-repo design (serialized integrator made "the
#     pool LOOK 1-wide") and worsen conflict recovery (failure atom becomes a wave, not a repo)
#     to save *sonnet* tokens — and the integrator is a rounding error vs Opus ($1317/76% of
#     spend). Safety locus: the integrator is the single-owner-merge-to-canonical locus (D5/D6).
#   - Re-open trigger: only if a future change makes multiple same-repo units co-ready in one
#     wave (e.g. injections id:fb75/6e9d dispatching several same-repo executes simultaneously).
#     Today discovery picks one verdict per repo per round, so this cannot occur.
#   Verdict (part 2): CLOSED — no viable batching lever. Cross-repo parallel design (line 465)
#   must be preserved.
#
# Combined verdict: id:c563 CLOSED. All levers exhausted. See meeting note:
#   docs/meeting-notes/2026-06-17-0812-relay-integrator-batching-close.md

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"

# ── (1) Early-return guard: !report path exits before any agent() call ─────────
# The integrate() function must short-circuit immediately when report is falsy
# (child failed/skipped): the blocked push happens FIRST, then a bare return.
# If this guard is removed, every null-child case would spawn a Sonnet agent.
grep -q "if (!report)" "$JS" || fail "integrate() missing the !report early-return guard"
# Verify the guard returns (or is a bare early-return block, not a conditional agent spawn)
# We check that the first agent() call in integrate() comes AFTER both guards
python3 - "$JS" <<'PYEOF'
import sys, re
src = open(sys.argv[1]).read()
# Find the integrate function body
m = re.search(r'async function integrate\(unit, report\) \{(.*?)^async function', src, re.DOTALL | re.MULTILINE)
if not m:
    print("FAIL: could not locate integrate() function body"); sys.exit(1)
body = m.group(1)
# Both early-return guards must appear before the first agent() call
pos_null_guard    = body.find('if (!report)')
pos_contract_guard = body.find('if (!report.contract_met)')
pos_agent_call    = body.find('const result = await agent(')
if pos_null_guard < 0:
    print("FAIL: !report guard not found inside integrate()"); sys.exit(1)
if pos_contract_guard < 0:
    print("FAIL: !report.contract_met guard not found inside integrate()"); sys.exit(1)
if pos_agent_call < 0:
    print("FAIL: agent() call not found inside integrate()"); sys.exit(1)
if not (pos_null_guard < pos_agent_call):
    print(f"FAIL: !report guard ({pos_null_guard}) does not precede agent() call ({pos_agent_call})"); sys.exit(1)
if not (pos_contract_guard < pos_agent_call):
    print(f"FAIL: !report.contract_met guard ({pos_contract_guard}) does not precede agent() call ({pos_agent_call})"); sys.exit(1)
print("PASS: both early-return guards precede the agent() call in integrate()")
PYEOF
pass "!report and !report.contract_met guards precede the Sonnet agent() call"

# ── (2) The Sonnet agent in integrate() is pinned to 'sonnet' ─────────────────
# The integrator is logic-dense (merge, tag, push, toml write) — must not inherit
# the session model. D2 decision: integrator stays sonnet (Haiku-fail risk for
# logic-dense tasks). Verify the agent() call in integrate() carries model:'sonnet'.
grep -qF "{ label: \`integrate:\${unit.repo}\`, phase: 'Integrate', schema: INTEGRATE_SCHEMA, model: 'sonnet' }" "$JS" \
  || fail "integrate() Sonnet agent not pinned to model:'sonnet' (D2: must not downgrade)"
pass "integrate() Sonnet agent pinned to model:'sonnet' (D2 invariant)"

# ── (3) Early-return paths push to state.handbacks (recoverable handback) ────────
# Both !report and !report.contract_met must push a blocked entry so the caller
# surfaces the repo as a recoverable handback, not a silent loss.
python3 - "$JS" <<'PYEOF'
import sys, re
src = open(sys.argv[1]).read()
m = re.search(r'async function integrate\(unit, report\) \{(.*?)^async function', src, re.DOTALL | re.MULTILINE)
if not m:
    print("FAIL: could not locate integrate() body"); sys.exit(1)
body = m.group(1)

# Null-report guard block: between 'if (!report)' and the next closing brace+return
null_guard_pos = body.find('if (!report) {')
contract_guard_pos = body.find('if (!report.contract_met)')
agent_pos = body.find('const result = await agent(')

# Both blocks before the agent call should contain state.handbacks.push
pre_agent = body[:agent_pos]
blocked_count = pre_agent.count('state.handbacks.push(')
if blocked_count < 2:
    print(f"FAIL: expected ≥2 state.handbacks.push() calls before the agent() call, found {blocked_count}"); sys.exit(1)
print(f"PASS: {blocked_count} state.handbacks.push() calls in early-return guards (both paths recorded)")
PYEOF
pass "early-return guards both push recoverable blocked entries to state.handbacks"

# ── (4) enqueueIntegration always enqueues (even for non-merge outcomes) ───────
# The enqueueIntegration call in runUnit is unconditional — it wraps the full
# integrate() function including its early-return guards. The guards inside
# integrate() prevent agent spawn, but the queue entry is still created.
# This is correct: the serialization chain must always advance its tail promise
# so subsequent same-repo integrations don't stall behind a missing link.
grep -qE "enqueueIntegration\(unit\.repo, \(\) => integrate\(unit, report\)\)" "$JS" \
  || fail "enqueueIntegration call wrapping integrate() not found in runUnit"
pass "enqueueIntegration unconditionally wraps integrate() (chain always advances)"

# ── (4b) CONTAINMENT (id:efaf): the enqueued promise pushed into `debts` MUST be .catch-wrapped
# so a single integrate() throw becomes a per-unit handback, never a pool-wide crash via the
# end-of-round `await Promise.all(debts)` (the 2026-07-07 `-c` incident stranded ~10 worktrees).
grep -qE "enqueueIntegration\(unit\.repo, \(\) => integrate\(unit, report\)\)\.catch\(" "$JS" \
  || fail "the debts-enqueued integrate() promise is NOT .catch-contained (id:efaf) — one integration failure can crash the whole pool"
grep -q "integrator threw (contained id:efaf)" "$JS" \
  || fail "containment .catch does not record a recoverable handback (must surface, not swallow)"
pass "(4b) integrate() rejection is contained to a per-unit handback (id:efaf), never a pool crash"

# ── (5) integrate() agent is only reached for contract_met=true ────────────────
# No alternative agent() call in integrate() before the result variable.
python3 - "$JS" <<'PYEOF'
import sys, re
src = open(sys.argv[1]).read()
m = re.search(r'async function integrate\(unit, report\) \{(.*?)^async function', src, re.DOTALL | re.MULTILINE)
if not m:
    print("FAIL: could not locate integrate() body"); sys.exit(1)
body = m.group(1)
agent_pos = body.find('const result = await agent(')
pre_agent = body[:agent_pos]
# No agent() call should appear before the guarded agent call
pre_agent_calls = len(re.findall(r'\bawait agent\(', pre_agent))
if pre_agent_calls > 0:
    print(f"FAIL: found {pre_agent_calls} premature await agent() call(s) before the guarded integrate agent"); sys.exit(1)
print("PASS: no agent() call before the contract_met=true guard — no premature agent spawns")
PYEOF
pass "no premature agent() call in integrate() before contract_met guard"

# ── (6) Handback-from-Sonnet (merged=false) is correctly recorded ─────────────
# When the Sonnet agent runs but returns merged=false (e.g. merge conflict), the
# result is pushed to state.handbacks with the reason. This path exists and must
# remain (it's the post-integrator conflict path, unavoidable — the merge must be
# attempted to detect conflicts).
grep -q "const reason = (result && result.reason) || 'integration failed'" "$JS" \
  || fail "post-integrator merged=false handback path missing"
pass "post-Sonnet merged=false handback path present (unavoidable merge-conflict case)"

# ── (7) Batching is NOT implemented ──────────────────────────────────────────
# id:c563 closed 2026-06-17: batching is infeasible (sequential cross-round dependency)
# and cross-repo batching would reverse the line-465 parallel-per-repo latency fix.
# Assert enqueueIntegration still serializes per-repo (one-at-a-time) and no batch
# variant exists.
grep -q "function enqueueIntegration(repo, fn)" "$JS" \
  || fail "enqueueIntegration signature changed — verify batching was not accidentally introduced"
if grep -qE "function batchIntegrat|batchIntegration" "$JS"; then
  fail "batching logic found in relay-loop.js — cross-repo batching reverses line-465 parallel design (id:c563 closed)"
fi
pass "batching NOT implemented — enqueueIntegration still serializes one unit at a time per repo (correct)"

# ── (8) Cross-repo parallel-per-repo design preserved (id:c563 D2 — do NOT collapse) ─
# The integrationChains Map keys separate promise chains per repo; cross-repo integration
# is intentionally parallel (comment at line 465: "serialized integrator made the pool
# LOOK 1-wide"). This must not be collapsed into a single serialized chain or a multi-repo
# batch agent. Check that the Map and the parallel design are still present.
grep -q "const integrationChains = new Map()" "$JS" \
  || fail "integrationChains Map not found — cross-repo parallel design may have been removed (id:c563 D2)"
# The Map must be keyed by repo name (not a single shared queue)
grep -q "integrationChains.get(repo)" "$JS" \
  || fail "integrationChains not keyed per repo — parallel isolation may be broken (id:c563 D2)"
# No single global integration queue replacing the per-repo chains
if grep -qE "globalIntegrationQueue|singleIntegrationChain|integrationQueue" "$JS"; then
  fail "global integration queue found — would serialize cross-repo integrations (id:c563 D2: must stay parallel per repo)"
fi
pass "cross-repo parallel-per-repo design intact — integrationChains keyed per repo (id:c563 D2)"

echo "ALL PASS: integrator no-op guard + parallel-design invariant (id:c563 closed)"
