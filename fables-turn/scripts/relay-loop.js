export const meta = {
  name: 'relay-loop',
  description: 'Priority-mixed 5-wide autonomous relay pool — serialized integrator, quota-guarded, STRONG_TIER-aware',
  phases: [
    { title: 'Discover', detail: 'classify confirmed repos into execute/review/handoff/idle units' },
    { title: 'Dispatch', detail: '5-wide pool: execute slots first, backfill with review/handoff' },
    { title: 'Integrate', detail: 'serialized merge → ckpt-tag → push per completed unit' },
  ],
}

// STRONG_TIER: model override for review and handoff agents.
// Execute agents (Sonnet) never receive this override — only review and handoff agents do.
// Values: 'fable' (default) | 'opus'
// Passed via args.STRONG_TIER from the front-door SKILL.md (set by STRONG_TIER env var or --strong-tier flag).
const STRONG_TIER = (args && args.STRONG_TIER) || 'fable'
const STRONG_MODEL = STRONG_TIER === 'opus' ? 'claude-opus-4-8' : 'claude-fable-5'

log(`relay-loop: STRONG_TIER=${STRONG_TIER} → model=${STRONG_MODEL}`)

// Full pool implementation: HARD item id:83c9.
//
// Tier dispatch contract (enforced in id:83c9 implementation):
//   Review agents:   agent(reviewPrompt,  { model: STRONG_MODEL, phase: 'Dispatch' })
//   Handoff agents:  agent(handoffPrompt, { model: STRONG_MODEL, phase: 'Dispatch' })
//   Execute agents:  agent(executePrompt, { phase: 'Dispatch' })  ← no model override (Sonnet default)
