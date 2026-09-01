# id:a282 -- per-phase slicing of the review child's mandatory reference docs

> **STATUS: MEASUREMENT AND PROPOSAL. NOT A RATIFIED DESIGN.**
> Nothing here has been implemented and nothing here is decided. This document
> reports byte measurements over `relay/references/review.md` and
> `relay/references/conventions.md`, maps each section to the review phase that
> needs it, and proposes a split for the owner to accept, amend, or reject.
> Every judgement about "phase X does not need section Y" is mine and is
> reversible; the UNSURE list below names every place I could not decide, and in
> each of those places I counted the section as NEEDED.

Related: TODO.md `id:a282` (`[INBOUND routed:2711 from loderite]`), point 5 of the
inbound item. Sibling prior art in this repo: `relay/scripts/ledger-slice.sh`
(id:dd59), which does the same thing for the ledgers rather than the reference docs.

## 1. The measured problem

`relay/scripts/relay-loop.js:3149` gives every child this line:

```
Procedure: follow <refDoc(unit.verdict)> exactly. Read
~/.claude/skills/relay/references/conventions.md for environment facts and relay
invariants before starting.
```

For a `review` unit, `refDoc()` (`relay-loop.js:2818`) resolves to
`references/review.md`. So a review child reads both files in full, before it
opens a single ledger line:

| File | Bytes |
|---|---:|
| `relay/references/review.md` | 29,051 |
| `relay/references/conventions.md` | 14,188 |
| **Flat mandatory load today** | **43,239** |

This is unconditional. It does not shrink for a repo with no host-bound items, no
versioned manifest, or no HARD budget this turn.

## 2. Method

1. Read both documents in full (they are the subject).
2. Enumerated headings with `grep -n '^#\{1,4\} '`, then hand-filtered the three
   false positives that are bash comments inside fenced code blocks
   (`review.md:11`, `:12`, `:277`).
3. Measured each section as the UTF-8 byte length of its heading line through the
   line before the next heading, with a small Python splitter. Section sums
   reconcile to within 3 bytes of `wc -c` on each file; the drift is trailing
   newline handling at the joins and is not material.
4. Sub-split `review.md` section 2b (the largest single section) at its numbered
   list items.
5. Read the child-dispatch prompt assembly in `relay-loop.js` (targeted `sed`
   around lines 2940-2975 and 3140-3160, plus greps) to establish HOW the docs are
   delivered, which turns out to constrain what any slicing can actually save.
   See section 7.

No file was modified. No commit was made.

## 3. Section inventory

### `review.md` (29,051 B, 15 sections)

| Section | Bytes | % of file |
|---|---:|---:|
| H0 preamble (title, trust-but-verify obligation) | 357 | 1.2 |
| 1. Establish the diff window | 425 | 1.5 |
| 2. Test-integrity audit (intro) | 141 | 0.5 |
| 2a. Mechanical pass, `gaming-scan.sh` (id:fa05) | 748 | 2.6 |
| 2b. Judgment-residue checks (10 numbered) | 7,702 | 26.5 |
| 2c. Host-bound verification gate (id:43b9) | 1,019 | 3.5 |
| 2d. Over-reach / SUPERSET check (id:b460) | 2,960 | 10.2 |
| 3. Test tiers, run-or-record-skip (id:f032) | 1,957 | 6.7 |
| 4. Spec-drift audit | 1,260 | 4.3 |
| 4b. Relay-health check, `relay-doctor.sh` (id:3eb5) | 3,116 | 10.7 |
| 5. Re-derive ROADMAP.md | 4,491 | 15.5 |
| 5b. Qualify unqualified ledger additions (D6) | 1,583 | 5.5 |
| 5c. User-visible-close + bump gate (id:8089) | 2,002 | 6.9 |
| 6. Spend remaining budget | 215 | 0.7 |
| Return contract | 1,076 | 3.7 |

Section 2b sub-split (7,702 B total):

| 2b item | Bytes |
|---|---:|
| heading + intro | 71 |
| 1. Resurrection check | 661 |
| 2. Fixture special-casing | 237 |
| 3. Green regression-guards | 470 |
| 4. `unverified`/skipped are not passes | 439 |
| 5. Faked-clean-tree (id:373e) | 1,081 |
| 6. Refactor claim vs diff (id:108e) | 968 |
| 7. Executor-introduced `@owner-accepted` (id:8089) | 597 |
| 8. Real-entrypoint judgment cross-check (id:8089 3b) | 603 |
| 9. Executor-introduced `@owner-answered` (id:ca14/6621) | 971 |
| 10. MODIFIED `@owner-answered` line (id:6621) | 1,444 |
| closing "Anything flagged here" | 160 |

### `conventions.md` (14,188 B, 7 sections)

| Section | Bytes | % of file |
|---|---:|---:|
| H0 preamble (two audiences) | 352 | 2.5 |
| Environment facts (inject into every child prompt) | 1,896 | 13.4 |
| Relay invariants (orchestrator + children) | 2,613 | 18.4 |
| Tagging `[INTENSIVE - <resource>]` (id:8d52) | 1,757 | 12.4 |
| Durable Fable-bonus-recheck queue (id:e030) | 1,053 | 7.4 |
| Semver bump trigger at integrate (id:e647/087b) | 5,104 | 36.0 |
| Executor-contract pointer | 1,414 | 10.0 |

Within the Semver section, the split between procedure and justification:

| Sub-block | Bytes |
|---|---:|
| The 8-branch resolution table (the actual procedure) | 1,979 |
| Rationale + 2026-08-26 amendment narrative | 2,969 |
| Trailing cross-repo-inbox bullet (structurally misfiled under this heading) | 155 |

## 4. Phases, and which sections each needs

Phases are taken from `review.md`'s own numbering, which is the procedure the child
is told to "follow exactly".

| Phase | Needs from review.md | Needs from conventions.md | Phase-specific bytes |
|---|---|---|---:|
| P1 test-integrity, mechanical | 2 intro, 2a | -- | 889 |
| P2 test-integrity, judgment residue | 2b (all 10) | -- | 7,702 |
| P3 host-bound gate *(conditional)* | 2c | -- | 1,019 |
| P4 over-reach / SUPERSET | 2d | -- | 2,960 |
| P5 test tiers | 3 | -- | 1,957 |
| P6 spec-drift audit | 4 | Executor-contract pointer | 2,673 |
| P7 relay-health | 4b | -- | 3,116 |
| P8 re-derive ROADMAP | 5 | Tagging `[INTENSIVE]` | 6,247 |
| P9 reverse-handoff qualify | 5b | -- | 1,583 |
| P10 user-visible-close + bump *(conditional)* | 5c | Semver bump trigger | 7,106 |
| P11 spend remaining HARD budget *(conditional)* | 6 | -- | 215 |

P6's dependency on the conventions pointer section is explicit in the text:
`review.md` section 4 says to refresh the pointer "from conventions.md
section Executor-contract pointer". P8's dependency on the INTENSIVE section is
by function, not by cross-reference: re-derivation is where a strong child
promotes, demotes, and tags items, and the INTENSIVE criteria are the tagging
rules. P10's dependency on the Semver section is explicit: `review.md` 5c feeds
`version-bump.sh`, whose trigger table lives in conventions.

## 5. The universal core

These sections are needed by every phase, or bind the child throughout, and
therefore can never be sliced away. This is the floor, and it is the honest
headline number.

| Section | File | Bytes | Why it is universal |
|---|---|---:|---|
| H0 preamble | review.md | 357 | states the trust-but-verify obligation that every phase serves |
| 1. Establish the diff window | review.md | 425 | `$LAST` is the input to 2a, 2b, 2d, 3, 5b; every phase is scoped by it |
| Return contract | review.md | 1,076 | the child must know the field names (`gaming_flags`, `verified_green`, `reopened`) while doing the work, not only at the end |
| H0 preamble | conventions.md | 352 | names which audience each following block is for |
| Environment facts | conventions.md | 1,896 | carries the id:f682 worktree-isolation rule, which binds every write in every phase |
| Relay invariants | conventions.md | 2,613 | carries children-never-push, children-never-run-diary, checkpoint prefix matching (UNSURE, see 8.1) |
| Durable Fable-recheck queue | conventions.md | 1,053 | integrator-facing, counted universal conservatively (UNSURE, see 8.2) |
| **Universal core** | | **7,769** | |

7,769 B is 18.0% of today's 43,239.

## 6. Per-phase load under an ideal split

Per-phase load = universal core + that phase's own sections.

| Phase | Load (B) | vs today's 43,239 |
|---|---:|---:|
| P11 spend HARD budget | 7,984 | 18.5% |
| P1 mechanical | 8,658 | 20.0% |
| P3 host gate | 8,788 | 20.3% |
| P9 reverse-handoff | 9,352 | 21.6% |
| P5 test tiers | 9,726 | 22.5% |
| P6 spec-drift | 10,442 | 24.1% |
| P4 over-reach | 10,729 | 24.8% |
| P7 relay-health | 10,885 | 25.2% |
| P8 re-derive ROADMAP | 14,016 | 32.4% |
| P10 bump gate | 14,875 | 34.4% |
| P2 judgment residue | 15,471 | 35.8% |

Best per-phase load 7,984 B (P11). Worst 15,471 B (P2). Assignment sum plus
universal core is 43,236 B against the measured 43,239 B, the 3 B being the
newline-join drift noted in section 2.

**Read this table with section 7 attached.** It is the theoretical per-phase
figure. It is realized in full only under a delivery model that does not exist
today.

## 7. What the delivery model actually allows

The review child is ONE agent that runs all phases sequentially in a single
context. It is handed one instruction ("follow review.md exactly, read
conventions.md before starting") and reads both files whole. Under that model the
per-phase table above saves nothing by itself: a child that runs every phase still
accumulates every section.

Two delivery models could realize part or all of it.

**Model A, progressive disclosure (low risk).** Ship a spine of roughly the
universal core plus a phase index, with each phase's sections in its own file that
the child Reads when it enters that phase. The peak context of a child that runs
every applicable phase is still close to the full document set, so this does NOT
deliver the table in section 6. What it does deliver, reliably, is that
inapplicable phases are never read at all. That saving is real and is quantified
in section 8's recommendation.

**Model B, per-phase sub-agents (high risk).** Each phase runs as its own agent
loading only universal core plus its own sections, and section 6's table is
literal. I do not recommend this and I am not proposing it. Sections 2b, 2d, and 5
are deliberately cross-referential: 2d says explicitly "run this AFTER the 2b
residue checks", 4b says its roadmap-lint output feeds step 5, and 5c points back
to 2b.7. Splitting judgment across agents that cannot see each other's findings is
exactly the failure the repo's own memory warns about for parallel meeting fan-out
(loss of cross-examination). It also multiplies the universal core by the phase
count, so the total tokens spent go UP even as peak-per-agent goes down.

## 8. Recommended split, and its projected saving

Conservative Model A. Two mechanisms, both decidable before or early in the run.

**(a) Conditional phases, omitted from the brief when provably inapplicable.**

| Omitted | Bytes | Condition, decidable at dispatch |
|---|---:|---|
| review 2c host-bound gate | 1,019 | no reviewed ROADMAP item carries a `[host:<name>]` tag |
| review 5c + conventions Semver | 7,106 | repo has no versioned manifest (Semver rule 3, e.g. dotclaude-skills by design, id:8ef3), or nothing closed this window (rule 4) |
| review 6 spend remaining budget | 215 | HARD budget not granted this turn |
| **Conditional saving, version-less repo** | **8,340** | 19.3% off, leaving 34,899 |

**(b) Rationale relocated behind a pointer, procedure kept inline.** Only where the
block is pure justification of a rule stated elsewhere in the same section.

| Relocated | Bytes | Note |
|---|---:|---|
| conventions Semver rationale + amendment narrative | 2,969 | the 8-branch table (1,979 B) stays; the "why rule 6 overrides D1" narrative moves |
| review 5c Provenance/Homing/Out-of-scope | 567 | the fail-closed gate itself stays |

I deliberately do NOT propose relocating `review.md` 2d's it-infra id:3177 example
(648 B). It is the only concrete instance of the SUPERSET shape the check hunts,
and 2d has no cheating hypothesis to fall back on. Removing it is precisely the
silent-degradation risk this task warns about.

**Projected result:**

| Case | Load | Saving |
|---|---:|---:|
| Today, flat, all repos | 43,239 | -- |
| Version-less repo (a + b) | 31,363 | 27.5% |
| Manifest repo, close in window (2c omitted, b applied) | 38,684 | 10.5% |

Those two numbers are the honest headline for the recommended split. The larger
figures in section 6 require Model B, which I do not recommend.

## 9. UNSURE list

Every one of these is counted as NEEDED in the numbers above.

1. **conventions "Relay invariants" (2,613 B).** Mixed audience. "Children NEVER
   push" and "children do not run git-diary-workflow" bind the child; the
   pre-integrate isolation gate and the `ckpt-tag.sh` label rules are the
   INTEGRATOR's. A sub-split could plausibly move roughly 1,300 B out of the
   universal core, but the section is explicitly headed "orchestrator + children"
   and I cannot cleanly attribute every bullet. Counted universal in full.
2. **conventions "Durable Fable-bonus-recheck queue" (1,053 B).** Reads as purely
   the integrator's write ("the integrator records a model-tracked entry"). I
   could find no review-child action that consumes it. Counted universal anyway,
   because a review child whose checkpoint is the strong one may need to
   understand what its own checkpoint triggers.
3. **conventions "Tagging `[INTENSIVE]`" (1,757 B).** Assigned to P8. It cannot be
   conditioned on "the repo is already intensive", because the whole point is that
   the reviewer decides whether an item BECOMES intensive. So it is always needed
   whenever P8 runs, which is every review.
4. **review 2b.7, 2b.9, 2b.10 (3,012 B combined).** These fire only if the diff
   contains `@owner-accepted` / `@owner-answered` markers. That is greppable before
   dispatch, so they LOOK conditional. But the child has to know to run the grep,
   and a mechanical pre-grep that decides for it would be a new enforcement surface
   with its own failure mode. Counted as always needed.
5. **review 2d's example narrative (648 B).** Structurally it is a rationale block,
   the shape section 8(b) relocates. Counted as needed and explicitly excluded from
   relocation, per the reasoning in section 8.
6. **review 1 (425 B) and Return contract (1,076 B).** Arguably P0 and P12 rather
   than universal. Counted universal, which raises the floor rather than the
   saving.
7. **conventions "Executor-contract pointer" (1,414 B).** Assigned to P6, but it is
   only genuinely needed when the pointer is actually stale, which is a cheap
   pre-check. Counted as needed for P6 unconditionally.
8. **review 5's atomic-commit paragraph (id:2147).** It lives inside section 5 and
   is counted there, but P7 and P9 also write ledger and REVIEW_ME content and are
   bound by the same commit rule. My per-phase numbers therefore UNDERSTATE P7 and
   P9 by whatever fraction of section 5 that paragraph is. Any real split must
   promote it, probably into the universal core, which would shrink the saving
   further.
9. **Whether P5 (test tiers) is separable from P1/P2 at all.** Section 3 leans on
   section 2.4's `unverified` doctrine by explicit cross-reference. Counted as a
   separate phase; a real split may have to duplicate 2b.4 (439 B) into it.

## 10. Risks

- **Silent degradation is the whole risk.** There is no test that catches a
  reviewer that quietly stopped checking something. A section wrongly omitted
  produces a review that looks identical to a correct one. This is why the
  recommendation is conservative and why the UNSURE list resolves toward keeping.
- **A conditional can be wrong at dispatch time.** A `[host:]` tag or a new
  manifest can appear in the very diff being reviewed. Any conditional omission
  needs a cheap in-child re-check with a loud "I need the section I was not given"
  path, not a silent proceed.
- **A slice must never claim to enforce anything** (the id:9663 lesson already
  recorded in `relay-loop.js`). A sliced brief is a smaller brief, not a narrower
  contract.
- **An empty or minimal slice must never mean "skip the phase"** (the id:dd59
  lesson in `ledger-slice.sh:280-300`, corrected on live evidence). If the slicer
  cannot decide, it must ship the full section.
- **Model A adds a Read round-trip per phase**, and a child can skip a Read it was
  merely invited to make. The spine has to make each phase's Read an unambiguous
  obligation, or the omission becomes the degradation.
- **Model B is worse than it looks** and is not proposed: see section 7.

## 11. What is NOT in scope here

No implementation. No change to `review.md`, `conventions.md`, `relay-loop.js`, or
any ledger. The split in section 8 is a proposal for the owner to rule on.
