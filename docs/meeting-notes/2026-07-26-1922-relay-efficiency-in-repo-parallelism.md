# 2026-07-26 — Relay efficiency: in-repo parallelism, and the levers that aren't parallelism

**Started:** 2026-07-26 19:22
**Session:** 87eb963b-0310-4f06-af8e-bdd2e5933142
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration), 🔩 Gil (git plumbing / merge semantics)
**Topic:** Where the relay's throughput actually goes, whether in-repo parallelism is buyable, and what non-parallel levers dominate it.

**Mode note:** `/meeting --fabled`. Two Fable-5 subagents ran: one *direct* investigation spawned at the owner's explicit request (mid-meeting, feeding Item 3), and the standard `id:7e87` closing adversarial pass. Neither drove the meeting; both are advisory.

## Agenda

1. Is `enforceOneUnitPerRepo` still load-bearing? (in-repo review ∥ execute)
2. Multiple executors in one repo — what is actually left to build for `id:ebbe`?
3. Non-parallel efficiency levers.
4. Disposition.

## Discussion

### Prior art (the owner's "did I already file this?")

Yes, twice, and one half is already built:

- **`id:1f4f`** (TODO.md:63) — `[HARD — meeting]` "wave-based parallel-execute with inter-wave review". **This meeting is its design session.** Note the ROADMAP prose implies `1f4f` is a re-frame label on `ebbe`; it is not — it is its own item.
- **`id:ebbe`** (TODO.md:76) — `/relay . --parallel N`, pool `pipeline()` fan-out, `gated-on:0534`. Its two hard children are **built, tested, green**: `relay/scripts/disjoint-greenlight.sh` (`id:5367`) and `relay/scripts/drain-integrate.sh` (`id:2062`).
- **Review ∥ its follow-up executor** — not filed anywhere. The genuinely new question.

### Item 1 — is the one-unit-per-repo bar load-bearing?

🏗️ Archie: the bar is `relay-loop.js:920` `enforceOneUnitPerRepo()`, rationale verbatim *"an execute+review pair for one repo in one round collides on the non-union ROADMAP.md at integrate"* (`id:dc5b` C2). But `enqueueIntegration` (`relay-loop.js:796`) already gives every repo its own tail promise — the git-level race was dissolved independently. C2 guards something else.

🔩 Gil named it precisely: two same-repo units get sibling worktrees off the same base; both tick checkboxes (`executor-contract.md:88` permits exactly this). Merge #1 lands `--no-ff`; merge #2's base no longer matches and `ROADMAP.md` is not union-merged. Not a race — a **deterministic stale-base textual conflict**. C2 is load-bearing *given the current executor contract*.

🎛️ Orla: that contract is the one `id:2062` already replaces — one-writer-to-main, driver ticks. A unit that never touches `ROADMAP.md` cannot produce Gil's conflict, so the cheap dissolution does not require `id:2840`'s "state out of markdown".

😈 Riku, three objections: **(a)** review ≠ execute — a review *re-derives* the roadmap (wide diff), so one-writer does not cover review ∥ execute; a merge can be clean and semantically wrong. **(b)** `claim.sh` is mode-blind, so a 2nd same-repo executor is refused today — in-repo parallelism needs a lease story. **(c)** cross-repo parallelism already saturates the lanes whenever ≥2 repos have work, so in-repo only helps a *narrow* fleet — i.e. drain mode.

✂️ Petra scoped on (c): fleet mode gains nothing, drain mode (`--only <cwd>`) is where 100% of the win is. 🏗️ Archie derived the ordering rule from (a): **review is the barrier; executes fan out between barriers** — which is exactly the pattern the owner hand-drove on 2026-07-23 and filed as `1f4f`. 😈 Riku noted this *kills* the owner's specific framing: review and its follow-up executor are the one pair that must stay serial, since the review's output is the executor's input.

😈 Riku's minimum-evidence challenge: has anyone counted whether open items are ever disjoint? Answer arrived in Item 2 — worse than a low rate.

### Item 2 — what is left for the fan-out

🏗️ Archie: `disjoint-greenlight.sh` is **fail-closed on empty sets**. A field-vocabulary scan of `ROADMAP.md` found 36×`Context`, 21×`Acceptance`, 8×`Tests`, 8×`RED spec`, and **0×`Files`/`Touches`/`Paths`** — read at the time as "the greenlight can never fire; `id:5367` is a correct function with no producer."

**The owner corrected this, and the correction stands:** the instrument was wrong. It asked for a *heading*, not for path-shaped *content*. `~/src/loderite/ROADMAP.md` carries a dense `**Anchors**` convention with explicit file:line references (`src/menu.ts:207`, `src/controls-core.ts:227-292`, `touch.ts:355-390`) alongside `**Tests**` naming exact files; and in this repo **37 of 39 open items** carry a path-shaped token inside `Context`/`Tests`/`Wiring`. The declared set exists as prose in a well-authored handoff — it is simply not a structured field. Layer A is therefore *extraction*, not *invention*.

🎛️ Orla split the remaining work: **Layer A** = a producer for the declared path set; **Layer B** = the engine's repo-as-primary-key assumptions, which are concrete:

- `relay-loop.js:1742` — `worktreePathFor = ~/.cache/relay/worktrees/${unit.repo}/${state.runId}-${unit.verdict}`. Two concurrent same-repo executes compute the **identical path**. A hard collision, not a race.
- `relay-loop.js:~2225` — `state.inFlight = state.inFlight.filter(r => r.repo !== unit.repo)` clears **every** same-repo entry; the first of two to finish clears both.
- `releaseLease(unit)` and the `claim.sh` key are repo-keyed.
- `enqueueIntegration(unit.repo, …)` is *correctly* repo-keyed and stays.

🔩 Gil: Layer B is cheap and hermetically testable; Layer A is a *prediction about a future diff*. `id:2062`'s `merge-check` catches under-declaration at merge (exit 1 + the intersecting paths, never auto-resolve), so the failure mode is a handback, not corruption — but fan-out's hit-rate is bounded by declaration quality.

### Item 3 — non-parallel levers (direct Fable pass, scrutinised)

The owner-requested Fable investigation surfaced levers neither the personas nor the facilitator had raised:

- **L1 — the integrator is still an LLM doing scripted work.** `relay-loop.js:2034`, `model: 'sonnet'`, a ~40-line prompt of deterministic steps (lease release → clean-tree gate → verify-isolation → sync-origin → `merge --no-ff` → version-bump → changelog-append → ckpt-tag → lock-push → worktree-retire → state-write), each already a tested script with enumerable exit codes. After `id:6176` mechanized quota/inject-take/heartbeat to `model:"bash"` hops, **this is the last big LLM agent doing deterministic work**, and it fires once per completed unit. The only genuine judgment is the semver "user-observable?" call. Mechanizing it also resolves the recorded contradiction that the bump step's prose says *"the REVIEWER's alone"* while running on a Sonnet integrate agent (`[[bump-changelog-reaches-one-of-three-paths]]`). 😈 Riku's caveat: this moves a failure from visible-and-recoverable to silent-and-corrupting (`id:25aa` class) — it needs loud-failure escalation.
- **L2 — only reviews rechain.** `relay-loop.js:2226`, comment verbatim: *"Only reviews chain — an execute never re-enqueues."* A repo with 5 open `[ROUTINE]` items therefore drains at ~1 per round, paying a full round barrier **and one STRONG_MODEL (Opus/Fable) review per Sonnet execute**. A bounded execute→execute rechain (K≤3) drains K items per round, serial in one lane, serially integrated — **no ROADMAP collision possible** — and cuts apex review spend by ~(K−1)/K.
- **L4 — the round tail is longer than stated.** After the lanes and integration drain comes the `[INTENSIVE]` serial run-alone phase (`relay-loop.js:2336+`), which serializes heavy units *and their integrations*; any round containing one idles every other lane for its duration.

😈 Riku surfaced the real tension: **L2 directly trades against D1.** D1 ratified review-as-barrier so a review audits each wave; L2 says review less often. ✂️ Petra resolved it by axis — D1 governs *ordering* (never concurrent), L2 governs *frequency* (executes per barrier). K=1 is today; K=3 is a wider wave. 🏗️ Archie: that makes L2 **strictly cheaper than fan-out** — same "drain K per review" benefit, no declaration requirement, no worktree collision, no lease change. Fan-out only adds concurrency *within* the wave.

**Corrected before adoption:** the direct pass recommended enabling the discovery-queue timer as a free win, citing `relay-loop.js:965` (*"ships installed but NOT auto-enabled"*). `systemctl --user is-enabled discover-repos-mechanical.timer` → **`enabled`**. It read a code comment as system state. Recorded, not adopted.

### Item 4 — disposition

🏗️ Archie established that `id:1f4f` is the `[HARD — meeting]` wave item and this meeting discharges its meeting lane, so the new work are its **children**, not parallel filings. 😈 Riku added the re-evaluation trigger for `ebbe`: if `cc90` delivers the drain win serially, concurrent fan-out's marginal value is only wall-clock — **`ebbe` may never be worth building**, and that should be written down so nobody builds it on momentum.

## Amendment session — `--fabled` closing pass (id:7e87)

One Fable-5 subagent, design-critique framing, fed a closing-time digest including the ratified decisions verbatim. Verdict: available; pass ran. Findings are advisory. Facilitator verified the load-bearing claim before relaying: `grep -c 'disjoint-greenlight\|drain-integrate' relay-loop.js` → **0**; `relay-burn.sh` exists.

**Owner accepted all four forced-amendment findings.** The ratified originals (D1–D4) stand as written; these are appended supersessions:

- **A1 (supersedes D1's disposition; finding F2)** — the disposition had **no child for the wiring D1's safety story depends on**. `drain-integrate.sh` and `disjoint-greenlight.sh` are unreferenced by the engine; the live path is still executors ticking `ROADMAP.md` in their own worktrees — the exact collision C2 prevents, now × N worktrees per wave. *"The plan ships every ingredient and no meal."* → new child `ae08`.
- **A2 (amends `cc90`; finding F1)** — D1's barrier and K≤3 are structurally compatible but D1 was ratified against a 1:1 review:execute ratio; `cc90` rewrites it to 1:K without stating what the eventual review reviews. Either units 1..K−1 never get a STRONG review (an unratified quality change) or the review audits a compound diff with undefined reject semantics. Additionally a chained execute is *dependent* on its predecessor — the opposite of what the greenlight certifies — so the wave silently becomes a DAG.
- **A3 (amends D2; finding F4)** — "re-key ALL collision sites" would break meeting↔pool exclusion: the repo-level lease is also what a parallel `/meeting` advisory claim collides against. Lease goes two-tier. Key shape ratified as **itemId × attempt** with a reconcile rule, since the open `id:1b1a` fail-open-append bug can produce two units with the same item id, and a bare nonce would orphan every pre-crash worktree from `id:7809`'s view.
- **A4 (amends `3ca7`; finding F6)** — L4 as ratified has non-intensive units co-running with an intensive unit, which is precisely what the serial run-alone tail (`id:8d52`/`5ac6`, exclusive resource claim) exists to prevent. D4d's re-key list named C2, the quota memo and MAX_UNITS but omitted the run-alone invariant.

**Hardenings folded into the children (no reopening):** `b099` — empty extraction is the *maximal* under-extraction, so empty ⇒ run-alone, plus a false-serialization metric (Context paths are often citations, not touches, so over-extraction would silently destroy the throughput win and D3's subset metric measures only under-extraction); `87f5` — pre-register the decision rule (per-phase attribution required, promote-if-share ≥ X%) and reconcile against the banked 47.6% discover baseline; `1f4f` — a **barrier timeout** tied to the `id:e149` heartbeat, because under waves one hung executor stalls the whole repo rather than one lane.

**Recorded, not adopted (F7):** crash-mid-wave reconcile must be designed *with* the D2 key shape rather than as an independent child; quota exhaustion mid-wave is undefined (the quota-cache stop was designed per-lane); and the `ebbe` retirement note conflates *depth* (cc90 reduces latency between dependent units) with *width* (fan-out buys throughput across independent ones) — one substitutes for the other only on a mostly-dependent queue, which nobody measured.

**Escalation trigger:** 4 forced-amendment findings; pre-registered threshold is ≥2. **The trigger has FIRED.** Recorded as standing evidence for the per-decision Fable pass and the full multi-pass (`id:8df5`); designing either is left to its own session (owner's call).

## Decisions

- **D1 — In-repo parallelism takes the WAVE MODEL, scoped to drain mode (`--only <cwd>`) only.** Review is a hard **barrier**: never concurrent with anything in its own repo. Between barriers, N executes may fan out, gated by `disjoint-greenlight.sh`. Fleet mode keeps `enforceOneUnitPerRepo` unchanged. **Out of scope:** the mode-blind lease *redesign* and `id:2840`'s state extraction — not needed under one-writer. **Explicitly rejected:** review ∥ its follow-up executor (the review's output is the executor's input). *Amended by A1 (disposition) and A3 (lease is two-tier, not redesigned away).*
- **D2 — Layer B: introduce a per-unit identity key and re-key the collision sites** — `worktreePathFor` (`:1742`), `state.inFlight` filtering (`:~2225`), lease acquisition. `enqueueIntegration` stays repo-keyed. This closes a latent bug that exists today independent of any fan-out decision. **Out of scope:** any change to integration serialization. *Amended by A3: lease two-tier (driver holds repo-level, units hold unit keys); key shape = itemId × attempt with an `id:7809` reconcile rule.*
- **D3 — Layer A: a mechanical extractor** pulls path-shaped tokens from an item's existing `**Anchors**`/`**Tests**`/`**Context**`/`**Wiring**` fields and feeds `disjoint-greenlight.sh`. **No new authored field for now.** Log how often the extracted set is a strict subset of the actual merged diff (`drain-integrate.sh`'s `merge-check` already computes the intersection); promote to an authored `**Touches**` field only if the miss rate justifies it. **Out of scope:** an LLM pre-pass predicting paths (adds an agent hop to the thing being made cheaper, and fails open). *Hardened: empty extraction ⇒ run-alone; add a false-serialization metric.*
- **D3a — greenlight is a throughput optimizer; the serialized integrator is the safety net.** Recorded explicitly so no future change relaxes integrate checks "because greenlight already proved disjointness".
- **D4 — Adopt four non-parallel levers, in order:** (a) **measure first** with `relay-burn.sh`, ranking recent runs, which orders the rest; (b) **L1** mechanize the integrator into one `integrate.sh` `relay-mech` hop, keeping a micro-hop only for the semver judgment, with loud-failure escalation; (c) **L2** bounded execute→execute rechain, depth counter K≤3 replacing the `rechained` boolean; (d) **L4** drained lanes pull rechain-eligible work during the `[INTENSIVE]` tail, re-keying round-scoped invariants to a window. **Out of scope:** re-plowing quota gating, discovery, and no-work churn — all already optimized (`id:6176`/`e9fa`, `id:4d8e`/`c3a6`/`c855`, `id:1432`/`365b`). *Amended by A2 (c) and A4 (d).*
- **D5 — `id:1f4f`'s meeting lane is discharged by this session.** The seven items below are its children. `ebbe` is gated on `ae08` and carries an explicit re-evaluation note: if `cc90` delivers the drain win, concurrent fan-out may never be worth building.

## Action items

- [ ] `[HARD — hands]` **87f5** — Measure: rank recent relay runs by burn with `relay/scripts/relay-burn.sh`; **pre-register the decision rule before running** (n runs, per-phase attribution required, promote-lever-if-share ≥ X%) and reconcile against the banked 47.6% discover baseline. Contract: a published per-phase ranking that orders `a955` and `3ca7`. (meeting `docs/meeting-notes/2026-07-26-1922-relay-efficiency-in-repo-parallelism.md`) <!-- children-of:1f4f --> <!-- id:87f5 -->
- [ ] `[ROUTINE]` **cc90** — L2 bounded execute→execute rechain: replace the `rechained` boolean (`relay-loop.js:~2233`) with a depth counter, K≤3. **Must pre-register (A2):** per-unit vs per-chain review scope, reject-unwind semantics at depth K, and whether a chained member re-enters the greenlight against the live wave set. Contract: a test proving a repo with 3 open `[ROUTINE]` items drains in one round with one review, and that depth >K stops chaining. (same note) <!-- children-of:1f4f --> <!-- id:cc90 -->
- [ ] `[ROUTINE]` **923b** — Layer B unit key: re-key `worktreePathFor` (`relay-loop.js:1742`) and the `state.inFlight` filter (`:~2225`) to a unit key of shape **itemId × attempt**; lease goes **two-tier** (driver holds the repo-level `claim.sh` lease, units hold unit keys) per A3; `enqueueIntegration` stays repo-keyed. Include an `id:7809` reconcile rule for N same-repo worktrees after a crash. Contract: a test proving two same-repo units never share a worktree path and that a parallel `/meeting` advisory claim still collides with the repo-level lease. (same note) <!-- children-of:1f4f --> <!-- id:923b -->
- [ ] `[ROUTINE]` **b099** — Layer A extractor: pull path-shaped tokens from `**Anchors**`/`**Tests**`/`**Context**`/`**Wiring**` into `disjoint-greenlight.sh` TSV. **Empty extraction ⇒ run-alone** (never greenlight-all). Log both the under-extraction rate (extracted ⊂ actual diff) and the false-serialization rate (declared-intersect but diffs disjoint). Contract: a test over fixture items from this repo and `~/src/loderite`, and both metrics emitted. (same note) <!-- children-of:1f4f --> <!-- id:b099 -->
- [ ] `[HARD — pool]` **ae08** — **Wire the built-but-unreferenced machinery** (A1/F2): call `disjoint-greenlight.sh` from the drain-mode planner and route same-repo integration through `drain-integrate.sh`; change `relay/references/executor-contract.md:88` tick-ownership (executors report `worked_ids`, the driver ticks) with a contract version bump. Verified precondition: `grep -c 'disjoint-greenlight\|drain-integrate' relay-loop.js` = 0. Contract: the greenlight and one-writer integrator are reachable from an actual relay run. **Gates `ebbe`.** (same note) <!-- children-of:1f4f --> <!-- id:ae08 -->
- [ ] `[HARD — pool]` **a955** — L1 mechanize the integrator: wrap `integrate` steps 0–8 in one `integrate.sh` dispatched as a single `relay-mech` hop (`relay-loop.js:2034` is `model:'sonnet'` today), fail-closed handback on any nonzero, retaining a micro-hop only for the semver "user-observable?" judgment, with loud-failure escalation (never a silent fallback — the `id:25aa` wrong-anchored-ckpt class). Contract: a run completes integration with no Sonnet integrate agent, and a forced nonzero surfaces loudly. <!-- children-of:1f4f --> <!-- gated-on:87f5 --> <!-- id:a955 -->
- [ ] `[HARD — meeting]` **3ca7** — L4 round tail: drained lanes pull rechain-eligible work **only during the wait before the `[INTENSIVE]` unit starts**, hard-fencing while it runs (A4) — co-running would silently amend `id:8d52`/`5ac6`. Re-key C2's per-round scope, the quota memo TTL and MAX_UNITS to a window. Contract: a test proving no non-intensive unit is dispatched while an intensive unit holds its resource claim. <!-- children-of:1f4f --> <!-- gated-on:87f5,cc90 --> <!-- id:3ca7 -->
- [ ] **Amend `id:1f4f`** with the ratified wave spec, its seven `children:` edges, and the **barrier-timeout requirement** (tie to the `id:e149` heartbeat — under waves one hung executor stalls the repo, not one lane). Record F7's open questions: crash-mid-wave reconcile must be designed with `923b`'s key shape; quota exhaustion mid-wave is undefined. <!-- id:1f4f -->
- [ ] **Amend `id:ebbe`** — gate on `ae08`; record that concurrent fan-out may never be worth building if `cc90` delivers the drain win, and that the depth-vs-width distinction (cc90 = latency between dependent units; ebbe = throughput across independent ones) must be checked before that retirement is decided. <!-- id:ebbe -->
- [ ] **Record the `--fabled` escalation-trigger fire** (4 forced amendments ≥ threshold 2) against `id:8df5` as standing evidence for the per-decision + full multi-pass; designing them is a separate session. <!-- id:8df5 -->
