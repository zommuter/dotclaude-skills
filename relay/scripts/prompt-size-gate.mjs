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

// The dispatch-time payload budget, in tokens.
//
// TIER DERIVATION (id:b018 — re-derived 2026-08-21 from the tiers this pool actually
// dispatches, rather than left as an unexplained flat number). relay-loop.js dispatches
// exactly four models: `claude-opus-4-8` (hard/review), `claude-fable-5` (hard/review when
// STRONG_TIER=fable), the default Sonnet (execute/integrate) and `haiku` (the id:4239
// mechanical fallback). ALL FOUR carry a 200,000-token context window — no dispatched tier
// has a different one, and the 1M-context variants are not dispatched here — so a tier-keyed
// budget table would hold four identical rows and buy nothing. The budget is therefore ONE
// number, derived as: 200,000-token window x 50% reserved as working room = 100,000 tokens of
// fixed dispatch payload. If a tier with a different window is ever dispatched, THIS is the
// line to split per tier (oversizeDispatchReason already takes a `budget` override).
//
// Why 50% and not more: Measured deaths sat at peak context 176,841 tok
// (dotclaude-skills, run relay-20260728-212859-24420) and the surviving children need real
// working room for exploration, edits and tool results — id:9eb7 records "well under 100k
// working room" as the pathology, not the target. So the FIXED payload the child must swallow
// before it can do anything (its dispatch prompt + the ledgers it is contractually required to
// read) is capped at 100k, leaving ~100k of working room.
//
// Calibration against the two known points: the 2026-08-01 ROADMAP (523,926 B ≈ 131k tok
// + overhead) is OVER and would have been refused; the same file after roadmap-archive.sh
// (254,087 B ≈ 63.5k tok + overhead) is UNDER and dispatches normally. The gate therefore
// fires on the ledger that actually killed a child and not on the one that does not.
export const DISPATCH_TOKEN_BUDGET = 100000

// Fixed overhead every child pays on top of its dispatch prompt and the ledgers, in tokens:
// the executor contract (~5.5k, measured id:9eb7) plus conventions.md (~4k) plus the harness
// system prompt and tool definitions. Counted so the budget is measured against what the child
// really carries, not just the things we can size directly.
export const FIXED_OVERHEAD_TOKENS = 12000

// id:b018 — WHICH ledgers count. The 4f9b gate sized ROADMAP.md ALONE, and loderite passed by
// 326 tokens then died anyway: the child is also contractually required to read TODO.md
// (handoff C2's first check, review's single-id-two-views tick-back, and the execute contract's
// id reuse), so its bytes belong in the estimate exactly as the ROADMAP's do. Both are measured
// on the HOST by classify-repo.sh (`roadmap_bytes`, `todo_bytes`) and ride along on the unit.
//
// Audit of the assembled child prompt (unitPrompt in relay-loop.js, 2026-08-21): the prompt
// EMBEDS no ledger bytes at all — it interpolates instructions plus `unit.reason`. What it
// makes the child SWALLOW is the set of files its procedure requires: ROADMAP.md (every
// verdict) and TODO.md (handoff/review/execute), plus the fixed contract+conventions payload
// already carried by FIXED_OVERHEAD_TOKENS. REVIEW_ME.md and RELAY_LOG.md are read by REVIEW
// units only and are deliberately NOT counted here — adding them would refuse execute units on
// bytes they never read.
//
// HONEST RESIDUAL (id:9663 / --fabled F5): this budgets what the child is REQUIRED to read, not
// everything it MAY pull. The child holds Read/Bash on the checkout and auto mode denies
// essentially nothing outside protected paths (banked probe id:5937), so its potential read set
// is the whole repo and is not soundly boundable from a byte count. Bounding it needs either
// the id:e68f slice-and-hand-a-path change or a real enforcement — neither is in this item.

// estimateDispatchTokens — tokens the child must swallow before it can start work.
// promptChars: length of the assembled unitPrompt string. roadmapBytes / todoBytes: the
// host-measured sizes of ROADMAP.md and TODO.md (0 or omitted when unmeasured).
export function estimateDispatchTokens(promptChars, roadmapBytes, todoBytes) {
  const n = (v) => (Number.isFinite(v) && v > 0 ? v : 0)
  const bytes = n(promptChars) + n(roadmapBytes) + n(todoBytes)
  return Math.round(bytes / CHARS_PER_TOKEN) + FIXED_OVERHEAD_TOKENS
}

// oversizeDispatchReason — '' when the unit is safe to dispatch, otherwise ONE line naming
// BOTH the cause and the remedy, suitable verbatim as a handback reason and as the
// RELAY_STATUS.md "Blocked" row. The cause names EVERY oversized ledger with its byte count
// and the archiver that shrinks it — a refusal that blames only ROADMAP.md sends the human to
// archive the wrong file (id:b018).
//
// FAIL-OPEN by construction: a unit with NO ledger measurement at all (an older queue entry, an
// injected unit, a shard-produced unit) measures as 0 and can never trip the gate. Refusing to
// dispatch on ABSENT data would be strictly worse than the death this prevents — the gate only
// ever acts on a positive measurement. A unit measured on only ONE ledger is still sized on
// that one (the old `if (!roadmapBytes) return ''` short-circuit silently skipped a TODO-only
// measurement).
export function oversizeDispatchReason(unit, promptChars, budget) {
  const u = unit || {}
  const cap = Number.isFinite(budget) && budget > 0 ? budget : DISPATCH_TOKEN_BUDGET
  const n = (v) => (Number.isFinite(v) && v > 0 ? v : 0)
  // id:35b7 — WHEN A SLICE EXISTS, THE SLICE *IS* THE REQUIRED-READ SET. sliceLedgerForUnit()
  // (id:e68f) stamps `slice_path`/`slice_bytes` immediately BEFORE this call, and the brief then
  // points the child at that file instead of the ledgers. Counting the ledgers anyway refuses
  // dispatches on bytes the child is no longer required to read: dotclaude-skills, 2026-08-21,
  // measured ROADMAP 252,809 B + TODO 904,586 B ⇒ ~301,349 tok vs a 100,000 budget ⇒ EVERY
  // dispatch refused, while the real slice for a real item measured 3,854 B (~300x smaller).
  // The slice size is MEASURED on the host by ledger-slice.sh and shipped on its stdout — never
  // a guessed allowance (the guessed-estimate failure is exactly what let loderite through by
  // 326 tok). A slice whose size is UNMEASURED is missing data, so it fails OPEN like any other
  // unmeasured input; it does NOT fall back to counting ledgers the child will not read.
  const sliced = typeof u.slice_path === 'string' && u.slice_path.length > 0
  if (sliced) {
    const sliceBytes = n(u.slice_bytes)
    if (!sliceBytes) return ''   // slice present but unmeasured ⇒ fail OPEN
    const sliceEst = estimateDispatchTokens(promptChars, sliceBytes, 0)
    if (sliceEst <= cap) return ''
    return `prompt-size gate (id:4f9b/id:35b7): NOT dispatched — the assembled ${u.verdict || 'child'} prompt for ${u.repo || '(repo)'} is ~${sliceEst} tok, over the ${cap} tok dispatch budget, so the child would die with "Prompt is too long" instead of doing work. CAUSE: this unit carries an id:e68f ledger SLICE (${u.slice_path}) and is sized on THAT, not on the ledgers — and the slice itself is ${sliceBytes} bytes (~${Math.round(sliceBytes / CHARS_PER_TOKEN)} tok of the estimate). REMEDY: archiving the ledgers will NOT help here — the bulk is one item's own block plus its typed edges and TODO twin. Shrink the dispatched ITEM: split it into seams, or move its prose into a linked meeting note and leave the acceptance criteria. This repo is skipped, not failed: no worktree was created and no work was lost.`
  }
  const roadmapBytes = n(u.roadmap_bytes)
  const todoBytes = n(u.todo_bytes)
  if (!roadmapBytes && !todoBytes) return ''   // unmeasured ⇒ fail OPEN, never block on missing data
  const est = estimateDispatchTokens(promptChars, roadmapBytes, todoBytes)
  if (est <= cap) return ''
  const repoPath = u.path || '<repo-path>'
  const measured = [
    { name: 'ROADMAP.md', bytes: roadmapBytes, fix: '~/.claude/skills/relay/scripts/roadmap-archive.sh ' + repoPath },
    { name: 'TODO.md', bytes: todoBytes, fix: '~/.claude/skills/todo-update/archive-done.sh ' + repoPath + '/TODO.md' },
  ].filter((l) => l.bytes > 0)
  // Name the ledgers that MATERIALLY drive the overrun (>= a quarter of the cap on their own);
  // if none does individually, the overrun is the aggregate, so name them all.
  const material = measured.filter((l) => l.bytes / CHARS_PER_TOKEN >= cap / 4)
  const named = material.length ? material : measured
  const causes = named.map((l) => `${l.name} is too large — ${l.bytes} bytes (~${Math.round(l.bytes / CHARS_PER_TOKEN)} tok of the estimate)`).join('; ')
  const remedies = named.map((l) => '`' + l.fix + '`').join(' and ')
  // REMEDY WORDING (id:35b7): the old text sent the operator to the archivers unconditionally.
  // They move DONE `- [x]` items ONLY, so on a ledger whose bulk is OPEN (dotclaude-skills
  // TODO.md, 2026-08-21: 529 open / 1 closed) they move nothing and the refusal is a dead end.
  // Name the lever that applies either way FIRST — the id:e68f slice, whose absence is why this
  // unit was sized on whole ledgers at all — and mark archiving as the conditional remedy.
  return `prompt-size gate (id:4f9b/id:b018): NOT dispatched — the assembled ${u.verdict || 'child'} prompt for ${u.repo || '(repo)'} is ~${est} tok, over the ${cap} tok dispatch budget, so the child would die with "Prompt is too long" instead of doing work. CAUSE: ${causes}. REMEDY: this unit carries NO id:e68f ledger slice, so it is sized on the WHOLE ledgers — a sliced unit is sized on its slice instead (id:35b7), so the first lever is to find why \`~/.claude/skills/relay/scripts/ledger-slice.sh\` produced no \`slice_path\` for it (the relay-loop log records the reason) and fix that. ARCHIVING is the second lever and only applies if the bulk is CLOSED: ${remedies} move done \`- [x]\` items into the matching archive file and do NOTHING for a ledger of mostly OPEN items — where the real lever is splitting the ledger or pruning stale open items. Then commit and re-run the pool. This repo is skipped, not failed: no worktree was created and no work was lost.`
}
