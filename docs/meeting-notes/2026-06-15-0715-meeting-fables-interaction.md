# 2026-06-15 — Making /meeting ↔ /fables-turn ↔ /fables-executor play well together

**Started:** 2026-06-15 07:15
**Session:** 6da37998-0939-4483-a33c-5f9345580ff9
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🧩 Sage (skill-runtime — standing in this project)
**Topic:** Find and close the remaining integration seams between the design-meeting skill and the reviewer/executor relay, given dotclaude-skills is dogfooded as both a meeting-using and a relay-managed repo.

## Surfaced discoveries
- No `discoveries.md` entry intersects the relay×meeting topology directly.
- Already-wired seams (found at setup): `orphan-scan.sh` reads the union TODO + archive + **ROADMAP.md**; `classify.sh` recognizes the `RELAY` mirror line and never proposes a meeting on it.
- This meeting's topic was **already decomposed into tracked items**: `id:5ab4` (umbrella), `id:15e9` (relay-awareness), `id:15d5` (REVIEW_ME→C3), `id:7b23` (unified-skill question).

## Agenda
1. Is there an intended meeting→TODO→ROADMAP→executor pipeline, and where does a design become executor-ready?
2. Mutual boundaries between the executor contract and /meeting.
3. /meeting no-arg relay-awareness + REVIEW_ME wiring (reframed by user as the core risk).
4. Reverse direction (relay picks up meeting/manual edits), worktree collisions, and build vs document.

## Discussion

**Item 1 — pipeline contract.** Topology: human/strong `/meeting` → TODO action items (`id:XXXX`); strong `/fables-turn handoff` → ROADMAP `[ROUTINE]`/`[HARD]`; cheap `/fables-executor` → works `[ROUTINE]`. The correlation plumbing exists (classify skips RELAY; orphan-scan unions ROADMAP), but the TODO→ROADMAP *transform* is implicit handoff-agent judgment. Riku named the failure: handoff/review mint a **fresh** id for work TODO already tracks → a duplicate orphan-scan can't catch (two ids look like two items). User pushed to check review + the no-arg pool, not just handoff — finding: `review.md` step 5 re-derives ROADMAP **and writes TODO.md** (summary count) and `relay-loop.js:436` tells review units to `append.sh new-ids` — **review is a second minting door**, no reuse instruction; the autonomous pool inherits both. Petra: a duplicate is undetectable while the two ids differ; the only mechanically-checkable invariant is the converse — once an id appears in both ledgers, its checkbox state must agree. Sage: that slots into `orphan-scan.sh` (already `cat`s the union) as a new advisory class, no new flock.

**Item 2 — boundaries.** Executor rule 3 already routes spec ambiguity to BLOCKED but never names `/meeting`; the real audience for a guard sentence is a *human wearing the executor hat*. Reverse direction already clean (classify skips RELAY lines). User chose to rely on rule 3 — no new executor text — and to protect the "meeting writes ledger-neutral items, relay owns HARD/ROUTINE difficulty" division.

**Item 3 — relay-awareness (the core).** `classify.sh` has **zero `[HARD]` awareness**; `[HARD]` is used informally in TODO titles (`id:15e9`, `id:6a3c`) to mean "strong-model design task", so such an item could be bucketed C1 → implemented inline on a weak/post-plan session. Riku flagged that `id:5ab4`'s own gate (≥2 relay turns of friction data) is unmet (only the 2026-06-12 pilot ran) — so design now, conservatively. User's four refinements: nudge target is **`/fables-turn review <current_repo>`** (bare `review` defaults to `--all`); relay *actions* only when a strong model is in play/switchable/Agent-runnable (user runs `/opusplan` → Opus in plan mode, Sonnet after) so the nudge **surfaces only**, no inline run; ALL relay-aware behavior is **gated on relay-detection** so non-relay repos are byte-for-byte unaffected; and `/meeting` should **write back** to TODO/ROADMAP/REVIEW_ME like a review/manual turn.

**Item 4 — reverse direction + worktree.** Relay review/handoff children edit the ledgers in worktrees and `--no-ff` merge them; `/meeting` edits the same files in the main tree; none are `merge=union` (checkbox toggles can't union) → concurrent meeting + pool can conflict at integration (git-surfaced, not silent; keep writes line-scoped via flock'd `md-merge.py`; D2 advisory catches residual drift; `RELAY_LOG.md` stays union). User added the symmetric obligations: the relay must **detect unqualified meeting/manual ledger items** (no `[ROUTINE]`/`[HARD]`, no acceptance/tests) and have the strong model qualify+size them (mini-handoff); and a relay-repo C1 dispatch should **follow the executor contract** ("C1s work as if picked by /fables-executor" — natural since the post-plan tier is Sonnet). Finally: before modifying the skills much, analyze common ground and consider extracting parts of /meeting into a **Workflow** — deferred to its own session. Closing dogfood (D9): seed the backlog **ledger-neutral** — safe because executors only touch promoted ROADMAP `[ROUTINE]` items, so un-promoted TODO items are out of scope, and they become D6's first real input.

## Decisions
- **D1 — single-id-two-views.** TODO/meeting is the design ledger ("why"); ROADMAP is the execution queue ("now"). Promotion (handoff C2 + review step 5) **reuses** the existing TODO id; mint new only for newly-discovered work. *Out of scope:* any auto-sync engine.
- **D2 — cross-ledger guard.** `orphan-scan.sh` gains an advisory: any `id:XXXX` present in **both** TODO.md and ROADMAP.md with disagreeing checkbox state is flagged. Plus a reuse-id instruction in `handoff.md` C2, `review.md` step 5, and the `relay-loop.js` review-unit prompt. *Out of scope:* making TODO.md `merge=union`.
- **D3 — no executor-contract text.** Rely on rule 3; document only the "meeting writes ledger-neutral items, relay owns HARD/ROUTINE" division on the meeting side. No contract `vN` bump.
- **D4 — classifier relay-awareness (lands on `id:15e9`).** `classify.sh` floors `[HARD]`/review-tagged TODO items at Class 3 (never C1/C2 inline). Relay-detection-gated nudge to **`/fables-turn review <repo>`** when ROADMAP has open `[ROUTINE]` items — **surface-only**, no inline run on the post-plan weak tier. *Out of scope now:* inline dispatch / auto-model-switch / strong-Agent-spawn (friction-gated under `id:5ab4`).
- **D5 — REVIEW_ME wiring + write-back (lands on `id:15d5`).** `/meeting` reads open REVIEW_ME boxes (`@manual` BDD + judgment calls) as Class 3 candidates and writes back to TODO/ROADMAP/REVIEW_ME consistently (D2 invariant, same id, flock'd `md-merge.py`). *Out of scope:* roadmap re-derivation / test-integrity audit (review's strong-model job).
- **D6 — reverse-handoff.** `/fables-turn review` + `handoff` detect ledger items added by `/meeting` or manual edits lacking `[ROUTINE]`/`[HARD]` qualifiers (or acceptance/tests) and have the strong model qualify+size them (mini-handoff).
- **D7 — C1 ≈ executor.** In a relay-managed repo, a no-arg `/meeting` C1 dispatch follows the executor contract (no test gaming, full suite green, RELAY_LOG append, checkpoint).
- **D8 — Workflow-extraction analysis (deferred).** Analyze common ground across /meeting end-of-meeting bookkeeping, executor work-discipline, and review write-back; consider extracting parts of /meeting into a Workflow. Separate session; relates `id:7b23`. Gate: this design landed + D1–D7 built (real common ground to factor).
- **D9 — this session is design-only.** Seed build items into TODO.md ledger-neutral (id-tagged, this-note-cited, acceptance-shaped, no `[ROUTINE]`/`[HARD]`). No skill code touched.
- **Cross-cutting:** ALL relay-aware `/meeting` behavior is gated on relay-detection (ROADMAP marker / `## Relay contract` pointer in CLAUDE.md / relay.toml entry); non-relay repos are unaffected.

## Action items
Build ordering (cheap→large): D2-guard → D4 (id:15e9) → D5 (id:15d5) → D6 → D7 → D8.
- [ ] D1/D2 — reuse-id instruction in `handoff.md` C2 + `review.md` step 5 + `relay-loop.js` review prompt; add cross-ledger checkbox-consistency advisory to `orphan-scan.sh`; document the shared non-union-ledger collision in relay guardrails + CLAUDE.md conventions. Contract: an id in both TODO+ROADMAP with disagreeing checkbox state is flagged; reuse-id text present in all three relay spots. <!-- id:38df -->
- [ ] D4 — `classify.sh` floors `[HARD]`/review TODO items at C3; relay-detection-gated surface-only nudge to `/fables-turn review <repo>`. Updates `id:15e9`. Contract: a `[HARD]`-tagged TODO item never classifies C1/C2; nudge names the current repo; no behavior change in a non-relay repo. <!-- id:15e9 -->
- [ ] D5 — `/meeting` reads open REVIEW_ME boxes as C3 candidates + D2-invariant write-back to TODO/ROADMAP/REVIEW_ME. Updates `id:15d5`. <!-- id:15d5 -->
- [ ] D6 — relay `review`+`handoff` qualify+size unqualified meeting/manual ledger items (mini-handoff, strong model). Contract: an unqualified new TODO/ROADMAP item gets `[ROUTINE]`/`[HARD]` + acceptance on the next strong turn. <!-- id:7c23 -->
- [ ] D7 — relay-repo no-arg `/meeting` C1 dispatch follows the executor contract (test integrity, full suite green, RELAY_LOG, checkpoint). <!-- id:a21b -->
- [ ] D8 (deferred; gated on D1–D7 landing; relates `id:7b23`) — analyze common ground across /meeting end-steps, executor discipline, review write-back; consider extracting parts of /meeting into a Workflow. Separate session. <!-- id:6ba4 -->
