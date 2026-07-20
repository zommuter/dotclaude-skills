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
// emission (id:dd1e) are separate children gated on THIS skeleton — not built here.

import { execSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'
import { isDryRound, isBlockedRound } from './drain.mjs'

const __dirname = dirname(fileURLToPath(import.meta.url))

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

function finish(reason, rounds, code) {
  console.log(`DRAIN_STOP reason=${reason} rounds=${rounds}`)
  process.exit(code)
}

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

  let rounds = 0
  let nonSubStreak = 0   // consecutive non-substantive rounds
  let anyBlocked = false // any blocked round within the current non-substantive streak

  while (true) {
    let r
    try {
      r = runRound(cmd, repo)
    } catch (e) {
      console.error(`drain-driver: round ${rounds + 1} failed: ${e && e.message ? e.message : e}`)
      process.exit(1)
    }
    rounds++

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
