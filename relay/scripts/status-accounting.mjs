// status-accounting.mjs — pure accounting invariant for RELAY_STATUS.md (id:8c85).
//
// WHY THIS EXISTS
// ---------------
// RELAY_STATUS.md is the fleet's primary observability surface. On 2026-08-10 it rendered a
// false clean: `dispatched=2 / completed=1 / blocked=0` with `## Blocked / HANDBACKs _(none)_`
// while four non-dispatch classes had silently vanished — dirty-deferred repos, an
// in-flight-suppressed repo, a `human`-verdict repo, and a REAL execute handback. No section
// mentioned them, so the operator could not see why nothing ran (id:4347, no-silent-swallow).
//
// The structural cause was that nothing asserted the obvious property: **every own repo must
// land in a rendered section, every round, with a reason.**
//
// AMENDED id:2f6b (2026-08-18): the original wording said "in EXACTLY one rendered section",
// and the duplication arm enforced it over ALL five sections keyed by REPO. That is false for
// any run completing more than one unit in a repo — `completed` and `handbacks` accumulate for
// the whole run — so it fired on legitimate state and, worse, the false message was read as
// fabricated by the harness safety classifier and killed two status writes. The COMPLETENESS
// arm (a repo reaching NO section) is the arm this module exists for and is unchanged; the
// duplication arm is now scoped to EXCLUSIVE_SECTIONS plus a unit-identity check. This module owns that
// property as pure, testable code, because the code that renders the file lives inside
// relay-loop.js — a Workflow module that cannot be imported or executed (id:2ec4). The house
// pattern for that situation is a pure `.mjs` sibling plus a byte-equivalent INLINE copy in
// relay-loop.js pinned by a structural test (cf. prompt-size-gate.mjs, round-plan.mjs,
// handback-summary.mjs).
//
// THIS MODULE DOES NOT YET MEET THAT PATTERN — say so plainly rather than imply otherwise.
// The inline copy in relay-loop.js is a HAND-REWRITE, not a byte-identical paste, so the house
// body-comparison assertion cannot be applied to it, and no test currently pins the two together
// (the 8c85 spec's case E4 greps only for the NAME `assertStatusAccounting`). Equivalence was
// hand-verified across 10 fixtures at review time (2026-08-10) — correct then, UNGUARDED since.
// Closing it needs a differential harness that evaluates the inline block and diffs its output
// against this module over these fixtures. Tracked as a follow-up; until it exists, treat any
// edit here as requiring a MANUAL matching edit in relay-loop.js.
//
// SHAPE
// -----
// `assertCompleteAccounting(universe, buckets, {label, id})` is the GENERIC core: partition
// completeness over an enumerated universe — it reports members of the universe that reached NO
// bucket (omission) and members that reached MORE THAN ONE (double-counting), and renders a loud
// message naming them. `assertStatusAccounting(ownRepos, state)` is a THIN wrapper that
// instantiates the core over `ownRepos` × the five RELAY_STATUS sections.
//
// The generic core is deliberately separable: `id:eb63(b)` needs the same partition-completeness
// shape at ITEM granularity (announced id vs worked id × {worked, substituted-away, deferred}).
// It can instantiate `assertCompleteAccounting` directly without touching this wrapper or its
// tests. (eb63's substitution EVENT is NOT an accounting concern and is not implemented here.)
//
// FAIL-SAFE: every entry point tolerates null/undefined/missing fields and never throws — this
// invariant runs inside the pool's round loop, where a throw would take down a live run.

// The five sections RELAY_STATUS.md renders per-repo rows into. `blocked` is not a state field:
// it is the RENDERED UNION of `state.surfaced` + `state.handbacks` (buildRelayStatus:291).
export const ACCOUNTING_SECTIONS = Object.freeze(['blocked', 'completed', 'inFlight', 'queued', 'skipped'])

// id:2f6b — the sections that are MUTUALLY EXCLUSIVE for one repo in one round. The other two
// are NOT, and asserting otherwise was a live false positive on every multi-round run:
//   • `completed` ACCUMULATES for the whole run (`state.completed.push`, never reset), so a repo
//     that closes a unit in round 1 and has another in flight in round 2 is legitimately in two.
//   • `blocked` is the rendered union of `state.surfaced` (per-round) and `state.handbacks` (a
//     PERSISTENT accumulator, relay-loop.js:2663), so it accumulates too — and `surfaced` can
//     legitimately co-occur with `inFlight` via in-flight suppression.
// The remaining three are per-round and genuinely exclusive: `state.queued` and `state.skipped`
// are reassigned each discovery (relay-loop.js:2174/2194) and in-flight suppression keeps a repo
// with a live unit out of `queued`.
// Observed false positives this fixes: loderite run relay-20260818-154017-12780 (14 completed
// rows for ONE repo read as 14-fold double-counting, which then tripped the harness safety
// classifier and FAILED both status writes) and csgebra run relay-20260818-205434-31345
// (completed + inFlight + blocked). Neither was a defect. See id:2f6b / id:b0ce.
export const EXCLUSIVE_SECTIONS = Object.freeze(['inFlight', 'queued', 'skipped'])

const asArray = (v) => (Array.isArray(v) ? v : [])

// A bucket member may be a bare name or a row object; accept the several key spellings the
// relay's row shapes use so the generic core stays reusable at other granularities (id:eb63).
function memberKey(m) {
  if (typeof m === 'string') return m
  if (!m || typeof m !== 'object') return ''
  for (const k of ['repo', 'name', 'id', 'item', 'key']) {
    if (typeof m[k] === 'string' && m[k] !== '') return m[k]
  }
  return ''
}

// ── Unit identity (id:2f6b / id:b0ce). ─────────────────────────────────────────────────────
// A RELAY_STATUS row is a UNIT, not a repo. Where a row carries an item identity we can key on
// it and detect the genuine defect — the SAME unit rendered in two sections at once. Rows with
// no item identity (a `surfaced`/`skipped` reason row, an agent-only in-flight row) return null
// and are exempt from the unit arm; they are still covered by the completeness arm.
export function statusUnitKey(m) {
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

// ── Generic core: partition completeness over an enumerated universe. ──────────────────────
// universe: array of member keys that MUST each be accounted for.
// buckets:  { <bucketName>: [member, …] } — members may be strings or row objects.
// opts.exclusiveBuckets (id:2f6b): the bucket names that are MUTUALLY EXCLUSIVE for a member.
//   Omit it and every bucket is treated as exclusive — the original "exactly one bucket"
//   semantics, which is what `id:eb63(b)` wants at item granularity. Naming a subset restricts
//   the cross-bucket duplication arm to those buckets; the rest may legitimately co-occur.
// opts.unitKey (id:2f6b): optional fn(member) → string|null. When given, a member appearing in
//   more than one bucket under the SAME non-null unit key is a duplicate regardless of which
//   buckets those are — this is the arm that still catches a unit rendered twice.
// returns:  { ok, missing, duplicated, message }
export function assertCompleteAccounting(universe, buckets, opts) {
  const o = opts && typeof opts === 'object' ? opts : {}
  const label = typeof o.label === 'string' && o.label ? o.label : 'accounting'
  const id = typeof o.id === 'string' ? o.id : ''
  const uni = asArray(universe).map(memberKey).filter(Boolean)
  const b = buckets && typeof buckets === 'object' ? buckets : {}
  const exclusive = Array.isArray(o.exclusiveBuckets) ? o.exclusiveBuckets : null
  const unitKeyOf = typeof o.unitKey === 'function' ? o.unitKey : null

  // member key → the bucket names it appeared in (repeats within one bucket count too).
  const placement = new Map()
  // member key → the EXCLUSIVE bucket names it appeared in (the cross-section duplication arm).
  const exclusivePlacement = new Map()
  // unit key → the bucket names that unit appeared in (the unit-identity duplication arm).
  const unitPlacement = new Map()
  for (const bucketName of Object.keys(b)) {
    const isExclusive = !exclusive || exclusive.includes(bucketName)
    for (const m of asArray(b[bucketName])) {
      const k = memberKey(m)
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
  const dupExclusive = [...exclusivePlacement.entries()]
    .filter(([, where]) => where.length > 1)
    .map(([k]) => k)
  const dupUnit = [...unitPlacement.entries()]
    .filter(([, where]) => where.length > 1)
    .map(([k]) => k)
  const duplicated = [...new Set([...dupExclusive, ...dupUnit])].sort()
  // the placement map a duplicate's detail line should quote
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
    if (missing.length) {
      parts.push(`${missing.length} of ${uni.length} reached NO section [${bucketNames}] — ${missing.join(', ')}`)
    }
    if (duplicated.length) {
      const detail = duplicated
        .map((k) => `${k} in ${[...whereOf(k)].sort().join('+')}`)
        .join('; ')
      const what = exclusive ? 'in more than one mutually-exclusive section' : 'must be exactly one section'
      parts.push(`${duplicated.length} double-counted (${what}) — ${detail}`)
    }
    message = `${label}: INCOMPLETE ACCOUNTING${tag} — ${parts.join(' | ')}. `
      + 'A member that reaches no section is INVISIBLE to the operator: the file reports a false clean.'
  }
  return { ok, missing, duplicated, message }
}

// ── RELAY_STATUS instantiation. ────────────────────────────────────────────────────────────

// The five rendered sections, derived from a run state. `blocked` is the union the renderer
// builds; the other four are read verbatim.
export function statusBuckets(state) {
  const s = state && typeof state === 'object' ? state : {}
  return {
    blocked: [...asArray(s.surfaced), ...asArray(s.handbacks)],
    completed: asArray(s.completed),
    inFlight: asArray(s.inFlight),
    queued: asArray(s.queued),
    skipped: asArray(s.skipped),
  }
}

// Every repo name that appears in ANY rendered section, in section order, WITH duplicates
// (a repo in two sections appears twice — that is what doubleCountedRepos detects).
export function accountedRepos(state) {
  const b = statusBuckets(state)
  const out = []
  for (const name of ACCOUNTING_SECTIONS) for (const m of asArray(b[name])) {
    const k = memberKey(m)
    if (k) out.push(k)
  }
  return out
}

// Own repos that reached NO rendered section — the class this whole item exists to make loud.
export function unaccountedRepos(ownRepos, state) {
  return assertCompleteAccounting(ownRepos, statusBuckets(state), { label: 'RELAY_STATUS', id: '8c85' }).missing
}

// Repos rendered in more than one section — `own_count == sum(sections)` is violated by a
// duplicate exactly as much as by an omission.
export function doubleCountedRepos(state) {
  return assertCompleteAccounting([], statusBuckets(state), {
    label: 'RELAY_STATUS', id: '8c85',
    exclusiveBuckets: EXCLUSIVE_SECTIONS, unitKey: statusUnitKey,
  }).duplicated
}

// The wired invariant: thin wrapper over the generic core.
export function assertStatusAccounting(ownRepos, state) {
  return assertCompleteAccounting(ownRepos, statusBuckets(state), {
    label: 'RELAY_STATUS accounting (every own repo in at least one section, with a reason)',
    id: '8c85',
    exclusiveBuckets: EXCLUSIVE_SECTIONS,   // id:2f6b — completed/blocked accumulate; see above
    unitKey: statusUnitKey,                 // id:2f6b — the same UNIT twice is still a defect
  })
}
