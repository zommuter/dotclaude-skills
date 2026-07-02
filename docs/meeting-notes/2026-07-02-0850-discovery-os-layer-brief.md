# Pre-meeting brief: should relay discovery move to an OS-level layer (systemd `--user` timer and/or inotify `.path` units)?

*Read-only research draft (Fable-orchestrated, Opus-researched, 2026-07-02). Does NOT decide — feeds a future `/meeting`. Strawman clearly labelled in §6.*

## 1. Question + why now

The relay pool discovers work by re-classifying every registered repo at the top of each in-run round (`relay-loop.js` Phase 1, `:717-1016`). That machinery just completed a major overhaul — the LLM judgment shard was replaced by a **deterministic, side-effect-free classifier** (`classify-verdict.sh`, id:85df; assembled by `classify-repo.sh`, id:3f0f; git side-effects split into `reconcile-repo.sh`, id:5987; flip = a0b6). The question raised now is whether discovery should additionally move *off* the in-run loop onto an OS-level layer that runs on a cadence or wakes on filesystem events. Two sibling items already scope pieces of this — **inotify wake (id:0ee6)** and **continuous dispatch (id:80b8)** — both explicitly *parked/gated* at the 2026-06-30 and 2026-07-01 meetings (`2026-06-30-1523-...classifier.md:104`; `2026-07-01-1904-...engine-swap.md:55`). This brief assembles the evidence so the meeting can decide whether to un-gate, and in what shape.

## 2. Status quo — how discovery works today

**Mechanism.** Each round, a once-only **prelude** agent (haiku) reads `relay.toml`, lists own repos, consumes the injection inbox, peeks live claims, runs `discover-sig.sh` for per-repo signatures, and runs `stop-sentinel.sh` (`relay-loop.js:723-734`). Then, for repos whose signature *changed* since last round, a **mechanical runner** agent (haiku) runs `discover-repo.sh` (→ `reconcile-repo.sh` + `classify-repo.sh --emit unit`) once per repo and relays JSON verbatim — zero judgment (`:820-851`). Unchanged repos are served from the content-addressed cache (`:789-815`).

**Cost per round.** The classifier itself is pure bash (`classify-verdict.sh:17-20` — "SIDE-EFFECT-FREE: no git, no filesystem writes"), so a *drained, unchanged* repo now costs ~0 LLM tokens (sig-cache hit, no runner agent — `:845-851`, "a round where every repo is cached runs zero runners"). Only changed/new/fail-open repos pay for a haiku runner.

**Measured (relay-econ.py, last 18 runs, cache-accurate list rates):**

| category | cost $ | cost % | Σ agent-time % | wall-clock (union) % |
|---|---|---|---|---|
| work (execute/review/hard/handoff/integrate) | 899.07 | 80.8% | 63.1% | 53.6% |
| **scaffold (discover + quota)** | **135.94** | **12.2%** | **23.3%** | **22.6%** |
| status | 17.57 | 1.6% | 7.4% | 15.5% |
| poll/other | 60.49 | 5.4% | 6.2% | 8.4% |

`scaffold` bundles discover **and** quota checks (`relay-econ.py:35-37`), so pure-discovery cost is a *subset* of the 12.2% / 22.6%-wall figure — discovery is a minority of spend but a non-trivial slice of wall-clock. (Historical pre-flip context: the old LLM shard was ~1.9M cache_read/shard, ~46% of cost — `2026-06-30-1523:32`; the flip already collapsed that. This is the constraint-archaeology crux — see §6.)

**What it MISSES.** Discovery only runs *while a pool is running*. The loop winds down on a **two-dry exit** (two consecutive discoveries with no actionable work — `relay-loop.js:620-633` header) or a quota/stop/max-rounds cap. Between runs, any churn — a `git push` landing new commits, a human editing ROADMAP/TODO, a dependency repo closing an item — is **invisible until the next manual `/relay` launch**. There is no push-style signal that "there is now fresh work"; the human is the scheduler between runs. (The outage watchdog id:98f0 notices a *dead* run, not *fresh work* for a cleanly-stopped fleet.)

## 3. Options matrix

**Hard constraint threaded through all options** (verify: `2026-06-22-1546-relay-outage-resilience.md:23`): an OS `systemd --user` timer firing `claude -p "/relay --afk"` satisfies survives-kill + reaches-local but **hits the permission wall**; the standing decision (DECISION 1, `:25`) is to *avoid* out-of-harness `claude -p`, which is why `relay-watchdog.sh` "deliberately does NOT run `claude -p`" (`relay-watchdog.sh:5-9`). So **an OS layer can only DETECT + PRE-COMPUTE (verdicts, decision-queue, notifications); a live harness session must CONSUME and dispatch.** The enabling new fact: `classify-repo.sh`/`classify-verdict.sh` are pure bash — an OS timer *can* run the whole classify island directly with **no LLM at all**. Only two LLM surfaces remain (AMBIGUOUS — never emitted today; lane-triage case-g — a resolution step) per `2026-06-30-1523:75`.

### (A) Status quo — in-run polling only
- **Buys:** nothing new; zero build.
- **Cost:** none.
- **Failure modes:** between-runs churn stays invisible (§2); human is the between-run scheduler.
- **Ids:** baseline.

### (B) `systemd --user` timer runs the pure classify island on a cadence → writes a durable decision/work-queue the next `/relay` consumes at launch
- **Buys:** between-runs *staleness* closes — verdicts are pre-computed while no pool runs; at launch the pool reads a fresh queue instead of re-deriving cold. Latency of "fresh work exists" drops from "until next manual launch" to "one timer tick." Tokens: ~0 (pure bash classify, no agent). A host timer also *sees* the real usage cache that the in-Workflow quota gate cannot (`quota-stop.sh:16-23` — the `/tmp`-namespace blindness), though quota is moot for pure detection.
- **Build+maintenance:** moderate. Needs a timer+service pair (precedent: `quota-sample.{service,timer}`, `relay-watchdog.{service,timer}`), a queue-writer wrapping `classify-repo.sh` over `relay.toml` repos, and a *consume* contract at `/relay` launch. `decision-queue.sh` (id:de31) already exists as a durable flock'd JSONL queue — but today it holds *human-decision-requests*, not pre-computed verdicts; either extend it or add a sibling queue. **b444 (durable-queue transport) is its home** (`2026-06-30-1523:103`).
- **Failure modes:** (1) *laptop asleep* → timer misses ticks (systemd `Persistent=true` catches up on wake, but a verdict computed pre-sleep may be stale on wake). (2) *stale queue consumed after manual edits* — a verdict computed at T, then a human edits the ledger at T+5min, then `/relay` launches at T+10 and trusts the stale entry. Mitigation: the queue entry must carry the `discover-sig` hash and the consumer re-validates (fail-open to re-classify on mismatch — exactly the existing cache contract, `discover-sig.sh:10-14`). (3) *double classification vs a live pool* — harmless for pure detection (classify is side-effect-free) but the queue writer must never `reconcile-repo.sh` (that has git side-effects, `reconcile-repo.sh:10-12`) against a repo a live pool holds; gate on `claim.sh peek` / heartbeat.
- **Advances:** b444 (gives the queue a producer), 80b8 (a pre-warmed queue feeds continuous dispatch). **Conflicts/overlaps:** id:0ee6 (inotify) is the event-driven alternative to a fixed cadence; the sig-cache (c3a6) already makes the *classify* cheap, so B's value is purely latency/wakeup, not tokens (the DP5 constraint-archaeology point, `:54`).

### (C) inotify / `systemd .path` units watch repo HEADs + ledger files → invalidate sig-cache entries push-style (pure cache-warming, NO verdicts)
- **Buys:** replaces sleep-poll cadence with event-driven wake (id:0ee6's residual value, `2026-06-30-1523:54`, "don't spin the loop on a /loop cadence over a drained backlog — a wakeup concern, not a token concern"). No verdict pre-computation — just marks which repos are dirty so the next scan skips clean ones faster.
- **Build+maintenance:** adds an `inotifywait` dependency (the meeting flagged "decide if the inotifywait dep is worth it only after" the classifier — `:78`). Watch-set derives from `discover-sig.sh`'s input superset (`discover-sig.sh:52-76` — HEAD, tags, porcelain, upstream, worktrees, orphans, toml, ROADMAP) + a b444 watchfile.
- **Failure modes:** inotify misses events across unmount/network-fs/overflow → must fail-safe toward re-checking, never sleep-through (`:56`, `:78`). Watching N repos' `.git` internals is fiddly (packed-refs, worktree HEADs). Laptop-asleep loses events entirely (inotify is not persistent like a timer).
- **Advances:** id:0ee6 directly. **Conflicts:** largely *redundant with the sig-cache* — `git status` incl. worktree heads "is the dominant change signal — already hashed by discover-sig, so it works with or without inotify" (`:78`). This is the weakest standalone option per the existing record.

### (D) B + C hybrid — inotify triggers the timer's classify-island run (event-driven pre-computation)
- **Buys:** union of B (pre-computed queue) + C (event-driven, no fixed-cadence spin). Freshest possible queue with least idle wakeups.
- **Cost:** highest build (both mechanisms + their failure-mode handling).
- **Failure modes:** compounded (asleep, overflow, stale-consume, claim races). Two moving parts to maintain.
- **Ids:** advances 0ee6 + b444 + 80b8 together — but bundles three gated items into one build (scope risk; the meetings deliberately *decomposed* these apart).

### (E) B + desktop/Push notification when the queue is non-empty
- **Buys:** closes the human-in-the-loop gap directly — when between-runs churn produces actionable work, *ping the human to launch a pool* (rather than pre-computing for a launch that may never come). Ties into the `relay-watchdog` notify precedent (notify-send → `$RELAY_WATCHDOG_NOTIFY_CMD` push, `relay-watchdog.sh:61-73`) and the ping-threshold doctrine (queue-depth-while-drained = PING trigger, `2026-06-30-1523:103`).
- **Cost:** B + a thin notify hook (the watchdog already has the reusable notify ladder).
- **Failure modes:** notification fatigue if the threshold is wrong (the watchdog's dedup-state pattern, `relay-watchdog.sh:86-99`, is the template). Ping when the *human* is the bottleneck, not on every tick.
- **Ids:** advances 98f0 (notify reuse) + b444 (queue) + the ping-threshold doctrine. Arguably the *cheapest genuinely-useful* option — it respects the "OS layer detects, human/session dispatches" constraint most honestly.

## 4. Interaction with a LIVE pool

- **Claims/heartbeat:** any OS-layer actor must treat a repo held by a live run as off-limits. The primitives exist: `claim.sh peek` (live cross-session claims) and `heartbeat.sh dead-runs`/`live-runs` (pure ts+TTL liveness, `heartbeat.sh:83-92`). A pure *classify* (side-effect-free) run is safe to overlap; a *reconcile* (git side-effects) run is NOT and must skip claimed/live repos.
- **Sig-cache writes:** the in-run cache is in-memory module state (`state.discoverCache`, `relay-loop.js:798`), not on disk — so an OS layer cannot warm the *live* pool's cache directly. It can only pre-populate a durable queue the *next* launch reads. (This is why C's "invalidate sig-cache entries" is really "write a durable dirty-list a launch consumes," not "poke the running loop.")
- **Decision-queue freshness/invalidation:** every pre-computed entry must carry its `discover-sig` and be re-validated at consume time (fail-open to re-classify on mismatch) — otherwise a live pool that just churned a repo leaves a stale queue entry. This is the same fail-open contract the in-run cache already uses (`discover-sig.sh:10-14`; `relay-loop.js:793-796`), so it is a known-safe pattern, not new design.
- **Double-classification races:** benign for classify (idempotent, side-effect-free); the hazard is only if the OS layer ever *reconciles* or *dispatches* — which the hard constraint forbids anyway.

## 5. Evidence gaps

What the meeting would ideally see measured *first* (observe-before-preventing):

1. **How often is between-runs churn actually stale/consequential?** i.e. how frequently does a repo gain actionable work while no pool runs, and for how long does it sit before the next manual launch? — **NOT directly answerable from current logs.** `relay-events.jsonl` (1620 lines) logs *dispatched* verdicts only; idle/skip are under-sampled (`2026-06-30-1523:69`). Measuring this needs correlating run-end→next-run-start gaps against ledger commit timestamps — a small analysis script, not existing tooling.
2. **What fraction of round wall-clock is discovery (vs quota)?** — **Partially answered:** relay-econ's `scaffold` = 22.6% of wall-clock union but bundles quota. Splitting discover from quota in `PHASE_CAT` (`relay-econ.py:36`) would isolate it; worth doing before claiming discovery latency is the bottleneck.
3. **Is the between-runs latency a real pain, or is the human cadence fine?** No incident log exists for "I wished the pool had noticed X sooner." The watchdog's outage-death evidence file is the model — a cheap logger before infra (the id:98f0 precedent, `2026-06-22-1546:41`).

## 6. Strawman recommendation + open questions

**STRAWMAN (not a decision — for the meeting to shoot at):**

The **token** argument for moving discovery off-loop has *already dissolved* — the a0b6 flip + sig-cache (c3a6) made unchanged-repo classification ~free (this is exactly the DP5 constraint-archaeology finding, `2026-06-30-1523:54`). So the only live justification is **between-runs latency/wakeup**, and there is **no measurement** that this latency is painful (§5). Per *observe-before-preventing*, the strawman is:

- **Do NOT build B/C/D yet.** Build the **evidence logger** first (gap §5.1): a tiny cadence-agnostic script (or extend relay-econ) that records run-end→next-run gaps and whether actionable work accrued in between. Gate any timer/inotify build on that showing a real, recurring latency cost.
- **If anything ships early, prefer (E)** — a notify-when-queue-non-empty hook — over (B/C/D). It respects the hard constraint most honestly (OS detects, human dispatches), reuses the watchdog notify ladder + ping-threshold doctrine at near-zero build, and doesn't pre-compute for launches that may never happen.
- **Keep inotify (C/id:0ee6) gated** — the existing record already judges it largely redundant with the sig-cache and dep-cost-questionable (`:78`); un-gate only if the logger shows fixed-cadence spin is a real cost *and* B is chosen.
- Any pre-computation option **must** carry the `discover-sig` and re-validate fail-open at consume (§4), and **must not** run `reconcile-repo.sh` against claimed/live repos.

**Open questions for the meeting:**
1. Is between-runs latency a *felt* pain today, or is manual `/relay` launching acceptable? (Decides whether this whole thread is premature.)
2. If a queue is built, is its home the existing `decision-queue.sh` (id:de31, currently human-decision-requests) or a new sibling — and does that pre-empt b444's transport meeting?
3. Does continuous-dispatch (id:80b8, in-run `pipeline()` refill) subsume the *need* for an OS layer by keeping a single launch running longer over a live-growing backlog — making the between-runs gap smaller?
4. Notify (E) vs pre-compute (B): do we want the OS layer to *prompt the human to launch*, or to *do work ahead of a launch*? These are different philosophies of the human's role as scheduler.
5. Laptop-sleep semantics: is `Persistent=true` catch-up acceptable, or does sleep make the whole cadence unreliable enough to prefer notify-on-next-wake?

---

**Note on the id map:** the inotify item is **id:0ee6** and continuous-dispatch is **id:80b8** (both siblings of 4d8e). `2ec4` (Workflow sandbox has no non-LLM dispatch target) and `65f9` (off-Workflow loop) live in private memory, not in the committed notes — the brief relied on memory summaries for those two. `1324` (backtest-verdict) corresponds to `backtest-verdict.py` in `relay/scripts/`; the pre-flip validation gate is documented under C3=id:5f93 / C4=id:9d2b.

Key files: `relay/scripts/relay-loop.js:708-1016`, `discover-sig.sh`, `classify-verdict.sh`, `classify-repo.sh`, `reconcile-repo.sh`, `decision-queue.sh`, `heartbeat.sh`, `stop-sentinel.sh`, `quota-stop.sh:16-23`, `tools/relay-watchdog.sh`; notes `docs/meeting-notes/2026-06-30-1523-relay-loop-mechanical-classifier.md`, `2026-07-01-1904-a0b6-step-b-engine-swap.md`, `2026-06-22-1546-relay-outage-resilience.md`.
