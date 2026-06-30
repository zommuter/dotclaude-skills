# 2026-06-30 — Revamp relay-loop discovery as a mechanical TDD classifier (id:4d8e)

**Started:** 2026-06-30 15:23
**Session:** 72f080b3-609b-4f19-830e-15188605a2ff
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (relay-orchestration), 🔎 Dex (grammar/diagnostic-severity determinism)
**Topic:** Move relay discovery off LLM judgment onto a deterministic verdict classifier with RED-test fixtures; the LLM becomes a last-resort loud-fail resolution layer. Direction was user-decided in the PREP brief; this meeting decided the HOW.

Brief: `docs/meeting-notes/2026-06-30-1514-relay-loop-mechanical-revamp-PREP.md`
Umbrella id:4d8e; siblings id:b444 (broker human-decision channel), id:80b8 (continuous dispatch), id:0ee6 (inotify wake).

## Surfaced state (grounding)
- `gather-repo-state.sh` (id:11ad) already deterministically computes most verdict-driving fields: `is_finished`, `top_intensive`, `substantive_unaudited`, `open_hard_pool`, `lock_only_unaudited`, roadmap presence/emptiness.
- `relay-loop.js:397–429` already runs JS-side **backstops** that OVERRIDE the shard verdict from those deterministic fields (finished-repo correction, INTENSIVE promote, hard-demote when no open pool lane).
- So a deterministic classifier is ~80% already built — scattered across a bash gatherer + JS overrides + an LLM shard that still owns the *primary* verdict. The 8 failures are all "the LLM shard (or a guard) trusted a state the deterministic layer would have caught."
- `relay-loop.js` is a **Workflow script** (sandbox: no `require`/`import`, no fs, no `Date.now()`) — decisive for DP6.

## Agenda
1. Classifier I/O contract + carve-out vs replace (DP1)
2. The ≤5% LLM boundary — what is irreducibly LLM (DP2)
3. RED-test harness shape (DP3)
4. Loud-failure resolution routing + sibling b444 broker home (DP4)
5. inotify (id:0ee6) composition with sig-cache + two-dry exit (DP5)
6. Continuous dispatch (id:80b8) interaction with the classifier (DP6)
7. Migration/cutover order + children to mint (DP7)

## Discussion

### DP1 — classifier I/O contract + carve-out vs replace
🏗️ Archie: one tested `classify-verdict.sh`, pure fn of gather-repo-state JSON → `{verdict, reason, evidence[], ambiguous}`; verdict ∈ {execute, review, hard, handoff, human, idle, AMBIGUOUS}; `evidence` = `{field,value,source}` pointers so RED tests assert on reason, not just label.
🔎 Dex: `AMBIGUOUS` is the ONLY legal exit to the LLM; everything else is a definite verdict OR a loud ERROR (severity). Tag/prose disagreement (case c) = ERROR/lint-fail that halts+surfaces, never a guess. No swallowed warnings (the g/h anti-pattern).
😈 Riku: the real fork is AUTHORITY — (A) Replace: classifier primary, shard fires only on AMBIGUOUS; (B) classifier-primary + shard audits every round. (B) re-introduces the cost AND the trust-a-state failure. Push (A).
🎛️ Orla: shard = biggest token sink (~1.9M cache_read/shard, ~46% cost, turn-count-driven). (A) makes the changed-common-case mechanical = 0 LLM tokens for drained+unchanged repos.
✂️ Petra: N=2 OK (loop + RED harness). OUT OF SCOPE: redesigning unpromoted-scan promote/surface label semantics (case h secondary) — separate child; the classifier merely consumes scan output.

### DP2 — the ≤5% LLM boundary
🔎 Dex: 7 of 8 cases are mechanical or loud-ERROR — (a) anchor to the item's own lane bracket; (b) drained = no executor-actionable open item + run scan; (c) tag/prose disagree = ERROR halt; (d) INTENSIVE free-typed = lint reject; (e) cohort-detect identical diffs; (f) clean-tree reap check; (h) finished = 0-open ROADMAP AND scan reports no promote/surface.
😈 Riku: case (g) is the one irreducible — per surfaced untagged item, "ROUTINE-ready vs [HARD — meeting] vs [HARD — pool] vs human-only" is an LLM judgment. BUT it is NOT part of computing the verdict: classifier emits a definite `handoff` + "N items need triage"; triage is a downstream RESOLUTION step.
🏗️ Archie: two distinct LLM surfaces — (1) verdict-level AMBIGUOUS (rare); (2) resolution-level lane-triage (verdict definite, executing it needs lane assignment, where b444 plugs in). Do not conflate.
🎛️ Orla: today's loop fuzzes verdict-pick and "nothing to promote" into one LLM breath → that's how g silently no-op'd. Splitting makes the verdict carry the unresolved-work obligation, so detection can't be wasted.

### DP3 — RED-test harness shape
🏗️ Archie: the 8 cases span 4 layers — gatherer (a/b/h), classifier (fields→verdict), lint (c/d), loop-orchestration (e/f/g). Two-tier harness: (1) pure-unit JSON→verdict; (2) integration mktemp-repo run gather→classify e2e for the gatherer cases.
🔎 Dex: lint cases assert exit-code + stderr severity, NOT a verdict label — mixing assert-verdict with assert-loud-fail is itself a swallowed-warning regression.
😈 Riku: each fixture seeded from the ACTUAL 2026-06-30 ledger state (truncocraft/zelegator/it-infra/ai-codebench) — a hand-written-to-pass fixture is worthless; transcribed-from-real-failure is a regression test.
🎛️ Orla: e/f/g are loop-level, a different substrate — don't block the classifier ship on them.

### DP4 — loud-failure resolution routing + b444 home
🎛️ Orla: resolution LADDER — (i) inline lane-triage LLM resolves most untagged items; (ii) only genuinely-human decisions go async. The pool can't `AskUserQuestion`, so blocking is impossible anyway.
😈 Riku: "ONE home" is not 3 competitors — record-and-defer is the durable SUBSTRATE, the broker is an optional live TRANSPORT, ping-threshold is the surfacing TRIGGER. One mechanism, three layers.
🏗️ Archie: interface = loop appends `{repo,kind,question,options[],evidence[],requested_at,id}` to a durable queue and keeps working; transport-agnostic.
😈 Riku: inline triage must be CONSERVATIVE — low confidence → write a human decision-request, never guess a lane (matches the user's reversible-by-default profile).

### DP5 — inotify (id:0ee6)
😈 Riku: constraint archaeology — 0ee6's original justification ("dry re-discovery re-shards every repo = wasted CLASSIFIER work") DISSOLVES once DP1 makes the classifier mechanical (dry re-discovery = near-zero-token bash). Residual value is only "don't spin the loop on a /loop cadence over a drained backlog" — a wakeup concern, not a token concern.
🏗️ Archie: inotify REPLACES the polling, not the two-dry exit (which stays the correctness condition).
🔎 Dex: if built, fail-safe toward re-checking (overflow/doubt → poll, never sleep-through) — over-waking is just a cheap re-scan now.
✂️ Petra: GATE behind the classifier, de-prioritize. In-session only (not outage survival — that's id:98f0, [[babysitter-durable-cron-no-op]]).

### DP6 — continuous dispatch (id:80b8)
🎛️ Orla: the mechanical classifier is the ENABLER — a per-repo pure fn lets a streaming picker re-classify one freed repo for ~zero cost.
**GROUNDING FINDING:** `relay-loop.js` is a Workflow script in a sandbox with **no module imports** → npm job-queue libs (p-queue/bullmq/piscina/better-queue) are ALL unusable. The "wheel to reuse" is the harness's own **`pipeline()`** primitive (the no-barrier model the PREP cited). Current loop uses `parallel()` = a barrier (`relay-loop.js:1685`, `:1715` comment); serialized integrator already exists = per-repo `integrationChains` Map (`:1719`).
😈 Riku caveat: `pipeline(items,…)` takes a FIXED ≤4096 array → no-barrier-within-batch, not true mid-flight refill. Realistic shape: each macro-iteration discover ALL ready units (cheap) → sort by D3 rank → feed `pipeline()`. Captures ~the whole payoff. True mid-flight refill = thin follow-on.
🎛️ Orla: HARD property — the classifier must be SIDE-EFFECT-FREE (never mutates ledgers / claims leases / dispatches); a picker calling it 50×/round must be effect-free.

### DP7 — cutover order + children
🏗️ Archie: build order is dependency-forced: classifier + fixtures → wire → lint → decision-queue → siblings.
😈 Riku: the risky step is flipping AUTHORITY; the 8 fixtures cover known failures, not unknown states.
USER REVISION: validation moves PRE-flip via **backtesting** the overhaul against past discoveries — "backtesting preferred to directly judge and flip; that's a point of the whole TDD approach." Flip only if no issues.
**Backtest feasibility (verified this session):** past DISPATCH verdicts ARE logged in `~/.config/relay/relay-events.jsonl` as `{ts,runId,repo,mode=verdict,tier,round}`; ledger inputs are git-recoverable via `git show <commit-near-T>:`. LIMITS: only dispatched verdicts logged (`idle`/skip under-sampled); ephemeral state (live worktrees/claims/dirty tree) NOT git-recoverable; shard `reason` not logged (compare LABELS only). ⇒ backtest is PARTIAL — faithful for verdicts that are pure fns of git-tracked ledger content; the forward-10 covers the ephemeral + idle gap.
✂️ Petra: this REPLACES a post-flip comparator — validation is entirely pre-flip; once flipped the shard is AMBIGUOUS-only with zero standing cost. The backtest harness becomes a permanent `make test` regression artifact.

## Decisions

- **DP1 — Replace (classifier-primary).** `classify-verdict.sh` is THE primary verdict source; the LLM shard fires ONLY on `AMBIGUOUS`; the general "classify this repo" shard prompt is deleted. The classifier is a **pure function** of `gather-repo-state.sh` JSON (+ `unpromoted-scan`/`gather-human-backlog` output passed in); orchestration (gather→scan→classify) lives in a thin wrapper. Contract: `{verdict, reason, evidence[], ambiguous}`, verdict ∈ {execute, review, hard, handoff, human, idle, AMBIGUOUS}. *Out of scope:* unpromoted-scan label-semantics redesign (separate child cb9b).
- **DP2 — Two narrow LLM surfaces ONLY.** (1) verdict-level `AMBIGUOUS` (rare; reserved for tag/prose cases we choose not to hard-halt); (2) resolution-level lane-triage of untagged surfaced items (case g), a FORCED downstream step never part of verdict computation. The classifier ALWAYS emits a definite verdict. Each lane-triage resolution feeds back as a new mechanical rule/fixture, shrinking surface (2). This boundary IS the contract: new discovery LLM calls must justify against these two surfaces. *Out of scope:* any third LLM surface.
- **DP3 — Two-tier, real-seeded harness, split scope.** Pure-unit (JSON→verdict) + integration (mktemp-repo gather→classify e2e), fixtures seeded from the REAL 2026-06-30 ledger states. Lint cases assert exit-code+stderr severity, not verdicts. Each fixture `# roadmap:XXXX` → EXPECTED-RED until ticked. New helper `assert_verdict`/`assert_loud_fail`. **Cases a/b/c/d/h = umbrella definition-of-done; e/f/g = follow-on children with their own substrate.** *Out of scope:* a combinatorial fixture matrix.
- **DP4 — Durable decision-queue is the "one home"; b444 transport deferred.** Resolution ladder (inline conservative LLM lane-triage → durable file-backed decision-request queue). The durable queue is the substrate; the broker (b444) is an optional live transport; ping-threshold is the surfacing trigger — layers, not competitors. IN SCOPE: the decision-request **record format** + the **write at the forced-resolution point** (so g/h obligations are persisted, never swallowed). *Out of scope → b444's own meeting:* transport (weigh broker vs **FIFO/named-pipe/append-file** per user note), auth, consume side, standalone/headless mode.
- **DP5 — inotify = gated, de-prioritized efficiency layer.** Replaces the sleep-poll, NOT the two-dry exit (which stays the correctness condition). Watch-set derives from `discover-sig.sh`'s input superset + the b444 decision-queue watchfile. Fail-safe toward re-checking. **GATED behind the classifier; decide if the inotifywait dep is worth it only after.** `git status` (incl. worktree heads) is the dominant change signal — already hashed by discover-sig — so it works with or without inotify. In-session only (not outage survival). *Out of scope:* outage resilience (id:98f0).
- **DP6 — Continuous dispatch reuses harness `pipeline()` + existing `integrationChains`.** npm job-queue libs are ruled out by the Workflow sandbox (recorded finding). Switch the dispatch wave from `parallel()` (barrier) to `pipeline()` (no-barrier); each macro-iteration does a cheap re-discovery of all ready units, sorted by D3 priority-class rank. Serialized integrator = existing chains; per-repo lease = id:0902; D3 order = pre-sort; stop/quota/two-dry = macro-iteration boundary checks. **Fairness/starvation is the only genuinely new design.** True mid-flight refill (raw Promise.race picker) = thin follow-on, gated on measurement. The classifier MUST be per-repo-callable, cheap, carry the D3 rank, and be **side-effect-free**. *Out of scope:* importing any external concurrency library.
- **DP7 — Pre-flip validation gate (backtest + forward-10), then flip.** Order: classifier + fixtures (a/b/c/d/h) → backtest harness → forward-10 shadow → flip → lint c/d → decision-queue write → siblings. (1) Backtest harness replays `classify-verdict.sh` over git-reconstructed past ledger states vs logged `relay-events.jsonl` dispatch verdicts; triage EVERY disagreement before flipping (script-bug → fix; shard-was-right → new RED fixture). (2) Run the shard for ~10 forward discoveries as shadow (dispatch on shard) to cover ephemeral-input + idle/skip verdicts the backtest can't recover. (3) Clean backtest AND clean forward-10 → flip (classify-verdict primary, shard → AMBIGUOUS-only). **No post-flip comparator** — validation is entirely pre-flip; flipped end-state has zero standing shard cost. The backtest harness is a permanent `make test` artifact. *Out of scope:* a standing post-flip sampled comparator or session-gated health-check (superseded by the pre-flip gate).

## Action items

Children of umbrella id:4d8e (ordered; cite this note):

- [ ] **C1 — `classify-verdict.sh` contract + pure-fn impl** — side-effect-free, carries the D3 priority-class rank, `gather-repo-state` JSON in → `{verdict,reason,evidence[],ambiguous}` out; orchestration in a thin wrapper. Contract test: hermetic JSON-in/verdict-out. <!-- id:85df -->
- [ ] **C2 — RED harness + fixtures a/b/c/d/h** (two-tier, seeded from the REAL 2026-06-30 ledgers) + `assert_verdict`/`assert_loud_fail` helper; each fixture `# roadmap:` (EXPECTED-RED). = umbrella definition-of-done. <!-- id:ccd9 -->
- [ ] **C3 — Backtest harness** — replay classify-verdict over git-reconstructed past ledger states vs logged `relay-events.jsonl` dispatch verdicts; triage disagreements (→ fix or new RED fixture); permanent `make test` regression artifact. PRE-flip gate. <!-- id:5f93 -->
- [ ] **C4 — Forward-10 shadow run** — shard for ~10 forward discoveries alongside the built script (dispatch on shard), compare; covers ephemeral-input + idle/skip verdicts the backtest can't recover. PRE-flip gate. <!-- id:9d2b -->
- [ ] **C5 — Flip authority** (gated on clean C3 AND clean C4): classify-verdict PRIMARY + dispatches; shard → AMBIGUOUS-only; delete the general shard prompt; no post-flip comparator. <!-- id:a0b6 -->
- [ ] **C6 — Lint cases c/d as loud ERRORs** (extend `roadmap-lint.sh`): tag/prose disagreement halts+surfaces; INTENSIVE must be derivable, not free-typed. <!-- id:297b -->
- [ ] **C7 — Durable decision-request queue**: record format `{repo,kind,question,options[],evidence[],requested_at,id}` + the forced-resolution write (g/h never silently no-op) + conservative inline lane-triage sub-agent (low-confidence → enqueue, never guess a lane). <!-- id:de31 -->

Follow-on children (NOT umbrella DoD; own substrate, sequenced after the classifier):

- [ ] **(e) Cohort-detect near-identical diffs → one verification** — hash the diffs so N plugins sharing one mechanical fan-out commit emit one `review`, not N. <!-- id:984d -->
- [ ] **(f) Clean-tree handback reap check** — mechanical auto-reap on a clean handback worktree (case f). <!-- id:3554 -->
- [ ] **(g) Loop-side forced-resolution orchestration** — wire the classifier's `handoff + "N items need triage"` obligation to the inline-triage/decision-queue resolution so "N surface" can never be swallowed as "handoff complete". <!-- id:47f1 -->
- [ ] **unpromoted-scan promote/surface label-semantics tested contract** (case h secondary) — pin the promote/surface labelling (e.g. a `[meeting candidate]` → promote-to-ROADMAP-as-`[HARD — meeting]`) in a test. <!-- id:cb9b -->

Sibling design-decisions recorded in this meeting (existing ids updated in TODO):
- **id:80b8** — continuous dispatch: shape decided (reuse `pipeline()` + existing `integrationChains`; macro-iteration re-discovery sorted by D3 rank; fairness/starvation = the only new design). npm libs ruled out by the Workflow sandbox.
- **id:b444** — durable-queue transport: weigh broker vs FIFO/named-pipe/append-file; folds in [[hermes-deferral-contract]] + [[feedback-ping-threshold-anomalies]] (queue-depth-while-drained = PING trigger). Own meeting.
- **id:0ee6** — inotify: gated behind the classifier, de-prioritized; watch-set from discover-sig inputs + the b444 watchfile; git-status-incl-worktree-heads is the dominant signal.
