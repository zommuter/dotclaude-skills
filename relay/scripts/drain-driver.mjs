#!/usr/bin/env node
// drain-driver.mjs (id:cd7a, children-of id:93fe) — the off-Workflow single-repo drain LOOP
// + stop predicate. A HOST node script (NOT Workflow-sandbox JS): `node drain-driver.mjs
// --repo <dir> [--max-rounds N]`. Once per round it runs the DRAIN_ROUND_CMD env seam (the
// real classify→dispatch→integrate round; hermetic tests stub it with scripted round-result
// JSON), then classifies the result via a DIRECT import of drain.mjs.
//
// GUARD-PARITY (TODO id:93fe, Fable review 2026-07-19): because a host node process CAN
// `import`, this driver MUST import drain.mjs's isDryRound/isBlockedRound instead of
// re-deriving them — those semantics were learned from the 2026-06-29 spin-forever and
// 2026-07-17 drained-while-blocked incidents; the Workflow-sandbox inline-copy exception
// (id:d58f) does NOT apply here.
//
// Stop contract (meeting 2026-07-19-2035 D2 on the off-Workflow substrate):
//   - 2 consecutive non-substantive rounds, all dry     → exit 0, reason=drained
//   - 2 consecutive non-substantive rounds, any blocked → exit 2, reason=blocked
//   - --max-rounds seatbelt reached                     → exit 3, reason=max-rounds
// Final stdout line is machine-readable: "DRAIN_STOP reason=<r> rounds=<n>".
//
// The run-heartbeat (id:f9d2), quota gate + agent seatbelt (id:838d), and event-line
// emission (id:dd1e) are wired here (children-of id:93fe), each preserving its guard-parity
// sibling's contract:
//   - id:f9d2 run-heartbeat (id:e149 parity): mint a runId in the watchdog's `relay-*`
//     namespace, `heartbeat.sh beat` before EVERY round, `heartbeat.sh stop` on every clean
//     exit. Crash detection stays heartbeat.sh's already-tested TTL contract (not re-done here).
//   - id:838d quota gate + agent seatbelt: run DRAIN_QUOTA_CMD (default quota-stop.sh) BEFORE
//     EVERY round (incl. the first); a refused round is NEVER dispatched; gate exit 1/2/3 map to
//     driver exit 4 with distinct DRAIN_STOP reasons; feed cumulative --agents/--wall so
//     quota-stop.sh's 200-agent/7200-s seatbelt engages on a long drain.
//   - id:dd1e event-line emission (id:c8b6 parity): append-only JSONL round-start + drain-stop
//     events to $RELAY_EVENTS_PATH, each a valid JSON line carrying ts + runId.

import { execSync } from 'node:child_process'
import { appendFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'
import { isDryRound, isBlockedRound } from './drain.mjs'

const __dirname = dirname(fileURLToPath(import.meta.url))

// Heartbeat + quota gate scripts co-located in relay/scripts/. The quota default is
// referenced by literal name here so tests can assert the driver never runs an unguarded loop.
const HEARTBEAT_SH = resolve(__dirname, 'heartbeat.sh')
const DEFAULT_QUOTA_CMD = resolve(__dirname, 'quota-stop.sh')

// K consecutive non-substantive rounds trigger a stop (the historical dry>=2 machinery).
const DRAIN_K = 2

function parseArgs(argv) {
  const args = { repo: null, maxRounds: 50 }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--repo') args.repo = argv[++i]
    else if (a === '--max-rounds') args.maxRounds = Number(argv[++i])
    else if (a.startsWith('--repo=')) args.repo = a.slice('--repo='.length)
    else if (a.startsWith('--max-rounds=')) args.maxRounds = Number(a.slice('--max-rounds='.length))
  }
  return args
}

// runRound — invoke the DRAIN_ROUND_CMD seam once and parse its round-result JSON. The command
// prints {actionable, produced, substantive, surfaced} on stdout — the same shape
// relay-loop.js's runRound() returns and drain.mjs classifies.
function runRound(cmd, repo) {
  const out = execSync(cmd, {
    cwd: repo,
    encoding: 'utf8',
    env: { ...process.env, DRAIN_REPO: repo },
  })
  const line = out.trim().split('\n').filter(Boolean).pop() || '{}'
  return JSON.parse(line)
}

// mkRunId — the run-heartbeat / event runId, in the watchdog's `relay-*` namespace glob (the
// outage watchdog id:98f0 and reap consumers scope with --prefix 'relay-*'; a non-matching
// runId is invisible to them, id:f9d2). `relay-drain-<epoch-ms>-<pid>` matches `relay-*`.
function mkRunId() {
  return `relay-drain-${Date.now()}-${process.pid}`
}

// heartbeat — beat/stop the run-liveness marker (id:e149 contract, via heartbeat.sh). Best-
// effort: a heartbeat wiring failure must never crash the drain (the marker is a watchdog aid,
// not the drain's correctness). Env (HEARTBEAT_BASE etc.) rides through process.env.
function heartbeat(sub, runId) {
  try {
    execSync(`bash ${JSON.stringify(HEARTBEAT_SH)} ${sub} ${JSON.stringify(runId)}`, {
      env: process.env,
      stdio: 'ignore',
    })
  } catch {
    /* best-effort: never let a heartbeat failure derail the drain */
  }
}

// emitEvent — append one JSONL event line to $RELAY_EVENTS_PATH (id:c8b6 parity, id:dd1e).
// APPEND-only (never truncate the pool's shared feed). Every line carries ts + runId. This is a
// HOST node process (not the Workflow sandbox), so real timestamps are allowed here.
function emitEvent(runId, event, fields) {
  const path = process.env.RELAY_EVENTS_PATH
  if (!path) return
  try {
    const line = JSON.stringify({ ts: new Date().toISOString(), runId, event, ...fields })
    appendFileSync(path, line + '\n')
  } catch {
    /* best-effort event feed; never derail the drain */
  }
}

// quotaGate — run the quota gate seam BEFORE a round (id:838d). Returns the gate's exit code:
// 0 = proceed; 1/2/3 = the three quota-stop.sh stop reasons. Feeds cumulative --agents/--wall so
// quota-stop.sh's hard seatbelt (200 agents / 7200 s) engages on a long drain.
function quotaGate(quotaCmd, agents, wall) {
  try {
    execSync(`${quotaCmd} --agents ${agents} --wall ${wall}`, {
      env: process.env,
      stdio: 'ignore',
    })
    return 0
  } catch (e) {
    return typeof e.status === 'number' ? e.status : 1
  }
}

// Map a non-zero quota-gate exit code to its distinct DRAIN_STOP reason (id:838d).
const QUOTA_REASON = { 1: 'quota-stop', 2: 'quota-cache-unreadable', 3: 'quota-extrapolated-stop' }

function main() {
  const args = parseArgs(process.argv.slice(2))
  if (!args.repo) {
    console.error('drain-driver: --repo <dir> is required')
    process.exit(64)
  }
  const repo = resolve(args.repo)
  const maxRounds = Number.isFinite(args.maxRounds) && args.maxRounds > 0 ? args.maxRounds : 50
  const cmd = process.env.DRAIN_ROUND_CMD
  if (!cmd) {
    console.error('drain-driver: DRAIN_ROUND_CMD is not set (no round command to run)')
    process.exit(64)
  }
  const quotaCmd = process.env.DRAIN_QUOTA_CMD || DEFAULT_QUOTA_CMD

  const runId = mkRunId()
  const startTime = Date.now()

  // finish — the single terminal exit path: stop the heartbeat (clean exit ⇒ marker archived,
  // never left stale to false-alarm the watchdog), emit the final drain-stop event, print the
  // machine-readable stop line, and exit.
  function finish(reason, rounds, code) {
    emitEvent(runId, 'drain-stop', { reason, rounds })
    heartbeat('stop', runId)
    console.log(`DRAIN_STOP reason=${reason} rounds=${rounds}`)
    process.exit(code)
  }

  let rounds = 0
  let nonSubStreak = 0   // consecutive non-substantive rounds
  let anyBlocked = false // any blocked round within the current non-substantive streak
  let totalAgents = 0    // cumulative agents dispatched (fed to the quota seatbelt)

  while (true) {
    // (id:838d) Quota gate BEFORE every round, incl. the first. A refused round is never
    // dispatched: we stop here, before runRound. Feed cumulative agents + elapsed wall-seconds.
    const wall = Math.floor((Date.now() - startTime) / 1000)
    const gate = quotaGate(quotaCmd, totalAgents, wall)
    if (gate !== 0) {
      finish(QUOTA_REASON[gate] || 'quota-stop', rounds, 4)
    }

    // (id:f9d2) Beat the run-heartbeat BEFORE dispatch, so the marker is live DURING the round.
    heartbeat('beat', runId)
    // (id:dd1e) One round-start event per round.
    emitEvent(runId, 'round-start', { round: rounds + 1 })

    let r
    try {
      r = runRound(cmd, repo)
    } catch (e) {
      console.error(`drain-driver: round ${rounds + 1} failed: ${e && e.message ? e.message : e}`)
      process.exit(1)
    }
    rounds++

    // Cumulative agent count feeds the quota seatbelt; the per-round count rides the optional
    // `agents` field of the round-result JSON.
    const roundAgents = Number(r && r.agents)
    if (Number.isFinite(roundAgents) && roundAgents > 0) totalAgents += roundAgents

    const dry = isDryRound(r)
    const blocked = isBlockedRound(r)
    const substantive = !dry && !blocked // substantive>0 ⇒ neither dry nor blocked

    if (substantive) {
      // Real backlog progress resets the wind-down counter.
      nonSubStreak = 0
      anyBlocked = false
    } else {
      nonSubStreak++
      if (blocked) anyBlocked = true
      if (nonSubStreak >= DRAIN_K) {
        // 2026-07-17 drained-while-blocked guard: if any round in the quiescent streak
        // surfaced blocked work, we are NOT drained — report blocked instead.
        if (anyBlocked) finish('blocked', rounds, 2)
        finish('drained', rounds, 0)
      }
    }

    if (rounds >= maxRounds) finish('max-rounds', rounds, 3)
  }
}

main()
