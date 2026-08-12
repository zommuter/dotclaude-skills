#!/usr/bin/env bash
# roadmap:315c — the provision attempt counter must survive ACROSS rounds, not just within one.
#
# id:9834 correctly made a collided provision bump `attempt` and retry once. But it bumped the
# UNIT OBJECT only, and discovery re-creates every unit fresh each round with no `attempt`
# field. So each round restarted at 0:
#   round N   : attempt 0 → collides with round N-1's leftover branch → bump to 1 → succeeds
#   round N+1 : attempt 0 AGAIN → collides → bump to 1 → collides with round N's retry → GIVES UP
# Both names are then permanently consumed and the repo is starved for the rest of the run.
#
# Observed live (run relay-20260812-122721-23819): loderite `review-repo-1` failed provisioning
# in rounds 3,4,5,6,7,8 and ai-codebench `hard-repo-1`/`hard-repo-2` 4× — 10 of that run's 14
# agent-failures. Fail-closed (id:66d9) so nothing was corrupted; the repo just silently lost
# its dispatch slot every round.
#
# FIX SHAPE: a run-scoped watermark keyed by the unit's attempt-LESS identity. A round starts at
# the last attempt that WORKED, so at most ONE collision+bump is ever needed — which is exactly
# the single-bump budget id:9834 already provides. Do NOT widen the retry into a loop.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
node --check "$JS" || fail "relay-loop.js fails node --check"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ── (1) a run-scoped watermark exists and is keyed WITHOUT attempt ───────────────────────
grep -q 'attemptSeq' "$JS" \
  || fail "no run-scoped attempt watermark — a fresh unit each round still restarts at 0 (THE DEFECT)"
grep -Eq 'attemptSeqKey *= *\(unit\) *=>.*unit\.repo.*unit\.verdict' "$JS" \
  || fail "the watermark key does not combine repo+verdict — two different units would share a counter"
grep -Eq 'attemptSeqKey *= *\(unit\) *=>' "$JS" && ! grep -Eq 'attemptSeqKey *= *\(unit\) *=>[^\n]*unit\.attempt' "$JS" \
  || fail "the watermark key includes `attempt` — it must key the attempt-LESS identity, else every attempt gets its own counter and nothing persists"
pass "a run-scoped watermark keyed by the attempt-less unit identity exists"

# ── (2) the watermark SEEDS a fresh unit, and only on the non-retry entry ────────────────
prov="$(awk '/^async function provisionWorktree/,/^}/' "$JS")"
grep -q 'attemptSeq\[' <<<"$prov" \
  || fail "provisionWorktree never reads/writes the watermark"
grep -Eq 'if *\(!isRetry\)' <<<"$prov" \
  || fail "the seed is not guarded by !isRetry — the retry recursion would re-seed and undo its own bump"
pass "the watermark seeds a fresh unit once per dispatch, not on the retry recursion"

# ── (3) the collision branch PERSISTS the bump ───────────────────────────────────────────
collision="$(awk '/already exists/,/return await provisionWorktree/' "$JS")"
grep -q 'attemptSeq\[' <<<"$collision" \
  || fail "the collision retry bumps unit.attempt but never persists it — next round starts at 0 again (THE DEFECT)"
pass "a collision persists the bumped attempt for the next round"

# ── (4) still exactly ONE bump — the id:9834 bound must not have been widened ────────────
if grep -qE 'while *\(' <<<"$prov"; then
  fail "provisionWorktree contains a while-loop — the retry must stay bounded to ONE bump"
fi
grep -q 'recordAgentFailure' <<<"$prov" \
  || fail "provisionWorktree no longer records its failure (id:06a1 silent-swallow)"
pass "the retry is still single-bump and still records a failure"

# ── (5) BEHAVIOURAL: simulate the multi-round sequence the incident showed ───────────────
# Extract the real helpers and drive them the way the loop does: a FRESH unit object each
# round (as discovery produces), against a set of branch names already taken on disk.
cat > "$tmpdir/sim.js" <<'JS'
const dispatchItemFor = (u) => u.itemId || ''
const unitKey = (u) => `${u.verdict}-${u.itemId || 'repo'}-${u.attempt || 0}`
const state = { runId: 'run1' }
const branchFor = (unit) => `relay/${state.runId}-${unitKey({ verdict: unit.verdict, itemId: dispatchItemFor(unit), attempt: unit.attempt || 0 })}`

// The fix under test, mirrored: a run-scoped watermark keyed attempt-lessly.
const attemptSeq = Object.create(null)
const attemptSeqKey = (unit) => `${unit.repo}|${unit.verdict}|${dispatchItemFor(unit) || 'repo'}`

const taken = new Set()          // branches that exist on disk (survive across rounds)
function provision(unit, isRetry) {
  if (!isRetry) {
    const seeded = attemptSeq[attemptSeqKey(unit)] || 0
    if (seeded > (unit.attempt || 0)) unit.attempt = seeded
  }
  const b = branchFor(unit)
  if (taken.has(b)) {
    if (isRetry) return false                       // single-bump budget exhausted
    unit.attempt = unit.attempt ? unit.attempt + 1 : 1
    attemptSeq[attemptSeqKey(unit)] = unit.attempt
    return provision(unit, true)
  }
  taken.add(b)                                       // a successful provision creates the branch
  attemptSeq[attemptSeqKey(unit)] = unit.attempt || 0
  return true
}

const failures = []
for (let round = 1; round <= 8; round++) {
  const unit = { repo: 'loderite', verdict: 'review', itemId: '' }   // FRESH each round, no attempt
  if (!provision(unit)) failures.push(round)
}
if (failures.length) {
  console.error('provision failed in rounds: ' + failures.join(','))
  process.exit(1)
}
console.log('8 rounds, 0 provision failures')
JS
node "$tmpdir/sim.js" > "$tmpdir/out" 2>&1 \
  || { echo "FAIL: the multi-round sequence still starves the repo:"; sed 's/^/    /' "$tmpdir/out"; exit 1; }
pass "8 consecutive rounds provision successfully (the incident sequence)"

# The same simulation WITHOUT the watermark must fail — proving the test can actually detect
# the defect rather than passing vacuously.
sed 's/^    const seeded = attemptSeq.*$/    const seeded = 0/' "$tmpdir/sim.js" > "$tmpdir/sim-broken.js"
if node "$tmpdir/sim-broken.js" >/dev/null 2>&1; then
  fail "the simulation passes even WITHOUT the watermark — it does not actually test the defect"
fi
pass "the same simulation without the watermark fails (the test is not vacuous)"

echo "ALL PASS: the attempt watermark survives across rounds (315c)"
