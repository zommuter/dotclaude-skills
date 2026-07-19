// handback-summary.mjs (id:1735) — the persistent-accumulator / per-round-view split that fixes
// the "handbacks:[] while the event log records a handback" bug. Root cause: relay-loop.js used
// to REASSIGN a single `state.blocked` array wholesale every round (from `discovery.surfaced`,
// stamping `worktreePath:'-'`) while FIVE handback sites pushed into that same array as if it
// accumulated across rounds. Any handback from round N was destroyed the moment round N+1's
// reassignment ran, so the run's returned `handbacks` summary silently lost it — while the
// event log (relay-events.jsonl) recorded it correctly the whole time. That was two incompatible
// jobs sharing one array; this module makes them two arrays with two different lifetimes:
//   - the per-round SURFACED VIEW (`buildSurfacedView`) — rebuilt fresh every round, always
//     reflects THIS round's discovery.surfaced (suppressed/gated/dirty repos). Reassignment here
//     is CORRECT and intentional.
//   - the PERSISTENT HANDBACK ACCUMULATOR — every real handback push targets this array, which
//     is NEVER reassigned for the life of the run (only ever pushed to). `reconcileHandbacks`
//     derives the final summary from it; `assertHandbackInvariant` is the loud backstop that
//     catches a regression of the original bug.
//
// PURE functions, unit-testable. relay-loop.js carries byte-identical inline copies (the
// Workflow sandbox cannot `import` — no filesystem/require); a structural test pins the wiring.
// Keep the two in sync.

// buildSurfacedView — rebuild the per-round surfaced/suppressed-repo view from
// discovery.surfaced. Every entry carries worktreePath:'-' (these repos never dispatched, so
// there is no worktree) — this is what makes them structurally distinguishable from real
// handback entries in reconcileHandbacks below.
export function buildSurfacedView(surfaced) {
  return (surfaced || []).map(s => ({ repo: s.repo, reason: s.reason, worktreePath: '-' }))
}

// reconcileHandbacks — derive the run's returned `handbacks` summary from the PERSISTENT
// accumulator. Filters out entries with no real worktree (worktreePath missing or '-') — those
// are surfaced-view-shaped pushes (e.g. the id:5ac6 INTENSIVE fail-closed skip) that never had a
// worktree to hand back.
export function reconcileHandbacks(accumulator) {
  return (accumulator || []).filter(b => b && b.worktreePath && b.worktreePath !== '-')
}

// assertHandbackInvariant — the loud backstop. EQUALITY over the real-worktree subset (id:4a46):
// every `pushEvent('handback', …)` emitted this run must have a corresponding entry in the
// persistent accumulator (same repo + reason) — the FORWARD direction — AND every accumulator
// entry with a REAL worktree (per `reconcileHandbacks`'s own `worktreePath && !== '-'` filter)
// must have a corresponding emitted event (same repo + reason) — the REVERSE direction. The
// `worktreePath:'-'` INTENSIVE fail-closed entries are excluded from the reverse check exactly
// as `reconcileHandbacks` already excludes them from the summary — they are not handbacks in
// the summary's sense. A forward violation means an event was recorded as happening but the
// run's summary has no matching entry for it: exactly the shape of the original id:1735 bug. A
// reverse violation means a real handback happened but no event was ever emitted for it: the
// event log under-reporting id:4a46 closes. Returns {ok, violations} — each violation is tagged
// `direction: 'forward'|'reverse'` so the caller's log names which direction tripped; the caller
// logs + surfaces `violations` rather than silently returning the (possibly incomplete) list.
export function assertHandbackInvariant(emittedEvents, accumulator) {
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
