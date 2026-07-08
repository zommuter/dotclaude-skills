#!/usr/bin/env bash
# roadmap:aec5 — generalize the discovery-only exec-smoke guard to ALL relay-loop.js inline
# prompt-builder template literals. `test_relay_loop_discovery_exec.sh` EXECUTES only the
# discovery dispatch, so an unescaped-backtick (or any other synchronous runtime fault) in the
# OTHER inline prompt templates — integrate, execute-child, review-child, handoff-child, quota,
# inject-take, auto-reconcile — still ships GREEN (node --check + grep miss a runtime throw; the
# id:5bac/efaf burn class). The id:71f2 static lexer lint (lint-workflow-templates.mjs) already
# covers the BACKTICK sub-case across all templates; this is the EXECUTABLE belt that also catches
# non-backtick runtime faults (a bad `${...}` reference, a mis-shaped tagged template) in the
# builders the discovery-only harness never evaluates.
#
# Contract: a full-round exec harness (tests/fixtures/loop-round-exec-harness.mjs) mirrors the
# Workflow sandbox (same stub-globals technique as discovery-exec-harness.mjs) but feeds the loop
# NON-EMPTY units of each verdict + an injected unit + a quota check, so EVERY prompt-building
# branch is entered and its template literal is actually evaluated. The harness records which
# builders it reached and fails loudly on ANY synchronous throw in a thunk. This test asserts the
# harness runs clean AND reached each named builder.
#
# NOTE (handoff.md D1): there is no live bug in relay-loop.js today, so once the harness exists
# this guard PASSES — it is a regression-guard for the NEXT such runtime fault, not a red spec of
# a present defect. It is RED now only because the harness fixture + coverage do not yet exist.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
HARNESS="$ROOT/tests/fixtures/loop-round-exec-harness.mjs"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

node --check "$JS" || fail "relay-loop.js fails node --check"

[[ -f "$HARNESS" ]] \
  || fail "loop-round-exec-harness.mjs not found — the generalized exec-smoke harness that drives EVERY prompt builder (integrate/execute-child/review-child/handoff-child/quota/inject-take/auto-reconcile) is the id:aec5 deliverable"

out="$(node "$HARNESS" "$JS" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "full-round exec harness reported a synchronous throw in a prompt builder:
$out"

# Every builder the discovery-only harness does NOT exercise must be reached by this one.
for builder in execute-child integrate review-child handoff-child quota inject-take auto-reconcile; do
  echo "$out" | grep -q "BUILT: $builder" \
    || fail "harness never evaluated the '$builder' prompt builder (coverage gap this item closes):
$out"
done
pass "every relay-loop.js prompt builder is evaluated under node with no synchronous throw (id:aec5)"

echo "ALL PASS: full-round exec-smoke over all prompt builders (id:aec5)"
