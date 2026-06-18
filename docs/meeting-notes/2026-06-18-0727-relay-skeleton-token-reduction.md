# 2026-06-18 — Cutting relay "skeleton" tokens; do LLM proxies help?

**Started:** 2026-06-18 07:27
**Session:** ed3ee74c-9ebe-4d50-abed-955c92f17874
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🔭 Otto (observability/MITM-proxy — re-onboarded), 🎛️ Orla (multi-agent orchestration / model-tier economics — re-onboarded)
**Topic:** How to significantly reduce the per-agent "skeleton"/scaffold token spend in `/relay` loops, and whether an LLM proxy could help here and in general.

## Surfaced discoveries
- [2026-06-03 dotclaude-skills] Parser-first / proxy-deferred: token/ctx accounting = transcript `usage` parser is durable; MITM proxy deferred behind an explicit real-time/**request-mutation** N=2 trigger.
- [2026-06-11 dotclaude-skills] CC Agent-tool subagents run in-process and share ONE global `ANTHROPIC_BASE_URL`; model field accepts only sonnet|opus|haiku|inherit — no per-subagent provider routing; a translating proxy carries alias-poisoning risk.
- [2026-06-16 toesnail] Out-of-harness LLM-in-automation has a ToS tripwire; in-harness (Claude Code IS the model) is the clean path.
- [2026-06-12 dotclaude-skills] Workflow engine + concurrency cap is the relay substrate; serialized integrator is structural not model-trusted.
- id:c3a6 (DONE 2026-06-17): status/scaffold was 34.9% of spend; fixed via discover-shard pin→sonnet + content-addressed discovery cache. Forward id:9cb1 = post-fix re-measure, **no live data yet**.

## Agenda
1. What exactly is "skeleton" spend, and is the big win already captured by id:c3a6 — i.e. measure-first vs build-more?
2. Can an LLM proxy reduce skeleton tokens — in the relay specifically, and in general?
3. If further reduction is warranted, which lever moves billed tokens: inline-guardrail trim, cache-friendly prompt ordering, or further tier-pinning?

## Discussion

### Block 1 — what "skeleton" costs; can a proxy touch it

🏗️ **Archie:** "skeleton" = `relay-econ.py` scaffold+status buckets. Last measured (5 runs/$633, id:c3a6) status = 34.9% at 2.2× concurrency. **DONE 2026-06-17**: discover-shard pinned sonnet (was inheriting Opus — 35% leak) + content-addressed discovery cache (`discover-sig.sh`). Headline leak plugged.

🎛️ **Orla:** Tier map already aggressive — write-relay-status/quota/gaming-log/release = haiku; discover/integrate = sonnet; only execute/review/hard = strong. Integrator cheapening closed (id:c563). Model-tier lever **saturated**; remaining is raw prompt bytes.

🔭 **Otto:** Proxy splits into (a) measurement-proxy — dominated by on-disk `usage` (killed 2026-06-03, zero-perturbation transcript wins); (b) mutation-proxy — the only variant that could cut spend, = the deferred request-mutation N=2 branch.

😈 **Riku:** Mutation-proxy has three independent killers — (1) can't beat Anthropic 0.1× server-side caching, can't cache across distinct subagent conversations; (2) stripping skeleton the agent must obey = editing the spec mid-flight (orphan-worktree risk, id:a4e9/8b1f); (3) shared `ANTHROPIC_BASE_URL` ⇒ can't route only cheap agents + out-of-harness billing = ToS tripwire. N=2 fails again.

✂️ **Petra:** Proxy fails N=2 — Consumer 1 "reduce skeleton tokens" is served by prompt-byte trimming; Consumer 2 "general token reduction" also served by trimming. No consumer where a proxy is the cheapest tool. Defer again, sharpened trigger: **request-mutation with a named consumer**.

🏗️ **Archie:** Real bytes are the per-spawn inline strings — `unitPrompt` (~lines 850-863) re-embeds the full id-tagged guardrail litany every dispatch, partly DUPLICATING `executor-contract.md` the agent already loads.

**User decision (proxy):** Gate proxy spike (id:e905) on the chidiAI model-degradation test as trigger+vehicle; framed strictly as an observation instrument, NOT a token-reduction lever. Record the reverse link in chidiAI's TODOs.

### Block 2 — three user questions (mechanization, cache-fill, push state-diagram)

🏗️ **Archie on (b) cache-fill:** id:c3a6 cache reuses verdicts for unchanged repos (zero shards when `changed.length===0`, relay-loop.js:634); pool refills across rounds from cached-ready verdicts. Residual: `discover-prelude` (relay-loop.js:528, sonnet) fires **unconditionally every round** — runId/take/peek/list/sig. Not touched by id:c3a6.

🎛️ **Orla on (c) push state-diagram:** Work agents already return `routine_open` (relay-loop.js:432) + `review_me_count`, but DON'T seed the cross-round cache. After the pool works a repo its sig changes → next round a shard re-classifies the exact repo the executor just finished and already knows the verdict of. Push-seeding `discoverCache[repo]` (recomputed bash sig + agent-known verdict) → cache HIT → shards shrink to externally-changed repos only. Under-invalidation (stale push-seed masking a real external change) is the failure mode to guard.

🎛️ **Orla on (a) mechanize via stricter ledgers:** Biggest finding = `writeRelayStatus` (relay-loop.js:205-247) is a **haiku agent running purely fixed shell** — peek/burn/write/events — a shell-runner spawned only because the Workflow script can't exec shell (id:6e9d constraint). Carries ~40 lines of fixed recipe re-sent every round. Same for `release` (~1077), `gaming-log` (~1051), `quota` (~908), `inject-take` (~1162). Lever: wrap each recipe in a named script → prompt collapses to a one-line invocation (~90% payload cut, zero judgment touched).

😈 **Riku guardrails:**
1. Measure first — id:c3a6 changed the denominator; no post-fix `relay-econ.py` run (id:9cb1 gates all levers).
2. Push-seed THINS discovery, can't eliminate it — external changes (human commits, origin advancing, /meeting writing ROADMAP, injected units) still need the sig-cache poll; **fail-open** must be preserved (under-invalidation is the one hazard class CLAUDE.md explicitly names).
3. Don't over-formalize ledgers — plaintext+git-diff is a deliberate value (CRDT meeting rejected SQLite), `classify.sh` advisory-only by design; mechanize bookkeeping, never the judgment core.

🔭 **Otto:** Even best-case a proxy is a measurement/degradation instrument reducing **zero** billed tokens; riding chidiAI is clean because that harness's job IS observation. Token caching economics: Anthropic 0.1× is already the floor; no proxy can undercut it, and a mutation proxy can't cache across distinct subagent conversations anyway.

**User decision (skeleton):** Spec both L1+L2 as TODO items, measure-gated on id:9cb1. L3 (prelude downgrade) folds into id:9cb1's annotation. L4 (unitPrompt trim) likewise gated and specced.

## Decisions

- **Proxy = no skeleton-reduction value; deferred and gated on the chidiAI model-degradation test (WIP).** Re-point id:e905: trigger = chidiAI degradation work; reuse that harness as the spike vehicle if/when it fires; framed strictly as an observation instrument, **explicitly NOT counted as a token-reduction lever**. Record the reverse link in chidiAI's TODOs too (cross-repo). *Out of scope:* any standing proxy, request-mutation/compression in the live path, treating a proxy as a token reducer.
- **Skeleton-reduction program = four levers, ALL gated on the id:9cb1 post-c3a6 re-measure** (one pool run + `relay-econ.py` to size scaffold% against the changed denominator). No build before the re-measure confirms scaffold% justifies it. *Out of scope:* any tier change to work agents; over-formalizing TODO/ROADMAP/REVIEW_ME beyond script-consumed markers; mechanizing the adjudication core.
  - **L1 thin-glue (biggest, most certain):** wrap each shell-runner agent's fixed recipe (`writeRelayStatus` 215-246; `release` ~1077; `gaming-log` ~1051; `quota` ~908; `inject-take` ~1162) into named scripts so the per-spawn agent prompt collapses to a one-line invocation. Shell-runner agent stays (engine can't exec shell); only its token payload shrinks. Zero behavior change. <!-- id:0d31 -->
  - **L2 push-seed discoverCache:** post-integrate, recompute `discover-sig.sh` for the just-worked repo and store `{sig, agent-known verdict}` (from `routine_open`/`review_me_count`) into `state.discoverCache` → next round is a cache HIT, no re-classifying shard for pool-touched repos. Keep the sig-cache as the out-of-band poll; **fail-open** (an external change between rounds must still re-classify — under-invalidation is the hazard to test). <!-- id:c855 -->
  - **L3 prelude cost (fold into id:9cb1):** evaluate downgrading the unconditional per-round `discover-prelude` (sonnet→haiku — it's pure glue, no judgment) + thin its instruction block (L1 applies). Annotate id:9cb1.
  - **L4 unitPrompt guardrail trim:** move stable every-agent guardrails that DUPLICATE `executor-contract.md` out of `unitPrompt`'s inline string; keep only variable bits (repo/branch/worktree/runId/verdict one-liner) + items the agent can't get from the contract file. <!-- id:2895 -->

## Action items
- [ ] **L1 thin-glue script refactor** — wrap shell-runner recipes (`writeRelayStatus`/`release`/`gaming-log`/`quota`/`inject-take`) into named relay scripts; per-spawn glue-agent prompts collapse to one-line invocations. Files: `relay/scripts/relay-loop.js` + new recipe scripts. Gated on id:9cb1. Test: glue-agent prompts ≤ N lines + invoke a named script; behavior unchanged; relay-econ.py scaffold% before/after. See `docs/meeting-notes/2026-06-18-0727-relay-skeleton-token-reduction.md`. <!-- id:0d31 -->
- [ ] **L2 push-seed discoverCache from work-agent returns** — seed `state.discoverCache[repo]` post-integrate with recomputed sig + agent-known verdict. Gated on id:9cb1. Tests: (a) repo worked round N served from cache round N+1 when only the pool touched it; (b) external change between rounds still re-classifies (fail-open preserved). See `docs/meeting-notes/2026-06-18-0727-relay-skeleton-token-reduction.md`. <!-- id:c855 -->
- [ ] **L4 unitPrompt guardrail trim** — de-duplicate `unitPrompt` inline guardrails against `executor-contract.md`; keep only variable bits inline. Gated on id:9cb1. Test: contract rules intact to agent; inline string shrinks. See `docs/meeting-notes/2026-06-18-0727-relay-skeleton-token-reduction.md`. <!-- id:2895 -->
- [ ] **Annotate id:9cb1** (ROADMAP.md) — its post-c3a6 re-measure is the gate for L1/L2/L4 and scopes L3 (prelude downgrade/thin). Reuse existing id:9cb1.
- [ ] **Re-point id:e905** (TODO.md) — proxy spike trigger = chidiAI model-degradation test; measurement-only, not a token reducer.
- → routed to chidiai inbox: relay proxy spike (dotclaude-skills id:e905) is gated on / can ride chidiAI's model-degradation test harness; record the link in chidiAI's TODO. See `docs/meeting-notes/2026-06-18-0727-relay-skeleton-token-reduction.md`. <!-- routed:fc0b -->
