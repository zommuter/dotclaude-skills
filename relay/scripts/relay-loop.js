export const meta = {
  name: 'relay-loop',
  description: 'Priority-mixed 5-wide autonomous relay pool — serialized integrator, quota-guarded, STRONG_TIER-aware',
  phases: [
    { title: 'Discover', detail: 'classify confirmed repos into execute/review/hard/handoff/idle units' },
    { title: 'Dispatch', detail: '5-wide pool: execute slots first, backfill with review/handoff' },
    { title: 'Integrate', detail: 'serialized merge → ckpt-tag → push per completed unit' },
  ],
}

// args may arrive as a JSON STRING (the harness delivers the Workflow `args` value
// stringified, even when the front door passes an object literal) or as a parsed
// object. Normalize to an object once — reading args.fableDown off a raw string
// yields undefined and silently disables -d, dispatching doomed strong-model units.
const A = (typeof args === 'string')
  ? (() => { try { return JSON.parse(args) } catch (_) { return {} } })()
  : (args || {})

// STRONG_TIER: apex model for review and handoff agents.
// Execute agents (Sonnet) never receive this override — only review and handoff agents do.
// Values: 'opus' (DEFAULT — Opus is the apex tier; user directive 2026-06-15) | 'fable'.
// Fable is an optional bonus, selected only when the front-door step-0 probe (or an explicit
// --strong-tier fable override) confirms it's available; otherwise the default 'opus' stands.
// Passed via args.STRONG_TIER from the front-door SKILL.md (set by STRONG_TIER env var or --strong-tier flag).
const STRONG_TIER = A.STRONG_TIER || 'opus'
const STRONG_MODEL = STRONG_TIER === 'opus' ? 'claude-opus-4-8' : 'claude-fable-5'

// RELAY_STATUS_PATH: output file for cross-repo rollup. Overridable for testing.
const RELAY_STATUS_PATH = A.RELAY_STATUS_PATH || '~/.config/relay/RELAY_STATUS.md'

// RELAY_EVENTS_PATH (id:c8b6): append-only JSONL history substrate behind the
// RELAY_STATUS.md snapshot. Each dispatch/integrate/handback pushes one line; the
// off-critical-path status writer flushes the batch via relay-state-write.sh event-append.
// `tail -f` it for a live event feed (the snapshot file is rewritten each round, so
// `tail -f` on RELAY_STATUS.md misbehaves — use `tail -F` there, but this file truly appends).
const RELAY_EVENTS_PATH = A.RELAY_EVENTS_PATH || '~/.config/relay/relay-events.jsonl'

// pendingEvents: accumulated, un-flushed event lines (JSON strings). pushEvent stamps each
// with the latest bash-produced state.ts (the Workflow runtime FORBIDS Date.now()/new Date()),
// so ordering rides on discovery/integrate timestamps. snapshotState drains this via splice()
// at schedule time, so a flushed batch is never re-emitted (no duplication across rounds).
let pendingEvents = []
function pushEvent(kind, fields) {
  pendingEvents.push(JSON.stringify({ ts: state.ts || '', runId: state.runId || '', kind, ...fields }))
}

// INTERACTIVE: pass-through of the front door's --interactive flag (default false).
// The Workflow itself NEVER prompts the user (unattended invariant, meeting D2 —
// enforced by tests/test_fables_front_door.sh grepping this file for the question tool);
// when true, dispatch may surface choices in RELAY_STATUS.md instead of silently skipping.
const INTERACTIVE = !!A.interactive
// [INTENSIVE] gate (id:8d52): resource-heavy units (local-LLM benchmarks, big index rebuilds —
// the OOM risk that killed 6 sessions) are NEVER auto-dispatched. --allow-intensive / --afk
// opt in; then they run SERIALLY-ALONE after the normal parallel wave, holding an exclusive
// resource claim (resource:<name>). --afk is the "I'm away, do something useful" alias.
const ALLOW_INTENSIVE = !!A.allowIntensive || !!A.afk

// FABLE_DOWN: set by --fable-down / -d front-door flag. It asserts ONE axis only — "the
// Fable strong tier is unavailable this run" — and composes with STRONG_TIER (which axis
// chooses WHICH strong model the review/handoff agents use):
//   • -d alone (STRONG_TIER unset/`fable`, STRONG_MODEL=claude-fable-5) → DEFER strong work:
//     the strong model literally can't run, so handoff units and routine-less review units
//     are deferred and review repos with open [ROUTINE] work are demoted to execute (the
//     Sonnet pool keeps running). See the demotion block in Phase 1 for the D3 rationale.
//   • -d + STRONG_TIER=opus (STRONG_MODEL=claude-opus-4-8) → SUBSTITUTE Opus for the
//     unavailable Fable: review/handoff units dispatch NORMALLY on Opus (already marked
//     `fable-standin` by standInSuffix). No defer/demote — the demote block is skipped.
// Forward-compatible: a future auto-probe would set args.fableDown = true identically.
const FABLE_DOWN = !!A.fableDown

// id:b841 — normalize a nested quotaThresholds map into flat RELAY_QUOTA_THRESHOLD_<BUCKET>
// keys so a user "raise 7d cap to 70%" directive actually takes effect.
// The front door may pass args.quotaThresholds = { SEVEN_DAY: 0.70, SEVEN_DAY_SONNET: 0.70 }
// (nested object form) while envPairs only reads the flat A.RELAY_QUOTA_THRESHOLD_* keys.
// Fold each nested entry into the flat key now — flat key wins if both present (explicit
// per-bucket override beats the nested default and beats the decay).
if (A.quotaThresholds && typeof A.quotaThresholds === 'object') {
  for (const [bucket, val] of Object.entries(A.quotaThresholds)) {
    const flatKey = `RELAY_QUOTA_THRESHOLD_${bucket}`
    if (A[flatKey] === undefined) {
      A[flatKey] = val
    }
  }
}

// D3: pool of distinct repos, one unit per repo. Default 5; override via args.POOL_WIDTH.
// NOTE: the Workflow harness independently caps concurrent agents at min(16, cpu_cores-2),
// so a POOL_WIDTH above that ceiling just queues — no benefit (e.g. 6 on an 8-core box).
const POOL_WIDTH = A.POOL_WIDTH || 5
// Agent-count seatbelt for one run (quota-stop.sh hard-caps at 200 independently).
const MAX_UNITS = A.MAX_UNITS || 20
// D3 policy invariant: Sonnet execute fills slots first; unreviewed-executor review
// ranks above fresh strong work (keeps the anti-gaming window short). Lower = sooner.
// hard (id:da26): Opus-apex HARD-execute, ranked AFTER execute and review but BEFORE
// handoff — review still beats a fresh strong-execute (preserves the D3 anti-gaming
// window), and a HARD item with a worked roadmap is more actionable than a fresh handoff.
const PRIORITY = { execute: 0, review: 1, hard: 2, handoff: 3 }

// True when THIS session's strong tier is real Fable (not an Opus substitute). Gates
// the standin re-review preference so an Opus run never re-reviews its own standin work.
const SESSION_IS_FABLE = STRONG_MODEL === 'claude-fable-5'

// "fable-standin" balance (user directive 2026-06-13): a repo whose latest fable-ckpt
// carries the `fable-standin` marker (unit.standin) was handed over / reviewed by Opus
// standing in for Fable, so it (a) still needs an INDEPENDENT Fable re-review, but
// (b) its roadmap specs are provisional until that happens. Reconcile both as a *slight*
// within-class tiebreaker (after verdict class + income; never a filter — standin repos
// are always still dispatched):
//   • review units on a Fable session  → standin FIRST (deliver the pending re-review, id:9821).
//   • everything else (execute/handoff dispatch, or any non-Fable session) → Fable-vetted
//     (non-standin) FIRST, so executors prefer trusted specs and Opus runs don't self-review.
// Lower rank sorts sooner. Fine-grained ordering vs income is intentionally deferred
// (income still dominates) per the 2026-06-13 fable-standin meeting note.
function standInRank(u) {
  if (u.verdict === 'review' && SESSION_IS_FABLE) return u.standin ? 0 : 1
  return u.standin ? 1 : 0
}

log(`relay-loop: STRONG_TIER=${STRONG_TIER} → model=${STRONG_MODEL}${FABLE_DOWN ? (STRONG_MODEL === 'claude-fable-5' ? ' (fable-down: Fable unavailable, no substitute → defer strong work, executor-only)' : ' (fable-down: Fable unavailable, STRONG_TIER=opus → substitute Opus for review+handoff, marked fable-standin)') : ''}`)

// buildRelayStatus — generate RELAY_STATUS.md content from a run-state snapshot.
// state shape:
//   { runId, ts, inFlight: [{repo, mode, agentId}],
//     completed: [{repo, mode, ckptTag, pushStatus}],
//     queued:    [{repo, verdict}],
//     blocked:   [{repo, reason, worktreePath}],
//     quota:     [{bucket, pctRemaining, resetTime}],
//     reviewMe:  [{repo, count, path}],
//     stopReason: string|null }  // id:8c35 — category of the stop (quota-stale-cache, quota-exhausted:<bucket>, etc.)
// id:8c35 — build the stop-reason line for RELAY_STATUS (called with the module-level
// stopReason at status-write time, so writeRelayStatus must pass it in via state).
function buildStopReasonLine(sr) {
  if (!sr) return '_(none — run still active or drained cleanly)_'
  return `**${sr}**`
}

function buildRelayStatus(state) {
  const header = `# RELAY_STATUS — last updated ${state.ts}  run: ${state.runId}`

  const inFlight = state.inFlight && state.inFlight.length
    ? state.inFlight.map(r => `- ${r.repo}  mode=${r.mode}  agent=${r.agentId}`).join('\n')
    : '_(none)_'

  const completed = state.completed && state.completed.length
    ? state.completed.map(r => `- ${r.repo}  mode=${r.mode}  ckpt=${r.ckptTag}  push=${r.pushStatus}`).join('\n')
    : '_(none)_'

  const queued = state.queued && state.queued.length
    ? state.queued.map(r => `- ${r.repo}  verdict=${r.verdict}`).join('\n')
    : '_(none)_'

  const blocked = state.blocked && state.blocked.length
    ? state.blocked.map(r => `- ${r.repo}  reason=${r.reason}  worktree=${r.worktreePath}`).join('\n')
    : '_(none)_'

  // Skipped (id:be62): every own repo NOT worked this round, with a one-word reason
  // category — excluded-by-config / idle-in-sync / dirty-worktree / diverged / claimed-
  // elsewhere / decision-gate / intensive — so the user sees at a glance what the pool is
  // ignoring and why. Populated from discovery.skipped (excluded + idle) at round start.
  const skipped = state.skipped && state.skipped.length
    ? state.skipped.map(r => `- ${r.repo}  ${r.reason}`).join('\n')
    : '_(none)_'

  const quota = state.quota && state.quota.length
    ? state.quota.map(r => `- ${r.bucket}  remaining=${r.pctRemaining}%${r.resetTime ? '  reset=' + r.resetTime : ''}`).join('\n')
    : '_(unknown)_'

  const reviewMe = state.reviewMe && state.reviewMe.length
    ? state.reviewMe.map(r => `- ${r.repo}  open=${r.count}  path=${r.path}`).join('\n')
    : '_(none)_'

  // id:8c35 — stop-reason line alongside Quota remaining so the operator sees WHY the run stopped
  const stopReasonLine = buildStopReasonLine(state.stopReason || null)

  // id:c8b6 — Run progress: at-a-glance counters so the snapshot conveys momentum, not just
  // the current frame. round/totalDispatched are run-totals; the rest are live tallies.
  const progress = [
    `- round=${state.round || 0}`,
    `- dispatched=${state.totalDispatched || 0} (total work units this run)`,
    `- in-flight=${(state.inFlight || []).length}`,
    `- completed=${(state.completed || []).length}`,
    `- blocked=${(state.blocked || []).length}`,
    `- queued=${(state.queued || []).length}`,
  ].join('\n')

  return [
    header,
    '',
    '## Run progress',
    progress,
    '',
    '## In-flight',
    inFlight,
    '',
    '## Completed this run',
    completed,
    '',
    '## Queued',
    queued,
    '',
    '## Blocked / HANDBACKs',
    blocked,
    '',
    '## Skipped (this round)',
    skipped,
    '',
    '## Quota remaining',
    quota,
    '',
    '## Stop reason',
    stopReasonLine,
    '',
    '## REVIEW_ME open items',
    reviewMe,
  ].join('\n')
}

// writeRelayStatus — write RELAY_STATUS.md via an agent (Workflow JS has no fs access)
// and emit a condensed log() line for the /workflows live view.
async function writeRelayStatus(state, statusPath) {
  const content = buildRelayStatus(state)
  const path = statusPath || RELAY_STATUS_PATH
  const inFlightCount = (state.inFlight || []).length
  const completedCount = (state.completed || []).length
  const blockedCount = (state.blocked || []).length
  // id:c8b6 — event batch drained into this snapshot (may be empty) + the append-only target.
  const events = state.events || []
  const eventsBlock = events.join('\n')
  log(`RELAY_STATUS updated: in-flight=${inFlightCount} completed=${completedCount} blocked=${blockedCount} events=${events.length} → ${path}`)
  // id:0d31 (skeleton L1 thin-glue) — ALL the deterministic work (path resolve + c34a guard,
  // claims peek → "## Claims (live)", relay-burn → "## Burnup this run", atomic flock'd write,
  // event-append) now lives in relay-status-publish.sh. The haiku agent's whole job collapses
  // to piping one blob to one command — short + precise, so a weak model can't drift off-target
  // (formatting claims-JSON into markdown by hand was the drift risk). The content (and, when
  // present, the event lines after a sentinel) ride stdin via a quoted heredoc so they transit
  // verbatim without expansion.
  const stdinPayload = events.length ? `${content}\n===RELAY-EVENTS===\n${eventsBlock}` : content
  await agent(
    `Run EXACTLY this one command and nothing else — no path math, no formatting, no extra files. Pipe the payload below to it verbatim via the quoted heredoc (the script resolves the path, renders the Claims + Burnup sections, writes atomically, and appends any events itself):

~/.claude/skills/relay/scripts/relay-status-publish.sh --path '${path}' --run '${state.runId || ''}' --events-path '${RELAY_EVENTS_PATH}' <<'RELAY_STATUS_EOF'
${stdinPayload}
RELAY_STATUS_EOF

Report the script's final line. If it exits non-zero, report its stderr; do not retry or write any file yourself.`,
    { label: 'write-relay-status', phase: 'Integrate', model: 'haiku' }
  )
}

// id:cb50 — keep the Haiku RELAY_STATUS write OFF the pool's critical path. It is purely a
// visibility side-effect, but it was `await`ed between discover→dispatch and at round end, so
// the next discover/dispatch blocked on it. scheduleStatusWrite snapshots the content NOW
// (state is mutated across rounds, so a queued write must not read it later) and queues the
// write on a single serialized tail (concurrent writes never clobber). The pool proceeds
// immediately; the run flushes the tail once at the end so the final status is durable.
let statusTail = Promise.resolve()
function snapshotState(s) {
  return {
    runId: s.runId, ts: s.ts,
    inFlight: [...(s.inFlight || [])], completed: [...(s.completed || [])],
    queued: [...(s.queued || [])], blocked: [...(s.blocked || [])],
    skipped: [...(s.skipped || [])], quota: [...(s.quota || [])], reviewMe: [...(s.reviewMe || [])],
    stopReason,  // id:8c35 — capture module-level stopReason at snapshot time
    round, totalDispatched,            // id:c8b6 — run-progress counters at snapshot time
    events: pendingEvents.splice(0),   // id:c8b6 — DRAIN pending events into this batch (never re-emitted)
  }
}
function scheduleStatusWrite(state, statusPath) {
  const snap = snapshotState(state)
  statusTail = statusTail
    .then(() => writeRelayStatus(snap, statusPath))
    .catch((err) => log(`relay-loop: RELAY_STATUS write failed (non-fatal): ${err}`))
  return statusTail
}

// ── Schemas (agents return validated objects, never free text) ──

const DISCOVER_SCHEMA = {
  type: 'object',
  required: ['runId', 'ts', 'units', 'surfaced'],
  properties: {
    runId: { type: 'string' },
    ts: { type: 'string' },
    units: {
      type: 'array',
      items: {
        type: 'object',
        required: ['repo', 'path', 'verdict', 'reason'],
        properties: {
          repo: { type: 'string' },
          path: { type: 'string' },
          verdict: { enum: ['execute', 'review', 'hard', 'handoff', 'idle'] },
          reason: { type: 'string' },
          lastCkpt: { type: 'string' },
          income: { type: 'boolean' },
          // hasRoutine: ROADMAP.md has >=1 unticked [ROUTINE] item, reported
          // INDEPENDENT of verdict — lets --fable-down demote a review repo that
          // also has open executor work instead of deferring it wholesale.
          hasRoutine: { type: 'boolean' },
          // openHard: count of unticked "- [ ]" items tagged "[HARD" (HARD — strong
          // model). Drives the "hard" verdict (id:da26): a repo with no unaudited
          // commits and no open [ROUTINE] but >=1 open [HARD] item is classified hard
          // so an Opus-apex child can work one bounded HARD item — the ROUTINE-drained,
          // Fable-out steady state where ~46 [HARD] items would otherwise stall.
          openHard: { type: 'number' },
          // strongRecheckPending: true iff relay.toml [repos.<name>] has a last_strong_ckpt
          // set with fable_rechecked = false (or absent/empty). This is the DURABLE,
          // model-tracked Fable-bonus-recheck queue (id:e030): it survives a later executor
          // checkpoint that masks the latest-tag `fable-standin` signal, so a pending optional
          // Fable recheck stays visible. Consumed by the id:9821 elevation below (Fable session).
          strongRecheckPending: { type: 'boolean' },
          // standin: latest relay checkpoint tag message (match BOTH fable-ckpt-* AND
          // relay-ckpt-* prefixes — repos may still carry an old fable-ckpt-*) contains the
          // literal `fable-standin` token — the repo's last relay checkpoint was Opus
          // standing in for Fable, so it still needs an independent Fable re-review.
          // Drives the standInRank tiebreaker.
          standin: { type: 'boolean' },
          // injected (id:baf1): this unit came from the user-driven injection inbox
          // (`inject.sh take`), NOT from repo classification. Injected units sort AHEAD of
          // every verdict class and skip the quota gate (an explicit user request). The
          // shard was already consumed by `take`, so it is not re-listed next round.
          injected: { type: 'boolean' },
          inject_token: { type: 'string' },   // the consumed shard token (for logging/trace)
          inject_prompt: { type: 'string' },  // optional freeform instruction for the child
          inject_item: { type: 'string' },    // optional specific ROADMAP id to work
          // intensive (id:8d52): non-empty resource name (e.g. "local-llm") iff this unit is
          // resource-heavy — the top open item it would work carries [INTENSIVE — <resource>],
          // or the repo's relay.toml block has intensive = "<resource>" / intensive = true
          // (→ "local-llm"). Empty/absent for normal units. Drives the never-auto-dispatch gate.
          intensive: { type: 'string' },
        },
      },
    },
    surfaced: {
      type: 'array',
      items: {
        type: 'object',
        required: ['repo', 'reason'],
        properties: { repo: { type: 'string' }, reason: { type: 'string' } },
      },
    },
    // skipped (id:be62): repos NOT worked this round for a BENIGN reason — every relay.toml
    // repo with classification != "own" ("excluded-by-config (clone|excluded|needs_review)")
    // and every own repo classified "idle" ("idle — in sync, no open work"). Distinct from
    // surfaced (which is needs-attention: dirty/diverged/claimed). Drives the RELAY_STATUS
    // "## Skipped (this round)" rollup so the user sees what the pool ignores and why.
    skipped: {
      type: 'array',
      items: {
        type: 'object',
        required: ['repo', 'reason'],
        properties: { repo: { type: 'string' }, reason: { type: 'string' } },
      },
    },
  },
}

// id:9ed4 — parallel-shard discovery splits the single discover agent into a once-only
// PRELUDE (runId, the CONSUMING inject.sh take, claim.sh peek, the own-repo list + non-own
// skipped rollup) and N SHARD classifiers run in parallel. PRELUDE_SCHEMA / SHARD_SCHEMA
// reuse DISCOVER_SCHEMA's exact unit/surfaced/skipped item shapes so the merged object is
// byte-identical to what the single agent used to return.
const PRELUDE_SCHEMA = {
  type: 'object',
  required: ['runId', 'ts', 'repos'],
  properties: {
    runId: { type: 'string' },
    ts: { type: 'string' },
    repos: {
      type: 'array',
      items: {
        type: 'object',
        required: ['repo', 'path'],
        properties: { repo: { type: 'string' }, path: { type: 'string' }, income: { type: 'boolean' } },
      },
    },
    liveClaimRepos: { type: 'array', items: { type: 'string' } },
    injectedUnits: DISCOVER_SCHEMA.properties.units,
    skippedConfig: DISCOVER_SCHEMA.properties.skipped,
    // id:c3a6 — per-repo SUPERSET signature from discover-sig.sh; runRound reuses a cached verdict
    // for any repo whose signature is unchanged round-to-round (content-addressed discovery cache).
    signatures: {
      type: 'array',
      items: {
        type: 'object',
        required: ['repo', 'sig'],
        properties: { repo: { type: 'string' }, sig: { type: 'string' } },
      },
    },
  },
}
const SHARD_SCHEMA = {
  type: 'object',
  required: ['units', 'surfaced'],
  properties: {
    units: DISCOVER_SCHEMA.properties.units,
    surfaced: DISCOVER_SCHEMA.properties.surfaced,
    skipped: DISCOVER_SCHEMA.properties.skipped,
  },
}

const QUOTA_SCHEMA = {
  type: 'object',
  required: ['exitCode'],
  properties: {
    exitCode: { type: 'number' },
    buckets: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          bucket: { type: 'string' },
          pctRemaining: { type: 'number' },
          resetTime: { type: 'string' },
        },
      },
    },
  },
}

const REPORT_SCHEMA = {
  type: 'object',
  required: ['contract_met', 'branch', 'worktree', 'summary'],
  properties: {
    contract_met: { type: 'boolean' },
    branch: { type: 'string' },
    worktree: { type: 'string' },
    summary: { type: 'string' },
    review_me_count: { type: 'number' },
    diary_fragment: { type: 'string' },
    handback: { type: 'string' },
    // routine_open: open [ROUTINE] item count after a REVIEW re-derived the roadmap.
    // >0 ⟹ the supervisor re-enqueues an execute unit for this repo in the SAME pool
    // (review→execute chaining) instead of waiting for the next pool's discovery.
    routine_open: { type: 'number' },
  },
}

const INTEGRATE_SCHEMA = {
  type: 'object',
  required: ['merged'],
  properties: {
    merged: { type: 'boolean' },
    ckptTag: { type: 'string' },
    pushStatus: { type: 'string' },
    ts: { type: 'string' },
    reason: { type: 'string' },
    // L2 push-seed (id:c855): the integrator recomputes the just-worked repo's discovery
    // signature (discover-sig.sh) AFTER merge+tag+push+toml+worktree-removal, plus cheap
    // open-work counts, so integrate() can seed state.discoverCache and next round's prelude
    // sig matches → cache HIT → no re-classifying shard for a repo only the pool touched.
    postSig: { type: 'string' },       // recomputed discover-sig for this repo ("" = fail-open)
    openRoutine: { type: 'number' },   // unticked "- [ ]" [ROUTINE] items in ROADMAP.md post-merge
    openHard: { type: 'number' },      // unticked "- [ ]" [HARD items in ROADMAP.md post-merge (any HARD)
  },
}

// id:6e9d — schema for the mid-round `inject.sh take` agent (takeInjections). Units are
// loosely typed (the agent echoes resolved injected units); the dispatch path tolerates the
// same fields the discovery agent's injected units carry.
const INJECT_TAKE_SCHEMA = {
  type: 'object',
  required: ['units'],
  properties: {
    units: { type: 'array', items: { type: 'object' } },
  },
}

// ── Per-repo serialized integrator (D5/D6 restated, id:bc9d: never two concurrent pushes
// to the SAME remote — but DISTINCT repos have DISTINCT remotes and do not conflict, so
// their integrations run concurrently; only same-repo integrations serialize, preserving
// review→execute re-chain ordering into the same main checkout). A single GLOBAL chain made
// every repo's ~1–2 min Sonnet integrate agent wait behind every other's, so checkpoints
// landed serially no matter how wide the dispatch — the pool LOOKED 1-wide even though the
// work agents ran concurrently. Each repo gets its own tail promise; cross-repo integration
// is parallel (git-lock-push.sh still flocks per-repo for the residual same-remote case).
// Intentionally NOT a parallel() over the integration step — a per-repo promise chain is the
// serializer, so same-repo merges into one main checkout never race. ──
const integrationChains = new Map()   // repo name -> tail promise
function enqueueIntegration(repo, fn) {
  const prev = integrationChains.get(repo) || Promise.resolve()
  const run = prev.then(fn, fn)
  integrationChains.set(repo, run.then(() => {}, () => {}))
  return run
}

// ── Self-feeding loop (user directive 2026-06-13): one launch drains the backlog.
// runRound() does one re-discover → dispatch wave → drain. The outer loop at the bottom
// repeats it, so executes→reviews→executes cycle via a FRESH discovery each round, until
// (a) the quota cap stops it, (b) two consecutive discoveries find no actionable work
// (drained), or (c) the MAX_ROUNDS seatbelt trips. `state` and `quotaStopped` persist
// across rounds (accumulators); per-round vars (queue/debts/unitsDispatched/roundCapHit)
// are local to runRound and reset each round.
const state = { runId: '', ts: '', inFlight: [], completed: [], queued: [], blocked: [], skipped: [], quota: [], reviewMe: [] }
let quotaStopped = false
// Run-progress accumulators (id:c8b6), declared here (not at the bottom loop) so snapshotState
// can read them with no temporal-dead-zone risk. round = re-discover→dispatch→drain iterations;
// totalDispatched = work units dispatched across ALL rounds (unitsDispatched resets per round).
let round = 0
let totalDispatched = 0
// id:8c35 — machine-readable stop reason: null | "quota-stale-cache" |
// "quota-exhausted:<bucket>" | "budget" | "drained" | "max-rounds"
// Populated by quotaGate on any stop so operators (and RELAY_STATUS) see WHY,
// not just "quotaStopped=true".
let stopReason = null
// Quota-check throttle (efficiency): spawning a Haiku quota agent before EVERY unit
// saturated the harness concurrency cap (min(16, cores-2)) with throwaway checks,
// starving the work lanes — with POOL_WIDTH lanes the effective WORK parallelism
// collapsed toward ~1 instead of POOL_WIDTH (one quota + one work agent per lane = 2×
// the slots, plus the serialized integrate agent). Re-run the real quota agent only every
// QUOTA_CHECK_EVERY dispatches and reuse the last verdict in between (Workflow scripts
// can't use Date.now() for a time TTL, so throttle by dispatch count). Mid-round
// exhaustion is still caught within QUOTA_CHECK_EVERY units; the sticky quotaStopped flag
// hard-stops instantly once any check trips.
const QUOTA_CHECK_EVERY = A.QUOTA_CHECK_EVERY || POOL_WIDTH
let quotaChecks = 0
let lastQuotaOk = true
const MAX_ROUNDS = A.MAX_ROUNDS || 30
// id:9ed4 — how many parallel discovery-shard classifiers to fan out per round. The own-repo
// list is round-robin chunked across this many agents (capped at repo count). The Workflow
// harness caps concurrent agents at min(16, cores-2), so shards above that just queue.
const DISCOVER_SHARDS = A.DISCOVER_SHARDS || 6

async function runRound() {
// id:2d20 — productivity baseline: completions integrated BEFORE this round. The outer loop's
// drain detector keys on `produced` (completions THIS round), not units dispatched — a round
// that only hands back gated/too-large HARD units produces 0 and counts as dry, so the loop
// drains instead of re-dispatching the same un-doable items for MAX_ROUNDS.
const completedBefore = state.completed.length
// ── Phase 1: Discover ──

phase('Discover')

// id:9ed4 — PRELUDE: once-only global work (runId, the CONSUMING inject.sh take, claim.sh
// peek, the own-repo list + non-own skipped rollup). Then fan out parallel SHARD classifiers.
const prelude = await agent(
  `You are the PRELUDE of the relay discovery step. Do ONLY the once-only global work; do NOT classify repos.
1. runId: generate ONCE via the shell: relay-$(date +%Y%m%d-%H%M%S)-$RANDOM (seconds + random suffix; MUST be unique per pool run — two concurrent pools must never share one because the cross-session lease and the worktree guard both key on it, id:0902).
2. ts: current ISO 8601 timestamp.
3. repos: read ~/.config/relay/relay.toml; for EVERY block with classification = "own" emit {repo, path (default ~/src/<name>, or the "# path:" comment override), income (true iff income = true)}.
4. skippedConfig (id:be62): for every block whose classification is NOT "own" emit {repo, reason: "excluded-by-config (<classification>)"}. The shards never see non-own repos.
5. liveClaimRepos: run ~/.claude/skills/relay/scripts/claim.sh peek once — it prints every LIVE cross-session claim as one JSON per line ({key,repo,runId,...}); return the SET of distinct "repo" values. [] if none.
6. injectedUnits (id:baf1): run ~/.claude/skills/relay/scripts/inject.sh take EXACTLY ONCE — it atomically emits AND CONSUMES pending user-injected units, one JSON per line {token, repo, verdict, item, prompt, requested_at}. For EACH, emit one unit: {injected:true, inject_token:<token>, verdict:(<verdict> or "execute"), repo:<repo>, path:(resolve ~/src/<repo> or the "# path:" override), reason:"user-injected high-priority task", inject_item:(<item> or ""), inject_prompt:(<prompt> or ""), income:false, standin:false, hasRoutine:false, openHard:false, strongRecheckPending:false, lastCkpt:"", intensive:""}. [] if take emits nothing. NEVER run take more than once (it consumes).
7. signatures (id:c3a6 — discovery cache): compute a per-repo SUPERSET signature so the supervisor can skip re-classifying (an LLM shard) a repo whose observable state is unchanged since last round. Build ONE JSON object {"repos":[{"repo":<repo>,"path":<path>} for EVERY own repo from step 3],"liveClaims":<the liveClaimRepos array from step 5>} and pipe it on stdin to ~/.claude/skills/relay/scripts/discover-sig.sh. The script emits one JSON line per repo {"repo":<repo>,"sig":<sha256-hex or "">} — return them verbatim as "signatures". An EMPTY sig is a fail-open sentinel (the script could not read the repo): pass it through unchanged, do NOT invent a hash. Do this ONCE for all own repos; do NOT classify here. ([] only if there are zero own repos.)`,
  { label: 'discover-prelude', phase: 'Discover', schema: PRELUDE_SCHEMA, model: 'sonnet' }
)

let discovery = null
if (prelude && Array.isArray(prelude.repos)) {
  const ownRepos = prelude.repos
  // ── Content-addressed discovery cache (id:c3a6) ──
  // The classifier shards used to re-run fresh EVERY round, re-classifying repos whose observable
  // state hadn't changed — the bulk of the on-critical-path "status" overhead. Reuse last round's
  // verdict for any repo whose SUPERSET signature (discover-sig.sh, returned by the prelude as
  // `signatures`) is byte-identical to the cached one; only changed/new/fail-open repos pay for an
  // LLM shard. FAIL-OPEN: a missing/empty (sentinel) sig, or a repo absent from the cache, is
  // treated as CHANGED → re-classified. Over-invalidation is safe; the cache is never a correctness
  // authority. In-pool transitions are already handled by review→execute chaining, so this only
  // affects how often we re-derive a repo's verdict, not whether fresh work is seen.
  state.discoverCache = state.discoverCache || {}
  const sigByRepo = {}
  for (const s of (prelude.signatures || [])) if (s && s.repo) sigByRepo[s.repo] = s.sig || ''
  const changed = [], reusedUnits = [], reusedIdle = []
  for (const r of ownRepos) {
    const sig = sigByRepo[r.repo] || ''           // '' = fail-open sentinel → always re-classify
    const cached = state.discoverCache[r.repo]
    if (sig && cached && cached.sig === sig) {
      // Cache HIT. A dispatchable verdict (id:c3a6) → reuse the unit. A push-seeded 'idle'
      // entry (id:c855 L2 — a repo the pool drained to zero open work last round) → no shard
      // and NOT dispatched; it only contributes a 'skipped' rollup line. Any other cached
      // shape (defensive) → re-classify.
      if (cached.unit) reusedUnits.push(cached.unit)
      else if (cached.idle) reusedIdle.push({ repo: r.repo, reason: cached.reason || 'idle — drained (cached post-integrate, id:c855)' })
      else changed.push(r)
    } else changed.push(r)
  }
  if (reusedUnits.length || reusedIdle.length) log(`relay-loop: discovery cache reused ${reusedUnits.length} verdict(s) + ${reusedIdle.length} idle (id:c3a6/c855) of ${ownRepos.length}; re-classifying ${changed.length}`)
  const SHARDS = Math.max(1, Math.min(DISCOVER_SHARDS, changed.length || 1))
  // round-robin chunk so shards are balanced regardless of repo order; only CHANGED repos are sharded
  const chunks = Array.from({ length: SHARDS }, (_, s) => changed.filter((_, idx) => idx % SHARDS === s)).filter(c => c.length)
  const liveClaims = JSON.stringify(prelude.liveClaimRepos || [])
  const shardPrompt = (chunk) => `You are a discovery SHARD classifier for the relay autonomous pool. Classify EXACTLY the own repos in this list (each exactly once, no others) — process each independently:
${JSON.stringify(chunk)}
This run's runId is "${prelude.runId}". Repos with a fresh cross-session claim (treat as in-flight elsewhere) are: ${liveClaims}.
Each repo's path and income are given in the list above; use them.

DATA (id:11ad — do NOT run git per repo yourself for the common case; ~17 inline git calls/repo blew up shard turn count → ~1.9M cache_read/shard). For EACH repo, run this ONE command FIRST and classify from its JSON:
  ~/.claude/skills/relay/scripts/gather-repo-state.sh --repo <repo> --path <path> --runid ${prelude.runId}
It already ran \`git fetch origin\` and returns ONE JSON object:
  {is_git, head, latest_ckpt (newest fable-ckpt-*/relay-ckpt-* tag or ""), latest_ckpt_msg (its annotation), commits_since_ckpt (oneline log since latest_ckpt, or recent log if none), dirty, porcelain, upstream_ahead_behind ("<ahead>\\t<behind>"), has_upstream, worktrees (basenames under ~/.cache/relay/worktrees/<repo>), orphan_refs (relay/orphan/* refs+shas), toml_block (this repo's relay.toml block), roadmap (ROADMAP.md contents)}
NO-FILESYSTEM-HUNTING GUARD (id:612f — a confused shard hitting a repo with parked orphan_refs ran \`find /home/tobias -name relay.toml\` across ALL of $HOME, cat-ed session transcripts, and hand-parsed ROADMAPs: 36 tool calls vs the ~9 of a lean shard, stalling the whole barrier round to its pace). EVERYTHING you need is already in the gather JSON — do NOT re-derive it from the filesystem: \`toml_block\` IS this repo's relay.toml block (never read ~/.config/relay/relay.toml, never \`find\` for it); \`roadmap\` IS its ROADMAP.md (never cat it); \`orphan_refs\` already lists the parked refs+shas. NEVER run \`find\` over $HOME or any broad tree, NEVER cat session/transcript files, NEVER search for state the JSON already holds. For the orphan cost-hint runId, PARSE it from the orphan ref basename itself (it embeds the originating runId, e.g. relay/orphan/relay-<runId>-<...>) — do NOT search for it. The ONLY git you may run per repo is the bounded set the orphan/worktree/sync guards below explicitly name (\`git show --stat <orphan-ref>\`, \`merge --ff-only\`, \`worktree remove\`, \`branch -m/-D\`). If a field is genuinely missing from the JSON, SURFACE the repo with a one-line reason — never go hunting.

If is_git is false → surface the repo with reason "not a git work tree". Otherwise classify into exactly one verdict from these fields:

- "review": commits_since_ckpt is NON-EMPTY (commits exist after the last relay checkpoint tag). Unaudited work always wins over other verdicts.
- "execute": commits_since_ckpt is empty, and roadmap has >=1 unticked "- [ ]" item tagged [ROUTINE].
- "hard": commits_since_ckpt is empty, NO open [ROUTINE] item, but roadmap has >=1 unticked "- [ ]" EXECUTABLE [HARD — strong model] item (see the EXECUTABLE-HARD test below). This is the ROUTINE-drained steady state where HARD work would otherwise stall.

EXECUTABLE-HARD test (id:2d20 — never dispatch an un-doable HARD item; a relay child can only refuse it, and re-dispatching it every round is pure waste). An unticked "- [ ]" [HARD item counts as EXECUTABLE only if a strong child could plausibly finish it green in one turn. It is NON-executable (GATED) — EXCLUDE it from the hard verdict and from openHard — when ANY of:
  • it is tagged "[HARD — decision gate]" (vs "[HARD — strong model]");
  • it sits under a "## Gated" / "do not start" / "deferred" ROADMAP section, or its acceptance text says to wait for a gate ("re-scope when the gate opens", "no code before ratification", "blocked on …");
  • its acceptance criteria require a /meeting or recorded design decision FIRST (e.g. "hold a scoping meeting", "design recorded in docs/meeting-notes/ … then implement");
  • it is explicitly multi-session or cross-repo in scope (cannot be finished+verified from this one repo's worktree).
A repo whose ONLY open [HARD items are all GATED is NOT "hard": put it in "surfaced" with reason "HARD backlog is gated — needs a /meeting to unblock/re-scope (items: <ids>); not dispatched (id:2d20)". This moves the gate-detection to cheap discovery instead of spawning an Opus hard child every round to re-derive the same handback.
- "handoff": commits_since_ckpt is empty, and roadmap is missing/has no roadmap marker, OR every item is ticked while untracked new work exists.
- "idle": none of the above.

Order of precedence (apply the FIRST that matches): review > execute(routine) > hard > handoff > idle.

A repo with a DIRTY main working tree (dirty=true / porcelain non-empty, ignoring entries already declared acceptable in the toml_block comments) is NOT dispatched: put it in "surfaced" with the reason (cite the porcelain) instead of "units". Repos with no relay checkpoint tag (latest_ckpt empty) and no handoff_date in toml_block are handoff candidates, not review.

SYNC-WITH-ORIGIN GUARD (id:c3f7 — never commit on a base behind origin; a 2026-06-15 incident built a doomed parallel relay timeline on a clone ~1 month behind origin, and a force-push "fix" would have destroyed 106 commits). gather-repo-state.sh ALREADY ran \`git fetch origin\`; read upstream_ahead_behind ("<ahead>\\t<behind>") — skip this guard when has_upstream is false:
- DIVERGED (ahead>0 AND behind>0): do NOT classify or work it. Put it in "surfaced" with reason "diverged from origin (local <ahead> / origin <behind>) — needs manual reconcile (id:c3f7)". Never dispatch or commit on a diverged repo.
- BEHIND-ONLY (ahead==0 AND behind>0) AND not dirty: fast-forward FIRST — git -C <path> merge --ff-only @{upstream} — then RE-RUN gather-repo-state.sh for this repo and classify from the fresh JSON (commits_since_ckpt changes after the ff).
- Otherwise (ahead-only, or in sync): proceed normally.

WORKTREE-AWARE / CLAIMED-ELSEWHERE GUARD (id:ebfb step 1 — don't double-work a repo another relay run/session holds; a held worktree is the durable in-flight signal). ONLY when the gather JSON's worktrees field is non-empty (skip entirely otherwise). Use the live-claim repo set given above (do NOT run claim.sh peek yourself — the prelude already did, once). For any worktree basename (in the worktrees field) that does NOT start with this run's runId:
  - If the repo IS in the live-claim set → it is genuinely in-flight under a LIVE run/session: put it in "surfaced" with reason "in-flight elsewhere (worktree <basename>) — claimed by another relay run (id:ebfb)" and do NOT classify it.
  - If the repo is NOT in the live-claim set → the worktree is a STALE leftover from a DEAD run (a live run always holds a claim before creating its worktree), so the bare existence of the directory must NOT block this repo (id:3ac8 — stale worktrees were falsely starving the pool). Reconcile it: resolve the worktree branch as relay/<basename>, then run git -C <repo canonical path> merge-base --is-ancestor <worktree HEAD> <repo default branch e.g. main>.
      • EMPTY (HEAD is an ancestor of main → no unmerged work): REAP it — git -C <repo path> worktree remove --force ~/.cache/relay/worktrees/<repo>/<basename> && git -C <repo path> branch -D relay/<basename> — then classify the repo NORMALLY this round (it is now free). This is safe: an ancestor-of-main branch has nothing to lose.
      • COMMITS AHEAD (NOT an ancestor of main → carries unmerged work): PARK the orphan (id:689c) — do NOT auto-integrate (no --no-ff merge here) and do NOT classify this round. Instead: (a) git -C <repo path> branch -m relay/<basename> relay/orphan/<basename>  (rename the stranded branch into the canonical relay/orphan/* namespace — the commit stays reachable on the ref, NOT deleted); then (b) git -C <repo path> worktree remove --force ~/.cache/relay/worktrees/<repo>/<basename>  (remove the dir so the ls-worktrees scan stops re-surfacing this orphan every round). Then put it in "surfaced" with reason "parked orphan from a dead run with <N> unmerged commit(s) — ref renamed to relay/orphan/<basename> for manual /relay reconcile (id:689c)". Emit ONE such summary line total, not one per round. This replaces the old surface-only behaviour that left the directory in place and re-triggered every round.

SUPPRESS-REDISPATCH OF PARKED PARTIAL WORK (id:1f53 — once an orphan is parked into relay/orphan/*, do NOT repeat the expensive session that already did partial work in vain). ONLY when the gather JSON's orphan_refs field is non-empty (skip entirely otherwise). The relay/orphan/* refs ARE the registry — there is NO new manifest; the orphan_refs field lists them (refname + sha). For each such ref, BIND it back to its ROADMAP item: run git -C <repo path> show --stat <orphan-ref> on the parked commit and read both (i) the commit subject/body and (ii) the touched files for an id:XXXX token (a relay executor commit references the ROADMAP item it worked). Then resolve that item's checkbox state in the repo's ROADMAP.md:
        - Item is still OPEN ("- [ ]") → SUPPRESS a fresh dispatch for that item this round (do NOT classify the repo into a dispatchable unit for that item — repeating the same expensive session would burn quota on work already half-done and parked). Surface it instead with ONE line carrying a best-effort cost hint, e.g. reason "suppressed re-dispatch: parked partial work for <id> on relay/orphan/<basename> — manual /relay reconcile; cost hint: relay-burn.sh --run <runId>" where <runId> is parsed from the orphan basename when present (the basename embeds the originating runId). Emit ONE such line per parked-open item, not per round.
        - Item is CLOSED ("- [x]") → the parked orphan is stale leftover of finished work and does NOT suppress: classify the repo normally (a later /relay reconcile prunes the dead ref).
        - AMBIGUOUS binding (no id token found, or the commit maps to no resolvable ROADMAP item) → DEFAULT TO SUPPRESS (a one-line glance from the human is far cheaper than blindly repeating an expensive session); surface the same one-line cost hint with reason "suppressed re-dispatch: parked partial work on relay/orphan/<basename> (item binding ambiguous) — manual /relay reconcile; cost hint: relay-burn.sh --run <runId>".
${INTERACTIVE ? 'Interactive run: include marginal/ambiguous repos in "surfaced" with a one-line question each.' : 'Unattended run: never include questions; surface ambiguous repos with a factual reason only.'}

Per-repo fields to set on each unit you emit:
- path and income: copy them verbatim from the repo's entry in the input list above.
(All of these come from the gather JSON — no extra git calls.)
- lastCkpt per repo = latest_ckpt (the tag name, or "" if none).
- income per repo: true iff toml_block has income = true.
- hasRoutine per repo: true iff roadmap has >=1 unticked "- [ ]" item tagged [ROUTINE], INDEPENDENT of the verdict. A repo classified "review" (unaudited commits) that ALSO has open [ROUTINE] work must report hasRoutine=true — this lets the --fable-down path keep executors busy on routine work in repos whose review must wait for the next strong turn.
- openHard per repo: the COUNT of unticked "- [ ]" EXECUTABLE [HARD — strong model] items in roadmap (apply the EXECUTABLE-HARD test above — do NOT count GATED/decision-gate/deferred/multi-session items), INDEPENDENT of the verdict. 0 when none (incl. when every open HARD item is gated). The supervisor uses it to surface the HARD backlog and (on an apex Opus session) to size the hard verdict.
- strongRecheckPending per repo: true iff toml_block has a non-empty last_strong_ckpt AND fable_rechecked is false (or absent/empty). This is the DURABLE, model-tracked Fable-bonus-recheck queue (id:e030): a strong (Opus) review/handoff/hard checkpoint that has not yet had its optional Fable recheck. It SURVIVES a later executor (sonnet) checkpoint that overwrites last_ckpt and masks the latest-tag fable-standin signal — so prefer this field over the tag grep when deciding optional-recheck candidacy. Report false when last_strong_ckpt is absent/empty or fable_rechecked is true (or a date).
- standin per repo: true iff latest_ckpt_msg contains the literal token "fable-standin" (the last relay checkpoint was produced by Opus standing in for Fable, so the repo still needs an independent Fable re-review and its specs are provisional). Report false when latest_ckpt is empty.
- intensive per repo (id:8d52): a resource name STRING (e.g. "local-llm") iff this repo's next unit of work is resource-heavy — set it when EITHER (a) toml_block has intensive = "<resource>" (or intensive = true → use "local-llm"), OR (b) the top open "- [ ]" item the unit would work in roadmap carries an "[INTENSIVE — <resource>]" modifier (parse the resource between "— " and "]"). Otherwise leave it "" (empty). These units are NEVER auto-dispatched (OOM risk) — they are gated behind --allow-intensive.

(Injected high-priority units (id:baf1) are handled ONCE by the PRELUDE via inject.sh take — NOT here. You only classify the own repos given to you.)

SKIPPED ROLLUP (id:be62): populate "skipped" with every repo from YOUR list that you classified "idle" → {repo, reason: "idle — in sync, no open work"}. (Non-own/excluded repos are the prelude's job — not yours.) This is distinct from "surfaced" (needs-attention: dirty / diverged / claimed-elsewhere / stale-worktree).

Return {units, surfaced, skipped} covering EXACTLY the repos in your list — each appears exactly once across units (verdict "idle" included) and surfaced; an idle repo ALSO gets a "skipped" entry.`
  // Only CHANGED repos pay for an LLM shard (id:c3a6); a round where every repo is cached runs
  // zero shards and is still a valid round (shardOk seeded true below).
  const shardResults = changed.length
    ? await parallel(chunks.map((chunk) => () =>
        agent(shardPrompt(chunk), { label: `discover-shard:${chunk.length}`, phase: 'Discover', schema: SHARD_SCHEMA, model: 'sonnet' })
      ))
    : []
  // Merge the shard classifications + the cached (reused) verdicts + the prelude's injected units +
  // non-own skipped rollup into the single discovery object the rest of runRound consumes
  // (byte-identical shape).
  const units = [], surfaced = [], skipped = [...(prelude.skippedConfig || []), ...reusedIdle]
  let shardOk = changed.length === 0  // all repos served from cache → valid round, zero shards (id:c3a6)
  shardResults.forEach((r, i) => {
    if (!r) {
      // Network-resilience: a discover shard that died (transient API / connection drop, AFTER
      // the harness's own retries) must NOT silently drop its repos — SURFACE them so the gap is
      // visible, not invisible. They are re-classified next round (fresh discovery), so a blip
      // costs one round, never a silently-skipped repo. (chunks[i] aligns with shardResults[i].)
      const lost = chunks[i] || []
      log(`relay-loop: discover-shard ${i} failed (network/API) — surfacing ${lost.length} unclassified repo(s)`)
      for (const repo of lost) {
        surfaced.push({ repo: repo.repo, reason: 'discover shard failed (transient API/network drop) — not classified this round; retried next round' })
      }
      return
    }
    shardOk = true
    units.push(...(r.units || []))
    surfaced.push(...(r.surfaced || []))
    skipped.push(...(r.skipped || []))
  })
  // id:c3a6 — cache the FRESHLY-classified units keyed by this round's signature, THEN fold in the
  // reused (cached) verdicts. Reused units already sit in the cache under the same sig, so only fresh
  // ones are written. Surfaced / idle-without-unit repos are NOT cached → they re-classify next round
  // (safe over-invalidation). Injected units are never cached (consumed each round by inject.sh take).
  for (const u of units) { const sig = sigByRepo[u.repo]; if (sig) state.discoverCache[u.repo] = { sig, unit: u } }
  units.push(...reusedUnits)
  units.push(...(prelude.injectedUnits || []))
  // shardOk = at least one shard succeeded → build discovery (failed shards' repos are surfaced).
  // All shards failed (total network outage) → discovery stays null → the round fails gracefully
  // and the outer loop stops after completed rounds (resumable via Workflow resumeFromRunId).
  if (shardOk) discovery = { runId: prelude.runId, ts: prelude.ts, units, surfaced, skipped }
  else log('relay-loop: all discovery shards failed this round (network outage?) — round fails, completed work preserved')
}

if (!discovery) {
  log('relay-loop: discovery prelude/shards failed this round')
  return { failed: true }
}

// Fable-return re-review (id:9821): after a clean handoff a repo's HEAD *is* its
// fable-ckpt tag, so it has no unaudited commits and the classifier calls it
// execute/idle — it would otherwise never be re-reviewed. On a real-Fable session,
// ELEVATE any repo whose latest checkpoint was an Opus standin (unit.standin) to a
// review verdict so the standin handoff/review gets an independent Fable audit. Repos
// already classified review (genuine unaudited commits) or handoff (need fresh strong
// work anyway) are left as-is. Dormant on Opus and --fable-down sessions
// (SESSION_IS_FABLE false), so Opus never re-reviews its own standin work.
// strongRecheckPending (id:e030) is the DURABLE, model-tracked signal: a strong Opus
// checkpoint whose optional Fable recheck has not yet happened (relay.toml
// last_strong_ckpt set + fable_rechecked=false). Unlike u.standin (the latest-TAG grep),
// it survives a later executor checkpoint that masks the tag — so a masked pending recheck
// still elevates. Either signal qualifies a repo as an optional-recheck candidate; both
// remain OPTIONAL/non-gating (Opus-apex @fable-optional-recheck) — they only re-route an
// otherwise execute/idle repo to a Fable review, never block or defer real work.
if (SESSION_IS_FABLE && !FABLE_DOWN) {
  let elevated = 0
  for (const u of discovery.units) {
    const pending = u.standin || u.strongRecheckPending
    if (pending && (u.verdict === 'execute' || u.verdict === 'idle')) {
      const src = u.strongRecheckPending
        ? 'relay.toml last_strong_ckpt has fable_rechecked=false (durable, survives executor-checkpoint masking, id:e030)'
        : 'latest relay-ckpt carries fable-standin'
      u.reason = `optional Fable recheck (${src} — Opus stood in for Fable; independent audit pending). Prior verdict: ${u.verdict}. ${u.reason || ''}`.trim()
      u.verdict = 'review'
      elevated++
    }
  }
  if (elevated) log(`relay-loop: elevated ${elevated} repo(s) to review for optional Fable re-audit (id:9821 + durable queue id:e030)`)
}

// Sort: verdict class first (D3 invariant), then income repos win slot contention
// within a class (user directive 2026-06-12: prefer income-relevant tasks), then the
// fable-standin tiebreaker (user directive 2026-06-13; see standInRank above).
// Injected units (id:baf1) outrank everything — they are explicit, high-priority user
// requests; only then verdict class (D3), income, fable-standin.
let actionable = discovery.units
  .filter(u => u.verdict !== 'idle')
  .sort((a, b) =>
    ((b.injected ? 1 : 0) - (a.injected ? 1 : 0)) ||
    (PRIORITY[a.verdict] - PRIORITY[b.verdict]) ||
    ((b.income ? 1 : 0) - (a.income ? 1 : 0)) ||
    (standInRank(a) - standInRank(b))
  )

// HARD-execute gate (id:da26): a "hard" unit dispatches an Opus-apex child to work ONE
// bounded [HARD] item. It is ONLY dispatched when STRONG_MODEL === 'claude-opus-4-8'
// (the apex tier). When the strong tier is Fable (or the -d defer path with no Opus
// substitute), HARD work stays for Fable handoff-C5 / review-step-6 as today — NEVER
// dispatched on the Sonnet execute tier. Non-apex hard units are pulled out of the
// dispatch queue and surfaced as Queued with a clear reason (next apex turn picks them up).
let hardDeferred = []
if (STRONG_MODEL !== 'claude-opus-4-8') {
  const kept = []
  for (const u of actionable) {
    if (u.verdict === 'hard') {
      hardDeferred.push(u)
    } else {
      kept.push(u)
    }
  }
  actionable = kept
  if (hardDeferred.length) {
    log(`relay-loop: HARD-execute requires apex Opus (STRONG_MODEL=${STRONG_MODEL}) — deferring ${hardDeferred.length} hard unit(s) for Fable handoff-C5/review-step6: ${hardDeferred.map(u => u.repo).join(', ')}`)
  }
}

// --fable-down / -d DEFER path: gated on STRONG_MODEL === 'claude-fable-5', i.e. -d with
// NO Opus substitute. The strong model is genuinely unavailable, so review/handoff units
// cannot run. Rather than idle the executors, DEMOTE any "review" repo that also has open
// [ROUTINE] work to an execute unit and keep working it. Rationale: D3's review-first
// precedence exists only to keep the unreviewed window SHORT — but if review literally
// cannot run this turn, deferring executable work shortens no window, it just wastes
// executor capacity (user directive 2026-06-13). The next Fable turn reviews the whole
// range. Handoff repos are NOT demoted (no proper ROADMAP → no executor work); review
// repos with no routine work are deferred and surface in RELAY_STATUS for the next turn.
//
// When -d is combined with STRONG_TIER=opus (STRONG_MODEL === 'claude-opus-4-8') this
// block is SKIPPED entirely: Opus SUBSTITUTES for the unavailable Fable, so review/handoff
// units dispatch normally (marked fable-standin via standInSuffix) — nothing is deferred.
let fableDownDeferred = []
if (FABLE_DOWN && STRONG_MODEL === 'claude-fable-5') {
  const kept = []
  const demoted = []
  for (const u of actionable) {
    if (u.verdict === 'execute') { kept.push(u); continue }
    if (u.verdict === 'review' && u.hasRoutine) {
      demoted.push({
        ...u,
        verdict: 'execute',
        reason: `demoted to execute (--fable-down: review unavailable, repo has open [ROUTINE] work). Original review reason: ${u.reason}`,
      })
    } else {
      fableDownDeferred.push(u)
    }
  }
  // All-execute now, so PRIORITY ties; injected units (id:baf1) still outrank, then income
  // repos win slot contention, then the fable-standin tiebreaker prefers Fable-vetted roadmaps.
  actionable = kept.concat(demoted).sort((a, b) =>
    ((b.injected ? 1 : 0) - (a.injected ? 1 : 0)) ||
    ((b.income ? 1 : 0) - (a.income ? 1 : 0)) ||
    (standInRank(a) - standInRank(b))
  )
  if (demoted.length) {
    log(`relay-loop: --fable-down — demoted ${demoted.length} review unit(s) with open [ROUTINE] work to execute: ${demoted.map(u => u.repo).join(', ')}`)
  }
  if (fableDownDeferred.length) {
    log(`relay-loop: --fable-down — deferring ${fableDownDeferred.length} strong-model unit(s) (no routine work): ${fableDownDeferred.map(u => `${u.repo}(${u.verdict})`).join(', ')}`)
  }
}

// [INTENSIVE] partition (id:8d52): pull resource-heavy units OUT of the parallel wave — they
// are never auto-run (OOM risk). With --allow-intensive/--afk they run serially-alone AFTER
// the wave (intensiveUnits); otherwise they are surfaced as skipped (intensiveDeferred).
let intensiveUnits = []
let intensiveDeferred = []
{
  const normal = []
  for (const u of actionable) {
    if (u.intensive) (ALLOW_INTENSIVE ? intensiveUnits : intensiveDeferred).push(u)
    else normal.push(u)
  }
  actionable = normal
}
if (intensiveUnits.length) log(`relay-loop: --allow-intensive — ${intensiveUnits.length} [INTENSIVE] unit(s) will run SERIALLY-ALONE after the wave: ${intensiveUnits.map(u => `${u.repo}(${u.intensive})`).join(', ')}`)
if (intensiveDeferred.length) log(`relay-loop: ${intensiveDeferred.length} [INTENSIVE] unit(s) NOT dispatched — need --allow-intensive/--afk: ${intensiveDeferred.map(u => `${u.repo}(${u.intensive})`).join(', ')}`)

// Refresh the cross-round accumulator's per-round views (completed/reviewMe persist).
state.runId = state.runId || discovery.runId
state.ts = discovery.ts
state.queued = [
  ...actionable.map(u => ({ repo: u.repo, verdict: u.verdict })),
  ...hardDeferred.map(u => ({ repo: u.repo, verdict: `hard (deferred: HARD-execute needs apex Opus; STRONG_MODEL=${STRONG_MODEL} — left for Fable handoff-C5/review-step6)` })),
  ...fableDownDeferred.map(u => ({ repo: u.repo, verdict: `${u.verdict} (deferred: --fable-down, strong model skipped)` })),
  ...intensiveDeferred.map(u => ({ repo: u.repo, verdict: `intensive:${u.intensive} (skipped — needs --allow-intensive/--afk; never auto-run, OOM risk id:8d52)` })),
]
state.blocked = discovery.surfaced.map(s => ({ repo: s.repo, reason: s.reason, worktreePath: '-' }))
state.skipped = (discovery.skipped || []).map(s => ({ repo: s.repo, reason: s.reason }))   // id:be62

log(`relay-loop: ${actionable.length} actionable units (${discovery.units.length} own repos, ${discovery.surfaced.length} surfaced)`)
scheduleStatusWrite(state)

// No actionable units this round (incl. --fable-down with no executor work) → a dry
// round; the outer loop counts consecutive dry rounds toward "backlog drained".
if (actionable.length === 0 && intensiveUnits.length === 0) {
  if (FABLE_DOWN && STRONG_MODEL === 'claude-fable-5') log('relay-loop: --fable-down — no executor work this round, strong work deferred')
  return { actionable: 0, produced: 0 }
}

// ── Phase 2+3: Dispatch pool + serialized integration ──

phase('Dispatch')

const queue = [...actionable]
const debts = []
let unitsDispatched = 0
let roundCapHit = false   // per-round MAX_UNITS cap; distinct from quotaStopped (run-ending)

function refDoc(verdict) {
  if (verdict === 'review') return '~/.claude/skills/relay/references/review.md'
  if (verdict === 'handoff') return '~/.claude/skills/relay/references/handoff.md'
  // hard (id:da26): reuse handoff.md's C5 "HARD item" section — its red-green-refactor +
  // "only if small enough to finish safely" rule is exactly the HARD-execute discipline.
  if (verdict === 'hard') return '~/.claude/skills/relay/references/handoff.md (its C5 HARD-item section)'
  return '~/.claude/skills/relay/references/executor-contract.md'
}

// Deterministic worktree path + branch for a unit — the child creates them, and the
// API-error recovery path (runUnit catch / integrate null-guard) needs the same names
// to find a failed child's partial work instead of orphaning it.
const worktreePathFor = (unit) => `~/.cache/relay/worktrees/${unit.repo}/${state.runId}-${unit.verdict}`
const branchFor = (unit) => `relay/${state.runId}-${unit.verdict}`

function unitPrompt(unit) {
  const wt = worktreePathFor(unit)
  const branch = branchFor(unit)
  return `You are a relay ${unit.verdict.toUpperCase()} child for the repo ${unit.repo} (main checkout: ${unit.path}).

FIRST acquire the cross-session repo lease (id:ebfb): run ~/.claude/skills/relay/scripts/claim.sh acquire ${unit.repo} --run ${state.runId} --mode ${unit.verdict} --worktree ${wt}. (The --worktree anchors id:7570 long-child liveness: a claim whose worktree has commits beyond main stays held past the TTL, so a >30-min child isn't stolen mid-work.) If it exits NON-ZERO, another live relay run/session already holds this repo — STOP IMMEDIATELY: do NOT create a worktree, do NOT do any work, and return contract_met=false with handback="claimed by another relay run (cross-session lease id:ebfb): " plus the holder JSON it printed to stderr. The supervisor releases the lease at integration, so do not release it yourself. Only if acquire SUCCEEDS, continue:
${unit.intensive ? '\nThis is an [INTENSIVE — ' + unit.intensive + '] unit (id:8d52): ALSO acquire the exclusive RESOURCE lease before any heavy work — ~/.claude/skills/relay/scripts/claim.sh acquire resource:' + unit.intensive + ' --run ' + state.runId + ' --mode intensive. If it exits non-zero (another relay run is using ' + unit.intensive + '), STOP: return contract_met=false, handback="resource ' + unit.intensive + ' busy (another relay run)". The supervisor releases it at integration.\n' : ''}
Create your worktree first: git -C ${unit.path} worktree add ${wt} -b ${branch} HEAD
Work EXCLUSIVELY in that worktree. Classifier verdict reason: ${unit.reason}. Last checkpoint tag: ${unit.lastCkpt || '(none)'}.

${unit.injected ? 'This is a USER-INJECTED high-priority task (id:baf1). ' + (unit.inject_item ? 'Work specifically the ROADMAP.md item tagged <!-- id:' + unit.inject_item + ' -->. ' : '') + (unit.inject_prompt ? 'User instruction: ' + unit.inject_prompt + ' ' : '') + 'Otherwise follow the verdict procedure below.\n' : ''}Procedure: follow ${refDoc(unit.verdict)} exactly. Read ~/.claude/skills/relay/references/conventions.md for environment facts and relay invariants before starting.
${unit.verdict === 'execute' ? 'Work the open [ROUTINE] items in ROADMAP.md under the executor contract. Stop at a natural boundary; never start an item you cannot finish.' : ''}
${unit.verdict === 'hard' ? 'You are an Opus-apex HARD-execute child (id:da26). Pick the TOP open "- [ ]" item tagged [HARD — strong model] in ROADMAP.md and SIZE it first. Model your discipline on handoff.md C5 "only if small enough to finish safely": only implement the item if you can finish it cleanly and green within this turn — full red-green-refactor, verify-before-merge. If it is too large, contains nested/multi-session scope, or you cannot make the test suite green safely, do NOT half-do it: set contract_met=false and explain the sizing in handback. CRITICAL (id:8b1f) — a SIZE-OUT / GATED refusal (you decided NOT to start) must leave the worktree COMPLETELY CLEAN: make NO commit, and do NOT write the rationale into RELAY_LOG.md / ROADMAP.md / REVIEW_ME.md in the worktree. The rationale goes ONLY in the returned `handback` field. Reason: the integrator never merges a handback, so ANY commit you make on a refusal strands forever as an orphan worktree (the bug behind id:a4e9); a CLEAN worktree is auto-reaped (id:3ac8). The "write a HANDBACK paragraph to RELAY_LOG.md and commit" step in handoff.md C5 applies ONLY to a genuine mid-item CUTOFF where you already committed real work and need resume provenance — NOT to a pre-start sizing refusal (the item stays open for a manual/next-turn strong session). When you DO finish: tick the item\'s checkbox ONLY if the work is genuinely green (all tests pass — never tick to manufacture a pass), append its done-note, commit in the worktree, and make the full test suite green. Work ONE bounded HARD item only — never start a second.' : ''}
${unit.verdict === 'handoff' ? 'Run checkpoints C1-C4. C5 (HARD execution) only if the top HARD item is small enough to finish safely; otherwise leave it specced.' : ''}
${unit.verdict === 'review' ? 'Run the full trust-but-verify procedure including the test-integrity audit. Single-id-two-views (D2): when you promote a ROADMAP item for work TODO.md already tracks under an <!-- id:XXXX -->, REUSE that token; mint a fresh one via ~/.claude/skills/meeting/append.sh new-ids N ' + unit.path + ' ONLY for genuinely new work — NEVER invent tokens, and never duplicate-id already-tracked work. When you close a ROADMAP item whose id also lives in TODO.md, tick the TODO line too. Reverse-handoff (review.md §5b): qualify+size any unqualified TODO/ROADMAP items added by /meeting or manual edits since the last checkpoint (mini-handoff) — reuse their id. After re-deriving the roadmap, set routine_open = the number of OPEN (unticked) [ROUTINE] items remaining — the supervisor uses it to re-enqueue an execute unit this same pool.' : ''}

Hard rules: commit in the worktree as you go; NEVER push; NEVER tag; NEVER run git-diary-workflow or todo-update; never prompt the user. If you cannot meet the contract, set contract_met=false and explain in handback.

Return: contract_met, branch ("${branch}"), worktree ("${wt}"), summary (one line for the checkpoint tag message), review_me_count (open REVIEW_ME.md boxes you wrote, else 0), diary_fragment (one paragraph), handback ("" if none), routine_open (review units: open [ROUTINE] count after re-derivation; 0 for handoff/execute).${unit.verdict === 'review' ? ' ALSO (review units only, id:3826 — feeds the gaming-flag rate logger; see review.md §6 return schema): verified_green (array of ROADMAP ids you confirmed genuinely green this review, [] if none), gaming_flags (array of "<id>: <reason>" strings for every DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT or judgment flag you raised, [] if none), reopened (array of ROADMAP ids you reopened, [] if none).' : ''}`
}

// Auto-resume after an API-error / terminal child failure (handoff only — its
// per-checkpoint commits make it resumable; review/execute are single-shot and instead
// surface as recoverable handbacks). The resume child inspects the worktree the failed
// child already created and continues from its last committed checkpoint to completion,
// committing per stage so a re-failure loses at most one more stage.
function resumePrompt(unit) {
  const wt = worktreePathFor(unit)
  const branch = branchFor(unit)
  return `You are RESUMING an interrupted relay HANDOFF for repo ${unit.repo} (main checkout: ${unit.path}). A prior child was killed (API error / timeout) mid-handoff.

The worktree may already exist at ${wt} on branch ${branch} with some checkpoints committed.
1. If that worktree does NOT exist or has NO committed "relay(handoff): C*" commits, there is nothing to resume: return contract_met=false, handback="no resumable checkpoints — fresh handoff needed", branch="${branch}", worktree="${wt}". Do not create anything.
2. Otherwise work EXCLUSIVELY in that worktree. Read its committed ROADMAP.md / docs to see which checkpoints (C1 docs, C2 roadmap, C3 red tests, C4 bdd, C5 hard) are already done (git -C ${wt} log --oneline), then CONTINUE from the next stage to completion per ~/.claude/skills/relay/references/handoff.md. Use ONLY the id tokens already in the committed ROADMAP.md; never invent tokens. Commit after EACH stage (so another failure loses at most one stage). C5 only if the top HARD item is small enough to finish safely.

Hard rules: NEVER push; NEVER tag; NEVER run git-diary-workflow/todo-update; never prompt the user. You are Opus standing in for Fable — flag judgment calls in REVIEW_ME.md.

Return: contract_met, branch ("${branch}"), worktree ("${wt}"), summary (one line), review_me_count, diary_fragment, handback ("" if none).`
}

async function quotaGate(tier) {
  if (quotaStopped) return false
  // Throttle (see QUOTA_CHECK_EVERY above): only every Nth call actually spawns the check
  // agent; the rest reuse the last verdict. quotaChecks++ is synchronous (no await before
  // it), so concurrent lanes see the updated counter and only ONE lane per window spawns
  // an agent — freeing the other slots for real work.
  if (quotaChecks++ % QUOTA_CHECK_EVERY !== 0) return lastQuotaOk
  // Forward quota-policy knobs from args into the quota-stop env so a self-looping run
  // self-enforces the cap with no orchestrator between rounds. RELAY_QUOTA_DECAY_7D gives
  // the time-decaying 7d/Sonnet cap (e.g. "0.70:0.10"); per-bucket/general thresholds
  // still work. Only forward what's set (default behaviour unchanged).
  const envPairs = ['RELAY_QUOTA_THRESHOLD', 'RELAY_QUOTA_DECAY_7D',
    'RELAY_QUOTA_THRESHOLD_FIVE_HOUR', 'RELAY_QUOTA_THRESHOLD_SEVEN_DAY', 'RELAY_QUOTA_THRESHOLD_SEVEN_DAY_SONNET']
    .filter(k => A[k] !== undefined && A[k] !== null && A[k] !== '')
    .map(k => `${k}=${A[k]}`)
  const thresholdEnv = envPairs.length ? envPairs.join(' ') + ' ' : ''
  // id:4267 — pass the RUN-TOTAL agent count, not the per-round count. quota-stop.sh hard-
  // caps at --agents >= 200 (a runaway-spawn seatbelt spanning the WHOLE self-feeding run), but
  // unitsDispatched resets to 0 each round (let unitsDispatched = 0 in runRound), so with
  // MAX_UNITS=20 it never exceeds 20 and the 200-agent seatbelt could NEVER fire across a
  // multi-round run — a 30-round run could spawn hundreds of agents unchecked. totalDispatched
  // is the across-all-rounds accumulator and is the value the seatbelt is meant to gate on.
  // (Same per-round-vs-run-total accounting family as id:2d20's drain fix.)
  const v = await agent(
    `Run this command and report the result: ${thresholdEnv}~/.claude/skills/relay/scripts/quota-stop.sh --tier ${tier} --agents ${totalDispatched} --wall 0
Return exitCode (0 = proceed, 1 = stop, 2 = uncertain/stale-cache) and, if /tmp/claude-usage-cache.json is readable, one bucket entry per quota bucket with pctRemaining (= 100 - utilization percent) and resetTime when present.`,
    { label: `quota:${tier}`, phase: 'Dispatch', schema: QUOTA_SCHEMA, model: 'haiku' }
  )
  if (v && v.buckets && v.buckets.length) state.quota = v.buckets
  // id:8c35 — distinguish exit codes instead of collapsing both to quotaStopped:
  //   exit 0 → proceed
  //   exit 1 → real threshold exhaustion (a specific bucket hit the cap)
  //   exit 2 → uncertain/stale-cache: can't verify, conservative STOP
  //   agent death / missing → fail-safe STOP
  if (!v || v.exitCode !== 0) {
    quotaStopped = true
    // Derive the human-readable + machine-readable stop category:
    if (!v) {
      stopReason = 'quota-stale-cache'  // agent death treated as stale/uncertain
      log(`relay-loop: quota gate STOP — reason=quota-stale-cache (agent failed; tier=${tier}) — draining in-flight units and integration debt`)
    } else if (v.exitCode === 2) {
      stopReason = 'quota-stale-cache'
      log(`relay-loop: quota gate STOP — reason=${stopReason} (cache stale or refresh unavailable; tier=${tier}) — draining in-flight units and integration debt`)
    } else {
      // exit 1: real exhaustion; pick the first over-threshold bucket when available
      const exhaustedBucket = (v.buckets || []).find(b => b.pctRemaining <= 10)
      stopReason = exhaustedBucket ? `quota-exhausted:${exhaustedBucket.bucket}` : 'quota-exhausted:unknown'
      log(`relay-loop: quota gate STOP — reason=${stopReason} (tier=${tier}) — draining in-flight units and integration debt`)
    }
    return false
  }
  return true
}

async function integrate(unit, report) {
  if (!report) {
    // Child failed terminally (and auto-resume, for handoffs, didn't recover). Record a
    // RECOVERABLE handback with the deterministic worktree path + resume hint, never an
    // orphan with worktreePath '-'. Any per-checkpoint commits survive on disk for a
    // manual/next-turn resume (handoff: re-dispatch reads them; see handoff.md §Resuming).
    state.blocked.push({
      repo: unit.repo,
      reason: `child agent failed/skipped (API error or terminal failure); ${unit.verdict === 'handoff' ? 'auto-resume did not complete' : 'no auto-resume for ' + unit.verdict}. Any committed checkpoints are preserved in the worktree — re-run /relay to resume (handoff continues from the last checkpoint).`,
      worktreePath: worktreePathFor(unit),
    })
    scheduleStatusWrite(state)
    return
  }
  if (!report.contract_met) {
    // HANDBACK: not merged; worktree held on disk for a human/strong turn.
    state.blocked.push({ repo: unit.repo, reason: report.handback || 'contract_met=false', worktreePath: report.worktree })
    scheduleStatusWrite(state)
    return
  }
  const standInSuffix = (unit.verdict !== 'execute' && STRONG_MODEL === 'claude-opus-4-8') ? ', fable-standin' : ''
  // A STRONG unit (review/handoff/hard — anything but the sonnet execute tier) checkpoints
  // a strong-model decision. We persist a durable, model-tracked Fable-bonus-recheck queue
  // entry into relay.toml (last_strong_ckpt/strong_model/fable_rechecked) so a LATER executor
  // checkpoint that overwrites last_ckpt does NOT mask the pending optional Fable recheck
  // (the masking bug id:e030). Executor (sonnet) checkpoints must never clear it.
  const isStrong = unit.verdict !== 'execute'
  // A real-Fable REVIEW unit IS the optional recheck: when this session's strong tier is
  // genuine Fable and it reviews a repo, mark the durable queue rechecked rather than
  // resetting it (id:e030 consume side; keeps @fable-optional-recheck idempotent).
  const isFableRecheck = SESSION_IS_FABLE && unit.verdict === 'review'
  // hard (id:da26): Opus-apex strong-execute of one [HARD] item. Distinct checkpoint
  // label from review/handoff (which use "reviewer (...)") so the relay log reads as
  // strong-execute work; it still carries fable-standin (apex Opus work invites an
  // optional Fable recheck) via the shared standInSuffix.
  const label = unit.verdict === 'execute'
    ? 'executor (sonnet, relay-loop)'
    : unit.verdict === 'hard'
      ? `strong-execute (${STRONG_MODEL}${standInSuffix}, relay-loop)`
      : `reviewer (${STRONG_MODEL}${standInSuffix}, relay-loop)`
  const result = await agent(
    `You are the serialized integrator of the relay pool. Integrate ONE completed unit, strictly in this order, for repo ${unit.repo} at ${unit.path}:

0. Release this repo's cross-session lease (id:ebfb) — the child's work is done; do this FIRST so it runs whether the merge below succeeds or aborts: ~/.claude/skills/relay/scripts/claim.sh release ${unit.repo} --run ${state.runId}  (run-scoped — a no-op if this run does not hold it).${unit.intensive ? ` Also release the exclusive resource lease (id:8d52): ~/.claude/skills/relay/scripts/claim.sh release resource:${unit.intensive} --run ${state.runId}.` : ''}
1. Verify the main checkout working tree is clean (git -C ${unit.path} status --porcelain). If dirty, abort: return merged=false with reason.
1b. Belt-and-suspenders (id:c3f7) — never checkpoint on a base that diverged from origin (the ai-codebench incident): run ~/.claude/skills/relay/scripts/sync-origin.sh ${unit.path}. If its output starts with "diverged", ABORT: return merged=false with reason "base diverged from origin — manual reconcile (id:c3f7)". (Output "ok"/"behind N"/"no-upstream" → proceed; the discovery step already fast-forwarded behind-only repos.)
2. git -C ${unit.path} merge --no-ff ${report.branch} -m "merge(relay): ${report.summary}"
   On conflict: git -C ${unit.path} merge --abort, return merged=false with reason (worktree stays on disk).
3. ~/.claude/skills/relay/scripts/ckpt-tag.sh ${unit.path} -m "${report.summary}" -l "${label}"
   It prints the new tag name — capture it as ckptTag.
4. ~/.claude/skills/git-diary-workflow/git-lock-push.sh --ff-only ${unit.path}
   pushStatus = "pushed" on success, otherwise the error summary.
5. git -C ${unit.path} worktree remove --force ${report.worktree} && git -C ${unit.path} branch -d ${report.branch}
   (--force is required and safe here: the merge+tag+push above already integrated the committed branch work, so the only thing --force discards is incidental untracked build artifacts the child left behind, e.g. a uv.lock from running tests. Without --force, worktree remove fails on any untracked file and the worktree+branch silently orphan in ~/.cache/relay/worktrees/ — id:d187.)
6. Update ~/.config/relay/relay.toml for [repos.${unit.repo}] via the flock'd single-writer (id:ebfb step 2) — for EACH field run \`~/.claude/skills/relay/scripts/relay-state-write.sh toml-set ${unit.repo} <key> <value>\` (value VERBATIM: quote strings e.g. '"<tag>"', bare for bool e.g. false; NEVER hand-edit relay.toml): set last_ckpt to the new tag${unit.verdict === 'review' ? ", set last_review to today's date (ISO)" : ''}${unit.verdict === 'handoff' ? ", set handoff_date to today's date (ISO) and status to \"handed-off\"" : ', set status to "active"'}. Change ONLY this repo's block.${isStrong ? `
6b. STRONG checkpoint — this is a ${unit.verdict} unit produced by the strong model (${STRONG_MODEL}). ${isFableRecheck ? `This session's strong tier is REAL Fable, and this is a review — it IS the optional Fable recheck (id:e030 consume side). Record the durable Fable-bonus-recheck queue entry for [repos.${unit.repo}]: set last_strong_ckpt = "<the new tag>", strong_model = "${STRONG_MODEL}", and fable_rechecked = "<today's date, ISO>" (the recheck just happened — mark it done, do NOT set false).` : `Record the durable Fable-bonus-recheck queue entry for [repos.${unit.repo}]: set last_strong_ckpt = "<the new tag>", strong_model = "${STRONG_MODEL}", and fable_rechecked = false (an Opus-standin/strong checkpoint that still invites an optional Fable recheck).`} These keys survive a LATER executor (sonnet) checkpoint that overwrites last_ckpt — so the pending optional Fable recheck stays visible even when masked. Write all three via the same flock'd relay-state-write.sh toml-set helper (overwrite if present; fable_rechecked is a BARE value: false, or '"<ISO date>"' when rechecked). Change ONLY this repo's block.` : `
6b. EXECUTOR checkpoint — this is an execute unit (sonnet). Do NOT touch last_strong_ckpt, strong_model, or fable_rechecked: an executor checkpoint must never clear the pending Fable-bonus-recheck queue (that is exactly the masking bug id:e030 fixes). Leave those keys untouched.`}
7. L2 push-seed inputs (id:c855) — compute these LAST, AFTER steps 1-6 so they reflect the fully-settled post-integrate state on main (the toml block, removed worktree dir, and pushed HEAD all feed the signature):
   a. postSig — recompute this repo's discovery signature so next round's prelude can match it: echo the one-repo object and pipe it to discover-sig.sh, then read the "sig" field:
        printf '%s' '{"repos":[{"repo":"${unit.repo}","path":"${unit.path}"}],"liveClaims":[]}' | ~/.claude/skills/relay/scripts/discover-sig.sh
      It prints one JSON line {"repo":...,"sig":"<hex or empty>"}. Set postSig = that sig verbatim (may be "" — a fail-open sentinel; pass it through, do NOT invent a hash).
   b. openRoutine — count of unticked routine items: git -C ${unit.path} grep -c -E '^- \\[ \\].*\\[ROUTINE\\]' HEAD -- ROADMAP.md 2>/dev/null (0 if the file/marker is absent; a plain count, not a list).
   c. openHard — count of unticked HARD items: git -C ${unit.path} grep -c -E '^- \\[ \\].*\\[HARD' HEAD -- ROADMAP.md 2>/dev/null (0 if absent). Count ALL [HARD items (gated or not) — the supervisor only push-seeds 'idle' when BOTH counts are 0, so over-counting here is safe (it just declines to cache).
8. Return merged=true, ckptTag, pushStatus, ts (current ISO timestamp), postSig, openRoutine, openHard.

Never push any other repo, never force-push, never resolve conflicts yourself.`,
    { label: `integrate:${unit.repo}`, phase: 'Integrate', schema: INTEGRATE_SCHEMA, model: 'sonnet' }
  )
  if (result && result.merged) {
    if (result.ts) state.ts = result.ts
    state.completed.push({ repo: unit.repo, mode: unit.verdict, ckptTag: result.ckptTag || '?', pushStatus: result.pushStatus || '?' })
    pushEvent('integrate', { repo: unit.repo, mode: unit.verdict, ckpt: result.ckptTag || '?', push: result.pushStatus || '?' })  // id:c8b6
    // L2 push-seed the discovery cache (id:c855): a just-integrated repo's sig CHANGES (new
    // ckpt tag + RELAY_LOG/ROADMAP), so without this the next round re-classifies (an LLM
    // shard — the dominant discover cost, id:9cb1) the exact repo the pool just finished.
    // The integrator recomputed the post-merge sig + open-work counts; seed an 'idle' cache
    // entry ONLY when the repo is PROVABLY drained (zero open [ROUTINE] AND zero open [HARD]
    // — no EXECUTABLE-HARD judgment needed, so no under-dispatch risk). Any open work, or a
    // missing/empty (fail-open) sig → DELETE the entry so the repo re-classifies next round.
    // FAIL-OPEN preserved: the seeded sig only HITS when next round's prelude recomputes a
    // byte-identical sig (no external change since integrate); any human commit / origin
    // advance / ROADMAP edit changes the sig → MISS → re-classify. Under-invalidation (a
    // stale 'idle' masking real work) is the one hazard we refuse — hence drained-only + the
    // sig gate. An idle entry skips the shard AND is not dispatched (it carries no unit).
    state.discoverCache = state.discoverCache || {}
    if (result.postSig && (result.openRoutine || 0) === 0 && (result.openHard || 0) === 0) {
      state.discoverCache[unit.repo] = { sig: result.postSig, idle: true, reason: 'idle — drained, cached post-integrate (id:c855)' }
    } else {
      delete state.discoverCache[unit.repo]
    }
    if (report.review_me_count) {
      state.reviewMe.push({ repo: unit.repo, count: report.review_me_count, path: `${unit.path}/REVIEW_ME.md` })
    }
    // id:3826 — gaming-flag rate logger: append one JSON line per review integration to
    // ~/.claude/logs/relay-gaming-flags.log. Records closed-item ids, flags, reopened, and
    // verified_green for cross-repo aggregate telemetry. NOT per-repo findings (those live
    // in RELAY_LOG/REVIEW_ME already) — this is the base-rate signal Riku mandated so
    // "if flags start firing" can be measured, not just noticed.
    //
    // DEFERRED-FLEET SEAM: to escalate, spawn parallel() refuters over gaming_flags[] or
    // verified_green[] here; see id:2909 meeting 2026-06-15 D1 for the evidence gate.
    if (unit.verdict === 'review' && report) {
      logGamingFlags(unit.repo, state.runId, report, result.ts || state.ts)
    }
  } else {
    const reason = (result && result.reason) || 'integration failed'
    state.blocked.push({ repo: unit.repo, reason, worktreePath: report.worktree })
    pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason })  // id:c8b6
  }
  scheduleStatusWrite(state)
}

// id:3826 — Append a gaming-flags telemetry line to relay-gaming-flags.log.
// Called (non-blocking, fire-and-forget) after a REVIEW unit integrates successfully.
// The log line is JSON: {repo, runId, ts, closed_ids, gaming_flags, reopened, verified_green}.
// Creates the log file if absent (the agent uses >> which creates on first write).
// The Workflow JS cannot write files directly; we spawn a minimal Haiku agent.
function logGamingFlags(repo, runId, report, ts) {
  // ts is passed in (integrate result.ts / round state.ts) — the Workflow runtime FORBIDS
  // new Date()/Date.now() (ShimDate throws to keep runs deterministic; a bare new Date() here
  // synchronously crashed the whole pool 2026-06-15). Never reintroduce a Date call in this file.
  const entry = {
    repo,
    runId,
    ts: ts || '',
    closed_ids: (report.verified_green || []).concat(report.reopened || []),
    gaming_flags: report.gaming_flags || [],
    reopened: report.reopened || [],
    verified_green: report.verified_green || [],
  }
  const json = JSON.stringify(entry)
  // The Workflow sandbox has NO Node APIs — process.env threw and crashed the pool 2026-06-15.
  // Keep the path as a literal ~ and let the AGENT (which runs shell) expand it. Never use
  // process.*/require()/fs in this file.
  const logPath = '~/.claude/logs/relay-gaming-flags.log'
  // Spawn a tiny agent (fire-and-forget, not awaited — log failure is non-fatal).
  agent(
    `Append the following JSON line to the gaming-flags log (create if absent, append only).
FIRST resolve the path with the shell (the JS cannot): log=$(python3 -c "import os;print(os.path.expanduser('${logPath}'))")
Then run: mkdir -p "$(dirname "$log")" && printf '%s\\n' '${json.replace(/'/g, "'\\''")}' >> "$log"
Confirm it succeeded.`,
    { label: `gaming-log:${repo}`, phase: 'Integrate', model: 'haiku' }
  ).catch(err => log(`relay-loop: gaming-flags log write failed (non-fatal): ${err}`))
}

// id:7570 — per-unit FINALLY lease release. The cross-session repo lease (id:ebfb) — and
// any exclusive resource lease (id:8d52) — were released ONLY inside the integrator agent
// (integrate() step 0). But a child that returns null / throws / hands back never reaches
// the integrator's release branch (integrate() early-returns on !report and !contract_met,
// and a thrown child never produces a report at all), so the lease LEAKED for the full
// 1800s TTL — needlessly blocking other sessions (observed live 2026-06-16, run -29307).
// This releases the repo lease (run-scoped → no-op if this run doesn't hold it, and
// idempotent vs. the integrator's later release of a merged unit) after the child SETTLES
// with ANY outcome. The Workflow sandbox has no shell/fs, so a tiny Haiku agent runs
// claim.sh release; failure is non-fatal (the TTL is the backstop, not the primary path).
// NEVER call it when this run is about to RE-CHAIN the same repo (a review→execute re-enqueue
// re-acquires the same lease re-entrantly): releasing in that window would open a steal gap
// for another run between this release and the re-chain's re-acquire — so the caller guards.
async function releaseLease(unit) {
  const resourceRelease = unit.intensive
    ? ` && ~/.claude/skills/relay/scripts/claim.sh release resource:${unit.intensive} --run ${state.runId}`
    : ''
  await agent(
    `Run exactly this command and report whether it exited 0 (the relay child for ${unit.repo} has settled; free its cross-session lease so other sessions aren't blocked for the TTL): ~/.claude/skills/relay/scripts/claim.sh release ${unit.repo} --run ${state.runId}${resourceRelease}
This is run-scoped (a no-op if this run no longer holds the claim) and idempotent. Report the exit code.`,
    { label: `release:${unit.repo}`, phase: 'Dispatch', model: 'haiku' }
  ).catch(err => log(`relay-loop: per-unit lease release failed for ${unit.repo} (non-fatal; TTL backstops): ${err}`))
}

async function runUnit(unit) {
  const tier = unit.verdict === 'execute' ? 'sonnet' : 'strong'
  // Injected units (id:baf1) skip the quota gate — an explicit user request runs even near
  // the cap. They were already consumed by `inject.sh take`, so deferring them would lose
  // the injection; honoring it is the whole point of "inject this next, highest priority".
  if (!unit.injected && !(await quotaGate(tier))) {
    state.queued.push({ repo: unit.repo, verdict: `${unit.verdict} (quota-deferred)` })
    return
  }
  unitsDispatched++
  totalDispatched++
  state.inFlight.push({ repo: unit.repo, mode: unit.verdict, agentId: `unit-${unitsDispatched}` })
  pushEvent('dispatch', { repo: unit.repo, mode: unit.verdict, tier, round })  // id:c8b6
  log(`relay-loop: dispatch ${unit.verdict} → ${unit.repo} (tier=${tier})`)
  // Tier dispatch (D4): review/handoff get the STRONG_TIER model. Execute agents are
  // pinned to Sonnet; STRONG_TIER applies no model override to them.
  const opts = { label: `${unit.verdict}:${unit.repo}`, phase: 'Dispatch', schema: REPORT_SCHEMA }
  if (unit.verdict === 'execute') opts.model = 'sonnet'
  else opts.model = STRONG_MODEL
  // API-error failsafe: agent() can throw or return null on a terminal API error after
  // the harness's own retries. Don't let that orphan a worktree with committed
  // checkpoints — catch it, and for a handoff attempt ONE auto-resume from the last
  // committed checkpoint. integrate() handles whatever report we end up with (a valid
  // resume report → merge; null/contract_met=false → recoverable handback with path).
  let report = null
  try {
    report = await agent(unitPrompt(unit), opts)
  } catch (e) {
    log(`relay-loop: ${unit.verdict} child for ${unit.repo} failed (${(e && e.message) || e}) — ${unit.verdict === 'handoff' ? 'attempting auto-resume' : 'will surface as handback'}`)
  }
  if (!report && unit.verdict === 'handoff') {
    log(`relay-loop: auto-resuming handoff ${unit.repo} from last checkpoint`)
    try {
      report = await agent(resumePrompt(unit), { ...opts, label: `resume:${unit.repo}` })
    } catch (e2) {
      log(`relay-loop: auto-resume of ${unit.repo} also failed (${(e2 && e2.message) || e2}) — handback`)
    }
  }
  state.inFlight = state.inFlight.filter(r => r.repo !== unit.repo)
  // Review→execute chaining (user directive 2026-06-13): when a REVIEW re-derives the
  // roadmap and open [ROUTINE] work remains, re-enqueue this repo as an execute unit in
  // the SAME pool rather than waiting for the next pool's discovery. The live lanes pull
  // it (the pushing lane itself re-checks `queue.length` after this returns, so it's
  // never lost even as the last unit). Only reviews chain — an execute never re-enqueues,
  // so there's no intra-pool ping-pong; the execute's own commits are reviewed next pool.
  // MAX_UNITS / quotaStopped still gate actual dispatch in the lane loop.
  let rechainedSameRepo = false
  if (unit.verdict === 'review' && report && report.contract_met &&
      (report.routine_open || 0) > 0 && !quotaStopped && !unit.rechained) {
    queue.push({
      repo: unit.repo, path: unit.path, verdict: 'execute',
      reason: `post-review re-enqueue: ${report.routine_open} open [ROUTINE] item(s)`,
      lastCkpt: unit.lastCkpt, income: unit.income, rechained: true,
    })
    rechainedSameRepo = true
    log(`relay-loop: review→execute re-enqueue ${unit.repo} (${report.routine_open} open [ROUTINE])`)
  }
  // id:7570 — per-unit FINALLY release: the child has settled (merged / handback / null /
  // error). Free the lease NOW so a leaked claim can't block other sessions until the TTL.
  // EXCEPTION: when this run just re-chained the SAME repo (review→execute above), keep the
  // lease — the re-chained execute will re-acquire it re-entrantly, and releasing in the gap
  // would let another run steal the repo. The integrator's step-0 release stays idempotent
  // for the merged case (run-scoped no-op once already released here).
  if (!rechainedSameRepo) await releaseLease(unit)
  // Integration debt is enqueued, not awaited here: the dispatch slot frees up
  // immediately while the serialized chain works through merges one at a time.
  debts.push(enqueueIntegration(unit.repo, () => integrate(unit, report)))
}

// id:6e9d — a freed lane pulls any pending injections mid-round (poll-once-on-drain) so an
// injected unit runs as soon as a slot frees with the queue empty, instead of idling until
// the round boundary. The Workflow script can't run shell, so a tiny agent runs `inject.sh
// take` (atomic/flock'd → each shard goes to exactly one lane). NO busy-spin: a lane only
// polls when it would otherwise EXIT (queue drained). Known residual: if ALL lanes are busy
// on long units the injection is caught at the imminent round boundary instead (see ROADMAP
// id:6e9d "Known residual"). A unit-shaped injected object so the normal dispatch path runs it.
async function takeInjections() {
  if (quotaStopped || roundCapHit || unitsDispatched >= MAX_UNITS) return []
  const res = await agent(
    `Run exactly this one command and nothing else: ~/.claude/skills/relay/scripts/inject.sh take
It atomically emits AND consumes pending user-injected relay units, one compact JSON per line:
{token, repo, verdict, item, prompt, requested_at}. For EACH emitted line, resolve the repo's
canonical path (default ~/src/<repo>, OR the "# path:" override in that repo's block in
~/.config/relay/relay.toml) and return one unit object with these exact fields:
{ injected:true, inject_token:<token>, verdict:(<verdict> or "execute"), repo:<repo>,
path:<resolved absolute path>, reason:"user-injected high-priority task (mid-round, id:6e9d)",
inject_item:(<item> or ""), inject_prompt:(<prompt> or ""), income:false, standin:false,
hasRoutine:false, openHard:false, strongRecheckPending:false, lastCkpt:"" }.
If inject.sh take emits NOTHING, return units:[]. Do not invent units; only echo what take emitted.`,
    { label: 'inject-take', phase: 'Dispatch', schema: INJECT_TAKE_SCHEMA, model: 'sonnet' }
  )
  return (res && Array.isArray(res.units)) ? res.units : []
}

await parallel(
  Array.from({ length: Math.min(POOL_WIDTH, queue.length) }, () => async () => {
    while (!quotaStopped && !roundCapHit) {
      if (unitsDispatched >= MAX_UNITS) {
        log(`relay-loop: MAX_UNITS per-round cap (${MAX_UNITS}) reached — draining this round`)
        roundCapHit = true
        break
      }
      if (budget.total && budget.remaining() < 50000) {
        log('relay-loop: token budget nearly exhausted — draining')
        quotaStopped = true
        break
      }
      if (!queue.length) {
        // queue drained — before idling this lane, pull any mid-round injections (id:6e9d).
        const injected = await takeInjections()
        if (injected.length) {
          queue.push(...injected)
          log(`relay-loop: mid-round inject pickup — ${injected.length} unit(s): ${injected.map(u => u.repo).join(', ')} (id:6e9d)`)
          continue
        }
        break  // nothing queued and no pending injection → this lane is done
      }
      const unit = queue.shift()
      state.queued = state.queued.filter(q => q.repo !== unit.repo)
      await runUnit(unit)
    }
  })
)

// Graceful drain (D5): the parallel() barrier above means all in-flight child agents
// have returned; now drain ALL integration debt before returning — an unmerged
// worktree is the worst thing to abandon.
await Promise.all(debts)
await Promise.all([...integrationChains.values()])

// ── [INTENSIVE] serial run-alone phase (id:8d52) ── the normal parallel wave + ALL its
// integration have fully drained above, so nothing else is in flight. Run intensive units
// one-at-a-time, draining each unit's integration before the next, so two heavy local-LLM
// loads never overlap (the OOM fix). Each child also holds an exclusive resource:<name>
// claim (acquired in unitPrompt) for cross-run exclusivity.
let intensiveRan = 0
for (const unit of intensiveUnits) {
  if (quotaStopped || roundCapHit) {
    state.queued.push({ repo: unit.repo, verdict: `intensive:${unit.intensive} (not run — quota/cap)` })
    continue
  }
  log(`relay-loop: [INTENSIVE] serial run-alone dispatch ${unit.repo} (resource=${unit.intensive})`)
  await runUnit(unit)
  await Promise.all(debts)
  await Promise.all([...integrationChains.values()])
  intensiveRan++
}

state.queued = state.queued.concat(queue.map(u => ({ repo: u.repo, verdict: `${u.verdict} (not dispatched)` })))
scheduleStatusWrite(state)
// id:2d20 — `produced` = checkpoints integrated THIS round (the only real progress signal).
// A round that dispatched units which ALL handed back produces 0 → the outer loop counts it dry.
const produced = state.completed.length - completedBefore
return { actionable: actionable.length + intensiveRan, produced }
}
// ── end runRound ──

// ── Outer self-feeding loop ──
// Repeat runRound (fresh discovery each round) until the quota cap stops the run, two
// consecutive rounds find no actionable work (backlog drained), or MAX_ROUNDS trips.
let dry = 0
while (!quotaStopped && round < MAX_ROUNDS) {
  round++
  const r = await runRound()
  if (r.failed) {
    if (round === 1) {
      await statusTail  // id:cb50 — flush any queued status write before the early return
      return { error: 'discovery failed', runId: state.runId, statusPath: RELAY_STATUS_PATH, completed: state.completed, handbacks: [], queuedRemaining: state.queued, quotaStopped, stopReason }
    }
    log('relay-loop: discovery failed mid-run — stopping after completed rounds')
    break
  }
  // id:2d20 — a round is "dry" when it integrated NO checkpoint (produced === 0), not merely
  // when it dispatched nothing. An all-handback round (only gated/too-large HARD units, which
  // correctly refuse to half-do the work) makes no progress, so it counts toward drain — the
  // loop stops after 2 such rounds instead of re-dispatching the same un-doable items every
  // round to the MAX_ROUNDS seatbelt.
  if ((r.produced || 0) === 0) {
    dry++
    const why = r.actionable === 0 ? 'no actionable units' : `${r.actionable} dispatched but 0 integrated (all handed back)`
    log(`relay-loop: round ${round} — no progress: ${why} (dry ${dry}/2)`)
    if (dry >= 2) { log('relay-loop: backlog drained (2 consecutive no-progress rounds) — done'); break }
  } else {
    dry = 0
  }
}

await statusTail  // id:cb50 — flush the queued (off-critical-path) RELAY_STATUS writes so the final state is durable before the run returns
const handbacks = state.blocked.filter(b => b.worktreePath && b.worktreePath !== '-')
log(`relay-loop: done — ${round} round(s), ${state.completed.length} integrated, ${handbacks.length} HANDBACKs, quotaStopped=${quotaStopped}`)

return {
  runId: state.runId,
  statusPath: RELAY_STATUS_PATH,
  completed: state.completed,
  handbacks,
  queuedRemaining: state.queued,
  quotaStopped,
  stopReason,  // id:8c35 — category: null | "quota-stale-cache" | "quota-exhausted:<bucket>" | "budget" | "drained" | "max-rounds"
  rounds: round,
}
