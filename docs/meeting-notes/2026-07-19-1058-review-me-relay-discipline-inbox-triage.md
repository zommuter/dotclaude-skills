# 2026-07-19 — REVIEW_ME / relay-discipline inbox triage (loderite 2026-07-18 retro)

**Started:** 2026-07-19 10:58
**Session:** a44f59c6-4299-42c5-9b1c-44af75762b23
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime / relay-contract mechanics, new), 🎛️ Orla (multi-agent orchestration / verification-gating, new)
**Topic:** Triage the two REVIEW_ME/relay-discipline inbox items (`routed:16e3`, `routed:3684`, filed from the loderite 2026-07-18 multi-model retro) into the dotclaude-skills ledger — adopt, lane, dedup against existing items, ground in the chidiai cases that generated them.

## Surfaced discoveries / memory intersections
- [[mechanization-415b]] — determinism-gate (M/G/K); [[enforce-contract]] — ENFORCE not document, fail-closed; [[gaming-detection]] (id:2909) — define-then-meet; [[human-sweep]] — stale-box recurrence; [[use-existing-tools]]; [[observe-before-preventing]].
- Live item **id:2e5c** (REVIEW_ME box↔ledger freshness lint, owner-prioritized 2026-07-16) — the dedup anchor for Cluster A.
- **chidiai cases (2026-07-18)** are the authoritative source — both inbox items were filed *from* them (see §Chidiai grounding). The owner flagged mid-meeting that these had not been read; correcting that materially sharpened every cluster.

## Context
Neither `routed:16e3` nor `routed:3684` was in TODO/ROADMAP — genuinely still in the inbox. Key grounding from the current tree:
- `templates.md:58` already says *"the reviewer prunes resolved ones each review turn"* — the prose 16e3(a) says silently no-ops.
- `templates.md:60` already mandates the **one-line** REVIEW_ME box — 16e3(b)/3684(5); the gap is enforcement.
- `review.md §3 / :135` (id:f032) already fully specifies tier-coverage (enumerate declared tiers from manifests, run-or-record-skip with `SKIPPED-TIER:`, ban subset-green) — 3684(1) *enforces* it.
- `classify-verdict.sh` has `{blocked,execute,review,hard,handoff,human,idle,AMBIGUOUS}` — **no `drained`**; `@manual` is live grammar, **`@wire` does not exist** — the genuinely new pieces (3684-2).
- `archive-closed.sh` (id:85d3) has REVIEW_ME support but is referenced **nowhere in `review.md`** — the mechanical pruner exists, it's just never invoked in a review turn ([[mechanize-first]] "loud detection, silent resolution").

So all 7 sub-parts are one species: **a relay contract rule already written as prose that silently no-ops under context pressure.** Determinism gradient: A+B = enforce-an-already-written-rule (mechanizable now); C = genuine new-grammar design; D splits.

## Discussion
Full transcript accumulated in chat (Opus normal-mode; no plan file). Decision points below carry the persona reasoning. The `scoped-a-core-feature-out` chidiai case (a `/meeting` facilitator asserting without checking the primary source) was flagged as a live self-caution — and was nearly repeated here until the owner forced the chidiai read.

## Chidiai grounding (2026-07-18 cases → sharpened acceptance contracts)
| Cluster | Case (severity) | Sharpening |
|---|---|---|
| A | `review-me-accreted` (Med) | Three invariants verbatim: mechanize per-turn prune; prune-or-it's-an-archive (resolved→RELAY_LOG); detail-to-log/queue-one-line. Our own REVIEW_ME violates all three (14 unpruned `[x]`, verbose open boxes). |
| B | `skipped-e2e-tier` (High) | Gate must **probe toolchain presence** to validate a skip — "doc-only window" is a judgment excuse, not a toolchain-absent skip. If `~/.cache/ms-playwright`/`node_modules` present ⇒ a `SKIPPED-TIER` claim is **rejected**. |
| C | `declared-drained` (High, retro-corrected) | "drained" = machine verdict (no open `[ROUTINE]`/`[HARD]` AND no open `@wire` half), never author prose; a routing headline may not contradict an in-context decomposition; **C must include a re-label migration** — loderite's ROADMAP has 103 `@manual` occurrences mislabelling executor-doable wiring. |
| D4 | `instructed-executors-author-own-RED` (High) | Strong side authors the RED spec; a flagged gap gets the *real* fix (not cosmetic RED-first on a self-authored test); shipped-on-self-marked = provisional → reopen. Folds into C. |
| C-input | `red-spec-verified-named-consumers` (Mod) | Even a handoff-authored spec is bounded by the consumers its author enumerated — C adds an "enumerate every reader of the artifact" discipline. (Sibling `routed:4fa9`/`c441`, not in inbox — out of scope.) |

## Decisions
- **D1 — Meeting scope = triage-and-adopt; Cluster C spun out.** Adopt A/B/D4 now with lanes+ids (deduped vs 2e5c); file C (drained+@wire) and D3 (visible-half, gated on C) as their own `[HARD — meeting]` design items. No scripts written today. Out of scope: designing the `@wire` regex, re-deriving the roadmap, the `4fa9`/`c441` sibling, the `fabricated-meeting-transcript` case.
- **D2 — Cluster A = new sibling item (id:07dc), cross-referencing id:2e5c, NOT folded in.** 2e5c owns *semantic freshness* (reads the live ledger); 07dc owns *syntactic hygiene* (prune + shape, reads only REVIEW_ME + git). Different inputs, separate scripts, shipped as a family. Prune axis is mostly *wiring the existing `archive-closed.sh` into the review turn + a loud over-ceiling count*, not a new pruner. Lane `[HARD — pool]`, handoff-authored RED fixtures. Child of the hook-substrate item (id:7a05). Out of scope: merging into 2e5c.
- **D3 — Cluster B (id:66d4) = `[HARD — pool]`, enforces id:f032.** A review-checkpoint gate enumerates declared tiers from manifests and refuses the checkpoint unless each carries a result-or-`SKIPPED-TIER` token; the gate **probes toolchain presence** so a judgment-excuse skip is rejected. Binds subagents (same script). May co-locate with 07dc's prune in one `review-gate.sh` host — implementation detail for the handoff. Out of scope: running tiers is not a pre-commit-hook operation (B stays a review-turn gate).
- **D4 — Cluster C (id:af48) = `[HARD — meeting]` design item; D4 (executor-no-own-RED) folded into it.** Mints the `drained` verdict + the `@wire`/`@manual` grammar axis; includes the 103-occurrence `@manual`→`@wire` re-label migration, the enumerate-every-consumer spec-completeness discipline, and the executor-no-own-RED policy **with** at least a loud detector (policy-without-enforcement reproduces the no-op). Design venue, not built inline. Out of scope: settling the grammar in this meeting.
- **D5 — Cluster D3 (id:2b49) = `[HARD — meeting]`, `gated-on:af48`.** Visible-half-is-primary: handoff authors the visible-half RED spec (failing e2e / snapshot-diff), sizes it as `@wire` executor work, never parks it `@manual`; "done" requires the visible half. Consumes C's `@wire`, so it does not build before C ratifies. Out of scope: building before af48.
- **D6 (amendment) — hook-substrate item (id:7a05) = `[HARD — meeting]`, parent of Cluster A.** Adopt git pre-commit hooks as the loud-reject enforcement substrate for *cheap, commit-time* ledger invariants (formatting / one-line shape / size ceiling / archival trigger / cross-ledger checkbox consistency / provenance-of-tick). Check *logic* written once as standalone scripts, invoked from whichever substrate fits (git pre-commit and/or Claude Code hooks) — not forked per substrate. **Provenance-of-tick = block immediately (owner's call, over the observe-first recommendation)**, with a HARD prerequisite in the DoD: a blocking hook **must be validated against every relay automated commit path** (`md-merge.py --commit`, `ckpt-tag.sh`, integrator `--no-ff` merge, `git-lock-push.sh`) — a false-positive there wedges the pool. B is out (can't run tiers at commit time). Out of scope: designing the hook system inline.

## Action items
- [ ] REVIEW_ME box syntactic-hygiene lint (prune + shape) — `[HARD — pool]`, xref id:2e5c, child of id:7a05 <!-- id:07dc -->
- [ ] Tier-coverage checkpoint gate — `[HARD — pool]`, enforces id:f032, toolchain-probe skip validation <!-- id:66d4 -->
- [ ] `drained` verdict + `@wire`/`@manual` grammar split (+ D4 executor-no-own-RED + spec-completeness) — `[HARD — meeting]` <!-- id:af48 -->
- [ ] Visible-half-is-primary handoff discipline — `[HARD — meeting]`, gated-on id:af48 <!-- id:2b49 -->
- [ ] Ledger-invariant enforcement substrate (loud-reject pre-commit hooks; provenance=block w/ relay-safety prereq) — `[HARD — meeting]`, parent of id:07dc <!-- id:7a05 -->
- [ ] Dogfood: prune this repo's REVIEW_ME.md resolved boxes via `archive-closed.sh` (in-session owner directive) — *resolved in-session, not mirrored to TODO*
- [ ] `inbox-done 16e3` and `inbox-done 3684` once adopted — *resolved in-session*
