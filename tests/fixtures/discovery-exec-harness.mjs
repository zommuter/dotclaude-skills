// Executable smoke harness for relay-loop.js discovery dispatch (defect-fix guard, 2026-07-07).
//
// WHY THIS EXISTS: the relay-loop.js test suite is otherwise `node --check` (syntax) +
// grep (source-text) only — it never EXECUTES the Workflow body, because agent()/parallel()/
// log()/phase() are harness-injected globals. That gap let a runtime crash ship GREEN: an
// unescaped backtick pair inside the discover-run prompt template (`.timer`) prematurely
// closed the template, turning it into a tagged-template call on `undefined` — "undefined is
// not a function", thrown synchronously in every discovery shard thunk → whole pool dead.
// node --check passed (a tagged template is valid grammar) and every grep passed.
//
// This harness mirrors the Workflow sandbox: it wraps the script body in an async IIFE (so
// top-level return/await are legal), injects stub globals, feeds a minimal fake prelude, and
// runs ONE discovery round. If any parallel() thunk throws (the dispatch is broken) it exits
// non-zero; it exits 0 only if the discover-run agent is actually reached.
//
// Usage: node discovery-exec-harness.mjs <path-to-relay-loop.js>
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const SRC = process.argv[2]
if (!SRC || !fs.existsSync(SRC)) { console.error('usage: node discovery-exec-harness.mjs <relay-loop.js>'); process.exit(2) }

let code = fs.readFileSync(SRC, 'utf8')
// Sandbox parity: the harness wraps the whole script body in an async function, so top-level
// `return`/`await` are legal. Strip the ESM `export` and wrap in an async IIFE.
code = code.replace(/^export\s+const\s+meta/m, 'const meta')
code = `globalThis.__reproResult = (async () => {\n${code}\n})()\n`

let thunkThrew = false
let discoverRunReached = false

globalThis.log = () => {}
globalThis.phase = () => {}
globalThis.budget = { total: null, spent: () => 0, remaining: () => Infinity }
globalThis.workflow = async () => ({})
globalThis.args = { STRONG_TIER: 'opus', interactive: false, fableDown: false, allowIntensive: false, afk: true }

// parallel: mirror the real contract (a thrown thunk resolves to null, the call never rejects)
// but RECORD the throw so the test can fail loudly on it.
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

// agent: return schema/label-appropriate stubs so the loop reaches discovery dispatch, then
// short-circuits (empty discovery → the loop drains without doing real work).
globalThis.agent = async (_prompt, opts = {}) => {
  const label = opts.label || ''
  const props = (opts.schema && opts.schema.properties) || {}
  if (label.includes('discover-prelude') || props.repos) {
    return {
      runId: 'relay-harness-0001', ts: '2026-07-07T00:00:00Z',
      repos: [
        { repo: 'alpha', path: '/tmp/harness/alpha', income: true },
        { repo: 'beta', path: '/tmp/harness/beta', income: false },
      ],
      skippedConfig: [], liveClaimRepos: [], injectedUnits: [], signatures: [], stopRequested: false,
    }
  }
  if (props.exitCode) return { exitCode: 0, buckets: [{ bucket: 'seven_day', pctRemaining: 95, resetTime: '2026-07-14T12:00:00Z' }] }
  if (label.includes('discover-run')) { discoverRunReached = true; return { units: [], surfaced: [], skipped: [] } }
  if (label.includes('inject-take')) return { units: [] }
  if (label.includes('auto-reconcile')) return 'no dead run, skipped'
  return { contract_met: false, branch: '', worktree: '', summary: '' }
}

const tmp = path.join(os.tmpdir(), `relay-loop-harness-${process.pid}.mjs`)
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

if (thunkThrew) { console.error('FAIL: a discovery parallel() thunk threw at runtime'); process.exit(1) }
if (!discoverRunReached) { console.error('FAIL: discovery dispatch never reached the discover-run agent'); process.exit(1) }
console.log('OK: discovery dispatch executed; discover-run agent reached; no thunk threw')
process.exit(0)
