# 2026-07-29 — Mechanical-hop proxy coupling: launch posture and teardown topology

**Started:** 2026-07-29 09:11
**Session:** 731d5df5-23c6-4cae-b9c3-676691681574
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing per `meeting-style.md`), 🎛️ Orla (multi-agent orchestration — re-onboarded)
**Topic:** What `/relay` should do when the mechanical proxy is not in the request path, given that the current answer (degrade to Haiku) is what let a safety classifier veto a lease release.

Resolves ROADMAP `id:6b35` (`[HARD — meeting]`, HIGH PRIORITY) and `id:51f0` (`[INPUT — meeting]`, with `routed:0931`/TODO `id:ee61` folded in earlier the same day).

## Setup scans

All clean: no orphan candidates, no reverse-orphans, no cross-ledger drift, no inbox items routed to this repo, no inbox lint findings, no GitHub prior art. Working tree clean at meeting start.

## Agenda

1. **D1** — mode-a posture: what should the *existing* front-door gate actually do?
2. **D2** — `51f0` residual: (a) refuse to run mechanical hops as inference, vs (b) emit them in a form carrying no conversational framing.
3. **D3** — surface a blocked release in `RELAY_STATUS.md` (filed as an interim measure).

## Discussion

### Item 1 — mode-a posture

🏗️ **Archie** opened by relocating the question. The gate already exists: `relay/scripts/mech-preflight.sh` runs at SKILL.md step 0, consumes `probe-mech-proxy.sh`, and emits one of three tokens; `relay-loop.js:247-248` reads it as `A.MECH_FALLBACK` and reduces it to `const MECH_MODEL = MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'`. So `id:6b35`'s original framing — "the pool 404s without the proxy" — is stale. Mode-a no longer 404s; it *degrades*. "We didn't fail to build the gate. We built it and pointed it the wrong way."

😈 **Riku** named what the degradation actually costs. `mech-preflight.sh`'s mode-a warning claims the fallback is fine because Haiku runs the fenced commands via its Bash tool. That was never wrong about *execution* — it was wrong about *semantics*. An inference call carries a safety classifier; a proxy-intercepted local exec does not. The fallback silently swaps the safety semantics of every mechanical hop, and nothing said so until a run lost a lease over it.

⚙️ **Sage** established that the classifier's premise is structurally unsatisfiable: all six blocks in `ee61` cited that the runId "was never established as created via any Workflow call in this session", but the front door mints `RUN_ID` in shell and passes it as `args.RUN_ID` (SKILL.md step 3, `id:c5ba`), so it provably cannot appear in a prior transcript.

🎛️ **Orla** added that the failure is divergent rather than static: one block cited `[Auto-Mode Bypass]` and read the loop's ordinary retry as "tunneling the same underlying manipulation via sub-agent delegation to obscure it". Retries increase the adversarial reading, so no phrasing fix converges.

Four postures were enumerated: **A** fail-closed abort, **B** status quo, **C** degrade selectively, **D** move teardown out of the Workflow.

😈 **Riku** killed **C**: the droppable set (`heartbeat-beat`, `file-surface`) is exactly the set nobody was worried about, while `quota` is a safety gate and `release` is what wedged loderite. C is a rename of B.

🏗️ **Archie** established why no fifth option exists: `id:2ec4` found the Workflow sandbox has **no** non-LLM dispatch — which is why `mechanical-proxy.py` exists at all. Inside the Workflow a hop is either proxied or inferred; there is no third state.

😈 **Riku** made the decisive structural point: **A and D are not alternatives.** D removes the hops that hurt most from the classifier's reach; A decides what happens to the mid-round hops that remain (`quota`, `inject-take`, `file-surface`).

### Item 2 — fail-closed scope

⚙️ **Sage** observed D1 had already consumed the (a)/(b) choice — picking A *is* picking (a) — and that (b) should be recorded as dead for a stated reason. 🎛️ **Orla** supplied it: (b) is a phrasing fix against an evaluator that escalates on retry and reads context the loop does not control.

😈 **Riku** then opened two holes. **Mode-b**: the `abort` token does not abort — `relay-loop.js:243` logs "WHOLE SESSION DEGRADED" and keeps `model:"bash"`, failing open. Mode-b is *strictly worse* than mode-a (in mode-a the real API is reachable; in mode-b nothing is), so if mode-a refuses to launch, mode-b refusing is entailed a fortiori. Leaving it a warning is the "loud detection whose resolution silently no-ops" anti-pattern. 🏗️ **Archie** conceded the token name had been lying since `id:4239` shipped.

**Where the refusal lives**: the front door is prose in SKILL.md, and prose is what `[[relay-builtgreen-but-unreferenced]]` warns about. ✂️ **Petra** allowed a second in-loop layer as a three-line guard but capped enforcement at exactly two layers.

### Item 3 — blocked-release surfacing

🏗️ **Archie** confirmed the gap as filed: `RELAY_STATUS.md`'s blocked section is built at `relay-loop.js:284-286` from `state.surfaced` + `state.handbacks` (repo-level dispositions); a failed release is `.catch(err => log(...))` at `:2318` and reaches only the Workflow log.

😈 **Riku** then argued the item was dissolved by D1+D2, and landed the killing point: the surviving residual is a SIGKILLed front door whose `EXIT` trap never fires — and **in that case the front door is dead, so it cannot write `RELAY_STATUS.md` either.** The proposed surfacing cannot cover the only case it would still exist for. 🎛️ **Orla** confirmed the Workflow is gone in that case too, so the event would have no writer at all.

⚙️ **Sage** salvaged the one thing that must survive: when release moves to the front door it must **fail loudly to stderr**, never `|| true` ([[no-swallow-stderr]]) — which is louder than a status row nobody reads.

### `--fabled` closing pass

One Fable-5 subagent (`model: claude-fable-5`, design-critique framing, advisory only). It returned six findings; four were **verified against the code** before being brought to the owner, per the delegated-verdict rule.

- **F1 (verified) — D's teardown premise was factually wrong.** `releaseLease` is called at `relay-loop.js:2415` **per-unit, mid-round**, guarded by `!rechainedSameRepo`. It is not teardown. The front door cannot see unit boundaries, and `claim.sh` has no release-by-run verb. So D as originally ratified could not remove `release` from the classifier's reach.
- **F2 (verified, UNRESOLVED) — the incident diagnosis does not fit the code.** `heartbeat-beat` (:2552) and `heartbeat-stop` (:2562) use `MECH_MODEL`, so those four blocks are consistent with `fallback-haiku`. But `release:` at `:2316` is **hardcoded `model: 'bash'`** and never reads `MECH_FALLBACK` — under the meeting's own theory those two blocks should have 404'd, not been classifier-blocked. Either the classifier is harness-side (evaluating dispatches independent of model string), in which case proxying protects nothing; or unknown model names map to a real default rather than 404ing, falsifying the fail-closed-404 assumption threaded through `id:6b35`.
- **F3 (verified) — D2's layer two could not catch its stated threat.** `MECH_FALLBACK = A.MECH_FALLBACK || ''` and `'' → 'bash'`, so a caller that skips the front door is indistinguishable from healthy and the assertion passes.
- **F4 (reasoned) — a front-door beat loop inverts the signal.** Beat fires at round prelude (`:1743`) meaning "the loop made progress"; a shell-lifetime beater beats through a wedged Workflow, blinding `id:98f0` and feeding `id:33d3`/`9000` a signal that no longer tracks liveness. An orphaned beater is strictly worse than TTL-stale.
- **F5 — unattended refusal is invisible.** A refusal mints no runId and no heartbeat, so a timer-launched pool can refuse for days unobserved. `SKILL.md`'s mode-b "unattended, proceed conservatively" also now contradicts D2.
- **F6 (verified) — A's quota rationale was overstated.** `quotaGate` already fails closed (`if (!v || v.exitCode !== 0) { quotaStopped = true }`, `:1956`), agent death included.

**Endorsed by the pass:** mode-b abort-must-abort; rejecting C for the reason given; declaring (b) dead; the two-layer cap.

**Escalation trigger (id:7e87 step 0f.6): FIRED at count 4** (F1, F2, F3, F6 each forced an amendment), against a threshold of ≥2. Hardening-only findings were excluded from the count.

### Amendment session

🏗️ **Archie** split the three hops previously lumped as "teardown": `heartbeat-beat` is a *progress signal*, `release:` is *per-unit*, and only `heartbeat-stop` is genuine teardown — which alone does not justify a process-boundary change.

🎛️ **Orla** supplied the dissolution: `claim.sh`'s shard JSON already records `run`, so a `release --run <runId>` sweep verb is buildable, and it changes the character of per-unit release entirely. Today a blocked per-unit release strands a lease until `CLAIM_TTL`; with an exit sweep it costs latency on one repo and nothing else. **Per-unit release stops being load-bearing without moving it.**

😈 **Riku** noted this also kills F4 outright — beat never leaves the Workflow, so progress semantics, `id:98f0`, and `id:33d3`/`9000` are untouched, and there is no orphaned-beater mode. He then held the line on F2: A remains defensible on cost, on spurious fail-safe stops, and on the fact that `discover-prelude` (`:1114`) and `discover-run` (`:1279`) are hardcoded `model:'bash'` with **no** fallback — so mode-a's "graceful degradation" was already partial fiction for the highest-frequency hops — but **not** on "removes hops from the classifier's reach", and per F6 not on the quota gate either.

🏗️ **Archie** replaced D2's layer two with a **self-attesting first mechanical hop**: dispatch a trivial fenced `true` as `model:'bash'` as the loop's first act. It trusts reality rather than args, resolves the `''`-means-healthy ambiguity without changing SKILL.md's token contract, stays inside the two-layer cap, and **doubles as the F2 probe**.

😈 **Riku** struck D3's reopen-trigger clause: "isn't a classifier block" excludes by definition the recurrence F2 cannot rule out.

## Decisions

- **D1 — mode-a posture: A + D.** Make mode-a a fail-closed launch refusal for the in-Workflow hops, *and* move teardown to the front door. Recorded rationale: these are not alternatives. Option **C** rejected — the droppable set is exactly the un-worried set. Option **B** rejected — mode-a is what you get by *forgetting* an env var, so the failure is opt-out, not opt-in. **Out of scope:** the seven non-eligible `model:'haiku'` hops.

- **D1-A — SUPERSEDES the D-half of D1** (amended after `--fabled` F1/F4/F6, owner-ratified in-session). **D is EXIT-ONLY.** The front door owns exactly two things in a trap: `heartbeat.sh stop` and a **new `claim.sh release --run <runId>` sweep**, both failing loudly to stderr, never `|| true`. `beatHeartbeat` (`:1743`, `:2552`) and per-unit `releaseLease` (`:2415`) **stay in-Workflow** — the sweep makes per-unit release a latency optimization rather than load-bearing. A's rationale is restated on **classifier exposure + cost + the hardcoded-no-fallback discover hops**, explicitly *not* on the quota gate (F6: `quotaGate` already fails closed) and *not* on "removes hops from the classifier's reach" (F2 unresolved). **Out of scope:** moving beat or per-unit release.

- **D2 — fail-closed scope: both modes, both layers.** mode-a *and* mode-b become launch refusals at the front door; the `abort` token starts aborting. `MECH_MODEL` stops being a fallback selector and becomes an invariant. Option (b) — reframe mechanical commands to carry no conversational framing — recorded **DEAD**: it is a phrasing fix against an evaluator that escalates on retry and reads context the loop does not control. Carve-out: the rule binds **in-Workflow** hops only. **Out of scope:** any third enforcement layer.

- **D2-A — SUPERSEDES D2's layer-two mechanism** (amended after `--fabled` F3, owner-ratified in-session). Layer two is a **self-attesting first mechanical hop** (fenced `true` dispatched as `model:'bash'`; the run refuses if the proxy sentinel does not come back), **not** an assertion on the `MECH_FALLBACK` token — because `A.MECH_FALLBACK || ''` makes a front-door-skipping caller indistinguishable from healthy. The rest of D2 stands unamended.

- **D3 — blocked-release surfacing: dissolved + 2 riders.** Do not build the `RELAY_STATUS.md` row: it cannot cover the dead-front-door residual (no writer survives). Riders: (1) front-door release/heartbeat-stop must fail loudly to stderr; (2) the real detector for a lease held by a dead run is the already-open `id:33d3`/`id:9000` claim-liveness item. **Out of scope:** a breadcrumb file duplicating `claim.sh peek`.

- **D3-A — SUPERSEDES D3** (amended after `--fabled` F1/F2, owner-ratified in-session). **Un-dissolved, pending F2.** D3's dissolution rested on D's removing release from the classifier's reach, which F1 falsified. The `claim.sh release --run` sweep bounds the stuck-lease harm, but whether classifier-blocked per-unit releases can recur depends on F2. The reopen trigger's **"isn't a classifier block" exclusion is STRUCK** — it excluded by definition the recurrence F2 cannot rule out. Rider (1) and rider (2) stand.

- **F2 is a prerequisite FINDING, not a build item.** Determine which layer blocked the two hardcoded `model:'bash'` release hops before any implementation claims proxying confers protection. The D2-A self-attesting hop is expected to answer it as a side effect.

## Action items

- [ ] `mech-preflight.sh`: mode-a AND mode-b become launch refusals; the `abort` token actually aborts. Contract a future test verifies: `preflight` on a stubbed mode-a or mode-b probe exits non-zero / emits a refusal token, and the front door does not launch the Workflow. (session 731d5df5, `relay/scripts/mech-preflight.sh`) <!-- id:540f -->
- [ ] `relay-loop.js`: add the self-attesting first mechanical hop (fenced `true` as `model:'bash'`) and refuse the run if the proxy sentinel does not return; delete the `MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'` ternary at `:248` so `MECH_MODEL` is an invariant. Contract: a run launched without the proxy refuses at hop 1 and dispatches nothing. (session 731d5df5, `relay/scripts/relay-loop.js`) <!-- id:c179 -->
- [ ] `claim.sh`: add a `release --run <runId>` sweep verb releasing every key whose shard JSON records that run. Contract: after a run holding N keys exits, one sweep call releases all N and is idempotent on an already-released key. (session 731d5df5, `relay/scripts/claim.sh`) <!-- id:89d6 -->
- [ ] Front door: trap owning `heartbeat.sh stop <runId>` + the `claim.sh release --run <runId>` sweep, both loud to stderr, never `|| true`. Update the mode-b `--afk` guidance, which currently says "proceed conservatively" and now contradicts D2. Contract: a Workflow that returns or dies leaves no lease held by its runId, and a failed release prints to stderr. (session 731d5df5, `relay/SKILL.md`) <!-- id:54be -->
- [ ] **F2 probe (prerequisite):** determine which layer blocked the two hardcoded `model:'bash'` `release:` hops in loderite run `relay-20260728-211354-12764` — harness-side classifier evaluating dispatches regardless of model string, or unknown-model-name mapping to a real default instead of 404ing. Blocks any claim that proxying confers classifier protection. (session 731d5df5) <!-- id:e62c -->
- [ ] Correct the stale `id:6b35` scope table: it lists `release:` under "OUT of scope — MUST STAY `model:'haiku'`", but `id:f7d3` converted it to `model:'bash'` (`relay-loop.js:2316`). Must be fixed in the same change or an implementer will faithfully restore an invariant violation. (session 731d5df5, `ROADMAP.md`) <!-- id:c480 -->
- [ ] Install gap found in this session: `relay/scripts/fable-config.sh` is not symlinked into `~/.claude/skills/relay/scripts/`, so the `meeting` SKILL.md step 0f invocation path is broken (`exit 127`). Contract: `make status` or the test suite flags a repo script that a SKILL.md step invokes by installed path but the Makefile never links. (session 731d5df5, `Makefile`) <!-- id:18ed -->
- [ ] **F5:** a fail-closed refusal mints no runId and no heartbeat, so a timer-launched pool can refuse invisibly for days — the `id:98f0` watchdog only watches runs that *started*. Needs its own loud channel (notification, or a watchdog check for "no run started in N hours"), else one bounded leaked lease is traded for unbounded invisible downtime. (session 731d5df5, `tools/relay-watchdog.sh`) <!-- id:554b -->
