#!/usr/bin/env bash
# roadmap:ec8a — dispatch bookkeeping must not fire before provisioning succeeds.
#
# RED SPEC authored at handoff 2026-08-11. relay-loop.js:2840-2849 does unitsDispatched++,
# totalDispatched++, state.inFlight.push(...) and pushEvent('dispatch', ...) — but provisioning
# is at :2867 and its handback returns at :2873. A unit that never dispatched is therefore
# counted as dispatched and rendered as in-flight. This is why the incident run
# (relay-20260811-221747-12629) emitted a dispatch event for a unit whose worktree did not exist,
# while `grep -c "provisionWorktree failed" relay-events.jsonl` was 0.
#
# Source-shape assertions only: relay-loop.js is Workflow-sandbox JS with no importable surface
# and no hermetic runner (the same limitation test_parent_creates_worktree_34b7.sh documents).
# We assert ORDER of statements within runUnit(), which is what the defect is.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"

# Work within runUnit() only — the file has other dispatch-ish lines elsewhere. Take from the
# runUnit declaration to the end of file; every statement we check lives in its first ~60 lines,
# and the ORDER comparison is unaffected by a generous tail.
body="$(awk '/^async function runUnit/,0' "$JS")"
[[ -n "$body" ]] || fail "could not locate runUnit() in relay-loop.js"

# NOTE: `|| true` is required — a grep miss returns 1, and under `set -e` a bare command
# substitution assignment would abort the whole test SILENTLY (exit 1, no output). The
# not-found case is handled explicitly by each caller instead.
line_of() { grep -n -F -- "$1" <<<"$body" | head -1 | cut -d: -f1 || true; }

prov="$(line_of 'await provisionWorktree(' || true)"
guard="$(line_of 'if (!provisioned)' || true)"
[[ -n "$prov" && -n "$guard" ]] || fail "provisionWorktree call / !provisioned guard not found in runUnit()"

for stmt in 'unitsDispatched++' 'totalDispatched++' 'state.inFlight.push(' "pushEvent('dispatch'"; do
  ln="$(line_of "$stmt" || true)"
  [[ -n "$ln" ]] || fail "statement '$stmt' not found in runUnit() — did it move out of the function?"
  [[ "$ln" -gt "$guard" ]] \
    || fail "'$stmt' (line $ln of runUnit) fires BEFORE the !provisioned guard (line $guard) — a unit that never dispatched is counted/rendered as dispatched"
done
pass "all four dispatch-bookkeeping statements fire AFTER the provisioning guard"

# The guard must still return early — moving bookkeeping is only safe if the failure path exits.
after_guard="$(awk -v g="$guard" 'NR>g && NR<=g+6' <<<"$body")"
grep -q "return" <<<"$after_guard" || fail "the !provisioned branch no longer returns early"
pass "the !provisioned branch still returns early"

# id:34b7's handback must survive the reorder — a provisioning failure stays VISIBLE.
grep -q "state.handbacks.push" <<<"$body" || fail "the provisioning handback push was lost in the reorder"
grep -q "provisionWorktree failed" "$JS" || fail "the provisionWorktree failure event/log text was lost"
pass "the provisioning failure still records a handback and an event"

# Both readers of unitsDispatched must still see it (the MAX_UNITS cap and takeInjections'
# short-circuit) — moving the increment must not orphan either.
grep -q "unitsDispatched >= MAX_UNITS" "$JS" || fail "the MAX_UNITS cap no longer reads unitsDispatched"
pass "unitsDispatched is still read by the MAX_UNITS cap"

echo "ALL PASS: dispatch bookkeeping follows successful provisioning (ec8a)"
