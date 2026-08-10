// prompt-size-gate.mjs (id:4f9b) — size the assembled child prompt BEFORE dispatch and refuse
// with the REAL reason instead of letting the child die with a bare `Prompt is too long`.
//
// The failure this replaces (run relay-20260801-213927-29875, dotclaude-skills, 2026-08-01):
// an execute child was dispatched against a 523,926-byte ROADMAP.md, exhausted its context
// window, and died. relay-loop.js recorded the generic `child agent failed/skipped (API error
// or terminal failure)` and RELAY_STATUS.md then printed `## Blocked / HANDBACKs _(none)_`
// while 481 lines of unverified work sat parked as an orphan. The cause appeared NOWHERE a
// human would look. That is exactly the silent-swallow the id:4347 rule bans: a detectable,
// nameable failure reported as an anonymous one.
//
// The measurement CANNOT be taken in relay-loop.js: it runs inside the Workflow sandbox, which
// has no filesystem and no `process.env` (id:2ec4 / id:61fa's premise problem). So
// classify-repo.sh stats ROADMAP.md on the host and ships `roadmap_bytes` on the unit; this
// module is the pure decision function over that number.
//
// PURE functions, unit-testable. relay-loop.js carries byte-identical inline copies (the
// Workflow sandbox cannot `import`); a structural test pins the wiring. Keep the two in sync.

// Chars-per-token for the estimate. Deliberately CRUDE: this gate decides "obviously will not
// fit" vs "plausibly fits", not a precise budget, and a real tokenizer is unavailable in the
// sandbox. ~4 chars/token is the standard English-prose approximation and errs on the LOW side
// for markdown ledgers (id-comments and punctuation tokenize denser), so the estimate
// UNDER-counts — which keeps the gate conservative: it fires late, never early.
export const CHARS_PER_TOKEN = 4

// The dispatch-time payload budget, in tokens. Derivation (do not "round this up" without
// redoing it): the child's window is ~200k. Measured deaths sat at peak context 176,841 tok
// (dotclaude-skills, run relay-20260728-212859-24420) and the surviving children need real
// working room for exploration, edits and tool results — id:9eb7 records "well under 100k
// working room" as the pathology, not the target. So the FIXED payload the child must swallow
// before it can do anything (its dispatch prompt + the ledger it is contractually required to
// read) is capped at 100k, leaving ~100k of working room.
//
// Calibration against the two known points: the 2026-08-01 ROADMAP (523,926 B ≈ 131k tok
// + overhead) is OVER and would have been refused; the same file after roadmap-archive.sh
// (254,087 B ≈ 63.5k tok + overhead) is UNDER and dispatches normally. The gate therefore
// fires on the ledger that actually killed a child and not on the one that does not.
export const DISPATCH_TOKEN_BUDGET = 100000

// Fixed overhead every child pays on top of its dispatch prompt and the ROADMAP, in tokens:
// the executor contract (~5.5k, measured id:9eb7) plus conventions.md (~4k) plus the harness
// system prompt and tool definitions. Counted so the budget is measured against what the child
// really carries, not just the two things we can size directly.
export const FIXED_OVERHEAD_TOKENS = 12000

// estimateDispatchTokens — tokens the child must swallow before it can start work.
// promptChars: length of the assembled unitPrompt string. roadmapBytes: the host-measured
// size of ROADMAP.md (0 when unmeasured).
export function estimateDispatchTokens(promptChars, roadmapBytes) {
  const p = Number.isFinite(promptChars) && promptChars > 0 ? promptChars : 0
  const r = Number.isFinite(roadmapBytes) && roadmapBytes > 0 ? roadmapBytes : 0
  return Math.round((p + r) / CHARS_PER_TOKEN) + FIXED_OVERHEAD_TOKENS
}

// oversizeDispatchReason — '' when the unit is safe to dispatch, otherwise ONE line naming
// BOTH the cause and the remedy, suitable verbatim as a handback reason and as the
// RELAY_STATUS.md "Blocked" row.
//
// FAIL-OPEN by construction: a unit with no `roadmap_bytes` (an older queue entry, an injected
// unit, a shard-produced unit) measures as 0 and can never trip the gate. Refusing to dispatch
// on ABSENT data would be strictly worse than the death this prevents — the gate only ever
// acts on a positive measurement.
export function oversizeDispatchReason(unit, promptChars, budget) {
  const u = unit || {}
  const cap = Number.isFinite(budget) && budget > 0 ? budget : DISPATCH_TOKEN_BUDGET
  const roadmapBytes = Number.isFinite(u.roadmap_bytes) && u.roadmap_bytes > 0 ? u.roadmap_bytes : 0
  if (!roadmapBytes) return ''   // unmeasured ⇒ fail OPEN, never block on missing data
  const est = estimateDispatchTokens(promptChars, roadmapBytes)
  if (est <= cap) return ''
  const roadmapTok = Math.round(roadmapBytes / CHARS_PER_TOKEN)
  return `prompt-size gate (id:4f9b): NOT dispatched — the assembled ${u.verdict || 'child'} prompt for ${u.repo || '(repo)'} is ~${est} tok, over the ${cap} tok dispatch budget, so the child would die with "Prompt is too long" instead of doing work. CAUSE: ROADMAP.md is too large — ${roadmapBytes} bytes (~${roadmapTok} tok of the estimate). REMEDY: run \`~/.claude/skills/relay/scripts/roadmap-archive.sh ${u.path || '<repo-path>'}\` to move the done \`- [x]\` items into ROADMAP.archive.md, commit, and re-run the pool. This repo is skipped, not failed: no worktree was created and no work was lost.`
}
