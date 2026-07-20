// round-plan.mjs (id:dc5b) — the C2 one-unit-per-repo-per-round scheduler invariant.
// DECIDED C2 at meeting mtg-1726 (2026-07-19, D3): NEVER dispatch two units for the same
// repo in one round. Root cause it dissolves: an execute+review pair dispatched for the SAME
// repo in one round collides on the non-union ROADMAP.md at integrate (observed: loderite run
// relay-20260717-100452-13146 — the review→execute re-chain fired on child-settle, the execute
// child branched from a pre-promotion main and conflicted with the merged review). The two
// units share one shared, line-scoped, NON-UNION ledger file; merging both in one round is a
// merge-time collision no worktree isolation can prevent (the dc5b topology invariant). The
// only structural fix is to not let both dispatch in the same round — the lower-priority
// duplicate is DEFERRED (loudly, never silently dropped) to the next round's fresh discovery,
// where the first unit has already integrated and moved the ledger forward.
//
// PURE function, unit-testable. relay-loop.js carries a byte-equivalent inline copy (the
// Workflow sandbox cannot `import` — no filesystem/require), per the established id:1735
// handback-summary.mjs pattern; a structural test pins the wiring. Keep the two in sync.

// enforceOneUnitPerRepo — given the units the round would dispatch, IN SCHEDULING ORDER
// (which is already verdict-class-priority order at the call site), keep exactly the FIRST
// unit per repo and defer every later same-repo unit.
//   input : [{ repo, verdict, ... }, ...]   (scheduling order — earlier = higher priority)
//   output: { plan: [...], deferred: [...] }
//     - plan     — the surviving units, order PRESERVED, at most one per repo. First-in wins,
//                  so within a repo the higher verdict-class unit (review before execute, etc.)
//                  is the one that dispatches.
//     - deferred — every later same-repo unit, in encounter order, carried WHOLE (so the
//                  surface can name repo + verdict of what was deferred). Never dropped.
export function enforceOneUnitPerRepo(units) {
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
