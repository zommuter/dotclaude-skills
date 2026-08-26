// id:a615 — BEHAVIOURAL harness for the dispatch-scoped bound in relay-loop.js.
//
// Unlike the static-structural relay-loop tests, this one EXECUTES the loop in a stubbed
// Workflow sandbox (same technique as loop-round-exec-harness.mjs) and reproduces the exact
// shape of run relay-20260822-154630-17003: ONE round (one discover-prelude call) in which
// the id:8123 chain-end re-ask + the review→execute re-chain keep pushing follow-on units
// into the same round's queue, so `dispatches >> rounds`.
//
// Usage: node dispatch-bound-harness.mjs <relay-loop.js> <mode>
//   unbounded   — no launch cap, MAX_ROUNDS=1: the chaining round runs free (the defect shape)
//   once        — args.once = true: the wave dispatch budget must bound the SAME chaining round
//   stop-at <K> — no cap; the stop-check hop reports stopRequested:true on its Kth call
//   stop-flaky  — the stop-check hop THROWS every time (must not wedge; must not stop)
//   stop-twice  — stop-check reports true forever (a second consume must be harmless)
//   stop-garbage— the stop-check hop returns an unparseable body (must not stop, must not wedge)
//
// Prints one JSON object on stdout:
//   { mode, preludeCalls, dispatches, stopChecks, dispatchLabels, threw }
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const SRC = process.argv[2]
const MODE = process.argv[3] || 'unbounded'
const STOP_AT = Number(process.argv[4] || 0)
if (!SRC || !fs.existsSync(SRC)) { console.error('usage: node dispatch-bound-harness.mjs <relay-loop.js> <mode> [K]'); process.exit(2) }

let code = fs.readFileSync(SRC, 'utf8')
code = code.replace(/^export\s+const\s+meta/m, 'const meta')
code = `globalThis.__reproResult = (async () => {\n${code}\n})()\n`

let thunkThrew = false
let preludeCalls = 0
let stopChecks = 0
const dispatchLabels = []

globalThis.log = () => {}
globalThis.phase = () => {}
globalThis.budget = { total: null, spent: () => 0, remaining: () => Infinity }
globalThis.workflow = async () => ({})

// MAX_ROUNDS = 1 pins the run to a SINGLE round, so every dispatch this harness counts happened
// inside one round — the `round=1` × 14 dispatches shape the item reports. `once` arms the
// id:a615 wave dispatch budget.
globalThis.args = {
  STRONG_TIER: 'opus', interactive: false, fableDown: false, allowIntensive: false, afk: true,
  MAX_ROUNDS: 1,
  ...(MODE === 'once' ? { once: true } : {}),
}

globalThis.parallel = async (thunks) => Promise.all(thunks.map((t, i) =>
  Promise.resolve().then(t).catch((e) => {
    thunkThrew = true
    console.error(`parallel thunk[${i}] THREW: ${e && e.stack ? e.stack : e}`)
    return null
  })))
globalThis.pipeline = async (items, ...stages) => {
  const out = []
  for (let i = 0; i < items.length; i++) {
    let v = items[i]
    try { for (const s of stages) v = await s(v, items[i], i) } catch (_) { v = null }
    out.push(v)
  }
  return out
}

// Every child reports contract_met with routine_open > 0, which is what makes the loop
// re-chain (review/execute → execute) WITHOUT returning to discover-prelude. The chain-end
// re-ask answers `review`, which chains once more. That is the whole defect mechanism.
const childReport = (branch) => ({
  contract_met: true, branch, worktree: '/tmp/a615-harness/wt', summary: 'harness child',
  review_me_count: 0, diary_fragment: 'harness', handback: '', routine_open: 4, worked_ids: [],
  verified_green: [], gaming_flags: [], reopened: [],
})

globalThis.agent = async (_prompt, opts = {}) => {
  const label = opts.label || ''

  if (label.includes('discover-prelude')) {
    preludeCalls++
    return {
      runId: 'relay-a615-harness', ts: '2026-08-26T00:00:00Z',
      repos: [
        { repo: 'alpha', path: '/tmp/a615-harness/alpha', income: true },
        { repo: 'beta', path: '/tmp/a615-harness/beta', income: true },
        { repo: 'gamma', path: '/tmp/a615-harness/gamma', income: true },
      ],
      skippedConfig: [], liveClaimRepos: [], injectedUnits: [], signatures: [], stopRequested: false,
    }
  }
  if (label.startsWith('discover-run')) {
    return {
      units: [
        { verdict: 'execute', repo: 'alpha', path: '/tmp/a615-harness/alpha', reason: 'harness', lastCkpt: '', income: true, intensive: '' },
        { verdict: 'execute', repo: 'beta', path: '/tmp/a615-harness/beta', reason: 'harness', lastCkpt: '', income: true, intensive: '' },
        { verdict: 'execute', repo: 'gamma', path: '/tmp/a615-harness/gamma', reason: 'harness', lastCkpt: '', income: true, intensive: '' },
      ],
      surfaced: [], skipped: [],
    }
  }
  if (label === 'stop-check') {
    stopChecks++
    if (MODE === 'stop-flaky') throw new Error('harness: simulated stop-check agent failure')
    if (MODE === 'stop-twice') return '{"stopRequested":true}'
    if (MODE === 'stop-garbage') return 'MECH-ERROR exit=1\nstop-sentinel.sh: unreadable'
    if (MODE === 'stop-at' && stopChecks >= STOP_AT) return '{"stopRequested":true}'
    return '{"stopRequested":false}'
  }
  // The id:8123 chain-end re-ask: answer `review` so the chain continues past the execute
  // chain — this is what turns one discovered unit into many dispatches in one round.
  if (label.startsWith('chain-end-reask:')) return '{"verdict":"review"}'
  if (label.startsWith('suppress-demote:')) return '{"verdict":"idle"}'
  if (label.startsWith('quota:')) return { exitCode: 0, buckets: [{ bucket: 'seven_day', pctRemaining: 95, resetTime: '2026-09-01T12:00:00Z' }] }
  if (label.startsWith('provision:')) return 'PROVISION-OK /tmp/a615-harness/wt'
  if (label.startsWith('integrate:')) return { merged: true, ckptTag: 'relay-ckpt-a615', pushStatus: 'pushed', ts: '2026-08-26T00:00:01Z', postSig: '', openRoutine: 4, openHard: 0 }
  if (label === 'inject-take') return ''
  if (label === 'auto-reconcile-restart') return 'no dead run, skipped'

  const m = /^(execute|review|handoff|hard):/.exec(label)
  if (m) {
    dispatchLabels.push(label)
    return childReport('relay/a615-' + m[1])
  }
  return { contract_met: false, branch: '', worktree: '', summary: '', ok: true, units: [] }
}

const tmp = path.join(os.tmpdir(), `relay-a615-harness-${process.pid}-${MODE}.mjs`)
fs.writeFileSync(tmp, code)
let threw = ''
try {
  await import('file://' + tmp)
  await globalThis.__reproResult
} catch (e) {
  threw = String(e && e.stack ? e.stack : e)
} finally {
  try { fs.unlinkSync(tmp) } catch (_) {}
}

console.log(JSON.stringify({
  mode: MODE, preludeCalls, dispatches: dispatchLabels.length, stopChecks,
  dispatchLabels, threw, thunkThrew,
}))
process.exit(threw ? 1 : 0)
