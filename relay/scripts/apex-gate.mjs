// apex-gate.mjs (id:7986/da51) — the apex `hard`-dispatch gate.
//
// TWO owner-ratified rulings this module encodes (2026-08-22/23, TODO.md id:7986/id:da51):
//   1. `hard` (an Opus-apex child working ONE bounded [HARD] item) is dispatched ONLY on an
//      `--afk` run. `review` and `handoff` dispatch at apex REGARDLESS of `--afk` — they are
//      NEVER withheld by this gate. (Owner 2026-08-22, after a live pool spent Opus on three
//      [HARD] units against his cap while `--afk` had zero consumers in relay-loop.js.)
//   2. The gate asks `strongTier === 'opus'` — NEVER a model-id string. The concrete model id is
//      a pure OUTPUT value elsewhere (relay-loop.js's STRONG_MODEL); this module observes no
//      model id and contains no model-id literal at all, so bumping that pin can never change
//      what this gate decides (the da51 trap: comparing a literal makes a correct bump defer
//      every hard unit while reporting "requires apex Opus" — false precisely when the pin is
//      right).
//
// PURE function, unit-testable (tests/test_apex_afk_hard_gate_7986.sh). relay-loop.js carries a
// byte-equivalent inline copy (the Workflow sandbox cannot `import`), per the established
// id:dc5b round-plan.mjs / id:1735 handback-summary.mjs pattern — a structural test pins the
// wiring. Keep the two in sync.

// enforceApexGate — given the round's dispatchable units IN SCHEDULING ORDER, withhold `hard`
// units unless BOTH the strong tier is apex (`opus`) AND the run was launched `--afk`.
//   input : units      — [{ repo, verdict, ... }, ...] (scheduling order)
//           strongTier  — 'opus' | 'fable' (NEVER a model id — the whole point of da51)
//           afk         — boolean, true when the run was launched --afk
//   output: plan        — surviving units, order PRESERVED; `hard` units withheld per the rules
//                          above, `review`/`handoff`/`execute` (and any other verdict) untouched.
//           hardDeferred — every withheld `hard` unit, carried WHOLE plus a `gateReason` string:
//                          - non-apex tier: reason names APEX (never blames --afk, which may
//                            have been supplied — the da51 self-contradiction class)
//                          - apex tier but no --afk: reason names --afk
//                          Never dropped, never silently idle — mirrors the proven
//                          `intensive:<res>` surfaced-as-skipped shape.
export function enforceApexGate(units, { strongTier, afk } = {}) {
  const isApex = strongTier === 'opus'
  const plan = []
  const hardDeferred = []
  for (const u of units || []) {
    if (u && u.verdict === 'hard') {
      if (!isApex) {
        hardDeferred.push({ ...u, gateReason: 'HARD-execute requires apex Opus (STRONG_TIER is not opus)' })
        continue
      }
      if (!afk) {
        hardDeferred.push({ ...u, gateReason: 'HARD-execute at apex requires --afk (owner 2026-08-22)' })
        continue
      }
    }
    plan.push(u)
  }
  return { plan, hardDeferred }
}
