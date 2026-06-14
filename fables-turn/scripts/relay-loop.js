export const meta = {
  name: 'relay-loop',
  description: 'Priority-mixed 5-wide autonomous relay pool — serialized integrator, quota-guarded, STRONG_TIER-aware',
  phases: [
    { title: 'Discover', detail: 'classify confirmed repos into execute/review/handoff/idle units' },
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

// STRONG_TIER: model override for review and handoff agents.
// Execute agents (Sonnet) never receive this override — only review and handoff agents do.
// Values: 'fable' (default) | 'opus'
// Passed via args.STRONG_TIER from the front-door SKILL.md (set by STRONG_TIER env var or --strong-tier flag).
const STRONG_TIER = A.STRONG_TIER || 'fable'
const STRONG_MODEL = STRONG_TIER === 'opus' ? 'claude-opus-4-8' : 'claude-fable-5'

// RELAY_STATUS_PATH: output file for cross-repo rollup. Overridable for testing.
const RELAY_STATUS_PATH = A.RELAY_STATUS_PATH || '~/.config/fables-turn/RELAY_STATUS.md'

// INTERACTIVE: pass-through of the front door's --interactive flag (default false).
// The Workflow itself NEVER prompts the user (unattended invariant, meeting D2 —
// enforced by tests/test_fables_front_door.sh grepping this file for the question tool);
// when true, dispatch may surface choices in RELAY_STATUS.md instead of silently skipping.
const INTERACTIVE = !!A.interactive

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

// D3: pool of distinct repos, one unit per repo. Default 5; override via args.POOL_WIDTH.
// NOTE: the Workflow harness independently caps concurrent agents at min(16, cpu_cores-2),
// so a POOL_WIDTH above that ceiling just queues — no benefit (e.g. 6 on an 8-core box).
const POOL_WIDTH = A.POOL_WIDTH || 5
// Agent-count seatbelt for one run (quota-stop.sh hard-caps at 200 independently).
const MAX_UNITS = A.MAX_UNITS || 20
// D3 policy invariant: Sonnet execute fills slots first; unreviewed-executor review
// ranks above fresh handoff (keeps the anti-gaming window short). Lower = sooner.
const PRIORITY = { execute: 0, review: 1, handoff: 2 }

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
//     reviewMe:  [{repo, count, path}] }
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

  const quota = state.quota && state.quota.length
    ? state.quota.map(r => `- ${r.bucket}  remaining=${r.pctRemaining}%${r.resetTime ? '  reset=' + r.resetTime : ''}`).join('\n')
    : '_(unknown)_'

  const reviewMe = state.reviewMe && state.reviewMe.length
    ? state.reviewMe.map(r => `- ${r.repo}  open=${r.count}  path=${r.path}`).join('\n')
    : '_(none)_'

  return [
    header,
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
    '## Quota remaining',
    quota,
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
  log(`RELAY_STATUS updated: in-flight=${inFlightCount} completed=${completedCount} blocked=${blockedCount} → ${path}`)
  await agent(
    `Write the following content verbatim to RELAY_STATUS.md. The target path is "${path}".

FIRST resolve it to a real absolute path with the shell, e.g.
  target=$(python3 -c "import os;print(os.path.expanduser('${path}'))")
then create parents with mkdir -p "$(dirname "$target")" and write the content to "$target".

CRITICAL (id:c34a): NEVER create a file or directory whose name literally contains "$HOME", "\${HOME}", "~", or a leading "$" — that means expansion failed and leaks a junk dir into the cwd. The final resolved path MUST begin with "/". If you cannot resolve an absolute path beginning with "/", abort WITHOUT writing anything. Do not truncate or reformat.

Content:
${content}`,
    { label: 'write-relay-status', phase: 'Integrate', model: 'haiku' }
  )
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
          verdict: { enum: ['execute', 'review', 'handoff', 'idle'] },
          reason: { type: 'string' },
          lastCkpt: { type: 'string' },
          income: { type: 'boolean' },
          // hasRoutine: ROADMAP.md has >=1 unticked [ROUTINE] item, reported
          // INDEPENDENT of verdict — lets --fable-down demote a review repo that
          // also has open executor work instead of deferring it wholesale.
          hasRoutine: { type: 'boolean' },
          // standin: latest fable-ckpt-* tag message contains the literal `fable-standin`
          // token — the repo's last relay checkpoint was Opus standing in for Fable, so
          // it still needs an independent Fable re-review. Drives the standInRank tiebreaker.
          standin: { type: 'boolean' },
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
  },
}

// ── Serialized integrator (D5/D6: one integration at a time, never two concurrent
// pushes; intentionally NOT parallel() — a promise chain is the serializer) ──

let integrationChain = Promise.resolve()
function enqueueIntegration(fn) {
  const run = integrationChain.then(fn, fn)
  integrationChain = run.then(() => {}, () => {})
  return run
}

// ── Self-feeding loop (user directive 2026-06-13): one launch drains the backlog.
// runRound() does one re-discover → dispatch wave → drain. The outer loop at the bottom
// repeats it, so executes→reviews→executes cycle via a FRESH discovery each round, until
// (a) the quota cap stops it, (b) two consecutive discoveries find no actionable work
// (drained), or (c) the MAX_ROUNDS seatbelt trips. `state` and `quotaStopped` persist
// across rounds (accumulators); per-round vars (queue/debts/unitsDispatched/roundCapHit)
// are local to runRound and reset each round.
const state = { runId: '', ts: '', inFlight: [], completed: [], queued: [], blocked: [], quota: [], reviewMe: [] }
let quotaStopped = false
const MAX_ROUNDS = A.MAX_ROUNDS || 30

async function runRound() {
// ── Phase 1: Discover ──

phase('Discover')

const discovery = await agent(
  `You are the discovery/classifier step of the fables-turn autonomous relay pool.

Read ~/.config/fables-turn/relay.toml. Consider ONLY repos with classification = "own".
Repo path default: ~/src/<name>; honor any "# path:" comment override in the repo's
relay.toml block. For each repo, classify into exactly one verdict:

- "review": commits exist after the last fable-ckpt-* tag (run: git -C <path> tag -l 'fable-ckpt-*' | sort | tail -1, then git -C <path> log <tag>..HEAD --oneline). Unaudited work always wins over other verdicts.
- "execute": no unaudited commits, and ROADMAP.md has >=1 unticked "- [ ]" item tagged [ROUTINE].
- "handoff": no unaudited commits, and ROADMAP.md is missing/has no roadmap marker, OR every item is ticked while untracked new work exists.
- "idle": none of the above.

A repo with a DIRTY main working tree (git -C <path> status --porcelain non-empty, ignoring entries already declared acceptable in relay.toml comments) is NOT dispatched: put it in "surfaced" with the reason instead of "units". Repos with no fable-ckpt-* tag and no handoff_date are handoff candidates, not review.
${INTERACTIVE ? 'Interactive run: include marginal/ambiguous repos in "surfaced" with a one-line question each.' : 'Unattended run: never include questions; surface ambiguous repos with a factual reason only.'}

Also produce:
- runId: "relay-" + current date-time as YYYYMMDD-HHMM (from the date command)
- ts: current ISO 8601 timestamp
- lastCkpt per repo (the tag name, or "" if none)
- income per repo: true iff the repo's relay.toml block has income = true
- hasRoutine per repo: true iff ROADMAP.md has >=1 unticked "- [ ]" item tagged [ROUTINE], INDEPENDENT of the verdict. A repo classified "review" (unaudited commits) that ALSO has open [ROUTINE] work must report hasRoutine=true — this lets the --fable-down path keep executors busy on routine work in repos whose review must wait for the next strong turn.
- standin per repo: true iff the repo's LATEST fable-ckpt-* tag message contains the literal token "fable-standin". Detect: T=$(git -C <path> tag -l 'fable-ckpt-*' | sort | tail -1); then git -C <path> tag -l --format='%(contents)' "$T" | grep -q fable-standin && true || false. This means the last relay checkpoint was produced by Opus standing in for Fable (Fable outage), so the repo still needs an independent Fable re-review and its specs are provisional. Report false when there is no fable-ckpt tag.

Return every own repo exactly once across units (verdict idle included) and surfaced.`,
  { label: 'discover', phase: 'Discover', schema: DISCOVER_SCHEMA }
)

if (!discovery) {
  log('relay-loop: discovery agent failed this round')
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
if (SESSION_IS_FABLE && !FABLE_DOWN) {
  let elevated = 0
  for (const u of discovery.units) {
    if (u.standin && (u.verdict === 'execute' || u.verdict === 'idle')) {
      u.reason = `standin re-review (latest fable-ckpt carries fable-standin — Opus stood in for Fable; independent audit pending). Prior verdict: ${u.verdict}. ${u.reason || ''}`.trim()
      u.verdict = 'review'
      elevated++
    }
  }
  if (elevated) log(`relay-loop: elevated ${elevated} standin repo(s) to review for independent Fable re-audit (id:9821)`)
}

// Sort: verdict class first (D3 invariant), then income repos win slot contention
// within a class (user directive 2026-06-12: prefer income-relevant tasks), then the
// fable-standin tiebreaker (user directive 2026-06-13; see standInRank above).
let actionable = discovery.units
  .filter(u => u.verdict !== 'idle')
  .sort((a, b) =>
    (PRIORITY[a.verdict] - PRIORITY[b.verdict]) ||
    ((b.income ? 1 : 0) - (a.income ? 1 : 0)) ||
    (standInRank(a) - standInRank(b))
  )

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
  // All-execute now, so PRIORITY ties; income repos win slot contention, then the
  // fable-standin tiebreaker prefers Fable-vetted roadmaps (standInRank: execute → non-standin first).
  actionable = kept.concat(demoted).sort((a, b) =>
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

// Refresh the cross-round accumulator's per-round views (completed/reviewMe persist).
state.runId = state.runId || discovery.runId
state.ts = discovery.ts
state.queued = [
  ...actionable.map(u => ({ repo: u.repo, verdict: u.verdict })),
  ...fableDownDeferred.map(u => ({ repo: u.repo, verdict: `${u.verdict} (deferred: --fable-down, strong model skipped)` })),
]
state.blocked = discovery.surfaced.map(s => ({ repo: s.repo, reason: s.reason, worktreePath: '-' }))

log(`relay-loop: ${actionable.length} actionable units (${discovery.units.length} own repos, ${discovery.surfaced.length} surfaced)`)
await writeRelayStatus(state)

// No actionable units this round (incl. --fable-down with no executor work) → a dry
// round; the outer loop counts consecutive dry rounds toward "backlog drained".
if (actionable.length === 0) {
  if (FABLE_DOWN && STRONG_MODEL === 'claude-fable-5') log('relay-loop: --fable-down — no executor work this round, strong work deferred')
  return { actionable: 0 }
}

// ── Phase 2+3: Dispatch pool + serialized integration ──

phase('Dispatch')

const queue = [...actionable]
const debts = []
let unitsDispatched = 0
let roundCapHit = false   // per-round MAX_UNITS cap; distinct from quotaStopped (run-ending)

function refDoc(verdict) {
  if (verdict === 'review') return '~/.claude/skills/fables-turn/references/review.md'
  if (verdict === 'handoff') return '~/.claude/skills/fables-turn/references/handoff.md'
  return '~/.claude/skills/fables-executor/SKILL.md'
}

// Deterministic worktree path + branch for a unit — the child creates them, and the
// API-error recovery path (runUnit catch / integrate null-guard) needs the same names
// to find a failed child's partial work instead of orphaning it.
const worktreePathFor = (unit) => `~/.cache/fables-turn/worktrees/${unit.repo}/${state.runId}-${unit.verdict}`
const branchFor = (unit) => `relay/${state.runId}-${unit.verdict}`

function unitPrompt(unit) {
  const wt = worktreePathFor(unit)
  const branch = branchFor(unit)
  return `You are a fables-turn ${unit.verdict.toUpperCase()} child for the repo ${unit.repo} (main checkout: ${unit.path}).

Create your worktree first: git -C ${unit.path} worktree add ${wt} -b ${branch} HEAD
Work EXCLUSIVELY in that worktree. Classifier verdict reason: ${unit.reason}. Last checkpoint tag: ${unit.lastCkpt || '(none)'}.

Procedure: follow ${refDoc(unit.verdict)} exactly. Read ~/.claude/skills/fables-turn/references/conventions.md for environment facts and relay invariants before starting.
${unit.verdict === 'execute' ? 'Work the open [ROUTINE] items in ROADMAP.md under the executor contract. Stop at a natural boundary; never start an item you cannot finish.' : ''}
${unit.verdict === 'handoff' ? 'Run checkpoints C1-C4. C5 (HARD execution) only if the top HARD item is small enough to finish safely; otherwise leave it specced.' : ''}
${unit.verdict === 'review' ? 'Run the full trust-but-verify procedure including the test-integrity audit. Mint any new id tokens via ~/.claude/skills/meeting/append.sh new-ids N ' + unit.path + ' — NEVER invent tokens. After re-deriving the roadmap, set routine_open = the number of OPEN (unticked) [ROUTINE] items remaining — the supervisor uses it to re-enqueue an execute unit this same pool.' : ''}

Hard rules: commit in the worktree as you go; NEVER push; NEVER tag; NEVER run git-diary-workflow or todo-update; never prompt the user. If you cannot meet the contract, set contract_met=false and explain in handback.

Return: contract_met, branch ("${branch}"), worktree ("${wt}"), summary (one line for the checkpoint tag message), review_me_count (open REVIEW_ME.md boxes you wrote, else 0), diary_fragment (one paragraph), handback ("" if none), routine_open (review units: open [ROUTINE] count after re-derivation; 0 for handoff/execute).`
}

// Auto-resume after an API-error / terminal child failure (handoff only — its
// per-checkpoint commits make it resumable; review/execute are single-shot and instead
// surface as recoverable handbacks). The resume child inspects the worktree the failed
// child already created and continues from its last committed checkpoint to completion,
// committing per stage so a re-failure loses at most one more stage.
function resumePrompt(unit) {
  const wt = worktreePathFor(unit)
  const branch = branchFor(unit)
  return `You are RESUMING an interrupted fables-turn HANDOFF for repo ${unit.repo} (main checkout: ${unit.path}). A prior child was killed (API error / timeout) mid-handoff.

The worktree may already exist at ${wt} on branch ${branch} with some checkpoints committed.
1. If that worktree does NOT exist or has NO committed "relay(handoff): C*" commits, there is nothing to resume: return contract_met=false, handback="no resumable checkpoints — fresh handoff needed", branch="${branch}", worktree="${wt}". Do not create anything.
2. Otherwise work EXCLUSIVELY in that worktree. Read its committed ROADMAP.md / docs to see which checkpoints (C1 docs, C2 roadmap, C3 red tests, C4 bdd, C5 hard) are already done (git -C ${wt} log --oneline), then CONTINUE from the next stage to completion per ~/.claude/skills/fables-turn/references/handoff.md. Use ONLY the id tokens already in the committed ROADMAP.md; never invent tokens. Commit after EACH stage (so another failure loses at most one stage). C5 only if the top HARD item is small enough to finish safely.

Hard rules: NEVER push; NEVER tag; NEVER run git-diary-workflow/todo-update; never prompt the user. You are Opus standing in for Fable — flag judgment calls in REVIEW_ME.md.

Return: contract_met, branch ("${branch}"), worktree ("${wt}"), summary (one line), review_me_count, diary_fragment, handback ("" if none).`
}

async function quotaGate(tier) {
  if (quotaStopped) return false
  // Forward quota-policy knobs from args into the quota-stop env so a self-looping run
  // self-enforces the cap with no orchestrator between rounds. RELAY_QUOTA_DECAY_7D gives
  // the time-decaying 7d/Sonnet cap (e.g. "0.70:0.10"); per-bucket/general thresholds
  // still work. Only forward what's set (default behaviour unchanged).
  const envPairs = ['RELAY_QUOTA_THRESHOLD', 'RELAY_QUOTA_DECAY_7D',
    'RELAY_QUOTA_THRESHOLD_FIVE_HOUR', 'RELAY_QUOTA_THRESHOLD_SEVEN_DAY', 'RELAY_QUOTA_THRESHOLD_SEVEN_DAY_SONNET']
    .filter(k => A[k] !== undefined && A[k] !== null && A[k] !== '')
    .map(k => `${k}=${A[k]}`)
  const thresholdEnv = envPairs.length ? envPairs.join(' ') + ' ' : ''
  const v = await agent(
    `Run this command and report the result: ${thresholdEnv}~/.claude/skills/fables-turn/scripts/quota-stop.sh --tier ${tier} ${unitsDispatched} 0
Return exitCode (0 = proceed, 1 = stop, 2 = uncertain/stale-cache) and, if /tmp/claude-usage-cache.json is readable, one bucket entry per quota bucket with pctRemaining (= 100 - utilization percent) and resetTime when present.`,
    { label: `quota:${tier}`, phase: 'Dispatch', schema: QUOTA_SCHEMA, model: 'haiku' }
  )
  if (v && v.buckets && v.buckets.length) state.quota = v.buckets
  // Fail safe: agent death or exit 1/2 both stop dispatch (exit 2 = "stop, uncertain").
  if (!v || v.exitCode !== 0) {
    quotaStopped = true
    log(`relay-loop: quota gate STOP (tier=${tier}, exit=${v ? v.exitCode : 'agent-failed'}) — draining in-flight units and integration debt`)
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
      reason: `child agent failed/skipped (API error or terminal failure); ${unit.verdict === 'handoff' ? 'auto-resume did not complete' : 'no auto-resume for ' + unit.verdict}. Any committed checkpoints are preserved in the worktree — re-run /fables-turn to resume (handoff continues from the last checkpoint).`,
      worktreePath: worktreePathFor(unit),
    })
    await writeRelayStatus(state)
    return
  }
  if (!report.contract_met) {
    // HANDBACK: not merged; worktree held on disk for a human/strong turn.
    state.blocked.push({ repo: unit.repo, reason: report.handback || 'contract_met=false', worktreePath: report.worktree })
    await writeRelayStatus(state)
    return
  }
  const standInSuffix = (unit.verdict !== 'execute' && STRONG_MODEL === 'claude-opus-4-8') ? ', fable-standin' : ''
  const label = unit.verdict === 'execute'
    ? 'executor (sonnet, relay-loop)'
    : `reviewer (${STRONG_MODEL}${standInSuffix}, relay-loop)`
  const result = await agent(
    `You are the serialized integrator of the fables-turn relay pool. Integrate ONE completed unit, strictly in this order, for repo ${unit.repo} at ${unit.path}:

1. Verify the main checkout working tree is clean (git -C ${unit.path} status --porcelain). If dirty, abort: return merged=false with reason.
2. git -C ${unit.path} merge --no-ff ${report.branch} -m "merge(relay): ${report.summary}"
   On conflict: git -C ${unit.path} merge --abort, return merged=false with reason (worktree stays on disk).
3. ~/.claude/skills/fables-turn/scripts/ckpt-tag.sh ${unit.path} -m "${report.summary}" -l "${label}"
   It prints the new tag name — capture it as ckptTag.
4. ~/.claude/skills/git-diary-workflow/git-lock-push.sh --ff-only ${unit.path}
   pushStatus = "pushed" on success, otherwise the error summary.
5. git -C ${unit.path} worktree remove --force ${report.worktree} && git -C ${unit.path} branch -d ${report.branch}
   (--force is required and safe here: the merge+tag+push above already integrated the committed branch work, so the only thing --force discards is incidental untracked build artifacts the child left behind, e.g. a uv.lock from running tests. Without --force, worktree remove fails on any untracked file and the worktree+branch silently orphan in ~/.cache/fables-turn/worktrees/ — id:d187.)
6. Update ~/.config/fables-turn/relay.toml for [repos.${unit.repo}]: set last_ckpt to the new tag${unit.verdict === 'review' ? ", set last_review to today's date (ISO)" : ''}${unit.verdict === 'handoff' ? ", set handoff_date to today's date (ISO) and status to \"handed-off\"" : ', set status to "active"'}. Change ONLY this repo's block.
7. Return merged=true, ckptTag, pushStatus, ts (current ISO timestamp).

Never push any other repo, never force-push, never resolve conflicts yourself.`,
    { label: `integrate:${unit.repo}`, phase: 'Integrate', schema: INTEGRATE_SCHEMA, model: 'sonnet' }
  )
  if (result && result.merged) {
    if (result.ts) state.ts = result.ts
    state.completed.push({ repo: unit.repo, mode: unit.verdict, ckptTag: result.ckptTag || '?', pushStatus: result.pushStatus || '?' })
    if (report.review_me_count) {
      state.reviewMe.push({ repo: unit.repo, count: report.review_me_count, path: `${unit.path}/REVIEW_ME.md` })
    }
  } else {
    state.blocked.push({ repo: unit.repo, reason: (result && result.reason) || 'integration failed', worktreePath: report.worktree })
  }
  await writeRelayStatus(state)
}

async function runUnit(unit) {
  const tier = unit.verdict === 'execute' ? 'sonnet' : 'strong'
  if (!(await quotaGate(tier))) {
    state.queued.push({ repo: unit.repo, verdict: `${unit.verdict} (quota-deferred)` })
    return
  }
  unitsDispatched++
  state.inFlight.push({ repo: unit.repo, mode: unit.verdict, agentId: `unit-${unitsDispatched}` })
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
  if (unit.verdict === 'review' && report && report.contract_met &&
      (report.routine_open || 0) > 0 && !quotaStopped && !unit.rechained) {
    queue.push({
      repo: unit.repo, path: unit.path, verdict: 'execute',
      reason: `post-review re-enqueue: ${report.routine_open} open [ROUTINE] item(s)`,
      lastCkpt: unit.lastCkpt, income: unit.income, rechained: true,
    })
    log(`relay-loop: review→execute re-enqueue ${unit.repo} (${report.routine_open} open [ROUTINE])`)
  }
  // Integration debt is enqueued, not awaited here: the dispatch slot frees up
  // immediately while the serialized chain works through merges one at a time.
  debts.push(enqueueIntegration(() => integrate(unit, report)))
}

await parallel(
  Array.from({ length: Math.min(POOL_WIDTH, queue.length) }, () => async () => {
    while (queue.length && !quotaStopped && !roundCapHit) {
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
await integrationChain

state.queued = state.queued.concat(queue.map(u => ({ repo: u.repo, verdict: `${u.verdict} (not dispatched)` })))
await writeRelayStatus(state)
return { actionable: actionable.length }
}
// ── end runRound ──

// ── Outer self-feeding loop ──
// Repeat runRound (fresh discovery each round) until the quota cap stops the run, two
// consecutive rounds find no actionable work (backlog drained), or MAX_ROUNDS trips.
let dry = 0
let round = 0
while (!quotaStopped && round < MAX_ROUNDS) {
  round++
  const r = await runRound()
  if (r.failed) {
    if (round === 1) {
      return { error: 'discovery failed', runId: state.runId, statusPath: RELAY_STATUS_PATH, completed: state.completed, handbacks: [], queuedRemaining: state.queued, quotaStopped }
    }
    log('relay-loop: discovery failed mid-run — stopping after completed rounds')
    break
  }
  if (r.actionable === 0) {
    dry++
    log(`relay-loop: round ${round} — no actionable work (dry ${dry}/2)`)
    if (dry >= 2) { log('relay-loop: backlog drained (2 consecutive empty discoveries) — done'); break }
  } else {
    dry = 0
  }
}

const handbacks = state.blocked.filter(b => b.worktreePath && b.worktreePath !== '-')
log(`relay-loop: done — ${round} round(s), ${state.completed.length} integrated, ${handbacks.length} HANDBACKs, quotaStopped=${quotaStopped}`)

return {
  runId: state.runId,
  statusPath: RELAY_STATUS_PATH,
  completed: state.completed,
  handbacks,
  queuedRemaining: state.queued,
  quotaStopped,
  rounds: round,
}
