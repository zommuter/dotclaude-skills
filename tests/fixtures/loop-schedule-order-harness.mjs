// Dispatch-ORDER harness for relay-loop.js (id:5c05).
//
// Sibling of loop-round-exec-harness.mjs — same stub-globals sandbox technique, but instead of
// asserting "every prompt builder was reached" it records the ORDER in which the round makes its
// per-unit dispatch decisions, so a scheduling change can be pinned behaviourally rather than by
// grepping source text.
//
// The pool is forced to ONE lane (args.POOL_WIDTH = 1) so the parallel wave dispatches strictly
// in comparator order and the recorded sequence is unambiguous.
//
// Usage: node loop-schedule-order-harness.mjs <path-to-relay-loop.js> <intensive|default>
// Prints:  ORDER: <verdict>:<repo>,<verdict>:<repo>,...
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const SRC = process.argv[2]
const MODE = process.argv[3] || 'default'
if (!SRC || !fs.existsSync(SRC)) {
  console.error('usage: node loop-schedule-order-harness.mjs <relay-loop.js> <intensive|default>')
  process.exit(2)
}
if (MODE !== 'intensive' && MODE !== 'default') {
  console.error(`unknown mode '${MODE}' (expected 'intensive' or 'default')`)
  process.exit(2)
}

let code = fs.readFileSync(SRC, 'utf8')
code = code.replace(/^export\s+const\s+meta/m, 'const meta')
code = `globalThis.__reproResult = (async () => {\n${code}\n})()\n`

let thunkThrew = false
const order = []

globalThis.log = (...a) => { if (process.env.HARNESS_DEBUG) console.error(...a) }
globalThis.phase = () => {}
globalThis.budget = { total: null, spent: () => 0, remaining: () => Infinity }
globalThis.workflow = async () => ({})
// STRONG_TIER=opus + afk: both are preconditions of the HARD-execute apex gate (id:7986/da51),
// so a `hard` unit is dispatchable in BOTH modes. The ONLY difference between the two runs is
// allowIntensive — which is exactly the axis id:5c05 scopes its change to.
globalThis.args = {
  STRONG_TIER: 'opus',
  interactive: false,
  fableDown: false,
  allowIntensive: MODE === 'intensive',
  afk: true,
  once: true,
  POOL_WIDTH: 1,
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

const CHILD = /^(execute|review|hard|handoff):([A-Za-z0-9_-]+)/

// The four seed units. Deliberately listed in an order that matches NEITHER expected
// schedule, so a green result cannot come from the harness handing the loop a pre-sorted list.
//   alpha  — routine [ROUTINE] execute work
//   gamma  — a [HARD] unit (open_hard_pool:1 clears the id:9973 deterministic demote guard)
//   delta  — an [INTENSIVE] unit (partitioned out of the sort, serial run-alone phase)
//   beta   — a review unit (the D3 anti-gaming rung: review outranks fresh strong work)
const SEED_UNITS = [
  { verdict: 'execute', repo: 'alpha', path: '/tmp/harness/alpha', reason: 'routine execute unit', lastCkpt: '', income: true, intensive: '' },
  { verdict: 'hard', repo: 'gamma', path: '/tmp/harness/gamma', reason: 'hard unit', lastCkpt: '', income: true, intensive: '', open_hard_pool: 1 },
  { verdict: 'execute', repo: 'delta', path: '/tmp/harness/delta', reason: 'intensive unit', lastCkpt: '', income: true, intensive: 'localllm' },
  { verdict: 'review', repo: 'beta', path: '/tmp/harness/beta', reason: 'review unit', lastCkpt: '', income: true, intensive: '' },
]

globalThis.agent = async (prompt, opts = {}) => {
  const label = opts.label || ''

  if (label.includes('discover-prelude')) {
    return {
      runId: 'relay-order-harness-0001', ts: '2026-09-01T00:00:00Z',
      repos: [
        { repo: 'alpha', path: '/tmp/harness/alpha', income: true },
        { repo: 'beta', path: '/tmp/harness/beta', income: true },
        { repo: 'gamma', path: '/tmp/harness/gamma', income: true },
        { repo: 'delta', path: '/tmp/harness/delta', income: true },
      ],
      skippedConfig: [], liveClaimRepos: [], injectedUnits: [], signatures: [], stopRequested: false,
    }
  }
  if (label.startsWith('discover-run')) {
    // The loop CHUNKS the repo list and calls this shard once per chunk, so a stub that
    // returned all four units every time would emit each unit N times (duplicates that the
    // id:dc5b one-unit-per-repo defer and the id:365b circuit breaker then mangle). Answer
    // only for the repos this chunk's prompt actually names.
    return {
      units: SEED_UNITS.filter(u => String(prompt).includes(u.path)),
      surfaced: [], skipped: [],
    }
  }
  if (label.startsWith('quota:')) {
    return { exitCode: 0, buckets: [{ bucket: 'seven_day', pctRemaining: 95, resetTime: '2026-09-08T12:00:00Z' }] }
  }
  if (label.startsWith('integrate:')) {
    return { merged: true, ckptTag: 'relay-ckpt-harness', pushStatus: 'pushed', ts: '2026-09-01T00:00:01Z', postSig: '', openRoutine: 0, openHard: 0 }
  }
  if (label.startsWith('provision:')) {
    return 'PROVISION-OK /tmp/harness/wt-' + label.slice('provision:'.length)
  }
  if (label === 'inject-take') return { units: [] }
  if (label === 'auto-reconcile-restart') return 'no dead run, skipped'

  const m = CHILD.exec(label)
  if (m) {
    order.push(`${m[1]}:${m[2]}`)
    const base = {
      contract_met: true, branch: `relay/harness-${m[2]}`, worktree: `/tmp/harness/wt-${m[2]}`,
      summary: 'harness child done', review_me_count: 0, diary_fragment: 'harness',
      handback: '', routine_open: 0, worked_ids: [],
    }
    if (m[1] === 'review') return { ...base, verified_green: [], gaming_flags: [], reopened: [] }
    return base
  }

  return { contract_met: false, branch: '', worktree: '', summary: '', ok: true, units: [] }
}

const tmp = path.join(os.tmpdir(), `relay-loop-order-harness-${process.pid}-${MODE}.mjs`)
fs.writeFileSync(tmp, code)
try {
  await import('file://' + tmp)
  await globalThis.__reproResult
} catch (e) {
  console.error('TOP-LEVEL THROW: ' + (e && e.stack ? e.stack : e))
  process.exit(1)
} finally {
  try { fs.unlinkSync(tmp) } catch (_) {}
}

if (thunkThrew) { console.error('FAIL: a parallel() thunk threw at runtime'); process.exit(1) }

console.log(`ORDER: ${order.join(',')}`)
process.exit(0)
