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

// MECH_FALLBACK (id:4239) — the front-door mechanical-tier preflight verdict, produced ONCE by
// scripts/mech-preflight.sh (SKILL.md step 0) and threaded in as a single run-level flag. The
// helper consumes the id:99a4 discriminator (probe-mech-proxy.sh) and emits one token:
//   'fallback-haiku' — probe mode-a: the session was NOT launched through mechanical-proxy.py,
//                      so model:"bash" would hit the real API and 404. The real API IS reachable
//                      directly, so the ~12 mechanical hops (quota gates, inject-take, heartbeat,
//                      file-surface) dispatch as model:"haiku" instead — Haiku genuinely runs the
//                      fenced relay-mech command via its Bash tool (the pre-proxy echo-runner path).
//   'abort'          — probe mode-b: base URL is the proxy loopback form but the proxy is DOWN.
//                      ALL agent() traffic transits the dead proxy, so Haiku is EQUALLY unreachable
//                      — NEVER a fallback. Surface loudly and keep model:"bash" (it will fail-open
//                      as before); do NOT hard-crash the whole loop over a mechanical-tier hop.
//   'proceed' / ''   — probe healthy (or no preflight ran): model:"bash" is proxy-intercepted as
//                      designed. Default posture.
// MECH_MODEL is the model string the mechanical hops actually use, decided ONCE here (never
// per-hop probing).
const MECH_FALLBACK = A.MECH_FALLBACK || ''
const MECH_MODEL = MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'

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

// routed:a923 — the scope token as it may be SPLICED INTO A SHELL COMMAND (the ```relay-mech
// fences below, which the mechanical proxy runs locally). Two hazards, both closed here:
//   1. injection — anything outside [A-Za-z0-9._-] is refused, never quoted-and-hoped.
//   2. fail-CLOSED on refusal — an unscoped `inject.sh take` under a scoped run is exactly the
//      steal this fixes, so an unsafe/unresolvable name yields a sentinel that matches NO repo
//      (nothing consumed) rather than falling back to a global drain. That mirrors what the
//      scope resolution does downstream anyway: an unconfirmed --only is a LOUD reject with an
//      empty scoped list (no dispatch), so consuming an injection for it would be pure loss.
// Empty ONLY_REPO ⇒ '' ⇒ no --repo flag ⇒ global take (unscoped pool, today's behaviour).
const INJECT_SCOPE = !ONLY_REPO ? ''
  : (/^[A-Za-z0-9._-]+$/.test(ONLY_REPO) ? ONLY_REPO : '__unresolvable-scope__')

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

// id:4239 — mechanical-tier preflight notice, logged ONCE. The loud operator warning already
// went to the front-door session's stderr (mech-preflight.sh); this is the in-loop trace.
if (MECH_FALLBACK === 'fallback-haiku') {
  log('relay-loop: id:4239 mechanical-preflight = mode-a (proxy NOT in path) → dispatching the ~12 model:"bash" mechanical hops as model:"haiku" for this run (real API reachable directly). Relaunch with ANTHROPIC_BASE_URL=http://127.0.0.1:61843 to use the mechanical tier natively.')
} else if (MECH_FALLBACK === 'abort') {
  log('relay-loop: id:4239 mechanical-preflight = mode-b (proxy DOWN at base URL) → WHOLE SESSION DEGRADED; Haiku is equally unreachable through the dead proxy, so NO fallback. Mechanical hops keep model:"bash" and will fail-open. Start/restart mechanical-proxy.py.')
}

// buildRelayStatus — generate RELAY_STATUS.md content from a run-state snapshot.
// state shape:
//   { runId, ts, inFlight: [{repo, mode, agentId, item, itemRank, eligibleCount}],  // choice id:8af2
//     completed: [{repo, mode, ckptTag, pushStatus, workedIds}],  // workedIds id:de69
//     queued:    [{repo, verdict}],
//     surfaced:  [{repo, reason, worktreePath}],   // id:8c85 — rendered as Blocked, with…
//     handbacks: [{repo, reason, worktreePath}],   // …the persistent handback accumulator
//     skipped:   [{repo, reason}],
//     ownRepos:  [string]                          // id:8c85 — accounting universe
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

// id:8c85 — inline copies of relay/scripts/status-accounting.mjs (keep behaviour-equivalent; the
// Workflow sandbox cannot import). NOT PINNED: unlike the prompt-size-gate/handback-guard inline
// copies, NO test asserts this copy still matches the module — E4 of the 8c85 spec only greps that
// the NAME `assertStatusAccounting` appears here. The copy is a hand-rewrite (`asArray` vs inline
// ternaries, `memberKey` vs `accountingMemberKey`), so it can never be byte-identical and the house
// body-comparison pattern cannot be applied as-is; it was hand-verified behaviour-equivalent across
// 10 fixtures at review time (2026-08-10) and is UNGUARDED against future drift. Closing that gap
// needs a differential harness, tracked separately — do not read this comment as a guarantee.
// See that module for the
// full rationale: RELAY_STATUS must account for EVERY own repo in exactly ONE rendered section
// every round, with a reason. On 2026-08-10 four non-dispatch classes vanished at once and the
// file reported a false clean; nothing asserted the property, so nothing noticed.
// assertCompleteAccounting is the GENERIC core (partition completeness over an enumerated
// universe); assertStatusAccounting is a thin wrapper instantiating it over ownRepos × the five
// sections. id:eb63(b) can instantiate the same core at item granularity without touching this.
const ACCOUNTING_SECTIONS = ['blocked', 'completed', 'inFlight', 'queued', 'skipped']
// id:2f6b — only these three are mutually exclusive for one repo in one round. `completed` and
// `handbacks` (rendered inside `blocked`) ACCUMULATE for the whole run, so a repo legitimately
// appears in them alongside anything else; asserting "exactly one section" over all five fired on
// every multi-round run and the false message then tripped the harness safety classifier, failing
// two status writes (loderite relay-20260818-154017-12780). See status-accounting.mjs.
const EXCLUSIVE_SECTIONS = ['inFlight', 'queued', 'skipped']
function accountingMemberKey(m) {
  if (typeof m === 'string') return m
  if (!m || typeof m !== 'object') return ''
  for (const k of ['repo', 'name', 'id', 'item', 'key']) {
    if (typeof m[k] === 'string' && m[k] !== '') return m[k]
  }
  return ''
}
// id:2f6b — a row is a UNIT, not a repo. Null when the row carries no item identity (exempt from
// the unit arm, still covered by the completeness arm).
function statusUnitKey(m) {
  if (!m || typeof m !== 'object') return null
  const repo = typeof m.repo === 'string' ? m.repo : ''
  if (!repo) return null
  const verdict = [m.mode, m.verdict].find((v) => typeof v === 'string' && v) || ''
  let item = ''
  if (typeof m.item === 'string' && m.item) item = m.item
  else if (Array.isArray(m.workedIds) && m.workedIds.length) item = [...m.workedIds].filter(Boolean).sort().join(',')
  if (!item) return null
  return `${repo}#${verdict}#${item}`
}
function assertCompleteAccounting(universe, buckets, opts) {
  const o = opts && typeof opts === 'object' ? opts : {}
  const label = typeof o.label === 'string' && o.label ? o.label : 'accounting'
  const id = typeof o.id === 'string' ? o.id : ''
  const uni = (Array.isArray(universe) ? universe : []).map(accountingMemberKey).filter(Boolean)
  const b = buckets && typeof buckets === 'object' ? buckets : {}
  const exclusive = Array.isArray(o.exclusiveBuckets) ? o.exclusiveBuckets : null
  const unitKeyOf = typeof o.unitKey === 'function' ? o.unitKey : null
  const placement = new Map()
  const exclusivePlacement = new Map()
  const unitPlacement = new Map()
  for (const bucketName of Object.keys(b)) {
    const isExclusive = !exclusive || exclusive.includes(bucketName)
    for (const m of (Array.isArray(b[bucketName]) ? b[bucketName] : [])) {
      const k = accountingMemberKey(m)
      if (k) {
        if (!placement.has(k)) placement.set(k, [])
        placement.get(k).push(bucketName)
        if (isExclusive) {
          if (!exclusivePlacement.has(k)) exclusivePlacement.set(k, [])
          exclusivePlacement.get(k).push(bucketName)
        }
      }
      const uk = unitKeyOf ? unitKeyOf(m) : null
      if (uk) {
        if (!unitPlacement.has(uk)) unitPlacement.set(uk, [])
        unitPlacement.get(uk).push(bucketName)
      }
    }
  }
  const missing = uni.filter((k) => !placement.has(k)).sort()
  const dupExclusive = [...exclusivePlacement.entries()].filter(([, where]) => where.length > 1).map(([k]) => k)
  const dupUnit = [...unitPlacement.entries()].filter(([, where]) => where.length > 1).map(([k]) => k)
  const duplicated = [...new Set([...dupExclusive, ...dupUnit])].sort()
  const whereOf = (k) => (exclusivePlacement.has(k) && exclusivePlacement.get(k).length > 1
    ? exclusivePlacement.get(k) : (unitPlacement.get(k) || placement.get(k) || []))
  const ok = missing.length === 0 && duplicated.length === 0
  const tag = id ? ` (id:${id})` : ''
  const bucketNames = Object.keys(b).sort().join(', ')
  let message
  if (ok) {
    const scope = exclusive ? `at most one of [${[...exclusive].sort().join(', ')}]` : `exactly one of [${bucketNames}]`
    message = `${label}: OK — all ${uni.length} member(s) accounted for, ${scope}${tag}`
  } else {
    const parts = []
    if (missing.length) parts.push(`${missing.length} of ${uni.length} reached NO section [${bucketNames}] — ${missing.join(', ')}`)
    if (duplicated.length) {
      const what = exclusive ? 'in more than one mutually-exclusive section' : 'must be exactly one section'
      parts.push(`${duplicated.length} double-counted (${what}) — ${duplicated.map((k) => `${k} in ${[...whereOf(k)].sort().join('+')}`).join('; ')}`)
    }
    message = `${label}: INCOMPLETE ACCOUNTING${tag} — ${parts.join(' | ')}. A member that reaches no section is INVISIBLE to the operator: the file reports a false clean.`
  }
  return { ok, missing, duplicated, message }
}
function statusBuckets(state) {
  const s = state && typeof state === 'object' ? state : {}
  const a = (v) => (Array.isArray(v) ? v : [])
  return {
    blocked: [...a(s.surfaced), ...a(s.handbacks)],
    completed: a(s.completed),
    inFlight: a(s.inFlight),
    queued: a(s.queued),
    skipped: a(s.skipped),
  }
}
function assertStatusAccounting(ownRepos, state) {
  return assertCompleteAccounting(ownRepos, statusBuckets(state), {
    label: 'RELAY_STATUS accounting (every own repo in at least one section, with a reason)',
    id: '8c85',
    exclusiveBuckets: EXCLUSIVE_SECTIONS,   // id:2f6b — completed/blocked accumulate across rounds
    unitKey: statusUnitKey,                 // id:2f6b — the same UNIT twice is still a defect
  })
}

function buildRelayStatus(state) {
  const header = `# RELAY_STATUS — last updated ${state.ts}  run: ${state.runId}`

  // id:8af2 — the per-repo row names the CHOSEN item and how many were eligible, e.g.
  // `- dotclaude-skills  mode=execute  agent=unit-1  → id:cbd2 (1 of 21 actionable)`.
  // Rank 0 means the id came from a user injection rather than the eligible order, so it renders
  // `injected, N actionable` instead of a fake "1 of N". Units with no named item (review/handoff,
  // or an id-less ledger) render EXACTLY as before — fail-open, no dangling decoration.
  const inFlightChoice = (r) => !r.item ? ''
    : `  → id:${r.item} (${r.itemRank ? `${r.itemRank} of ${r.eligibleCount}` : `injected, ${r.eligibleCount}`} actionable)`
  const inFlight = state.inFlight && state.inFlight.length
    ? state.inFlight.map(r => `- ${r.repo}  mode=${r.mode}  agent=${r.agentId}${inFlightChoice(r)}`).join('\n')
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

  // id:06a1 — per-agent/per-hop failures that produced NO handback. Rendered as its OWN
  // clearly-labelled section (an operator has to be able to FIND it), and omitted entirely
  // when there is nothing to report — an always-present empty section is the id:8c85
  // cry-wolf failure. Tolerates an absent `agentFailures` (an older/partial state object),
  // exactly like every sibling row above.
  const agentFailures = state.agentFailures || []
  const agentFailureSection = agentFailures.length
    ? [
        '',
        '## Agent/hop FAILURES (id:06a1 — failed with no handback; invisible before this)',
        agentFailures.map(f => `- ❌ ${f.label}  repo=${f.repo}  phase=${f.phase}  round=${f.round}  reason=${f.reason}`).join('\n'),
      ]
    : []

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
    `- agent-failures=${(state.agentFailures || []).length} (id:06a1 — hops/children that failed with no handback)`,
  ].join('\n')

  // id:8c85 — LOUD accounting invariant, rendered INTO the file the operator reads. Every own
  // repo must appear in exactly one of the five sections above, with a reason; if any repo
  // reached none (or two), say so here and NAME it, rather than letting the file read clean.
  // Fail-safe: an absent ownRepos list (early rounds, a pre-discovery write) renders as
  // not-yet-known instead of a false violation.
  const accountingUniverse = state.ownRepos || []
  const accounting = accountingUniverse.length
    ? (() => {
        const r = assertStatusAccounting(accountingUniverse, state)
        return r.ok
          ? `_(ok — all ${accountingUniverse.length} own repo(s) accounted for across [${ACCOUNTING_SECTIONS.join(', ')}])_`
          : `⚠️ **${r.message}**`
      })()
    : '_(own-repo list not yet known this round)_'

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
    ...agentFailureSection,
    '',
    '## Skipped (this round)',
    skipped,
    '',
    '## Accounting invariant (id:8c85 — every own repo in exactly one section, with a reason)',
    accounting,
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
  // id:8c85 — the invariant is WIRED, not merely built: fail LOUDLY into the run log too (the
  // rendered file carries the same message). An unreferenced module is not an invariant.
  const acct = assertStatusAccounting(state.ownRepos || [], state)
  if ((state.ownRepos || []).length && !acct.ok) log(`relay-loop: ${acct.message}`)
  // id:0d31 (skeleton L1 thin-glue) — ALL the deterministic work (path resolve + c34a guard,
  // claims peek → "## Claims (live)", relay-burn → "## Burnup this run", atomic flock'd write,
  // event-append) now lives in relay-status-publish.sh. The haiku agent's whole job collapses
  // to piping one blob to one command — short + precise, so a weak model can't drift off-target
  // (formatting claims-JSON into markdown by hand was the drift risk). The content (and, when
  // present, the event lines after a sentinel) ride stdin via a quoted heredoc so they transit
  // verbatim without expansion.
  const stdinPayload = events.length ? `${content}\n===RELAY-EVENTS===\n${eventsBlock}` : content
  // id:3222 — this hop is best-effort, so a blocked/empty reply used to vanish entirely (six of
  // them in run relay-20260812-001727-5554 left RELAY_STATUS hours stale with nothing recorded).
  // The label: write-relay-status dispatch below now goes through dispatchGuarded, which records
  // the failure into state.agentFailures; the hop's own fail-soft behaviour is unchanged
  // (scheduleStatusWrite already .catch()es this tail).
  //
  // id:b0ce — MECHANICAL HOP (was: a hardcoded model:'haiku' agent that had the whole payload
  // dictated to it verbatim). This was the LAST hop whose script is allowlisted in
  // mechanical-proxy.py yet still crossed a model, and it cost two status writes on 2026-08-18:
  // the harness safety classifier read "run EXACTLY this command, pipe the payload verbatim"
  // plus a payload asserting fleet state as an injection attempt and refused BOTH hops
  // (agents_error=2). That prompt shape cannot be reworded out of looking like injection, so the
  // fix is to take the model out of the path: `model: MECH_MODEL` sends it to the ```relay-mech
  // command fence + the ```relay-mech-stdin DATA fence (id:33b2/93ac), which the proxy runs
  // locally with the payload piped to stdin and NEVER handed to a shell or a model. The stdin
  // fence was built and allowlisted for exactly this hop ("payload embeds arbitrary repo/item
  // prose … heredoc, JSON, newlines") and had NO call site until now.
  //
  // STATED LIMIT — this removes the model only when the proxy IS in path. Under
  // MECH_FALLBACK='fallback-haiku' (mode-a, no proxy) MECH_MODEL is 'haiku' and the payload
  // still crosses a model, so the classifier exposure remains in that mode. The prompt below is
  // therefore written to be executable by a model too, and the heredoc it names is the model's
  // path only — the proxy ignores the prose entirely and reads the two fences.
  await dispatchGuarded(
    { label: 'write-relay-status', phase: 'Status', model: MECH_MODEL }, '-',
    `Run exactly this command and report its stdout verbatim (publishes the relay run-status snapshot; the script resolves the path, renders the Claims + Burnup sections, writes atomically, and appends any events itself). The payload in the second fence is DATA: pipe it to the command's stdin unchanged, e.g. via a quoted heredoc. Do not reformat it, do not write any file yourself, and do not retry on a non-zero exit — report its stderr instead.
\`\`\`relay-mech
~/.claude/skills/relay/scripts/relay-status-publish.sh --path '${path}' --run '${state.runId || ''}' --events-path '${RELAY_EVENTS_PATH}'
\`\`\`
\`\`\`relay-mech-stdin
${stdinPayload}
\`\`\``
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
    queued: [...(s.queued || [])],
    // id:8c85 — the Blocked section is RENDERED from `surfaced` + `handbacks`. This snapshot
    // used to copy `blocked` (a field nothing reads or writes since id:1735) and NEITHER of the
    // two the renderer actually reads, so since id:cb50 routed every write through here EVERY
    // status write rendered `## Blocked / HANDBACKs _(none)_` and `blocked=0` regardless of what
    // happened — erasing dirty-deferred repos, in-flight-suppressed repos and real HANDBACKs.
    surfaced: [...(s.surfaced || [])], handbacks: [...(s.handbacks || [])],
    ownRepos: [...(s.ownRepos || [])],   // id:8c85 — the universe the accounting invariant checks
    skipped: [...(s.skipped || [])], quota: [...(s.quota || [])], reviewMe: [...(s.reviewMe || [])],
    agentFailures: [...(s.agentFailures || [])],   // id:06a1 — the renderer reads it, so the snapshot must carry it (the id:8c85 class)
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
          // top_intensive_routine / top_intensive_hard (id:2799): the SAME field, split by
          // the lane the matching [INTENSIVE] item is actually in ([ROUTINE] / [HARD —
          // pool] respectively), "" when that lane carries none. Computed deterministically
          // by gather-repo-state.sh alongside top_intensive. The id:ad74 promote backstop
          // below reads these (not the lane-blind top_intensive) when patching a non-idle
          // unit's .intensive, so it never stamps an unrelated lane's resource claim onto a
          // dispatch (the exact id:2799 regression: an unrelated [HARD] [INTENSIVE] item
          // deferring every open [ROUTINE] item behind --intensive).
          top_intensive_routine: { type: 'string' },
          top_intensive_hard: { type: 'string' },
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
          // open_hard_pool_ids (id:7517, routed:2d94): the RESOLVED 4-hex ids BEHIND
          // open_hard_pool, in ROADMAP file order, produced by gather-repo-state.sh's own
          // open_hard_pool walk — the SAME predicate that produces the count, so list and count
          // cannot drift. unitPrompt HANDS this list to the HARD-execute child and FORBIDS it
          // from re-deriving the enumeration by grep: in loderite run
          // relay-20260814-133435-24323 a HARD child grepped only the RETIRED "[HARD — pool]"
          // spelling, found 0, and refused 5 real bare-"[HARD]" items — a whole dispatch round
          // wasted on a repo that had work. Exact sibling of actionable_routine_ids (id:b09e).
          // An item with no `<!-- id:XXXX -->` contributes an EMPTY STRING (counted, unnameable).
          // ABSENT/[] on older queue entries and injected units → fail-open to the old
          // survey-the-ledger instruction, so this can only narrow the child's search.
          open_hard_pool_ids: { type: 'array', items: { type: 'string' } },
          // queue_sig (id:4860): the discover-sig.sh SUPERSET signature the MECHANICAL
          // discovery producer (discover-repos-mechanical.sh, id:9d97) stamped onto this
          // entry in the discovery queue, present ONLY on units the runner copied from the
          // queue (CASE A). The runner is instructed to copy a queue verdict ONLY when this
          // queue_sig equals the repo's LIVE sig (from the prelude); the JS-side canary below
          // re-asserts u.queue_sig === sigByRepo[u.repo] and DROPS+surfaces any mismatch
          // (stale snapshot / went-dirty-after-snapshot / mangled bridge-copy). ABSENT on
          // CASE B live units (computed live, exempt from the assert). "" = fail-open sentinel.
          queue_sig: { type: 'string' },
          // actionable_routine_ids (id:b09e): the 4-hex ROADMAP ids BEHIND actionable_routine_open,
          // in ROADMAP file order, emitted by classify-repo.sh from the SAME per-line predicate
          // that produces the count (len(ids) === actionable_routine_open, by construction — the
          // count is derived as the list's length, so the two cannot drift). Gated (🚧) /
          // @manual / human-lane / non-[ROUTINE] / closed items never appear. An actionable item
          // with no `<!-- id:XXXX -->` contributes an EMPTY STRING (counted, but unnameable).
          // unitPrompt names ids[0] in the execute dispatch so the child goes straight to its
          // item instead of surveying the ledger — the phase two measured children died in
          // (peak ctx 176,841 / 242 entries, Bash 52 Read 19, zero implementation started).
          // ABSENT/[] on older queue entries and injected units → fail-open to the old plural
          // instruction.
          actionable_routine_ids: { type: 'array', items: { type: 'string' } },
          // id:b09e — orphan-suppressed ids the naming picker must subtract (discover-repo.sh).
          suppressed_item_ids: { type: 'array', items: { type: 'string' } },
          // roadmap_bytes (id:4f9b): size of the repo's ROADMAP.md in BYTES, measured on the
          // host by classify-repo.sh. This loop runs inside the Workflow sandbox and cannot
          // stat a file, so the number has to ride along. It feeds the pre-dispatch size gate
          // (oversizeDispatchReason) which refuses to dispatch a child into a ledger that
          // cannot fit, naming the cause and the remedy. ABSENT/0 ⇒ unmeasured ⇒ fail OPEN.
          roadmap_bytes: { type: 'integer' },
          // todo_bytes (id:b018): size of the repo's TODO.md in BYTES, measured the same way
          // and for the same reason. The child reads BOTH ledgers, so sizing only the ROADMAP
          // under-counted by ~50% — loderite cleared the budget by 326 tok and died anyway.
          todo_bytes: { type: 'integer' },
        },
      },
    },
    surfaced: {
      type: 'array',
      items: {
        type: 'object',
        required: ['repo', 'reason'],
        // queue_sig (id:4860): the producer stamps it on surfaced entries too; harmless
        // pass-through here (a surfaced entry carries no dispatch verdict, so it needs no
        // canary). NOTE (id:bc49): being surfaced no longer implies the repo is NOT dispatched
        // — an additive orphan-suppress repo appears in BOTH units and surfaced. Only a
        // repo-level block (in-flight/diverged/e3ad-refusal/discover-error) is substitutive.
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
// id:86a2 — PRELUDE_SCHEMA is no longer passed to agent() (the prelude is now a model:'bash'
// dispatch of discover-prelude.sh, parsed by parsePrelude); it is RETAINED as the documented
// output contract discover-prelude.sh must emit — the canonical shape the two views must agree on.
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

// id:6176 — the quota hop is now a model:"bash" mechanical dispatch (was a QUOTA_SCHEMA-typed
// haiku return). quota-stop.sh prints NOTHING to stdout on success and signals its verdict purely
// via EXIT CODE, logging the crossed bucket to STDERR. mechanical-proxy.py therefore returns the
// 'MECH-OK exit=0\n' sentinel on exit 0 (id:3557 — a genuinely empty string wedges the model:"bash"
// agent harness, which treats an empty completion as retryable and re-dispatches forever), or
// 'MECH-ERROR exit=<N>\n<stderr>' on any non-zero exit (see _run_mechanical). Parse that raw shape
// back into the { exitCode, crossedBucket, buckets } object quotaGate() consumes. VERIFIED
// (id:3557 audit): parseQuotaMechResult's `/^MECH-ERROR exit=(\d+)/` regex does not match the
// 'MECH-OK …' sentinel, so the `!m` branch (exitCode 0 / proceed) fires exactly as it did for the
// old empty string — no logic change needed here.
//   exitCode: 0 (proceed) / 1 (real-cache exhaustion) / 2 (cache unreadable, no burn sample) /
//             3 (cache unreadable, burn-rate extrapolates over threshold).
//   crossedBucket (id:2425): exit 1 stderr "quota-stop: <bucket>=<val>% >= threshold <t>";
//             exit 3 stderr "REASON=quota-extrapolated-stop bucket=<bucket>". Empty otherwise.
//   buckets: no longer available — quota-stop.sh emits no per-bucket JSON on stdout, so state.quota
//            is simply not refreshed from this hop (crossedBucket now names the culprit directly).
function parseQuotaMechResult(raw, tier) {
  const text = (raw == null) ? '' : String(raw)
  const m = text.match(/^MECH-ERROR exit=(\d+)/)
  if (!m) return { exitCode: 0, crossedBucket: '', buckets: [] }
  // id:a104 — MECH-ERROR is how the mechanical proxy conveys ANY non-zero exit (real quota
  // exhaustion included), so this is a hop-visibility record, not a judgment that the exit was
  // unexpected — quotaGate() below still handles the exit code exactly as before (fail-soft
  // preserved, no change to the returned shape).
  recordAgentFailure(`quota:${tier || '-'}`, '-', 'Quota', text)
  const exitCode = Number(m[1])
  const ex = text.match(/REASON=quota-extrapolated-stop\s+bucket=(\S+)/)   // exit 3
  const th = text.match(/quota-stop:\s*([A-Za-z0-9_]+)=[\d.]+%\s*>=\s*threshold/)  // exit 1
  const crossedBucket = ex ? ex[1] : (th ? th[1] : '')
  return { exitCode, crossedBucket, buckets: [] }
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
    // considered_ids (id:bfbf, routed:9371): on a WHOLE-DISPATCH "nothing dispatchable"
    // handback, the 4-hex ids the child actually LOOKED AT and rejected. This is the EVIDENCE
    // behind the claim: without it a correct "nothing to do" is indistinguishable from a child
    // that looked in the wrong place (loderite 2026-08-14 — grepped the retired "[HARD — pool]"
    // spelling, found 0, refused 5 real bare-"[HARD]" items, and the pool accepted it as a
    // clean drain). noWorkEnumerationAlarm cross-checks it against the deterministic
    // open_hard_pool count; an empty/absent list with a nonzero count ALARMS and is NOT
    // recorded as a clean drain. [] / absent on a successful unit.
    considered_ids: { type: 'array', items: { type: 'string' } },
    route: { type: 'string' },          // decision-gate | hard-split | human | none
    gate_reason: { type: 'string' },    // ONE short line for the inline ROADMAP gate note
    proposed_split: {                   // hard-split only: seams to mint as pickable units
      type: 'array',
      items: {
        type: 'object',
        // id:44a1 — a bare {title} seam renders as an un-workable one-liner (no
        // Acceptance/Tests/Done-check clause, id:213a's lint flags it) and cannot
        // point an executor at the file/function it concerns. acceptance/done_check/
        // file are REQUIRED so handback-followup.py can render a real body instead of
        // a title-only line; the emitter (handback-followup.py) enforces this at the
        // schema boundary (rejects + writes nothing on a non-conforming split item).
        required: ['title', 'acceptance', 'done_check', 'file'],
        properties: {
          title: { type: 'string' }, id: { type: 'string' },
          tier: { type: 'string' }, dep: { type: 'string' },
          acceptance: { type: 'string' },   // observable "done" behaviour for this seam
          done_check: { type: 'string' },   // exact command/test that proves the seam done
          file: { type: 'string' },         // file(s)/function(s) this seam concerns
        },
      },
    },
  },
}

// id:087b — this is NO LONGER a dispatch schema: integrate() has no LLM agent to constrain.
// It is retained as the DOCUMENTED SHAPE of the object `parseIntegrateResult()` builds from
// integrate.sh's `KEY=VALUE`-per-line stdout contract, so the producer (the shell script),
// the parser and the consumer below can be diffed against one written-down contract.
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
    // id:dd7d — sibling-branch surfacing (c): OTHER branches for the same item (not
    // report.branch itself) that stranded-branch-scan.sh found still carrying committed
    // work at integrate time. "<branch>\t<count>" lines, verbatim from the scan; empty/absent
    // when none. Informational only — does NOT block the merge already performed in step 2.
    siblingBranches: { type: 'array', items: { type: 'string' } },
  },
}

// id:6176 — the mid-round `inject.sh take` hop (takeInjections) is now a model:"bash" mechanical
// dispatch (was an INJECT_TAKE_SCHEMA-typed haiku return that ALSO resolved paths + shaped units).
// The proxy returns inject.sh take's RAW STDOUT: one compact JSON per line
// {token, repo, verdict, item, prompt, requested_at}, empty when nothing pending, or 'MECH-ERROR …'
// if the script itself failed. parseInjectTake reconstructs the dispatch-ready unit objects in JS —
// including the path-resolve the old prompt asked the LLM to do. The Workflow sandbox has NO
// shell/$HOME/fs (process.env crashes the pool, id:2026-06-15), so the absolute path is resolved
// from `ownRepos` (prelude.repos — this round's relay.toml read, honoring `# path:`); an injected
// repo absent from that own-repo list cannot be path-resolved in-sandbox and is skipped LOUDLY,
// never dispatched with a guessed path.
// routed:a923 — BACKSTOP for the scope contract above (the enforce-don't-document rule). The
// fix proper is at the CONSUMING layer (`inject.sh take --repo`), because only refusing to
// consume keeps an out-of-scope unit recoverable. This is the second line: if an out-of-scope
// injected unit ever reaches the loop anyway (an inject.sh predating the flag, a proxy running
// a different copy), do NOT dispatch it under a scope that the harness would block — log LOUDLY
// with its token so the shard is recoverable by hand from inject.done/. Never silent: a dropped
// injection that logs nothing is the failure mode this whole item is about.
function enforceInjectScope(units, where) {
  if (!INJECT_SCOPE) return units
  const kept = []
  for (const u of units) {
    if (u.repo === INJECT_SCOPE) { kept.push(u); continue }
    log(`relay-loop: routed:a923 SCOPE VIOLATION (${where}) — injected unit for repo '${u.repo}' surfaced under a --only '${ONLY_REPO}' run and was NOT dispatched. It was ALREADY CONSUMED upstream, so recover the shard by hand: ~/.config/relay/inject.done/${u.inject_token || '<token>'}.json → inject.d/. Expected inject.sh take --repo to have left it pending — check the installed inject.sh supports --repo.`)
  }
  return kept
}

function parseInjectTake(raw, ownRepos) {
  const text = (raw == null) ? '' : String(raw)
  // id:3557 — an empty take (nothing pending) now comes back as the 'MECH-OK exit=0' sentinel
  // rather than a genuinely empty string (mechanical-proxy.py _run_mechanical); check for it
  // explicitly so this never depends on the JSON.parse-per-line loop below happening to fail
  // closed on the sentinel text.
  // id:a104 — only the genuine failure sentinel is worth recording; an empty take or the
  // legitimate MECH-OK "nothing pending" result is normal quiet operation, not a hop failure
  // (recording those would cry-wolf every round the injection queue happens to be empty).
  if (/^MECH-ERROR/.test(text)) recordAgentFailure('inject-take', '-', 'Support', text)
  if (!text.trim() || /^MECH-ERROR/.test(text) || /^MECH-OK\b/.test(text)) return []
  const units = []
  for (const line of text.split('\n')) {
    const s = line.trim()
    if (!s) continue
    let obj
    try { obj = JSON.parse(s) } catch (_) { continue }  // tolerate stray non-JSON lines
    if (!obj || !obj.repo) continue
    const match = (ownRepos || []).find(r => r.repo === obj.repo)
    if (!match || !match.path) {
      log(`relay-loop: id:6176 inject-take — injected repo '${obj.repo}' not in this round's own-repo list (relay.toml); cannot resolve its path in the fs-less Workflow sandbox → skipping injected unit ${obj.token || ''}`)
      continue
    }
    units.push({
      injected: true,
      inject_token: obj.token,
      verdict: obj.verdict || 'execute',
      repo: obj.repo,
      path: match.path,
      reason: 'user-injected high-priority task (mid-round, id:6e9d)',
      inject_item: obj.item || '',
      inject_prompt: obj.prompt || '',
      income: false,
      standin: false,
      hasRoutine: false,
      openHard: false,
      strongRecheckPending: false,
      lastCkpt: '',
    })
  }
  return units
}

// id:86a2 — parse the model:'bash' discover-prelude return. discover-prelude.sh emits the
// PRELUDE_SCHEMA object as ONE JSON line on stdout; the mechanical proxy returns that raw
// string. The exec harnesses (discovery-exec-harness.mjs / loop-round-exec-harness.mjs) stub
// agent() to return the OBJECT directly for the 'discover-prelude' label — so accept both.
// FAIL-SAFE: a MECH-ERROR / empty (MECH-OK) / unparseable return is a falsy prelude, which the
// `if (prelude && prelude.stopRequested === true)` and `if (prelude && Array.isArray(prelude.repos))`
// guards downstream already tolerate (a dead prelude ⇒ a benign no-op round), exactly as the old
// haiku prelude's failure mode was handled.
function parsePrelude(raw) {
  if (raw && typeof raw === 'object') return raw
  const text = (raw == null) ? '' : String(raw)
  // id:a104 — record the genuine failure sentinel (MECH-ERROR); an empty/MECH-OK return is the
  // legitimate "nothing to say" shape (agent() stub, or a quiet mechanical exit) and not a hop
  // failure — recording it would cry-wolf every ordinary round.
  if (/^MECH-ERROR/.test(text)) recordAgentFailure('discover-prelude', '-', 'Discover', text)
  if (!text.trim() || /^MECH-ERROR/.test(text) || /^MECH-OK\b/.test(text)) return null
  try { return JSON.parse(text) } catch (_) {
    const m = text.match(/\{[\s\S]*\}/)   // defensive: grab the first {...} block if wrapped in stray lines
    if (m) { try { return JSON.parse(m[0]) } catch (_) { /* fall through */ } }
    // id:a104 — genuinely unparseable body (not a MECH-ERROR/MECH-OK sentinel, just bad JSON)
    // is the other named failure mode for this hop; record it too before falling back to null.
    recordAgentFailure('discover-prelude', '-', 'Discover', `unparseable prelude body: ${text.slice(0, 200)}`)
    return null
  }
}

// id:24ec — parse the model:'bash' discover-run SHARD return. discover-chunk.sh emits the
// {units,surfaced,skipped} object as ONE JSON line on stdout; the mechanical proxy returns that
// raw string. The exec harnesses (discovery-exec-harness.mjs / loop-round-exec-harness.mjs) stub
// agent() to return the OBJECT directly for the 'discover-run' label — so accept both. A
// MECH-ERROR / empty (MECH-OK) / unparseable return is a null (a FAILED shard), which the
// shardResults merge below already handles by SURFACING the chunk's repos (visible gap, re-
// classified next round) — never a silent drop. Mirrors parsePrelude (the id:86a2 prelude flip).
function parseShard(raw) {
  if (raw && typeof raw === 'object') return raw
  const text = (raw == null) ? '' : String(raw)
  if (!text.trim() || /^MECH-ERROR/.test(text) || /^MECH-OK\b/.test(text)) return null
  try { return JSON.parse(text) } catch (_) {
    const m = text.match(/\{[\s\S]*\}/)   // defensive: grab the first {...} block if wrapped in stray lines
    if (m) { try { return JSON.parse(m[0]) } catch (_) { /* fall through */ } }
    return null
  }
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
// id:06a1 — `agentFailures` is the accumulator for a mechanical hop / child agent that
// resolved to a failure WITHOUT producing a handback. Before this, such a failure existed
// only in the Workflow task-notification block, which an --afk operator never reads
// (id:4347 no-silent-swallow class). It records ONLY; it changes no hop's semantics.
const state = { runId: (A.RUN_ID ? String(A.RUN_ID) : ''), ts: '', inFlight: [], completed: [], queued: [], surfaced: [], handbacks: [], skipped: [], quota: [], reviewMe: [], agentFailures: [] }
let quotaStopped = false
// id:06a1 — the ONE writer for the failure accumulator. Call it wherever a mechanical hop
// or child agent resolves to a failure/null; the reason is truncated so a multi-KB model
// error body can never blow up RELAY_STATUS.md. RENDERING only — never change a hop's
// failure semantics from here (id:66d9 owns fail-closed for provision).
function recordAgentFailure(label, repo, phase, reason) {
  state.agentFailures.push({
    label: String(label || '(unlabelled)'),
    repo: String(repo || '-'),
    phase: String(phase || '-'),
    round,
    reason: String(reason == null ? '(no reason reported)' : reason).replace(/\s+/g, ' ').trim().slice(0, 200),
  })
}
// id:3222 — ONE guarded-dispatch wrapper for the fire-and-forget / best-effort hops
// (`release:*`, `write-relay-status`, `gaming-log:*`). VISIBILITY ONLY: it changes no hop's
// control flow — a hop that continues on failure still continues, it just stops being
// INVISIBLE. Run relay-20260812-001727-5554 had 39 agents blocked at the dispatch boundary
// while RELAY_STATUS.md reported `agent-failures=8`: id:a104 wired the three PARSE sites, but
// a dispatch that resolves null/empty or rejects at the `agent()` boundary was counted
// nowhere the operator could see (the id:4347 silent-swallow shape).
//
// BOTH failure shapes are recorded, deliberately: a rejected call AND a null/empty resolution.
// The run's own journal (wf_3da78c35-8a0/journal.jsonl) records 198 dispatches, ALL of them
// with a non-empty result — i.e. it contains NO record of a blocked dispatch at all, so it
// does NOT establish which shape a harness block takes. Handling only the shape one incident
// note guessed at would leave the other silent again.
//
// It NEVER rethrows and never fails a unit — id:66d9 owns fail-closed for provisioning, and
// provisionWorktree() deliberately does NOT route through here: it records its own failure, and
// a second entry for the same event would double-count it.
//
// Signature is (opts, repo, prompt): the hop's identity leads the call so the label, phase and
// model stay on the dispatch line itself.
async function dispatchGuarded(opts, repo, prompt) {
  const o = opts || {}
  const label = o.label || '(unlabelled hop)'
  const phase = o.phase || '-'
  let res
  try {
    res = await agent(prompt, o)
  } catch (e) {
    log(`relay-loop: id:3222 guarded hop ${label} failed (non-fatal, continuing): ${(e && e.message) || e}`)
    recordAgentFailure(label, repo, phase, `agent() rejected: ${(e && e.message) || e}`)
    return null
  }
  const body = typeof res === 'string' ? res : (res == null ? '' : JSON.stringify(res))
  if (!String(body).trim()) {
    log(`relay-loop: id:3222 guarded hop ${label} resolved null/empty (non-fatal, continuing)`)
    recordAgentFailure(label, repo, phase, 'agent() resolved null/empty — the dispatch produced no reply (the shape a harness-side block leaves behind)')
    return null
  }
  return res
}
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
// id:3906 — per-run accumulator of the STRUCTURED handback fields (handback_item/route/
// gate_reason, mandatory since id:3801) so the exit-summary alert can tell a genuine bug signal
// (same item, repeatedly) from queue exhaustion (different items, each a legitimate size-out/
// gate) instead of always calling every >=2x repeat "a bug signal". Fed to classifyRepeatHandbacks.
const handbackClassifyLog = []
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
// id:bfbf (routed:9371) — inline copy of handback-guard.mjs's noWorkEnumerationAlarm (keep
// byte-equivalent; see that file for the full rationale). An unevidenced "nothing dispatchable"
// claim must ALARM LOUDLY and must NOT be recorded as a clean drain.
function noWorkEnumerationAlarm(ctx) {
  const c = ctx || {}
  const route = c.route ? String(c.route) : 'none'
  const item = c.handbackItem ? String(c.handbackItem) : ''
  if (route !== 'none' || item) return null            // item-level handback — not this detector's business
  const open = Number.isFinite(c.openHardPool) ? c.openHardPool : Number(c.openHardPool || 0)
  if (!(open > 0)) return null                          // genuinely empty backlog — nothing to enumerate
  const norm = (a) => (Array.isArray(a) ? a : [])
    .filter((x) => typeof x === 'string' && x.trim() !== '')
    .map((x) => x.trim().toLowerCase())
  const considered = norm(c.consideredIds)
  const pool = norm(c.poolIds)
  const who = `${c.repo || '(repo)'} ${c.verdict || '(verdict)'}`
  const base = { repo: c.repo || '', verdict: c.verdict || '', openHardPool: open, cleanDrain: false }
  const NOT_A_DRAIN = 'NOT recorded as a clean drain: the no-work suppression cache is deliberately NOT stamped, so this verdict cannot silently park a repo that has work.'
  // (a) No enumeration at all — independent of whether the pool set is usable. The child owed
  // evidence and returned none; silence must never read as "considered everything".
  if (!considered.length) {
    return {
      ...base,
      kind: 'unevidenced-no-enumeration',
      overlap: 0,
      reason: `UNEVIDENCED zero-dispatchable handback (id:bfbf): ${who} claimed nothing was dispatchable while the deterministic open_hard_pool count is ${open}, and returned NO considered_ids at all. Without the enumeration a correct "nothing to do" is indistinguishable from a child that looked in the wrong place — the id:7517/routed:2d94 failure. ${NOT_A_DRAIN} Investigate the child's item-selection path before re-dispatching.`,
    }
  }
  // (b) THIRD STATE — the pool set is unusable, so disjointness cannot be decided either way.
  if (!pool.length) {
    const rawLen = Array.isArray(c.poolIds) ? c.poolIds.length : 0
    const why = rawLen
      ? `open_hard_pool_ids was PRESENT (${rawLen} entr${rawLen === 1 ? 'y' : 'ies'}) but NONE of them resolves to an id — every counted ROADMAP line was unnameable (the routed:3ad9 multi-marker ambiguity, where an item's own id cannot be told from a trailing reference)`
      : `open_hard_pool_ids was ABSENT or empty — an older discovery-queue entry, or a producer that never emitted the field`
    return {
      ...base,
      kind: 'enumeration-unevaluable',
      overlap: null,
      reason: `UNEVALUABLE zero-dispatchable handback (id:bfbf): ${who} claimed nothing was dispatchable and DID enumerate ${considered.length} considered id(s) [${considered.join(', ')}], but the cross-check could not be run: open_hard_pool is ${open} while ${why}. This is NOT an assertion that the child looked in the wrong place — disjointness was never computed — and it is NOT a clean drain either: a nonzero open_hard_pool whose ids cannot be named is itself an upstream fault worth fixing (something counted work it could not name). ${NOT_A_DRAIN} The handback is not blocked; this is surfaced so the gap cannot rot into a silent branch.`,
    }
  }
  // (c) Both sets usable — the real test.
  const overlap = pool.filter((x) => considered.includes(x))
  if (overlap.length) return null                       // the child really did look at the queue
  return {
    ...base,
    kind: 'unevidenced-disjoint',
    overlap: 0,
    reason: `UNEVIDENCED zero-dispatchable handback (id:bfbf): ${who} claimed nothing was dispatchable while the deterministic open_hard_pool count is ${open}, and it returned ${considered.length} considered id(s) [${considered.join(', ')}] of which NOT ONE is in the resolved pool set [${pool.join(', ')}] — ZERO overlap. The child looked somewhere OTHER than the queue — exactly the id:7517/routed:2d94 failure (it swept for the retired "[HARD — pool]" spelling, found 0, and refused ${open > 1 ? open + ' real items' : 'a real item'}; three occurrences on 2026-08-14 alone). ${NOT_A_DRAIN} Investigate the child's item-selection path before re-dispatching.`,
  }
}
function handbackAlerts(tracker, threshold = 2) {
  return Object.values(tracker)
    .filter(e => e.count >= threshold)
    .sort((a, b) => b.count - a.count || a.repo.localeCompare(b.repo) || a.verdict.localeCompare(b.verdict))
    .map(e => ({ repo: e.repo, verdict: e.verdict, count: e.count, lastReason: e.lastReason }))
}
// id:3906 — inline copy of drain.mjs's classifyRepeatHandbacks (keep byte-identical).
const REPEAT_HANDBACK_LEGIT_ROUTES = ['hard-split', 'decision-gate', 'human']
function classifyRepeatHandbacks(handbacks) {
  const list = Array.isArray(handbacks) ? handbacks : []
  const byItem = {}
  for (const h of list) {
    const item = (h && h.handback_item) ? String(h.handback_item) : ''
    ;(byItem[item] || (byItem[item] = [])).push(h || {})
  }
  const bugItems = [], exhaustedItems = []
  for (const item of Object.keys(byItem)) {
    const entries = byItem[item]
    const routes = [...new Set(entries.map(e => (e && e.route) ? String(e.route) : 'none'))]
    const allLegit = routes.every(r => REPEAT_HANDBACK_LEGIT_ROUTES.includes(r))
    const lastReason = (entries[entries.length - 1] || {}).gate_reason || ''
    if (entries.length >= 2 || !allLegit) {
      bugItems.push({ item, count: entries.length, routes, lastReason })
    } else {
      exhaustedItems.push({ item, count: entries.length, routes })
    }
  }
  const kind = (bugItems.length && exhaustedItems.length) ? 'mixed'
    : bugItems.length ? 'bug-signal'
    : 'queue-exhausted'
  return { kind, bugItems, exhaustedItems }
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
  const emitted = emittedEvents || []
  const violations = []
  for (const ev of emitted) {
    const found = acc.some(h => h && h.repo === ev.repo && h.reason === ev.reason)
    if (!found) violations.push({ ...ev, direction: 'forward' })
  }
  for (const h of reconcileHandbacks(acc)) {
    const found = emitted.some(ev => ev && ev.repo === h.repo && ev.reason === h.reason)
    if (!found) violations.push({ ...h, direction: 'reverse' })
  }
  return { ok: violations.length === 0, violations }
}
// id:dc5b — inline copy of round-plan.mjs enforceOneUnitPerRepo (keep byte-equivalent; the
// Workflow sandbox cannot import, structural test pins the wiring). C2 one-unit-per-repo-per-
// round: given the units the round would dispatch IN SCHEDULING ORDER, keep the FIRST unit per
// repo (the higher verdict-class one) and DEFER every later same-repo unit — an execute+review
// pair for one repo in one round collides on the non-union ROADMAP.md at integrate. See that
// file for full rationale.
function enforceOneUnitPerRepo(units) {
  const seen = new Set()
  const plan = []
  const deferred = []
  for (const u of units || []) {
    if (u && seen.has(u.repo)) {
      deferred.push(u)
    } else {
      if (u) seen.add(u.repo)
      plan.push(u)
    }
  }
  return { plan, deferred }
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
// id:e9fa — per-round, per-tier quota-verdict memo. See quotaGateMemoized (below quotaGate)
// for the full rationale — this const/object pair is declared here, alongside the sibling
// QUOTA_CHECK_EVERY throttle they layer on top of, so both quota-dispatch-reduction
// mechanisms are visible together.
const QUOTA_MEMO_TTL_ROUNDS = 1
const quotaMemo = {}  // tier -> { verdict: boolean, round: number }
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
// id:bd04 — ONE predicate for "this handback CREATED dispatchable work", shared by both sites
// that record a handback. It was previously inline at the integrate() site ONLY, which made
// id:c919 inert for the case it was built for: a child-reported SIZE-OUT takes the
// `if (!report.contract_met)` branch and never reaches integrate(), so its `workCreated` stayed
// undefined and isDryRound scored the round dry. Observed csgebra run
// relay-20260818-205434-31345: two hard size-outs whose reports explicitly carried
// route=hard-split + a 4-seam and a 3-seam proposed_split, both recorded via the contract_met
// path, run exited stopReason:'drained' while classify-repo.sh reported open_hard=4.
function handbackCreatedWork(report) {
  const split = report && Array.isArray(report.proposed_split) ? report.proposed_split.length : 0
  return !!(report && report.route === 'hard-split' && split > 0)
}

function isDryRound(r) {
  return !!(r && (r.substantive || 0) === 0 && (r.surfaced || 0) === 0 && (r.workCreated || 0) === 0)
}

// ── id:907e clause (iii) — verdict-class OSCILLATION guard ──────────────────────────────
// Widening `workCreated` to "this round changed the repo's verdict class" (the amended
// producer in integrateUnit) opens a livelock the narrow c919 predicate could not have: a
// repo whose class alternates execute <-> review every round would report work-created
// FOREVER, so the 2-dry-round drain never trips and the pool only ever stops at the
// MAX_ROUNDS seatbelt — looking like an ordinary termination (--fabled F6). The guard closes
// it on BOTH sides the decision asked for: a flapping repo's class change stops counting as
// work (so the round scores DRY again), AND the seatbelt exit reason names the oscillation so
// it fails LOUDLY instead of reading as a normal max-rounds stop.
//
// Flapping = at least OSCILLATION_MIN_FLIPS class transitions inside the last
// OSCILLATION_WINDOW observations for that repo. Two genuine, settling changes over the
// window score 1-2 flips and are NOT flapping; a true alternation (A,B,A,B,A) scores 4 and is.
const OSCILLATION_WINDOW = 5
const OSCILLATION_MIN_FLIPS = 3
const verdictClassHistory = {}     // repo -> the last OSCILLATION_WINDOW observed verdict classes
const oscillatingRepos = new Set() // repos that tripped the guard this run (named in the exit reason)
function recordVerdictClass(repo, verdictClass) {
  if (!repo || !verdictClass) return { flips: 0, oscillating: false }
  const hist = verdictClassHistory[repo] || (verdictClassHistory[repo] = [])
  hist.push(verdictClass)
  if (hist.length > OSCILLATION_WINDOW) hist.shift()
  let flips = 0
  for (let i = 1; i < hist.length; i++) if (hist[i] !== hist[i - 1]) flips++
  const oscillating = flips >= OSCILLATION_MIN_FLIPS
  if (oscillating) oscillatingRepos.add(repo)
  return { flips, oscillating }
}
// id:907e — pull the `verdict` out of a fresh classify-repo.sh mechanical hop's RAW stdout.
// Returns null on anything unparseable (MECH-ERROR, the id:3557 MECH-OK empty-stdout sentinel,
// malformed JSON) so the caller can fall back LOUDLY instead of inventing a class.
function parseVerdictClass(raw) {
  const text = (raw == null) ? '' : String(raw)
  if (/^MECH-ERROR exit=/.test(text)) return null
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start < 0 || end <= start) return null
  try {
    const obj = JSON.parse(text.slice(start, end + 1))
    return (obj && typeof obj.verdict === 'string' && obj.verdict) ? obj.verdict : null
  } catch (_) { return null }
}
// id:087b — quote ONE argument for the `relay-mech` fence. Two hazards, both real:
//   (a) mechanical-proxy.py's `_SEG_SPLIT_RE` splits a command on `| ; & \n` with a NAIVE
//       regex that is NOT shell-aware, so those characters inside an otherwise-quoted
//       argument make a segment that leads with no allowlisted script → the gate refuses →
//       FAIL-OPEN to the real model. On the integrate path that would silently resurrect an
//       LLM integrator, so they are stripped, never merely quoted.
//   (b) a single quote cannot survive inside a single-quoted argument.
// Everything else (`$`, backtick, parens — e.g. the id:1a34 ckpt label "reviewer (claude-…)")
// is inert inside single quotes and is preserved VERBATIM.
const mechArg = (v) => "'" + String(v == null ? '' : v)
  .replace(/[|;&\n\r]+/g, ' ')
  .replace(/'/g, '')
  .replace(/\s+/g, ' ')
  .trim() + "'"
// id:087b — parse integrate.sh's KEY=VALUE stdout contract into the object integrate()
// consumes. Shape mirrors INTEGRATE_SCHEMA (kept above as the documented contract). Returns
// `{merged:false, reason}` for MECH-ERROR / the id:3557 MECH-OK empty-stdout sentinel / any
// stdout without a `merged=` line — a handback, never an invented success.
function parseIntegrateResult(raw) {
  const text = (raw == null) ? '' : String(raw)
  if (/^MECH-ERROR exit=/.test(text) || /^MECH-OK exit=0/.test(text)) {
    return { merged: false, reason: `integrate.sh handback: ${text.replace(/\s+/g, ' ').trim().slice(0, 900)}` }
  }
  const out = { merged: false, siblingBranches: [] }
  for (const line of text.split('\n')) {
    const eq = line.indexOf('=')
    if (eq <= 0) continue
    const k = line.slice(0, eq).trim()
    const v = line.slice(eq + 1).trim()
    if (k === 'merged' && v) out.merged = true
    else if (k === 'ckpt') out.ckptTag = v
    else if (k === 'push') out.pushStatus = v
    else if (k === 'ts') out.ts = v
    else if (k === 'postSig') out.postSig = v
    else if (k === 'openRoutine') out.openRoutine = Number(v) || 0
    else if (k === 'openHard') out.openHard = Number(v) || 0
    else if (k === 'sibling' && v) out.siblingBranches.push(v)
  }
  if (!out.merged) {
    out.reason = `integrate.sh produced no merged= line (unparseable integrator output): ${text.replace(/\s+/g, ' ').trim().slice(0, 900)}`
  }
  return out
}
// Shared shape for BOTH cache-bypassed classifier hops — id:907e's post-handback
// re-classification and id:8123's chain-end re-ask. One fenced `relay-mech` command dispatched
// at MECH_MODEL, stdout parsed by parseVerdictClass (null on MECH-ERROR / the id:3557 empty-
// stdout sentinel / malformed JSON) so each caller falls back LOUDLY on its own terms. Extracted
// rather than copied: the two hops must not drift apart on model tier, phase or parse strictness.
// THROWS on agent failure — callers own the try/catch and the log line that names their fallback.
async function mechVerdictHop(note, command, label) {
  const raw = await agent(
    'Run EXACTLY this one command and report its stdout VERBATIM (' + note + '):\n' +
    '```relay-mech\n' + command + '\n```',
    { label, phase: 'Classify', model: MECH_MODEL }
  )
  return parseVerdictClass(raw)
}

async function runRound() {
// id:2d20 — productivity baseline: completions integrated BEFORE this round. The outer loop's
// drain detector keys on `produced` (completions THIS round), not units dispatched — a round
// that only hands back gated/too-large HARD units produces 0 and counts as dry, so the loop
// drains instead of re-dispatching the same un-doable items for MAX_ROUNDS.
const completedBefore = state.completed.length
// id:c919 — a round that only HANDS BACK can still CREATE work: a route:hard-split handback
// with a non-empty proposed_split makes handback-followup.py write those seams into ROADMAP.md
// as pickable [ROUTINE] units. Scoring such a round "dry" ended runs with stopReason:"drained"
// while the backlog had just GROWN (loderite relay-20260728-155041-20282: 4 seams filed, loop
// stopped, a fresh classify-repo.sh immediately reported verdict=execute). Track the round's
// work-creating handbacks so isDryRound can exclude them.
const handbacksBefore = state.handbacks.length
// id:5c00 — quota PRE-GATE: check quota BEFORE the discover-prelude + DISCOVER_SHARDS fan-out.
// A round that immediately quota-stops wastes N shard agents if the gate fires post-sharding.
// (Incident 2026-06-25, run relay-20260625-225111: 5 shards ~94k tokens spent before stop.)
// Uses the existing quotaGate() / last-known cache (no extra API refresh before round 1 shards).
if (!await quotaGateMemoized('sonnet')) {
  // quotaStopped was set to true by quotaGate; outer loop exits after this round.
  log('relay-loop: id:5c00 quota PRE-GATE fired — skipping discovery fan-out (quota at threshold before round start)')
  return { actionable: 0, produced: 0 }
}
// ── Phase 1: Discover ──

phase('Discover')

// id:9ed4/id:86a2 — PRELUDE: once-only global work (runId, the CONSUMING inject.sh take,
// claim.sh peek, the own-repo list + non-own skipped rollup, discover-sig, the STOP sentinel).
// MECHANIZED (id:86a2): the prelude never CLASSIFIES a repo and every step is already a shell
// helper, so the whole thing is ONE deterministic model:'bash' (```relay-mech) dispatch of
// discover-prelude.sh — no LLM judgment. discover-prelude.sh emits the PRELUDE_SCHEMA object on
// stdout (byte-identical shape to the old haiku return); parsePrelude() below accepts both the
// proxy's raw JSON string AND the exec harnesses' stubbed object. Then fan out parallel SHARD
// classifiers. STOP_PATH is threaded unquoted so a leading ~ is tilde-expanded by the shell.
const preludeRaw = await agent(
  'Run exactly this one command and report its stdout verbatim — it is the deterministic discovery PRELUDE (runId, own-repo enumeration + non-own skipped rollup, live-claim peek, the CONSUMING inject.sh take, discover-sig, and the operator STOP-sentinel check), emitting one JSON object on stdout:\n' +
  '```relay-mech\n' +
  // id:cd94 — RELAY_RUN_ID threads THIS pool's stable run id into the prelude so its STOP check
  // is run-scoped (`<STOP_PATH>.<runId>`) and a stop aimed at a different live pool cannot be
  // stolen. Empty on round 1 only if the front door skipped its id:c5ba mint, in which case the
  // prelude falls back to its own per-round mint and only the broadcast sentinel is seen.
  // routed:a923 — ONLY_REPO threads THIS pool's --only scope into the prelude's CONSUMING
  // `inject.sh take`, so a scoped pool consumes only its own repo's injections and leaves the
  // rest PENDING. Unset for an unscoped pool ⇒ global take, unchanged. Without it a scoped pool
  // drains the inbox globally and then cannot dispatch what it took — the unit is LOST (no
  // re-enqueue on handback). Same steal-once shape as the id:cd94 run-scoped STOP sentinel.
  `${state.runId ? `RELAY_RUN_ID=${state.runId} ` : ''}${INJECT_SCOPE ? `ONLY_REPO=${INJECT_SCOPE} ` : ''}STOP_PATH=${STOP_PATH} ~/.claude/skills/relay/scripts/discover-prelude.sh` +
  '\n```',
  { label: 'discover-prelude', phase: 'Discover', model: MECH_MODEL }
)
const prelude = parsePrelude(preludeRaw)

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
  // id:8c85 — publish the in-scope own-repo list ONTO the run state. It used to be a local here
  // only, i.e. out of scope at status-write / run-end time, so the accounting invariant had no
  // universe to check and a repo could fall out of every rendered section unnoticed.
  state.ownRepos = ownRepos.map(r => r.repo)
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
  // id:e87d — repos served from the discovery cache this round (verdict event cached:true below).
  const reusedRepoSet = new Set([...reusedUnits.map(u => u.repo), ...reusedIdle.map(r => r.repo)])
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
  // emits NO judgment: it runs scripts per repo and concatenates the JSON. classify-verdict never
  // emits AMBIGUOUS today, so the big LLM shard prompt is DELETED (the dormant AMBIGUOUS path is
  // surfaced loudly by discover-repo.sh) — DP1 "classifier primary, no post-flip comparator"
  // (meetings 2026-06-30-1523 / 2026-07-01-1904). The four JS-side backstops below
  // (id:000d/9973/ad74/365b) stay as belt-and-suspenders (meeting A2); deletion is gated on id:b50e.
  //
  // id:24ec — the discover-run SHARD is now MECHANIZED: the per-chunk reconcile+classify LOOP is
  // wrapped into ONE deterministic script, discover-chunk.sh, dispatched via a single model:'bash'
  // (```relay-mech) fence — ZERO agents, no LLM judgment. This is the id:c14d "multi-step-Haiku →
  // one fenced command" pattern applied to discovery, mirroring the discover-prelude flip (id:86a2),
  // un-gated by the id:a36e proxy fix. discover-chunk.sh reads the chunk JSON on stdin and, for
  // EACH repo, runs discover-repo.sh LIVE (reconcile-repo.sh side-effects + classify-repo.sh --emit
  // unit) and CONCATENATES {units,surfaced,skipped} in chunk order — the exact shape the old haiku
  // shard returned. runnerPrompt now BUILDS THAT FENCE (it is no longer an LLM prompt): it echoes
  // the chunk JSON into discover-chunk.sh via a single `echo … | discover-chunk.sh` pipeline the
  // mechanical proxy accepts. SCOPE (id:24ec): CASE B only — the full live discover-repo.sh path
  // (the SHIPPED default; the id:9d97 .timer producer is not installed by default). The CASE-A
  // content-address copy of the queue verdict (the id:7402 residual LLM read) is a GATED follow-on,
  // id:6eb3 — until it lands, the shard always runs live (correct, never a stale verdict; the queue
  // was only ever an optimization). SHARD_SCHEMA is RETAINED (below/above) as the documented output
  // contract discover-chunk.sh must emit; like id:86a2's PRELUDE_SCHEMA it is no longer passed to
  // agent() (a model:'bash' hop returns raw stdout, parsed by parseShard).
  const runnerPrompt = (chunk) =>
    'Run exactly this one command and report its stdout verbatim — it is the deterministic, MECHANICAL discovery SHARD (per-repo LIVE reconcile-repo.sh side-effects + classify-repo.sh verdict via discover-repo.sh, concatenated over the chunk), emitting one {units,surfaced,skipped} JSON object on stdout:\n' +
    '```relay-mech\n' +
    `echo '${JSON.stringify(chunk)}' | ~/.claude/skills/relay/scripts/discover-chunk.sh --runid ${prelude.runId} --live-claims "${liveClaimsCsv}"` +
    '\n```'
  // Only CHANGED repos pay for a runner agent (id:c3a6); a round where every repo is cached runs
  // zero runners and is still a valid round (shardOk seeded true below).
  if (changed.length) log(`relay-loop: id:24ec discover-run MECHANICAL shard dispatch (model:'bash') — reconcile+classify runs LIVE every round via discover-chunk.sh → discover-repo.sh per repo (ff-merge/uv.lock/reap-park/live-claims side-effects + deterministic classify verdict), concatenated in chunk order; CASE B only (the id:9d97 queue content-address copy is the gated follow-on id:6eb3). No LLM judgment — the shard is a single fenced command; the id:7402 residual LLM read is ELIMINATED for CASE B`)
  const shardResults = changed.length
    ? (await parallel(chunks.map((chunk) => () =>
        agent(runnerPrompt(chunk), { label: `discover-run:${chunk.length}`, phase: 'Classify', model: MECH_MODEL })
      ))).map(parseShard)
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
  units.push(...enforceInjectScope(prelude.injectedUnits || [], 'discovery prelude'))
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
  //
  // id:2799 — LANE-AWARE patch. The idle→execute PROMOTE case (below) still uses the
  // lane-blind top_intensive: an idle unit has no verdict-lane yet, so there is nothing to
  // match it against, and "there is open [INTENSIVE] work somewhere so this repo is not
  // really idle" is the pre-existing (unchanged) contract here. But the PATCH case — filling
  // in .intensive on a unit that ALREADY carries a real verdict (execute/hard, typically from
  // the deterministic classify-verdict.sh path) — must use ONLY the resource from THAT
  // verdict's own lane (top_intensive_routine for execute, top_intensive_hard for hard).
  // Patching from the lane-blind field here was the id:2799 regression: an unrelated [HARD]
  // [INTENSIVE — disk-io] item (id:3c9d) stamped .intensive onto every unrelated [ROUTINE]
  // execute unit, deferring the whole repo's routine backlog behind --intensive
  // (relay-20260818-152657-28729). A verdict outside {idle, execute, hard} is never patched
  // (mirrors the id:5ac6 invariant: intensive!="" => verdict in {execute,hard}).
  {
    const promotedIntensive = []
    for (const u of units) {
      if (u.injected) continue
      const top_intensive = u.top_intensive || ''
      if (u.verdict === 'idle') {
        if (!top_intensive) continue
        u.intensive = top_intensive
        u.verdict = 'execute'
        u.reason = `promoted by INTENSIVE-emit backstop (id:ad74): open [INTENSIVE — ${top_intensive}] item found but shard classified idle — intensive dispatch gated behind --allow-intensive. ${u.reason || ''}`.trim()
        promotedIntensive.push(`${u.repo}(idle→execute,${top_intensive})`)
        emitBackstopFire('ad74', u.repo, u.verdict)
      } else if (u.verdict === 'execute' || u.verdict === 'hard') {
        const laneVal = u.verdict === 'hard' ? (u.top_intensive_hard || '') : (u.top_intensive_routine || '')
        if (!u.intensive && laneVal) {
          u.intensive = laneVal
          promotedIntensive.push(`${u.repo}(intensive-field-patched,${laneVal})`)
        }
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
  if (shardOk) {
    // id:e87d — per-repo-per-round verdict event (seam 3 of id:c7dc): every own-repo appears
    // exactly once across units/surfaced/skipped this round (id:8c85 accounting invariant), so
    // one pushEvent('verdict', …) per entry across all three buckets covers every repo exactly
    // once — INCLUDING cache-reused repos (cached:true via reusedRepoSet, id:c3a6).
    for (const u of units) pushEvent('verdict', { repo: u.repo, round: round, verdict: u.verdict || '', priority_rank: u.priority_rank || 0, reason: u.reason || '', sig: u.sig || sigByRepo[u.repo] || '', cached: reusedRepoSet.has(u.repo) })
    for (const s of surfaced) pushEvent('verdict', { repo: s.repo, round: round, verdict: s.verdict || '', priority_rank: s.priority_rank || 0, reason: s.reason || '', sig: sigByRepo[s.repo] || '', cached: reusedRepoSet.has(s.repo) })
    for (const s of skipped) pushEvent('verdict', { repo: s.repo, round: round, verdict: s.verdict || '', priority_rank: s.priority_rank || 0, reason: s.reason || '', sig: sigByRepo[s.repo] || '', cached: reusedRepoSet.has(s.repo) })
    discovery = { runId: prelude.runId, ts: prelude.ts, units, surfaced, skipped }
  }
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
// id:8c85 — hoisted out of the block below so the units reach a RENDERED section. Previously
// `humanUnits` was block-scoped and died with the block: a human-verdict repo was pulled from
// `actionable` and added to NEITHER state.queued NOR state.skipped, so it appeared nowhere at
// all (class (c) — zkWhale, 2026-08-10). Mirrors the `mechanicalSurfaced` pattern below.
let humanSurfaced = []
{
  const nonHuman = []
  const humanUnits = []
  for (const u of actionable) {
    if (u.verdict === 'human') humanUnits.push(u)
    else nonHuman.push(u)
  }
  actionable = nonHuman
  humanSurfaced = humanUnits
  if (humanUnits.length) {
    log(`relay-loop: id:5eb3 — ${humanUnits.length} human-verdict unit(s) (surface-only backlog): filing to decision-queue mechanically: ${humanUnits.map(u => u.repo).join(', ')}`)
    // Fire all human-verdict filings concurrently (each is an independent repo, no cross-dep).
    await Promise.all(humanUnits.map(u =>
      agent(
        // id:6176 — mechanical hop (model:"bash"): the ```relay-mech fence carries the single
        // allowlisted relay-script command; mechanical-proxy.py extracts it, runs it locally, and
        // returns its stdout with ZERO upstream inference. Fire-and-forget (output only logged).
        // id:3557 audit: the resolved value is only passed to `log()` on catch, never parsed on
        // success, so the MECH-OK sentinel on a silent success is harmless.
        'Run EXACTLY this one command for the surface-only TODO backlog of repo ' + u.repo + ' and report its stdout verbatim (id:5eb3/id:47f1):\n' +
        '```relay-mech\n' +
        `~/.claude/skills/relay/scripts/file-surface-decisions.sh '${u.path}'` +
        '\n```',
        { label: `file-surface:${u.repo}`, phase: 'Support', model: MECH_MODEL }
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

// id:dc5b — C2 one-unit-per-repo-per-round: the LAST dispatch gate. `actionable` is now in
// final scheduling order (verdict-class priority, then the id:d530/income/standin tiebreakers)
// with all pool-inert verdicts (human/mechanical/intensive/hard-deferred) already pulled out.
// enforceOneUnitPerRepo keeps the FIRST unit per repo — the higher verdict-class one wins the
// slot — and DEFERS every later same-repo unit to the next round's fresh discovery (where the
// survivor has already integrated and moved the non-union ROADMAP.md forward). Deferring here,
// not dropping: the duplicates are surfaced LOUDLY in RELAY_STATUS Queued (never silently lost).
let repoDeferred = []
{
  const { plan, deferred } = enforceOneUnitPerRepo(actionable)
  actionable = plan
  repoDeferred = deferred
  if (repoDeferred.length) {
    log(`relay-loop: id:dc5b one-unit-per-repo — deferring ${repoDeferred.length} duplicate same-repo unit(s) to the next round (first-in-scheduling-order wins the slot; the duplicate would collide on the non-union ROADMAP.md at integrate): ${repoDeferred.map(u => `${u.repo}(${u.verdict})`).join(', ')}`)
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
  // human-verdict repos are deliberately NOT queued (they were handled by the surface-filer
  // above and are not dispatchable pool work); they are folded into state.skipped just below,
  // with their routing reason, so the operator sees them without confusing them with queued
  // work. Until id:8c85 this paragraph CLAIMED that placement while no code performed it, and
  // a human-verdict repo therefore reached no section at all.
  // mechanical-verdict repos (id:7616): POOL-INERT — surfaced here in Queued (visible, never
  // dispatched by the LLM pool; a host daemon dispatches them, A3, gated). Mirrors the `human`
  // contract: pulled from `actionable` above, no child spawned, absent from PHASE_BY_VERDICT.
  ...mechanicalSurfaced.map(u => ({ repo: u.repo, verdict: `mechanical (pool-inert: pure-compute work for the host daemon, A3-gated; never dispatched by the LLM pool)` })),
  // id:dc5b — same-repo duplicates deferred by the one-unit-per-repo gate: visible in Queued
  // so the operator sees what was held for the next round (never silently dropped).
  ...repoDeferred.map(u => ({ repo: u.repo, verdict: `${u.verdict} (deferred: id:dc5b one-unit-per-repo — another unit for this repo dispatched this round; re-discovered next round after it integrates)` })),
]
const humanSkipped = humanSurfaced.map(u => ({ repo: u.repo, reason: `human (surface-only backlog — filing dispatched to the decision queue; not dispatchable pool work, id:5eb3)` }))   // id:8c85
state.surfaced = buildSurfacedView(discovery.surfaced)
state.skipped = (discovery.skipped || []).map(s => ({ repo: s.repo, reason: s.reason })).concat(humanSkipped)   // id:be62 + id:8c85

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
// id:8123 — CHAIN-END re-ask bookkeeping. At most ONE chain-end review re-ask per repo per
// round: a re-asked review can itself re-chain an execute (review→execute below), whose chain
// end would re-ask again — this Set is the explicit bound on that ping-pong, and it is also the
// NAMED ESCAPE hatch: when the re-ask cannot be answered (mechanical hop error, apex/tier
// outage) the repo is SURFACED-AND-SKIPPED for the round (state.queued + a loud log) rather
// than the loop halting or silently dropping the audit. Cleared per round with the queue.
const chainEndReasked = new Set()
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

// id:923b — per-unit identity key (children-of:1f4f D2/A3, ratified 2026-07-31 `/relay human`).
// Two same-repo units in the same run used to collide on {repo,verdict} alone (worktree path,
// inFlight sweep). Key shape is itemId x attempt: a bare itemId collides on retries and on the
// open id:1b1a duplicate-line bug; a bare nonce would orphan pre-crash worktrees from id:7809's
// reconcile view. MUST stay a single-line pure arrow with NO closure over module state — the
// Workflow sandbox extracts it textually to test it standalone (tests/test_unit_identity_key_923b.sh).
const unitKey = (u) => `${u.verdict}-${u.itemId || 'repo'}-${u.attempt || 0}`

// Deterministic worktree path + branch for a unit — the child creates them, and the
// API-error recovery path (runUnit catch / integrate null-guard) needs the same names
// to find a failed child's partial work instead of orphaning it. Keyed by unitKey (not
// bare repo+verdict) so two same-repo units in one run never compute the same path/branch;
// the runId prefix is preserved so reconcile-repo.sh's "skip worktrees from THIS run"
// prefix match (`bn == runid*`) keeps working unchanged.
const worktreePathFor = (unit) => `~/.cache/relay/worktrees/${unit.repo}/${state.runId}-${unitKey({ verdict: unit.verdict, itemId: dispatchItemFor(unit), attempt: unit.attempt || 0 })}`
const branchFor = (unit) => `relay/${state.runId}-${unitKey({ verdict: unit.verdict, itemId: dispatchItemFor(unit), attempt: unit.attempt || 0 })}`

// id:b09e — NAME the item the execute child must work, instead of handing it the whole ledger.
// `unit.actionable_routine_ids` is emitted by classify-repo.sh: the ids BEHIND the
// actionable_routine_open count, in ROADMAP file order, filtered by the SAME predicate the
// count uses (gated 🚧 / @manual / non-[ROUTINE] / closed items never appear). SELECTION RULE
// (deterministic, spec-required): the FIRST id in that order — ROADMAP.md is priority-ordered
// top-down by convention, and file order is stable for a given ROADMAP, so two runs on the same
// ledger name the same item. "" entries (actionable items carrying no id) are unnameable and
// skipped. A user-injected item (id:baf1) always outranks the classifier's pick.
// FAIL-OPEN: no usable id (older queue entry, injected unit, id-less ROADMAP) ⇒ the historical
// plural instruction is used unchanged, so this can only ever narrow the child's search, never
// break dispatch.
// id:b09e — SUBTRACT orphan-suppressed ids. discover-repo.sh appends "orphan-parked (id:X) —
// reconcile-first, do NOT work id:X" to unit.reason AND publishes the set as
// unit.suppressed_item_ids. Both strings land in the same child prompt, so naming a suppressed
// item would imperatively override the very instruction next to it — benign before b09e (the
// plural instruction left the child free to obey the reason), a live conflict after it.
// Read the FIELD, never the prose. Case-normalised: classify-repo.sh accepts [0-9a-fA-F] while
// this filter was lowercase-only, so an uppercase-hex id was counted but silently unnameable.
const namedItemsFor = (unit) => {
  const suppressed = new Set(
    (Array.isArray(unit.suppressed_item_ids) ? unit.suppressed_item_ids : [])
      .filter((x) => typeof x === 'string')
      .map((x) => x.toLowerCase()),
  )
  return (Array.isArray(unit.actionable_routine_ids) ? unit.actionable_routine_ids : [])
    .filter((x) => typeof x === 'string' && /^[0-9a-fA-F]{4}$/.test(x))
    .map((x) => x.toLowerCase())
    .filter((x) => !suppressed.has(x))
}

// id:7517 (routed:2d94) — the HARD-lane sibling of namedItemsFor. `unit.open_hard_pool_ids` is
// emitted by gather-repo-state.sh's open_hard_pool walk: the ids BEHIND the count, in ROADMAP
// file order, filtered by the SAME predicate the count uses (parked sections, @container,
// @owner-gated, typed gated-on: edges, 🚧, blocked*, and the spent recurring audit never
// appear), with BOTH the retired "[HARD — pool]" and the new bare "[HARD]" spelling normalized
// by roadmap_primary_lane. Handing this to the child is the whole point: the previous brief told
// it to "Pick the TOP open item tagged [HARD — pool] in ROADMAP.md", i.e. to RE-DERIVE the
// enumeration by raw grep on the retired spelling — loderite run relay-20260814-133435-24323
// found 0 that way and refused 5 real items. Mechanize-first: the resolved list already exists;
// re-deriving it is the defect.
// Orphan-suppressed ids are subtracted for the same reason namedItemsFor subtracts them (id:b09e):
// unit.reason carries a "do NOT work id:X" instruction into the same prompt, so naming a
// suppressed item would imperatively contradict the text next to it.
// FAIL-OPEN: an empty/absent list ⇒ the historical survey instruction is used unchanged.
const hardPoolIdsFor = (unit) => {
  const suppressed = new Set(
    (Array.isArray(unit.suppressed_item_ids) ? unit.suppressed_item_ids : [])
      .filter((x) => typeof x === 'string')
      .map((x) => x.toLowerCase()),
  )
  return (Array.isArray(unit.open_hard_pool_ids) ? unit.open_hard_pool_ids : [])
    .filter((x) => typeof x === 'string' && /^[0-9a-fA-F]{4}$/.test(x))
    .map((x) => x.toLowerCase())
    .filter((x) => !suppressed.has(x))
}

// Shared tail of the execute instruction — identical in the named and the fallback branch, so
// the two can never drift on the SIZE-OUT contract.
const EXECUTE_SIZEOUT = 'Stop at a natural boundary; never start an item you cannot finish. SIZE-OUT rule (id:08c0): if a [ROUTINE] item is too large to land green in one session and you cannot partially advance it, do NOT silently leave it open — return a structured handback (contract_met=false, handback_item=<id>, route=hard-split or decision-gate, gate_reason). Soft notes (friction:/BLOCKED:) are not sufficient; the integrator\'s durable follow-up (id:3801) reads only the structured fields. Leave the worktree COMPLETELY CLEAN on a size-out (no commit) — same clean-worktree discipline as the hard-verdict id:8b1f.'

// The single item this unit dispatches on, "" when none is known (fail-open to the old
// plural instruction). An injected --item always wins over the classifier's pick.
const dispatchItemFor = (unit) => unit.inject_item || namedItemsFor(unit)[0] || ''

// id:8af2 — SURFACE the choice. b09e made the pick deterministic but SILENT: an execute unit
// takes actionable_routine_ids[0] and no surface ever said which id that was, nor how many were
// eligible. On 2026-07-31 this repo had 21 actionable [ROUTINE] items with the primary cadence
// fix mid-list, so the pool would have worked a different item and NOTHING anywhere would have
// recorded it — the mismatch was invisible until a human read the classifier JSON by hand.
// VISIBILITY ONLY: this helper does not choose, it REPORTS dispatchItemFor's existing choice.
// The selection rule (head of namedItemsFor, injection overriding) is deliberately unchanged —
// override mechanisms already exist (/relay inject --item, --priority).
//   item          — the id actually dispatched ('' when none could be named; fail-open).
//   itemRank      — 1-based position of that id in the eligible order; 0 when the id is NOT in
//                   that order (a user-injected --item), so "1 of 21" is never faked.
//   eligibleCount — size of the eligible set AFTER orphan-suppression subtraction, i.e. exactly
//                   the set selection ranges over. That count is what makes a mid-list primary
//                   fix obvious at a glance; the id alone is not enough.
const dispatchChoiceFor = (unit) => {
  const eligible = namedItemsFor(unit)
  const item = dispatchItemFor(unit)
  const idx = eligible.indexOf(item)
  return { item, itemRank: idx >= 0 ? idx + 1 : 0, eligibleCount: eligible.length }
}

// Returns the NAMED execute instruction, or '' when no item could be named — the caller then
// falls back INLINE to the historical plural instruction (kept on the template line so the
// fallback text and its size-out wiring stay visible at the dispatch site).
function executeNamedInstruction(unit) {
  const named = namedItemsFor(unit)
  const primary = dispatchItemFor(unit)
  if (!primary) return ''
  const alts = named.filter((i) => i !== primary).slice(0, 2)
  return 'Work specifically the ROADMAP.md item tagged <!-- id:' + primary + ' --> under the executor contract — the classifier ALREADY selected it for you (id:b09e), so do NOT survey ROADMAP.md to find your work. '
    + 'Go straight to it: `grep -n "id:' + primary + '" ROADMAP.md` gives the line, then read only that item\'s own block (the bullet plus its indented sub-bullets). Do NOT read the whole ROADMAP.md — on a large ledger that alone exhausts the context window and kills the child mid-survey; that is the exact failure this naming exists to prevent. '
    + (alts.length ? 'ONLY if that item turns out to be already done or genuinely unworkable, the next classifier-actionable candidates are ' + alts.map((i) => '<!-- id:' + i + ' -->').join(' then ') + ' — never range beyond those. ' : 'It is the only executor-actionable [ROUTINE] item the classifier found; if it is unworkable, hand back rather than looking for other work. ')
    + EXECUTE_SIZEOUT
}

// id:7517 (routed:2d94) — the OPENING of the HARD-execute brief: HAND the child the resolved
// pool-lane list and FORBID re-derivation. The retired text (it told the child to pick the top
// open checkbox item carrying the OLD venue-keyed pool tag) made re-deriving the enumeration the
// child's job, on a spelling the lane-vocab migration had retired — loderite run
// relay-20260814-133435-24323 found 0 that way and refused 5 real bare-[HARD] items, wasting
// the whole dispatch round on a repo that had work. Returns the naming form when gather
// resolved ids, else a DUAL-VOCAB fallback survey instruction (FAIL-OPEN: an older queue entry
// or an injected unit carries no list, and must still be able to work).
function hardNamedInstruction(unit) {
  const ids = hardPoolIdsFor(unit)
  const NO_REDERIVE = 'That list is AUTHORITATIVE and already resolved by gather-repo-state.sh from the SAME predicate that counted them — do NOT re-derive it by grepping ROADMAP.md for a lane tag. The lane vocabulary is in a DUAL-VOCAB window: the pool lane is spelled BOTH as a bare "[HARD]" and as the retired "[HARD — pool]", so a grep for either spelling alone silently misses real items (id:7517/routed:2d94). '
  if (!ids.length) {
    return 'You are an Opus-apex HARD-execute child (id:da26). The classifier resolved NO pool-lane id list for this unit, so survey ROADMAP.md yourself and pick the TOP open "- [ ]" item on the POOL lane — that is an item tagged with a bare "[HARD]" OR with the retired "[HARD — pool]" spelling; BOTH are the same lane and you must accept either. Skip items that are parked, @container, @owner-gated, 🚧, BLOCKED, or gated-on an open id. SIZE it first. '
  }
  const rest = ids.slice(1, 3)
  return 'You are an Opus-apex HARD-execute child (id:da26). The pool-lane queue for this repo is ALREADY RESOLVED for you (id:7517) — the open, dispatchable pool-lane items, in ROADMAP file order, are: '
    + ids.map((i) => '<!-- id:' + i + ' -->').join(', ') + '. Work the FIRST one, <!-- id:' + ids[0] + ' -->: `grep -n "id:' + ids[0] + '" ROADMAP.md` gives the line, then read only that item\'s own block (the bullet plus its indented sub-bullets). Do NOT read the whole ROADMAP.md. '
    + NO_REDERIVE
    + 'Because that list is non-empty, you MUST NOT hand back "no open [HARD] item / nothing dispatchable" — if you believe every listed id is unworkable, say so per id in `handback` and return them in `considered_ids` (id:bfbf). '
    + (rest.length ? 'ONLY if the first item is already done or genuinely unworkable, fall through to ' + rest.map((i) => '<!-- id:' + i + ' -->').join(' then ') + ' — never range beyond the resolved list. ' : '')
    + 'SIZE it first. '
}

// id:4f9b — inline copies of relay/scripts/prompt-size-gate.mjs (keep byte-equivalent; the
// Workflow sandbox cannot import, and a structural test pins the wiring). Pre-dispatch prompt
// sizing: refuse to dispatch a child into a ledger that cannot fit, and say WHY, instead of
// letting it die with a bare `Prompt is too long` that surfaces as the generic terminal-failure
// handback (and, on 2026-08-01, as `## Blocked / HANDBACKs _(none)_` — a false clean).
// See that module for the budget derivation and the fail-open rationale.
const CHARS_PER_TOKEN = 4
const DISPATCH_TOKEN_BUDGET = 100000
const FIXED_OVERHEAD_TOKENS = 12000
// id:b018 — BOTH ledgers are counted (ROADMAP.md + TODO.md), not just the ROADMAP: sizing one
// under-counted by ~50% and let loderite through by 326 tok before it died anyway.
function estimateDispatchTokens(promptChars, roadmapBytes, todoBytes) {
  const n = (v) => (Number.isFinite(v) && v > 0 ? v : 0)
  const bytes = n(promptChars) + n(roadmapBytes) + n(todoBytes)
  return Math.round(bytes / CHARS_PER_TOKEN) + FIXED_OVERHEAD_TOKENS
}
function oversizeDispatchReason(unit, promptChars, budget) {
  const u = unit || {}
  const cap = Number.isFinite(budget) && budget > 0 ? budget : DISPATCH_TOKEN_BUDGET
  const n = (v) => (Number.isFinite(v) && v > 0 ? v : 0)
  const roadmapBytes = n(u.roadmap_bytes)
  const todoBytes = n(u.todo_bytes)
  if (!roadmapBytes && !todoBytes) return ''   // unmeasured ⇒ fail OPEN, never block on missing data
  const est = estimateDispatchTokens(promptChars, roadmapBytes, todoBytes)
  if (est <= cap) return ''
  const repoPath = u.path || '<repo-path>'
  const measured = [
    { name: 'ROADMAP.md', bytes: roadmapBytes, fix: '~/.claude/skills/relay/scripts/roadmap-archive.sh ' + repoPath },
    { name: 'TODO.md', bytes: todoBytes, fix: '~/.claude/skills/todo-update/archive-done.sh ' + repoPath + '/TODO.md' },
  ].filter((l) => l.bytes > 0)
  // Name the ledgers that MATERIALLY drive the overrun (>= a quarter of the cap on their own);
  // if none does individually, the overrun is the aggregate, so name them all.
  const material = measured.filter((l) => l.bytes / CHARS_PER_TOKEN >= cap / 4)
  const named = material.length ? material : measured
  const causes = named.map((l) => `${l.name} is too large — ${l.bytes} bytes (~${Math.round(l.bytes / CHARS_PER_TOKEN)} tok of the estimate)`).join('; ')
  const remedies = named.map((l) => '`' + l.fix + '`').join(' and ')
  return `prompt-size gate (id:4f9b/id:b018): NOT dispatched — the assembled ${u.verdict || 'child'} prompt for ${u.repo || '(repo)'} is ~${est} tok, over the ${cap} tok dispatch budget, so the child would die with "Prompt is too long" instead of doing work. CAUSE: ${causes}. REMEDY: run ${remedies} to move the done \`- [x]\` items into the matching archive file, commit, and re-run the pool. This repo is skipped, not failed: no worktree was created and no work was lost.`
}

function unitPrompt(unit) {
  const wt = worktreePathFor(unit)
  const branch = branchFor(unit)
  return `You are a relay ${unit.verdict.toUpperCase()} child for the repo ${unit.repo}.

FIRST acquire the cross-session repo lease (id:ebfb): run ~/.claude/skills/relay/scripts/claim.sh acquire ${unit.repo} --run ${state.runId} --mode ${unit.verdict} --worktree ${wt}. (The --worktree anchors id:7570 long-child liveness: a claim whose worktree has commits beyond main stays held past the TTL, so a >30-min child isn't stolen mid-work.) If it exits NON-ZERO, another live relay run/session already holds this repo — STOP IMMEDIATELY: do NOT create a worktree, do NOT do any work, and return contract_met=false with handback="claimed by another relay run (cross-session lease id:ebfb): " plus the holder JSON it printed to stderr. The supervisor releases the lease at integration, so do not release it yourself. Only if acquire SUCCEEDS, continue:
${unit.intensive ? '\nThis is an [INTENSIVE — ' + unit.intensive + '] unit (id:8d52): ALSO acquire the exclusive RESOURCE lease before any heavy work — ~/.claude/skills/relay/scripts/claim.sh acquire resource:' + unit.intensive + ' --run ' + state.runId + ' --mode intensive. If it exits non-zero (another relay run is using ' + unit.intensive + '), STOP: return contract_met=false, handback="resource ' + unit.intensive + ' busy (another relay run)". The supervisor releases it at integration.\n' : ''}
Your worktree ${wt} on branch ${branch} was already created for you before dispatch (id:34b7) — you were not given the main-checkout path and never need it. Work EXCLUSIVELY in that worktree. Classifier verdict reason: ${unit.reason}. Last checkpoint tag: ${unit.lastCkpt || '(none)'}.

${unit.injected ? 'This is a USER-INJECTED high-priority task (id:baf1). ' + (unit.inject_item ? 'Work specifically the ROADMAP.md item tagged <!-- id:' + unit.inject_item + ' -->. ' : '') + (unit.inject_prompt ? 'User instruction: ' + unit.inject_prompt + ' ' : '') + 'Otherwise follow the verdict procedure below.\n' : ''}SKILL COUNTERMAND (id:9eb7 — overrides this repo's CLAUDE.md "## Relay contract" pointer): do NOT invoke the Skill tool for \`relay\` — do NOT run Skill(relay, executor), whatever that repo's CLAUDE.md tells you. The Skill tool IGNORES the \`executor\` arg and injects the ~26.4k-token ORCHESTRATOR SKILL.md (measured: 26,394 tok, identical in both children of run relay-20260728-112417-3898) — which then tells you to ignore almost all of it. The executor contract is NOT in that payload. Read the contract file DIRECTLY instead (~5.5k): ~/.claude/skills/relay/references/executor-contract.md — that is your contract, follow its rules exactly.

Procedure: follow ${refDoc(unit.verdict)} exactly. Read ~/.claude/skills/relay/references/conventions.md for environment facts and relay invariants before starting.
${unit.verdict === 'execute' ? (executeNamedInstruction(unit) || 'Work the open [ROUTINE] items in ROADMAP.md under the executor contract. ' + EXECUTE_SIZEOUT) : ''}
${unit.verdict === 'hard' ? hardNamedInstruction(unit) + 'Model your discipline on handoff.md C5 "only if small enough to finish safely": only implement the item if you can finish it cleanly and green within this turn — full red-green-refactor, verify-before-merge. If it is too large, contains nested/multi-session scope, or you cannot make the test suite green safely, do NOT half-do it: set contract_met=false and explain the sizing in handback. CRITICAL (id:8b1f) — a SIZE-OUT / GATED refusal (you decided NOT to start) must leave the worktree COMPLETELY CLEAN: make NO commit, and do NOT write the rationale into RELAY_LOG.md / ROADMAP.md / REVIEW_ME.md in the worktree. The rationale goes ONLY in the returned `handback` field. Reason: the integrator never merges a handback, so ANY commit you make on a refusal strands forever as an orphan worktree (the bug behind id:a4e9); a CLEAN worktree is auto-reaped (id:3ac8). The "write a HANDBACK paragraph to RELAY_LOG.md and commit" step in handoff.md C5 applies ONLY to a genuine mid-item CUTOFF where you already committed real work and need resume provenance — NOT to a pre-start sizing refusal (the item stays open for a manual/next-turn strong session). When you DO finish: do NOT tick the item\'s checkbox yourself (executor-contract v12, id:5b12) — return the item id in worked_ids and the DRIVER ticks the box at integrate; append its done-note, commit in the worktree, and make the full test suite green. Never manufacture a pass. Work ONE bounded HARD item only — never start a second.' : ''}
${unit.verdict === 'handoff' ? 'Run checkpoints C1-C4. C5 (HARD execution) only if the top HARD item is small enough to finish safely; otherwise leave it specced.' : ''}
${unit.verdict === 'review' ? 'Run the full trust-but-verify procedure including the test-integrity audit. Single-id-two-views (D2): when you promote a ROADMAP item for work TODO.md already tracks under an <!-- id:XXXX -->, REUSE that token; mint a fresh one via ~/.claude/skills/meeting/append.sh new-ids N ' + wt + ' ONLY for genuinely new work — NEVER invent tokens, and never duplicate-id already-tracked work. When you close a ROADMAP item whose id also lives in TODO.md, tick the TODO line too. Reverse-handoff (review.md §5b): qualify+size any unqualified TODO/ROADMAP items added by /meeting or manual edits since the last checkpoint (mini-handoff) — reuse their id. After re-deriving the roadmap, set routine_open = the number of OPEN (unticked) [ROUTINE] items remaining — the supervisor uses it to re-enqueue an execute unit this same pool.' : ''}

Hard rules: commit in the worktree as you go; NEVER push; NEVER tag; NEVER run git-diary-workflow or todo-update; never prompt the user. If you cannot meet the contract, set contract_met=false and explain in handback.

Return: contract_met, branch ("${branch}"), worktree ("${wt}"), summary (one line for the checkpoint tag message), review_me_count (open REVIEW_ME.md boxes you wrote, else 0), diary_fragment (one paragraph), handback ("" if none), routine_open (review units: open [ROUTINE] count after re-derivation; 0 for handoff/execute), worked_ids (id:de69 — array of the ROADMAP/TODO 4-hex id(s) you actually worked this unit: for execute, the item id(s) you closed/advanced; for hard, the single [HARD] item id you executed; for handoff, the id(s) you promoted/created; for review, the ids you verified-green or reopened; [] if none — these are the tokens in the commits/ROADMAP you touched, NOT invented).${unit.verdict === 'review' ? ' ALSO (review units only, id:3826 — feeds the gaming-flag rate logger; see review.md §6 return schema): verified_green (array of ROADMAP ids you confirmed genuinely green this review, [] if none), gaming_flags (array of "<id>: <reason>" strings for every DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT or judgment flag you raised, [] if none), reopened (array of ROADMAP ids you reopened, [] if none).' : ''}

IF YOU HAND BACK CLAIMING THERE IS NOTHING DISPATCHABLE (id:bfbf) — no open item you could work — you MUST set considered_ids = the array of every 4-hex ROADMAP id you actually LOOKED AT and rejected, and say per id in \`handback\` WHY it was rejected. That enumeration is the EVIDENCE for the claim: a bare "nothing to do" is indistinguishable from a child that looked in the wrong place, and the supervisor cross-checks considered_ids against its own deterministic open-item count. An empty or missing considered_ids with a nonzero count raises a LOUD alarm and is NOT accepted as a clean drain, so returning the list is how a genuine empty queue gets believed.

ON A HANDBACK (contract_met=false), ALSO classify it so the integrator records it DURABLY in ROADMAP.md and the pool stops re-dispatching the same un-doable item (id:3801): set handback_item (the 4-hex ROADMAP id you handed back, e.g. the [HARD] item you sized out), and route = one of "decision-gate" (needs a /meeting design decision before anyone can build it), "hard-split" (too large for one turn but decomposable into smaller pickable seams), "human" (needs a manual human action / /relay human), or "none" (transient/other failure — no durable action). Set gate_reason to ONE short line for the inline ROADMAP note. For route="hard-split" ONLY, set proposed_split = an ordered array of seam units [{title, tier:"HARD"|"ROUTINE", dep:"<4-hex id of the seam this one depends on, omit if independent>", id:"<reuse an existing 4-hex token if the seam already has one in the ROADMAP/meeting-note, else OMIT to let the integrator mint one>", acceptance:"<observable done-behaviour for THIS seam>", done_check:"<exact command/test that proves this seam done>", file:"<the file(s)/function(s) this seam concerns, so the executor goes straight to the work>"}] — acceptance/done_check/file are REQUIRED per seam (id:44a1); a seam missing any of them is rejected and written nowhere. On a clean success, omit these (route defaults to none).`
}

// Auto-resume after an API-error / terminal child failure (handoff only — its
// per-checkpoint commits make it resumable; review/execute are single-shot and instead
// surface as recoverable handbacks). The resume child inspects the worktree the failed
// child already created and continues from its last committed checkpoint to completion,
// committing per stage so a re-failure loses at most one more stage.
function resumePrompt(unit) {
  const wt = worktreePathFor(unit)
  const branch = branchFor(unit)
  return `You are RESUMING an interrupted relay HANDOFF for repo ${unit.repo}. A prior child was killed (API error / timeout) mid-handoff.

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
  // id:6176 — mechanical hop (model:"bash"): the ```relay-mech fence carries quota-stop.sh; the
  // proxy runs it locally and returns its RAW STDOUT. quota-stop.sh conveys its verdict via EXIT
  // CODE (0 proceed / 1 exhausted / 2 cache-unreadable / 3 extrapolated-stop) and logs the crossed
  // bucket to STDERR — so mechanical-proxy.py returns '' on exit 0, or 'MECH-ERROR exit=<N>\n<stderr>'
  // on any non-zero exit. parseQuotaMechResult reconstructs {exitCode, crossedBucket, buckets} from
  // that raw shape (the consumer rewire off the old QUOTA_SCHEMA-typed return).
  // The command sits on its own template-literal line ending exactly at `--wall 0` (the id:5f09
  // install-manifest invocation contract: no bare positional after the three flags); the fence
  // markers are escaped backticks so the literal command line stays clean for that grep.
  const raw = await agent(
    `Run this command and report its stdout verbatim (a quota threshold check; its exit code is the verdict):
\`\`\`relay-mech
${runIdEnv}${thresholdEnv}~/.claude/skills/relay/scripts/quota-stop.sh --tier ${tier} --agents ${totalDispatched} --wall 0
\`\`\``,
    { label: `quota:${tier}`, phase: 'Quota', model: MECH_MODEL }
  )
  const v = parseQuotaMechResult(raw, tier)
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

// id:e9fa — memo the quota verdict PER ROUND so runUnit doesn't issue its own mechanical
// round-trip for every non-injected dispatch just to re-read a cache that barely changes
// within one round (quotaGate is awaited BOTH pre-shard once/round at ~981 AND per-unit here
// before every non-injected dispatch — N serialized mechanical round-trips/round for what is
// usually the same answer). quotaGate() (above) stays the single AUTHORITATIVE check — both
// call sites now go through THIS wrapper instead of calling quotaGate() directly, so the
// pre-shard call (always the first of the round, hence always a memo MISS) refreshes the
// memo as a side effect, and every runUnit call for the rest of that round reuses it with
// NO further dispatch. quotaGate()'s own dispatch-count throttle (QUOTA_CHECK_EVERY,
// lastQuotaOk) still sits underneath, unchanged — this is an ADDITIONAL layer, not a
// replacement.
//
// A real wall-clock TTL (originally proposed as ~45s) is NOT implementable here: the
// Workflow sandbox FORBIDS Date.now()/new Date() (ShimDate throws to keep runs
// deterministic — see the QUOTA_CHECK_EVERY comment near QUOTA_MEMO_TTL_ROUNDS, and id:2031's
// inline note for prior art hitting the same wall). The closest correctness-preserving proxy
// this sandbox can actually observe is the ROUND boundary: `round` is a plain incrementing
// counter (bumped once per runRound() call), not a clock read. This is coarser than a true
// 45s TTL — a long round holds the memo the whole round; a short round refreshes sooner than
// 45s would have — but it never weakens the hard-stop guarantee: `quotaStopped` is sticky and
// checked FIRST on every call (memoized or not), so a tripped stop short-circuits instantly
// regardless of memo state, and a real STOP verdict written into the memo is honored
// immediately by every subsequent memoized caller in the same round.
//
// INTERIM STOPGAP, not the structural fix — the off-Workflow drain-driver (id:cd7a/65f9/2b23)
// runs with real host-side clock access and should replace this round-keyed proxy with a
// genuine time-based memo when it lands.
async function quotaGateMemoized(tier) {
  if (quotaStopped) return false
  const memo = quotaMemo[tier]
  if (memo && (round - memo.round) < QUOTA_MEMO_TTL_ROUNDS) return memo.verdict
  const ok = await quotaGate(tier)
  quotaMemo[tier] = { verdict: ok, round }
  return ok
}

// id:4df8 — force-free retirement of a CONTEXT-DEATH worktree (null-report handback), via the
// SAME shared helper the integrator + reconcile-repo.sh already use (worktree-retire.sh,
// id:373e) — reusing the existing D1 park/reap machinery rather than writing new disposal
// logic. Factored OUT of integrate() as its own top-level function (mirrors releaseLease() /
// beatHeartbeat() / stopHeartbeat() above) rather than an inline `await agent(...)` in
// integrate()'s body: the id:c563 structural invariant (test_relay_integrator_noop_guard.sh)
// asserts NO agent() call precedes the Sonnet integrator dispatch inside integrate() — that
// invariant is about not wastefully spawning the EXPENSIVE Sonnet integrator on a no-op path,
// and still holds (this dispatches a near-free MECHANICAL model:'bash'/MECH_MODEL hop, id:6176,
// never Sonnet); keeping it a separate named call avoids re-litigating that invariant's exact
// text-matching for an unrelated, cheap addition.
// Without this, worktreePathFor(unit) is RUN-ID-SCOPED
// (~/.cache/relay/worktrees/<repo>/<runId>-<verdict>) and a relaunch mints a NEW runId and never
// looks there; worse, next round's reconcile-repo.sh reap/park (id:ebfb/3ac8/689c) might not even
// run for this repo if the content-addressed discovery sig (id:c3a6) happens to hit the cache.
// A worktree with committed work ends up a reachable relay/orphan/<bn> ref (id:a4e9 — refs ARE
// the registry); a clean, commitless one is reaped with no ref (do not litter); a
// dirty-but-uncommitted one is surfaced and left on disk (id:373e force-free discipline) —
// worktree-retire.sh already implements all three outcomes, untouched here.
// retireFlags: extra worktree-retire.sh flags for THIS call site (kept as a parameter, not
// hardcoded in the shared function body, so the literal flag text lives at the call site that
// decides to pass it — id:f272's caller-wiring check greps the null-report branch's own source
// for the flag; a flag buried only inside this shared helper would not be visible there).
async function retireDeadWorktree(unit, retireFlags = '') {
  const wt = worktreePathFor(unit)
  const branch = branchFor(unit)
  try {
    const r = await agent(
      // id:ba7e — interpolating unit.path here is a DELIBERATE, justified exception to id:34b7's
      // no-main-checkout rule: this is a PARENT-side mechanical hop, not a child prompt.
      // worktree-retire.sh's first argument IS the canonical repo (`git -C <repo> worktree
      // remove/prune` + the orphan-ref write must run against the real checkout, never the
      // worktree being retired — which by then may not exist). No child ever sees this string.
      `Run exactly this one command and report its stdout verbatim (force-free retirement of a context-death worktree, id:4df8/373e/f272 — NEVER pass --force/-D yourself, this helper never does):\n` +
      '```relay-mech\n' +
      `~/.claude/skills/relay/scripts/worktree-retire.sh ${unit.path} ${wt} ${branch}${retireFlags ? ' ' + retireFlags : ''}` +
      '\n```',
      { label: `retire-death:${unit.repo}`, phase: 'Integrate', model: MECH_MODEL }
    )
    return (r && (r.stdout || r.output)) || ''
  } catch (err) {
    log(`relay-loop: id:4df8 context-death retire failed for ${unit.repo} (non-fatal — next round's reconcile-repo.sh remains a backstop, though its sig-cache may skip it): ${err}`)
    return ''
  }
}

async function integrate(unit, report) {
  if (!report) {
    // Child failed terminally (and auto-resume, for handoffs, didn't recover). Record a
    // RECOVERABLE handback with the deterministic worktree path + resume hint, never an
    // orphan with worktreePath '-'. Any per-checkpoint commits survive on disk for a
    // manual/next-turn resume (handoff: re-dispatch reads them; see handoff.md §Resuming).
    //
    // id:4df8 — a null-report handback is a CONTEXT-DEATH: park/reap the worktree HERE (via
    // retireDeadWorktree(), which reuses the D1 worktree-retire.sh / relay/orphan/* machinery)
    // rather than leaving it to a relaunch that would never look at this run-id-scoped path.
    const branch = branchFor(unit)
    const bn = `${state.runId}-${unit.verdict}`
    const orphanRef = `relay/orphan/${bn}`
    // id:f272 — a context-death worktree may be DIRTY (uncommitted residue), not just
    // committed-but-unmerged; --commit-residue lets worktree-retire.sh commit-and-park that
    // residue instead of leaving it surfaced-and-stranded for a human to notice by chance
    // (the exact incident this item records: run relay-20260729-111723-7520's 47 lines).
    const retireNote = await retireDeadWorktree(unit, '--commit-residue')
    const terminalFailReason = `child agent failed/skipped (API error or terminal failure); ${unit.verdict === 'handoff' ? 'auto-resume did not complete' : 'no auto-resume for ' + unit.verdict}. Any committed checkpoints are retired force-free (id:4df8/373e): if the worktree carried commits they are now parked as a reachable ${orphanRef} (verify: git -C ${unit.path} show-ref --verify refs/heads/${orphanRef}); if it was clean it was reaped; if it was dirty-but-uncommitted it is surfaced and left on disk at ${worktreePathFor(unit)} for a supervised reconcile. Do NOT rely on the run-id-scoped path ${worktreePathFor(unit)} alone — a relaunch never looks there.${retireNote ? ' retire-helper said: ' + retireNote : ''}`
    state.handbacks.push({
      repo: unit.repo,
      reason: terminalFailReason,
      worktreePath: worktreePathFor(unit),
    })
    pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason: terminalFailReason })
    emittedHandbackEvents.push({ repo: unit.repo, reason: terminalFailReason })  // id:4a46 — invariant backstop
    // id:e3b7 (in-sandbox half of id:61fa) — a null-report handback means the child died
    // terminally (API error / context death) with NO report at all, which today produces NO
    // durable ROADMAP action (unlike an item-level handback via handback-followup.py/id:3801).
    // Without a stamp, the discovery signature cache can re-dispatch the SAME repo straight
    // back into the identical death next round (observed: 2x same-day deaths on 2026-07-26).
    // Reuse the SAME id:1432 negative cache + pure helper the route=none path already uses —
    // applyNoWorkSuppression's existing pre-filter (and its existing RELAY_STATUS "Blocked"
    // surfacing via `surfaced.push`) then suppresses the re-dispatch for free, clearing only
    // when the repo's work_sig genuinely changes (e.g. its ROADMAP shrinks).
    recordNoWorkHandback(noWorkNegCache, unit.repo, unit.verdict, unit.work_sig || '')
    scheduleStatusWrite(state)
    return
  }
  if (!report.contract_met) {
    // HANDBACK: not merged; worktree held on disk for a human/strong turn.
    // id:bfbf (routed:9371) — CROSS-CHECK a whole-dispatch "nothing dispatchable" claim against
    // the RESOLVED pool set BEFORE anything records it. The discriminator is SET DISJOINTNESS,
    // not emptiness: in the real incident the child returned 15 considered ids (all correctly
    // gated) and NOT ONE was among the 5 the counter had counted, so an emptiness check would
    // have stayed silent — exactly the id:7517/routed:2d94 failure (it swept for the retired
    // "[HARD — pool]" spelling, found 0, refused 5 real bare-"[HARD]" items). The alarm is
    // folded into hbReason so it rides the PERSISTENT handback accumulator (state.surfaced is
    // rebuilt every round by buildSurfacedView — a push there would be destroyed, the id:1735
    // bug), and it is computed here so `hbReason` is identical in the accumulator, the emitted
    // event, and the invariant backstop.
    const enumAlarm = noWorkEnumerationAlarm({
      repo: unit.repo, verdict: unit.verdict,
      openHardPool: unit.open_hard_pool || 0,
      // routed:9371 correction — the RESOLVED pool set is the second consumer of
      // gather-repo-state.sh's OPEN_HARD_POOL_IDS (the first is the HARD brief). Passing the
      // raw unit field, not hardPoolIdsFor(unit): orphan-suppression is a DISPATCH concern and
      // a suppressed id the child correctly looked at still proves it looked in the right place.
      poolIds: unit.open_hard_pool_ids,
      consideredIds: report.considered_ids,
      route: report.route, handbackItem: report.handback_item,
    })
    const hbReason = (report.handback || 'contract_met=false') + (enumAlarm ? ` || ${enumAlarm.reason}` : '')
    // THREE outcomes, and the third one must stay VISIBLE: 'enumeration-unevaluable' is neither
    // an accept nor a disjointness finding — it says the cross-check could not be run. It is
    // surfaced in the same place as the alarms, with its own event kind so it can never be
    // read as a proven wrong-place verdict, and it does NOT block the handback. All three
    // non-null outcomes skip recordNoWorkHandback below.
    if (enumAlarm) {
      log(`relay-loop: ${enumAlarm.reason}`)
      pushEvent(`handback-${enumAlarm.kind}`, { repo: unit.repo, mode: unit.verdict, kind: enumAlarm.kind, openHardPool: enumAlarm.openHardPool, overlap: enumAlarm.overlap, reason: enumAlarm.reason })
    }
    // id:bd04 — a size-out that proposes seams CREATES work (handback-followup.py writes them into
    // ROADMAP.md as pickable units), so it must not score the round dry. This is the id:c919
    // predicate, which until now was applied only at the integrate() site — i.e. never to a
    // size-out, the one case c919 exists for.
    state.handbacks.push({ repo: unit.repo, reason: hbReason, worktreePath: report.worktree, workCreated: handbackCreatedWork(report) })
    pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason: hbReason })
    emittedHandbackEvents.push({ repo: unit.repo, reason: hbReason })  // id:4a46 — invariant backstop
    // id:1432 (b) — loud repeat-tracking: count every child handback this run; a repo+verdict
    // at >=2 surfaces as an ALERT in the exit summary + RELAY_STATUS (a repeating handback is a
    // bug signal, not noise).
    trackHandback(handbackTracker, unit.repo, unit.verdict, hbReason)
    // id:3906 — record the STRUCTURED fields alongside the tracker's aggregate count, so the
    // exit summary can classify a repeat as a bug signal vs. legitimate queue exhaustion instead
    // of always alarming.
    handbackClassifyLog.push({
      repo: unit.repo,
      handback_item: report.handback_item || '',
      route: report.route || 'none',
      child: `${unit.repo}:${unit.verdict}:${round}`,
      gate_reason: report.gate_reason || '',
    })
    // id:1432 (a) — dispatch-level suppression: a WHOLE-DISPATCH "no executor-actionable work"
    // handback (route missing/none — it produces no durable ROADMAP action from id:3801) stamps
    // a negative cache keyed on the unit's work_sig, so discovery does NOT re-dispatch the same
    // verdict until the work_sig genuinely changes. ITEM-level handbacks (route=decision-gate/
    // hard-split/human, with handback_item) are gated durably by handback-followup.py instead —
    // this is the defense-in-depth for the route=none case that path skips.
    // id:bfbf (routed:9371) — but ONLY when the zero-dispatchable claim is EVIDENCED (alarm
    // computed above). Stamping the negative cache on an UNEVIDENCED claim would suppress
    // re-dispatch until work_sig changes, i.e. silently PARK a repo that has work — the alarm
    // must never be recorded as a clean drain.
    if (!enumAlarm && (!report.route || report.route === 'none')) {
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
  // id:087b — the ` [id:a,b]` checkpoint-message suffix itself is built by integrate.sh from
  // the --ids it receives; relay-loop.js only RESOLVES the ids (above) and forwards them.
  // ── id:087b — THE INTEGRATOR IS FULLY MECHANICAL. NO LLM AGENT RUNS HERE. ──────────
  // What used to sit here was an ~11-step Sonnet AGENT prompt (model:'sonnet') that merged
  // to main, ticked ROADMAP, bumped, changelogged, archived, tagged, pushed, retired the
  // worktree and wrote relay.toml — every one of those steps DETERMINISTIC, all of them on
  // the merge-to-main critical path, all of them re-derived from prose by an LLM on every
  // single integration. It is now ONE `relay-mech` mechanical hop (id:6176) dispatching
  // relay/scripts/integrate.sh at MECH_MODEL, exactly like the other mechanical hops in this
  // file. Owner rulings D1/D2 (2026-08-20) closed the last five LLM-only behaviours into the
  // script: the ROADMAP tick (roadmap-tick.sh, id:5b12), archive-done (roadmap-archive.sh,
  // id:f54d), the durable Fable-recheck keys last_strong_ckpt/strong_model/fable_rechecked
  // (id:e030), the L2 push-seed inputs (id:c855 — postSig via discover-sig.sh plus the
  // open [ROUTINE] / [HARD] counts, computed LAST so they reflect settled post-integrate
  // state), and sibling-branch surfacing (stranded-branch-scan.sh, id:dd7d).
  //
  // The two SAFETY rules that used to live in the prompt are now ENFORCED IN-SCRIPT, which
  // is the whole point of the move — a shell script cannot decide to "clean the tree to make
  // room": id:aa93 (a foreign-dirty main is DEFERRED, and NEVER force-cleaned — integrate.sh
  // must NEVER run `git stash`, `git reset --hard`, `git checkout --` or `git clean`, and
  // contains none of them in any code line, proven by its own test) and id:6e02 (retire
  // EXACTLY the one named worktree+branch, never a glob, never a "tidy other relay/*").
  // The ckpt `-c` anchor (id:8e3e zero-commit vs id:25aa post-merge tip) is DERIVED from
  // whether the merge moved HEAD, not judged.
  //
  // THE ONE RESIDUAL, deliberately NOT guessed here: the semver bump trigger ("one bump per
  // USER-OBSERVABLE close; a refactor-only close does NOT bump", id:e647). It is driven by
  // this unit's `substantive` signal — and when that cannot settle user-observability,
  // integrate.sh HANDS BACK LOUDLY (`HANDBACK[bump]`, exit 30) BEFORE any mutation rather
  // than silently bumping or silently skipping. It resolves without asking on a version-less
  // repo (nothing to bump), on a non-substantive close, or from a durable per-repo
  // `bump_policy` in relay.toml.
  //
  // id:ba7e — the CANONICAL main checkout below is a DELIBERATE exception to id:34b7's
  // no-main-checkout rule, not an oversight. The integrator is not an execute/review child:
  // its whole job is to merge the child's branch INTO the canonical checkout, every step of
  // which is defined only against the main repo. id:34b7 established that WORKING children
  // never receive it; the integrator is the single serialized writer that must.
  const integrateArgs = [
    '--repo', mechArg(unit.repo), '--path', mechArg(unit.path),
    '--worktree', mechArg(report.worktree), '--branch', mechArg(report.branch),
    '--summary', mechArg(report.summary), '--run', mechArg(state.runId),
    '--label', mechArg(label), '--verdict', mechArg(unit.verdict),
    '--substantive', mechArg(String(unitIsSubstantive(unit.verdict, report))),
    '--strong-model', mechArg(STRONG_MODEL),
  ]
  if (workedIds.length) integrateArgs.push('--ids', mechArg(workedIds.join(',')))
  if (unit.intensive) integrateArgs.push('--intensive', mechArg(unit.intensive))
  // isStrong / isFableRecheck are computed above and passed through VERBATIM: integrate.sh
  // preserves BOTH branches of step 6b (a real-Fable strong ckpt marks fable_rechecked with
  // today's date; an Opus-standin strong ckpt records bare `false`), and an EXECUTE (sonnet)
  // checkpoint never touches those three keys at all — that is the id:e030 masking bug.
  if (isStrong && isFableRecheck) integrateArgs.push('--fable-recheck')
  if (unit.chainEnded) integrateArgs.push('--chain-ended')
  let result
  try {
    // The script path is a LITERAL in the fence body (only the args are built above) so the
    // id:5bbb allowlist-completeness guard can statically resolve this hop to integrate.sh.
    const raw = await agent(
      'Run EXACTLY this one command and report its stdout VERBATIM (id:087b mechanical relay integrator for ' + unit.repo + ' — merge, tick, bump, changelog, archive, tag, push, retire, state-write; it is fail-closed and prints a loud HANDBACK[<step>] on stderr):\n' +
      '```relay-mech\n~/.claude/skills/relay/scripts/integrate.sh ' + integrateArgs.join(' ') + '\n```',
      { label: `integrate:${unit.repo}`, phase: 'Integrate', model: MECH_MODEL }
    )
    result = parseIntegrateResult(raw)
  } catch (err) {
    // A dispatch failure is NOT evidence the merge did or did not land — integrate.sh is
    // idempotent enough to re-run (every mutating step is guarded), so record a handback and
    // let the next round retry rather than inventing a merged=true.
    result = { merged: false, reason: `integrate.sh mechanical hop failed to dispatch (${(err && err.message) || err}) — no merged= line was returned; the worktree stays on disk for a retry` }
  }
  if (result && result.merged) {
    if (result.ts) state.ts = result.ts
    // id:dd7d step 1c — the integrator's own stranded-sibling scan came back non-empty:
    // ANOTHER committed branch for this same item exists beyond the one just merged. This
    // does not block the merge already performed (a human triages which result is right),
    // but it must not surface only as luck — log it loudly and record it in RELAY_STATUS so
    // it cannot silently disappear the way the lodelore id:15d2 divergence did.
    const siblingBranches = Array.isArray(result.siblingBranches) ? result.siblingBranches.filter(Boolean) : []
    if (siblingBranches.length) {
      const siblingReason = `id:dd7d sibling branch(es) for ${unit.repo}${workedIds.length ? ' item ' + workedIds[0] : ''} still carry committed work distinct from the branch just merged (${report.branch}) — a prior attempt may have reached a different result; needs human triage: ${siblingBranches.join('; ')}`
      log(`relay-loop: ${siblingReason}`)
      state.handbacks.push({ repo: unit.repo, reason: siblingReason, worktreePath: '-' })
      pushEvent('sibling-branch', { repo: unit.repo, mode: unit.verdict, ids: workedIds, siblingBranches })
    }
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
      // id:ba7e — a DELIBERATE main-checkout reference, and not a child prompt at all: this is
      // the operator-facing path printed in RELAY_STATUS.md, written AFTER the merge landed.
      // The child's worktree is retired moments later, so pointing the human at it would hand
      // them a path that no longer exists; the canonical checkout is the only durable location.
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
    if (report && unit.verdict === 'review') {
      logGamingFlags(unit.repo, state.runId, report, result.ts || state.ts)
    }
  } else {
    const reason = (result && result.reason) || 'integration failed'
    // id:c919 — workCreated: did THIS handback cause new dispatchable work to be written?
    // ONLY route:hard-split with a non-empty proposed_split does (handback-followup.py appends
    // those seams as pickable units). route decision-gate/human do NOT — they re-tag the parent
    // into a classifier-EXCLUDED lane, which REMOVES work rather than adding it; counting them
    // would keep the loop spinning on a shrinking backlog. (This narrows routed:b945's proposed
    // "{hard-split, decision-gate}" — decision-gate creates nothing.) Keyed on the emitted
    // INTENT rather than the followup's actual write count because durableHandbackFollowup is
    // fire-and-forget and reports nothing back; over-counting is the safe direction here and
    // matches this file's own stated principle — under-draining merely runs an extra round,
    // over-draining could strand work.
    const routeCreatedWork = handbackCreatedWork(report)   // id:bd04 — shared with the size-out site
    // ── id:907e — AMENDS the c919 predicate above: VERDICT-CLASS CHANGE, not route only ──
    // c919's reasoning counted only *dispatchable [ROUTINE]* work, so it scored a
    // gate-writing handback as nothing. But writing the gate drops actionable_routine_open
    // to 0, which flips the repo's classifier verdict execute -> review — the round created
    // a REVIEW unit. Loderite run relay-20260730-173701-17132 rounds 8-9: both handbacks
    // wrote gates, both counted dry, K=2 tripped, and the pool quit on the exact round its
    // verdict had changed. c919's own asymmetry argument (under-draining costs one extra
    // round; over-draining strands work) argues FOR counting it — it was applied backwards
    // for this case.
    //
    // Clause (i) — CACHE BYPASS (id:c3a6). The "after" class is re-derived from a FRESH,
    // DIRECT `classify-repo.sh` run dispatched right here as a mechanical model:'bash' hop.
    // It deliberately does NOT read `state.discoverCache` (the id:c3a6 content-addressed
    // discovery cache) nor this round's reused verdict: that cache serves last round's
    // verdict whenever a repo's discover-sig is unchanged, so a predicate reading it would
    // answer "unchanged" essentially always and the whole amendment would ship as a silent
    // no-op — the banned detector-whose-resolution-does-nothing pattern. `classify-repo.sh`
    // and `classify-verdict.sh` are documented side-effect-free and are themselves UNCACHED,
    // which is what makes the direct call a legitimate bypass rather than a cache poke.
    //
    // Clause (ii) — REPO-SCOPED, not per-handback causality. The question is "did THIS ROUND
    // change THIS REPO's verdict class?", so the named pair is verdictClassBefore (the class
    // discovery assigned this repo when it dispatched the unit) vs verdictClassAfter (the
    // repo's whole-repo class now). Because the "after" re-classifies the REPO, a flip caused
    // by a sibling unit under in-repo parallelism (id:1f4f) is counted too — single-`report`
    // attribution would under-count exactly there.
    let verdictClassAfter = null
    try {
      verdictClassAfter = await mechVerdictHop(
        'fresh, cache-bypassed re-classification of ' + unit.repo + ' for the id:907e verdict-class change predicate',
        // id:ba7e — DELIBERATE canonical-checkout use: this is a PARENT-side mechanical hop, not
        // a child prompt. classify-repo.sh must read the repo's POST-INTEGRATE state (the merge
        // just landed on main); the child's worktree holds the pre-merge branch, so classifying
        // it would answer the wrong question.
        `~/.claude/skills/relay/scripts/classify-repo.sh --repo '${unit.repo}' --path '${unit.path}'`,
        `reclassify:${unit.repo}`
      )
    } catch (err) {
      log(`relay-loop: id:907e re-classification of ${unit.repo} failed (${err}) — falling back to the c919 route-only predicate for this round`)
    }
    const verdictClassBefore = unit.verdict || null
    if (!verdictClassAfter) {
      // LOUD, never silent: an unreadable class is not evidence of a flip, so we fall back to
      // c919's route-only answer for this round rather than guess in either direction.
      log(`relay-loop: id:907e — no fresh verdict class for ${unit.repo} (before='${verdictClassBefore}'); workCreated falls back to route-only`)
    }
    const osc = recordVerdictClass(unit.repo, verdictClassAfter)
    const verdictClassChanged = !!(verdictClassBefore && verdictClassAfter && verdictClassBefore !== verdictClassAfter)
    if (verdictClassChanged && osc.oscillating) {
      // Clause (iii): flapping counts as DRY (see recordVerdictClass) and is named in the exit reason.
      log(`relay-loop: id:907e OSCILLATION GUARD — ${unit.repo} verdict class is flapping (${osc.flips} flips in the last ${OSCILLATION_WINDOW} observations, now '${verdictClassAfter}'); NOT counting this change as work created`)
    } else if (verdictClassChanged) {
      log(`relay-loop: id:907e — ${unit.repo} verdict class changed ${verdictClassBefore} -> ${verdictClassAfter} this round; counting the round as work-creating (a ${verdictClassAfter} unit now exists)`)
    }
    // The amended predicate: c919's route test OR a repo-scoped verdict-class change, read from
    // the FRESH classify-repo.sh run above rather than the id:c3a6 discovery cache (which would
    // answer "unchanged" forever), minus a flapping repo (clause iii).
    const workCreated = routeCreatedWork || (verdictClassChanged && !osc.oscillating)
    state.handbacks.push({ repo: unit.repo, reason, worktreePath: report.worktree, workCreated })
    pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason })  // id:c8b6
    emittedHandbackEvents.push({ repo: unit.repo, reason })  // id:1735 — invariant backstop
  }
  scheduleStatusWrite(state)
}

// id:3801 — Durable handback follow-up. When a child hands back (contract_met=false) with a
// classified route, durably record it in the repo's MAIN-checkout ROADMAP.md so the pool stops
// re-dispatching an un-doable item: decision-gate/human → re-tag the parent to the
// classifier-excluded "[INPUT — decision]" (id:4b64 — the canonical capability-keyed spelling
// of the old "[HARD — decision gate]"); hard-split → gate the parent + append the
// proposed seams as pickable units. The Workflow sandbox has NO shell/fs (process.* / new Date()
// crash the pool — id 2026-06-15), so a tiny Haiku agent runs handback-followup.py, which owns
// all idempotency + the flock'd md-merge write + the --ff-only commit/push. Fire-and-forget,
// non-fatal (a follow-up failure must never crash the integrator).
//
// LOUD ON FAILURE (id:4b64): "non-fatal" used to mean SILENT — the agent was asked for the exit
// code and the answer was discarded, so a follow-up that could not write its gate (the
// pre-commit lane-vocab ratchet rejecting the emitted old-vocab tag) left the round reporting a
// clean `drained` while the repo sat wedged (lodelore run relay-20260810-214130-15097). The
// script itself no longer leaves residue (md-merge rolls a failed commit back), but the FAILURE
// must still surface: a non-zero exit — or an unreadable answer — pushes a Blocked entry into
// state.handbacks, which renders into RELAY_STATUS and the exit summary. The gate stays a CLAIM
// the next review re-checks (anti-gaming).
function durableHandbackFollowup(unit, report) {
  const route = report.route
  if (!route || route === 'none' || !report.handback_item) return  // nothing durable to do
  const esc = s => String(s == null ? '' : s).replace(/'/g, "'\\''")
  const splitJson = JSON.stringify(Array.isArray(report.proposed_split) ? report.proposed_split : [])
  // Short, single-line gate note (never inline the verbose handback into a ROADMAP line).
  const gateReason = (report.gate_reason || String(report.handback || '').slice(0, 200)).replace(/\s+/g, ' ').trim()
  const surfaceFollowupFailure = detail => {
    const reason = `durable handback follow-up FAILED for id:${report.handback_item} (route=${route}, id:3801/id:4b64) — the gate was NOT recorded in ROADMAP.md, so the pool will keep re-dispatching this un-doable item: ${detail}`
    log(`relay-loop: ${reason}`)
    state.handbacks.push({ repo: unit.repo, reason, worktreePath: '-' })
    pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason })
    scheduleStatusWrite(state)
  }
  agent(
    `Run exactly this command and report whether it exited 0 (durable handback follow-up for ${unit.repo}, id:3801 — records the handback in ROADMAP.md so the pool stops re-dispatching an un-doable item; the script owns idempotency + commit/push):
python3 ~/.claude/skills/relay/scripts/handback-followup.py '${esc(unit.path)}' --parent-id '${esc(report.handback_item)}' --route '${esc(route)}' --gate-reason '${esc(gateReason)}' --split-json '${esc(splitJson)}' --run-id '${esc(state.runId)}'
Then report the command's exit code as the LAST line of your answer, in EXACTLY this form with nothing else on that line: EXIT:<code> (for example EXIT:0). If the command could not be run at all, report EXIT:127. When the code is not 0, include its stderr on the lines above.`,
    { label: `handback-followup:${unit.repo}`, phase: 'Logging', model: 'haiku' }
  ).then(res => {
    const text = typeof res === 'string' ? res : JSON.stringify(res || '')
    const m = /EXIT:\s*(\d+)/.exec(text)
    // An unreadable answer counts as a FAILURE: a silent fallback here is precisely the hole
    // this closes (the no-silent-swallow rule, id:4347). Over-surfacing is the safe direction.
    if (!m) { surfaceFollowupFailure(`follow-up agent reported no exit code; answer: ${text.slice(0, 300)}`); return }
    if (m[1] !== '0') { surfaceFollowupFailure(`handback-followup.py exited ${m[1]}; output: ${text.slice(0, 300)}`); return }
  }).catch(err => surfaceFollowupFailure(`agent error: ${err}`))
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
  // id:3222 — routed through dispatchGuarded so a blocked/empty log write is RECORDED in
  // state.agentFailures instead of vanishing; still fire-and-forget (the guard never rejects).
  const gamingPrompt =
    `Append the following JSON line to the gaming-flags log (create if absent, append only).
FIRST resolve the path with the shell (the JS cannot): log=$(python3 -c "import os;print(os.path.expanduser('${logPath}'))")
Then run: mkdir -p "$(dirname "$log")" && printf '%s\\n' '${json.replace(/'/g, "'\\''")}' >> "$log"
Confirm it succeeded.`
  // The trailing .catch stays: the guard already absorbs a rejected dispatch, but this call is
  // never awaited, so the belt-and-braces handler keeps a gaming-flags log failure non-fatal
  // even if the guard itself ever grows a reject path.
  dispatchGuarded({ label: `gaming-log:${repo}`, phase: 'Logging', model: 'haiku' }, repo, gamingPrompt)
    .catch(err => log(`relay-loop: gaming-flags log write failed (non-fatal): ${err}`))
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
//
// id:f7d3 — MECHANIZED: this used to be a single Haiku call running two (or three, with the
// intensive branch) `&&`-joined commands. `mechanical-proxy.py`'s `_command_allowed()` refuses
// any unquoted sequence operator (`;`, `&&`, newline — see `_has_unquoted_sequence_operator`),
// so that bundled prompt could never pass the `model:'bash'` gate as one fence: a refused
// command fails OPEN to the real model, and `"bash"` is not a real model (the id:6b35
// fail-CLOSED hazard — this would 404 every release). Splitting into one dispatch per fenced
// command (mirrors id:86a2/24ec's single-fence pattern) lets each pass the gate as-is:
// `claim.sh` and `heartbeat.sh` are both already in `ALLOWED_RELAY_SCRIPTS`, and each fence here
// is a clean single-stage pipeline leading with one of them. Each `.catch()` stays independently
// non-fatal — a failed release/beat must never fail the unit; the claim TTL / next heartbeat
// backstops it either way.
async function releaseLease(unit) {
  // id:3222 — each fence goes through dispatchGuarded: a release blocked at the dispatch
  // boundary used to be invisible (17 of them in run relay-20260812-001727-5554 stranded two
  // leases for the full TTL with nothing in RELAY_STATUS). Still non-fatal — the guard records
  // and returns null, it never rejects, so the TTL/next-heartbeat backstop is unchanged.
  const dispatch = (label, cmd) =>
    dispatchGuarded({ label: `release:${unit.repo}:${label}`, phase: 'Leases', model: MECH_MODEL }, unit.repo,
      `Run exactly this one command and report whether it exited 0:\n` +
      '```relay-mech\n' + cmd + '\n```')

  await dispatch('claim', `~/.claude/skills/relay/scripts/claim.sh release ${unit.repo} --run ${state.runId}`)
  if (unit.intensive) {
    await dispatch('resource', `~/.claude/skills/relay/scripts/claim.sh release resource:${unit.intensive} --run ${state.runId}`)
  }
  await dispatch('heartbeat', `~/.claude/skills/relay/scripts/heartbeat.sh beat ${state.runId}`)
}

// id:34b7 — DISSOLUTION: the PARENT creates + provisions the child's worktree BEFORE
// dispatch, so the child is never handed the main-checkout path and has no reason or
// means to reach into it (removes the reach, rather than guarding the write after the
// fact — that guard is id:d464, a PreToolUse deny hook, and carries a standing owner
// "DISCUSSION ONLY — DO NOT BUILD" directive, deliberately untouched here).
// Mechanical hop (MECH_MODEL/model:'bash'), mirrors releaseLease()/retireDeadWorktree()
// above: ONE `git worktree add` using the SAME worktreePathFor()/branchFor() naming the
// API-error recovery path already depends on (assertions 7-8 of
// tests/test_parent_creates_worktree_34b7.sh), plus part (2) — provisioning the
// gitignored build artifacts a child would otherwise have to reach into main for
// (node_modules, .venv; loderite RELAY_LOG.md:2681/3022/3422/3486 already did this by
// hand, per-child, every time). Symlinked, best-effort (`|| true` — a repo with neither
// artifact class is a no-op, not a failure); this is deliberately NOT exhaustive of every
// build-artifact class a repo might have, just the two named in the item's own text.
// id:315c — RUN-SCOPED attempt watermark, keyed by the unit's attempt-LESS identity.
// id:9834 made the retry bump `attempt`, but it bumped it on the UNIT OBJECT only, and a
// unit is re-created fresh by discovery every round with no `attempt` field. So each round
// restarted at 0, collided with its own earlier round's leftover branch, bumped to 1,
// collided with THAT round's retry branch too, and gave up — both names permanently
// consumed for the rest of the run. Observed 2026-08-12 (run relay-20260812-122721-23819):
// loderite `review-repo-1` failed provisioning in rounds 3,4,5,6,7,8 and ai-codebench
// `hard-repo-1/2` 4× — 10 of that run's 14 agent-failures were this one bug, each burning
// the repo's dispatch slot for the round while doing nothing. Fail-closed (id:66d9) so it
// never corrupted anything; it just silently starved those repos.
// Seeding from this watermark means a round starts at the last attempt that WORKED, so at
// most ONE collision+bump is ever needed (attempt N's branch may survive; N+1 is then free
// by construction) — which is exactly what the id:9834 single-bump budget provides.
const attemptSeq = Object.create(null)
const attemptSeqKey = (unit) => `${unit.repo}|${unit.verdict}|${dispatchItemFor(unit) || 'repo'}`

// id:dd7d — pre-dispatch stranded-branch check (b). Returns an array of
// "<branch>\t<count>" lines (possibly empty) reporting any branch — live or parked in
// relay/orphan/* — for this unit's item that already carries >0 commits beyond base, i.e.
// a prior attempt's committed-but-unmerged work (lodelore id:15d2: a dirty-tree handback
// followed by a plain re-dispatch redid the work from scratch and reached a contradictory
// answer, undetected until a manual integrate hit an add/add conflict). Repo-scoped units
// (no item id) have nothing to compare against and always return []. FAIL-OPEN on any
// scan/agent error — this is a refusal-to-dispatch guard, not a correctness gate, and must
// never itself become a reason no repo can ever be worked.
async function strandedBranchesFor(unit) {
  const item = dispatchItemFor(unit)
  if (!item) return []
  let raw
  try {
    // (unit.path is the CANONICAL repo checkout, not a worktree — deliberate: no worktree
    // exists yet at pre-dispatch time (same canonical-checkout justification as id:ba7e),
    // so the branch/commit scan below must run against the repo's own git dir.)
    const res = await agent(
      `Run EXACTLY this one command and report its stdout VERBATIM (id:dd7d pre-dispatch stranded-branch scan — is there already a committed branch for this item from a prior attempt?):\n` +
      '```relay-mech\n' +
      `~/.claude/skills/relay/scripts/stranded-branch-scan.sh ${unit.path} --verdict ${unit.verdict} --item ${item}` +
      '\n```',
      { label: `stranded-scan:${unit.repo}`, phase: 'Support', model: MECH_MODEL }
    )
    raw = typeof res === 'string' ? res : JSON.stringify(res == null ? '' : res)
  } catch (e) {
    log(`relay-loop: id:dd7d stranded-branch-scan threw for ${unit.repo} (${(e && e.message) || e}) — fail-open, proceeding with dispatch`)
    return []
  }
  if (/^MECH-ERROR exit=/.test(String(raw))) {
    log(`relay-loop: id:dd7d stranded-branch-scan errored for ${unit.repo}: ${String(raw).replace(/\s+/g, ' ').slice(0, 200)} — fail-open, proceeding with dispatch`)
    return []
  }
  return String(raw).split('\n').map(l => l.trim()).filter(l => l.includes('\t'))
}

async function provisionWorktree(unit, isRetry) {
  // Seed once per dispatch (never on the retry recursion — that already carries its bump).
  if (!isRetry) {
    const seeded = attemptSeq[attemptSeqKey(unit)] || 0
    if (seeded > (unit.attempt || 0)) unit.attempt = seeded
  }
  const wt = worktreePathFor(unit)
  const branch = branchFor(unit)
  let out
  try {
    const res = await agent(
      `Run exactly this one command and report its stdout VERBATIM, including the final line (id:34b7 pre-dispatch worktree creation + gitignored-artifact provisioning):\n` +
      '```relay-mech\n' +
      `~/.claude/skills/relay/scripts/provision-worktree.sh ${unit.path} ${wt} ${branch}` +
      '\n```',
      { label: `provision:${unit.repo}`, phase: 'Support', model: MECH_MODEL }
    )
    out = typeof res === 'string' ? res : JSON.stringify(res == null ? '' : res)
  } catch (e) {
    log(`relay-loop: id:34b7 provisionWorktree threw for ${unit.repo} (${(e && e.message) || e}) — no worktree, no dispatch`)
    recordAgentFailure(`provision:${unit.repo}`, unit.repo, 'Support', `provisionWorktree threw: ${(e && e.message) || e}`)
    return false
  }
  // id:66d9 — fail CLOSED on a POSITIVE token. The proxy signals command failure in the
  // RESPONSE BODY, never by throwing (mechanical-proxy.py returns `MECH-ERROR exit=<n>`),
  // so the old unbound `await agent(...)` + unconditional success dispatched children into repos
  // with no worktree. Sniffing for `MECH-ERROR` would be fail-open by construction: an
  // unrecognised body — a 404 model-error passthrough, a harness message, a truncated read
  // — is not that string and would sail straight through. Only `PROVISION-OK`, which
  // provision-worktree.sh emits solely after self-verifying registration AND branch, counts.
  if (!String(out).includes('PROVISION-OK')) {
    // id:9834 — RETRYABLE COLLISION. The worktree path and branch are already attempt-scoped
    // (unitKey encodes `attempt`, and worktreePathFor/branchFor thread `unit.attempt || 0` into
    // it) — but nothing ever INCREMENTED attempt, so a unit re-dispatched after a prior attempt
    // parked its worktree (an isolation-gate defer, id:76d2, or a dirty exit) renamed to `…-0`
    // every round and died on its own leftover branch: `fatal: a branch named
    // 'relay/<run>-execute-4d35-0' already exists` (run relay-20260812-001727-5554 spent three
    // dispatches per repo on that, then the id:365b breaker skipped the repo).
    // Bump the attempt ONCE and re-provision under the fresh name. Exactly one bump, via a
    // single guarded recursion rather than a loop: an unbounded retry would spin against a
    // genuinely broken repo. Reusing the parked worktree is deliberately NOT an option — it
    // would hand a child another attempt's uncommitted state, which is what the isolation gate
    // exists to prevent. If the retry also fails it records its own failure below (id:06a1).
    if (!isRetry && /already exists/i.test(String(out))) {
      const nextAttempt = unit.attempt ? unit.attempt + 1 : 1
      unit.attempt = nextAttempt
      // id:315c — persist the bump for the NEXT round's fresh unit object, not just this one.
      attemptSeq[attemptSeqKey(unit)] = nextAttempt
      log(`relay-loop: id:9834 provision collided with a prior attempt's branch/worktree for ${unit.repo} — retrying ONCE as attempt ${nextAttempt} (fresh name ${branchFor(unit)})`)
      return await provisionWorktree(unit, true)
    }
    log(`relay-loop: id:34b7 provisionWorktree failed for ${unit.repo} — no PROVISION-OK token in the hop's reply; got: ${String(out).replace(/\s+/g, ' ').slice(0, 200)}`)
    recordAgentFailure(`provision:${unit.repo}`, unit.repo, 'Support', `no PROVISION-OK token: ${String(out).slice(0, 200)}`)
    return false
  }
  return true
}

async function runUnit(unit) {
  const tier = unit.verdict === 'execute' ? 'sonnet' : 'strong'
  // Injected units (id:baf1) skip the quota gate — an explicit user request runs even near
  // the cap. They were already consumed by `inject.sh take`, so deferring them would lose
  // the injection; honoring it is the whole point of "inject this next, highest priority".
  if (!unit.injected && !(await quotaGateMemoized(tier))) {
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
  // id:4f9b — PRE-DISPATCH PROMPT-SIZE GATE. Size the assembled child prompt (plus the ROADMAP
  // the child is contractually required to read, measured on the host by classify-repo.sh as
  // `roadmap_bytes` — and TODO.md as `todo_bytes`, id:b018) BEFORE spawning anything. Over
  // budget ⇒ do NOT dispatch: emit a handback whose reason NAMES every oversized ledger with
  // its byte count and the REMEDY that shrinks it (roadmap-archive.sh / todo-update's
  // archive-done.sh), and surface it in RELAY_STATUS.md's Blocked section. Without this the
  // child dies with a bare harness `Prompt is too long`, integrate() records the GENERIC
  // `child agent failed/skipped (API error or terminal failure)`, and the status file reports
  // `## Blocked / HANDBACKs _(none)_` — a false clean over 481 lines of parked work
  // (run relay-20260801-213927-29875). That anonymous report is the id:4347 silent-swallow.
  // FAIL-OPEN: a unit with no ledger measurement at all can never trip this.
  // The handback is emitted on BOTH surfaces (event log + accumulator) so the id:4a46
  // bidirectional invariant holds; worktreePath is '-' because nothing was created.
  const oversizeReason = oversizeDispatchReason(unit, unitPrompt(unit).length)
  if (oversizeReason) {
    log(`relay-loop: ${oversizeReason}`)
    state.handbacks.push({ repo: unit.repo, reason: oversizeReason, worktreePath: '-' })
    pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason: oversizeReason })
    emittedHandbackEvents.push({ repo: unit.repo, reason: oversizeReason })  // id:4a46 backstop
    scheduleStatusWrite(state)
    return
  }
  // id:dd7d — pre-dispatch stranded-branch guard (b). Runs BEFORE provisioning (same
  // ordering rationale as id:ec8a below: a refused dispatch must consume no MAX_UNITS slot
  // and must not render as in-flight). If a prior attempt already committed a branch for
  // this exact item — live (relay/*) or parked (relay/orphan/*), any run — do NOT dispatch
  // a fresh child blind to it (the lodelore id:15d2 incident: a second child redid the work
  // from scratch and reached a contradictory answer, undetected until a manual integrate).
  // Hand back naming every branch found + its commit count so a human dispositions it —
  // this guard never deletes/merges/picks a winner itself.
  const stranded = await strandedBranchesFor(unit)
  if (stranded.length) {
    const reason = `id:dd7d stranded branch(es) already carry committed work for ${unit.repo} item ${dispatchItemFor(unit)} — refusing re-dispatch to avoid a second child redoing the work blind (lodelore id:15d2): ${stranded.join('; ')}`
    log(`relay-loop: ${reason}`)
    state.handbacks.push({ repo: unit.repo, reason, worktreePath: '-' })
    pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason })
    scheduleStatusWrite(state)
    return
  }
  // id:34b7 — the parent creates + provisions the worktree BEFORE dispatch (see
  // provisionWorktree() above). A failure here means no worktree exists at all: don't
  // dispatch a child into nothing — hand back exactly like the oversize gate above.
  // id:ec8a — this gate runs BEFORE any of the dispatch bookkeeping below (the two
  // counters, the in-flight row and the dispatch event). It used to sit AFTER them, so a
  // unit that never dispatched was still counted, still rendered as in-flight, and still
  // left a spurious forensic event — exactly what the 2026-08-11 incident run showed. A
  // failed provision must also consume no MAX_UNITS slot, so the counters follow the guard.
  const provisioned = await provisionWorktree(unit)
  if (!provisioned) {
    state.handbacks.push({ repo: unit.repo, reason: `id:34b7 pre-dispatch worktree provisioning failed for ${unit.repo} — no child dispatched`, worktreePath: worktreePathFor(unit) })
    pushEvent('handback', { repo: unit.repo, mode: unit.verdict, reason: 'id:34b7 provisionWorktree failed' })
    scheduleStatusWrite(state)
    return
  }
  unitsDispatched++
  totalDispatched++
  // id:8af2 — compute the choice ONCE and stamp it on BOTH surfaces (the live RELAY_STATUS row
  // and the forensic dispatch event), so the two can never disagree about which item ran.
  // id:923b — the inFlight row's `key: unitKey(...)` below stamps this unit's identity so
  // completion only clears THIS unit, not every same-repo sibling; recomputed identically
  // (pure fn) at the filter site further down.
  const choice = dispatchChoiceFor(unit)
  state.inFlight.push({ repo: unit.repo, mode: unit.verdict, agentId: `unit-${unitsDispatched}`, item: choice.item, itemRank: choice.itemRank, eligibleCount: choice.eligibleCount, key: unitKey({ verdict: unit.verdict, itemId: choice.item || '', attempt: unit.attempt || 0 }) })
  pushEvent('dispatch', { repo: unit.repo, mode: unit.verdict, tier, round, sig: unit.sig || '', item: choice.item, itemRank: choice.itemRank, eligibleCount: choice.eligibleCount })  // id:c8b6 + choice id:8af2
  log(`relay-loop: dispatch ${unit.verdict} → ${unit.repo} (tier=${tier})${choice.item ? ` item=id:${choice.item} (${choice.itemRank ? `${choice.itemRank} of ${choice.eligibleCount}` : `injected, ${choice.eligibleCount}`} actionable)` : ''}`)
  // Tier dispatch (D4): review/handoff get the STRONG_TIER model. Execute agents are
  // pinned to Sonnet; STRONG_TIER applies no model override to them.
  // id:de69 (a) — if the worked item id is ALREADY known at dispatch (an injected unit's
  // --item, or a hard unit whose classifier surfaced the bounded item), append it to the
  // /workflows label so the live pane reads `execute:zkm-stt id:09a3`. plain execute/review
  // pick the item inside the child, so their id is filled in post-run via report.worked_ids.
  // (id:b09e names an execute unit's item at DISPATCH now, so this label could carry it too —
  // deliberately NOT wired: `test_relay_worked_ids.sh` pins this exact resolution line, and a
  // cosmetic label is not worth reshaping another item's contract. Follow-up, not a defect.)
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
  state.inFlight = state.inFlight.filter(r => r.key !== unitKey({ verdict: unit.verdict, itemId: choice.item || '', attempt: unit.attempt || 0 }))
  // Review→execute AND execute→execute chaining (id:cc90, L2 — bounded rechain K≤3;
  // originally review-only per the 2026-06-13 user directive, generalized 2026-07-31
  // owner-ratified `/relay human`): when a review OR an execute unit re-derives the
  // roadmap and open [ROUTINE] work remains, re-enqueue this repo as an execute unit in
  // the SAME pool rather than waiting for the next pool's discovery, bounded by a DEPTH
  // COUNTER (not a one-shot boolean) so a repo with several open items drains in one
  // round instead of one item per round. The live lanes pull it (the pushing lane itself
  // re-checks `queue.length` after this returns, so it's never lost even as the last unit).
  // FALSE-PREMISE CORRECTED (id:8123, 2026-07-31): a comment here used to claim that an execute's
  // commits get reviewed by the next pool. That was NOT true. classify-verdict.sh's cascade is a strict
  // elif chain, so `review` was UNREACHABLE while a single actionable [ROUTINE] item stayed open —
  // an execute's commits were never reviewed at all (16 unaudited executor checkpoints piled up on
  // one repo in a single day; a human had to intervene twice). The chain-end classifier RE-ASK
  // below is what actually gets those commits audited, now that chains can run longer.
  // MAX_UNITS / quotaStopped still gate actual dispatch in the lane loop.
  //
  // id:cc90 pre-registration (amendment A2 / --fabled F1) — recorded in the SAME commit as the
  // code that implements it, per the owner-ratified 2026-07-31 `/relay human` decision:
  //   (a) review scope under chaining = PER-CHAIN, deferred: a chained execute is NOT reviewed
  //       mid-chain; the whole chain's commits are audited by the id:8123 chain-end classifier
  //       RE-ASK below (NOT a `chainDepth === K` trigger — that premise was false, see id:8123).
  //   (b) reject-unwind at depth K = NO UNWIND: a reject at depth K does not unwind units already
  //       integrated at lower depths in the chain. Integrated is integrated.
  //   (c) a chained member does NOT re-enter the disjoint greenlight (`disjoint-greenlight.sh`):
  //       it stays dependent on its predecessor in its own serial lane, never a parallel-wave member.
  const MAX_CHAIN_DEPTH = 3 // id:cc90 — K: named constant, not a magic literal at the gate below
  let rechainedSameRepo = false
  if ((unit.verdict === 'review' || unit.verdict === 'execute') && report && report.contract_met &&
      (report.routine_open || 0) > 0 && !quotaStopped && (unit.chainDepth || 0) < MAX_CHAIN_DEPTH) {
    const chainDepth = (unit.chainDepth || 0) + 1
    queue.push({
      repo: unit.repo, path: unit.path, verdict: 'execute',
      reason: `post-${unit.verdict} re-enqueue: ${report.routine_open} open [ROUTINE] item(s)`,
      lastCkpt: unit.lastCkpt, income: unit.income, chainDepth,
    })
    rechainedSameRepo = true
    log(`relay-loop: ${unit.verdict}→execute re-enqueue ${unit.repo} (${report.routine_open} open [ROUTINE], chainDepth ${chainDepth}/${MAX_CHAIN_DEPTH})`)
    // id:b8ae — mechanize the six-weeks-uncaught observe-only signal: record the re-chain as a
    // durable relay-events.jsonl entry (kind 'rechain') instead of relying on a human to catch
    // the log line above. Names the repo, the re-enqueued verdict, and the chain depth so the
    // occurrence can be found on evidence rather than needing someone to be watching a log.
    pushEvent('rechain', { repo: unit.repo, fromVerdict: unit.verdict, reenqueuedVerdict: 'execute', routineOpen: report.routine_open, chainDepth, maxChainDepth: MAX_CHAIN_DEPTH })
  }
  // ── id:8123 — CHAIN-END CLASSIFIER RE-ASK ──────────────────────────────────────────────
  // The chain for this repo has ENDED whenever we did not just re-chain it: normal completion,
  // mid-chain handback, contract_met:false, quota-stop, or an agent error. The loop supplies ONLY
  // that FACT (`chain_ended` + `chain_end_reason`) to classify-verdict.sh and lets the CLASSIFIER
  // decide — no loop-side `review` judgement, no classifier bypass, purity contract intact.
  //
  // This REPLACES id:cc90's originally-ratified `chainDepth === K` forced-review trigger, which
  // could not have worked: executes never re-enqueue (see the block above), so no chain is longer
  // than one unit today and a depth-K trigger would never have fired for the incident it was
  // designed to fix — and every chain ending BELOW K would escape it. A chain-end fact catches
  // all of those causes uniformly. cc90's K<=3 still bounds chain LENGTH; it is no longer the
  // audit trigger, and no separate aging term is built (meeting 2026-07-31-1231, amendment A1).
  //
  // RESET SEMANTICS (D2b, recorded here because cc90's counter is not shipped yet): when
  // chainDepth lands it resets on strong-audit WATERMARK ADVANCE (relay.toml last_strong_ckpt
  // moving — ckpt-tag.sh id:1a34/c500 now warns LOUDLY when a label carries no full claude-* id,
  // so a silent non-advance is no longer possible), NEVER on mere review DISPATCH: dispatch-reset
  // would degrade the guard to nothing under an apex outage. The outage escape is the
  // `chainEndReasked` surfaced-and-skipped path below, not a halt-at-K.
  //
  // The re-ask reuses the id:907e mechanical-hop shape (model:'bash' + parseVerdictClass) and
  // deliberately BYPASSES the id:c3a6 discovery cache — the cache serves last round's verdict for
  // an unchanged signature, which is exactly the situation a chain end changes. The matching
  // cache-side half is the `chain_ended` field hashed by discover-sig.sh (step 7a below).
  let chainEndReason = null
  if (!rechainedSameRepo && unit.verdict !== 'review' && !chainEndReasked.has(unit.repo)) {
    chainEndReason = !report ? 'agent-error'
      : (report.contract_met === false ? 'contract-not-met'
        : (quotaStopped ? 'quota-stop' : 'chain-complete'))
    chainEndReasked.add(unit.repo)
    unit.chainEnded = true            // read by integrate()'s step-7a postSig (discover-sig input)
    unit.chainEndReason = chainEndReason
    let chainEndVerdict = null
    try {
      chainEndVerdict = await mechVerdictHop(
        'chain-end classifier RE-ASK for ' + unit.repo + ' — id:8123; the loop supplies only the chain-end FACT, classify-verdict.sh decides the verdict',
        // id:5552 — the `| jq -c '. + {chain_ended:true,…}' |` middle stage is GONE:
        // classify-repo.sh now owns the field via --chain-ended. `jq` is not in
        // mechanical-proxy.py's _SAFE_PLUMBING, so _command_allowed() refused this whole
        // pipeline, it fell open to the real API, and model:"bash" 404'd — making this re-ask
        // 100% dead for every repo since it landed (routed:c555; verified by calling
        // _command_allowed on the exact string). Two pinned relay scripts pass the gate.
        // id:ba7e — DELIBERATE canonical-checkout use, same rationale as the id:907e re-ask
        // above: a PARENT-side mechanical hop that must classify the repo's real main state.
        `~/.claude/skills/relay/scripts/classify-repo.sh --repo '${unit.repo}' --path '${unit.path}' --emit unit --chain-ended '${String(chainEndReason).replace(/'/g, "'\\''")}' | ~/.claude/skills/relay/scripts/classify-verdict.sh`,
        `chain-end-reask:${unit.repo}`
      )
    } catch (err) {
      log(`relay-loop: id:8123 chain-end re-ask for ${unit.repo} failed (${err})`)
    }
    if (chainEndVerdict === 'review' && !quotaStopped) {
      queue.push({
        repo: unit.repo, path: unit.path, verdict: 'review',
        reason: `chain-end review re-ask (${chainEndReason}): classify-verdict.sh returned review for the chain just ended (id:8123)`,
        lastCkpt: unit.lastCkpt, income: unit.income, chainEndReask: true,
      })
      log(`relay-loop: id:8123 chain-end re-ask ${unit.repo} (${chainEndReason}) → classifier says review; enqueued`)
    } else if (!chainEndVerdict) {
      // NAMED ESCAPE — surfaced-and-skipped, never a silent drop and never a halt.
      state.queued.push({ repo: unit.repo, verdict: `review (id:8123 chain-end re-ask unanswered — surfaced, skipped this round)` })
      log(`relay-loop: id:8123 CHAIN-END ESCAPE — no readable verdict for ${unit.repo} after a chain end (${chainEndReason}); surfaced-and-skipped, next round re-derives (discover-sig carries the chain_ended fact)`)
    } else {
      log(`relay-loop: id:8123 chain-end re-ask ${unit.repo} (${chainEndReason}) → classifier says ${chainEndVerdict}; no review owed`)
    }
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
  // id:6176 — mechanical hop (model:"bash"): the ```relay-mech fence carries `inject.sh take`; the
  // proxy runs it locally and returns its RAW STDOUT (one compact JSON per line
  // {token,repo,verdict,item,prompt,requested_at}; empty when nothing pending). The path-resolve +
  // unit-shaping the old INJECT_TAKE_SCHEMA haiku agent did now lives in parseInjectTake (JS) — it
  // resolves each injected repo's absolute path from prelude.repos (this round's relay.toml read,
  // honoring `# path:`), since the fs-less Workflow sandbox cannot expand $HOME / read relay.toml.
  const raw = await agent(
    'Run exactly this one command and report its stdout verbatim (it atomically emits AND consumes pending user-injected relay units, one compact JSON per line):\n' +
    '```relay-mech\n' +
    // routed:a923 — the mid-round take is scoped the same way as the prelude's: a `--only X`
    // pool consumes only X's injections, leaving another pool's PENDING rather than stealing
    // (and losing) it. Unscoped pool ⇒ no flag ⇒ global take, unchanged.
    `~/.claude/skills/relay/scripts/inject.sh take${INJECT_SCOPE ? ` --repo ${INJECT_SCOPE}` : ''}` +
    '\n```',
    { label: 'inject-take', phase: 'Support', model: MECH_MODEL }
  )
  return enforceInjectScope(parseInjectTake(raw, prelude.repos), 'mid-round take')
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
// id:c919 — hard-split handbacks THIS round whose seams were written as new pickable units.
const workCreated = state.handbacks.slice(handbacksBefore).filter(h => h.workCreated).length
return { actionable: actionable.length + intensiveRan, produced, substantive, workCreated, surfaced: discovery.surfaced.length }
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
    // id:6176 — mechanical hop (model:"bash"): fence carries `heartbeat.sh beat <runId>`; the proxy
    // runs it locally (ZERO upstream inference). Fire-and-forget — return ignored, TTL backstop.
    // id:3557 audit: the resolved value is discarded entirely here, so the MECH-OK sentinel on a
    // silent success is harmless (no parsing of this hop's stdout exists).
    await agent(
      'Run exactly this command and report its stdout verbatim (refresh the relay run-liveness heartbeat so the outage watchdog/auto-reconcile know this pool is alive):\n' +
      '```relay-mech\n' +
      `~/.claude/skills/relay/scripts/heartbeat.sh beat ${state.runId}` +
      '\n```',
      { label: 'heartbeat-beat', phase: 'Support', model: MECH_MODEL }
    )
  } catch (_) { /* non-fatal — TTL backstop */ }
}

async function stopHeartbeat() {
  if (!state.runId) return
  try {
    // id:6176 — mechanical hop (model:"bash"): fence carries `heartbeat.sh stop <runId>`; the proxy
    // runs it locally (ZERO upstream inference). Fire-and-forget — return ignored.
    // id:3557 audit: same as heartbeat-beat — the resolved value is discarded, so the MECH-OK
    // sentinel on a silent success is harmless.
    await agent(
      'Run exactly this command and report its stdout verbatim (clean relay-loop shutdown — release the run heartbeat so the watchdog/auto-reconcile don\'t read this clean stop as a death):\n' +
      '```relay-mech\n' +
      `~/.claude/skills/relay/scripts/heartbeat.sh stop ${state.runId}` +
      '\n```',
      { label: 'heartbeat-stop', phase: 'Support', model: MECH_MODEL }
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
// id:c14d — this used to be a 3-step haiku prompt (the LLM issued each of dead-runs ->
// --all --auto -> per-runId reap-run -> TTL reap in sequence, reading its own prior output
// to drive the data-dependent next step). relay-reconcile.sh --auto-restart now wraps all
// three steps into ONE allowlisted command (see its header comment for the exact contract
// this replicates, including the REQUIRED --prefix 'relay-*' scoping), so this is a genuine
// single-command model:"bash" mechanical dispatch like the other id:6176 hops. Because id:3557
// landed first, a benign "no dead run" summary is never empty (the wrapper always prints a
// real one-line summary) — but it wouldn't matter here either way, since the result is
// discarded (fire-and-forget, `await` with no consumer of the return value).
try {
  await agent(
    'Run exactly this command and report its stdout verbatim (relay id:7809/id:c14d — auto-reconcile any prior DISPATCH-LOOP relay run that died without a clean heartbeat stop, before starting fresh work this restart):\n' +
    '```relay-mech\n' +
    "~/.claude/skills/relay/scripts/relay-reconcile.sh --auto-restart" +
    '\n```',
    { label: 'auto-reconcile-restart', phase: 'Support', model: MECH_MODEL }
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
      // id:907e clause (iii) — a drain reached WHILE a repo's verdict class was flapping is not an
      // ordinary drain: qualify the (already-set) reason so the oscillation is loud, not silent.
      if (stopReason === 'drained' && oscillatingRepos.size) stopReason = `drained:verdict-oscillation:${[...oscillatingRepos].join(',')}`
      log(`relay-loop: backlog drained (2 consecutive no-substantive-progress rounds) — done. Remaining: ${drain.summary}`)
      if (drain.gated.length) log(`relay-loop: ${drain.gated.length} repo(s) have gated [HARD] work the pool cannot auto-do — take them to /relay human --all or /meeting --cross.`)
      break
    }
  } else {
    dry = 0
  }
}
// id:907e clause (iii) — the MAX_ROUNDS seatbelt is the exit a verdict-class livelock lands on,
// and until now it left stopReason null, so a livelock was indistinguishable from an ordinary
// long run. Set it explicitly, and DISTINGUISH the oscillation case by name.
if (!quotaStopped && !stopReason && round >= MAX_ROUNDS) {
  stopReason = oscillatingRepos.size
    ? `max-rounds:verdict-oscillation:${[...oscillatingRepos].join(',')}`
    : 'max-rounds'
  log(`relay-loop: MAX_ROUNDS seatbelt (${round}/${MAX_ROUNDS}) — stopReason=${stopReason}`)
  if (oscillatingRepos.size) log(`relay-loop: id:907e — ${oscillatingRepos.size} repo(s) hit the seatbelt with a FLAPPING verdict class (${[...oscillatingRepos].join(', ')}); this is a livelock, not a normal termination — take them to /relay human.`)
}

await statusTail  // id:cb50 — flush the queued (off-critical-path) RELAY_STATUS writes so the final state is durable before the run returns
await stopHeartbeat()  // id:e149 — clean shutdown: release the run-liveness marker (no stale marker ⇒ no false watchdog/reconcile trigger)
// id:1735/id:4a46 — the loud invariant backstop: EQUALITY over the real-worktree subset. Every
// pushEvent('handback', …) emitted this run must have a matching entry in the persistent
// state.handbacks accumulator (forward — catches a regression of the original id:1735 bug: a
// handback event recorded as having happened, but the returned summary has no matching entry
// for it), AND every real-worktree accumulator entry must have a matching emitted event
// (reverse — id:4a46 closes the under-reporting gap: a real handback happened but no event was
// ever emitted for it). FAIL LOUDLY rather than silently returning the (possibly incomplete)
// list.
const handbackInvariant = assertHandbackInvariant(emittedHandbackEvents, state.handbacks)
if (!handbackInvariant.ok) {
  log(`relay-loop: INVARIANT VIOLATED (id:1735/id:4a46) — ${handbackInvariant.violations.length} handback event/accumulator mismatch(es) this run (forward: emitted with no accumulator entry; reverse: real handback with no emitted event): ${JSON.stringify(handbackInvariant.violations)}`)
}
const handbacks = reconcileHandbacks(state.handbacks)
// id:1432 — LOUD exit-summary surfacing: any repo+verdict that handed back >=2× this run gets
// flagged. id:3906 — but NOT always as "a bug signal": classify first, since three independent
// executors each correctly sizing-out a different item (route in {hard-split, decision-gate,
// human}) is the pool reporting the cheap work is DONE, not a bug — the two readings are
// operationally opposite and mislabelling sends the operator to debug a healthy pool.
const repeatHandbacks = handbackAlerts(handbackTracker, 2)
const repeatHandbackClassification = classifyRepeatHandbacks(handbackClassifyLog)
log(`relay-loop: done — ${round} round(s), ${state.completed.length} integrated, ${handbacks.length} HANDBACKs, quotaStopped=${quotaStopped}`)
if (repeatHandbacks.length) {
  const kind = repeatHandbackClassification.kind
  const label = kind === 'bug-signal' ? 'BUG SIGNAL, investigate'
    : kind === 'queue-exhausted' ? 'QUEUE EXHAUSTED — bring a human or re-spec the items, machinery is fine'
    : 'MIXED — some items need a human/re-spec, at least one repeat is a real bug signal'
  log(`relay-loop: id:3906/id:1432 ⚠️ REPEAT-HANDBACK ALERT (${label}) — ${repeatHandbacks.length} repo/verdict(s) handed back >=2× this run: ${repeatHandbacks.map(a => `${a.repo}(${a.verdict})×${a.count}`).join(', ')}`)
}

return {
  runId: state.runId,
  statusPath: RELAY_STATUS_PATH,
  completed: state.completed,
  handbacks,
  handbackInvariantViolations: handbackInvariant.violations,  // id:1735 — [] unless the invariant tripped
  repeatHandbacks,  // id:1432 — [{repo, verdict, count, lastReason}] for >=2× handbacks this run
  repeatHandbackKind: repeatHandbacks.length ? repeatHandbackClassification.kind : null,  // id:3906 — 'bug-signal'|'queue-exhausted'|'mixed'|null
  queuedRemaining: state.queued,
  quotaStopped,
  stopReason,  // id:8c35 — category: null | "quota-cache-unreadable" | "quota-extrapolated-stop[:<bucket>]" (id:0175/82e3) | "quota-exhausted:<bucket>" | "budget" | "drained" | "max-rounds" | "user-stop" (id:c012)
  rounds: round,
}
