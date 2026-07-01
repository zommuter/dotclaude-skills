# 2026-07-01 — a0b6 step (b): relay-loop.js engine swap to the deterministic classifier

**Started:** 2026-07-01 19:04
**Session:** 47bb595f-f8f4-4512-a807-7ac84d0a9ddb
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration)
**Topic:** How to swap the LLM discovery shard for the deterministic `classify-verdict` as `relay-loop.js`'s primary verdict source — the sole remaining work before the id:4d8e classifier flip.

## Surfaced discoveries
- [[relay-classifier-flip-prereqs-5eb3-5ac6]] — case-b split (5eb3: promote→handoff / surface-only→human); INTENSIVE is a flag+invariant, not a verdict.
- [[relay-mechanical-classifier-4d8e]] — the umbrella: discovery → deterministic `classify-verdict.sh` REPLACES the LLM shard (shard only on AMBIGUOUS); two narrow LLM surfaces; `relay-loop.js` is a Workflow script (no npm imports → reuse `pipeline()`).

## Grounding (what step (a) already delivered)
- Commit `2aade46`: `classify-verdict.sh` reaches **verdict parity** — rank-0 `blocked` for dirty/diverged (id:e424); lock-only-unaudited subsumed by `substantive_unaudited`. `classify-repo.sh` (id:3f0f) assembles gather→derive→fold-unpromoted→classify end-to-end, **side-effect-free**.
- C3 (historical backtest 0 candidate-worse/762) + C4 (forward-shadow) gates satisfied (id:9d2b).
- The authority model was ratified pre-flip in DP1 (meeting 2026-06-30-1523): **Replace** — classifier primary, shard fires only on `AMBIGUOUS`, no post-flip comparator.

**Decisive constraint (raised at open):** `relay-loop.js` is a Workflow script (sandbox: no `require`/`fs`/subprocess). It cannot run bash itself — every git/script execution goes through an `agent()` call. So "delete the shard" reframes to "replace the *judgment* shard with a *mechanical runner* agent" that runs scripts and relays JSON verbatim.

## Agenda
1. Reconciliation-action ownership (the side-effecting git ops the side-effect-free classifier can't hold).
2. Fate of the four JS-side backstops (id:000d/9973/ad74/365b).
3. Cutover safety given the 3× template-literal-lint pool crashes.
4. Scope fence + children to mint.

## Discussion

### A1 — Reconciliation-action ownership
🏗️ Archie: the shard (`relay-loop.js:820-893`) does three separable jobs — (1) verdict (now `classify-repo.sh`); (2) per-unit fields (all in the gather JSON classify-repo passes through — free); (3) side-effecting git reconciliation (behind-origin ff-merge + re-gather, stale-worktree reap, orphan-park, id:bae5 in-place uv.lock commit). (3) can never live in a side-effect-free classifier → a new `reconcile-repo.sh` + a thin runner agent (`reconcile-repo.sh` → `classify-repo.sh` per repo, zero judgment).
😈 Riku: the orphan reap-vs-park decision (`merge-base --is-ancestor`) is where a regression force-removes unmerged work — transcribing battle-tested prose into a script is exactly where the hazard hides → needs its OWN RED test seeded from the real id:689c/3ac8/1f53 fixtures, not just "classifier tests pass."
🎛️ Orla: this is the thin-glue lever (id:0d31) — today's ~4KB reasoning prompt is the ~46% cache_read sink; a runner whose recipe is "run these scripts, return JSON verbatim" collapses token cost AND kills the judgment surface (the id:612f `find`-over-$HOME failure mode dies).
✂️ Petra: N=2 on a standalone `reconcile-repo.sh` is really N=1 (only the runner calls it). Counter: keep the git recipe as bounded prompt-prose, only `classify-repo.sh` a script.
🏗️ Archie / 😈 Riku: prose-in-a-prompt is precisely what we're escaping — non-deterministic, untestable. The abstraction's value here is **testability of the dangerous git ops**, not reuse — that tips it to a script even at N=1½. The real split is **side-effect-free (classify-repo, the pure tested island) vs side-effecting (reconcile-repo, the dangerous tested island)**; the agent is pure transport between them. Keep them **two** scripts (fusing loses classify-repo's isolated hermeticity). Reuse the id:612f NO-FILESYSTEM-HUNTING guard verbatim so the runner can't improvise.

### A2 — Fate of the four JS-side backstops
😈 Riku (per-guard, not hand-wave): **id:000d** finished-demote guards `is_finished ∧ surface>0` — a DIFFERENT axis than classify-verdict's `unpromoted`-based idle predicate (that state routes to `human`, not idle) → NOT provably redundant. **id:9973** hard-pool-demote — classify-verdict emits `hard` only when `open_hard_pool≥1`, so it's a no-op for classifier verdicts BUT still guards a bogus `hard` from the AMBIGUOUS→LLM path. **id:ad74** INTENSIVE-promote (idle→execute) is loop-level and only matters for the LLM path (classifier idle units have `intensive=""` by invariant). **id:365b** circuit breaker is pure cross-round loop state — the per-repo per-round classifier *cannot* implement it → non-negotiable keep.
✂️ Petra: honest tally — none is fully subsumed *while the LLM/AMBIGUOUS path exists*. Constraint-archaeology: the constraint (a fallible verdict emitter) hasn't lapsed, it's SHRUNK to the AMBIGUOUS path. Keep all four.
🎛️ Orla: deleting cheap correctness guards in the SAME session we swap the verdict source is reckless — they're the belt to the classifier's suspenders if the runner has a bug.
😈 Riku (forward-flag): once the AMBIGUOUS path is *proven* constrained, 000d/9973/ad74 become truly vestigial and a future item deletes them. Don't gold-plate now.

### A3 — Cutover safety
🏗️ Archie: the edit is confined to the prompt-and-agent-call region (`:820-900`); the whole downstream merge/backstop consumer (`:906-1063`) + `SHARD_SCHEMA` are untouched — that confinement is the key safety property.
😈 Riku: the 3× crashes were the template-literal-lint hazard (backtick/`${}` in the giant template string). `test_workflow_template_lint.sh` MUST gate this; the new runner prompt is smaller (fewer git snippets) which helps. Old `shardPrompt` must be **deleted, not commented** (a commented 70-line template is still a lint liability + rots; git history is the archive).
🎛️ Orla / ✂️ Petra: DP1 already ratified "no post-flip comparator." A fallback *flag* isn't a comparator but a dual-path engine doubles the crash surface and keeps the exact lint liability alive; "temporary" fallbacks never get deleted. The C3/C4 gates already did the de-risking a flag would provide → **hard swap**, rollback = `git revert` of the focused commit.
😈 Riku (acceptance smoke, not a comparator): one `/relay --once` on the drained portfolio — 0 crashes, byte-compatible discovery object, verdicts match the historical backtest expectation — before ticking the box.

### A4 — Scope fence + children
✂️ Petra: IN — the confined engine swap + `reconcile-repo.sh` + tests. OUT (separate parked children) — b444 lane-triage broker, inotify (0ee6), continuous dispatch (80b8), unpromoted-scan promote/surface semantics.
🏗️ Archie: decompose like step (a)'s e424 — `reconcile-repo.sh` is a separable hermetically-testable [ROUTINE] executor task; the `relay-loop.js` edit is the gated [HARD — pool] remainder (reuse id:a0b6).
😈 Riku: the engine swap is **gated on `reconcile-repo.sh` green** (else the runner has nothing to call) — encode it as an explicit acceptance gate so classify-verdict's own EXECUTABLE-HARD test (id:2d20) won't dispatch it prematurely (dogfooding our own gate).

## Decisions
- **A1 — reconcile home:** NEW tested `relay/scripts/reconcile-repo.sh` holds the bounded side-effecting git ops (behind-origin ff-merge + re-gather, stale-worktree reap, orphan-park, id:bae5 in-place uv.lock commit). Runner agent = pure transport: `reconcile-repo.sh` → `classify-repo.sh` per repo, returns the existing `SHARD_SCHEMA` `{units,surfaced,skipped}`, forbidden any other git/fs (id:612f guard verbatim). Two scripts, not fused. *Out of scope:* moving any reconciliation into the side-effect-free classifier.
- **A2 — backstops:** keep ALL FOUR (000d/9973/ad74/365b) unchanged this session; 365b is irreplaceable cross-round loop state, the other three still guard the residual AMBIGUOUS→LLM path. Mint a tracked deletion child gated on the AMBIGUOUS path being constrained/proven. *Out of scope:* deleting any backstop now.
- **A3 — cutover:** HARD swap, no runtime fallback flag (rollback = `git revert` of the focused commit). Old `shardPrompt` DELETED not commented. Edit confined to `:820-900`; merge/backstop/`SHARD_SCHEMA` untouched. Landing order (DoD): (1) extend `test_workflow_template_lint.sh`; (2) `reconcile-repo.sh` + RED test seeded from real fixtures; (3) structure test pinning runner→same `SHARD_SCHEMA`; (4) confined engine edit deleting old prompt; (5) `make test` green + a0b6 box ticked; (6) one `/relay --once` smoke run as acceptance. *Out of scope:* a comparator/observation window (C3/C4 already satisfied).
- **A4 — decomposition:** `reconcile-repo.sh` = new [ROUTINE] id:5987; a0b6 remainder = [HARD — pool] `relay-loop.js` swap, gated on 5987 green; backstop-deletion = [HARD — decision gate] id:b50e (not dispatchable now). *Out of scope:* b444 / 0ee6 / 80b8 / unpromoted-scan semantics.

## Action items
- [ ] `relay/scripts/reconcile-repo.sh` [ROUTINE] — bounded side-effecting git ops transcribed from `relay-loop.js:854-870` (sync/worktree/orphan guards); deterministic reap-vs-park (`merge-base --is-ancestor`). Test `tests/test_reconcile_repo.sh` (`# roadmap:5987`) hermetic mktemp fixtures seeded from real id:689c/3ac8/1f53/c3f7/bae5 states. Contract: side effects only via the named bounded git ops; RED until it lands. (session 2026-07-01-1904) <!-- id:5987 -->
- [ ] a0b6 remainder [HARD — pool] — the confined `relay-loop.js:820-900` swap: replace `shardPrompt`+`agent(shardPrompt(chunk),…)` with a runner-agent prompt (per repo: `reconcile-repo.sh` then `classify-repo.sh`; return `SHARD_SCHEMA`). DELETE the old prompt. Gated on id:5987 green. Tests: extended `test_workflow_template_lint.sh` + new `test_relay_runner_swap.sh` (structure: runner→same schema the merge code reads). Acceptance: `make test` green + box ticked + one `/relay --once` smoke run (0 crashes, byte-compatible discovery). (session 2026-07-01-1904) <!-- id:a0b6 -->
- [ ] Delete the id:000d/9973/ad74 JS backstops [HARD — decision gate] — GATED: not dispatchable until the AMBIGUOUS→LLM path is proven constrained (then these three become vestigial; 365b stays). (session 2026-07-01-1904) <!-- id:b50e -->
