# 2026-06-17 — Opus quality-degradation investigation (id:dba3)

**Started:** 2026-06-17 08:35
**Session:** 14477aed-3d6c-4ccd-8dfa-50048942bc5f
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 📊 Cal (calibration/UQ), 🔭 Otto (observability), ⚙️ Sage (skill-runtime — joined for invocation-path/ToS point)
**Topic:** Was Opus genuinely degraded the evening of 2026-06-16, or are we over-reading anecdotes — and what should we build from it?

## Surfaced discoveries
- [2026-06-17 dotclaude-skills] Relay discovery shards silently inherited the Opus session model (sibling prelude was sonnet) — a tier omission cost ~35% of relay spend; fix = pin + content-address discovery cache (id:c3a6). Shows recent, real model-tier mistakes in this codebase.
- [2026-06-16 project_manager] The "measure certainty → gate the action → degrade gracefully" primitive ("Grand Truth Project") recurs across the owner's projects — the native lens for "how certain must we be before acting on a quality suspicion?"

## Setup findings (pre-agenda)
- Evidence source: memory `opus-quality-degradation-20260616.md`; 4 incidents: (1) sloppy lightweight-tag handling after toesnail history rewrite; (2) confident-wrong "zkm-* on another machine" misdiagnosis; (3) over-engineered ~/.claude branch-split (2 user corrections); (4) weaker statistics output vs prior day.
- **Key confound:** the flagged session `bf9dd9e5` is 1213 lines / 2.4M tokens — genuinely very long. If all 4 errors are from this one session, that is n=1 in *sessions*, and cannot by itself separate a model-serving regression from long-context fatigue.
- The transcript is turn-indexed and already on disk → turn-clustering is a zero-cost, zero-perturbation test.

## Agenda
1. Is the signal real or a self-anchored prior over n=4 anecdotes? Minimum evidence that changes the conclusion?
2. Model-serving regression vs. long-context degradation — what cheap evidence discriminates them?
2b. Amendment: wall-duration vs context-length axis; silent-swap detectability?
3. What action does each conclusion unlock? Anything warranted NOW?
4. Disposition of id:dba3.

## Discussion

### Agenda 1–2: real signal vs. self-anchored prior; how to discriminate

🏗️ **Archie:** Most of this is auditable without spending a token. The session is on disk. If I plot error-turn vs. session position and they all sit in the back third, that's long-context degradation on the cheapest possible evidence. `relay-econ.py` artifacts are deterministic day-over-day, but they measure cost/structure not reasoning quality — weak signal on incident #4 only.

😈 **Riku:** n=4, really n=1 in *sessions*. With a single long session you cannot distinguish a model regression (which would also hit short, fresh sessions) from end-of-session context fatigue. Sampling is contaminated: the user already believed Opus felt off, then noticed errors. Minimum evidence: (a) a **short, fresh** Opus session today reproducing the same confident-wrong class → rules out long-context; or (b) an Anthropic status/model-version note for the window → confirms serving-side. Absent one, "Opus degraded" is unfalsifiable folklore.

📊 **Cal:** Textbook self-anchored prior. The measurement device is "a human noticing mistakes," conditioned on the hypothesis before sampling. n=4 gives a 95% interval wide enough to be compatible with "a normal bad day." Don't *conclude* from these four — calibrate the device instead: pick a signal readable blind to which day it came from, compare to baseline. Our own "measure certainty → gate the action" primitive applies here: certainty is low, so the gated action should be cheap and reversible.

🔭 **Otto:** Two zero-perturbation ground-truth sources already exist: the turn-indexed transcript and the econ artifacts. Turn-clustering is the highest value-per-cost test — falsifies long-context if even one of the four errors is early; supports it if all four are late. Anthropic status is the other free read. Run both before spending a fresh Opus token.

✂️ **Petra:** Name the lever first. If the only consequence is "be more careful in long sessions," that's free advice needing no audit. The one decision-relevant question is whether this changes relay tier policy — but id:c3a6 was Sonnet/Haiku tiering of discovery/integrator agents, orthogonal to Opus reasoning quality. Identify the lever before authorizing a 2.4M transcript audit.

**[Zommuter — decision on Agenda 1–2]:** Go with the fresh-session probe, escalate to full forensic only if the probe result warrants it. Also pull in yesterday's last big `/relay` session. Two extra hypotheses: (a) maybe not context-*length* but wall-clock *duration* — KV-cache rot, or some Anthropic "optimization" that degrades over a long-running session; (b) how likely is it Anthropic silently degraded the model while still labelling it Opus 4.8 — and can we even detect that?

### Agenda 2b: wall-duration vs context-length, and silent-swap detectability

🔭 **Otto:** Three separable axes for the four errors from the *same* artifact: (1) context depth — tokens-in-context; (2) elapsed wall time; (3) idle-gap before the error — proxy for server-side KV-cache eviction/rot. They're correlated in one long session but not identical: if errors track idle-gaps rather than depth, that points at cache rot, not "fuller context = dumber." No extra cost.

🏗️ **Archie:** Extract `(turn_index, cumulative_input_tokens, timestamp, gap_since_prev)` from both `bf9dd9e5.jsonl` and yesterday's last big `/relay` session, mark the four known error turns. Two sessions = n=2 *sessions* — cheapest attack on the "really n=1" objection. Same late-turn pattern in structurally-different relay work = corroboration; clean relay session = issue specific to the interactive evening.

📊 **Cal:** On silent-swap: almost certainly cannot prove it — no pre-suspicion fixed-task baseline exists, and a silent degrade under an unchanged model string leaves no label to catch. Weak signals: resolved model-id string (catches a *relabel*, not a silent degrade), tokens/sec shift (quantization swaps change server behavior), the status check. The rigorous answer exists only going forward — a **banked baseline**. Skip measuring now and we're equally blind next time.

😈 **Riku:** Four anecdotes, zero baseline — that's the real indictment. Accept the fresh probe as a *baseline-establishing act*. Guard it: fixed prompt stored verbatim, run cold, judged against the recorded incident, not vibes. Note: it can only *rule out* long-context (fail-fresh ⇒ context wasn't the cause); it can't *rule in* a serving regression.

✂️ **Petra:** Surviving scope: three-axis turn-cluster on two sessions (free) + one cold fixed-prompt probe re-posing incidents #2/#3 (small Opus spend) + status check (free). Full forensic stays out unless the cluster shows a decision-relevant pattern. The durable artifact is the banked probe, not a verdict on one evening.

**[Zommuter — decision on disposition]:** Build a standing probe. id:dba3 closes with the investigation finding plus the probe as the deliverable.

### Agenda 3–4: standing-probe design

🏗️ **Archie:** `tools/model-probe.sh <model>` (default `opus`). A versioned battery `tools/model-probe.battery.jsonl` of ~15–20 timeless deterministic items `{id, prompt, golden_regex}`. Each item runs cold — its own headless invocation — graded 0/1, appended to `~/.claude/logs/model-probe.jsonl`: `{ts, battery_version, model, item_id, pass, latency_s, out_tokens, tok_per_s}`. No LLM-judge.

🔭 **Otto:** Cold per item (measure the model, not session state) + capture tokens/sec every run — a quantization/serving swap often shows as throughput drift even when text looks unchanged. Only hedge against a silent same-label degrade; bank it from day one.

📊 **Cal:** Binary golden grading → pass-rate baseline. ~15–20 timeless items only resolves *big* regressions — which is all we care about. **Pre-register** the acceptance band before we have data so we can't move goalposts.

😈 **Riku:** Guards: version-stamp the battery (edits reset baseline); timeless items only; cadence is a bounded knob; require **2 consecutive** out-of-band runs before flagging; keep each prompt bare so we measure the model, not the harness.

✂️ **Petra:** Model-generic is a free flag; commit to running the load-bearing tiers. Out of scope: LLM-judge, dashboard, auto-rollback, long-context paired variant (v2), full 2.4M forensic.

### Amendment: tiers, frontend-metadata, and ToS/invocation-path

**[Zommuter — decision on probe scope]:** All three tiers (Opus + Sonnet + Haiku). Track the model's version number and any other frontend details that might silently change. Cadence: seed now, cron deferred. Concern: "are you using a `claude -p` call? Make sure we don't accidentally violate the ToS' harness clause."

🔭 **Otto:** Capture every frontend-visible field that could shift: resolved model-id string, system fingerprint/response headers, `claude --version`, account/quota tier, throughput. A relabel (id string moves) is the one swap we *can* catch for free.

⚙️ **Sage:** On `claude -p` — won't assert the exact clause from memory ("never answer ToS from recall"). Make the invocation path a **gated decision, not a baked-in call**: before shipping, verify the *current* Anthropic usage policy / Claude Code terms on low-volume non-interactive use. Two compliant shapes — **(A)** low-volume on-demand `claude -p` (subscription quota, harness-prompt-contaminated, least friction) or **(B)** raw Anthropic API (own key/billing, cleanest measurement). Deferring the scheduler already removes the riskiest shape. Gate it, don't assume.

😈 **Riku:** Build precondition: step 0 = "confirm path in-bounds"; write invocation as one swappable function so a later compliance answer never forces a rewrite. Record which path produced each sample.

✂️ **Petra:** One abstraction, two real consumers (A and B) — passes N=2, build it. No third path, no scheduler. ToS surface stays small.

## Decisions

- **D1 — id:dba3 disposition.** Run the bounded investigation (three-axis turn-cluster on `bf9dd9e5` + yesterday's last big `/relay` session; cold fixed-prompt probe re-posing incidents #2/#3; Anthropic status/version check for the 2026-06-16 evening window), then close id:dba3 with the finding AND a standing model-probe as the durable deliverable. Investigation expected inconclusive (no prior baseline); the probe is the real output. *Out of scope:* concluding "Opus is/isn't degraded" as fact from n=4.
- **D2 — probe shape + metadata.** `tools/model-probe.sh <model>` (default `opus`); versioned `tools/model-probe.battery.jsonl` of ~15–20 timeless deterministic items `{id, prompt, golden_regex}`; each item run **cold** via one headless invocation; deterministic 0/1 grading; append-only log `~/.claude/logs/model-probe.jsonl` with `{ts, battery_version, model, item_id, pass, latency_s, out_tokens, tok_per_s, model_id_str, fingerprint, cli_version, quota_tier}` — every frontend-visible field. *Out of scope:* LLM-judge, dashboard.
- **D3 — detection rule.** Pre-registered acceptance band (pass-rate floor + latency/throughput band), flag only on **2 consecutive** out-of-band runs. tokens/sec is the weak silent-swap hedge. *Out of scope:* auto-rollback.
- **D4 — three axes.** Turn-cluster extracts context depth, elapsed wall-time, idle-gap-before — so cache-rot (tracks idle-gaps) is separable from context-fatigue (tracks depth). Silent same-label swap: accepted as near-unprovable without a banked baseline; the probe is what makes the *next* such question answerable.
- **D5 — tiers + cadence.** Commit to **Opus + Sonnet + Haiku**. Cadence: **seed on-demand now, cron deferred**; cadence is a knob, no scheduler shipped.
- **D6 — invocation path GATED on ToS.** Do not hard-code `claude -p`. Step 0 of the build verifies the *current* Anthropic usage policy / Claude Code terms re: low-volume non-interactive use. Implement invocation as one swappable function — **(A)** low-volume on-demand `claude -p` (subscription) or **(B)** raw Anthropic API (own key). Default to A if terms permit; fall back to B otherwise. *Out of scope:* any automated/bulk scheduler until terms confirmed AND probe proven stable.

## Action items

- [ ] **Blocking pre-check:** confirm the probe's invocation path against current Anthropic usage policy / Claude Code terms (low-volume on-demand `claude -p` vs raw API). Record finding here. Build does not proceed on the wrong path. (dotclaude-skills) <!-- id:2d01 -->
- [ ] Build `tools/model-probe.sh` + `tools/model-probe.battery.jsonl` (~15–20 timeless items w/ golden regex) + append-only `~/.claude/logs/model-probe.jsonl` schema. Contract: cold per-item headless run; deterministic grading; battery-version + full frontend-metadata (model_id_str, fingerprint, cli_version, quota_tier, tok_per_s) stamped per log line; invocation-path as swappable function (shapes A and B). (dotclaude-skills) <!-- id:c345 -->
- [ ] Write `tests/test_model_probe.sh` — hermetic, `mktemp -d`, no network. Contract: grading, log format, battery-version propagation all tested offline. (dotclaude-skills) <!-- id:040a -->
- [ ] Three-axis cluster extractor: script that pulls `(turn_index, cum_input_tokens, ts, gap_since_prev)` from a session `.jsonl` and marks supplied error turns; run on `bf9dd9e5` + yesterday's last big `/relay` session. Contract: output a per-error table on all three axes. (dotclaude-skills) <!-- id:903a -->
- [ ] Run the cold fixed-prompt probe re-posing incidents #2 (zkm-* plugin location) and #3 (~/.claude branch-split) against fresh Opus; record pass/fail vs the recorded incident behaviour. (investigation step — human or executor) <!-- id:e3c0 -->
- [ ] Check Anthropic status/model-version for the 2026-06-16 evening window (free read). (investigation step) <!-- id:241c -->
- [ ] Pre-register the acceptance band + seed the baseline by running the probe on Opus + Sonnet + Haiku a handful of times; then close id:dba3 with the finding written into this note. (dotclaude-skills) <!-- id:23e9 -->
- [ ] Add `tests/test_model_probe.sh` with `# roadmap:` entry once the ROADMAP item is open. (dotclaude-skills) <!-- id:6ffe -->
