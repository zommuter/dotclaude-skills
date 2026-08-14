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

// noWorkEnumerationAlarm (id:bfbf, routed:9371) — the DETECTOR behind the no-work handback.
// recordNoWorkHandback above accepts a whole-dispatch "nothing dispatchable" claim on the
// child's word alone and stamps the negative cache with it, which then SUPPRESSES re-dispatch
// until work_sig changes. That is correct when the claim is true and actively harmful when it
// is not: on 2026-08-14 a loderite HARD child re-derived the pool-lane enumeration by raw grep
// on the RETIRED "[HARD — pool]" spelling, found 0, and refused 5 real bare-"[HARD]" items
// (id:7517/routed:2d94) — the pool recorded that as a clean drain and parked a repo that had
// work. Nothing in the pipeline could tell a correct "nothing to do" from a child that looked
// in the wrong place, because the claim carried no evidence.
//
// The evidence is the ENUMERATION: a child claiming zero dispatchable must return the ids it
// CONSIDERED. The discriminator is SET DISJOINTNESS against the resolved pool list, NOT
// emptiness:
//   openHardPool > 0 AND (poolIds ∩ consideredIds) == ∅   ⇒ ALARM, cleanDrain=false
//   openHardPool > 0 AND the two sets OVERLAP             ⇒ accepted (the child really did look
//                                                           at the queue and rejected it)
//   openHardPool == 0                                     ⇒ accepted (nothing to enumerate)
//   pool set unusable                                     ⇒ 'enumeration-unevaluable' (below)
//
// WHY NOT an emptiness check — this is the whole correction, and it is load-bearing: in the
// REAL incident the considered list was NOT empty. The loderite child returned FIFTEEN ids
// (containers 16b2/ca44/d215/5d76/5d00/9403/23aa/40ad and gated
// 3d11/8452/9a6b/c8ad/c2f3/1a09/55c7), every one of them correctly gated — and NOT ONE of them
// was among the five items the counter had counted. An empty-list detector would have stayed
// SILENT through the exact failure it was written for. Zero overlap between what the counter
// counted and what the child actually looked at is the signal; the empty list is merely a
// SUBSUMED instance of it (∅ ∩ anything = ∅, so it still fires).
// An ABSENT list is treated exactly like an empty one: silence must never read as "considered
// everything" — an older child that never learned to enumerate is precisely a child whose claim
// cannot be trusted.
// SCOPE: only a WHOLE-DISPATCH zero-dispatchable claim, i.e. route missing/"none" with no
// handback_item. An ITEM-level handback (route=decision-gate/hard-split/human on a named item)
// is not a claim about the queue at all and is gated durably by handback-followup.py (id:3801).
//
// THREE OUTCOMES, not two. The detector is allowed to say "I could not evaluate this", but it
// is NEVER allowed to say nothing:
//   null                              — ACCEPTED (evidenced, or out of scope).
//   kind:'unevidenced-no-enumeration' — ALARM: the child returned no enumeration at all.
//   kind:'unevidenced-disjoint'       — ALARM: it enumerated, but ZERO overlap with the queue.
//   kind:'enumeration-unevaluable'    — THIRD STATE: openHardPool > 0 but the resolved pool set
//                                       is unusable, so disjointness cannot be decided. NOT a
//                                       clean drain and NOT an assertion of disjointness.
// Why the third state rather than the two obvious branches: ACCEPTING silently would recreate
// the very defect this detector closes (open_hard_pool > 0 with an unusable id list is itself a
// signal that something upstream failed to NAME its work — swallowing it is the silent fallback
// the no-silent-swallow rule bans), while ALARMING as though disjointness were PROVEN is a
// false positive that fires on every legitimate older queue entry, and a detector that cries
// wolf gets ignored, which costs the true positives too. So it surfaces in the same place, with
// its own wording, and does not block the handback.
// The two upstream faults behind it are DIFFERENT and are named separately in the message:
// `poolIds` ABSENT/empty (an older queue entry, or a producer that never emitted the field) vs.
// PRESENT-BUT-UNNAMEABLE (entries exist but none resolves to an id — every ROADMAP line
// ambiguous under the routed:3ad9 multi-marker rule).
//
// PURE: returns null when accepted, else {repo, verdict, openHardPool, kind, cleanDrain:false,
// overlap, reason}. `overlap` is null in the unevaluable state — it was never computed, and
// reporting 0 there would fake a disjointness finding.
// The caller logs + surfaces the result AND skips recordNoWorkHandback for ALL THREE non-null
// outcomes — nothing this function declines to bless may become a suppression.
export function noWorkEnumerationAlarm(ctx) {
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
