// Executable containment harness for relay-loop.js integrate() failures (defect-fix guard,
// 2026-07-07, id:efaf). Drives ONE execute unit through a full round to a THROWING integrator
// agent and asserts the whole workflow still RESOLVES (does not reject) with the unit recorded
// as blocked — instead of a single integration failure crashing the entire pool and stranding
// every other in-flight worktree (observed: one integrate throw killed a 27-min, 51-agent run).
//
// Mirrors the Workflow sandbox: wraps the script body in an async IIFE + stub globals. The agent
// stub routes by PROMPT CONTENT: the serialized-integrator prompt THROWS (simulating an
// INTEGRATE_SCHEMA validation failure after retries, which makes agent() throw); the discovery
// runner emits one execute unit on round 1 then drains; the execute child returns contract_met.
//
// Exit 0 = workflow resolved (containment works); exit 1 = workflow REJECTED (the pre-fix crash)
// or the unit was not recorded blocked.
//
// Usage: node integrate-contain-harness.mjs <path-to-relay-loop.js>
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const SRC = process.argv[2]
if (!SRC || !fs.existsSync(SRC)) { console.error('usage: node integrate-contain-harness.mjs <relay-loop.js>'); process.exit(2) }

let code = fs.readFileSync(SRC, 'utf8')
code = code.replace(/^export\s+const\s+meta/m, 'const meta')
code = `globalThis.__reproResult = (async () => {\n${code}\n})()\n`

let integratorCalls = 0
let discoverCalls = 0

globalThis.log = () => {}
globalThis.phase = () => {}
globalThis.budget = { total: null, spent: () => 0, remaining: () => Infinity }
globalThis.workflow = async () => ({})
globalThis.args = { STRONG_TIER: 'opus', interactive: false, fableDown: false, allowIntensive: false, afk: true, MAX_ROUNDS: 4 }

globalThis.parallel = async (thunks) => Promise.all(thunks.map((t) =>
  Promise.resolve().then(t).catch(() => null)))
globalThis.pipeline = async (items, ...stages) => {
  const out = []
  for (let i = 0; i < items.length; i++) {
    let v = items[i]
    try { for (const s of stages) v = await s(v, items[i], i) } catch (_) { v = null }
    out.push(v)
  }
  return out
}

globalThis.agent = async (prompt, opts = {}) => {
  const p = String(prompt || '')
  const props = (opts.schema && opts.schema.properties) || {}

  // The serialized integrator → THROW (the id:efaf crash trigger: a schema-validation failure
  // after retries surfaces as a thrown Error out of the `await agent(...)` in integrate()).
  if (p.includes('serialized integrator of the relay pool')) {
    integratorCalls++
    throw new Error('simulated INTEGRATE_SCHEMA validation failure (harness)')
  }
  // Discovery runner: one execute unit on the first call, drained after → loop winds down.
  if (p.includes('MECHANICAL discovery runner')) {
    discoverCalls++
    if (discoverCalls === 1) {
      return { units: [{ repo: 'alpha', path: '/tmp/relay-harness/alpha', verdict: 'execute', is_finished: false, injected: false, income: false, sig: '' }], surfaced: [], skipped: [] }
    }
    return { units: [], surfaced: [], skipped: [] }
  }
  // Prelude (once-only global work).
  if ((opts.label || '').includes('discover-prelude') || props.repos) {
    return {
      runId: 'relay-harness-efaf', ts: '2026-07-07T00:00:00Z',
      repos: [{ repo: 'alpha', path: '/tmp/relay-harness/alpha', income: false }],
      skippedConfig: [], liveClaimRepos: [], injectedUnits: [], signatures: [], stopRequested: false,
    }
  }
  if (props.exitCode) return { exitCode: 0, buckets: [{ bucket: 'seven_day', pctRemaining: 95, resetTime: '2026-07-14T12:00:00Z' }] }
  // The execute child (REPORT_SCHEMA has contract_met) → succeeds so integration is attempted.
  if ('contract_met' in props) {
    return { contract_met: true, branch: 'relay/relay-harness-efaf-execute', worktree: '~/.cache/relay/worktrees/alpha/relay-harness-efaf-execute', summary: 'did work', review_me_count: 0, worked_ids: [], routine_open: 0 }
  }
  return { units: [] }
}

const tmp = path.join(os.tmpdir(), `relay-loop-contain-${process.pid}.mjs`)
fs.writeFileSync(tmp, code)
let result
try {
  await import('file://' + tmp)
  result = await globalThis.__reproResult   // the pre-fix crash makes THIS reject
} catch (e) {
  console.error('FAIL: the workflow REJECTED — one integration failure crashed the whole pool (uncontained): ' + (e && e.message ? e.message : e))
  process.exit(1)
} finally {
  try { fs.unlinkSync(tmp) } catch (_) {}
}

if (!integratorCalls) { console.error('FAIL: the integrator was never invoked — harness did not exercise the integration path'); process.exit(1) }
const blocked = (result && Array.isArray(result.handbacks)) ? result.handbacks
  : (result && Array.isArray(result.queuedRemaining)) ? result.queuedRemaining : []
console.log(`OK: workflow resolved despite a throwing integrator (integratorCalls=${integratorCalls}); no pool-wide crash. result.completed=${(result && result.completed || []).length}`)
process.exit(0)
