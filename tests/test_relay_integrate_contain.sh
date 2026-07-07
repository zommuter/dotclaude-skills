#!/usr/bin/env bash
# Defect-fix test (no roadmap item, id:efaf). EXECUTES relay-loop.js through one full round to a
# THROWING integrator agent and asserts the whole workflow still RESOLVES (unit recorded blocked)
# instead of a single integration failure crashing the entire pool.
#
# The burn (2026-07-07): an unescaped `-c` inline span in the integrator prompt template threw
# "c is not defined" out of integrate(); integrate() had no try/catch around its `await
# agent(integrator, {schema})`, so the raw rejecting promise landed in `debts` and the
# end-of-round `await Promise.all(debts)` rejected → the ENTIRE 27-min, 51-agent run died,
# stranding ~10 in-flight worktrees. The `-c` typo is guarded by test_workflow_template_lint.sh
# (2c); THIS test guards the CONTAINMENT (id:efaf) so that ANY future integrate() failure — for
# any reason, not just a backtick — degrades to one recoverable per-unit handback, never a
# pool-wide crash. Proven RED without the .catch (workflow rejects), GREEN with it.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
HARNESS="$ROOT/tests/fixtures/integrate-contain-harness.mjs"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]]      || fail "relay-loop.js not found"
[[ -f "$HARNESS" ]] || fail "integrate-contain-harness.mjs not found"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

node --check "$JS" || fail "relay-loop.js fails node --check"

out="$(node "$HARNESS" "$JS" 2>&1)"; rc=$?
if [[ $rc -ne 0 ]]; then
  fail "a throwing integrator crashed the whole workflow (uncontained integration failure):
$out"
fi
echo "$out" | grep -q '^OK:' || fail "containment harness did not report success:
$out"
pass "relay-loop.js contains a throwing integrator to one per-unit handback (no pool-wide crash)"
