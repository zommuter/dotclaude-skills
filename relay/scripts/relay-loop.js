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
const RELAY_STATUS_PATH = A.RELAY_STATUS_PATH || '~/.config/fables-turn/RELAY_STATUS.md'

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
    '## Skipped (this round)',
    skipped,
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
then write the combined content to "$target" ATOMICALLY via the flock'd single-writer (id:ebfb
step 2), which serializes concurrent runs + does mkdir -p + temp + atomic mv:
  printf '%s' "$CONTENT" | ~/.claude/skills/relay/scripts/relay-state-write.sh status-write "$target"
(the helper also re-checks the path is absolute and refuses a literal ~ / \${HOME} target).

CRITICAL (id:c34a): NEVER create a file or directory whose name literally contains "$HOME", "\${HOME}", "~", or a leading "$" — that means expansion failed and leaks a junk dir into the cwd. The final resolved path MUST begin with "/". If you cannot resolve an absolute path beginning with "/", abort WITHOUT writing anything. Do not truncate or reformat.

LIVE CLAIMS (id:ebfb): before writing, run ~/.claude/skills/relay/scripts/claim.sh peek — it prints zero or more live cross-session claims, one compact JSON per line ({key,repo,runId,mode,item,...}). APPEND to the Content below a final section exactly:
## Claims (live)
with one "- <repo>  mode=<mode>  run=<runId>" line per claim (use item if repo is empty), or "_(none)_" if peek prints nothing. Then write the combined text (the Content verbatim followed by this Claims section).

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

async function runRound() {
// ── Phase 1: Discover ──

phase('Discover')

const discovery = await agent(
  `You are the discovery/classifier step of the relay autonomous pool.

Read ~/.config/fables-turn/relay.toml. Consider ONLY repos with classification = "own".
Repo path default: ~/src/<name>; honor any "# path:" comment override in the repo's
relay.toml block. For each repo, classify into exactly one verdict:

- "review": commits exist after the last relay checkpoint tag (run: git -C <path> tag -l 'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1 — match BOTH prefixes; old fable-ckpt-* tags are historical and repos may still carry one until their next checkpoint — then git -C <path> log <tag>..HEAD --oneline). Unaudited work always wins over other verdicts.
- "execute": no unaudited commits, and ROADMAP.md has >=1 unticked "- [ ]" item tagged [ROUTINE].
- "hard": no unaudited commits, NO open [ROUTINE] item, but ROADMAP.md has >=1 unticked "- [ ]" item tagged [HARD (i.e. [HARD — strong model]). This is the ROUTINE-drained steady state where HARD work would otherwise stall.
- "handoff": no unaudited commits, and ROADMAP.md is missing/has no roadmap marker, OR every item is ticked while untracked new work exists.
- "idle": none of the above.

Order of precedence (apply the FIRST that matches): review > execute(routine) > hard > handoff > idle.

A repo with a DIRTY main working tree (git -C <path> status --porcelain non-empty, ignoring entries already declared acceptable in relay.toml comments) is NOT dispatched: put it in "surfaced" with the reason instead of "units". Repos with no relay checkpoint tag (neither fable-ckpt-* nor relay-ckpt-*) and no handoff_date are handoff candidates, not review.

SYNC-WITH-ORIGIN GUARD (id:c3f7 — never commit on a base behind origin; a 2026-06-15 incident built a doomed parallel relay timeline on a clone ~1 month behind origin, and a force-push "fix" would have destroyed 106 commits). BEFORE classifying each repo, sync it with its upstream:
- Run: git -C <path> fetch origin -q   (ignore fetch errors — offline/missing remote — and fall through to local-only classification).
- U = output of: git -C <path> rev-parse --abbrev-ref @{upstream}   (if empty, skip this guard for that repo). Then read "ahead behind" from: git -C <path> rev-list --left-right --count HEAD...$U  (first number = ahead = local-only commits; second = behind = origin-only commits).
- DIVERGED (ahead>0 AND behind>0): do NOT classify or work it. Put it in "surfaced" with reason "diverged from origin (local <ahead> / origin <behind>) — needs manual reconcile (id:c3f7)". Never dispatch or commit on a diverged repo.
- BEHIND-ONLY (ahead==0 AND behind>0) AND the main tree is clean: fast-forward FIRST — git -C <path> merge --ff-only $U — then classify the now-up-to-date repo normally.
- Otherwise (ahead-only, or in sync): proceed normally.

WORKTREE-AWARE / CLAIMED-ELSEWHERE GUARD (id:ebfb step 1 — don't double-work a repo another relay run/session holds; a held worktree is the durable in-flight signal). Before classifying a repo, check: ls -d ~/.cache/fables-turn/worktrees/<repo>/* 2>/dev/null. If any worktree directory exists whose basename does NOT start with this run's runId, the repo is in-flight under another relay run/session — put it in "surfaced" with reason "in-flight elsewhere (worktree <basename>) — claimed by another relay run (id:ebfb)" instead of classifying it.
${INTERACTIVE ? 'Interactive run: include marginal/ambiguous repos in "surfaced" with a one-line question each.' : 'Unattended run: never include questions; surface ambiguous repos with a factual reason only.'}

Also produce:
- runId: a PER-RUN UNIQUE id — generate it ONCE with the shell as: relay-$(date +%Y%m%d-%H%M%S)-$RANDOM (seconds + a random suffix). It MUST be unique per pool run: two concurrent pools must NEVER share a runId, because the cross-session lease's same-run re-entrancy AND the worktree-aware discovery guard both key on runId — a shared (e.g. minute-granular) runId would make two pools see each other as "the same run" and double-work a repo (id:0902 follow-up). Do NOT use a minute-granular id.
- ts: current ISO 8601 timestamp
- lastCkpt per repo (the tag name, or "" if none)
- income per repo: true iff the repo's relay.toml block has income = true
- hasRoutine per repo: true iff ROADMAP.md has >=1 unticked "- [ ]" item tagged [ROUTINE], INDEPENDENT of the verdict. A repo classified "review" (unaudited commits) that ALSO has open [ROUTINE] work must report hasRoutine=true — this lets the --fable-down path keep executors busy on routine work in repos whose review must wait for the next strong turn.
- openHard per repo: the COUNT of unticked "- [ ]" items tagged [HARD (i.e. [HARD — strong model]) in ROADMAP.md, INDEPENDENT of the verdict. 0 when none. The supervisor uses it to surface the HARD backlog and (on an apex Opus session) to size the hard verdict.
- strongRecheckPending per repo: true iff the relay.toml [repos.<name>] block has a non-empty last_strong_ckpt AND fable_rechecked is false (or absent/empty). This is the DURABLE, model-tracked Fable-bonus-recheck queue (id:e030): a strong (Opus) review/handoff/hard checkpoint that has not yet had its optional Fable recheck. It SURVIVES a later executor (sonnet) checkpoint that overwrites last_ckpt and masks the latest-tag fable-standin signal — so prefer this field over the tag grep when deciding optional-recheck candidacy. Report false when last_strong_ckpt is absent/empty or fable_rechecked is true (or a date).
- standin per repo: true iff the repo's LATEST relay checkpoint tag message contains the literal token "fable-standin". Detect (match BOTH prefixes — the latest tag may be fable-ckpt-* or relay-ckpt-*): T=$(git -C <path> tag -l 'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1); then git -C <path> tag -l --format='%(contents)' "$T" | grep -q fable-standin && true || false. This means the last relay checkpoint was produced by Opus standing in for Fable (Fable outage), so the repo still needs an independent Fable re-review and its specs are provisional. Report false when there is no checkpoint tag.
- intensive per repo (id:8d52): a resource name STRING (e.g. "local-llm") iff this repo's next unit of work is resource-heavy — set it when EITHER (a) the repo's relay.toml block has intensive = "<resource>" (or intensive = true → use "local-llm"), OR (b) the top open "- [ ]" item the unit would work in ROADMAP.md carries an "[INTENSIVE — <resource>]" modifier (parse the resource between "— " and "]"). Otherwise leave it "" (empty). These units are NEVER auto-dispatched (OOM risk) — they are gated behind --allow-intensive.

INJECTED HIGH-PRIORITY UNITS (id:baf1): also run \`~/.claude/skills/relay/scripts/inject.sh take\`. It emits zero or more pending user-injected units as compact JSON lines (and atomically consumes them, so they are NOT re-listed next round): {token, repo, verdict, item, prompt, requested_at}. For EACH such line, add ONE extra unit to "units" with: injected=true, inject_token=<token>, verdict=<its verdict, default "execute">, repo=<its repo>, path=<resolve like any own repo: ~/src/<repo> or the "# path:" override>, reason="user-injected high-priority task", inject_item=<item or "">, inject_prompt=<prompt or "">, and income/standin/hasRoutine/openHard/strongRecheckPending=false, lastCkpt="". These are IN ADDITION to (not instead of) the repo's normal classification — a repo may appear both as its classified unit and as an injected unit. If \`inject.sh take\` emits nothing, add no injected units.

SKIPPED ROLLUP (id:be62): also populate "skipped" — repos NOT worked this round for a benign reason, so the user sees what the pool ignores and why: (a) every relay.toml repo whose classification is NOT "own" (clone / excluded / needs_review) → {repo, reason: "excluded-by-config (<classification>)"}; (b) every OWN repo you classified "idle" → {repo, reason: "idle — in sync, no open work"}. This is distinct from "surfaced" (which is needs-attention: dirty / diverged / claimed-elsewhere). Dirty/diverged/claimed repos go in "surfaced", NOT "skipped".

Return every own repo exactly once across NON-INJECTED units (verdict idle included) and surfaced; injected units are extra.`,
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
await writeRelayStatus(state)

// No actionable units this round (incl. --fable-down with no executor work) → a dry
// round; the outer loop counts consecutive dry rounds toward "backlog drained".
if (actionable.length === 0 && intensiveUnits.length === 0) {
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
const worktreePathFor = (unit) => `~/.cache/fables-turn/worktrees/${unit.repo}/${state.runId}-${unit.verdict}`
const branchFor = (unit) => `relay/${state.runId}-${unit.verdict}`

function unitPrompt(unit) {
  const wt = worktreePathFor(unit)
  const branch = branchFor(unit)
  return `You are a relay ${unit.verdict.toUpperCase()} child for the repo ${unit.repo} (main checkout: ${unit.path}).

FIRST acquire the cross-session repo lease (id:ebfb): run ~/.claude/skills/relay/scripts/claim.sh acquire ${unit.repo} --run ${state.runId} --mode ${unit.verdict}. If it exits NON-ZERO, another live relay run/session already holds this repo — STOP IMMEDIATELY: do NOT create a worktree, do NOT do any work, and return contract_met=false with handback="claimed by another relay run (cross-session lease id:ebfb): " plus the holder JSON it printed to stderr. The supervisor releases the lease at integration, so do not release it yourself. Only if acquire SUCCEEDS, continue:
${unit.intensive ? '\nThis is an [INTENSIVE — ' + unit.intensive + '] unit (id:8d52): ALSO acquire the exclusive RESOURCE lease before any heavy work — ~/.claude/skills/relay/scripts/claim.sh acquire resource:' + unit.intensive + ' --run ' + state.runId + ' --mode intensive. If it exits non-zero (another relay run is using ' + unit.intensive + '), STOP: return contract_met=false, handback="resource ' + unit.intensive + ' busy (another relay run)". The supervisor releases it at integration.\n' : ''}
Create your worktree first: git -C ${unit.path} worktree add ${wt} -b ${branch} HEAD
Work EXCLUSIVELY in that worktree. Classifier verdict reason: ${unit.reason}. Last checkpoint tag: ${unit.lastCkpt || '(none)'}.

${unit.injected ? 'This is a USER-INJECTED high-priority task (id:baf1). ' + (unit.inject_item ? 'Work specifically the ROADMAP.md item tagged <!-- id:' + unit.inject_item + ' -->. ' : '') + (unit.inject_prompt ? 'User instruction: ' + unit.inject_prompt + ' ' : '') + 'Otherwise follow the verdict procedure below.\n' : ''}Procedure: follow ${refDoc(unit.verdict)} exactly. Read ~/.claude/skills/relay/references/conventions.md for environment facts and relay invariants before starting.
${unit.verdict === 'execute' ? 'Work the open [ROUTINE] items in ROADMAP.md under the executor contract. Stop at a natural boundary; never start an item you cannot finish.' : ''}
${unit.verdict === 'hard' ? 'You are an Opus-apex HARD-execute child (id:da26). Pick the TOP open "- [ ]" item tagged [HARD — strong model] in ROADMAP.md and SIZE it first. Model your discipline on handoff.md C5 "only if small enough to finish safely": only implement the item if you can finish it cleanly and green within this turn — full red-green-refactor, verify-before-merge. If it is too large, contains nested/multi-session scope, or you cannot make the test suite green safely, do NOT half-do it: set contract_met=false and explain the sizing in handback (the item stays open for a manual/next-turn strong session). When you DO finish: tick the item\'s checkbox ONLY if the work is genuinely green (all tests pass — never tick to manufacture a pass), append its done-note, commit in the worktree, and make the full test suite green. Work ONE bounded HARD item only — never start a second.' : ''}
${unit.verdict === 'handoff' ? 'Run checkpoints C1-C4. C5 (HARD execution) only if the top HARD item is small enough to finish safely; otherwise leave it specced.' : ''}
${unit.verdict === 'review' ? 'Run the full trust-but-verify procedure including the test-integrity audit. Single-id-two-views (D2): when you promote a ROADMAP item for work TODO.md already tracks under an <!-- id:XXXX -->, REUSE that token; mint a fresh one via ~/.claude/skills/meeting/append.sh new-ids N ' + unit.path + ' ONLY for genuinely new work — NEVER invent tokens, and never duplicate-id already-tracked work. When you close a ROADMAP item whose id also lives in TODO.md, tick the TODO line too. Reverse-handoff (review.md §5b): qualify+size any unqualified TODO/ROADMAP items added by /meeting or manual edits since the last checkpoint (mini-handoff) — reuse their id. After re-deriving the roadmap, set routine_open = the number of OPEN (unticked) [ROUTINE] items remaining — the supervisor uses it to re-enqueue an execute unit this same pool.' : ''}

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
  const v = await agent(
    `Run this command and report the result: ${thresholdEnv}~/.claude/skills/relay/scripts/quota-stop.sh --tier ${tier} --agents ${unitsDispatched} --wall 0
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
      reason: `child agent failed/skipped (API error or terminal failure); ${unit.verdict === 'handoff' ? 'auto-resume did not complete' : 'no auto-resume for ' + unit.verdict}. Any committed checkpoints are preserved in the worktree — re-run /relay to resume (handoff continues from the last checkpoint).`,
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
   (--force is required and safe here: the merge+tag+push above already integrated the committed branch work, so the only thing --force discards is incidental untracked build artifacts the child left behind, e.g. a uv.lock from running tests. Without --force, worktree remove fails on any untracked file and the worktree+branch silently orphan in ~/.cache/fables-turn/worktrees/ — id:d187.)
6. Update ~/.config/fables-turn/relay.toml for [repos.${unit.repo}] via the flock'd single-writer (id:ebfb step 2) — for EACH field run \`~/.claude/skills/relay/scripts/relay-state-write.sh toml-set ${unit.repo} <key> <value>\` (value VERBATIM: quote strings e.g. '"<tag>"', bare for bool e.g. false; NEVER hand-edit relay.toml): set last_ckpt to the new tag${unit.verdict === 'review' ? ", set last_review to today's date (ISO)" : ''}${unit.verdict === 'handoff' ? ", set handoff_date to today's date (ISO) and status to \"handed-off\"" : ', set status to "active"'}. Change ONLY this repo's block.${isStrong ? `
6b. STRONG checkpoint — this is a ${unit.verdict} unit produced by the strong model (${STRONG_MODEL}). ${isFableRecheck ? `This session's strong tier is REAL Fable, and this is a review — it IS the optional Fable recheck (id:e030 consume side). Record the durable Fable-bonus-recheck queue entry for [repos.${unit.repo}]: set last_strong_ckpt = "<the new tag>", strong_model = "${STRONG_MODEL}", and fable_rechecked = "<today's date, ISO>" (the recheck just happened — mark it done, do NOT set false).` : `Record the durable Fable-bonus-recheck queue entry for [repos.${unit.repo}]: set last_strong_ckpt = "<the new tag>", strong_model = "${STRONG_MODEL}", and fable_rechecked = false (an Opus-standin/strong checkpoint that still invites an optional Fable recheck).`} These keys survive a LATER executor (sonnet) checkpoint that overwrites last_ckpt — so the pending optional Fable recheck stays visible even when masked. Write all three via the same flock'd relay-state-write.sh toml-set helper (overwrite if present; fable_rechecked is a BARE value: false, or '"<ISO date>"' when rechecked). Change ONLY this repo's block.` : `
6b. EXECUTOR checkpoint — this is an execute unit (sonnet). Do NOT touch last_strong_ckpt, strong_model, or fable_rechecked: an executor checkpoint must never clear the pending Fable-bonus-recheck queue (that is exactly the masking bug id:e030 fixes). Leave those keys untouched.`}
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
  // Injected units (id:baf1) skip the quota gate — an explicit user request runs even near
  // the cap. They were already consumed by `inject.sh take`, so deferring them would lose
  // the injection; honoring it is the whole point of "inject this next, highest priority".
  if (!unit.injected && !(await quotaGate(tier))) {
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
  debts.push(enqueueIntegration(unit.repo, () => integrate(unit, report)))
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
await writeRelayStatus(state)
return { actionable: actionable.length + intensiveRan }
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
