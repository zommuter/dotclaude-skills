export const meta = {
  name: 'relay-loop',
  description: 'Priority-mixed 5-wide autonomous relay pool — serialized integrator, quota-guarded, STRONG_TIER-aware',
  // id:7c10 — finer-grained progress buckets so the /workflows pane's per-phase counts are
  // meaningful. The two former floods are split out (discover-shards → Classify; the
  // write-relay-status snapshot writer → Status) and the Support/Integrate catch-alls are
  // broken into single-purpose buckets (Quota / Leases / Logging). Purely a DISPLAY grouping —
  // zero behavioural change (the id:7d1e precedent).
  phases: [
    { title: 'Discover', detail: 'once-only prelude: runId · inject-take · claim-peek · sigs · stop-sentinel' },
    { title: 'Classify', detail: 'parallel discover-shard classifiers (one per repo chunk)' },
    { title: 'Execute', detail: '[ROUTINE] executor units (Sonnet)' },
    { title: 'Review', detail: 'audit unaudited commits + re-derive roadmap (apex)' },
    { title: 'Hard', detail: '[HARD] (formerly [HARD — pool]) apex execution of one bounded item' },
    { title: 'Handoff', detail: 'docs → roadmap → red tests → BDD handoff (apex)' },
    { title: 'Integrate', detail: 'serialized merge → ckpt-tag → push per completed unit' },
    { title: 'Status', detail: 'off-critical-path RELAY_STATUS.md snapshot writes' },
    { title: 'Logging', detail: 'gaming-flag log · handback-followup routing' },
    { title: 'Quota', detail: 'per-tier quota gate checks' },
    { title: 'Leases', detail: 'per-unit cross-session lease release' },
    { title: 'Support', detail: 'injection take · run-heartbeat · auto-reconcile-on-restart' },
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

// id:854c — shared emitter for the three JS-side dispatch backstops (id:000d/9973/ad74).
// Each backstop previously only log()d its fire to sandbox stdout, leaving b50e's
// GO-criterion (a) — evidence of how often they actually fire — unmeasured. Reuses the
// existing durable pushEvent sink (pendingEvents -> snapshotState -> relay-events.jsonl);
// no new file write, no fs/net/shell, no process.env/Date.now().
function emitBackstopFire(backstopId, repo, verdict) {
  pushEvent('backstop', { backstop: backstopId, repo, verdict })
}

// [INTENSIVE] gate (id:8d52; semantics revised id:052c): resource-heavy units (local-LLM
// benchmarks, big index rebuilds — the OOM risk that killed 6 sessions) are NEVER auto-dispatched
// by default. ONLY --intensive (synonym: --allow-intensive) opts in; then they run SERIALLY-ALONE
// after the normal parallel wave, holding an exclusive resource claim (resource:<name>).
// --afk ("I'm away, do something useful") NO LONGER implies intensive (id:052c) — auto-running
// OOM-risky work *because* the user stepped away is backwards; --afk stays SAFE / non-intensive.
// Conversely --intensive IMPLIES --afk (a front-door concern: it is inherently an away-run). So
// the in-loop gate is args.allowIntensive ALONE — the front door sets it ONLY for --intensive /
// --allow-intensive, never for a bare --afk.
const ALLOW_INTENSIVE = !!A.allowIntensive

// TODO (id:e407 follow-up, NOT required for that item's green): supersede this binary
// gate with the graded permitted-intensity window (relay/scripts/relay-intensity.sh
// `permits <est_wall> <resource>`). Deferred here deliberately — the meeting note flags
// this specific engine edit as RISKY/crash-prone (the a0b6 template-literal-lint hazard
// class); it needs its own `node --check` + `lint-workflow-templates.mjs` + structure-test
// pass, not a same-session drive-by. See docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md decision 4.

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

// id:c012 — graceful (patient) operator stop. THREE entry points, all converging on
// stopReason="user-stop" + a clean drain (the prior round's wave + integration debt are
// already drained by runRound before the next round's discovery runs, so a stop between
// rounds abandons nothing — it just declines to re-discover/dispatch a new wave):
//   • STOP sentinel (live pool): a file at STOP_PATH the discover-prelude checks each round
//     (the Workflow script has NO filesystem access — only agents run shell, so the prelude
//     owns the read/decrement/consume and returns `stopRequested`). Sentinel CONTENT = integer
//     "rounds remaining before stop" (empty / non-numeric / <=0 ⇒ stop at the NEXT round
//     boundary). `/relay stop` writes an empty file (stop now); `/relay stop --after N` writes
//     N (drain N more rounds, then stop). The prelude decrements N→N-1 each round and consumes
//     (rm) the sentinel when it fires, so a stale sentinel can never wedge the next pool.
//   • --once (launch flag): dispatch exactly ONE round, then stop. Pure JS round cap.
//   • --after N (launch flag): dispatch N rounds, then stop. Pure JS round cap (--once = N:1).
// Distinct from quota-stop (involuntary) — this is the voluntary, operator-initiated wind-down.
const STOP_PATH = A.STOP_PATH || '~/.config/relay/STOP'
// Launch-time round cap (0 = off). --once is sugar for --after 1. The outer loop breaks with
// stopReason="user-stop" once `round` reaches this cap.
const STOP_AFTER_ROUNDS = A.once ? 1 : (Number.isInteger(A.stopAfter) && A.stopAfter > 0 ? A.stopAfter : 0)

// id:d530 — first-class per-RUN --priority / --exclude pool args (no relay.toml write; the
// registry stays untouched). The front door maps the natural-language forms the user types
// ("priority on X", "exclude Y") onto args.priorityRepos / args.excludeRepos. Both arrive as
// a string ("a,b") or an array; normalize to a clean array of repo names (fail-safe: empty
// arg ⇒ no change = today's behaviour).
//   • EXCLUDE: those repos are DROPPED from the own-repo list BEFORE sharding (no shard sees
//     them, no unit is emitted), each added to the skipped rollup as "excluded for this run
//     (--exclude)". An exclude name that is not a confirmed own repo is a LOUD reject (surfaced).
//   • PRIORITY: a per-run ORDERING bump ONLY (priorityRank in the unit sort comparators) — it
//     reorders a repo's NATURALLY-DISCOVERED unit, never creates/injects one, so it can never
//     double-dispatch the way inject.sh-as-priority did (the id:d530 finding). Above income,
//     below injected-precedence + the D3 verdict-class order — NEVER a verdict override.
// These helpers are byte-identical to relay/scripts/pool-args.mjs (the unit-tested pure copy;
// the Workflow sandbox cannot import it). A structural test pins the wiring — keep them in sync.
function normalizeRepoArg(val) {
  if (!val) return []
  const parts = Array.isArray(val) ? val : String(val).split(/[\s,]+/)
  return parts.map(s => String(s).trim()).filter(Boolean)
}
const EXCLUDE_REPOS = normalizeRepoArg(A.excludeRepos)
const PRIORITY_REPOS = normalizeRepoArg(A.priorityRepos)
function priorityRank(unit, prioritySet) {
  return (prioritySet && prioritySet.has(unit.repo)) ? 0 : 1
}

// id:7633 — first-class SINGLE-REPO scope. `/relay <repo>` / `/relay .` / `--only <repo>` map (at
// the front door; `.` resolved to the cwd repo's basename there) onto A.onlyRepo. When set, ONLY
// that repo enters the discover fan-out (the own-repo universe enumeration + 40× classification is
// bypassed — the same per-repo path, discover-repo.sh, is REUSED for the one repo, never forked).
// The repo resolves against the canonical own-repo list (relay.toml, honoring `# path:`); an
// unconfirmed name is a LOUD reject, not a `~/src` guess. FAIL-SAFE: empty ⇒ today's whole-fleet
// behaviour. Byte-identical to pool-args.mjs::resolveScopeRepo (the unit-tested pure copy — the
// Workflow sandbox cannot import; a structural test pins the two in sync).
const ONLY_REPO = A.onlyRepo ? String(A.onlyRepo).trim() : ''
function resolveScopeRepo(onlyRepo, ownRepos) {
  const name = onlyRepo ? String(onlyRepo).trim() : ''
  if (!name) return { scoped: null, surfaced: null }
  const match = (ownRepos || []).find(r => r.repo === name)
  if (match) return { scoped: match, surfaced: null }
  return {
    scoped: null,
    surfaced: { repo: name, reason: `--only: '${name}' is not a confirmed own repo in relay.toml — refusing to guess a path (id:7633; canonical own set only, never a ~/src glob)` },
  }
}

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
// human (id:5eb3): surface-only verdict (promote==0 ∧ surface>0), rank 5 — never dispatched
// as an executor child (mechanical filing only).
// mechanical (id:7616): MECHANICAL-only backlog (open [MECHANICAL] items, nothing higher),
// rank 6 — POOL-INERT. A host daemon dispatches this (A3, gated), NEVER the LLM pool. Present
// in the schema enum + here for a valid round-trip and to SURFACE it (RELAY_STATUS Queued),
// but — exactly like `human` — it is ABSENT from PHASE_BY_VERDICT and never spawns a child.
const PRIORITY = { execute: 0, review: 1, hard: 2, handoff: 3, human: 5, mechanical: 6 }

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
//     completed: [{repo, mode, ckptTag, pushStatus, workedIds}],  // workedIds id:de69
//     queued:    [{repo, verdict}],
//     blocked:   [{repo, reason, worktreePath}],
//     quota:     [{bucket, pctRemaining, resetTime}],
//     reviewMe:  [{repo, count, path}],
//     stopReason: string|null }  // id:8c35 — category of the stop (quota-cache-unreadable, quota-extrapolated-stop, quota-exhausted:<bucket>, etc.)
// id:8c35 — build the stop-reason line for RELAY_STATUS (called with the module-level
// stopReason at status-write time, so writeRelayStatus must pass it in via state).
function buildStopReasonLine(sr) {
  if (!sr) return '_(none — run still active or drained cleanly)_'
  // id:c012 — operator-initiated graceful stop (STOP sentinel or --once/--after cap).
  if (sr === 'user-stop') return '**user-stop** — operator graceful stop (STOP sentinel or --once/--after); in-flight wave + integration debt were drained, no new wave dispatched'
  return `**${sr}**`
}

function buildRelayStatus(state) {
  const header = `# RELAY_STATUS — last updated ${state.ts}  run: ${state.runId}`

  const inFlight = state.inFlight && state.inFlight.length
    ? state.inFlight.map(r => `- ${r.repo}  mode=${r.mode}  agent=${r.agentId}`).join('\n')
    : '_(none)_'

  const completed = state.completed && state.completed.length
    ? state.completed.map(r => `- ${r.repo}  mode=${r.mode}  ckpt=${r.ckptTag}  push=${r.pushStatus}${(r.workedIds && r.workedIds.length) ? `  ids=${r.workedIds.join(',')}` : ''}`).join('\n')  // ids id:de69
    : '_(none)_'

  const queued = state.queued && state.queued.length
    ? state.queued.map(r => `- ${r.repo}  verdict=${r.verdict}`).join('\n')
    : '_(none)_'

  // id:1735 — "Blocked" now shows BOTH this round's surfaced/suppressed repos AND every
  // still-outstanding real handback (the persistent accumulator) — previously the reassignment
  // bug meant a handback from an earlier round silently vanished from this section too.
  const blockedRows = [...(state.surfaced || []), ...(state.handbacks || [])]
  const blocked = blockedRows.length
    ? blockedRows.map(r => `- ${r.repo}  reason=${r.reason}  worktree=${r.worktreePath}`).join('\n')
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

  // id:1432 — LOUD repeat-handback ALERTs: any repo+verdict that handed back >=2× this run.
  // A repeating handback is a bug signal (a false/stale verdict looping, or an un-doable item
  // the classifier keeps re-picking) — surface it so it is investigated, never silently looped.
  const alerts = state.handbackAlertsList && state.handbackAlertsList.length
    ? state.handbackAlertsList.map(a => `- ⚠️ ${a.repo}  verdict=${a.verdict}  handbacks=${a.count}  last="${a.lastReason}"`).join('\n')
    : '_(none)_'

  // id:c8b6 — Run progress: at-a-glance counters so the snapshot conveys momentum, not just
  // the current frame. round/totalDispatched are run-totals; the rest are live tallies.
  const progress = [
    `- round=${state.round || 0}`,
    `- dispatched=${state.totalDispatched || 0} (total work units this run)`,
    `- in-flight=${(state.inFlight || []).length}`,
    `- completed=${(state.completed || []).length}`,
    `- blocked=${((state.surfaced || []).length + (state.handbacks || []).length)}`,
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
    '## Repeat-handback ALERTs (id:1432 — >=2× this run, a bug signal)',
    alerts,
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
  const blockedCount = (state.surfaced || []).length + (state.handbacks || []).length
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
    { label: 'write-relay-status', phase: 'Status', model: 'haiku' }
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
    handbackAlertsList: handbackAlerts(handbackTracker, 2),  // id:1432 — >=2× handback ALERTs
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
          // 'mechanical' (id:7616) is a VALID verdict classify-verdict.sh emits (priority_rank 6)
          // for a MECHANICAL-only backlog — it MUST be in the enum so the first such repo's shard
          // output validates. It is POOL-INERT (pulled out before dispatch, surfaced not run).
          verdict: { enum: ['execute', 'review', 'hard', 'handoff', 'human', 'mechanical', 'idle'] },
          reason: { type: 'string' },
          lastCkpt: { type: 'string' },
          income: { type: 'boolean' },
          // hasRoutine: ROADMAP.md has >=1 unticked [ROUTINE] item, reported
          // INDEPENDENT of verdict — lets --fable-down demote a review repo that
          // also has open executor work instead of deferring it wholesale.
          hasRoutine: { type: 'boolean' },
          // openHard: count of unticked "- [ ]" items tagged "[HARD" — matches both the
          // legacy "[HARD — pool]" spelling and the new bare "[HARD]" capability tag
          // (id:4f02/id:8111 dual-vocab migration window; relay/references/hard-lanes.md).
          // Drives the "hard" verdict (id:da26): a repo with no unaudited
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
          // is_finished (id:000d): the DETERMINISTIC finished-repo flag computed by
          // gather-repo-state.sh (roadmap present/non-empty + 0 open "- [ ]" items +
          // commits_since_ckpt empty + clean/lock-only-dirty tree). The shard MUST copy it
          // verbatim from the gather JSON onto the unit — the JS-side demote guard below
          // reads u.is_finished to correct a shard that mis-classifies a finished repo as
          // execute/hard/handoff (id:401c Run 45 fix: the guard was dead because the value
          // never reached the unit object). false when no roadmap.
          is_finished: { type: 'boolean' },
          // top_intensive (id:ad74): the resource name of the top open "- [ ]" item
          // carrying an "[INTENSIVE — <resource>]" modifier, "" when none. Computed
          // deterministically by gather-repo-state.sh. The JS-side INTENSIVE promote
          // backstop reads this field to self-correct a shard that classified a repo
          // idle/skipped despite having open [INTENSIVE] work. MUST be "" (not absent)
          // when no open [INTENSIVE] item exists.
          top_intensive: { type: 'string' },
          // substantive_unaudited (id:365b): the DETERMINISTIC anti-spin flag computed by
          // gather-repo-state.sh — false iff there is NOTHING NEW for a recurring strong-model
          // audit (id:401c) to review since the audit ref (only `relay:/fable: checkpoint` /
          // uv.lock-only commits). The shard's recurring-audit gate (mechanism 1) reads it to
          // demote a `relay:recurring-audit`-marked HARD item with nothing to audit. FAIL-OPEN
          // true when uncomputable. Copy verbatim from the gather JSON onto every unit.
          substantive_unaudited: { type: 'boolean' },
          // work_sig (id:365b): a signature STABLE across the pool's own `relay: checkpoint`
          // churn but changing when an item closes or a substantive commit lands. The JS-side
          // re-dispatch circuit breaker (mechanism 2) keys on it. Copy verbatim from the gather
          // JSON onto every unit; "" when uncomputable (the breaker treats "" as fail-open).
          work_sig: { type: 'string' },
          // open_hard_pool (id:9973): the DETERMINISTIC count of open "- [ ]" ROADMAP items
          // tagged EXACTLY "[HARD — pool]" OR (id:4f02/id:8111 dual-vocab window) the new bare
          // "[HARD]" capability tag — the only pool-dispatchable HARD lane per
          // relay/references/hard-lanes.md — [HARD — meeting]/[HARD — decision gate]/[HARD —
          // hands] (nor their new-vocab equivalents [INPUT — meeting]/[INPUT — decision]/
          // [INPUT — access]) are NOT. Recurring-audit-marked items with nothing new to audit are
          // excluded (reuses substantive_unaudited, id:365b). Computed by gather-repo-state.sh
          // (B2a; this field is tag-agnostic here — a numeric count, no regex change needed in
          // this file); copy verbatim from the gather JSON onto every unit. The JS-side
          // demote-guard below reads u.open_hard_pool to demote a \`hard\` verdict on a repo with
          // NO open pool-lane HARD item (the shard's `hard` judgment is non-deterministic —
          // observed 2026-06-24 dispatching repos whose only open HARD item was
          // [HARD — decision gate]). 0 when none.
          open_hard_pool: { type: 'number' },
          // queue_sig (id:4860): the discover-sig.sh SUPERSET signature the MECHANICAL
          // discovery producer (discover-repos-mechanical.sh, id:9d97) stamped onto this
          // entry in the discovery queue, present ONLY on units the runner copied from the
          // queue (CASE A). The runner is instructed to copy a queue verdict ONLY when this
          // queue_sig equals the repo's LIVE sig (from the prelude); the JS-side canary below
          // re-asserts u.queue_sig === sigByRepo[u.repo] and DROPS+surfaces any mismatch
          // (stale snapshot / went-dirty-after-snapshot / mangled bridge-copy). ABSENT on
          // CASE B live units (computed live, exempt from the assert). "" = fail-open sentinel.
          queue_sig: { type: 'string' },
        },
      },
    },
    surfaced: {
      type: 'array',
      items: {
        type: 'object',
        required: ['repo', 'reason'],
        // queue_sig (id:4860): the producer stamps it on surfaced entries too; harmless
        // pass-through here (a surfaced repo is never dispatched, so it needs no canary).
        properties: { repo: { type: 'string' }, reason: { type: 'string' }, queue_sig: { type: 'string' } },
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
        // queue_sig (id:4860): producer-stamped on skipped entries too; harmless pass-through.
        properties: { repo: { type: 'string' }, reason: { type: 'string' }, queue_sig: { type: 'string' } },
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
    // id:c012 — true when the operator STOP sentinel fired this round (drain + stop, no new wave).
    stopRequested: { type: 'boolean' },
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
    // id:2425 — crossed bucket: on exit 1 (real exhaustion) the agent reports which bucket
    // crossed its (possibly decayed/overridden) threshold, so relay-loop can name the culprit
    // without falling back to the stale <=10% heuristic. Empty/absent means no agent-side info.
    crossedBucket: { type: 'string' },
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
    // worked_ids (id:de69): the ROADMAP/TODO 4-hex id(s) this unit actually worked — closed,
    // created, or promoted (review: the ids verified-green or reopened). The supervisor
    // propagates these into RELAY_STATUS "Completed this run", the integrate event, and the
    // checkpoint message, so a finished unit is traceable to its item even though plain
    // execute/review pick the item INSIDE the child (the id isn't known at dispatch). [] if none.
    worked_ids: { type: 'array', items: { type: 'string' } },
    // --- durable handback follow-up (id:3801) -------------------------------------
    // On a handback (contract_met=false), the child classifies WHY so the integrator
    // can durably record it in ROADMAP.md (handback-followup.py) instead of letting the
    // judgment evaporate into RELAY_STATUS and re-dispatching the same un-doable item.
    handback_item: { type: 'string' },  // the 4-hex id the handback concerns
    route: { type: 'string' },          // decision-gate | hard-split | human | none
    gate_reason: { type: 'string' },    // ONE short line for the inline ROADMAP gate note
    proposed_split: {                   // hard-split only: seams to mint as pickable units
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' }, id: { type: 'string' },
          tier: { type: 'string' }, dep: { type: 'string' },
        },
      },
    },
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
// runId is seeded from the front-door-minted args.RUN_ID (relay-$(date)-$RANDOM) so a valid
// RELAY_RUN_ID exists at the PRE-DISCOVERY round-1 quota gate (line ~771) — the discovery
// prelude that used to mint it runs AFTER that gate, so without this seed state.runId was ''
// at the first quota check, disabling the extrapolation fallback + burn-sampler (both gated on
// RELAY_RUN_ID) and blind-stopping any background run the moment its /tmp cache went stale.
// The prelude's `state.runId || prelude.runId` keeps this seeded value; absent an args.RUN_ID
// (older front door) it falls back to the prelude-minted one as before.
// id:1735 — `blocked` used to be ONE array doing two incompatible jobs: reassigned wholesale
// every round from discovery.surfaced (a per-round VIEW) while five handback sites pushed into
// it as if it accumulated (a persistent LOG). A handback from round N was destroyed by round
// N+1's reassignment, so the run's returned summary silently lost it. Split into two fields with
// two different lifetimes: `surfaced` (per-round view, REASSIGNED every round — see ~line 1491,
// that reassignment is correct and intentional) and `handbacks` (persistent accumulator, only
// ever pushed to — see handback-summary.mjs for the pure logic + rationale).
const state = { runId: (A.RUN_ID ? String(A.RUN_ID) : ''), ts: '', inFlight: [], completed: [], queued: [], surfaced: [], handbacks: [], skipped: [], quota: [], reviewMe: [] }
let quotaStopped = false
// Run-progress accumulators (id:c8b6), declared here (not at the bottom loop) so snapshotState
// can read them with no temporal-dead-zone risk. round = re-discover→dispatch→drain iterations;
// totalDispatched = work units dispatched across ALL rounds (unitsDispatched resets per round).
let round = 0
let totalDispatched = 0
// id:365b — re-dispatch circuit breaker state. PERSISTS across rounds within this single
// pool invocation (a module-level object, like the discoverCache). Keyed `${repo}:${verdict}`
// → {sig, count}: how many times that (repo,verdict) has been dispatched this run with the
// SAME work_sig (a sig stable across the pool's own `relay: checkpoint` churn). A DETERMINISTIC
// backstop catching ANY spin even if the discover-shard's principled recurring-audit gate
// (mechanism 1) slips — see the inline breaker in the discovery guards block.
const redispatchGuard = {}
// id:1432 — WHOLE-DISPATCH handback defense-in-depth (see handback-guard.mjs for the full
// rationale + the unit-tested pure helpers; these inline copies MUST stay byte-equivalent —
// the Workflow sandbox cannot import). Both objects PERSIST across rounds within this one pool
// invocation, like redispatchGuard.
//   noWorkNegCache: `${repo}:${verdict}` → {sig} — a route=none "no executor-actionable work"
//     handback stamps the unit's work_sig; the same verdict is NOT re-dispatched until the
//     work_sig genuinely changes (work_sig is stable across the pool's own checkpoint churn, so
//     the empty-integrate checkpoint can't trivially clear it — the id:2ab2 loop the observed
//     it-infra false-execute took).
//   handbackTracker: `${repo}:${verdict}` → {repo, verdict, count, lastReason} — per-run handback
//     counter; a repo+verdict at >=2 surfaces as a LOUD ALERT (a repeating handback is a bug signal).
const noWorkNegCache = {}
const handbackTracker = {}
// id:1432 — inline copies of handback-guard.mjs (keep byte-equivalent; structural test pins it).
function recordNoWorkHandback(negCache, repo, verdict, sig) {
  negCache[`${repo}:${verdict}`] = { sig: sig || '' }
}
function applyNoWorkSuppression(units, negCache, runId) {
  const kept = [], suppressed = []
  for (const u of units) {
    if (u.injected) { kept.push(u); continue }
    const key = `${u.repo}:${u.verdict}`
    const prev = negCache[key]
    const sig = u.work_sig || ''
    if (prev && prev.sig === sig) {
      suppressed.push({
        unit: u,
        reason: `no-work handback suppression (id:1432): ${u.repo} ${u.verdict} handed back "no executor-actionable work" with work_sig unchanged — not re-dispatching this verdict until the repo's work_sig genuinely changes; cost hint: relay-burn.sh --run ${runId}`,
      })
    } else {
      if (prev) delete negCache[key]
      kept.push(u)
    }
  }
  return { kept, suppressed }
}
function trackHandback(tracker, repo, verdict, reason) {
  const key = `${repo}:${verdict}`
  const e = tracker[key] || (tracker[key] = { repo, verdict, count: 0, lastReason: '' })
  e.count++
  e.lastReason = String(reason == null ? '' : reason).replace(/\s+/g, ' ').trim().slice(0, 200)
  return e
}
function handbackAlerts(tracker, threshold = 2) {
  return Object.values(tracker)
    .filter(e => e.count >= threshold)
    .sort((a, b) => b.count - a.count || a.repo.localeCompare(b.repo) || a.verdict.localeCompare(b.verdict))
    .map(e => ({ repo: e.repo, verdict: e.verdict, count: e.count, lastReason: e.lastReason }))
}
// id:1735 — persistent record of every `pushEvent('handback', …)` emitted this run (repo +
// reason only — pendingEvents itself gets drained/flushed by snapshotState, so it cannot be
// read back at end-of-run; this is a separate, NEVER-drained accumulator kept purely for the
// invariant check below). Populated at the same call sites that call pushEvent('handback', …).
const emittedHandbackEvents = []
// id:1735 — inline copies of handback-summary.mjs (keep byte-equivalent; structural test pins
// the wiring). See that file for full rationale.
function buildSurfacedView(surfaced) {
  return (surfaced || []).map(s => ({ repo: s.repo, reason: s.reason, worktreePath: '-' }))
}
function reconcileHandbacks(accumulator) {
  return (accumulator || []).filter(b => b && b.worktreePath && b.worktreePath !== '-')
}
function assertHandbackInvariant(emittedEvents, accumulator) {
  const acc = accumulator || []
  const violations = []
  for (const ev of (emittedEvents || [])) {
    const found = acc.some(h => h && h.repo === ev.repo && h.reason === ev.reason)
    if (!found) violations.push(ev)
  }
  return { ok: violations.length === 0, violations }
}
// id:8c35 — machine-readable stop reason: null | "quota-cache-unreadable" |
// "quota-extrapolated-stop[:<bucket>]" (id:0175/82e3) | "quota-exhausted:<bucket>" |
// "budget" | "drained" | "max-rounds" | "user-stop" (id:c012)
// Populated by quotaGate on any stop (and by the id:c012 graceful-stop paths) so operators
// (and RELAY_STATUS) see WHY, not just "quotaStopped=true".
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

// id:7402 (D3) — the mechanical discovery-queue drop-dir the id:9d97 `.timer` producer writes
// (relay/references/discovery-queue-manifest.md). FRESH_SECS = the producer's 15min cadence
// (tools/discover-repos-mechanical.timer) + a 5min buffer, so one missed/slow tick is still
// tolerated before falling back. The queue is ABSENT by default — the timer ships installed
// but NOT auto-enabled (`make install-discovery-timer` is a deliberate manual step) — so out of
// the box this is always a no-op and the runner takes the live discover-repo.sh exec path
// unchanged (non-breaking by construction).
const DISCOVERY_QUEUE_LATEST = A.discoveryQueueLatest || '~/.config/relay/discovery-queue/latest.json'
const DISCOVERY_QUEUE_FRESH_SECS = A.discoveryQueueFreshSecs || 1200

// id:d58f — fleet-quiescence drain. BYTE-IDENTICAL inline copies of relay/scripts/drain.mjs
// (the Workflow sandbox cannot `import`; the .mjs is the canonical, unit-tested source — keep
// in sync). See drain.mjs for the full rationale: a CONFIRMING-only review (verified-green,
// reopened/added nothing) must NOT count as progress, else the loop spins on an already-drained
// fleet re-reviewing a concurrently-churning repo instead of winding down.
function unitIsSubstantive(verdict, report) {
  if (verdict === 'execute' || verdict === 'hard' || verdict === 'handoff') return true
  if (verdict === 'review') {
    if (!report) return false
    const reopened = Array.isArray(report.reopened) ? report.reopened.length : 0
    const gaming = Array.isArray(report.gaming_flags) ? report.gaming_flags.length : 0
    const routineOpen = Number(report.routine_open) || 0
    return reopened > 0 || gaming > 0 || routineOpen > 0
  }
  return true
}
function classifyDrainBacklog(blocked) {
  const buckets = { finished: [], gated: [], suppressed: [], circuitBroken: [], dirty: [], other: [] }
  for (const b of (blocked || [])) {
    const repo = b && b.repo ? b.repo : '?'
    const reason = (b && b.reason) ? String(b.reason) : ''
    if (/finished repo|anti-false-handoff|0 open items/i.test(reason)) buckets.finished.push(repo)
    else if (/suppressed re-dispatch/i.test(reason)) buckets.suppressed.push(repo)
    else if (/HARD backlog|\[HARD —|\[HARD\]|\[INPUT —|no open \[HARD — pool\]|no open \[HARD\]|demote-guard|needs a \/meeting|@manual|human-only|requires human/i.test(reason)) buckets.gated.push(repo)
    else if (/circuit breaker/i.test(reason)) buckets.circuitBroken.push(repo)
    else if (/dirty main tree|dirty/i.test(reason)) buckets.dirty.push(repo)
    else buckets.other.push(repo)
  }
  const parts = []
  if (buckets.finished.length)     parts.push(`${buckets.finished.length} finished`)
  if (buckets.suppressed.length)   parts.push(`${buckets.suppressed.length} suppressed (→ /relay reconcile: ${buckets.suppressed.join(', ')})`)
  if (buckets.gated.length)        parts.push(`${buckets.gated.length} gated (→ /relay human or /meeting: ${buckets.gated.join(', ')})`)
  if (buckets.circuitBroken.length) parts.push(`${buckets.circuitBroken.length} circuit-broken`)
  if (buckets.dirty.length)        parts.push(`${buckets.dirty.length} dirty`)
  if (buckets.other.length)        parts.push(`${buckets.other.length} other`)
  const summary = parts.length ? parts.join(' · ') : 'no blocked repos'
  return { ...buckets, summary }
}
// id:4ca8 — inline copies of drain.mjs's isBlockedRound/isDryRound (keep byte-equivalent).
function isBlockedRound(r) {
  return !!(r && (r.substantive || 0) === 0 && (r.surfaced || 0) > 0)
}
function isDryRound(r) {
  return !!(r && (r.substantive || 0) === 0 && (r.surfaced || 0) === 0)
}

async function runRound() {
// id:2d20 — productivity baseline: completions integrated BEFORE this round. The outer loop's
// drain detector keys on `produced` (completions THIS round), not units dispatched — a round
// that only hands back gated/too-large HARD units produces 0 and counts as dry, so the loop
// drains instead of re-dispatching the same un-doable items for MAX_ROUNDS.
const completedBefore = state.completed.length
// id:5c00 — quota PRE-GATE: check quota BEFORE the discover-prelude + DISCOVER_SHARDS fan-out.
// A round that immediately quota-stops wastes N shard agents if the gate fires post-sharding.
// (Incident 2026-06-25, run relay-20260625-225111: 5 shards ~94k tokens spent before stop.)
// Uses the existing quotaGate() / last-known cache (no extra API refresh before round 1 shards).
if (!await quotaGate('sonnet')) {
  // quotaStopped was set to true by quotaGate; outer loop exits after this round.
  log('relay-loop: id:5c00 quota PRE-GATE fired — skipping discovery fan-out (quota at threshold before round start)')
  return { actionable: 0, produced: 0 }
}
// ── Phase 1: Discover ──

phase('Discover')

// id:9ed4 — PRELUDE: once-only global work (runId, the CONSUMING inject.sh take, claim.sh
// peek, the own-repo list + non-own skipped rollup). Then fan out parallel SHARD classifiers.
const prelude = await agent(
  `You are the PRELUDE of the relay discovery step. Do ONLY the once-only global work; do NOT classify repos.
1. runId: generate ONCE via the shell: relay-$(date +%Y%m%d-%H%M%S)-$RANDOM (seconds + random suffix; MUST be unique per pool run — two concurrent pools must never share one because the cross-session lease and the worktree guard both key on it, id:0902).
2. ts: current ISO 8601 timestamp.
3. repos: read ~/.config/relay/relay.toml; for EVERY block with classification = "own" emit {repo, path (ABSOLUTE — expand a leading ~ to $HOME; default $HOME/src/<name>, or the "# path:" comment override with any leading ~ likewise expanded — NEVER emit a literal ~), income (true iff income = true)}.
4. skippedConfig (id:be62): for every block whose classification is NOT "own" emit {repo, reason: "excluded-by-config (<classification>)"}. The shards never see non-own repos.
5. liveClaimRepos: run ~/.claude/skills/relay/scripts/claim.sh peek once — it prints every LIVE cross-session claim as one JSON per line ({key,repo,runId,...}); return the SET of distinct "repo" values. [] if none.
6. injectedUnits (id:baf1): run ~/.claude/skills/relay/scripts/inject.sh take EXACTLY ONCE — it atomically emits AND CONSUMES pending user-injected units, one JSON per line {token, repo, verdict, item, prompt, requested_at}. For EACH, emit one unit: {injected:true, inject_token:<token>, verdict:(<verdict> or "execute"), repo:<repo>, path:(resolve ~/src/<repo> or the "# path:" override), reason:"user-injected high-priority task", inject_item:(<item> or ""), inject_prompt:(<prompt> or ""), income:false, standin:false, hasRoutine:false, openHard:false, strongRecheckPending:false, lastCkpt:"", intensive:""}. [] if take emits nothing. NEVER run take more than once (it consumes).
7. signatures (id:c3a6 — discovery cache): compute a per-repo SUPERSET signature so the supervisor can skip re-classifying (an LLM shard) a repo whose observable state is unchanged since last round. Build ONE JSON object {"repos":[{"repo":<repo>,"path":<path>} for EVERY own repo from step 3 — the ABSOLUTE paths, NOT a literal ~; discover-sig.sh stats each path and a literal ~ yields an empty fail-open sig that silently disables the cache],"liveClaims":<the liveClaimRepos array from step 5>} and pipe it on stdin to ~/.claude/skills/relay/scripts/discover-sig.sh. The script emits one JSON line per repo {"repo":<repo>,"sig":<sha256-hex or "">} — return them verbatim as "signatures". An EMPTY sig is a fail-open sentinel (the script could not read the repo): pass it through unchanged, do NOT invent a hash. Do this ONCE for all own repos; do NOT classify here. ([] only if there are zero own repos.)
8. stopRequested (id:c012/id:482d — operator graceful-stop sentinel, mechanized): run ~/.claude/skills/relay/scripts/stop-sentinel.sh check --path ${STOP_PATH} (expand a leading ~ to $HOME) EXACTLY ONCE and return its JSON verbatim as stopRequested. The script atomically implements the check/countdown/consume semantics (absent → false; positive-integer countdown → decrement, false; anything else → consume + timestamped log line, true) in one call, so consumption can never lag behind the round it fires in. This is the ONLY actor that runs it; never run more than once per round.`,
  { label: 'discover-prelude', phase: 'Discover', schema: PRELUDE_SCHEMA, model: 'haiku' }
)

// id:c5ba/id:a921 — canonicalize the run id ONCE, here: the earliest point it exists, and
// BEFORE any consumer cites it. `||` preserves the front-door mint (A.RUN_ID) and, from round 2
// on, round 1's value — prelude.runId is re-minted EVERY round, so anything naming a run must
// read state.runId (the stable id the events log, RELAY_STATUS header, heartbeat and burn
// sampler all write). Consumers that cited prelude.runId printed a run nothing ever wrote:
// `relay-burn.sh --run <that id>` returned "0 samples" (id:a921). Guarded for a failed prelude
// (the stop-sentinel branch below tolerates a falsy prelude).
state.runId = state.runId || (prelude && prelude.runId) || ''

// id:c012 — operator graceful-stop sentinel fired this round. The PRIOR round's wave +
// integration debt were already drained by runRound before this discovery ran, so there is
// nothing in flight to abandon: short-circuit BEFORE sharding/dispatch (drop any queued units,
// do NOT re-discover a new wave), set the machine-readable stop reason, and let the outer loop
// break. FAIL-SAFE: only a literal stopRequested===true triggers it (a dead prelude / absent
// field is falsy ⇒ normal run), so a flaky sentinel read can never wedge the pool.
if (prelude && prelude.stopRequested === true) {
  stopReason = 'user-stop'
  log('relay-loop: STOP sentinel — operator graceful stop; draining (prior wave already integrated), not dispatching a new wave')
  // Persist the user-stop into RELAY_STATUS before short-circuiting: the normal end-of-round
  // status write (~L1357) is skipped on this early return, so without this the "Stop reason"
  // section would stay stale ("(none — drained cleanly)") even though the run returns
  // stopReason="user-stop". snapshotState captures the module-level stopReason; the outer
  // loop's `await statusTail` flushes this queued write. Set the fresh prelude timestamp so the
  // header isn't stale (discovery isn't built on this path); runId is already canonicalized above.
  if (prelude.ts) state.ts = prelude.ts
  scheduleStatusWrite(state)
  return { actionable: 0, produced: 0, userStop: true }
}

let discovery = null
// id:d530 — the --priority within-class ordering set, populated from the confirmed-own
// priority names below; read by the unit sort comparators (priorityRank). Empty when no
// --priority arg ⇒ no ordering change (fail-safe).
let prioritySet = new Set()
if (prelude && Array.isArray(prelude.repos)) {
  // id:d530 — per-run --exclude / --priority. EXCLUDE drops repos from the own-repo list
  // BEFORE sharding (no shard sees them, no unit is emitted); each confirmed-own excluded repo
  // contributes a benign "excluded for this run (--exclude)" skipped line; an exclude name that
  // is NOT a confirmed own repo is a LOUD reject surfaced below. PRIORITY validates names the
  // same way (unknown → surfaced) and seeds the prioritySet the sort comparators read. NO
  // relay.toml write — the registry is untouched. This inline block is byte-identical to
  // pool-args.mjs::applyExcludeFilter + validatePriorityNames (unit-tested pure copies).
  const allOwnRepos = prelude.repos
  const ownNames = new Set(allOwnRepos.map(r => r.repo))
  const excludeSkipped = [], poolArgSurfaced = []
  // id:7633 — first-class single-repo scope. Resolve A.onlyRepo against the CANONICAL own-repo
  // list (allOwnRepos = the prelude's relay.toml read, honoring `# path:`). A confirmed match
  // narrows the list that enters the exclude filter + sig-cache + discover fan-out to that ONE
  // repo, so the universe classification is bypassed (only one discover-repo.sh runs) while the
  // per-repo path is reused unchanged. An unconfirmed name is a LOUD reject (surfaced; scoped list
  // empty ⇒ no dispatch, no guess). Empty A.onlyRepo ⇒ scopedOwnRepos = the whole fleet (fail-safe,
  // today's behaviour). --exclude / --priority names still validate against the FULL canonical set
  // (ownNames above), so an unknown name loud-rejects even under a single-repo scope.
  let scopedOwnRepos = allOwnRepos
  if (ONLY_REPO) {
    const { scoped, surfaced } = resolveScopeRepo(ONLY_REPO, allOwnRepos)
    if (scoped) {
      scopedOwnRepos = [scoped]
      log(`relay-loop: id:7633 single-repo scope — classifying ONLY '${ONLY_REPO}' (own-repo enumeration + discover fan-out bypassed; canonical relay.toml resolution honoring # path:)`)
    } else {
      scopedOwnRepos = []
      if (surfaced) poolArgSurfaced.push(surfaced)
      log(`relay-loop: id:7633 single-repo scope LOUD reject — '${ONLY_REPO}' is not a confirmed own repo (registry untouched; no dispatch)`)
    }
  }
  const excludeSet = new Set(EXCLUDE_REPOS)
  for (const name of EXCLUDE_REPOS) {
    if (!ownNames.has(name)) poolArgSurfaced.push({ repo: name, reason: `--exclude: unknown/unconfirmed repo '${name}' — ignored (not a confirmed own repo; registry untouched, id:d530)` })
  }
  for (const name of PRIORITY_REPOS) {
    if (ownNames.has(name)) prioritySet.add(name)
    else poolArgSurfaced.push({ repo: name, reason: `--priority: unknown/unconfirmed repo '${name}' — ignored (not a confirmed own repo; registry untouched, id:d530)` })
  }
  // id:d530/id:7633 — --exclude drops repos from the (possibly single-repo-scoped) own list
  // BEFORE sharding: no shard/discover-repo.sh ever sees them, no unit is emitted.
  const ownRepos = []
  for (const r of scopedOwnRepos) {
    if (excludeSet.has(r.repo)) excludeSkipped.push({ repo: r.repo, reason: 'excluded for this run (--exclude)' })
    else ownRepos.push(r)
  }
  if (excludeSkipped.length) log(`relay-loop: id:d530 --exclude — dropped ${excludeSkipped.length} repo(s) from this run (registry untouched): ${excludeSkipped.map(r => r.repo).join(', ')}`)
  if (prioritySet.size) log(`relay-loop: id:d530 --priority — within-class ordering bump for: ${[...prioritySet].join(', ')}`)
  if (poolArgSurfaced.length) log(`relay-loop: id:d530 pool-arg LOUD reject — ${poolArgSurfaced.length} unknown/unconfirmed name(s): ${poolArgSurfaced.map(s => s.repo).join(', ')}`)
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
  // round-robin chunk so shards are balanced regardless of repo order; only CHANGED repos are sharded.
  // id:4860 — carry each repo's LIVE sig (sigByRepo) into the chunk JSON so the runner can
  // content-address the CASE A copy: it copies a repo's queue verdict ONLY when the queue
  // entry's queue_sig byte-matches this live sig. A pure string equality, not judgment.
  const chunks = Array.from({ length: SHARDS }, (_, s) =>
    changed.filter((_, idx) => idx % SHARDS === s).map(r => ({ repo: r.repo, path: r.path, sig: sigByRepo[r.repo] || '' }))
  ).filter(c => c.length)
  const liveClaimsCsv = (prelude.liveClaimRepos || []).join(',')
  // Mechanical discovery runner (id:a0b6 flip step b): the LLM classifier SHARD is REPLACED by
  // a pure-transport runner. Two source shapes (see STEP 0 in the prompt): CASE B (no fresh
  // queue) runs discover-repo.sh once per repo — the full live path; CASE A (fresh id:9d97
  // queue) SPLITS the round — reconcile-repo.sh runs LIVE per repo for the side-effecting half
  // and the deterministic CLASSIFY verdict is copied from the queue (id:9d97 data-loss fix,
  // 2026-07-07 Fable second-opinion: the queue must NEVER substitute for the live reconcile
  // side-effects). discover-repo.sh (id:64b4) composes reconcile-repo.sh (side-effecting git,
  // id:5987) + classify-repo.sh --emit unit (deterministic full-unit assembler, id:3d61) and
  // routes per repo, so ALL verdict + reconciliation logic is deterministic + tested
  // (test_reconcile_repo.sh / test_classify_repo_unit.sh / test_discover_repo.sh). The runner
  // emits NO judgment: it runs scripts per repo (+ a queue cat in CASE A) and concatenates the
  // JSON. classify-verdict never emits AMBIGUOUS today,
  // so the big LLM shard prompt is DELETED (the dormant AMBIGUOUS path is surfaced loudly by
  // discover-repo.sh) — DP1 "classifier primary, no post-flip comparator" (meetings
  // 2026-06-30-1523 / 2026-07-01-1904). The four JS-side backstops below (id:000d/9973/ad74/365b)
  // stay as belt-and-suspenders (meeting A2); deletion is gated on id:b50e.
  const runnerPrompt = (chunk) => `You are a MECHANICAL discovery runner for the relay pool. You do NOT classify or judge anything yourself — you run ONE command per repo (either a cat or an exec, per the STEP 0 check below) and return its JSON verbatim.

Process EXACTLY these own repos (each once, no others):
${JSON.stringify(chunk)}

This run's runId is "${prelude.runId}". Repos currently held by a live relay run are: "${liveClaimsCsv}".

STEP 0 — SPLIT each repo into a LIVE reconcile half (ALWAYS runs, every round) and a CLASSIFY half (from the mechanical queue when fresh, else live). WHY the split (id:9d97 data-loss fix, 2026-07-07 Fable second-opinion): the mechanical producer's reliability win is in the deterministic CLASSIFY verdict (the Haiku-mangle-prone "run classify + echo the verdict" step). The RECONCILE half is bounded SIDE-EFFECTING git — ff-merge behind-origin (id:c3f7), uv.lock cascade commit (id:bae5), worktree reap/park + orphan suppress-redispatch (id:1f53/ebfb), and live-claims filtering — that MUST run LIVE against real pool state every round; the read-only producer (--no-reconcile) never performed it, and the queue carries NO live-claims context and only mtime freshness. So NEVER take reconcile results from the queue: always run reconcile live, and take only the classify verdict from the queue.

First check whether a FRESH mechanical discovery-queue snapshot exists (id:7402/D3, PRODUCER id:9d97): run
  find ${DISCOVERY_QUEUE_LATEST} -newermt "@$(( $(date +%s) - ${DISCOVERY_QUEUE_FRESH_SECS} ))" 2>/dev/null

CASE A — that command prints the path (file exists AND its mtime is within the last ${DISCOVERY_QUEUE_FRESH_SECS}s ⇒ FRESH queue): take the CLASSIFY verdict from the queue, but STILL reconcile LIVE. Run
  cat ${DISCOVERY_QUEUE_LATEST}
ONCE for the whole chunk. Then for EACH repo in your list above, run its LIVE reconcile — this ONE command (substitute its repo name and path from the entry):
  ~/.claude/skills/relay/scripts/reconcile-repo.sh --repo <repo> --path <path> --runid ${prelude.runId} --live-claims "${liveClaimsCsv}"
It emits ONE JSON object {"repo":...,"actions":[...],"surfaced":[...]} and performs the round's bounded side-effects for that repo. THEN route this repo, mirroring discover-repo.sh exactly:
  • if reconcile's "surfaced" array is NON-EMPTY (in-flight elsewhere / parked orphan / diverged-from-origin) → emit {"units":[],"surfaced":<reconcile's surfaced array>,"skipped":[]} for this repo and STOP — do NOT take the queue's classify verdict (a surfaced repo is never classified).
  • else (reconcile surfaced nothing) → CONTENT-ADDRESS the copy (id:4860). Find THIS repo's entries in the queue's top-level "units"/"surfaced"/"skipped" arrays by matching .repo == <repo name>. Each entry carries a "queue_sig" field (the sig the producer stamped). Each repo in the list above carries a "sig" field (its LIVE sig this round). COPY the queue entries VERBATIM ONLY IF the matched queue entry's "queue_sig" is BYTE-IDENTICAL to this repo's "sig" from your list — a pure string equality, NOT judgment (do not re-derive, re-run, or re-judge anything). If they MATCH, copy the entries verbatim. If the queue_sig is MISSING, EMPTY (the fail-open sentinel — an empty sig can never content-address, even if the live sig is also empty), or does NOT byte-match the live sig (the repo's state changed after the snapshot, or the copy was mangled), DO NOT copy the stale verdict — instead run the CASE B live command for THAT repo only (~/.claude/skills/relay/scripts/discover-repo.sh --repo <repo> --path <path> --runid ${prelude.runId} --live-claims "${liveClaimsCsv}") and use ITS output for this repo (a live unit carries no queue_sig). If a repo is MISSING from the queue's arrays entirely, likewise fall to that CASE B live command — NEVER guess a verdict. THIS SIG-GATED CAT-AND-COPY OF THE CLASSIFY VERDICT IS THE RESIDUAL LLM SURFACE (id:7402/D3 — the known-remaining, irreducible-for-now LLM read; deferred+labeled, not eliminated; see relay/references/discovery-queue-manifest.md and the 2026-07-07 discovery-off-Workflow meeting note). Content-addressing SHRINKS the trust in this residual read: it is a pure file-echo of an already-mechanical verdict gated on a byte-equal sig (a mechanical mangle canary the JS re-asserts) — far smaller surface than classifying yourself, but still an LLM hop until the launch-wall (id:af30/id:2ec4) is resolved.

CASE B — the find command prints NOTHING (queue missing or stale — e.g. the id:9d97 \`.timer\` is not installed/enabled, the shipped default): FALL BACK to the live exec path, unchanged from before this queue existed — discover-repo.sh does BOTH reconcile and classify live. For EACH repo in the list above, run this ONE command (substitute its repo name and path from the entry):
  ~/.claude/skills/relay/scripts/discover-repo.sh --repo <repo> --path <path> --runid ${prelude.runId} --live-claims "${liveClaimsCsv}"
It emits ONE JSON object {"units":[...],"surfaced":[...],"skipped":[...]} for that repo — it does ALL reconciliation, classification, and routing internally. Collect all of them.

NO-FILESYSTEM-HUNTING GUARD (id:612f): per repo, run ONLY the command(s) STEP 0 selected — CASE A: the queue cat (ONCE for the whole chunk) PLUS reconcile-repo.sh (ONCE per repo), plus — ONLY for a repo whose queue_sig is missing/mismatched or that is absent from the queue (id:4860) — the ONE live discover-repo.sh fallback for THAT repo; CASE B: discover-repo.sh (ONCE per repo). Never anything else. Do NOT run git, gather-repo-state, classify-repo, find (beyond the STEP 0 freshness check), or read ROADMAP/relay.toml/transcripts — the selected source(s) already have everything. If discover-repo.sh errors for a repo, put that repo in "surfaced" with the reason — NEVER guess a verdict.

Return {units, surfaced, skipped} = the CONCATENATION across every repo in your list (append each repo's three arrays). Each repo appears exactly once across units+surfaced; an idle repo appears in BOTH units and skipped.`
  // Only CHANGED repos pay for a runner agent (id:c3a6); a round where every repo is cached runs
  // zero runners and is still a valid round (shardOk seeded true below).
  if (changed.length) log(`relay-loop: id:7402 discover-run agent() dispatch — RECONCILE runs LIVE every round (reconcile-repo.sh per repo: ff-merge/uv.lock/reap-park/live-claims side-effects); the CLASSIFY verdict comes from the id:9d97 mechanical queue (${DISCOVERY_QUEUE_LATEST}, fresh<${DISCOVERY_QUEUE_FRESH_SECS}s) when present AND content-addressed (id:4860: copied only when the queue entry's queue_sig byte-matches the repo's live sig — else the live discover-repo.sh path for that repo), else the full live discover-repo.sh exec path; EITHER WAY the agent() call itself is the residual LLM surface (D3, deferred+labeled, not eliminated — see relay/references/discovery-queue-manifest.md), now with a JS-side queue_sig mangle canary`)
  const shardResults = changed.length
    ? await parallel(chunks.map((chunk) => () =>
        agent(runnerPrompt(chunk), { label: `discover-run:${chunk.length}`, phase: 'Classify', schema: SHARD_SCHEMA, model: 'haiku' })
      ))
    : []
  // Merge the shard classifications + the cached (reused) verdicts + the prelude's injected units +
  // non-own skipped rollup into the single discovery object the rest of runRound consumes
  // (byte-identical shape).
  // id:d530 — seed skipped with the --exclude rollup lines and surfaced with the pool-arg
  // LOUD-reject lines (unknown --exclude/--priority names), alongside the existing config/idle rollups.
  const units = [], surfaced = [...poolArgSurfaced], skipped = [...(prelude.skippedConfig || []), ...reusedIdle, ...excludeSkipped]
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
  // id:4860 — discovery-queue mangle canary (belt-and-suspenders for the content-addressed
  // CASE A copy). The runner prompt is INSTRUCTED to copy a queue verdict only when the queue
  // entry's queue_sig equals the repo's live sig — a pure string equality, not judgment. This
  // JS assert re-checks it MECHANICALLY: any queue-sourced unit (one carrying a queue_sig)
  // whose queue_sig does NOT byte-match this round's live sig (sigByRepo) is DROPPED from
  // dispatch and SURFACED loudly — same pattern as the shard-failure surfacing above (costs one
  // round, never dispatches on stale/mangled state). This structurally dissolves gap (1) the
  // stale snapshot (an executor committed AFTER the T−Δ snapshot, so its execute/idle verdict
  // outlived the live state that now demands review) and gap (2) went-dirty-after-snapshot, AND
  // catches gap (3) a Haiku bridge-copy that mangled/dropped the sig (a fabricated-but-correct
  // 64-hex sig is implausible). CASE B / live / reused / injected units carry NO queue_sig
  // (computed live) and are EXEMPT. Only sig-matching (or exempt) units reach the discoverCache
  // write below — that fixes the stale-cache-poisoning: a stale verdict can never be cached
  // under the NEW live sig (it is dropped here first).
  {
    const kept = [], staleDropped = []
    for (const u of units) {
      // Empty queue_sig is the discover-sig fail-open SENTINEL — it can never content-address a
      // verdict, so it is dropped even when the live sig is ALSO empty ('' === '' must NOT pass:
      // both sides failing sig derivation is systemic discover-sig breakage, not a match).
      if (u.queue_sig !== undefined && (u.queue_sig === '' || u.queue_sig !== (sigByRepo[u.repo] || ''))) staleDropped.push(u)
      else kept.push(u)
    }
    if (staleDropped.length) {
      log(`relay-loop: id:4860 discovery-queue sig canary — dropped ${staleDropped.length} unit(s) whose queue_sig != live sig (stale snapshot / went-dirty-after-snapshot / mangled bridge-copy): ${staleDropped.map(u => u.repo).join(', ')}`)
      for (const u of staleDropped) {
        surfaced.push({ repo: u.repo, reason: `discovery-queue verdict dropped: queue_sig != live discover-sig (repo state changed after the snapshot, or the queue copy was mangled) — re-derived next round (content-addressed mangle canary id:4860)` })
      }
      units.length = 0
      units.push(...kept)
    }
  }
  // id:c3a6 — cache the FRESHLY-classified units keyed by this round's signature, THEN fold in the
  // reused (cached) verdicts. Reused units already sit in the cache under the same sig, so only fresh
  // ones are written. Surfaced / idle-without-unit repos are NOT cached → they re-classify next round
  // (safe over-invalidation). Injected units are never cached (consumed each round by inject.sh take).
  // id:4860 — only sig-matching (or CASE B live/exempt) units reach here; a stale queue verdict was
  // dropped by the canary above, so it can never poison the cache under the NEW live sig.
  for (const u of units) { const sig = sigByRepo[u.repo] || ''; u.sig = sig; if (sig) state.discoverCache[u.repo] = { sig, unit: u } }
  units.push(...reusedUnits)
  units.push(...(prelude.injectedUnits || []))
  // shardOk = at least one shard succeeded → build discovery (failed shards' repos are surfaced).
  // All shards failed (total network outage) → discovery stays null → the round fails gracefully
  // and the outer loop stops after completed rounds (resumable via Workflow resumeFromRunId).
  // id:000d — JS-side is_finished demote guard (anti-false-handoff). Runs after ALL shard
  // results are merged so it catches any shard that emitted execute/hard/handoff for a
  // provably-finished repo. is_finished is computed deterministically by gather-repo-state.sh
  // (roadmap present/non-empty + 0 open "- [ ]" items + commits_since_ckpt empty + clean tree).
  // DEMOTE-ONLY: a finished repo is removed from units and pushed to surfaced with a fixed reason.
  // review is unaffected (review requires commits_since_ckpt non-empty → is_finished false anyway).
  // Injected units (id:baf1) are exempt from demotion — an explicit user injection overrides
  // the finished-repo heuristic (the user may have targeted a specific task to finish).
  {
    const FINISHED_DEMOTE_VERDICTS = new Set(['execute', 'hard', 'handoff'])
    const kept = [], demotedFinished = []
    for (const u of units) {
      if (!u.injected && u.is_finished && FINISHED_DEMOTE_VERDICTS.has(u.verdict)) {
        demotedFinished.push(u)
      } else {
        kept.push(u)
      }
    }
    if (demotedFinished.length) {
      log(`relay-loop: id:000d finished-repo demote — ${demotedFinished.length} unit(s) removed from dispatch (execute/hard/handoff on finished repos): ${demotedFinished.map(u => u.repo).join(', ')}`)
      for (const u of demotedFinished) {
        surfaced.push({ repo: u.repo, reason: 'finished repo (0 open items, clean, no unaudited commits) — not dispatched (anti-false-handoff guard id:000d)' })
        emitBackstopFire('000d', u.repo, u.verdict)
      }
      units.length = 0
      units.push(...kept)
    }
  }
  // id:9973 — JS-side HARD-pool demote guard (deterministic, mirrors the id:000d pattern).
  // Runs after ALL shard results are merged so it catches any shard that emitted a `hard`
  // verdict for a repo with NO open executable [HARD — pool] item (or, id:4f02/id:8111
  // dual-vocab window, the new bare [HARD] tag). Only [HARD — pool]/bare-[HARD] items
  // are pool-dispatchable (relay/references/hard-lanes.md); [HARD — meeting]/[HARD — decision
  // gate]/[HARD — hands] (and their new-vocab equivalents [INPUT — meeting]/[INPUT —
  // decision]/[INPUT — access]) are NOT — but the LLM shard's `hard` judgment is
  // non-deterministic and has wrongly dispatched repos whose only open HARD item was [HARD — decision gate], handing
  // them back as pre-start size-outs (burning Opus; observed 2026-06-24). open_hard_pool is
  // computed deterministically by gather-repo-state.sh (count of open [HARD — pool] items, minus
  // any recurring-audit item with nothing to audit). DEMOTE-ONLY: a `hard` unit on a repo with
  // open_hard_pool == 0 is removed from units and pushed to surfaced — it can only push toward
  // surfaced, never toward a higher verdict. Injected units (id:baf1) are exempt. Only the
  // `hard` verdict is touched; review/execute/handoff are unaffected.
  {
    const kept = [], demotedHard = []
    for (const u of units) {
      if (!u.injected && u.verdict === 'hard' && (u.open_hard_pool || 0) === 0) {
        demotedHard.push(u)
      } else {
        kept.push(u)
      }
    }
    if (demotedHard.length) {
      log(`relay-loop: id:9973 HARD-pool demote — ${demotedHard.length} unit(s) removed from dispatch (hard verdict, no open [HARD — pool] item): ${demotedHard.map(u => u.repo).join(', ')}`)
      for (const u of demotedHard) {
        surfaced.push({ repo: u.repo, reason: 'HARD backlog is gated — no open [HARD — pool] item (only meeting/hands/decision-gate lanes); not dispatched (deterministic demote-guard id:9973)' })
        emitBackstopFire('9973', u.repo, u.verdict)
      }
      units.length = 0
      units.push(...kept)
    }
  }
  // id:ad74 — JS-side INTENSIVE promote backstop (symmetric PROMOTE counterpart to id:000d DEMOTE).
  // After all shard results are merged, a repo whose gathered state shows an open [INTENSIVE — <res>]
  // item (top_intensive non-empty) MUST NOT remain idle. The shard contract guarantees every repo
  // it classified "idle" ALSO appears as an emitted UNIT (verdict:'idle') — not only in the skipped
  // rollup — and the shard copies top_intensive verbatim onto every unit it emits. So the recoverable
  // case is "an emitted unit with top_intensive set"; we operate on units only. (A skipped-rollup
  // entry carries just {repo, reason} — no top_intensive — so it is NOT a recoverable source here;
  // its paired unit is. Treating skipped entries as a source was a dead branch: top_intensive was
  // always '' when the unit was absent, the symmetric twin of the id:401c-Run-45 dead-guard bug.)
  //
  // For each unit with top_intensive set: (1) copy it to .intensive (the field the INTENSIVE
  // partition at line ~935 reads), AND (2) if the shard parked the unit as verdict:'idle', PROMOTE
  // it to 'execute' — otherwise the `verdict !== 'idle'` filter (the `actionable` build below) drops
  // it BEFORE the intensive partition ever sees it, so merely patching .intensive on an idle unit is
  // a no-op. The INTENSIVE partition then gates real dispatch behind --allow-intensive
  // (ALLOW_INTENSIVE ? intensiveUnits : intensiveDeferred) — exactly as a shard-emitted intensive
  // unit would be. PROMOTE-ONLY: only moves idle→execute, never demotes a higher verdict.
  // Injected units are exempt (explicit user injection is already the highest priority).
  {
    const promotedIntensive = []
    for (const u of units) {
      const top_intensive = u.top_intensive || ''
      if (!top_intensive || u.injected) continue
      if (!u.intensive) u.intensive = top_intensive
      if (u.verdict === 'idle') {
        u.verdict = 'execute'
        u.reason = `promoted by INTENSIVE-emit backstop (id:ad74): open [INTENSIVE — ${top_intensive}] item found but shard classified idle — intensive dispatch gated behind --allow-intensive. ${u.reason || ''}`.trim()
        promotedIntensive.push(`${u.repo}(idle→execute,${top_intensive})`)
        emitBackstopFire('ad74', u.repo, u.verdict)
      } else {
        promotedIntensive.push(`${u.repo}(intensive-field-patched,${top_intensive})`)
      }
    }
    if (promotedIntensive.length) {
      log(`relay-loop: id:ad74 INTENSIVE promote backstop — ${promotedIntensive.length} repo(s) corrected: ${promotedIntensive.join(', ')}`)
    }
  }
  // id:1432 — WHOLE-DISPATCH no-work suppression. Runs BEFORE the id:365b >3× circuit breaker:
  // a repo+verdict that handed back "no executor-actionable work" (route=none) this run is not
  // re-dispatched at all while its work_sig is unchanged, so a false/stale verdict is capped at
  // its FIRST wasted child (the breaker's >3× is the coarser backstop for any other spin).
  // Injected units are exempt. Suppressed units are surfaced (visible, not silently dropped).
  {
    // id:a921 — cite the CANONICAL run id (state.runId, canonicalized at the prelude), not the
    // per-round prelude mint: the reason carries a `relay-burn.sh --run <id>` cost hint, and
    // prelude.runId names a run nothing ever wrote (0 samples).
    const { kept, suppressed } = applyNoWorkSuppression(units, noWorkNegCache, state.runId)
    if (suppressed.length) {
      for (const s of suppressed) surfaced.push({ repo: s.unit.repo, reason: s.reason })
      log(`relay-loop: id:1432 no-work handback suppression — ${suppressed.length} unit(s) not re-dispatched (route=none handback, work_sig unchanged): ${suppressed.map(s => `${s.unit.repo}(${s.unit.verdict})`).join(', ')}`)
      units.length = 0
      units.push(...kept)
    }
  }
  // id:365b — the re-dispatch circuit breaker USED to run here. MOVED (id:f980, shape A) down to
  // just before the dispatch sort: it must run AFTER every verdict mutation (notably the
  // id:9821/e030 Fable idle→review elevation) and over the idle-FILTERED set. Running it here was
  // wrong twice: (1) it counted `${repo}:idle` keys for units the `verdict !== 'idle'` filter
  // later dropped — surfacing phantom ">3× dispatched" reasons for repos dispatched ZERO times
  // (run relay-20260716-125514-23493: 38 phantom entries buried 2 real handbacks); and (2) its
  // splice could delete an idle unit the Fable elevation still needed, silently dropping the
  // optional recheck after 3 rounds. See the breaker at its new home below.
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
      u.reason = `optional Fable recheck (${src} — strong checkpoint pending independent Fable audit). Prior verdict: ${u.verdict}. ${u.reason || ''}`.trim()
      u.verdict = 'review'
      elevated++
    }
  }
  if (elevated) log(`relay-loop: elevated ${elevated} repo(s) to review for optional Fable re-audit (id:9821 + durable queue id:e030)`)
}

// Sort: verdict class first (D3 invariant), then the per-run --priority bump (id:d530:
// a priority repo's NATURALLY-discovered unit ranks ahead WITHIN its verdict class), then
// income repos win slot contention within a class (user directive 2026-06-12: prefer
// income-relevant tasks), then the fable-standin tiebreaker (user directive 2026-06-13;
// see standInRank above). Injected units (id:baf1) outrank everything — they are explicit,
// high-priority user requests; --priority is below injected-precedence + the D3 verdict-class
// order (NEVER a verdict override), above income.
// The DISPATCHABLE set: idle units never dispatch, so they are dropped BEFORE the id:365b
// breaker sees them (id:f980). Filtering first — rather than special-casing `verdict==='idle'`
// inside the guard — is what keeps the inline copy logic-equivalent to redispatch-guard.mjs:
// the helper's semantics are untouched; only the set it is handed changes. The breaker then
// counts exactly what dispatches, under the verdict key it actually dispatches as.
const dispatchable = discovery.units.filter(u => u.verdict !== 'idle')

// id:365b — re-dispatch circuit breaker (mechanism 2, deterministic JS backstop). Runs AFTER
// the id:000d finished-demote, id:ad74 INTENSIVE-promote and id:9821/e030 Fable-elevation
// verdict mutations, over the idle-filtered `dispatchable` set, and BEFORE the dispatch sort —
// i.e. it is the LAST gate before dispatch, so what it counts is exactly what dispatches
// (id:f980, shape A). The principled fix is mechanism 1 (the shard's recurring-audit gate);
// this catches ANY dispatch spin even if the shard slips. For each non-injected unit, key on
// `${repo}:${verdict}`: if the persistent counter's stored work_sig matches this unit's
// work_sig (a sig STABLE across the pool's own `relay: checkpoint` churn, so unchanged means
// "no substantive change since last dispatch") increment its count, else (re)seed at 1. A
// unit may dispatch on counts 1,2,3 and is SUPPRESSED once count would reach 4 ("not more
// than thrice") — removed from dispatch and surfaced. A work_sig change resets the counter.
// Injected units (id:baf1) are EXEMPT (an explicit user request is never auto-suppressed).
// A Fable-elevated unit (idle→review) is counted as `${repo}:review` — the verdict it
// dispatches as — so the optional recheck is spin-protected like any other review.
// NOTE: this inline copy MUST stay logic-equivalent to redispatch-guard.mjs (the unit-tested
// pure helper — the Workflow sandbox cannot import it). A structural test pins the wiring.
{
  const keptCB = [], suppressedCB = []
  for (const u of dispatchable) {
    if (u.injected) { keptCB.push(u); continue }
    const key = `${u.repo}:${u.verdict}`
    const sig = u.work_sig || ''
    const prev = redispatchGuard[key]
    if (prev && prev.sig === sig) prev.count++
    else redispatchGuard[key] = { sig, count: 1 }
    if (redispatchGuard[key].count > 3) {
      suppressedCB.push(u)
      discovery.surfaced.push({ repo: u.repo, reason: `circuit breaker (id:365b): ${u.repo} ${u.verdict} dispatched >3× this run with no substantive change (work_sig unchanged) — skipping until new work or a human intervenes; cost hint: relay-burn.sh --run ${state.runId}` })
    } else {
      keptCB.push(u)
    }
  }
  if (suppressedCB.length) {
    log(`relay-loop: id:365b re-dispatch circuit breaker — ${suppressedCB.length} unit(s) suppressed (>3× this run, work_sig unchanged): ${suppressedCB.map(u => `${u.repo}(${u.verdict})`).join(', ')}`)
    dispatchable.length = 0
    dispatchable.push(...keptCB)
  }
}

let actionable = dispatchable
  .sort((a, b) =>
    ((b.injected ? 1 : 0) - (a.injected ? 1 : 0)) ||
    (PRIORITY[a.verdict] - PRIORITY[b.verdict]) ||
    (priorityRank(a, prioritySet) - priorityRank(b, prioritySet)) ||
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
  // All-execute now, so PRIORITY ties; injected units (id:baf1) still outrank, then the per-run
  // --priority bump (id:d530), then income repos win slot contention, then the fable-standin
  // tiebreaker prefers Fable-vetted roadmaps.
  actionable = kept.concat(demoted).sort((a, b) =>
    ((b.injected ? 1 : 0) - (a.injected ? 1 : 0)) ||
    (priorityRank(a, prioritySet) - priorityRank(b, prioritySet)) ||
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
// are never auto-run (OOM risk). With --intensive (id:052c; synonym --allow-intensive) they run
// serially-alone AFTER the wave (intensiveUnits); otherwise they are surfaced as skipped
// (intensiveDeferred). A bare --afk does NOT enable them (id:052c — --afk stays non-intensive).
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
if (intensiveUnits.length) log(`relay-loop: --intensive — ${intensiveUnits.length} [INTENSIVE] unit(s) will run SERIALLY-ALONE after the wave: ${intensiveUnits.map(u => `${u.repo}(${u.intensive})`).join(', ')}`)
if (intensiveDeferred.length) log(`relay-loop: ${intensiveDeferred.length} [INTENSIVE] unit(s) NOT dispatched — need --intensive (a bare --afk no longer enables them, id:052c): ${intensiveDeferred.map(u => `${u.repo}(${u.intensive})`).join(', ')}`)

// id:5eb3 — human-verdict mechanical surface-filer: extract `human` units (promote==0 ∧ surface>0)
// from the dispatch queue and call file-surface-decisions.sh for each. No apex dispatch is ever
// spawned for a human unit — mechanical filing only. LOUD: each filing is logged and counted;
// never a silent no-op (anti-gaming invariant, id:47f1). Items with an existing OPEN decision-queue
// record are skipped idempotently by the script; the anti-gaming loop stops once all items are filed.
{
  const nonHuman = []
  const humanUnits = []
  for (const u of actionable) {
    if (u.verdict === 'human') humanUnits.push(u)
    else nonHuman.push(u)
  }
  actionable = nonHuman
  if (humanUnits.length) {
    log(`relay-loop: id:5eb3 — ${humanUnits.length} human-verdict unit(s) (surface-only backlog): filing to decision-queue mechanically: ${humanUnits.map(u => u.repo).join(', ')}`)
    // Fire all human-verdict filings concurrently (each is an independent repo, no cross-dep).
    await Promise.all(humanUnits.map(u =>
      agent(
        `Run EXACTLY this one command for the surface-only TODO backlog of repo ${u.repo} and report its stdout verbatim (it files each surface item to the decision-queue so the relay loop stops re-firing on them, id:5eb3/id:47f1):
~/.claude/skills/relay/scripts/file-surface-decisions.sh '${u.path}'
Report the single output line. If it exits non-zero, report the error; do not retry.`,
        { label: `file-surface:${u.repo}`, phase: 'Support', model: 'haiku' }
      ).catch(err => log(`relay-loop: id:5eb3 file-surface-decisions for ${u.repo} failed (non-fatal): ${err}`))
    ))
  }
}

// id:7616 — mechanical-verdict surface (POOL-INERT). A `mechanical` verdict (classify-verdict.sh
// priority_rank 6) means the repo's only remaining backlog is open [MECHANICAL] items — pure-compute
// work a HOST DAEMON dispatches (A3, gated), NEVER the LLM pool. Mirror the CONTRACT of the `human`
// verdict EXACTLY: present in the schema enum + PRIORITY and SURFACED, but never dispatched as an
// executor child and ABSENT from PHASE_BY_VERDICT. Pull mechanical units out of the dispatch queue
// so no child is ever spawned, and surface them in RELAY_STATUS Queued with a clear pool-inert
// reason so they are VISIBLE, not silently dropped. Unlike `human` there is not even a mechanical
// filing agent — the host daemon (A3, gated) owns the actual dispatch; the pool only makes it seen.
let mechanicalSurfaced = []
{
  const nonMechanical = []
  for (const u of actionable) {
    if (u.verdict === 'mechanical') mechanicalSurfaced.push(u)
    else nonMechanical.push(u)
  }
  actionable = nonMechanical
  if (mechanicalSurfaced.length) {
    log(`relay-loop: id:7616 — ${mechanicalSurfaced.length} mechanical-verdict unit(s) (open [MECHANICAL] backlog): POOL-INERT — surfaced in RELAY_STATUS Queued, NEVER dispatched (host daemon A3, gated): ${mechanicalSurfaced.map(u => u.repo).join(', ')}`)
  }
}

// Refresh the cross-round accumulator's per-round views (completed/reviewMe persist).
// (state.runId is canonicalized right after the !discovery guard above — id:a921.)
state.ts = discovery.ts

// id:e149 — beat the STABLE run-heartbeat (state.runId, fixed at round 1) every round. This
// MUST use state.runId, not the prelude's per-round freshly-generated runId: the prelude
// regenerates `relay-<ts>-<rand>` each round, so beating that would create a NEW marker each
// round and never refresh the prior one — leaving stale orphan markers that falsely read
// "dead" to the watchdog (id:98f0) while the pool is alive. The integrator also beats per
// settled unit (intra-round freshness), so the marker stays fresh whenever the pool does
// anything; only a genuinely dead loop lets it age past TTL. Best-effort.
await beatHeartbeat()
state.queued = [
  ...actionable.map(u => ({ repo: u.repo, verdict: u.verdict })),
  ...hardDeferred.map(u => ({ repo: u.repo, verdict: `hard (deferred: HARD-execute needs apex Opus; STRONG_MODEL=${STRONG_MODEL} — left for Fable handoff-C5/review-step6)` })),
  ...fableDownDeferred.map(u => ({ repo: u.repo, verdict: `${u.verdict} (deferred: --fable-down, strong model skipped)` })),
  ...intensiveDeferred.map(u => ({ repo: u.repo, verdict: `intensive:${u.intensive} (skipped — needs --intensive; a bare --afk no longer enables it, id:052c; never auto-run, OOM risk id:8d52)` })),
  // human-verdict repos are not queued (they were handled by the surface-filer above); they
  // surface in RELAY_STATUS skipped as "human (surface-only: filing dispatched)" so the operator
  // can see them without confusing them with dispatchable queued work.
  // mechanical-verdict repos (id:7616): POOL-INERT — surfaced here in Queued (visible, never
  // dispatched by the LLM pool; a host daemon dispatches them, A3, gated). Mirrors the `human`
  // contract: pulled from `actionable` above, no child spawned, absent from PHASE_BY_VERDICT.
  ...mechanicalSurfaced.map(u => ({ repo: u.repo, verdict: `mechanical (pool-inert: pure-compute work for the host daemon, A3-gated; never dispatched by the LLM pool)` })),
]
state.surfaced = buildSurfacedView(discovery.surfaced)
state.skipped = (discovery.skipped || []).map(s => ({ repo: s.repo, reason: s.reason }))   // id:be62

log(`relay-loop: ${actionable.length} actionable units (${discovery.units.length} own repos, ${discovery.surfaced.length} surfaced)`)
scheduleStatusWrite(state)

// No actionable units this round (incl. --fable-down with no executor work) → a dry
// round; the outer loop counts consecutive dry rounds toward "backlog drained".
if (actionable.length === 0 && intensiveUnits.length === 0) {
  if (FABLE_DOWN && STRONG_MODEL === 'claude-fable-5') log('relay-loop: --fable-down — no executor work this round, strong work deferred')
  // id:4ca8 — plumb the surfaced count through so the outer loop can tell "no work" apart from
  // "work exists but is BLOCKED" (suppressed/gated repos surfaced by discovery this round).
  return { actionable: 0, produced: 0, surfaced: discovery.surfaced.length }
}

// ── Phase 2+3: Dispatch pool + serialized integration ──

// id:7d1e — finer-grained progress buckets (user request 2026-06-22): instead of dumping
// every dispatch-time agent into one crowded "Dispatch" group, route each WORK unit to a
// per-verdict phase (Execute/Review/Hard/Handoff) and shunt the non-work support agents
// (quota gate, per-unit lease release, injection take) into a "Support" bucket. Purely a
// display grouping — zero behavioural change. The serialized merge stays under "Integrate".
const PHASE_BY_VERDICT = { execute: 'Execute', review: 'Review', hard: 'Hard', handoff: 'Handoff' }
const unitPhase = (v) => PHASE_BY_VERDICT[v] || 'Execute'

phase('Execute')

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
${unit.verdict === 'execute' ? 'Work the open [ROUTINE] items in ROADMAP.md under the executor contract. Stop at a natural boundary; never start an item you cannot finish. SIZE-OUT rule (id:08c0): if a [ROUTINE] item is too large to land green in one session and you cannot partially advance it, do NOT silently leave it open — return a structured handback (contract_met=false, handback_item=<id>, route=hard-split or decision-gate, gate_reason). Soft notes (friction:/BLOCKED:) are not sufficient; the integrator\'s durable follow-up (id:3801) reads only the structured fields. Leave the worktree COMPLETELY CLEAN on a size-out (no commit) — same clean-worktree discipline as the hard-verdict id:8b1f.' : ''}
${unit.verdict === 'hard' ? 'You are an Opus-apex HARD-execute child (id:da26). Pick the TOP open "- [ ]" item tagged [HARD — pool] in ROADMAP.md and SIZE it first. Model your discipline on handoff.md C5 "only if small enough to finish safely": only implement the item if you can finish it cleanly and green within this turn — full red-green-refactor, verify-before-merge. If it is too large, contains nested/multi-session scope, or you cannot make the test suite green safely, do NOT half-do it: set contract_met=false and explain the sizing in handback. CRITICAL (id:8b1f) — a SIZE-OUT / GATED refusal (you decided NOT to start) must leave the worktree COMPLETELY CLEAN: make NO commit, and do NOT write the rationale into RELAY_LOG.md / ROADMAP.md / REVIEW_ME.md in the worktree. The rationale goes ONLY in the returned `handback` field. Reason: the integrator never merges a handback, so ANY commit you make on a refusal strands forever as an orphan worktree (the bug behind id:a4e9); a CLEAN worktree is auto-reaped (id:3ac8). The "write a HANDBACK paragraph to RELAY_LOG.md and commit" step in handoff.md C5 applies ONLY to a genuine mid-item CUTOFF where you already committed real work and need resume provenance — NOT to a pre-start sizing refusal (the item stays open for a manual/next-turn strong session). When you DO finish: tick the item\'s checkbox ONLY if the work is genuinely green (all tests pass — never tick to manufacture a pass), append its done-note, commit in the worktree, and make the full test suite green. Work ONE bounded HARD item only — never start a second.' : ''}
${unit.verdict === 'handoff' ? 'Run checkpoints C1-C4. C5 (HARD execution) only if the top HARD item is small enough to finish safely; otherwise leave it specced.' : ''}
${unit.verdict === 'review' ? 'Run the full trust-but-verify procedure including the test-integrity audit. Single-id-two-views (D2): when you promote a ROADMAP item for work TODO.md already tracks under an <!-- id:XXXX -->, REUSE that token; mint a fresh one via ~/.claude/skills/meeting/append.sh new-ids N ' + unit.path + ' ONLY for genuinely new work — NEVER invent tokens, and never duplicate-id already-tracked work. When you close a ROADMAP item whose id also lives in TODO.md, tick the TODO line too. Reverse-handoff (review.md §5b): qualify+size any unqualified TODO/ROADMAP items added by /meeting or manual edits since the last checkpoint (mini-handoff) — reuse their id. After re-deriving the roadmap, set routine_open = the number of OPEN (unticked) [ROUTINE] items remaining — the supervisor uses it to re-enqueue an execute unit this same pool.' : ''}

Hard rules: commit in the worktree as you go; NEVER push; NEVER tag; NEVER run git-diary-workflow or todo-update; never prompt the user. If you cannot meet the contract, set contract_met=false and explain in handback.

Return: contract_met, branch ("${branch}"), worktree ("${wt}"), summary (one line for the checkpoint tag message), review_me_count (open REVIEW_ME.md boxes you wrote, else 0), diary_fragment (one paragraph), handback ("" if none), routine_open (review units: open [ROUTINE] count after re-derivation; 0 for handoff/execute), worked_ids (id:de69 — array of the ROADMAP/TODO 4-hex id(s) you actually worked this unit: for execute, the item id(s) you closed/advanced; for hard, the single [HARD] item id you executed; for handoff, the id(s) you promoted/created; for review, the ids you verified-green or reopened; [] if none — these are the tokens in the commits/ROADMAP you touched, NOT invented).${unit.verdict === 'review' ? ' ALSO (review units only, id:3826 — feeds the gaming-flag rate logger; see review.md §6 return schema): verified_green (array of ROADMAP ids you confirmed genuinely green this review, [] if none), gaming_flags (array of "<id>: <reason>" strings for every DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT or judgment flag you raised, [] if none), reopened (array of ROADMAP ids you reopened, [] if none).' : ''}

ON A HANDBACK (contract_met=false), ALSO classify it so the integrator records it DURABLY in ROADMAP.md and the pool stops re-dispatching the same un-doable item (id:3801): set handback_item (the 4-hex ROADMAP id you handed back, e.g. the [HARD] item you sized out), and route = one of "decision-gate" (needs a /meeting design decision before anyone can build it), "hard-split" (too large for one turn but decomposable into smaller pickable seams), "human" (needs a manual human action / /relay human), or "none" (transient/other failure — no durable action). Set gate_reason to ONE short line for the inline ROADMAP note. For route="hard-split" ONLY, set proposed_split = an ordered array of seam units [{title, tier:"HARD"|"ROUTINE", dep:"<4-hex id of the seam this one depends on, omit if independent>", id:"<reuse an existing 4-hex token if the seam already has one in the ROADMAP/meeting-note, else OMIT to let the integrator mint one>"}]. On a clean success, omit these (route defaults to none).`
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

Return: contract_met, branch ("${branch}"), worktree ("${wt}"), summary (one line), review_me_count, diary_fragment, handback ("" if none), worked_ids (id:de69 — array of the ROADMAP id(s) you promoted/created this resume, [] if none).`
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
  // Pass RELAY_RUN_ID so quota-stop.sh's extrapolation fallback + burn-sampler (both gated on
  // it, id:0175) actually engage inside a live run. Without this the child shell had no
  // RELAY_RUN_ID → extrapolate_or_stop blind-exited 2 on any stale cache and no burn sample was
  // ever written (so there was never a series to extrapolate from — the circular dead-fallback).
  const runIdEnv = state.runId ? `RELAY_RUN_ID=${state.runId} ` : ''
  // id:4267 — pass the RUN-TOTAL agent count, not the per-round count. quota-stop.sh hard-
  // caps at --agents >= 200 (a runaway-spawn seatbelt spanning the WHOLE self-feeding run), but
  // unitsDispatched resets to 0 each round (let unitsDispatched = 0 in runRound), so with
  // MAX_UNITS=20 it never exceeds 20 and the 200-agent seatbelt could NEVER fire across a
  // multi-round run — a 30-round run could spawn hundreds of agents unchecked. totalDispatched
  // is the across-all-rounds accumulator and is the value the seatbelt is meant to gate on.
  // (Same per-round-vs-run-total accounting family as id:2d20's drain fix.)
  const v = await agent(
    `Run this command and report the result: ${runIdEnv}${thresholdEnv}~/.claude/skills/relay/scripts/quota-stop.sh --tier ${tier} --agents ${totalDispatched} --wall 0
Return exitCode (0 = proceed, 1 = real-cache exhaustion, 2 = cache unreadable with no usable burn sample, 3 = cache unreadable but burn-rate EXTRAPOLATES to over threshold) and, if /tmp/claude-usage-cache.json is readable, one bucket entry per quota bucket with pctRemaining (= 100 - utilization percent) and resetTime when present.
On exit 1 OR exit 3 (a bucket crossed), also return crossedBucket: the bucket the script logged as crossing its threshold. The script logs either "quota-stop: <bucket>=<val>% >= threshold <t>" (exit 1) or "REASON=quota-extrapolated-stop bucket=<bucket>" (exit 3) to stderr — capture that bucket name, e.g. "seven_day_sonnet". Leave crossedBucket absent or empty otherwise.`,
    { label: `quota:${tier}`, phase: 'Quota', schema: QUOTA_SCHEMA, model: 'haiku' }
  )
  if (v && v.buckets && v.buckets.length) state.quota = v.buckets
  // id:8c35 — distinguish exit codes instead of collapsing both to quotaStopped:
  //   exit 0 → proceed
  //   exit 1 → real threshold exhaustion (a specific bucket hit the cap)
  //   exit 2 → cache unreadable, NO usable burn sample to extrapolate → conservative STOP
  //   exit 3 → cache unreadable but the recent burn-rate series extrapolates to over
  //            threshold (id:0175 / routed:82e3) → STOP (distinct from a genuine exhaustion)
  //   agent death / missing → fail-safe STOP
  if (!v || v.exitCode !== 0) {
    quotaStopped = true
    // Derive the human-readable + machine-readable stop category:
    if (!v) {
      stopReason = 'quota-cache-unreadable'  // agent death treated as cache-unreadable/uncertain
      log(`relay-loop: quota gate STOP — reason=quota-cache-unreadable (agent failed; tier=${tier}) — draining in-flight units and integration debt`)
    } else if (v.exitCode === 2) {
      // id:0175 / routed:82e3 — infra cache-read failure with no usable burn sample. Distinct
      // from a genuine quota event so it never masquerades as exhaustion in the surfaced status.
      stopReason = 'quota-cache-unreadable'
      log(`relay-loop: quota gate STOP — reason=${stopReason} (cache unreadable, no usable burn sample to extrapolate; tier=${tier}) — draining in-flight units and integration debt`)
    } else if (v.exitCode === 3) {
      // id:0175 / routed:82e3 — cache unreadable, but the burn-rate extrapolation crossed the
      // threshold. A real (estimated) over-spend signal, kept distinct from both the genuine
      // real-cache exhaustion (exit 1) and the can't-tell cache-unreadable case (exit 2).
      stopReason = `quota-extrapolated-stop${v.crossedBucket ? ':' + v.crossedBucket : ''}`
      log(`relay-loop: quota gate STOP — reason=${stopReason} (cache unreadable; burn-rate extrapolation over threshold; tier=${tier}) — draining in-flight units and integration debt`)
    } else {
      // exit 1: real exhaustion — id:2425: use the agent-returned crossedBucket first, so a
      // decayed/overridden threshold below 90% utilization names the real culprit, not :unknown.
      // Last-resort fallback: the old pctRemaining<=10 heuristic (catches the >=90% case when
      // the agent didn't report crossedBucket — defense in depth, never the primary path).
      const fallbackBucket = (v.buckets || []).find(b => b.pctRemaining <= 10)  // last-resort fallback
      stopReason = `quota-exhausted:${v.crossedBucket || (fallbackBucket && fallbackBucket.bucket) || 'unknown'}`
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
    state.handbacks.push({
      repo: unit.repo,
      reason: `child agent failed/skipped (API error or terminal failure); ${unit.verdict === 'handoff' ? 'auto-resume did not complete' : 'no auto-resume for ' + unit.verdict}. Any committed checkpoints are preserved in the worktree — re-run /relay to resume (handoff continues from the last checkpoint).`,
      worktreePath: worktreePathFor(unit),
    })
    scheduleStatusWrite(state)
    return
  }
  if (!report.contract_met) {
    // HANDBACK: not merged; worktree held on disk for a human/strong turn.
    const hbReason = report.handback || 'contract_met=false'
    state.handbacks.push({ repo: unit.repo, reason: hbReason, worktreePath: report.worktree })
    // id:1432 (b) — loud repeat-tracking: count every child handback this run; a repo+verdict
    // at >=2 surfaces as an ALERT in the exit summary + RELAY_STATUS (a repeating handback is a
    // bug signal, not noise).
    trackHandback(handbackTracker, unit.repo, unit.verdict, hbReason)
    // id:1432 (a) — dispatch-level suppression: a WHOLE-DISPATCH "no executor-actionable work"
    // handback (route missing/none — it produces no durable ROADMAP action from id:3801) stamps
    // a negative cache keyed on the unit's work_sig, so discovery does NOT re-dispatch the same
    // verdict until the work_sig genuinely changes. ITEM-level handbacks (route=decision-gate/
    // hard-split/human, with handback_item) are gated durably by handback-followup.py instead —
    // this is the defense-in-depth for the route=none case that path skips.
    if (!report.route || report.route === 'none') {
      recordNoWorkHandback(noWorkNegCache, unit.repo, unit.verdict, unit.work_sig || '')
    }
    // id:3801 — durably record the handback in ROADMAP.md (auto-gate / auto-split) so the
    // child's judgment doesn't evaporate into RELAY_STATUS and the pool stops re-dispatching
    // the same un-doable item. Fire-and-forget, non-fatal (like logGamingFlags).
    durableHandbackFollowup(unit, report)
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
  // ANY strong unit (review/handoff/hard) produced while this session's strong tier is
  // genuine Fable IS a self-produced strong checkpoint with nothing pending: mark the
  // durable queue rechecked rather than queuing a bogus Fable-rechecks-Fable review next
  // round (id:6856 — a Fable HANDOFF previously fell to the else branch and recorded
  // fable_rechecked = false, unlike a Fable review). id:e030 consume side; keeps
  // @fable-optional-recheck idempotent regardless of which strong verdict produced it.
  const isFableRecheck = SESSION_IS_FABLE
  // hard (id:da26): Opus-apex strong-execute of one [HARD] item. Distinct checkpoint
  // label from review/handoff (which use "reviewer (...)") so the relay log reads as
  // strong-execute work; it still carries fable-standin (apex Opus work invites an
  // optional Fable recheck) via the shared standInSuffix.
  const label = unit.verdict === 'execute'
    ? 'executor (sonnet, relay-loop)'
    : unit.verdict === 'hard'
      ? `strong-execute (${STRONG_MODEL}${standInSuffix}, relay-loop)`
      : `reviewer (${STRONG_MODEL}${standInSuffix}, relay-loop)`
  // id:de69 — the item id(s) this unit worked, for the durable record (checkpoint message +
  // RELAY_STATUS + integrate event). Prefer the child's explicit report.worked_ids; fall back to
  // a review's verified_green∪reopened, then to a known dispatch-time id (injected/hard item).
  // Children sometimes return a JSON-STRING ("[]", or '["ab12"]') where the report schema
  // expects an array; spreading a string iterates its CHARACTERS, which wrote ids:["[","]"]
  // into integrate events (observed 4× in run relay-20260701-202806-14640). Coerce: array →
  // itself; a string that parses to a JSON array → that array; anything else → [] (loud "?"
  // is worse than empty here — the id suffix is telemetry, never authority).
  const asIdArray = (v) => {
    if (Array.isArray(v)) return v.filter(Boolean).map(String)
    if (typeof v === 'string') {
      try { const p = JSON.parse(v); return Array.isArray(p) ? p.filter(Boolean).map(String) : [] } catch { return [] }
    }
    return []
  }
  let workedIds = asIdArray(report.worked_ids)
  if (!workedIds.length && unit.verdict === 'review') {
    workedIds = [...new Set([...asIdArray(report.verified_green), ...asIdArray(report.reopened)])]
  }
  if (!workedIds.length && (unit.inject_item || unit.item)) workedIds = [unit.inject_item || unit.item]
  const idSuffix = workedIds.length ? ` [id:${workedIds.join(',')}]` : ''
  const result = await agent(
    `You are the serialized integrator of the relay pool. Integrate ONE completed unit, strictly in this order, for repo ${unit.repo} at ${unit.path}:

0. Release this repo's cross-session lease (id:ebfb) — the child's work is done; do this FIRST so it runs whether the merge below succeeds or aborts: ~/.claude/skills/relay/scripts/claim.sh release ${unit.repo} --run ${state.runId}  (run-scoped — a no-op if this run does not hold it).${unit.intensive ? ` Also release the exclusive resource lease (id:8d52): ~/.claude/skills/relay/scripts/claim.sh release resource:${unit.intensive} --run ${state.runId}.` : ''}
1. DETERMINISTIC clean-tree gate (id:aa93 — a foreign-dirty main checkout was silently DESTROYED 3× on 2026-06-18 when an agent "cleaned" the tree to make room): run ~/.claude/skills/relay/scripts/clean-tree-gate.sh ${unit.path}. It prints "clean" and exits 0 ONLY if the tree carries no changes; otherwise it prints "dirty <N>" + the offending porcelain lines and exits NON-ZERO. On any non-zero exit, ABORT: return merged=false with reason "main checkout dirty — a concurrent edit is present; deferring to avoid data loss (id:aa93)" plus the gate's dirty output. The integrator works on the child's WORKTREE, never the main checkout, so ANY dirty entry here is a foreign/concurrent editor's work. You must NEVER run \`git stash\`, \`git checkout --\`, \`git reset --hard\`, or \`git clean\` on ${unit.path} to make room for the merge — do NOT force-clean a foreign-dirty tree; just DEFER it.
1a. DETERMINISTIC isolation gate (id:f682/id:7612 — a spawned child ran \`git worktree add\` correctly but then wrote every edit to the target's MAIN checkout instead, observed 2026-07-14 loderite and 2026-06-30 jobAI id:c6c8): run ~/.claude/skills/relay/scripts/verify-isolation.sh ${report.worktree}. It prints "ok …" and exits 0 when the worktree is a legitimate completed unit (has its own commits and a clean tree, OR is a genuine zero-commit id:8e3e no-op review — main unmoved since dispatch); it exits NON-ZERO (2) when the worktree is dirty, or is empty AND main advanced by a non-merge commit since dispatch (the isolation-breach signature — the failure output names the offending commit(s)). On any non-zero exit, ABORT: return merged=false with reason "isolation gate failed — worktree/main-checkout isolation breach suspected; deferring to avoid merging unaudited main-checkout drift (id:7612)" plus the gate's output. This gate is OBSERVE-ONLY (never stash/reset --hard/checkout --/clean) — do NOT attempt to "fix" a failure yourself.
1b. Belt-and-suspenders (id:c3f7) — never checkpoint on a base that diverged from origin (the ai-codebench incident): run ~/.claude/skills/relay/scripts/sync-origin.sh ${unit.path}. If its output starts with "diverged", ABORT: return merged=false with reason "base diverged from origin — manual reconcile (id:c3f7)". (Output "ok"/"behind N"/"no-upstream" → proceed; discovery's live reconcile-repo.sh already fast-forwarded behind-only repos — it runs every round on BOTH the fresh-queue and the live-exec discovery path, id:9d97/7402, so a behind-only repo is always ff-merged before dispatch.)
2. git -C ${unit.path} merge --no-ff ${report.branch} -m "merge(relay): ${report.summary}"
   On conflict: git -C ${unit.path} merge --abort, return merged=false with reason (worktree stays on disk).
   The checkpoint tag's anchor (\`-c\` for step 3) is decided HERE by which of two cases the merge produced:
   • ZERO-COMMIT branch (id:8e3e — merge printed "Already up to date"; the branch tip is already an ancestor of main): the child audited its window and had nothing to change. That IS a completed unit, NOT a "duplicate dispatch" — do NOT return merged=false (a handback here leaves the audited window UNCLOSED, so discovery re-dispatches the same strong review every round; observed 3× on 2026-07-01). Capture reviewedTip = git -C ${unit.path} rev-parse ${report.branch}, then proceed to step 3 WITH the extra flag \`-c <reviewedTip>\` so the checkpoint tag anchors on the commit the child actually audited — NEVER on current main HEAD, which may contain commits that landed after dispatch and were NOT audited.
   • BRANCH WITH COMMITS (id:25aa — the merge actually created a \`--no-ff\` merge commit; the branch carried its own work, e.g. a REVIEW_ME prune + a RELAY_LOG commit): the run's OWN merged commits MUST fall INSIDE the audited window, so the checkpoint MUST anchor on the POST-MERGE tip. Do this by passing NO \`-c\` at step 3 (the default: ckpt-tag appends its RELAY_LOG commit on top of the just-created merge commit and tags THAT — the post-merge tip, which contains the merge). Do NOT carry over the zero-commit rule here: passing \`-c <reviewedTip>\` (the branch tip) when the branch carried commits anchors the tag BEHIND the merge, leaving the run's own merged commits permanently OUTSIDE the audited window — classify-repo then re-dispatches a "substantive unaudited commits" review forever (the id:25aa bug; the carries-commits COMPLEMENT of id:8e3e). The id:8e3e "NEVER tag main HEAD" caution applies ONLY to the zero-commit case (where main HEAD may hold unaudited post-dispatch commits); when the merge just happened, the post-merge tip IS the audited boundary.
2b. DERIVE the CHANGELOG entry (id:b8fa) — the repo's human-readable record of this close, folded from the SAME state you already have (report.summary + the worked ids; NO new field — meeting 2026-07-17-1541 D2). Run:
     ~/.claude/skills/relay/scripts/changelog-append.sh ${unit.path} --summary "${report.summary}"${workedIds.length ? ' --ids "' + workedIds.join(',') + '"' : ''}
   This is a NO-OP for a repo without a CHANGELOG.md (opt-in; it exits 0 and writes nothing), so the step is safe for EVERY repo — a repo only participates once its CHANGELOG.md has been deliberately bootstrapped (dotclaude-skills date-buckets now; each semver repo when id:e647 ships and creates its file, release-bucketed). If (and only if) the helper actually modified CHANGELOG.md — check with: git -C ${unit.path} status --porcelain -- CHANGELOG.md is non-empty — commit ONLY that exact path so the tree stays clean for retire: git -C ${unit.path} add -- CHANGELOG.md then git -C ${unit.path} commit -q -m "docs(changelog): ${report.summary}". NEVER stage anything else (scoped-staging invariant id:debf — no git add -A/./-u/--all). Version-less repos (no manifest, e.g. dotclaude-skills) date-bucket with no --version; a semver bump (id:e647) would pass --version, but until that ships there is none to pass, so omit it.
3. ~/.claude/skills/relay/scripts/ckpt-tag.sh ${unit.path} -m "${report.summary}${idSuffix}" -l "${label}"
   (Append \`-c <reviewedTip>\` ONLY in the ZERO-COMMIT "Already up to date" case per step 2; for a branch that carried commits, pass NO \`-c\` so the tag lands on the post-merge tip.)
   It prints the new tag name — capture it as ckptTag. (The trailing [id:…] tags the durable RELAY_LOG checkpoint with the worked item id(s), id:de69.)
4. ~/.claude/skills/git-diary-workflow/git-lock-push.sh --ff-only ${unit.path}
   pushStatus = "pushed" on success, otherwise the error summary.
5. ~/.claude/skills/relay/scripts/worktree-retire.sh ${unit.path} ${report.worktree} ${report.branch} --expect-merged
   (FORCE-FREE retirement — id:373e. The merge+tag+push above already integrated the committed branch work, so the branch is merged; \`--expect-merged\` tells the helper that a \`git branch -d\` refusal is an anomaly to surface, not to park. The helper runs \`git worktree remove\` WITHOUT \`--force\` and \`git branch -d\` WITHOUT \`-D\` — you must NEVER run \`--force\`, \`git branch -D\`, \`git stash\`, \`git clean\`, or \`git reset --hard\` yourself (they are destructive and the executor's clean-worktree exit gate in the executor contract means the tree is normally already clean; gitignored build residue like a uv.lock does NOT block a force-free remove). If the child nonetheless left the worktree DIRTY (uncommitted non-ignored files), the helper SURFACES it and LEAVES the worktree+branch on disk for a supervised reconcile — that is the correct, safe outcome; do NOT force-clean to "finish the job". Capture the helper's stdout line into your report if it is non-empty (id:d187 orphaning is now surfaced, not silent).)
   DESTRUCTIVE-CLEANUP SCOPE (id:6e02): you may remove ONLY the two artifacts named above — ${report.worktree} and ${report.branch}, this unit's own. NEVER delete, prune, or "tidy up" any OTHER relay/* branch or worktree, no matter how redundant it looks: a zero-commit branch whose tip is an ancestor of main is NOT proof of an already-integrated leftover — it is exactly what a LIVE parallel child's freshly-created worktree looks like, and the repo lease was already released in step 0 so a foreign child may legitimately hold one (on 2026-07-01 an integrator swept a parallel review child's branch+worktree mid-run on this inference). The same scope applies on EVERY abort/handback path: return merged=false and leave ALL worktrees and branches on disk — including this unit's own.
6. Update ~/.config/relay/relay.toml for [repos.${unit.repo}] via the flock'd single-writer (id:ebfb step 2) — for EACH field run \`~/.claude/skills/relay/scripts/relay-state-write.sh toml-set ${unit.repo} <key> <value>\` (value VERBATIM: quote strings e.g. '"<tag>"', bare for bool e.g. false; NEVER hand-edit relay.toml): set last_ckpt to the new tag${unit.verdict === 'review' ? ", set last_review to today's date (ISO)" : ''}${unit.verdict === 'handoff' ? ", set handoff_date to today's date (ISO) and status to \"handed-off\"" : ', set status to "active"'}. Change ONLY this repo's block.${isStrong ? `
6b. STRONG checkpoint — this is a ${unit.verdict} unit produced by the strong model (${STRONG_MODEL}). ${isFableRecheck ? `This session's strong tier is REAL Fable, so this self-produced strong checkpoint (${unit.verdict}) has nothing pending — it IS (or satisfies) the optional Fable recheck (id:e030 consume side). Record the durable Fable-bonus-recheck queue entry for [repos.${unit.repo}]: set last_strong_ckpt = "<the new tag>", strong_model = "${STRONG_MODEL}", and fable_rechecked = "<today's date, ISO>" (the recheck just happened — mark it done, do NOT set false).` : `Record the durable Fable-bonus-recheck queue entry for [repos.${unit.repo}]: set last_strong_ckpt = "<the new tag>", strong_model = "${STRONG_MODEL}", and fable_rechecked = false (an Opus-standin/strong checkpoint that still invites an optional Fable recheck).`} These keys survive a LATER executor (sonnet) checkpoint that overwrites last_ckpt — so the pending optional Fable recheck stays visible even when masked. Write all three via the same flock'd relay-state-write.sh toml-set helper (overwrite if present; fable_rechecked is a BARE value: false, or '"<ISO date>"' when rechecked). Change ONLY this repo's block.` : `
6b. EXECUTOR checkpoint — this is an execute unit (sonnet). Do NOT touch last_strong_ckpt, strong_model, or fable_rechecked: an executor checkpoint must never clear the pending Fable-bonus-recheck queue (that is exactly the masking bug id:e030 fixes). Leave those keys untouched.`}
7. L2 push-seed inputs (id:c855) — compute these LAST, AFTER steps 1-6 so they reflect the fully-settled post-integrate state on main (the toml block, removed worktree dir, and pushed HEAD all feed the signature):
   a. postSig — recompute this repo's discovery signature so next round's prelude can match it: echo the one-repo object and pipe it to discover-sig.sh, then read the "sig" field:
        printf '%s' '{"repos":[{"repo":"${unit.repo}","path":"${unit.path}"}],"liveClaims":[]}' | ~/.claude/skills/relay/scripts/discover-sig.sh
      It prints one JSON line {"repo":...,"sig":"<hex or empty>"}. Set postSig = that sig verbatim (may be "" — a fail-open sentinel; pass it through, do NOT invent a hash).
   b. openRoutine — count of unticked routine items: git -C ${unit.path} grep -c -E '^- \\[ \\].*\\[ROUTINE\\]' HEAD -- ROADMAP.md 2>/dev/null (0 if the file/marker is absent; a plain count, not a list).
   c. openHard — count of unticked HARD items: git -C ${unit.path} grep -c -E '^- \\[ \\].*\\[HARD' HEAD -- ROADMAP.md 2>/dev/null (0 if absent). Count ALL [HARD items (gated or not) — the supervisor only push-seeds 'idle' when BOTH counts are 0, so over-counting here is safe (it just declines to cache).
8. Return merged=true, ckptTag, pushStatus, ts (current ISO timestamp), postSig, openRoutine, openHard.

SCOPED-STAGING INVARIANT (id:debf — never scoop a concurrent ledger edit). You integrate the child's work EXCLUSIVELY via the committed-branch \`git merge --no-ff\` in step 2 — that brings in ONLY the commits already on \`${report.branch}\`. You must NEVER stage the main checkout broadly: do NOT run \`git add -A\`, \`git add .\`, \`git add -u\`, or \`git add --all\` anywhere. A \`/meeting\` or \`/relay human\` session may be writing a ledger file (TODO/ROADMAP/REVIEW_ME) in the main checkout concurrently (those writes are flock-protected, NOT lease-protected — id:c144); a broad \`git add\` would capture that uncommitted foreign edit into this pool checkpoint commit (the scoop window, id:3558). The step-1 clean-tree gate already DEFERS on any foreign-dirty tree; the merge stages nothing from the working tree, so a concurrent ledger edit is never scooped. If you ever need to stage a specific file (e.g. the id:bae5 uv.lock relock), stage it by exact path (\`git add -- <path>\`), never broadly.

Never push any other repo, never force-push, never resolve conflicts yourself.`,
    { label: `integrate:${unit.repo}`, phase: 'Integrate', schema: INTEGRATE_SCHEMA, model: 'sonnet' }
  )
  if (result && result.merged) {
    if (result.ts) state.ts = result.ts
    state.completed.push({ repo: unit.repo, mode: unit.verdict, ckptTag: result.ckptTag || '?', pushStatus: result.pushStatus || '?', substantive: unitIsSubstantive(unit.verdict, report), workedIds })  // workedIds id:de69
    pushEvent('integrate', { repo: unit.repo, mode: unit.verdict, ckpt: result.ckptTag || '?', push: result.pushStatus || '?', ids: workedIds })  // id:c8b6 + worked ids id:de69
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
    state.handbacks.push({ repo: unit.repo, reason, worktreePath: report.worktree })
    pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason })  // id:c8b6
    emittedHandbackEvents.push({ repo: unit.repo, reason })  // id:1735 — invariant backstop
  }
  scheduleStatusWrite(state)
}

// id:3801 — Durable handback follow-up. When a child hands back (contract_met=false) with a
// classified route, durably record it in the repo's MAIN-checkout ROADMAP.md so the pool stops
// re-dispatching an un-doable item: decision-gate/human → re-tag the parent to the
// classifier-excluded "[HARD — decision gate]"; hard-split → gate the parent + append the
// proposed seams as pickable units. The Workflow sandbox has NO shell/fs (process.* / new Date()
// crash the pool — id 2026-06-15), so a tiny Haiku agent runs handback-followup.py, which owns
// all idempotency + the flock'd md-merge write + the --ff-only commit/push. Fire-and-forget,
// non-fatal (a follow-up failure must never crash the integrator); the item simply stays
// surfaced in RELAY_STATUS as before. The gate is a CLAIM the next review re-checks (anti-gaming).
function durableHandbackFollowup(unit, report) {
  const route = report.route
  if (!route || route === 'none' || !report.handback_item) return  // nothing durable to do
  const esc = s => String(s == null ? '' : s).replace(/'/g, "'\\''")
  const splitJson = JSON.stringify(Array.isArray(report.proposed_split) ? report.proposed_split : [])
  // Short, single-line gate note (never inline the verbose handback into a ROADMAP line).
  const gateReason = (report.gate_reason || String(report.handback || '').slice(0, 200)).replace(/\s+/g, ' ').trim()
  agent(
    `Run exactly this command and report whether it exited 0 (durable handback follow-up for ${unit.repo}, id:3801 — records the handback in ROADMAP.md so the pool stops re-dispatching an un-doable item; the script owns idempotency + commit/push):
python3 ~/.claude/skills/relay/scripts/handback-followup.py '${esc(unit.path)}' --parent-id '${esc(report.handback_item)}' --route '${esc(route)}' --gate-reason '${esc(gateReason)}' --split-json '${esc(splitJson)}' --run-id '${esc(state.runId)}'
Report the exit code.`,
    { label: `handback-followup:${unit.repo}`, phase: 'Logging', model: 'haiku' }
  ).catch(err => log(`relay-loop: durable handback follow-up failed for ${unit.repo} (non-fatal): ${err}`))
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
    { label: `gaming-log:${repo}`, phase: 'Logging', model: 'haiku' }
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
    `Run exactly these two commands and report whether they exited 0 (the relay child for ${unit.repo} has settled; free its cross-session lease so other sessions aren't blocked for the TTL, and refresh the run-liveness heartbeat — id:e149 — so the outage watchdog knows the pool made progress this unit):
  ~/.claude/skills/relay/scripts/claim.sh release ${unit.repo} --run ${state.runId}${resourceRelease}
  ~/.claude/skills/relay/scripts/heartbeat.sh beat ${state.runId}
The release is run-scoped (a no-op if this run no longer holds the claim) and idempotent; the beat is best-effort. Report the exit codes.`,
    { label: `release:${unit.repo}`, phase: 'Leases', model: 'haiku' }
  ).catch(err => log(`relay-loop: per-unit lease release/beat failed for ${unit.repo} (non-fatal; TTL backstops): ${err}`))
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
  // id:5ac6 — fail-closed INTENSIVE pre-dispatch assertion: if a unit carries an `intensive`
  // flag (set by classify-verdict.sh / shard from gather's top_intensive) AND ALLOW_INTENSIVE
  // is false, NEVER spawn the child — skip loudly instead (the OOM-kill invariant).
  // The INTENSIVE partition above (id:8d52) already routes intensive units to intensiveUnits or
  // intensiveDeferred; this assertion is a final-layer backstop for any unit that reaches
  // runUnit() with intensive set despite the partition (e.g. a mid-round injected unit with
  // intensive set, or a future code path that bypasses the partition). Fail-closed: it is
  // better to loudly skip a unit than to silently OOM-dispatch (id:oom-local-model-session-kills).
  if (unit.intensive && !ALLOW_INTENSIVE) {
    log(`relay-loop: id:5ac6 INTENSIVE fail-closed — unit ${unit.repo}(${unit.verdict}, intensive=${unit.intensive}) reached runUnit without --allow-intensive; SKIP + surface LOUDLY. This is a dispatch invariant violation (the INTENSIVE partition should have caught this). Use --intensive to enable.`)
    state.handbacks.push({
      repo: unit.repo,
      reason: `INTENSIVE fail-closed (id:5ac6): unit carries intensive=${unit.intensive} but ALLOW_INTENSIVE=false — skipped to prevent OOM dispatch; use --intensive to enable`,
      worktreePath: '-',
    })
    scheduleStatusWrite(state)
    return
  }
  unitsDispatched++
  totalDispatched++
  state.inFlight.push({ repo: unit.repo, mode: unit.verdict, agentId: `unit-${unitsDispatched}` })
  pushEvent('dispatch', { repo: unit.repo, mode: unit.verdict, tier, round, sig: unit.sig || '' })  // id:c8b6
  log(`relay-loop: dispatch ${unit.verdict} → ${unit.repo} (tier=${tier})`)
  // Tier dispatch (D4): review/handoff get the STRONG_TIER model. Execute agents are
  // pinned to Sonnet; STRONG_TIER applies no model override to them.
  // id:de69 (a) — if the worked item id is ALREADY known at dispatch (an injected unit's
  // --item, or a hard unit whose classifier surfaced the bounded item), append it to the
  // /workflows label so the live pane reads `execute:zkm-stt id:09a3`. plain execute/review
  // pick the item inside the child, so their id is filled in post-run via report.worked_ids.
  const knownItem = unit.inject_item || unit.item || ''
  const opts = { label: `${unit.verdict}:${unit.repo}${knownItem ? ` id:${knownItem}` : ''}`, phase: unitPhase(unit.verdict), schema: REPORT_SCHEMA }
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
  // CONTAINMENT (id:efaf) — a single integration failure must NEVER crash the whole pool.
  // integrate() has no try/catch around its `await agent(integrator, {schema: INTEGRATE_SCHEMA})`,
  // so an integrator agent whose output fails schema validation after retries makes agent()
  // throw → integrate() rejects. Without this .catch the raw rejecting promise lands in `debts`,
  // and the end-of-round `await Promise.all(debts)` rejects → the ENTIRE workflow dies, STRANDING
  // every other in-flight worktree (observed 2026-07-07: one integrate throw stranded ~10 units
  // of a 27-min run — "Error at integrate", agents_error:0 because a schema-validation failure is
  // not an agent runtime error). Contain per unit: record a RECOVERABLE handback (worktree held on
  // disk for /relay reconcile) and surface it LOUDLY — never swallow (the error text rides the
  // reason + event), never cascade. The per-repo integrationChains link is already error-isolated
  // (enqueueIntegration line ~653); this closes the one un-contained path, the raw `debts` promise.
  debts.push(
    enqueueIntegration(unit.repo, () => integrate(unit, report)).catch((err) => {
      const reason = `integrator threw (contained id:efaf): ${err && err.message ? err.message : String(err)} — worktree preserved; recover via /relay reconcile`
      state.handbacks.push({ repo: unit.repo, reason, worktreePath: (report && report.worktree) || worktreePathFor(unit) })
      pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason })
      emittedHandbackEvents.push({ repo: unit.repo, reason })  // id:1735 — invariant backstop
      scheduleStatusWrite(state)
    })
  )
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
canonical ABSOLUTE path (default $HOME/src/<repo>, OR the "# path:" override in that repo's block in
~/.config/relay/relay.toml — expand a leading ~ to $HOME, NEVER emit a literal ~) and return one
unit object with these exact fields:
{ injected:true, inject_token:<token>, verdict:(<verdict> or "execute"), repo:<repo>,
path:<resolved absolute path>, reason:"user-injected high-priority task (mid-round, id:6e9d)",
inject_item:(<item> or ""), inject_prompt:(<prompt> or ""), income:false, standin:false,
hasRoutine:false, openHard:false, strongRecheckPending:false, lastCkpt:"" }.
If inject.sh take emits NOTHING, return units:[]. Do not invent units; only echo what take emitted.`,
    { label: 'inject-take', phase: 'Support', schema: INJECT_TAKE_SCHEMA, model: 'haiku' }
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
// id:d58f — substantive = NEW completions this round that made real backlog progress
// (execute/hard/handoff checkpoints + reviews that reopened/surfaced-routine/flagged). A
// confirming-only review is produced-but-not-substantive; the drain detector keys on this so a
// quiescent fleet (only re-confirming reviews) winds down instead of spinning to MAX_ROUNDS.
const substantive = state.completed.slice(completedBefore).filter(c => c.substantive).length
return { actionable: actionable.length + intensiveRan, produced, substantive, surfaced: discovery.surfaced.length }
}
// ── end runRound ──

// stopHeartbeat (id:e149): release this run's liveness marker on a CLEAN shutdown so the
// outage watchdog (id:98f0) + auto-reconcile (id:7809) never treat a deliberate end as a
// death. Called on every exit path. Best-effort — the TTL backstop + the conservative
// reconcile classifier mean a missed stop only ever causes a benign false "dead" (a watchdog
// nudge + a no-op safe-reconcile pass), never data loss. No-op before a runId exists.
async function beatHeartbeat() {
  if (!state.runId) return
  try {
    await agent(
      `Run exactly this command and report whether it exited 0 (refresh the relay run-liveness heartbeat so the outage watchdog/auto-reconcile know this pool is alive): ~/.claude/skills/relay/scripts/heartbeat.sh beat ${state.runId}`,
      { label: 'heartbeat-beat', phase: 'Support', model: 'haiku' }
    )
  } catch (_) { /* non-fatal — TTL backstop */ }
}

async function stopHeartbeat() {
  if (!state.runId) return
  try {
    await agent(
      `Run exactly this command and report whether it exited 0 (clean relay-loop shutdown — release the run heartbeat so the watchdog/auto-reconcile don't read this clean stop as a death): ~/.claude/skills/relay/scripts/heartbeat.sh stop ${state.runId}`,
      { label: 'heartbeat-stop', phase: 'Support', model: 'haiku' }
    )
  } catch (_) { /* non-fatal */ }
}

// ── Auto-reconcile-on-restart (id:7809) ──
// If a PRIOR relay run DIED without a clean stop (a stale run-heartbeat, id:e149), dispose its
// SAFE (ledger-only, clean, non-diverged) parked orphans automatically and SURFACE the
// judgment ones into REVIEW_ME.md — BEFORE starting fresh work, so a restart neither
// double-works nor skips a dead run's leftovers. The classifier is conservative (never a
// weaker bar than a human /relay review). Runs ONCE at startup, gated on a stale heartbeat so a
// clean start does nothing; this run hasn't beaten its own marker yet (first beat is in round-1
// prelude), so dead-runs reports only PRIOR runs. Best-effort — the human /relay reconcile is
// always the backstop, so a failure here never blocks the pool.
try {
  await agent(
    `Auto-reconcile-on-restart check (relay id:7809), unattended — NEVER prompt. Run exactly:
  ~/.claude/skills/relay/scripts/heartbeat.sh dead-runs --prefix 'relay-*'
If it prints NOTHING, no prior DISPATCH-LOOP relay run died — do nothing else and report "no dead run, skipped". If it prints one or more JSON lines (a prior run died without a clean heartbeat stop), then:
  1. Run: ~/.claude/skills/relay/scripts/relay-reconcile.sh --all --auto
  2. THEN, for EACH distinct "runId" value printed by the dead-runs command above, immediately archive THAT SPECIFIC run's marker (id:7725 — observed-death reap, do not wait on the TTL-only sweep below):
       ~/.claude/skills/relay/scripts/heartbeat.sh reap-run '<that runId>'
  3. Finally run the TTL backstop sweep (catches any OTHER present-but-stale marker this restart did not individually observe/reconcile):
       ~/.claude/skills/relay/scripts/heartbeat.sh reap --prefix 'relay-*'
Report all three steps' output verbatim.
(Step 1 auto-integrates only ledger-only/clean orphans and surfaces everything else into REVIEW_ME.md; step 2 immediately archives each JUST-reconciled dead run's own marker by exact runId so the watchdog (id:98f0) cannot re-alarm on a crash already handled this restart (id:7725 — the old design only relied on the stale-only sweep, which under-TTL markers slipped through, ~1h-late false alarm observed 2026-07-07); step 3 is the pure TTL backstop for a marker that was NOT in this restart's dead-runs list (impossible in practice, but keeps the two liveness paths independent). The --prefix 'relay-*' is REQUIRED on BOTH the dead-runs detection AND the reap in step 3 and must not be dropped — it scopes both to this dispatch loop's own runId namespace so a dead INDEPENDENT discovery-producer heartbeat marker (id:54fc, a separate liveness domain that ages past heartbeat's 3600s default TTL) never falsely trips this per-restart --all reconcile nor gets archived by the reap. Un-scoped dead-runs would fire relay-reconcile --all --auto on EVERY restart while that producer marker is stale.) Take NO other action.`,
    { label: 'auto-reconcile-restart', phase: 'Support', model: 'haiku' }
  )
} catch (_) { /* non-fatal: the human /relay reconcile is always available */ }

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
      await stopHeartbeat()  // id:e149 — round-1 discovery failed but the prelude may have beaten; release it
      return { error: 'discovery failed', runId: state.runId, statusPath: RELAY_STATUS_PATH, completed: state.completed, handbacks: [], queuedRemaining: state.queued, quotaStopped, stopReason }
    }
    log('relay-loop: discovery failed mid-run — stopping after completed rounds')
    break
  }
  // id:c012 — operator STOP sentinel fired inside this round's prelude: stopReason is already
  // set to "user-stop"; the round drained without dispatching. Break the outer loop cleanly.
  if (r.userStop) { log(`relay-loop: graceful stop after round ${round} (operator STOP sentinel)`); break }
  // id:c012 — launch-time round cap (--once = 1 round; --after N = N rounds). The cap counts
  // COMPLETED rounds; once `round` reaches it, wind down voluntarily (drain already done above).
  if (STOP_AFTER_ROUNDS > 0 && round >= STOP_AFTER_ROUNDS) {
    // id:0175 — don't mask a REAL stop reason set earlier in this same round (e.g. a quota
    // gate that fired in the prelude): only claim 'user-stop' when nothing else stopped us.
    if (!stopReason) stopReason = 'user-stop'
    log(`relay-loop: graceful stop — launch round cap reached (${round}/${STOP_AFTER_ROUNDS}, --once/--after)`)
    break
  }
  // id:4ca8 — a round that produced nothing SUBSTANTIVE but SURFACED >=1 suppressed/gated repo
  // is BLOCKED, not empty — id:1735's original "stale discovery snapshot" hypothesis for this
  // symptom was FALSIFIED (discovery was fresh + correct); the real gap was that nothing
  // distinguished "surfaced" from "genuinely nothing left" here. Stop DECISIVELY on the first
  // such round (no need to wait for a 2nd confirming round — the surfaced count already tells
  // us why) with a distinct stopReason, instead of silently drifting into the generic
  // 2-dry-rounds "backlog drained" path below while real (blocked) work still sits in
  // ROADMAP.md.
  if (isBlockedRound(r)) {
    const drain = classifyDrainBacklog(state.surfaced)
    stopReason = 'blocked-pending-human'
    log(`relay-loop: id:4ca8 stopping — round ${round} surfaced ${r.surfaced} blocked repo(s), 0 substantive progress: ${drain.summary}`)
    if (drain.suppressed.length) log(`relay-loop: ${drain.suppressed.length} repo(s) have parked partial work suppressing re-dispatch — take them to /relay reconcile.`)
    if (drain.gated.length) log(`relay-loop: ${drain.gated.length} repo(s) have gated [HARD] work the pool cannot auto-do — take them to /relay human --all or /meeting --cross.`)
    break
  }
  // id:2d20 + id:d58f — a round makes no progress when it produced nothing SUBSTANTIVE, not
  // merely when it integrated nothing. id:2d20 counted any integrated checkpoint as progress;
  // id:d58f tightens that: a CONFIRMING-only review (verified-green, reopened/added nothing) is
  // produced-but-not-substantive, so a fleet whose only remaining activity is re-confirming
  // already-reviewed repos (notably a concurrently-churning cwd repo) counts as dry and winds
  // down after 2 such rounds instead of spinning to the MAX_ROUNDS seatbelt. An all-handback
  // round (gated/too-large HARD) and a dispatched-but-confirming-only round both count here.
  // id:4ca8 — now gated on isDryRound (substantive===0 AND surfaced===0): the isBlockedRound
  // check above already intercepted (and broke on) any substantive===0-but-surfaced>0 round, so
  // this branch is only ever reached when surfaced===0 too — a genuinely empty round.
  if (isDryRound(r)) {
    dry++
    const why = r.actionable === 0
      ? 'no actionable units'
      : ((r.produced || 0) > 0
          ? `${r.actionable} dispatched, ${r.produced} integrated but none substantive (confirming-only reviews)`
          : `${r.actionable} dispatched but 0 integrated (all handed back)`)
    log(`relay-loop: round ${round} — no substantive progress: ${why} (dry ${dry}/2)`)
    if (dry >= 2) {
      const drain = classifyDrainBacklog(state.surfaced)
      stopReason = stopReason || 'drained'  // id:4ca8 — always set, never left null on a drain exit
      log(`relay-loop: backlog drained (2 consecutive no-substantive-progress rounds) — done. Remaining: ${drain.summary}`)
      if (drain.gated.length) log(`relay-loop: ${drain.gated.length} repo(s) have gated [HARD] work the pool cannot auto-do — take them to /relay human --all or /meeting --cross.`)
      break
    }
  } else {
    dry = 0
  }
}

await statusTail  // id:cb50 — flush the queued (off-critical-path) RELAY_STATUS writes so the final state is durable before the run returns
await stopHeartbeat()  // id:e149 — clean shutdown: release the run-liveness marker (no stale marker ⇒ no false watchdog/reconcile trigger)
// id:1735 — the loud invariant backstop: every pushEvent('handback', …) emitted this run must
// have a matching entry in the persistent state.handbacks accumulator. This is the assertion
// that catches a regression of the original bug (a handback event recorded as having happened,
// but the returned summary has no matching entry for it) — FAIL LOUDLY rather than silently
// returning the (possibly incomplete) list.
const handbackInvariant = assertHandbackInvariant(emittedHandbackEvents, state.handbacks)
if (!handbackInvariant.ok) {
  log(`relay-loop: INVARIANT VIOLATED (id:1735) — ${handbackInvariant.violations.length} handback event(s) emitted this run have NO corresponding entry in state.handbacks: ${JSON.stringify(handbackInvariant.violations)}`)
}
const handbacks = reconcileHandbacks(state.handbacks)
// id:1432 — LOUD exit-summary surfacing: any repo+verdict that handed back >=2× this run is a
// bug signal (a looping false/stale verdict). Log it prominently so an --afk operator sees it.
const repeatHandbacks = handbackAlerts(handbackTracker, 2)
log(`relay-loop: done — ${round} round(s), ${state.completed.length} integrated, ${handbacks.length} HANDBACKs, quotaStopped=${quotaStopped}`)
if (repeatHandbacks.length) {
  log(`relay-loop: id:1432 ⚠️ REPEAT-HANDBACK ALERT — ${repeatHandbacks.length} repo/verdict(s) handed back >=2× this run (bug signal, investigate): ${repeatHandbacks.map(a => `${a.repo}(${a.verdict})×${a.count}`).join(', ')}`)
}

return {
  runId: state.runId,
  statusPath: RELAY_STATUS_PATH,
  completed: state.completed,
  handbacks,
  handbackInvariantViolations: handbackInvariant.violations,  // id:1735 — [] unless the invariant tripped
  repeatHandbacks,  // id:1432 — [{repo, verdict, count, lastReason}] for >=2× handbacks this run
  queuedRemaining: state.queued,
  quotaStopped,
  stopReason,  // id:8c35 — category: null | "quota-cache-unreadable" | "quota-extrapolated-stop[:<bucket>]" (id:0175/82e3) | "quota-exhausted:<bucket>" | "budget" | "drained" | "max-rounds" | "user-stop" (id:c012)
  rounds: round,
}
