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
// already carried by FIXED_OVERHEAD_TOKENS.
//
// id:7c5f — THE COUNTED SET IS VERDICT-DEPENDENT. b018's exclusion of REVIEW_ME.md and
// RELAY_LOG.md ("adding them would refuse execute units on bytes they never read") is correct
// for execute/hard/handoff units and WRONG for review units: a review child is contractually
// required to read BOTH (the trust-but-verify procedure, and the single-id-two-views tick-back
// that reads RELAY_LOG.md's session entries). Excluding them left the loderite-by-326-tokens
// pathology — clear the budget, then die with `Prompt is too long` — alive for exactly one
// verdict class, with no detector. The fix is not to count them always (that would resurrect
// b018's objection) but to make the counted set a function of `unit.verdict`:
// countedLedgersFor() below is that function, and it is the single place the set is decided —
// both the gate and sliceLedgerHeadroom() read it, so the two can never disagree about which
// files a given verdict must swallow.
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

// countedLedgersFor (id:7c5f) — the ledgers THIS unit's verdict makes the child swallow, each
// with its host-measured byte count and the remedy that shrinks it. ROADMAP.md + TODO.md are
// counted for every verdict (id:4f9b, id:b018). REVIEW_ME.md + RELAY_LOG.md are added ONLY for
// `verdict === 'review'`, because only a review child is required to read them — counting them
// for an execute unit would refuse it on bytes it never reads, which is precisely the objection
// b018 recorded. Byte counts are measured on the HOST by classify-repo.sh and ride along on the
// unit; an absent/unmeasured file is 0 and therefore contributes nothing (fail-open).
//
// `cmd` marks a remedy that is a runnable command (rendered in backticks) versus a prose
// instruction. RELAY_LOG.md has NO archiver — it is append-only/merge=union — so its remedy is
// honest prose rather than a command that does not exist.
export function countedLedgersFor(unit) {
  const u = unit || {}
  const n = (v) => (Number.isFinite(v) && v > 0 ? v : 0)
  const repoPath = u.path || '<repo-path>'
  const ledgers = [
    { name: 'ROADMAP.md', bytes: n(u.roadmap_bytes), cmd: true, fix: '~/.claude/skills/relay/scripts/roadmap-archive.sh ' + repoPath },
    { name: 'TODO.md', bytes: n(u.todo_bytes), cmd: true, fix: '~/.claude/skills/todo-update/archive-done.sh ' + repoPath + '/TODO.md' },
  ]
  if (u.verdict === 'review') {
    ledgers.push({ name: 'REVIEW_ME.md', bytes: n(u.review_me_bytes), cmd: true, reviewOnly: true, fix: '~/.claude/skills/relay/scripts/archive-closed.sh ' + repoPath })
    ledgers.push({ name: 'RELAY_LOG.md', bytes: n(u.relay_log_bytes), cmd: false, reviewOnly: true, fix: 'RELAY_LOG.md is append-only (merge=union) and has NO archiver — rotate its older session entries into a RELAY_LOG.archive.md by hand' })
  }
  return ledgers
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
  // id:7c5f — the counted set is verdict-dependent (see countedLedgersFor). For a review unit
  // this includes REVIEW_ME.md + RELAY_LOG.md; for every other verdict it is exactly the b018
  // pair, so no execute/hard/handoff unit's verdict can change.
  const measured = countedLedgersFor(u).filter((l) => l.bytes > 0)
  if (!measured.length) return ''   // unmeasured ⇒ fail OPEN, never block on missing data
  const ledgerBytes = measured.reduce((s, l) => s + l.bytes, 0)
  const est = estimateDispatchTokens(promptChars, ledgerBytes, 0)
  if (est <= cap) return ''
  // Name the ledgers that MATERIALLY drive the overrun (>= a quarter of the cap on their own);
  // if none does individually, the overrun is the aggregate, so name them all.
  const material = measured.filter((l) => l.bytes / CHARS_PER_TOKEN >= cap / 4)
  // id:7c5f — a REVIEW-ONLY ledger is typically small yet decisive: if the estimate WITHOUT the
  // review-only ledgers would have fitted, they are the SWING cause and must be named however
  // far under the materiality threshold they sit. Naming only ROADMAP.md/TODO.md there would
  // send the operator to archive the two files that were never the problem — the same
  // wrong-file misdirection id:b018 fixed for the roadmap-only refusal.
  const swing = measured.filter((l) => l.reviewOnly)
  const swingBytes = swing.reduce((s, l) => s + l.bytes, 0)
  const swingIsCause = swingBytes > 0 && estimateDispatchTokens(promptChars, ledgerBytes - swingBytes, 0) <= cap
  const named = swingIsCause ? measured.filter((l) => l.reviewOnly || material.includes(l))
                             : (material.length ? material : measured)
  const causes = named.map((l) => `${l.name} is too large — ${l.bytes} bytes (~${Math.round(l.bytes / CHARS_PER_TOKEN)} tok of the estimate)`).join('; ')
  const remedies = named.map((l) => (l.cmd === false ? l.fix : '`' + l.fix + '`')).join(' and ')
  // REMEDY WORDING (id:35b7): the old text sent the operator to the archivers unconditionally.
  // They move DONE `- [x]` items ONLY, so on a ledger whose bulk is OPEN (dotclaude-skills
  // TODO.md, 2026-08-21: 529 open / 1 closed) they move nothing and the refusal is a dead end.
  // Name the lever that applies either way FIRST — the id:e68f slice, whose absence is why this
  // unit was sized on whole ledgers at all — and mark archiving as the conditional remedy.
  return `prompt-size gate (id:4f9b/id:b018): NOT dispatched — the assembled ${u.verdict || 'child'} prompt for ${u.repo || '(repo)'} is ~${est} tok, over the ${cap} tok dispatch budget, so the child would die with "Prompt is too long" instead of doing work. CAUSE: ${causes}. REMEDY: this unit carries NO id:e68f ledger slice, so it is sized on the WHOLE ledgers — a sliced unit is sized on its slice instead (id:35b7), so the first lever is to find why \`~/.claude/skills/relay/scripts/ledger-slice.sh\` produced no \`slice_path\` for it (the relay-loop log records the reason) and fix that. ARCHIVING is the second lever and only applies if the bulk is CLOSED: ${remedies} move done \`- [x]\` items into the matching archive file and do NOTHING for a ledger of mostly OPEN items — where the real lever is splitting the ledger or pruning stale open items. Then commit and re-run the pool. This repo is skipped, not failed: no worktree was created and no work was lost.`
}

// ── id:7575 — the SLICED brief's conditional escape hatch. ─────────────────────────────────
//
// The defect this closes: a sliced unit is sized on its SLICE alone (id:35b7, above), so the
// gate approves dispatch on a few KB — and the brief then told the child, unconditionally,
// that "the full ledgers are still on disk". On dotclaude-skills (2026-08-21) that is an
// approval granted on a 3,854 B slice plus an open invitation to read a 904,586 B TODO.md
// (~226k tok). A child that accepts dies with `Prompt is too long`, surfaced as the generic
// "child agent failed/skipped" while id:61fa is open. (When this was written ledger-slice.sh
// also bounded an item block by INDENTATION, so a column-0 acceptance line was dropped
// silently. `id:b015` FIXED that — the block now extends to the next column-0 checkbox or
// `#`-heading with fence tracking, so column-0 prose is INCLUDED. Do not re-assert the old
// truncation anywhere: it is no longer a defect the child can hit, and the hardened brief
// below no longer cites it. id:31c3.)
//
// This changes ONLY WHAT THE BRIEF SAYS. oversizeDispatchReason's verdict is untouched: every
// unit that dispatches today still dispatches. And it does NOT claim the slice enforces
// anything (id:9663) — the child keeps Read/Bash on the checkout; the hardened wording states
// the cost and asks for a hand-back instead of a speculative read.

// sliceLedgerHeadroom — how much of the dispatch budget is left AFTER the slice, and whether
// that could plausibly absorb one full ledger read on top of it. Every figure is MEASURED
// from the unit's own host-side byte counts (`slice_bytes` from ledger-slice.sh, and
// `roadmap_bytes`/`todo_bytes` from classify-repo.sh) against the same budget the gate uses.
// There is NO invented allowance — a guessed estimate is the exact bug class here (loderite
// passed the 4f9b gate by 326 tok and died anyway).
//
// WHICH ledger must fit: the LARGEST measured one, taken from the SAME verdict-dependent set
// the gate counts (countedLedgersFor, id:7c5f) — so for a review unit REVIEW_ME.md and
// RELAY_LOG.md are candidates too. Sizing a review child's invitation on ROADMAP/TODO alone
// would tell it a full read is affordable while the two files it is REQUIRED to read went
// uncounted. The invitation is plural ("the ledgers"), so a child may open any of them; sizing
// on a smaller one would leave the bigger uncovered.
//
// The assembled prompt's own chars are NOT subtracted — they are unknown at brief-assembly
// time (the brief is part of that prompt, so subtracting it would be circular). That makes
// `headroomTokens` an UPPER bound, i.e. deliberately GENEROUS: the hardened wording fires only
// when a ledger provably cannot fit even under the most favourable accounting. Erring that way
// is correct for a wording change — a marginal call keeps today's text.
//
// FAIL-OPEN on missing data, exactly like the gate: an unmeasured slice or unmeasured ledgers
// yield `affordable: true`, which leaves the historical invitation in place.
export function sliceLedgerHeadroom(unit, budget) {
  const u = unit || {}
  const cap = Number.isFinite(budget) && budget > 0 ? budget : DISPATCH_TOKEN_BUDGET
  const n = (v) => (Number.isFinite(v) && v > 0 ? v : 0)
  const sliceBytes = n(u.slice_bytes)
  let largestLedgerBytes = 0
  let largestLedgerName = ''
  for (const l of countedLedgersFor(u)) {
    if (l.bytes > largestLedgerBytes) { largestLedgerBytes = l.bytes; largestLedgerName = l.name }
  }
  const headroomTokens = cap - estimateDispatchTokens(0, sliceBytes, 0)
  const largestLedgerTokens = Math.round(largestLedgerBytes / CHARS_PER_TOKEN)
  const affordable = largestLedgerBytes <= 0 || largestLedgerTokens <= headroomTokens
  return { headroomTokens, largestLedgerTokens, largestLedgerBytes, largestLedgerName, affordable, budget: cap }
}

// sliceInstruction — the SLICE sentence shared by both named briefs (id:e68f). When
// sliceLedgerForUnit() stamped a path on the unit, point the child at that file instead of
// leaving it to grep the ledgers. It is a cheaper DEFAULT, not a boundary (id:9663): the child
// keeps Read/Bash and the checkout, so the wording must not claim it cannot read more. Empty
// string when no slice exists (fail-open), which leaves the historical grep instruction as the
// only guidance — exactly the pre-e68f behaviour.
//
// The trailing clause is CONDITIONAL on sliceLedgerHeadroom (id:7575): offer the "full ledgers
// are still on disk" escape only when the measured headroom could absorb one; otherwise quote
// the measured cost and ask for a hand-back.
export function sliceInstruction(unit, budget) {
  if (!unit || typeof unit.slice_path !== 'string' || !unit.slice_path) return ''
  const head = 'The orchestrator has ALREADY extracted this item for you (id:e68f): read ' + unit.slice_path + ' — it holds the item\'s own block, its typed gated-on:/children: edges with each target\'s line, the TODO.md twin, and a repo-state header. Start there; it is the intended default context for this unit. '
  const h = sliceLedgerHeadroom(unit, budget)
  if (h.affordable) {
    return head + 'The full ledgers are still on disk at their canonical paths if the slice genuinely does not carry something you need — if you had to open one, say which and why in your report. '
  }
  return head + 'Do NOT open the full ledgers for this unit (id:7575) — ROADMAP.md, TODO.md, and on a review unit REVIEW_ME.md and RELAY_LOG.md too (id:7c5f). They are MEASURED at ' + h.largestLedgerBytes + ' bytes for ' + h.largestLedgerName + ' alone (~' + h.largestLedgerTokens + ' tok) against only ~' + h.headroomTokens + ' tok of dispatch headroom left once this slice is counted, so a full read would blow the window and kill you mid-work with "Prompt is too long" — reported to the operator as an anonymous failure. Nothing stops you from reading them: this is a cost, not a boundary. A targeted `grep -n` for a specific id or string against a ledger is fine and cheap; a whole-file read is not. If the slice is genuinely insufficient — it carries this item block, its typed edges and the TODO twin, not neighbouring items or whole-ledger context — HAND BACK (contract_met=false, gate_reason naming exactly what the slice lacked) rather than opening a ledger speculatively. '
}
