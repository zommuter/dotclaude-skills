#!/usr/bin/env bash
# roadmap:c563 — relay-loop.js integrate(): verify no Sonnet agent is spawned for
# no-op/handback cases (null report or contract_met=false), and that genuine merges
# (contract_met=true) always reach the Sonnet agent. Static structural checks only —
# live integration throughput is out of scope per task scope (high blast-radius guard).
#
# Finding from id:c563 investigation (2026-06-17):
#   - integrate() has TWO early-return guards before the agent() call (lines 940-958)
#   - !report → pushes to state.blocked, returns without spawning any LLM agent
#   - !report.contract_met → pushes to state.blocked, returns without spawning any LLM agent
#   - The Sonnet agent() call is only reachable when contract_met === true
#   - Event-log evidence (relay-events.jsonl, 2026-06-16): 168 dispatches → 119 merges
#     (integrate events, Sonnet ran + merged=true) + 8 handbacks (Sonnet ran + merged=false,
#     i.e. conflict at merge step) + 41 silent early-returns (null/contract_met=false, no Sonnet)
#   - No wasteful Sonnet agents: 100% of spawned integrators had work to attempt
#   - No safe skip exists: conflict detection requires attempting the merge (no prior knowledge)
# Verdict: REPORT ONLY — no safe change implemented; all 127/168 Sonnet integrators were
# genuine merge attempts. The remaining 41 were already correctly early-returned.

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

# ── (3) Early-return paths push to state.blocked (recoverable handback) ────────
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

# Both blocks before the agent call should contain state.blocked.push
pre_agent = body[:agent_pos]
blocked_count = pre_agent.count('state.blocked.push(')
if blocked_count < 2:
    print(f"FAIL: expected ≥2 state.blocked.push() calls before the agent() call, found {blocked_count}"); sys.exit(1)
print(f"PASS: {blocked_count} state.blocked.push() calls in early-return guards (both paths recorded)")
PYEOF
pass "early-return guards both push recoverable blocked entries to state.blocked"

# ── (4) enqueueIntegration always enqueues (even for non-merge outcomes) ───────
# The enqueueIntegration call in runUnit is unconditional — it wraps the full
# integrate() function including its early-return guards. The guards inside
# integrate() prevent agent spawn, but the queue entry is still created.
# This is correct: the serialization chain must always advance its tail promise
# so subsequent same-repo integrations don't stall behind a missing link.
grep -qE "debts\.push\(enqueueIntegration\(unit\.repo,.*integrate\(unit, report\)\)\)" "$JS" \
  || fail "enqueueIntegration call wrapping integrate() not found in runUnit"
pass "enqueueIntegration unconditionally wraps integrate() (chain always advances)"

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
# result is pushed to state.blocked with the reason. This path exists and must
# remain (it's the post-integrator conflict path, unavoidable — the merge must be
# attempted to detect conflicts).
grep -q "const reason = (result && result.reason) || 'integration failed'" "$JS" \
  || fail "post-integrator merged=false handback path missing"
pass "post-Sonnet merged=false handback path present (unavoidable merge-conflict case)"

# ── (7) Batching (id:c563 forward scope) is NOT implemented ───────────────────
# The design note recommends batching as a future item (high blast-radius). Assert
# the enqueueIntegration function still serializes per-repo (one-at-a-time) and
# does NOT batch multiple units before invoking the integrator.
grep -q "function enqueueIntegration(repo, fn)" "$JS" \
  || fail "enqueueIntegration signature changed — check if batching was accidentally introduced"
# No batchIntegrate or similar function should be present yet
if grep -qE "function batchIntegrat|batchIntegration" "$JS"; then
  fail "batching logic found in relay-loop.js — it was NOT supposed to be implemented (high blast-radius)"
fi
pass "batching NOT implemented — enqueueIntegration still serializes one unit at a time (correct)"

echo "ALL PASS: integrator no-op guard (id:c563 investigation)"
