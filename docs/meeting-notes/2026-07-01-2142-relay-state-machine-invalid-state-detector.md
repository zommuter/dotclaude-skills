# 2026-07-01 — Relay as a state machine + invalid-state detector (id:4da4 part 2)

**Started:** 2026-07-01 21:42
**Session:** 5a6937db-9578-42ba-8b60-60faaab54298
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration / relay internals), 🔩 Gil (git plumbing / atomic-commit integrity), 🔭 Otto (measurement-without-perturbation)
**Topic:** Turn the relay's "what touches what when" into a formal model, and the two observed invalid states into a deterministic detector.

## Surfaced discoveries
- [2026-06-21 dotclaude-skills] mechanization determinism-gate — loud-reject over silent no-op (id:415b).
- [2026-06-30 dotclaude-skills] mechanical-classifier no-silent-swallow (id:4d8e / id:4347).
- relay-doctor id:9bec is the report-only aggregator; its fail-loud policy was already deferred once (id:0907).
- Sibling id:a17a (state-diagrams for /relay & /meeting, kept in sync) — folded into this meeting.

## Agenda
1. Is the deliverable the model, or a rendered state-diagram too?
2. Detector shape + home.
3. C5 — fail-loud vs report-only policy for the new invariants.
4. Where does check 10 (verdict-invariant replay) run?
5. C4 — the atomic main-write fix scope.
6. (Amendment) Fold id:a17a into this meeting.

## The model — artifact × actor × transition (§1)

Grounded in code; every transition read at `file:line`. Legend: R read · W working-tree write (uncommitted) · C commit · T tag · P push.

**Actors:** prelude (`relay-loop.js:723`) · discover-run mechanical runner (`:831`) → `discover-repo.sh` (composes `reconcile-repo.sh` + `classify-repo.sh --emit unit`) · executor (`:1256`) · reviewer/strong · integrator (`:1412`) · id:3801 handback follow-up (`handback-followup.py`) · file-surface (`file-surface-decisions.sh`) · /meeting · /relay handoff/review/next.

**Three actors write+commit the MAIN checkout, on non-shared paths (the load-bearing asymmetry):**
- **integrator** — `clean-tree-gate.sh` (`:1416`) → `merge --no-ff` + `ckpt-tag.sh` + `git-lock-push --ff-only` (`:1418-1422`).
- **id:3801 handback follow-up** — `md-merge.py update-ids` **write-only** (`handback-followup.py:173`) **then a separate** `git-lock-push.sh --ff-only` (`:194`). A death between the two strands `ROADMAP.md` dirty on main → **seed invalid-state (i)** (the loderite id:3801 residue).
- **reconcile-repo** — direct `git add -- uv.lock` + `git commit` (`reconcile-repo.sh:86-88`), un-flock'd, during discovery. Commits (never strands) but un-serialized.

**`commit-ledger.sh` is the id:148b atomic pattern** (single flock on `.git-lock-push.lock`, stage-scoped, commit under the one lock — `:86/:98/:108`) — used by /relay review/human/scan-routed/relay-reconcile, **NOT** by `handback-followup.py` nor `reconcile-repo.sh`. The C4 "deeper fix" = route the strander through this pattern.

**execute-on-no-work (seed invalid-state ii)** is already *prevented* at source post-part-1: `classify-verdict.sh:91` gates on `actionable_routine_open` (`classify-repo.sh:99-103`). What is missing is a standing *detector* (regression guard).

**Terminology correction:** the TODO text calls actor (i) "id:3801 gate-detection." In code, id:3801 = the durable-handback follow-up (`handback-followup.py`); the generic "gate-detection" also covers /relay review/human ledger annotations (`commit-ledger.sh`). Two distinct main writers — only `handback-followup.py` currently strands.

## Invariants (round-boundary; after integrate, before next prelude)

| # | Invariant | Origin | Mechanizable now? |
|---|---|---|---|
| I1 | main checkout clean OR dirty-lock-only; no foreign-dirty tracked edit persists | seed (i); `clean-tree-gate.sh` | YES (porcelain per own repo) |
| I2 | `verdict==execute ⟹ actionable_routine_open>0` | seed (ii); `classify-verdict.sh:91` | YES (replay `classify-repo.sh --emit unit`) |
| I3 | no id open in ROADMAP but closed in TODO (or vice-versa) | `orphan-scan --cross-ledger` | YES (already wired, `relay-doctor.sh:153`) |
| I4 | `intensive!="" ⟹ verdict∈{execute,hard}` | id:5ac6, `classify-verdict.sh:161` | YES (assert on unit) |
| I5 | no worktree without a live claim OR a `relay/orphan/*` ref | `reconcile-repo.sh:92`; id:d187 | PARTIAL — gated on id:e149 heartbeat |
| I6 | relay.toml parses under strict tomllib | id:2945 | YES (already wired, `relay-doctor.sh:443`) |
| I7 | no gate-detection/handback ledger write left uncommitted | seed (i), subset of I1 | YES (detect); fix = C4 |
| I8 | relay.toml `last_ckpt` names an existing git tag | integrator `:1426` | YES (`rev-parse --verify`) |
| I9 | no decision-queue entry for an already-`[x]` id | `file-surface-decisions.sh` | PARTIAL — gated on id:b444 schema |

Core detectable-now (pure fn of state): I1, I2, I4, I8 (+ I3, I6 already wired). Gated: I5 (id:e149), I9 (id:b444).

## Discussion
🏗️ **Archie** anchored the model in the §1 matrix (11 artifacts × 9 actors, file:line-cited) and argued a Mermaid diagram would be a drift-prone second rendering of the same facts. ✂️ **Petra** placed the diagram out of scope by ownership — id:a17a already owns "state-diagrams kept in sync" and wants derive-or-guard, not hand-sync. 😈 **Riku** accepted, conditional on the matrix being precise enough for id:a17a to later generate from (it is).

On the detector, 🏗️ **Archie** + 🎛️ **Orla** put it as three `relay-doctor.sh` checks (lever-first; it is already the report-only aggregator with `check_repo()`, a coverage-gap honesty block `:529`, and `--strict` id:a883). 😈 **Riku** flagged that check 10 re-runs classification — but the derived count (`classify-repo.sh`) and the verdict (`classify-verdict.sh`) are *different* scripts, so a self-replay cross-checks one against the other and catches exactly the part-1 gate-wiring bug class; it cannot catch a bug where derivation and gate agree wrongly (coverage must be stated honestly).

On C5, 🏗️ **Archie** presented the draft's "I1/I2 always `--strict`/block-a-round." 😈 **Riku (pre-emption)** flagged a profile contradiction — *identity-resolution conservatism* (high confidence): a consistent preference for a reversible/visible signal over a hard auto-exclusion that could silently bury, and intent-over-mechanical-firing on gates. A false-positive invariant hit that halts real dispatch is exactly that. 🔭 **Otto**: no-silent-swallow (id:4347) demands the violation be *loud*, not that it *block*; report-only-but-prominent satisfies "loud." Build the detector as a measurement, watch firing-frequency, add enforcement only if a violation proves frequent+harmful (observe-before-preventing). ✂️ **Petra**: report-only for all new invariants therefore unblocks C1–C3 to land in parallel (C5 stops being a prerequisite).

On C4, 🔩 **Gil** confirmed the stranding window (`handback-followup.py:173` write-only md-merge → `:194` separate push) and that `md-merge.py` already supports `--commit` (the id:148b atomic pattern). ✂️ **Petra** scoped out `reconcile-repo.sh:86` (un-serialized but commits, never strands; zero incidents — observe-first). 😈 **Riku** set the C4 test contract: simulate the death *between* md-merge and push and assert no dirty residue.

**Amendment (id:a17a):** 🏗️ **Archie** — this meeting produces the machine-readable-ish source a17a was missing (the file:line matrix + the detector naming the real state set), so a17a narrows to *guard* (a test that a diagram's states match the detector's/loop's real mode+verdict set). ✂️ **Petra** — fold = cross-link + record the strategy, keep a17a its own build item (no scope creep).

## Decisions
- **D1 — Deliverable.** The model is the §1 matrix + invariants I1–I9 (this note is the artifact). Detector = three new `relay-doctor.sh` checks. A rendered state-diagram is OUT of scope → id:a17a. *Out of scope:* any Mermaid/diagram build here.
- **D2 — C5 policy (report-only floor).** All new invariants surface loudly but NEVER auto-block a round; the existing `--strict` (id:a883) stays an explicit human/CI opt-in. Firing-frequency is observed before any enforcement is added. *Out of scope:* wiring any invariant to abort a round.
- **D3 — Check 10 replay.** Self-replay now (`classify-repo.sh --emit unit`, read-only) asserting `execute⟹actionable_routine_open>0` and `intensive!=""⟹verdict∈{execute,hard}`, with an honest coverage note (guards verdict↔derivation *consistency*, not derivation *correctness*). Reading `relay-events.jsonl` for the real dispatched verdict is a noted future upgrade. *Out of scope:* the events-read path for now.
- **D4 — Disposition.** C1–C4 are filed as RED-spec ROADMAP items for the pool/executor; NOT implemented in this Opus session. *Out of scope:* inline implementation.
- **D5 — id:a17a.** Amended to cite this note as source-of-truth; strategy narrows to drift-GUARD (not hand-sync); a17a stays its own build item. *Out of scope:* building the diagram/guard here.
- **C4 scope.** `handback-followup.py` stranding window only. `reconcile-repo.sh:86` is OUT of scope (un-serialized but commits, no observed incident).
- **Coverage honesty.** I5 (gated on id:e149 heartbeat) and I9 (gated on id:b444 decision-queue schema) are listed in relay-doctor's coverage-gap block as not-yet-wired — no build now.

## Action items
- [ ] C1 [ROUTINE] `relay-doctor.sh` check 9 — main-checkout residue (I1/I7): reuse `clean-tree-gate.sh`; count non-lock-only dirty as issues; report-only (honors existing `--strict`). Test: foreign-dirty tracked ledger edit → reported; lock-only → clean. <!-- id:8018 -->
- [ ] C2 [ROUTINE] `relay-doctor.sh` check 10 — verdict-invariant replay (I2/I4): run `classify-repo.sh --emit unit` read-only, assert `execute⟹actionable_routine_open>0` ∧ `intensive!=""⟹verdict∈{execute,hard}`; print honest coverage note. Test: `@manual`-only `[ROUTINE]` repo (verdict≠execute) + synthetic `intensive` w/ verdict=review → flagged. <!-- id:188c -->
- [ ] C3 [ROUTINE] `relay-doctor.sh` check 11 — `last_ckpt` tag existence (I8): parse each own repo's toml block, `rev-parse --verify refs/tags/<tag>`; missing → issue. Test: toml `last_ckpt` naming a non-existent tag → flagged. <!-- id:333c -->
- [ ] C4 [HARD — pool] atomic main-write fix (seed state i): route `handback-followup.py`'s ROADMAP write+commit through the id:148b atomic path (pass `--commit` to `md-merge.py` so write+commit are one flock, or via `commit-ledger.sh`). Test: simulate death between write and commit → no dirty residue. reconcile-repo.sh out of scope. Cross-ref id:148b/id:2147. <!-- id:e5e9 -->
- [ ] Coverage-gap block: list I5 (gated id:e149) + I9 (gated id:b444) in relay-doctor's not-yet-wired section (no build). *(folded into C1–C3's relay-doctor edits)*
- [ ] Amend id:a17a: cite this note as source-of-truth; strategy = drift-guard. *(bookkeeping, done in this session's write-back)*
