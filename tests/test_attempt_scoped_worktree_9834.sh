#!/usr/bin/env bash
# roadmap:9834 — a retried unit must not collide with its own prior attempt's branch.
#
# RED SPEC authored at handoff 2026-08-12.
#
# PREMISE CORRECTION, recorded because the item text got it wrong and an executor would
# otherwise rewrite working code: the names are ALREADY attempt-scoped. `unitKey` is
# `${verdict}-${itemId||'repo'}-${attempt||0}` (relay-loop.js:~2098) and both
# worktreePathFor/branchFor (:2110/:2111) pass `attempt: unit.attempt || 0` into it. The naming
# machinery is CORRECT and must not be touched.
#
# THE ACTUAL GAP: nothing ever INCREMENTS `attempt`. A re-dispatched unit is a fresh object from
# discovery with no `attempt` field, so it renames to `…-0` every time. Round 2 therefore asks
# `git worktree add -b <the same branch>` and dies with "a branch named ... already exists".
#
# Observed, run relay-20260812-001727-5554 / linguistic-universals: round 1 parked its worktree
# (id:76d2), rounds 2 and 3 failed provisioning with exactly that fatal, then the id:365b circuit
# breaker skipped the repo — three dispatches on a structurally impossible provision.
#
# NOT a regression from id:66d9: before fail-closed, round 2 dispatched a child into a
# NON-EXISTENT worktree. The corrected gate turned silent corruption into an honest refusal and
# exposed that retry-after-defer was never viable.
#
# FIX SHAPE: on a provision failure whose body reports the branch/worktree already exists, bump
# the unit's attempt ONCE and re-provision under the fresh name. Exactly one bump — an unbounded
# retry loop would spin against a genuinely broken repo.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ── (1) the naming machinery must remain attempt-scoped (guard against a "fix" that removes it) ──
grep -q 'attempt: unit.attempt || 0' "$JS" \
  || fail "worktreePathFor/branchFor no longer thread `attempt` into unitKey — the working half was broken"
grep -Eq 'unitKey = \(u\) =>.*u\.attempt' "$JS" \
  || fail "unitKey no longer encodes attempt — retries would collide by construction"
pass "unitKey + the name builders still encode attempt (unchanged, correct half)"

# ── (2) a collision-shaped provision body is RECOGNISED ────────────────────────────────────
# The real body from the incident, verbatim from RELAY_STATUS.md.
BODY='MECH-ERROR exit=255 Preparing worktree (new branch '"'"'relay/relay-20260812-001727-5554-execute-4d35-0'"'"') fatal: a branch named '"'"'relay/relay-20260812-001727-5554-execute-4d35-0'"'"' already exists'
grep -qiE "already exists" "$JS" \
  || fail "relay-loop.js never recognises an 'already exists' provision failure — it cannot distinguish a retryable collision from a real error"
pass "an 'already exists' provision failure is recognised as its own case"

# ── (3) the retry BUMPS attempt exactly once ───────────────────────────────────────────────
grep -Eq "attempt[^)]*\+ *1|\+\+ *attempt|attempt: *\(?[a-zA-Z_.]*attempt[^)]*\+ *1" "$JS" \
  || fail "nothing increments `attempt` anywhere — a retried unit still renames to -0 and collides (THE DEFECT)"
pass "a retry increments attempt"

# Bound it: the retry must not be able to loop unboundedly.
prov="$(awk '/^async function provisionWorktree/,/^}/' "$JS")"
run="$(awk '/^async function runUnit/,0' "$JS" | head -80)"
if grep -qE "while *\(" <<<"$prov"; then
  fail "provisionWorktree contains a while-loop — the retry must be bounded to ONE bump, not a spin"
fi
pass "the retry is not an unbounded loop"

# ── (4) the bumped unit actually produces DIFFERENT names ──────────────────────────────────
awk '/^const unitKey/'            "$JS" >  "$tmpdir/names.js"
grep -q 'const unitKey' "$tmpdir/names.js" || fail "could not extract unitKey from relay-loop.js"
cat >> "$tmpdir/names.js" <<'JS'
const bad = []
const k0 = unitKey({ verdict: 'execute', itemId: '4d35', attempt: 0 })
const k1 = unitKey({ verdict: 'execute', itemId: '4d35', attempt: 1 })
if (k0 === k1) bad.push('unitKey collides across attempts: ' + k0)
if (!/-0$/.test(k0)) bad.push('attempt 0 key changed shape (existing on-disk worktrees/branches would be orphaned): ' + k0)
// A missing attempt must behave exactly as 0 — older queue entries must not rename.
if (unitKey({ verdict: 'execute', itemId: '4d35' }) !== k0) bad.push('a unit with no attempt field does not match attempt 0')
if (bad.length) { bad.forEach(b => console.error('  ' + b)); process.exit(1) }
JS
node "$tmpdir/names.js" >"$tmpdir/out" 2>&1 \
  || { echo "FAIL: attempt does not separate unit names:"; sed 's/^/    /' "$tmpdir/out"; exit 1; }
pass "attempt 1 yields a distinct key; attempt 0 keeps its current shape"

# ── (5) the failure is still RECORDED when the retry also fails (no silent swallow) ────────
grep -q "recordAgentFailure" <<<"$prov" \
  || fail "provisionWorktree no longer records its failure — the retry must not swallow the id:06a1 signal"
pass "a failed retry is still recorded as an agent failure"

echo "ALL PASS: a retried unit gets a fresh worktree + branch (9834)"
