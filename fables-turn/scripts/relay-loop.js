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

// RELAY_STATUS_PATH: output file for cross-repo rollup. Overridable for testing.
const RELAY_STATUS_PATH = (args && args.RELAY_STATUS_PATH) || '~/.config/fables-turn/RELAY_STATUS.md'

log(`relay-loop: STRONG_TIER=${STRONG_TIER} → model=${STRONG_MODEL}`)

// buildRelayStatus — generate RELAY_STATUS.md content from a run-state snapshot.
// state shape:
//   { runId, ts, inFlight: [{repo, mode, agentId}],
//     completed: [{repo, mode, ckptTag, pushStatus}],
//     queued:    [{repo, verdict}],
//     blocked:   [{repo, reason, worktreePath}],
//     quota:     [{bucket, pctRemaining, resetTime}],
//     reviewMe:  [{repo, count, path}] }
function buildRelayStatus(state) {
  const header = `# RELAY_STATUS — last updated ${state.ts}  run: ${state.runId}`

  const inFlight = state.inFlight && state.inFlight.length
    ? state.inFlight.map(r => `- ${r.repo}  mode=${r.mode}  agent=${r.agentId}`).join('\n')
    : '_(none)_'

  const completed = state.completed && state.completed.length
    ? state.completed.map(r => `- ${r.repo}  mode=${r.mode}  ckpt=${r.ckptTag}  push=${r.pushStatus}`).join('\n')
    : '_(none)_'

  const queued = state.queued && state.queued.length
    ? state.queued.map(r => `- ${r.repo}  verdict=${r.verdict}`).join('\n')
    : '_(none)_'

  const blocked = state.blocked && state.blocked.length
    ? state.blocked.map(r => `- ${r.repo}  reason=${r.reason}  worktree=${r.worktreePath}`).join('\n')
    : '_(none)_'

  const quota = state.quota && state.quota.length
    ? state.quota.map(r => `- ${r.bucket}  remaining=${r.pctRemaining}%${r.resetTime ? '  reset=' + r.resetTime : ''}`).join('\n')
    : '_(unknown)_'

  const reviewMe = state.reviewMe && state.reviewMe.length
    ? state.reviewMe.map(r => `- ${r.repo}  open=${r.count}  path=${r.path}`).join('\n')
    : '_(none)_'

  return [
    header,
    '',
    '## In-flight',
    inFlight,
    '',
    '## Completed this run',
    completed,
    '',
    '## Queued',
    queued,
    '',
    '## Blocked / HANDBACKs',
    blocked,
    '',
    '## Quota remaining',
    quota,
    '',
    '## REVIEW_ME open items',
    reviewMe,
  ].join('\n')
}

// writeRelayStatus — write RELAY_STATUS.md via an agent (Workflow JS has no fs access)
// and emit a condensed log() line for the /workflows live view.
async function writeRelayStatus(state, statusPath) {
  const content = buildRelayStatus(state)
  const path = statusPath || RELAY_STATUS_PATH
  const inFlightCount = (state.inFlight || []).length
  const completedCount = (state.completed || []).length
  const blockedCount = (state.blocked || []).length
  log(`RELAY_STATUS updated: in-flight=${inFlightCount} completed=${completedCount} blocked=${blockedCount} → ${path}`)
  await agent(
    `Write the following content verbatim to the file at path ${path} (expand ~ to $HOME). Create parent directories if needed. Do not truncate or reformat.

Content:
${content}`,
    { label: 'write-relay-status', phase: 'Integrate' }
  )
}

// Full pool implementation: HARD item id:83c9.
//
// Tier dispatch contract (enforced in id:83c9 implementation):
//   Review agents:   agent(reviewPrompt,  { model: STRONG_MODEL, phase: 'Dispatch' })
//   Handoff agents:  agent(handoffPrompt, { model: STRONG_MODEL, phase: 'Dispatch' })
//   Execute agents:  agent(executePrompt, { phase: 'Dispatch' })  ← no model override (Sonnet default)
//
// writeRelayStatus() is called after each integration step and each phase transition.
