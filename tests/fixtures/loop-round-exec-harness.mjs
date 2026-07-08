// Full-round executable smoke harness for relay-loop.js (id:aec5, generalizes
// discovery-exec-harness.mjs's stub-globals technique beyond the discovery-only dispatch).
//
// WHY THIS EXISTS: discovery-exec-harness.mjs EXECUTES only the discover-prelude/discover-run
// dispatch — every OTHER inline prompt-builder template (the per-verdict unit dispatch,
// integrate, quota, mid-round inject-take, auto-reconcile-restart) is covered ONLY by
// `node --check` (syntax) + grep (source-text), so a runtime fault (an unescaped backtick, a
// bad `${...}` reference, a mis-shaped tagged template) in any of THOSE templates still ships
// GREEN (the id:5bac/efaf burn class). This harness drives one full self-feeding-loop round
// (bounded to exactly one round via `args.once = true`, i.e. STOP_AFTER_ROUNDS = 1) with a
// stubbed discovery that seeds one unit of EACH of the three pool-dispatchable verdicts
// (execute/review/handoff), so the loop actually reaches and evaluates:
//   - the per-verdict unit-dispatch prompt (unitPrompt(), label `${verdict}:${repo}`)
//   - the quota gate prompt (label `quota:${tier}`)
//   - the serialized integrate prompt (label `integrate:${repo}`)
//   - the mid-round inject-take prompt (label `inject-take`, hit once the queue drains)
//   - the auto-reconcile-on-restart prompt (label `auto-reconcile-restart`, runs once at
//     startup before the round loop)
// A `hard` unit is deliberately NOT seeded — the id:aec5 acceptance list names only
// execute-child/integrate/review-child/handoff-child/quota/inject-take/auto-reconcile (7
// builders), not a hard-child; discovery-exec-harness.mjs's sibling covers discover-run.
//
// Usage: node loop-round-exec-harness.mjs <path-to-relay-loop.js>
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const SRC = process.argv[2]
if (!SRC || !fs.existsSync(SRC)) { console.error('usage: node loop-round-exec-harness.mjs <relay-loop.js>'); process.exit(2) }

let code = fs.readFileSync(SRC, 'utf8')
// Sandbox parity (mirrors discovery-exec-harness.mjs): the harness wraps the whole script
// body in an async IIFE so top-level return/await are legal. Strip the ESM `export` wrapper.
code = code.replace(/^export\s+const\s+meta/m, 'const meta')
code = `globalThis.__reproResult = (async () => {\n${code}\n})()\n`

let thunkThrew = false
const built = new Set()

globalThis.log = () => {}
globalThis.phase = () => {}
globalThis.budget = { total: null, spent: () => 0, remaining: () => Infinity }
globalThis.workflow = async () => ({})
// args.once = true bounds the outer self-feeding loop to EXACTLY one round
// (STOP_AFTER_ROUNDS = 1) — this harness only needs one round to reach every builder once.
globalThis.args = { STRONG_TIER: 'opus', interactive: false, fableDown: false, allowIntensive: false, afk: true, once: true }

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

// agent: dispatch a schema/label-appropriate stub PER BUILDER so every non-discovery prompt
// template is actually evaluated (the template literal is built and returned to `agent()`
// BEFORE this stub ever runs — a synchronous throw building it surfaces here as a rejected
// call, caught by the parallel() wrapper above or by runUnit's own try/catch).
globalThis.agent = async (_prompt, opts = {}) => {
  const label = opts.label || ''

  if (label.includes('discover-prelude')) {
    return {
      runId: 'relay-harness-0002', ts: '2026-07-08T00:00:00Z',
      repos: [
        { repo: 'alpha', path: '/tmp/harness/alpha', income: true },
        { repo: 'beta', path: '/tmp/harness/beta', income: true },
        { repo: 'gamma', path: '/tmp/harness/gamma', income: true },
      ],
      skippedConfig: [], liveClaimRepos: [], injectedUnits: [], signatures: [], stopRequested: false,
    }
  }
  if (label.startsWith('discover-run')) {
    // Seed exactly one unit of each pool-dispatchable non-hard verdict so the loop's
    // per-verdict dispatch/integrate/quota machinery all fire this round.
    return {
      units: [
        { verdict: 'execute', repo: 'alpha', path: '/tmp/harness/alpha', reason: 'harness execute unit', lastCkpt: '', income: true, intensive: '' },
        { verdict: 'review', repo: 'beta', path: '/tmp/harness/beta', reason: 'harness review unit', lastCkpt: '', income: true, intensive: '' },
        { verdict: 'handoff', repo: 'gamma', path: '/tmp/harness/gamma', reason: 'harness handoff unit', lastCkpt: '', income: true, intensive: '' },
      ],
      surfaced: [], skipped: [],
    }
  }
  if (label.startsWith('quota:')) {
    built.add('quota')
    return { exitCode: 0, buckets: [{ bucket: 'seven_day', pctRemaining: 95, resetTime: '2026-07-14T12:00:00Z' }] }
  }
  if (label.startsWith('execute:')) {
    built.add('execute-child')
    return { contract_met: true, branch: 'relay/harness-execute', worktree: '/tmp/harness/wt-execute', summary: 'harness execute done', review_me_count: 0, diary_fragment: 'harness', handback: '', routine_open: 0, worked_ids: [] }
  }
  if (label.startsWith('review:')) {
    built.add('review-child')
    return { contract_met: true, branch: 'relay/harness-review', worktree: '/tmp/harness/wt-review', summary: 'harness review done', review_me_count: 0, diary_fragment: 'harness', handback: '', routine_open: 0, worked_ids: [], verified_green: [], gaming_flags: [], reopened: [] }
  }
  if (label.startsWith('handoff:')) {
    built.add('handoff-child')
    return { contract_met: true, branch: 'relay/harness-handoff', worktree: '/tmp/harness/wt-handoff', summary: 'harness handoff done', review_me_count: 0, diary_fragment: 'harness', handback: '', worked_ids: [] }
  }
  if (label.startsWith('integrate:')) {
    built.add('integrate')
    return { merged: true, ckptTag: 'relay-ckpt-harness', pushStatus: 'pushed', ts: '2026-07-08T00:00:01Z', postSig: '', openRoutine: 0, openHard: 0 }
  }
  if (label === 'inject-take') {
    built.add('inject-take')
    return { units: [] }
  }
  if (label === 'auto-reconcile-restart') {
    built.add('auto-reconcile')
    return 'no dead run, skipped'
  }
  // heartbeat-beat / heartbeat-stop / resume / write-relay-status / file-surface / anything
  // else this harness doesn't specifically target: a generic, schema-tolerant stub so the
  // round still drains cleanly.
  return { contract_met: false, branch: '', worktree: '', summary: '', ok: true, units: [] }
}

const tmp = path.join(os.tmpdir(), `relay-loop-round-harness-${process.pid}.mjs`)
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

const required = ['execute-child', 'integrate', 'review-child', 'handoff-child', 'quota', 'inject-take', 'auto-reconcile']
const missing = required.filter(b => !built.has(b))
if (missing.length) {
  console.error(`FAIL: harness ran but never reached: ${missing.join(', ')}`)
  process.exit(1)
}
for (const b of required) console.log(`BUILT: ${b}`)
console.log('OK: full-round exec harness executed every non-discovery prompt builder; no thunk threw')
process.exit(0)
