// handback-guard.mjs (id:1432) — dispatch-level suppression + loud repeat-tracking for
// WHOLE-DISPATCH handbacks. Complements the id:365b re-dispatch circuit breaker (which caps
// ANY repeated dispatch at >3×) and handback-followup.py / id:3801 (which durably gates
// ITEM-level handbacks). The gap this closes: a child that hands back the WHOLE dispatch with
// "no executor-actionable work / classifier verdict wrong" (route missing or "none", no
// handback_item) produced NO durable ROADMAP action, so discovery re-dispatched the same
// bogus verdict every round (observed: it-infra execute in rounds 3,5,6,7,8 of one run —
// 5 wasted children). This adds a negative cache so a no-work verdict can't loop, plus a
// per-run handback counter so a repeating handback surfaces LOUDLY as a bug signal.
//
// PURE functions, unit-testable. relay-loop.js carries byte-identical inline copies (the
// Workflow sandbox cannot `import` — no filesystem/require); a structural test pins the wiring.
// Keep the two in sync.

// recordNoWorkHandback — called at integrate time when a child hands back with NO durable
// route (route missing or "none"). Stamps the (repo,verdict) key with the unit's work_sig AT
// HANDBACK TIME. work_sig (id:365b) is STABLE across the pool's own `relay: checkpoint` churn,
// so it does NOT trivially bump on the empty-integrate checkpoint — keying on it means the
// suppression clears only on a GENUINE change, never on the pool's own bookkeeping. Pure
// mutation of negCache.
export function recordNoWorkHandback(negCache, repo, verdict, sig) {
  negCache[`${repo}:${verdict}`] = { sig: sig || '' }
}

// applyNoWorkSuppression — dispatch pre-filter. For each non-injected unit whose (repo,verdict)
// carries a negCache entry: if the stamped sig EQUALS the unit's current work_sig (nothing
// genuinely changed since the no-work handback), SUPPRESS it (do not re-dispatch). If the sig
// DIFFERS (a value NOT equal to the handback-time sig ⇒ genuine churn), CLEAR the entry and
// dispatch normally. Injected units (id:baf1) are EXEMPT — an explicit user request is never
// auto-suppressed. Returns {kept, suppressed:[{unit,reason}]}; the caller pushes suppressed
// reasons to `surfaced`.
export function applyNoWorkSuppression(units, negCache, runId) {
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
      if (prev) delete negCache[key]  // work_sig changed ⇒ genuine churn ⇒ allow re-dispatch
      kept.push(u)
    }
  }
  return { kept, suppressed }
}

// trackHandback — increment the per-(repo,verdict) handback counter for this run and record the
// last reason. Call on EVERY child handback (contract_met=false). Returns the updated entry.
export function trackHandback(tracker, repo, verdict, reason) {
  const key = `${repo}:${verdict}`
  const e = tracker[key] || (tracker[key] = { repo, verdict, count: 0, lastReason: '' })
  e.count++
  e.lastReason = String(reason == null ? '' : reason).replace(/\s+/g, ' ').trim().slice(0, 200)
  return e
}

// handbackAlerts — the LOUD signal: every (repo,verdict) that handed back >= threshold times
// this run (default 2). A repeating handback is a bug signal, not noise — surfaced in the run's
// exit summary + RELAY_STATUS.md so it is never silently looped. Returns a sorted array of
// {repo, verdict, count, lastReason} (highest count first).
export function handbackAlerts(tracker, threshold = 2) {
  return Object.values(tracker)
    .filter(e => e.count >= threshold)
    .sort((a, b) => b.count - a.count || a.repo.localeCompare(b.repo) || a.verdict.localeCompare(b.verdict))
    .map(e => ({ repo: e.repo, verdict: e.verdict, count: e.count, lastReason: e.lastReason }))
}
