# Design: a review-shaped ledger slice (id:502f)

**Status: EVIDENCE + RECOMMENDATION. Nothing here is decided.** The choices marked
**OWNER DECISION** are the repo owner's; this document supplies measurements and options.

Investigated 2026-08-27. Every code/contract claim below cites `file:line` and was verified
by running the command that proves it.

---

## 1. Why is RELAY_LOG.md read at all, and why WHOLE?

### 1a. The gate's stated reason

`relay-loop.js:2886-2891` (inline copy of `prompt-size-gate.mjs`'s `countedLedgersFor`,
pinned byte-identical by `tests/test_prompt_size_gate_review_7c5f.sh`):

> ROADMAP.md + TODO.md always, plus REVIEW_ME.md + RELAY_LOG.md when the verdict is `review`,
> **because only a review child is contractually required to read those two.**

So the gate charges a review unit for the WHOLE of both files. The question is whether the
contract actually requires that.

### 1b. What the contract actually says

The review child's procedure doc is `relay/references/review.md` (`relay-loop.js:2756`:
`if (verdict === 'review') return '.../references/review.md'`). Every RELAY_LOG mention in
it is either a WRITE or a **diff-window-scoped** read:

| review.md | Use | Scope |
|---|---|---|
| `:78` "a RELAY_LOG note mentioning a stash/reset/checkout to 'clean up' or 'make room'" | READ (faked-clean-tree check, id:373e) | the diff window's entries — it is checking what the executor being reviewed wrote |
| `:87` "the executor contract (rule 4) requires a `refactor:` line in the RELAY_LOG self-report" | READ (id:108e) | this window's self-report entry only |
| `:195` "record the skip explicitly ... in BOTH `RELAY_LOG.md` and the returned summary" | WRITE | — |
| `:310` "read commit messages (`friction:` lines) and RELAY_LOG.md entries" | READ (lane promote/demote) | "what executors actually struggled with" — this window |
| `:357` "Record each qualification in the diff window's `RELAY_LOG.md` paragraph" | WRITE, **and it says "the diff window's" explicitly** | — |

`relay/references/executor-contract.md:267-285` (`## RELAY_LOG.md conventions`) is entirely a
**write-format** spec: *"Append to `RELAY_LOG.md` (append-only, `merge=union` in
`.gitattributes`)"*. It never instructs a read.

The assembled review prompt (`relay-loop.js:3055`) does not mention RELAY_LOG.md at all.

**Answer: nothing requires a whole read. The owner's hypothesis is correct.** Every
contractual READ of RELAY_LOG.md is bounded by the same `$LAST..HEAD` diff window that
review.md §1 (`relay/references/review.md:78-86`) already establishes. The whole-file charge
in `countedLedgersFor` is a conservative over-estimate that was never re-derived against
review.md's actual text. The same is true of REVIEW_ME.md: review.md's uses are `:63`
(existence of an entry — a grep), `:230-272` (§4b, WRITE boxes), `:381` (WRITE). No open-box
read is required.

### 1c. What that over-estimate costs (measured 2026-08-27)

| repo | RELAY_LOG.md whole | RELAY_LOG delta per ckpt window (last 5) | over-count |
|---|---|---|---|
| dotclaude-skills | 676,801 B (~169k tok) | 0 – 4,197 B | ~161× |
| loderite | 1,252,525 B (~313k tok) | 1,699 – 8,301 B | ~151× |
| it-infra | 115,702 B (~29k tok) | 0 – 2,344 B | ~49× |

RELAY_LOG.md is the **single largest counted ledger** in loderite (1.25 MB, larger than
ROADMAP + TODO + REVIEW_ME combined) and the second largest in dotclaude-skills.

---

## 2. Does a bounded required-read set exist?

**Partly. A bounded SET exists; for two of the three repos it still does not FIT.**

Derived from review.md section by section:

| # | Required read | Bound | dotclaude | loderite | it-infra |
|---|---|---|---|---|---|
| R1 | `git log --stat $LAST..HEAD` + diffs (§1, §2) | the child produces this itself; not a ledger | — | — | — |
| R2 | RELAY_LOG.md entries added in the window (§2.5, §2.6, §5) | **window** | ≤4.2 KB | ≤8.3 KB | ≤2.3 KB |
| R3 | REVIEW_ME.md **open boxes** (§4b context) | open-only | 11.1 KB | 17.7 KB | 0 KB |
| R4 | ROADMAP.md **open item blocks** (§5 re-derivation) | **open-only — but ALL of them** | 208.6 KB | 228.9 KB | 25.0 KB |
| R5 | TODO/ROADMAP `- [ ]` lines added in the window (§5b reverse-handoff) | **window** | ≤15.9 KB | ≤4.5 KB | ≤19.7 KB |
| R6 | TODO.md id→title lookup for D2 single-id-two-views (§5) | a **lookup**, not a read | see below | | |

**R4 is the irreducible core and it is not item-keyed.** §5 (`review.md:271-320`) obliges the
child to re-derive the ROADMAP: lint every open item, close the green ones, re-scope, promote/
demote lanes, tick TODO twins. That ranges over the *entire open set*, and judging "genuinely
green" needs each item's acceptance/done-check — i.e. the block, not the headline. There is no
principled way to shrink R4 without changing what a review IS.

**R6 is the one place a lossy projection is unavoidable.** dotclaude-skills' TODO.md is 633
open items at ~1,740 B **per single line** — headline-only is 1,101,522 B (~275k tok), no
better than the whole file. A usable index therefore has to TRUNCATE (id + first ~120 chars).
That is a **OWNER DECISION**, not a mechanical fix: truncation can hide the very text §5b
needs to qualify an item.

### Projected slice, with a truncated R6 index (id + 120 chars/item)

| repo | R2+R3+R4+R5+R6 | est. tokens | + 12,000 overhead | vs 100,000 |
|---|---|---|---|---|
| dotclaude-skills | ~328 KB | ~82.1k | **94.1k** | fits by 6% |
| loderite | ~285 KB | ~71.3k | **83.3k** | fits by 17% |
| it-infra | ~75 KB | ~18.9k | **30.9k** | fits comfortably |

Compare today: 550,287 / 520,546 / 155,393 tok. So the slice is a 5.8× / 6.2× / 5.0× reduction
and it clears the *nominal* gate for all three.

### The caveat that undoes two of those three

`prompt-size-gate.mjs:168-171`:

> UNCHANGED, but now KNOWN LOW: the measured preamble is ~58,600 tok, not 12,000 ... The two
> numbers must be re-derived TOGETHER, by the owner.

At 58,600 the same slices are **140.7k (dotclaude) / 129.9k (loderite) / 77.5k (it-infra)** —
two of three still over 100k. **R4 alone** is 52.2k / 57.2k tok, so open-ROADMAP mass plus the
real preamble exceeds the budget on its own.

**Finding, stated plainly: slicing RELAY_LOG and REVIEW_ME is necessary but NOT sufficient.**
It rescues it-infra outright and rescues the other two only against the nominal-12k arithmetic
the gate's own source flags as wrong. The residual blocker for dotclaude-skills and loderite is
open-ROADMAP mass, which is a ledger-splitting / item-prose problem, not a slicer problem.
**OWNER DECISION:** whether to re-derive `FIXED_OVERHEAD_TOKENS` + `DISPATCH_TOKEN_BUDGET`
together before or after building this.

---

## 3. Recommended slicer shape

**A SIBLING script, `relay/scripts/review-slice.sh`, not an extension of `ledger-slice.sh`.**

Reason: `ledger-slice.sh`'s entire structure is item-keyed — `--id` is validated as 4 hex
(`ledger-slice.sh:70`), the block-bounds walk (`:118-166`), typed-edge collection (`:171-190`)
and the TODO twin (`:250-256`) all hang off one located item, and exit 4 means "that id owns no
ROADMAP item". A review has no id. Overloading `--id` with a sentinel would make exit 4
ambiguous, which is exactly the LOUD/silent-empty distinction id:4347 exists to protect.

Keep the two scripts' **shared contract** identical so `sliceLedgerHeadroom` and the gate need
no special-casing:

- Usage: `review-slice.sh --repo <name> --path <repo-path> --since <ckpt-tag> [--out <file>]`
- STDOUT: `slice-bytes: <N>` then the path as the **last non-empty line** (`ledger-slice.sh:41-47`).
- Exits: `0` written, `2` misuse, `4` **unresolvable window** — no `$LAST` tag, or `--since`
  names a tag that does not exist. Never a silent empty slice.
- Side-effect-free apart from the one written file; output under `$RELAY_SLICE_DIR`, named
  `${repo}-review-${since}.md` (run-stable, mirroring `:76-79`).
- Reuse `lib-typed-edges.sh` for every id lookup — never a bare `grep id:XXXX` (`:31-35`).

Sections it writes, in order:

1. `## Repo state` — repo, path, `$LAST`, ROADMAP/TODO/REVIEW_ME/RELAY_LOG byte sizes, and the
   same id:9663 disclaimer `ledger-slice.sh:216-219` prints: *this is the default context, not
   a boundary; the ledgers remain readable — say so in your handback if the slice was
   insufficient.*
2. `## RELAY_LOG — this window` — `git diff $LAST..HEAD -- RELAY_LOG.md`, added lines only.
   If empty, say so explicitly (`_(no RELAY_LOG entries this window)_`) rather than omitting
   the heading — an absent self-report is itself a §2.6 signal.
3. `## REVIEW_ME — open boxes` — open `- [ ]` blocks only.
4. `## ROADMAP — open items` — every open `- [ ]` block, reusing the id:b015 block-bounds and
   fence-state logic and the owning-section-heading stamp (`ledger-slice.sh:118-166`,
   `:206-212`). This is the bulk; do not summarise it.
5. `## Ledger additions this window` — `git diff $LAST..HEAD -- TODO.md ROADMAP.md`, added
   `- [ ]` lines (R5/§5b).
6. `## TODO index (TRUNCATED)` — one line per open TODO id: `id:XXXX — <first N chars>…`.
   Header must state N and that it is lossy, so a child that needs the full text knows to open
   TODO.md rather than silently working a truncated spec.

The id:b015 lesson applies with full force here: a well-formed, non-empty, honestly-sized slice
that silently dropped acceptance criteria produced WRONG WORK, not a crash. Sections 4 and 6
are where that failure would recur.

### Call-site change

`relay-loop.js:3960-3962`:

```js
async function sliceLedgerForUnit(unit) {
  const item = dispatchItemFor(unit)
  if (!item) return null
```

Change: branch on verdict *before* the item check.

```js
async function sliceLedgerForUnit(unit) {
  if (unit && unit.verdict === 'review') return reviewSliceForUnit(unit)   // keyed on $LAST, not an id
  const item = dispatchItemFor(unit)
  if (!item) return null
```

`reviewSliceForUnit` is a near-copy of the existing body: same `agent(...)` mechanical
`relay-mech` hop at `MECH_MODEL` (`:3968-3976`), same `MECH-ERROR` check (`:3982`), same
last-line path extraction and `/^[~/][^\s]*\.md$/` validation (`:3985`), same fail-open-and-log
on every failure, same `unit.slice_path` + `slice_bytes` stamping (`:3988-3990`). It needs
`$LAST` — either passed via a `--since` the script resolves itself (simplest: let the script
run the same `git tag -l 'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1` that review.md §1
uses) or read from `unit.lastCkpt`, which the prompt already carries (`relay-loop.js:3051`).

Two consequences, both free:

- The gate at `:2991-3007` already sizes a unit on `slice_path`/`slice_bytes` when present
  (id:35b7), so **no gate change is needed** — a review unit with a slice is sized on the slice
  automatically, and its over-budget message already names the right remedy.
- `sliceInstruction` (`:2923-2924`) already hands the child the path for any unit with
  `slice_path`. Its wording is item-shaped ("the item's own block ... the TODO.md twin") and
  would need a review-shaped variant. Note `prompt-size-gate.mjs:154-155` warns
  `sliceInstruction` has an **unpinned** inline copy at `relay-loop.js:2666` that will silently
  diverge — check both.

`countedLedgersFor` (`:2891`) should be left ALONE. It is byte-pinned to `prompt-size-gate.mjs`
by a structural test, and it is only consulted for UNSLICED units — where charging the whole
files remains the honest conservative answer.

---

## 4. Weaknesses of this recommendation

1. **It does not fix dotclaude-skills or loderite under the real overhead.** §2 above. If the
   owner re-derives `FIXED_OVERHEAD_TOKENS` to the measured 58.6k without also raising
   `DISPATCH_TOKEN_BUDGET`, this work buys those two repos nothing. Build order matters.
2. **The TODO index is lossy by construction** and §5b is precisely the step that reads new
   TODO prose to qualify it. A truncated index could cause a review to mis-size an item it can
   no longer see. Section 5 (window additions, untruncated) covers *newly added* items, which is
   the §5b case — but the D2 token-reuse lookup against OLD items still runs on truncated text.
3. **"Open-only ROADMAP" is an assumption about §5, not a quoted requirement.** review.md never
   says a review may ignore closed items; §2's test-integrity audit is diff-window scoped so it
   should not need them, but a closed item ticked *this window* is exactly what the audit
   checks. Mitigation: include closed items whose checkbox changed in the window. Unmeasured.
4. **A slice is not an enforcement** (`ledger-slice.sh:9-14`, id:9663, banked probe id:5937).
   The child holds Read/Bash; nothing stops it opening the 1.25 MB RELAY_LOG.md and dying with
   `Prompt is too long` *after* the gate approved it on 285 KB. `sliceLedgerHeadroom`
   (`:2908-2917`) already conditions the "full ledgers are still on disk" offer on measured
   headroom; a review slice makes that conditioning more load-bearing, not less.
5. **Two scripts now duplicate the id:b015 block-bounds walk.** That logic is subtle (fence
   state, column-0 bounds, sibling comment runs) and its previous bug produced silent wrong
   work. Extracting it into `lib-typed-edges.sh` first would be safer than copying it — but
   that library is under concurrent edits (`ledger-slice.sh:81-83` says as much), so the
   sequencing is a real constraint.
6. **Unverified: whether a review child today actually reads RELAY_LOG whole.** I verified the
   contract does not *require* it. I did not measure what children *do*. If they already
   window-scope it by instinct, the gate is refusing dispatches over a cost nobody was paying —
   which changes the framing from "make the child cheaper" to "stop the gate lying". A
   transcript check would settle it and is cheap.

## 5. Explicitly for the owner, not mechanical

- Re-derive `FIXED_OVERHEAD_TOKENS` (12,000 → measured ~58,600) and `DISPATCH_TOKEN_BUDGET`
  **together**, per `prompt-size-gate.mjs:171`. Everything above is arithmetic on the current
  pair.
- The TODO-index truncation length, and whether a lossy index is acceptable at all for D2.
- Whether "open-only" is the right ROADMAP bound for §5, or whether window-closed items belong.
- Whether to extract the block-bounds walk into the shared lib first (safer, blocked on a
  concurrent editor) or copy it (faster, duplicates a subtle bug surface).
