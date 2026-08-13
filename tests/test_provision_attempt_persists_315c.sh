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

# SECTIONS 1-4 ARE SOURCE-SHAPE GUARDS, NOT BEHAVIOURAL ASSERTIONS (id:3a50). They grep
# relay-loop.js and would stay green against code whose fix is functionally disabled — that is
# exactly the defect id:3a50 records. They are kept only as cheap "the fix was not deleted /
# not widened into a loop" tripwires. The behavioural claim is carried by section 5, which
# EXTRACTS AND RUNS the real relay-loop.js source of provisionWorktree.

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

# ── (5) BEHAVIOURAL: run the REAL relay-loop.js provisionWorktree over 8 rounds ──────────
#
# This section previously wrote a hand-copied COPY of the fix into a sim.js and ran THAT
# (id:3a50): production `provisionWorktree` was never executed, and the vacuity guard mutated
# the copy, so the whole section proved only that the copy was self-consistent. Mutation-tested
# 2026-08-13: `if (false && seeded > (unit.attempt || 0)) unit.attempt = seeded` in
# relay-loop.js still yielded ALL PASS.
#
# It now EXTRACTS THE REAL SOURCE REGION out of relay/scripts/relay-loop.js — unitKey,
# worktreePathFor, branchFor, attemptSeq/attemptSeqKey and the whole `async function
# provisionWorktree` body, verbatim — evaluates it in a `vm` context, and drives it exactly as
# the loop does: a FRESH unit object per round (as discovery produces, with no `attempt`
# field), against branch names that persist on "disk" across rounds. relay-loop.js is a
# Workflow script that cannot be `require`d (no module.exports, closes over engine globals),
# so textual extraction is the same mechanism tests/test_unit_identity_key_923b.sh already
# uses for unitKey.
#
# WHAT THIS COVERS: the real seed/bump/persist logic of the shipped provisionWorktree, its
# real branch-name derivation, its single-bump bound, and its fail-closed PROVISION-OK check.
# WHAT IT DOES NOT COVER (honest limits): the `agent()` hop, provision-worktree.sh itself, and
# git are STUBBED — the stub only decides "this branch name is already taken" and returns the
# real `fatal: a branch named … already exists` / `PROVISION-OK` strings; `dispatchItemFor`,
# `log`, `recordAgentFailure`, `state` and `MECH_MODEL` are stubs too. So this proves the
# watermark logic in the shipped file, NOT that a real worktree gets created on disk.
# The extraction fails LOUDLY if the markers move, rather than silently testing nothing.
cat > "$tmpdir/drive.mjs" <<'MJS'
import fs from 'node:fs'
import vm from 'node:vm'

const [file, mutation = 'none'] = process.argv.slice(2)
const src = fs.readFileSync(file, 'utf8')
const die = (m) => { console.error('EXTRACT-FAIL: ' + m); process.exit(2) }

// --- extract the REAL source spans -------------------------------------------------------
const lines = src.split('\n')
const oneLine = (re, what) => {
  const hits = lines.filter((l) => re.test(l))
  if (hits.length !== 1) die(`expected exactly 1 line matching ${what}, found ${hits.length}`)
  return hits[0]
}
const unitKeyLine   = oneLine(/^const unitKey = \(/, 'const unitKey =')
const worktreeLine  = oneLine(/^const worktreePathFor = \(/, 'const worktreePathFor =')
const branchLine    = oneLine(/^const branchFor = \(/, 'const branchFor =')
const seqLine       = oneLine(/^const attemptSeq = /, 'const attemptSeq =')
const seqKeyLine    = oneLine(/^const attemptSeqKey = /, 'const attemptSeqKey =')

const startIdx = src.indexOf('\nasync function provisionWorktree(')
if (startIdx < 0) die('no top-level `async function provisionWorktree(` in ' + file)
const endIdx = src.indexOf('\n}\n', startIdx)
if (endIdx < 0) die('could not find the closing brace of provisionWorktree')
let prov = src.slice(startIdx + 1, endIdx + 3)
if (!/return true\s*\n\}/.test(prov)) die('extracted provisionWorktree does not end in `return true }` — extraction is wrong')

// --- MUTATIONS applied to the REAL source (this is what makes the test non-vacuous) -------
const mutate = (text, re, replacement, what) => {
  const hits = text.split('\n').filter((l) => re.test(l))
  if (hits.length !== 1) die(`mutation "${what}": expected exactly 1 matching line, found ${hits.length} — the implementation moved, re-derive this test`)
  return text.split('\n').map((l) => (re.test(l) ? replacement : l)).join('\n')
}
if (mutation === 'seed') {
  // neuter the seed, keeping every identifier the sections 1-4 greps look for
  prov = mutate(prov, /unit\.attempt = seeded/, '    // MUTATED: seed disabled', 'seed')
} else if (mutation === 'persist') {
  prov = mutate(prov, /attemptSeq\[attemptSeqKey\(unit\)\] *= *[^|]*$/, '      // MUTATED: bump not persisted', 'persist')
} else if (mutation !== 'none') {
  die('unknown mutation ' + mutation)
}

const region = [unitKeyLine, worktreeLine, branchLine, seqLine, seqKeyLine, prov].join('\n')

// --- stubs (see the honest-limits note in the test file) ----------------------------------
const taken = new Set()      // branch names that exist on "disk"; they survive across rounds
const paths = new Set()
let agentCalls = 0
const sandbox = {
  console,
  state: { runId: 'relay-20260101-000000-1234' },
  MECH_MODEL: 'bash',
  dispatchItemFor: (u) => u.inject_item || '',        // STUB of the real ledger-reading helper
  log: () => {},
  failures: [],
  recordAgentFailure: (...a) => { sandbox.failures.push(a) },
  agent: async (prompt) => {
    agentCalls++
    const m = /provision-worktree\.sh\s+(\S+)\s+(\S+)\s+(\S+)/.exec(String(prompt))
    if (!m) { console.error('STUB-FAIL: provisionWorktree did not invoke provision-worktree.sh with 3 args'); process.exit(2) }
    const [, , wt, branch] = m
    if (taken.has(branch)) return `fatal: a branch named '${branch}' already exists`
    taken.add(branch); paths.add(wt)
    return 'PROVISION-OK'
  },
}
sandbox.globalThis = sandbox
vm.createContext(sandbox)
vm.runInContext(region, sandbox, { filename: 'relay-loop-region.js' })
if (typeof sandbox.provisionWorktree !== 'function') die('provisionWorktree did not evaluate to a function')

// --- drive the incident sequence: 8 rounds, a FRESH unit each round ------------------------
const failedRounds = []
const perRoundCalls = []
for (let round = 1; round <= 8; round++) {
  const before = agentCalls
  const unit = { repo: 'loderite', verdict: 'review', path: '/fixture/loderite' }  // no `attempt`
  const ok = await sandbox.provisionWorktree(unit)
  perRoundCalls.push(agentCalls - before)
  if (!ok) failedRounds.push(round)
}
if (failedRounds.length) {
  console.error('provision failed in rounds: ' + failedRounds.join(',') + ' (agent calls/round: ' + perRoundCalls.join(',') + ')')
  process.exit(1)
}
const worst = Math.max(...perRoundCalls)
if (worst > 2) {
  console.error('a round needed ' + worst + ' provision attempts — the id:9834 single-bump bound was widened')
  process.exit(1)
}
if (taken.size !== 8) { console.error('expected 8 distinct branches, got ' + taken.size); process.exit(1) }
if (paths.size !== 8) { console.error('expected 8 distinct worktree paths, got ' + paths.size); process.exit(1) }
console.log('8 rounds, 0 provision failures, max ' + worst + ' attempts in any round')
MJS

node "$tmpdir/drive.mjs" "$JS" > "$tmpdir/out" 2>&1 \
  || { echo "FAIL: the REAL provisionWorktree still starves the repo across rounds:"; sed 's/^/    /' "$tmpdir/out"; exit 1; }
pass "8 consecutive rounds provision successfully against the real relay-loop.js source ($(cat "$tmpdir/out"))"

# MUTATION GUARD — mutate the REAL source region (not a copy of it) and require a FAIL.
# `seed` reproduces the exact mutation that fooled the old section 5; `persist` kills the
# cross-round write. An EXTRACT-FAIL (exit 2) is itself a failure: it means the mutation no
# longer matched, so the guard would have been proving nothing.
for m in seed persist; do
  if node "$tmpdir/drive.mjs" "$JS" "$m" > "$tmpdir/mut" 2>&1; then
    fail "mutation '$m' of the REAL relay-loop.js source still passed — this test is vacuous"
  fi
  if grep -q 'EXTRACT-FAIL\|STUB-FAIL' "$tmpdir/mut"; then
    sed 's/^/    /' "$tmpdir/mut"
    fail "mutation '$m' failed for the WRONG reason (extraction/stub broke, not the behaviour)"
  fi
  pass "mutating the real source ('$m') makes this test FAIL — it is not vacuous"
done

echo "ALL PASS: the attempt watermark survives across rounds (315c)"
