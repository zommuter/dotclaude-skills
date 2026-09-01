# 2026-09-01 -- Ledger line-shrink: ratifying the FORMAT (id:0d7c)

**Started:** 2026-09-01 22:26
**Session:** e266a9e6-6437-468c-93ea-5b90b1990598
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🔎 Dex (marker grammar / define-vs-refer), 🏷️ Tilda (work-management substrate), 🛰️ Hank (fleet migration topology); 🜛 Fable-5 as closing adversarial reviewer (`--fabled`)
**Topic:** Ratify the FORMAT for ledger line-shrink before any build, consolidating loderite's `routed:04cf` with `id:55f6`.

**Scope fence:** FORMAT only. BUILD FULL per-item was owner-ratified 2026-08-13 and restated 2026-09-01 and was not reopened. Four of `id:55f6`'s six sub-questions were answered by the owner earlier the same day and were not re-litigated.

## Agenda

1. Reconcile `routed:04cf`'s REVIEW_ME merge against the owner's same-day "REVIEW_ME out of the per-item tree" ruling.
2. Where does the marker keep-set come from, given the hard constraint that markers must stay on the item line?
3. Detail-file topology, provenance, and lifecycle.
4. The ratchet: budget and home.
5. The write path and concurrency.
6. What is in scope for this item versus filed separately.

## Verified before the meeting opened

Three checks were run rather than cited. Two changed the brief.

- **The item's own build plan was false.** `TODO.md:870` said loderite's extractor "already performs exactly the relocate-body-leave-pointer move; pushing its `--min-chars` down is the cheap 90%." loderite measured otherwise (`routed:2711`, filed the same day): the tool moved *indented continuation lines only*, so items with everything on the checkbox line were invisible to it. At `--min-chars 1000` it found one item worth 188 bytes while the longest open lines were 9,187 and 7,496, and it never touched TODO.md at all. A usable reference implementation does now exist (`splitHead` at `tools/extract-roadmap-notes.mjs:101`, `MUST_KEEP_PATTERNS:74`, `--split-heads`, `--file`, plus `tests/extract-roadmap-head-split.test.ts`), with measured dry-runs of ROADMAP 361,717 -> 313,143 and TODO 418,346 -> 126,347.
- **`MUST_KEEP_PATTERNS` omits the marker the hard constraint names first.** No lane-tag pattern, no `routed:` pattern. The lane tag survives only because it sits left of the cut point, which is position rather than rule. Measured: **59 exact-form `<!-- routed:XXXX -->` markers sit after the cut point** (48 TODO, 11 ROADMAP); relocating them breaks `inbox-done`'s anchored twin-check. A lane-loss count could **not** be produced reliably here (this repo quotes lane vocabulary in prose constantly; the detector moved between 1 and 27 depending on definition), so it is recorded as an unenforced gap, not a number.
- **The stated basis of the REVIEW_ME ruling does not match the file.** "57 entries, only 2 keyed" is what the handover and the item both record. Actual: `REVIEW_ME.md` has 21 boxes, 15 keyed, 42,860 bytes; with `REVIEW_ME.archive.md`, 126 boxes and 100 keyed. The 57/2 figure could not be reconstructed under any counting tried.

**Measured distribution (this repo):** TODO.md carries 1,261,641 bytes on 674 item lines (median 1,380, p90 3,690, max **28,617** -- roughly 7k tokens returned by a single `grep` hit). ROADMAP.md carries 107,988 bytes on 127 lines. At a 500-char budget, 935 KB of TODO is recoverable (74%); at 800, 768 KB (61%); at 1200, 585 KB (46%).

## Discussion

**On REVIEW_ME (D1).** Archie held that the two rulings answer different questions and neither noticed: "is REVIEW_ME a *source* of bloat worth relocating" is a size question whose answer is genuinely no (42.9 KB against 1.25 MB), while "how many files must a reader chase for one id" is a topology question that size does not bear on. Dex identified the keying ratio as the fact that decides it, which is why the false figure mattered: at 2-of-57 the merge would be *undefined* for the majority and "out" would follow mechanically; at 100-of-126 it is well defined. Riku argued the other way, that REVIEW_ME boxes are transient by design and merging a transient queue into a durable store leaves residue in a file that outlives it. Tilda framed it as a schema question: TODO and ROADMAP share a record identity, whereas a REVIEW_ME box is keyed *by* an id but is *about* an artifact the item produced, which is a foreign key rather than shared identity. Petra costed inclusion at ~2.5% of the bytes. Hank asked that whatever was decided be recorded on grounds that survive checking.

**On the keep-set (D2).** Dex located the defect in the reference implementation's own docstring, which instructs the reader to "keep this list in sync with `classify-repo.sh`'s substring matches and `hard-lanes.md`" -- a hand-maintained cache of another file's matcher, whose failure mode is silent invisibility. Riku posed the choice as derive-versus-refuse. Hank noted that a prose "keep in sync" instruction has never held in this fleet.

**On topology (D3).** Archie's finding, recorded because the item claims the opposite: the merge does **not** collapse single-id-two-views. Two-views lives at the line level, which is all `orphan-scan --cross-ledger` compares; each ledger keeps its own line and checkbox and only the body merges. Dex required each section to name its true source. Tilda raised the transient-to-durable lifecycle, and Riku identified `routed:71ed` (the `roadmap-archive.sh` block rule already mis-attributing bodies across items) as a live prerequisite rather than a parallel concern.

**On the ratchet (D4).** Hank found the grandfathering already built as the `id:cb3e` WARN-to-ERROR baseline. Archie observed that `todo-conformance.sh:19` never lints continuation lines, so removing bodies perturbs its grammar not at all. Petra derived the budget from the recovery curve rather than taste.

**On the write path (D5).** Archie showed contention dissolves under the existing tool-choice rule: `md-merge.py` exists because TODO.md is shared and non-union, whereas a per-id file holds one item, so a collision there is a real conflict rather than a merge artifact. Riku countered that atomicity does not dissolve: one shrink writes two files, and `id:148b` exists so a ledger edit commits under one flock with no dirty residue for the pool's `id:aa93` guard.

**Backlink feasibility (owner requirement at D3b).** Measured live: the full index across 217 meeting notes and 1.73 MB builds in **0.034 s**; 659 distinct ids are cited and **259 in two or more notes**, which is the "haven't we settled this before" population. `id:55f6` resolves to three prior meetings.

## Decisions

Each decision below is stated **as amended**. Where the closing pass forced a change, the superseding text is marked and cites what it supersedes; no ratified original was silently rewritten.

- **D1 -- REVIEW_ME joins the per-item tree, re-scoped to single-id boxes.** This REOPENS and overrides the owner's earlier same-day "REVIEW_ME out" ruling, on the ground that that ruling's stated basis ("57 entries, only 2 keyed") is false. **AMENDED after the closing pass (supersedes the unrestricted merge ratified earlier in this session):** only boxes carrying exactly ONE id join (7 of 21 live). 14 of 21 live boxes cite multiple ids, for which "an id's REVIEW_ME text merges into one file" is undefined, and per `id:6059` `md-merge.py` REFUSES multi-marker lines outright -- so the unrestricted form fed D5's write-owner lines it structurally rejects. Multi-id boxes stay in `REVIEW_ME.md` and are out of the tree until their semantics are designed. **Out of scope:** duplicate-into-N-files and primary-id-by-rule are both explicitly undecided.
- **D2 -- The keep-set is DERIVED from the detectors, not hand-maintained, verified by an end-to-end round trip.** Owner's words: *"3 and make sure that's kept in sync via e2e tests (that re-extract them maybe?)"*. The mechanism does not parse the ~48 detector files; it RUNS them. **AMENDED after the closing pass (supersedes strict before/after equality):** (a) the predicate is **directional** -- a verdict may move only toward "spurious hit removed", never toward "gate or lane lost" -- because strict equality fails by construction on `classify-repo.sh`'s `roadmap_bytes`/`todo_bytes`/`review_me_bytes` fields and fires on spurious substring hits legitimately disappearing; (b) the detector set is **explicitly enumerated** in a registry, with non-pure detectors (git, worktree, network) declared out of scope in writing; (c) a **grep-derived marker registry** is cross-checked against the keep-list, catching shapes the corpus does not currently exercise (`@wire`, `@owner-verify`, `@needs-auth`, lowercase `blocked on`). **Out of scope:** proving preservation for detectors that cannot run as pure functions of the ledger.
- **D3 -- ONE detail file per id at `docs/ledger-notes/<id>.md`, sections named by logical ledger.** Sections are `## From TODO`, `## From ROADMAP`, `## From REVIEW_ME`. **AMENDED after the closing pass (supersedes physical-path section names):** naming the physical file (`## From TODO.md`) goes stale the moment `archive-done.sh` moves the line to `TODO.archive.md`, which is the same staleness role-naming was rejected for; the logical name keeps provenance without the archive-boundary rot. Recorded finding: **the merge does NOT collapse single-id-two-views** -- two-views lives at the line level and only the body merges, so the item's own claim to the contrary is wrong on the mechanism. Path verified unclaimed (no existing reference to `docs/ledger-notes/` anywhere in the repo). **Out of scope:** per-view files, role-named sections.
- **D3b -- A detail section carries its box's own state, and the archiver moves it on the same trigger that moves the box.** `routed:71ed` is a HARD PREREQUISITE, not a parallel item. Owner requirement: the per-id file must surface the MEETINGS linked to that id, to avoid the "haven't we settled this before" failure. **AMENDED after the closing pass (supersedes an embedded derived section):** backlinks live in their OWN derived file and the detail file carries only a static pointer -- embedding a regenerated block inside a hand-edited file inverts `id:2840` (whose model puts the cache in a separate artifact) and lets a hand edit be silently clobbered on regen. Noted, not resolved: at least three archival code paths exist (`archive-done.sh`, `roadmap-archive.sh`, REVIEW_ME resolution) and `71ed` fixes only one. **Out of scope:** the relevance filter for noisy backlinks.
- **D4 -- Ratchet budget is 500 chars on the head line, home `relay/scripts/todo-conformance.sh`.** **AMENDED after the closing pass (supersedes "reuse the cb3e baseline, build no second mechanism"):** the `id:cb3e` baseline is ID-keyed and its own source documents that it *"silently RE-GRANDFATHERS ... There is no expiry"* (`lib-state-claim.sh:157`). It therefore cannot express "modified lines BLOCK": every current id would be baselined and could regrow to 30 KB unchecked, which is precisely what the owner's ratchet requirement exists to prevent. The ratchet instead **baselines the LENGTH and enforces monotonic shrink** -- an over-budget line may be modified only if the new length is less than or equal to the old. This is the second mechanism D4 originally forbade, ratified deliberately. **Composition rule, also amended:** a line the splitter REFUSES to cut is reported but never blocks (a rule may not demand a cut the tool will not make), and `splitHead` gains a fallback cut point so the 193 bold-less items (150 TODO, 43 ROADMAP) shrink over time rather than being permanently exempt; the 23 split heads still over budget are baselined at post-split length. **Out of scope:** an 800 or 1200 char budget; a per-id total-bytes budget.
- **D5 -- `md-merge.py` owns BOTH files: one call, one commit.** The reason is ATOMICITY, not contention -- contention genuinely dissolves, but the commit must cover both files or the pool's `id:aa93` dirty-guard can scoop a half-state through the window `id:148b` closed. **AMENDED after the closing pass (supersedes per-ledger locking and the prose-only-Edit clause):** the lock is keyed on the DETAIL FILE (per-id) and acquired in a FIXED order with the ledger lock (ledger, then detail), because one id's detail file is a write target from two or three independently-locked ledgers and the ratified form raced, including both-create-the-file. The "detail files remain ordinary Edit-able files for prose-only edits" clause is **struck**: it licensed an unlocked bypass, and this repo's own tool-choice doc records Edit as the larger flock-bypass channel. **Out of scope:** a single coarse lock over the whole notes tree.
- **D6 -- Four spin-offs, all ratified.** (a) file the reference-doc slicing item separately; (b) route relay-core shadow parity via the inbox; (c) derived meeting backlinks become their own child, shippable before the shrink; (d) correct `id:0d7c`'s false premises in place.

## `--fabled` closing pass

🜛 Fable-5 ran as a single closing adversarial reviewer, fed the ratified decisions verbatim, framed as design critique. It returned **12 findings, 7 of them amendment-forcing**, and independently reproduced the `cb3e` finding the facilitator had reached minutes earlier from the same source.

Forced amendments, all accepted by the owner: (1) `ledger-slice.sh` (`id:e68f`, 10 references in `relay-loop.js`) hands every dispatched child its spec and does not follow detail pointers, so post-shrink children receive a well-formed, honest-byte-count slice **missing its acceptance criteria** -- verbatim the `id:b015` failure its own header documents; (2) the `cb3e` reuse cannot express "modified lines block"; (3) 14 of 21 live REVIEW_ME boxes are multi-id and `md-merge.py` refuses multi-marker lines; (4) the round-trip predicate fails by construction on the byte fields, which also means the `id:4f9b` prompt-size gate goes systematically optimistic post-shrink, partly disarming the guard against this item's own founding failure; (5) the splitter and the ratchet do not compose on today's corpus (193 refused lines, 23 over-budget split heads); (6) per-ledger locks race on a shared detail file; (7) the `routed:` marker finding had no owning decision.

Hardening findings recorded and not separately actioned: (8) the round trip certifies the corpus rather than the rule -- addressed by D2's marker registry; (9) verdict equality is wrong in the false-positive direction too -- addressed by D2's directional predicate; (10) physical section names stale at the archive boundary -- addressed in D3; (11) the embedded derived section inverts `id:2840` -- addressed in D3b; (12) small oddities, of which one is binding: **the reference `pointerFor` emits an em dash** (extractor line 52), so the port must strip it -- the ban is a hard rule, so this is compliance rather than a decision.

**Pre-registered escalation trigger:** 7 forced-amendment findings against a threshold of 2. This is the sixth recorded firing and ties the highest count to date. Fable's own summary: *"The direction itself (BUILD FULL per-item) is not undermined by any of this; every finding is about mechanism, sequencing, or an unstated assumption, not about whether prose should move."*

## Amendment session -- post-closure, 2026-09-01 ~22:5x

Evidence arriving AFTER the note was written and committed: loderite (session `loderite-3d`)
IMPLEMENTED AND RAN the shrink in its own repo tonight and reported measured results. Two of its
findings were new to this meeting; the other four (head-line-is-a-control-surface,
refuse-rather-than-guess, provenance-names-its-true-source, and the 43.2k reference-doc cost)
were already covered above and are unchanged.

**AMENDS D2 (supersedes its acceptance check as ratified above; the derive-from-detectors
ruling and the directional predicate both STAND).** loderite's shrink **silently dropped four
ids** (`89f9`, `a5b6`, `ba07`, `ed26`). All four sat on INDENTED lines carrying their own
`<!-- id:XXXX -->`; the parser anchors its item regex at column 0, so an indented sub-item reads
as CONTINUATION of the preceding top-level item, and relocating that continuation carried its id
marker off the ledger. The body survived in the note file; **the ADDRESS did not** --
`md-merge update-ids` can no longer reach those ids and `orphan-scan` cannot see them. Nothing
failed loudly: open-item counts were unchanged and their round-trip guard passed green.

This is a class our ratified predicate provably misses, because a lost id need not change any
detector verdict. The acceptance check is therefore **the directional verdict round trip AND an
exact id-SET diff (before == after, per ledger)**, plus loderite's conservative rule: **REFUSE to
relocate any continuation that contains another id marker**, and report it. A long line costs
context; a lost id costs the item.

**Exposure measured here:** `TODO.md` carries **21** indented lines with their own id (ROADMAP.md:
0) -- e.g. `TODO.md:41-46`, `:101-111`, `:143`. The 2026-09-01 ruling to "promote the 11 then lint
the construct out" is recorded against a count of 11; **11 and 21 are not reconciled**, and the
owner ruled that 11 is UNVERIFIED until they are. Filed as `id:8679`. Sizing a promote pass at 11
against a true population of 21 leaves ten ids in precisely the orphaning shape.

**loderite's fifth finding (old-vocab lane tags block a sweep) is REAL as a mechanism but does
NOT bind here, and the reason is worth recording.** Rewriting a line that carries an old-vocab
lane tag turns a GRANDFATHERED tag into an ADDED one, so `hooks/pre-commit-lane-vocab.sh` blocks;
loderite hit this on two `[HARD — hands]` items, a lane `hard-lanes.md` gives no auto-default.
Checked against our hook rather than assumed: it masks backtick-quoted mentions and fires only on
a CHECKBOX line's LEFTMOST lane bracket, and detail files contain no checkbox lines, so relocating
prose into new files cannot trip it. Recognized old vocabulary is exactly four lanes (pool,
meeting, decision gate, hands) and we have **zero live `[HARD — hands]`**. Note the trap that cost
three re-measurements: `[INPUT — meeting]` is NEW vocabulary carrying the OLD em-dash DELIMITER,
a separate in-flight migration the hook does not block -- raw greps conflate the two and
over-report by an order of magnitude (118 raw hits vs effectively zero genuine blockers).

**Sizing datum, for reference:** loderite measured 793,338 -> 453,327 chars overall (-43%), with
TODO.md alone 418,764 -> 130,103 (-70%) and 131 items relocated; parity verified after at ids
275/275 and 209/209, open items 137/137 and 198/198, all gate-marker counts identical, roadmap-lint
unchanged at 14.

## Action items

- [ ] Rewrite `id:0d7c` to the ratified format above, correcting its three disproved premises: the "cheap 90%" build plan, the "57 entries / 2 keyed" REVIEW_ME figure, and the "collapses single-id-two-views" claim. <!-- id:0d7c -->
- [ ] `ledger-slice.sh` must inline the pointed-to detail file. HARD PREREQUISITE of the shrink, same standing as `routed:71ed`. Contract: a dispatched child's slice contains the item's acceptance criteria after the shrink exactly as it does before. <!-- id:2ee1 -->
- [ ] Extend the `id:4f9b` prompt-size gate to count pointed-to detail files. Contract: post-shrink the gate's byte estimate for an item is not lower than the bytes a child actually loads. <!-- id:f3d2 -->
- [ ] Per-phase slicing of the review child's mandatory reference docs: `relay/references/review.md` (29,051 bytes verified) + `conventions.md` (14,188) = 43,239 chars loaded before any ledger is read. Different mechanism from body relocation; cites `routed:2711` point 5. <!-- id:a282 -->
- [ ] Derived meeting-backlink index as its own file (`children-of:0d7c`). Independently useful with no line-shrink at all: 659 ids cited across 217 notes, 259 in two or more. Measured build time 0.034 s. Contract: regenerating is idempotent and never clobbers hand-edited content. <!-- id:e8af -->
- [ ] Reconcile the indented-id count before any promote pass: the 2026-09-01 ruling says "promote the 11", measurement says 21 indented lines in `TODO.md` carry their own id (ROADMAP: 0). Treat 11 as UNVERIFIED until the two scopes are reconciled; each unpromoted line is an id a shrinker can orphan silently. Contract: the promote pass and the measurement agree on one population before it runs. <!-- id:8679 -->
- [ ] relay-core shadow-binary parity: a ledger-format change puts `classify-verdict.sh` / `gather-repo-state.sh` parity RED. Different repo. -> routed to relay-core inbox <!-- routed:c6c5 -->
