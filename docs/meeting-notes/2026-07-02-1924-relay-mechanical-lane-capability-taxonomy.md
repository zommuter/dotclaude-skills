# 2026-07-02 — Relay: capability-keyed lane taxonomy + mechanical-run daemon

**Started:** 2026-07-02 19:24
**Session:** faa4dcf0-e245-4bbd-a6d1-3436147cf12b
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration), 🛠️ Sven (systemd `--user`/`.path`/`.timer`)
**Topic:** Mechanize more of `/relay` — status of the discovery flip, and a new capability tier for pure-mechanical (often intense) compute a daemon/CLI runs directly while an LLM session reviews.

## Surfaced discoveries
EMBED unset — no semantic retrieval. Priors carried in: id:4d8e (mechanical classifier flip), id:2ec4 (mechanical model tier — deferred, no non-LLM dispatch target in the Workflow sandbox), id:65f9 (move discovery off Workflow), id:5ac6 (INTENSIVE = flag+invariant, operative only on dispatchable lanes), the 2026-06-30 hands-disposition redesign (db39/e175/45c6/1d3f — author-then-run split, relay NEVER auto-executes, 5-criterion pool-safe check a–e), [[oom-local-model-session-kills]], [[babysitter-durable-cron-no-op]].

## Status readout — discovery flip & backtest (Thread 1, no decision needed)
The flip is **DONE**. `a0b6` shipped 2026-07-01 (supervised): the 74-line LLM `shardPrompt` DELETED; discovery is now fully deterministic (reconcile+classify+route via `reconcile-repo.sh` id:5987 + `classify-repo.sh` + `classify-verdict.sh` id:85df); the LLM is confined to a dormant `AMBIGUOUS` surface. Supporting pieces all shipped: case-b split (5eb3), INTENSIVE fail-safe (5ac6), roadmap-lint case-d realign (9062). Backtest gates: **C3** historical — 762 events, 0 crashes, candidate-worse **0/762** after `match_policy_delta()` mechanization (commit 784a3b1); **C4** forward — RELAXED/SATISFIED 2026-07-01 (portfolio drained; 2 clean drained runs suffice as idle/skip confirmation). Remaining tail only: `b50e` (delete 000d/9973/ad74 JS backstops once AMBIGUOUS proven constrained — GATED), `de31`/`b444` (decision-queue + transport), follow-ons `984d`/`3554`/`cb9b`.

## Agenda
1. Represent a daemon-runnable intense task — new lane vs reuse INTENSIVE + 5-criterion?
2. Overthrow the lanes → capability-keyed taxonomy; sequencing vs the freshly-hardened flip.
3. Live-resource arbitration + rename cadence.

## Discussion

### Item 1 — new lane vs reuse
🏗️ Archie: the topology already exists **three times** — `tools/model-probe.sh`, `tools/quota-sample.{sh,service,timer}`, `tools/relay-watchdog.{sh,service,timer}`: systemd-`--user` → mechanical script → git-JSONL → LLM-reviews-later. `model-probe` IS this pattern (benchmark run mechanically, reviewed against a pre-registered band). Question is generalize-into-a-lane + contract, not can-we-build.
😈 Riku: won't fight existence; will fight **auto-execute scope**. Benchmarks are the OOM-risky GPU workloads that killed six sessions ([[oom-local-model-session-kills]]). A daemon that auto-picks "any INTENSIVE item" is exactly what `--intensive` (explicit opt-in) prevents. Safe only if it runs a **whitelisted, host-gated, pre-authored recipe set** — the registry is the gate, not a tag.
✂️ Petra: prefer no new lane — "daemon-runnable" = the 5-criterion pool-safe check (a–e) applied to an INTENSIVE item, with the daemon an alternative runner to human hands.
🎛️ Orla: classification is reuse, but the new objects are a **recipe queue + result-return path**; results re-enter the pool as `review` units via the existing `inject.sh` bridge (pool sandbox can't read fs — same intake injections use).
🛠️ Sven: pure-mechanical run has no permission wall → sidesteps the babysitter problem. `.path` unit watching a drop-dir for on-demand relay-authored recipes; `.timer` for standing ones.

### Item 2 — overthrow the lanes (chair's reframe: tag = required capability, not dispatch venue)
🏗️ Archie: a disentangling, not a rename. Today `[HARD — <suffix>]` conflates capability tier (HARD=strong LLM) with dispatch venue. Capability-keyed mapping: `[HARD — pool]→[HARD]`, `[HARD — meeting]→[INPUT — meeting]`, `[HARD — decision gate]→[INPUT — decision]`, `[HARD — hands]→[INPUT — access]` OR `[MECHANICAL]` (per-item). `[HARD — hands]` splitting into MANUAL-vs-MECHANICAL IS the unfinished business of the hands meeting ("shrink the hands queue to the irreducible").
🎛️ Orla: advances mechanization — the **tag becomes the verdict**, `classify-verdict.sh` derivation shrinks; `[MECHANICAL]→mechanical` (new verdict, daemon consumes/pool ignores); `[INPUT — decision]` items ARE the de31 decision-queue's contents.
😈 Riku: won't fight the taxonomy; fights blast radius + timing — vocabulary hardened 4 days ago across ~15 tests + the crash-prone engine. **Decide target now, sequence the build**; rename as a separate migration with **dual-vocabulary lint + deterministic converter**, never a flag-day.
✂️ Petra: N=2 cut — actual need = run benchmarks without an LLM babysitter = `[MECHANICAL]` + recipe manifest + daemon + permitted-intensity; none requires renaming an existing item. Ratify overthrow as target, sequence rename as gated follow-up.
🛠️ Sven: daemon buildable today off the additive tags. `.path` watches `~/.config/relay/recipes/pending/`; handoff authors recipe JSON `{id,repo,cmd,host,est_wall,resource,acceptance_artifact}`; daemon pending→running→done, writes artifact, drops review-request via inject. Permitted-intensity should SUPERSEDE binary `ALLOW_INTENSIVE` — graded window (tea 15m/light vs lunch 2h/heavy).

### Item 3 — live-resource arbitration + `[INPUT — kind]` refinement
🛠️ Sven: launch gate = TWO independent conditions — permitted window (declared budget) AND live availability (measured VRAM/RAM/load + no competing `[INTENSIVE — same-resource]` claim). Reuses the `resource:` claim (id:8d52/052c).
😈 Riku: "suspend zkm via gamemode" is riskier than "defer until zkm finishes" — suspending an in-flight embed-rebuild can corrupt the index (hands-criterion b). gamemode lives in **it-infra**, not here. Safe default = **check-and-defer, never preempt**; active-suspend = cross-repo enhancement, routed + gated.
🎛️ Orla: arbitration = the `resource:` claim generalized across both runners (pool + daemon share one `claim.sh` registry).
🏗️ Archie (chair refinement `[INPUT — kind]`): everything needing a human collapses to one capability `[INPUT]`, sub-typed `{meeting,decision,access}` = kind/effort (triage-able). `[INTENSIVE — human]` rejected — INTENSIVE is a resource axis; overloading it breaks the `resource:` claim derivation. Two clean orthogonal axes: **capability** (ROUTINE/HARD/INPUT/MECHANICAL) × **resource** (INTENSIVE — res).

## Decisions

1. **Target taxonomy = capability-keyed (ratified as north star; write to `relay/references/hard-lanes.md`).** Two orthogonal axes — **capability**: `[ROUTINE]` (executor LLM) · `[HARD]` (strong LLM) · `[INPUT — {meeting,decision,access}]` (human ± LLM; sub-type = effort) · `[MECHANICAL]` (compute only, no LLM/human); **resource** (orthogonal): `[INTENSIVE — <res>]`. Tag names *what is required*; dispatch venue DERIVED. Only ROUTINE/HARD/INPUT—meeting touch an LLM. Mapping: `[HARD — pool]→[HARD]`, `[HARD — meeting]→[INPUT — meeting]`, `[HARD — decision gate]→[INPUT — decision]`, `[HARD — hands]→[INPUT — access]` OR `[MECHANICAL]` (per-item judgment). `[INPUT — access]` replaces `[MANUAL]`; `[INTENSIVE — human]` rejected. *Out of scope:* any dispatch-venue suffix in the tag.

2. **Build additively first (slice A); rename soon (slice B).** Slice A touches nothing existing. Slice B gated ONLY on `[MECHANICAL]` existing — next relay handoff after A1, not deferred behind the daemon or b50e — with a deterministic converter + dual-vocabulary lint window (both accepted ERROR-free one window, then old-vocab → lint ERROR). *Out of scope:* flag-day rename; indefinite deferral (chair: no sunken-cost stall).

3. **Mechanical-run daemon = host `--user` `.path` unit, model-probe topology, OUTSIDE the Workflow.** Handoff (LLM) authors recipe JSON into `~/.config/relay/recipes/pending/`; daemon runs it (no `claude -p`), writes acceptance artifact, re-enters pool as a `review` unit via existing `inject.sh`. Sidesteps babysitter/outage (pure-mechanical → no permission wall). *Out of scope:* moving the *discovery* loop off Workflow (id:65f9 stays separate — this only de-risks it); reimplementing the executor pool outside Workflow.

4. **Auto-launch gated by TWO required conditions: graded permitted-intensity window AND live resource availability.** `~/.config/relay/permitted-intensity.json = {max_wall_seconds, resource_ceiling, expires_at}`; `relay intensity` CLI (tea 15m/light, lunch 2h/heavy; `--afk` conservative default) SUPERSEDES binary `ALLOW_INTENSIVE`. Launch iff `est_wall≤window ∧ resource≤ceiling ∧ now<expires_at` AND `resource-probe.sh` (VRAM/RAM/load + shared `claim.sh` read) shows the resource free. **Check-and-defer, never preempt.** *Out of scope:* active gamemode-suspend (→ it-infra, gated); auto-scanning ROADMAP for arbitrary INTENSIVE items (whitelisted recipe manifest is the gate).

## Action items
- [ ] **A1 — `[MECHANICAL]` capability tag** — `gather-human-backlog.sh` + `roadmap-lint.sh` accept it; `classify-verdict.sh` emits new `mechanical` verdict (pool-inert; INTENSIVE composes); document in `relay/references/hard-lanes.md`. Contract: `[MECHANICAL]`→`mechanical`, pool ignores, `[MECHANICAL][INTENSIVE — <res>]` carries the intensive flag. <!-- id:7616 -->
- [ ] **A2 — recipe manifest schema + drop-dir contract** — `~/.config/relay/recipes/{pending,running,done}/`; recipe JSON `{id,repo,cmd,host,est_wall,resource,acceptance_artifact}`; whitelisted (relay-authored), never auto-scanned from ROADMAP. <!-- id:64d3 -->
- [ ] **A3 — mechanical-run daemon** — `--user` `.path`-triggered oneshot (model-probe topology), runs pending recipes pending→running→done, writes artifact, drops a review-request consumed via `inject.sh`. `make install-mechanical-daemon`. <!-- id:b3d0 -->
- [ ] **A4 — `permitted-intensity.json` + `relay intensity` CLI** — graded windows (tea/lunch; `--afk` conservative default); daemon reads it; SUPERSEDE binary `ALLOW_INTENSIVE` with a graded gate + migration. <!-- id:e407 -->
- [ ] **A5 — `resource-probe.sh`** — VRAM/RAM/load + shared `claim.sh` read → check-and-defer arbitration (daemon + pool share one claim registry). <!-- id:68dc -->
- [ ] **B1 — target taxonomy → `hard-lanes.md` north star + converter + dual-vocab lint window** — deterministic `[HARD — *]`→new-vocab converter; lint accepts BOTH one window then old-vocab → ERROR. Gated on A1. <!-- id:4f02 -->
- [ ] **B2 — migrate all lane-readers + tests** — `gather-human-backlog.sh`, `roadmap-lint.sh`, `classify-verdict.sh`, `relay-loop.js`, `references/*` to `[HARD]`/`[INPUT — {meeting,decision,access}]`/`[MECHANICAL]`; `[HARD — hands]` fans out to `[INPUT — access]` vs `[MECHANICAL]` by per-item judgment. Gated on A1/B1. <!-- id:8111 -->
- → routed to it-infra inbox: gamemode active-suspend integration for the daemon (gated cross-repo enhancement; SIGSTOP-safety per-competitor judgment). <!-- routed:f506 -->
- [ ] **Annotate id:2ec4** — this host daemon is the answer to "where does mechanical execution live" (outside the Workflow); the deferred in-Workflow mechanical tier stays parked. (in-session note, no new id)
- [ ] **Relate id:65f9** — daemon proves the off-Workflow mechanical-run pattern (de-risks moving discovery) but does NOT subsume it. (in-session note, no new id)

## Amendment 2026-07-02 (post-build — the `[MECHANICAL]` producer gap)
Slice-A A1 shipped the CONSUMER half only: the classifier now RECOGNIZES `[MECHANICAL]` and emits the pool-inert `mechanical` verdict, but no relay layer PRODUCES the tag and nothing RUNS it. Filed three producer follow-ons (join wave 2 with A3/B1/B2):
- **M1 (id:9c88)** — `handoff.md` C2 must recognize compute-only/no-LLM/benchmark work and tag `[MECHANICAL]` + author the A2 recipe (the missing producer link; pairs with A3).
- **M2 (id:2313)** — the "`[HARD — hands]` wrongly" contract sites: `hard-lanes.md` re-lane 5-criterion, `handoff.md`/`human.md` author-then-run split still route daemon-runnable "run" work to `[HARD — hands]` (human). Add a "needs an LLM?" branch → compute-only+passes-a–e ⇒ `[MECHANICAL]`; exclude `[MECHANICAL]` from `human.md`'s "you run these". Orthogonal to B2 (rename) — must survive it.
- **M3 (id:3ef7)** — detector-surfaces + per-repo re-lane of EXISTING `[HARD — hands]` items that are actually daemon-runnable (conformance-sweep: surface-don't-auto-fix). No dotclaude-skills-local candidates; real ones live in benchmark/pilot repos.
