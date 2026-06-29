// drain.mjs (id:d58f) — fleet-quiescence drain logic for the autonomous relay loop.
//
// PROBLEM (observed 2026-06-29, run relay-20260629-125922): the outer loop's drain detector
// (id:2d20) stops only after 2 consecutive rounds that integrate ZERO checkpoints
// (`produced === 0`). But a round whose only output is a CONFIRMING review — a review that
// verified-green and reopened/added nothing — still counts as "produced > 0", so it resets the
// dry counter and the pool spins toward MAX_ROUNDS re-discovering + re-reviewing an already-
// drained fleet. The pathological driver: a repo that keeps gaining commits from a CONCURRENT
// session (e.g. the pool's own cwd repo under live editing) is re-reviewed every round, each
// review confirming-green → never dry. The [ROUTINE] backlog is gone and every open [HARD] is
// gated ([HARD — meeting]/[decision gate]/[hands], open_hard_pool=0), so there is no autonomous
// work left — yet the loop won't wind down.
//
// FIX: redefine "progress" as SUBSTANTIVE production, not any checkpoint. A confirming-only
// review no longer resets the dry counter, so the existing dry>=2 → drain machinery fires when
// the fleet is genuinely quiescent. Reversible & low-regret: discovery is fresh each round, so a
// genuinely-new commit/injection is SEEN and dispatched (→ substantive) BEFORE draining; the
// loop is restartable. No data loss.
//
// PURE + unit-tested here; relay-loop.js (the Workflow sandbox cannot `import`) carries
// BYTE-IDENTICAL inline copies of these bodies — keep the two in sync (the pool-args.mjs /
// redispatch-guard.mjs precedent).

// unitIsSubstantive(verdict, report) — did this COMPLETED unit make real backlog progress?
//   - execute / hard / handoff: an integrated checkpoint is always real committed work → true.
//   - review: true ONLY if it actually changed the backlog — reopened a ROADMAP item, surfaced
//     open [ROUTINE] work (routine_open > 0, which re-enqueues an execute unit this same pool),
//     or raised a gaming flag. A review that merely verified-green and reopened/added nothing is
//     CONFIRMATION, not progress → false (this is the spin we stop).
// A null/garbled report is treated as NON-substantive (conservative: don't keep the pool alive
// on a missing signal). Only ever called for units that integrated (contract_met).
export function unitIsSubstantive(verdict, report) {
  if (verdict === 'execute' || verdict === 'hard' || verdict === 'handoff') return true
  if (verdict === 'review') {
    if (!report) return false
    const reopened = Array.isArray(report.reopened) ? report.reopened.length : 0
    const gaming = Array.isArray(report.gaming_flags) ? report.gaming_flags.length : 0
    const routineOpen = Number(report.routine_open) || 0
    return reopened > 0 || gaming > 0 || routineOpen > 0
  }
  // Unknown verdict: be conservative and treat as substantive (don't drain on an unrecognized
  // unit type — under-draining merely runs an extra round, over-draining could strand work).
  return true
}

// classifyDrainBacklog(blocked) — when the loop winds down, bucket the surfaced/blocked repos by
// WHY they were not actionable, so the wind-down message tells the human what (if anything) is
// left and where to take it. `blocked` is an array of {repo, reason} (state.blocked). Matching is
// on the reason strings the discovery emits. Returns {finished, gated, circuitBroken, dirty,
// other} arrays of repo names + a one-line `summary` string. Pure (no I/O).
export function classifyDrainBacklog(blocked) {
  const buckets = { finished: [], gated: [], circuitBroken: [], dirty: [], other: [] }
  for (const b of (blocked || [])) {
    const repo = b && b.repo ? b.repo : '?'
    const reason = (b && b.reason) ? String(b.reason) : ''
    if (/finished repo|anti-false-handoff|0 open items/i.test(reason)) buckets.finished.push(repo)
    else if (/HARD backlog|\[HARD —|no open \[HARD — pool\]|demote-guard|needs a \/meeting|@manual|human-only|requires human/i.test(reason)) buckets.gated.push(repo)
    else if (/circuit breaker/i.test(reason)) buckets.circuitBroken.push(repo)
    else if (/dirty main tree|dirty/i.test(reason)) buckets.dirty.push(repo)
    else buckets.other.push(repo)
  }
  const parts = []
  if (buckets.finished.length)     parts.push(`${buckets.finished.length} finished`)
  if (buckets.gated.length)        parts.push(`${buckets.gated.length} gated (→ /relay human or /meeting: ${buckets.gated.join(', ')})`)
  if (buckets.circuitBroken.length) parts.push(`${buckets.circuitBroken.length} circuit-broken`)
  if (buckets.dirty.length)        parts.push(`${buckets.dirty.length} dirty`)
  if (buckets.other.length)        parts.push(`${buckets.other.length} other`)
  const summary = parts.length ? parts.join(' · ') : 'no blocked repos'
  return { ...buckets, summary }
}
