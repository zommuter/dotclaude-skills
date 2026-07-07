# 2026-07-07 — Move relay discovery off the Workflow engine? (id:65f9)

**Started:** 2026-07-07 12:28
**Session:** 1fa48c3d-c2f4-439f-9378-8bbb363853b3
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate — blast radius/regression), ✂️ Petra (productivity/YAGNI), 🎛️ Orla (multi-agent orchestration + model-tier cost economics), 🛠️ Sven (systemd `--user`/`.path`/`.timer`)
**Topic:** id:65f9 — the discovery loop still spends one (Haiku) LLM round-trip per round only because the Workflow sandbox can't exec/curl/read-fs. Should discovery go mechanical, and how?

## Surfaced context
The a0b6 flip (2026-07-01) made discovery pure transport: `discover-prelude`+`discover-run` exec `discover-repo.sh` per repo and relay JSON verbatim — zero reasoning. But the Workflow sandbox has no fs/net/subprocess (`relay-loop.js:1529/1551`), so `agent()` (Haiku-floored) is the only way to shell out. id:2ec4 parked the in-Workflow "mechanical tier" (no non-LLM dispatch target in the sandbox); the 2026-07-02 umbrella built the mechanical-run daemon for [MECHANICAL] *executor recipes* but scoped *discovery*-off-Workflow OUT — that's this item. Verified this session: long-lived Workflow with an internal round loop (`state.round`, `--once`/`--after`); discovery is an in-round `agent()` (`relay-loop.js:336`); `args` read once at launch (`:29`).

## Agenda
1. Gate check: is the residual discovery cost material enough to justify any re-architecture?
2. If so: hybrid (cron→queue→bridge-read) vs wholesale (abandon Workflow).
3. Outage-resilience regression.

## Discussion

### Item 1 — is the residual cost material?
Personas initially framed it as a **token-cost** gate: 🎛️ Orla noted a0b6 already banked the Opus→Haiku win and `discover-sig.sh` caches unchanged repos, so the residual is a rounding error against executor spend; ✂️ Petra and 😈 Riku argued the item's own gate ("only worth it if the residual haiku cost proves material") was unmet and the blast radius of re-architecting the just-hardened engine dwarfs a Haiku saving.

**User reframe (decisive):** the cost is **not tokens — it is reliability.** Haiku has been observed to mangle even "execute and echo the JSON" requests. The governing rule is **"no LLM if mechanical can do as good or even better."** Pure-transport exec-classify is the textbook case where mechanical is *strictly* better (deterministic, cannot hallucinate a verdict). This resolves Item 1 *for* the work — id:65f9 is warranted, on correctness grounds, not cost.

### Item 2 — the HOW, under the reliability doctrine
😈 **Riku:** The mangle lives in the exec-and-classify (Haiku running `discover-repo.sh` + echoing the verdict). Move *that* to a `.timer` script and the mangle dies at its source. But the executor pool is a long-lived fs-blind Workflow, so ingesting the cron's results back in needs an `agent()` read — itself a small "echo the JSON," the same mangle class, smaller surface. Zero-LLM needs either per-round relaunch (args is the only non-LLM channel, launch-time-only) or leaving the Workflow.

🎛️ **Orla:** A trilemma: (i) keep the long-lived loop → irreducible small bridge-read; (ii) relaunch per round via `args` → reintroduces the *launch* permission-wall (the id:af30 governor, auto-mode **denied**); (iii) wholesale → reimplement worktrees/leases/integrator/quota-stop. The doctrine says kill the LLM where mechanical is as-good; it's only *blocked* for the final file-echo by the sandbox.

🛠️ **Sven:** Asymmetry: the **discovery** half has no permission wall — a `--user` `.timer` running `discover-repo.sh` is pure-mechanical, no `claude`, and *more* outage-resilient than a session-bound loop. The wall lives entirely in the **dispatch** half, which id:65f9 doesn't change.

✂️ **Petra:** N=2 cut — **split the item.** Ship the mechanical producer now (the part that mangles, no wall, bounded); defer eliminating the residual queue-read, gated on the launch-wall.

🏗️ **Archie:** Composes with the 2026-07-02 daemon (`~/.config/relay/recipes/{pending,running,done}` + `inject.sh` intake) — the producer reuses that topology; the mangle-prone compute leaves the LLM.

**User decision:** option 1 (split, producer now); keep option 3 (wholesale) as a **parallel investigation activated the moment trouble stirs up.**

### Item 3 — outage-resilience
🛠️ Sven: the `.timer` producer *improves* discovery resilience (systemd restarts it; no wall). 😈 Riku forward-flag: two liveness domains now (producer `.timer` + dispatch Workflow) vs the watchdog/reconcile's one-loop assumption — extend the heartbeat to the producer. 🎛️ Orla: label the residual read as the known-remaining LLM surface (no-silent-swallow), don't let 95%-mechanized read as 100%.

## Decisions
- **D1 — id:65f9 warranted on RELIABILITY grounds, not token cost.** Rule: "no LLM if mechanical can do as good or better." Pure-transport exec-classify is strictly better mechanical. *Out of scope:* a token-cost justification (rejected as the frame).
- **D2 — SPLIT id:65f9; build the mechanical discovery PRODUCER now.** A `--user` `.timer` runs `discover-repo.sh` per confirmed `relay.toml` repo (honoring `# path:`), zero LLM, no permission wall, writing a schema-checked work-queue into the 2026-07-02 daemon drop-dir topology. Removes the mangle-prone exec-classify from the LLM. Executor prelude consumes the queue. *Out of scope:* eliminating the residual queue-read; reimplementing the pool. <!-- id:9d97 -->
- **D3 — Residual `agent()` queue-read stays, DEFERRED + LABELED.** Irreducible while dispatch is a long-lived fs-blind Workflow (a pure file-echo, far smaller mangle surface). Elimination needs per-round relaunch via `args` (blocked on the launch-wall id:af30) or D4. Gate on the launch-wall / mechanical-dispatch-target (id:af30 / id:2ec4). Must be **labeled** as the known-remaining LLM surface (no-silent-swallow). *Out of scope:* eliminating it now. <!-- id:7402 -->
- **D4 — Wholesale off-Workflow = TRIGGER-GATED parallel investigation** ("the moment trouble stirs up"). Trigger = residual read proving unreliable/insufficient, OR the launch-wall staying unsolved long enough to block D3. On trigger: reimplement worktrees/leases/integrator/quota-stop outside the Workflow (zero LLM, own the parallelism). Not a live build. *Out of scope:* building it pre-trigger. <!-- id:882a -->
- **Item 3 — discovery resilience improves; forward-flag two liveness domains.** Extend the run-heartbeat (id:e149) to cover the producer `.timer` so a dead timer reads as "discovery down," not "no work." *Out of scope:* the dispatch-launch wall (unchanged; id:af30). <!-- id:54fc -->

## Action items
- [ ] Build the mechanical discovery producer: `.timer` + `discover-repos-mechanical.sh` (exec `discover-repo.sh` per confirmed relay.toml repo) → schema-checked work-queue in the daemon drop-dir; `make install-*` target; hermetic test (queue schema + **determinism parity** vs the Haiku `discover-run` output on a fixture repo set). Reuses 2026-07-02 daemon topology (id:64d3/b3d0). [ROUTINE once RED-specced] — dispatch via `/relay handoff` → executor. `docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md`. <!-- id:9d97 -->
- [ ] Wire the executor prelude to consume the mechanical queue when present, and **LABEL** the residual queue-read as the known-remaining LLM surface (no-silent-swallow), pointing at the D3 deferral. Gated on id:9d97. `docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md`. <!-- id:7402 -->
- [ ] Extend the run-heartbeat (id:e149) to cover the producer `.timer` so the watchdog (id:98f0) + auto-reconcile (id:7809) see two liveness domains. Gated on id:9d97. `docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md`. <!-- id:54fc -->
- [ ] Register the D4 wholesale-off-Workflow investigation, trigger-gated (residual-read unreliable OR launch-wall blocks D3's elimination). Do NOT build pre-trigger. `docs/meeting-notes/2026-07-07-1228-relay-discovery-off-workflow.md`. <!-- id:882a -->
