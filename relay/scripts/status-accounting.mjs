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
// land in exactly one rendered section, every round, with a reason.** This module owns that
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

// ── Generic core: partition completeness over an enumerated universe. ──────────────────────
// universe: array of member keys that MUST each be accounted for.
// buckets:  { <bucketName>: [member, …] } — members may be strings or row objects.
// returns:  { ok, missing, duplicated, message }
export function assertCompleteAccounting(universe, buckets, opts) {
  const o = opts && typeof opts === 'object' ? opts : {}
  const label = typeof o.label === 'string' && o.label ? o.label : 'accounting'
  const id = typeof o.id === 'string' ? o.id : ''
  const uni = asArray(universe).map(memberKey).filter(Boolean)
  const b = buckets && typeof buckets === 'object' ? buckets : {}

  // member key → the bucket names it appeared in (repeats within one bucket count too).
  const placement = new Map()
  for (const bucketName of Object.keys(b)) {
    for (const m of asArray(b[bucketName])) {
      const k = memberKey(m)
      if (!k) continue
      if (!placement.has(k)) placement.set(k, [])
      placement.get(k).push(bucketName)
    }
  }

  const missing = uni.filter((k) => !placement.has(k)).sort()
  const duplicated = [...placement.entries()]
    .filter(([, where]) => where.length > 1)
    .map(([k]) => k)
    .sort()

  const ok = missing.length === 0 && duplicated.length === 0
  const tag = id ? ` (id:${id})` : ''
  const bucketNames = Object.keys(b).sort().join(', ')
  let message
  if (ok) {
    message = `${label}: OK — all ${uni.length} member(s) accounted for in exactly one of [${bucketNames}]${tag}`
  } else {
    const parts = []
    if (missing.length) {
      parts.push(`${missing.length} of ${uni.length} reached NO section [${bucketNames}] — ${missing.join(', ')}`)
    }
    if (duplicated.length) {
      const detail = duplicated
        .map((k) => `${k} in ${placement.get(k).sort().join('+')}`)
        .join('; ')
      parts.push(`${duplicated.length} double-counted (must be exactly one section) — ${detail}`)
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
  return assertCompleteAccounting([], statusBuckets(state), { label: 'RELAY_STATUS', id: '8c85' }).duplicated
}

// The wired invariant: thin wrapper over the generic core.
export function assertStatusAccounting(ownRepos, state) {
  return assertCompleteAccounting(ownRepos, statusBuckets(state), {
    label: 'RELAY_STATUS accounting (every own repo in exactly one section, with a reason)',
    id: '8c85',
  })
}
