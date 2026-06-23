// redispatch-guard.mjs (id:365b) — the re-dispatch circuit breaker, mechanism 2 of the
// relay anti-spin fix. A DETERMINISTIC JS backstop that catches ANY dispatch spin even if
// the discover shard's principled recurring-audit gate (mechanism 1) slips: if the SAME
// (repo, verdict) unit is dispatched more than thrice in one pool run WITHOUT its work_sig
// changing (work_sig is stable across the pool's own `relay: checkpoint` churn, so an
// unchanged sig means "no substantive change since last dispatch"), suppress it.
//
// This is the SAME logic relay-loop.js runs inline (it cannot `import` — Workflow modules
// run in a sandbox with no filesystem/require), extracted as a tiny PURE function so it is
// unit-testable. relay-loop.js carries a byte-identical inline copy guarded by a structural
// test; keep the two in sync.
//
// applyRedispatchGuard(units, guard) mutates `guard` (the per-run persistent counter object,
// keyed `${repo}:${verdict}` → {sig, count}) and returns {kept, suppressed}:
//   - kept:       units to dispatch this round.
//   - suppressed: {unit, reason} for units the breaker tripped (count would reach 4 with an
//                 unchanged work_sig). Pushed to `surfaced` by the caller.
// Semantics: a unit may dispatch on counts 1,2,3 and is suppressed once count would reach 4
// ("not more than thrice"). A work_sig change resets the counter (genuinely new work).
// Injected units (u.injected) are EXEMPT — an explicit user request is never auto-suppressed.

export function applyRedispatchGuard(units, guard, runId) {
  const kept = [], suppressed = []
  for (const u of units) {
    if (u.injected) { kept.push(u); continue }
    const key = `${u.repo}:${u.verdict}`
    const sig = u.work_sig || ''
    const prev = guard[key]
    if (prev && prev.sig === sig) prev.count++
    else guard[key] = { sig, count: 1 }
    if (guard[key].count > 3) {
      suppressed.push({
        unit: u,
        reason: `circuit breaker (id:365b): ${u.repo} ${u.verdict} dispatched >3× this run with no substantive change (work_sig unchanged) — skipping until new work or a human intervenes; cost hint: relay-burn.sh --run ${runId}`,
      })
    } else {
      kept.push(u)
    }
  }
  return { kept, suppressed }
}
