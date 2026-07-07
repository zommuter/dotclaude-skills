# 2026-07-07 — Opus quality vs. exhaustion/load: observational disappointment-mining (id:5fc6)

**Started:** 2026-07-07 18:43
**Session:** 345d3c04-98ef-4f26-a7bf-e43923fd3047
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 📊 Cal (calibration/UQ), 🔭 Otto (observability)
**Topic:** Is Anthropic silently degrading Opus quality as a function of global load — and how (if at all) do we mine our own transcripts for disappointment events + correlate them with time-of-day/load without generating folklore-at-scale?

## Surfaced discoveries
- [2026-06-17 dotclaude-skills] The 2026-06-17 degradation investigation already killed "conclude degradation from n=4 anecdotes" as a self-anchored prior; the controlled cold probe (id:dba3) is the instrument of record, not human anecdote.
- [2026-06-16 project_manager] The Grand-Truth "measure certainty → gate the action → degrade gracefully" primitive is the native lens for "how certain must we be before acting on a quality suspicion?" — and its assertion-layer home (chidiAI) already curates a failure-case corpus.

## Prerequisite reality (setup findings)
- `tools/model-probe.sh` + battery BUILT (id:c345, done 2026-06-17); **`~/.claude/logs/model-probe.jsonl` is EMPTY** — zero seed runs.
- id:23e9 (seed + close dba3) is GATED on the `claude-probe` OS user (id:d0c0, `useradd`/sudo — forbidden for a relay child) → dba3 sits `[HARD — decision gate] route:human`, stalled. This meeting does **not** touch that stall.
- id:903a three-axis extractor: **NOT built** (5fc6 proposed to reuse it as substrate).
- id:e3c0 (cold re-pose probe), id:241c (status check): not run.
- Ground truth that DOES exist: `~/src/chidiai/docs/cases/` = **12 hand-curated, timestamped, severity-tagged failure cases** (the "offenders"), replayable via `chidiai seed-cases`; `~/src/claude-diary/quota/quota-samples.jsonl`; `relay/scripts/relay-burn.sh`. chidiAI TODO id:3eb6 frames chidiAI as the intended **home of the model-degradation test harness**.

## Agenda
1. Dependency/sequencing: 5fc6 reuses the 903a extractor (not built) and rides the dba3 stream (stalled). Build the extractor here, or block behind the stall?
2. The hard core — disappointment detection: how to label "user dissatisfaction" from `.jsonl` transcripts, given FP/FN and the LLM-judge circularity?
3. Confound stack / measurement validity: time-of-day correlation adds the same (worse) confounds. Decision-relevant or folklore-at-scale?
4. Lever + scope: is "schedule apex work off-peak" a live lever? Minimum viable slice; what's out of scope.
5. Disposition of 5fc6 vs dba3/903a.

## Discussion

### Agenda 1 — dependency / sequencing

🔭 **Otto:** The 903a extractor is a pure `.jsonl` reader — zero tokens, no OS user; transcripts are on disk. 5fc6's stream (1) just adds a second label source (mined disappointment) alongside 903a's supplied-error labels. So the *extraction* is UNBLOCKED even though dba3 is gated — the stall is the cold-probe *seed*, not the mining.

🏗️ **Archie:** One script reads `bf9dd9e5.jsonl` et al., emits `(ts, turn_index, cum_input_tokens, gap_since_prev, label)`; `quota-samples.jsonl` + `relay-burn.sh` supply the load axis for free. 903a = the `label=supplied-error` special case; 5fc6 generalizes `label` to include `mined-disappointment`. No token spend for the mining pass.

😈 **Riku:** "Unblocked" conflates extraction with interpretation. Extraction is free; interpretation isn't — with no seeded probe there's no serving-side baseline, so any time-of-day peak can't separate Anthropic-under-load from our-own-behaviour-varying-by-hour. We'd ship a correlation engine whose output is uninterpretable until dba3 unstalls.

📊 **Cal:** The two streams measure different things. Probe = "worse at a FIXED task, blind to time." Mining = "WHEN is the user disappointed." A disappointment peak at hour X is equally compatible with (a) model degraded, (b) harder tasks scheduled then, (c) user tireder then, (d) longer sessions run then (context fatigue — the axis the 2026-06-17 note isolated). Mining alone can NEVER confirm load-degradation; its honest role is a hypothesis generator that RETARGETS the probe cadence to flagged hours.

✂️ **Petra:** Name the lever before authorizing anything. If the only unlocked action is "run the probe at peak hours," we can't take it until dba3 unstalls anyway. Seed the real instrument first; let mining be a cheap add-on that retargets cadence — not a "correlation verdict" built against an empty log.

**[Zommuter — decision on Agenda 1]:** Mine now, output = retarget list. Build the zero-token extractor/miner against existing on-disk data; its ONLY output is a hypothesis/retarget list (candidate peak hours + per-event table). Any degradation verdict stays gated on the seeded probe (dba3).

### Agenda 2 — disappointment-detection method

🔭 **Otto:** Three tiers, cheapest first. (1) STRUCTURAL — label-free events on disk: permission-deny, git-revert of a claude-authored commit, explicit re-do/"undo", a corrective user turn right after an assistant edit. (2) LEXICAL — negative-sentiment keyword hits. (3) SEMANTIC — LLM-judge. Tier 1 is highest precision-per-cost, no model call.

📊 **Cal:** The label is the whole ballgame — evaluative-labeling, so verify-the-verifier ([[feedback-no-unearned-evaluative-labels]]). Two confounds baked into the label: task difficulty (more corrections on hard tasks) and user state (terser when tired). The killer: an LLM-judge on the suspect tier is CIRCULAR — a degraded model grading its own degradation, itself degrading at the peak hours under study. Prefer a label that is cheap, time-blind, and not model-quality-dependent to compute. Structural is closest.

😈 **Riku:** Keyword miner drowns in FPs ("no, keep it as is") and misses silent re-dos (FN). "Next turn reverts/corrects the immediately-preceding assistant action" is the highest-precision proxy but still conflates model-error with user-changed-mind. Emit surrounding turns; hand-audit a sample for precision BEFORE any aggregate is trusted.

🏗️ **Archie:** Reuse the 903a `.jsonl` walk + `label_source` param. On-disk structural events: permission-deny; corrective-regex user turn within N turns of an assistant edit/commit; git-revert of a claude-authored commit (cross-refs diary — expensive, defer). Ship (deny + corrective-turn) for v1 with surrounding-turn context per event.

✂️ **Petra:** N=2 for the extractor generalization holds (903a supplied-error + 5fc6 mined-disappointment). Scope the label method to ONE tier for v1. LLM-judge out (circular + expensive); lexical a gated fast-follow.

**[Zommuter — decision on Agenda 2]:** Hybrid, and also consider chidiAI's progress and list of offenders.

*(Setup finding surfaced here: `~/src/chidiai/docs/cases/` = the 12-case offender corpus; chidiAI id:3eb6 = degradation-harness home.)*

📊 **Cal:** The chidiAI cases corpus IS the hand-audited ground truth Riku demanded — 12 human-verified, dated, severity-tagged events. So: bootstrap from the curated label set, use structural mining only for RECALL expansion. Each case's wall-clock timestamp is a zero-label-noise input to the time-of-day axis. Loud caveat: **n=12 cannot support a significance claim** (pilot heuristic: n≈10 can't distinguish rates within ~10pp). Deliverable = "events + hours + what the probe should test," never "evenings worse, p<0.05."

😈 **Riku:** "Hybrid" must not mean structural + lexical + LLM-judge + glue all at once. The escalation gate must be MEASURABLE: run the structural miner over the transcripts containing the 12 known cases, measure RECALL. Ship structural-only if recall is good; add lexical ONLY if recall against known cases is poor. LLM-judge stays out.

🏗️ **Archie:** Align schemas — miner emits candidate events in a shape that becomes / cross-references a chidiAI case; `(ts, time-of-day, context-depth, idle-gap)` attach per case. Reuse `seed-cases` + `.chidi.jsonl`, no parallel table.

✂️ **Petra:** Home question forced early. chidiAI owns the case-log and is the degradation-harness home (id:3eb6) → offender corpus + correlation table live in CHIDIAI; dotclaude-skills owns only the transcript-mining extractor (generalized 903a). Split by repo; don't duplicate the corpus.

🔭 **Otto:** Keeps the extractor honest — the dotclaude-skills side stays a pure zero-token `.jsonl`→events reader (reused by 903a + the chidiAI harness); interpretation/correlation/curation sits in chidiAI where ground truth lives.

**[Zommuter — decision on Agenda 2 specifics]:** Escalation = recall-vs-known-cases gate (add lexical only if structural re-finds too few of the 12; LLM-judge out). Home = split: extractor in dotclaude-skills (generalized 903a), corpus + correlation + curation in chidiAI (routed via inbox).

### Agenda 4–5 — lever, minimum slice, disposition

✂️ **Petra:** The lever "schedule apex work off-peak" is LATENT, not live — actionable only if a signal emerges AND the seeded probe confirms it (neither exists). v1's value = the substrate (generalized extractor + chidiAI seed corpus + retarget list), not a schedule change.

🔭 **Otto:** Free per-event from the transcript: time-of-day, day-of-week, context-depth, idle-gap. Free from our data: `quota-samples.jsonl` + `relay-burn.sh` (OUR load, not global). Anthropic status-page history = free read, honest generalization of 241c (one window → scan), a chidiAI-side correlation input not a blocker. Community reports out (noisy manual).

📊 **Cal:** Label the global-load axis as mostly UNOBSERVABLE — we cannot see Anthropic's global demand. "Global usage spike" degrades to status-page incidents (coarse) + our-own-load (a confound). State it in the deliverable so coincidence isn't read as causation.

🏗️ **Archie:** The extractor SUBSUMES 903a — its three axes + supplied-error label = the `label_source=supplied-error` special case. Build once (generalized `session-events` extractor), run on `bf9dd9e5` as 903a's smoke test.

😈 **Riku:** Keep gated things gated — e3c0 + probe seed (23e9) stay blocked on the claude-probe OS user; this meeting doesn't touch dba3's stall. The chidiAI-side item inherits the recall-gate + n-underpowered caveat as BUILD CONTRACT, not afterthoughts.

## Decisions

- **D1 — mine now, output is a retarget list not a verdict.** Build the zero-token transcript miner against on-disk data now; the extraction is unblocked (dba3's stall is the cold-probe *seed*, not the mining). Its ONLY output is a hypothesis/retarget list (candidate peak hours + a per-event table). Any "Opus is/isn't degraded under load" conclusion stays **gated on the seeded probe (dba3)**. *Out of scope:* a standalone degradation verdict from observational data.
- **D2 — hybrid label anchored on chidiAI's offender corpus; escalation is a measurable recall gate.** The 12 hand-curated, timestamped `~/src/chidiai/docs/cases/` are the precision-anchored ground-truth label set. Structural mining (permission-deny + corrective/re-do user turn within N turns of an assistant edit/commit; git-revert cross-ref deferred as expensive) provides **recall expansion**. Validation = run the structural miner over the transcripts containing the 12 known cases and measure recall; **add the lexical tier ONLY if recall against known cases is poor** (~< 2/3). *Out of scope:* LLM-judge (circular — a suspect-tier model grading its own degradation at the hours under study).
- **D3 — home split by repo.** dotclaude-skills owns the pure zero-token `.jsonl`→events extractor (generalized 903a, reused by 903a and the chidiAI harness). chidiAI owns the offender corpus, the recall validation, the time-of-day/load correlation table, and the case-curation — it already owns the case-log and is the intended degradation-harness home (id:3eb6). Routed via the inbox (`routed:e8eb`). *Out of scope:* duplicating the corpus in dotclaude-skills.
- **D4 — the extractor subsumes 903a.** Build ONE generalized `session-events` extractor: `label_source ∈ {supplied-error, mined-disappointment}`, emitting per-event `(ts, turn_index, time-of-day, day-of-week, context-depth=cum_input_tokens, idle-gap)` + surrounding-turn context. Run on `bf9dd9e5` as the first smoke test (reproducing 903a's supplied-error three-axis table). 903a folds into id:0711. *Out of scope:* a second narrow extractor.
- **D5 — v1 axes: free on-disk only; global load is mostly unobservable.** v1 attaches the four transcript-derived axes + our-own-load from `quota-samples.jsonl`/`relay-burn.sh` (explicitly labeled a confound, not global truth). The Anthropic status-page-history scan (subsumes 241c: one window → scan) is a **separate small chidiAI-side step**, non-blocking. **Every correlation read carries the n-underpowered AND unobservable-global-load caveats.** *Out of scope:* community-report scraping.
- **D6 — the lever is latent; dba3's stall is untouched.** "Schedule apex work off-peak" is not actionable until a signal emerges and the probe confirms it. e3c0 (cold re-pose probe) and 23e9 (probe seed) stay gated on the `claude-probe` OS user; this meeting does not touch dba3's `route:human` stall.

## Action items

- [ ] **Build the generalized `session-events` extractor** (dotclaude-skills, `tools/`). `label_source ∈ {supplied-error, mined-disappointment}`; structural disappointment signals = permission-deny + corrective/re-do user turn within N turns of an assistant edit/commit (git-revert cross-ref deferred). Emits per-event `(ts, turn_index, time-of-day, day-of-week, context-depth, idle-gap)` + surrounding-turn context; zero-token, reads on-disk `.jsonl`. Smoke test: run on `bf9dd9e5` reproducing 903a's supplied-error three-axis table. Hermetic `tests/test_*.sh`. **Subsumes id:903a.** <!-- id:0711 -->
- [ ] **[chidiAI — routed]** Build the model-degradation offender-corpus + recall-validation + time-of-day/load correlation harness consuming the dotclaude-skills extractor (id:0711). Seed from `docs/cases/` (12 offenders, `seed-cases`); recall gate decides lexical tier; LLM-judge out. Correlation table on `{ts, time-of-day, day-of-week, context-depth, idle-gap, our-own-load, status-page-state}`; status-page-history scan subsumes dotclaude id:241c. **Mandatory build contract:** n-underpowered (no significance claim) + global-load-unobservable caveats; output = per-event table + probe-retarget list, NOT a degradation verdict (gated on seeded probe dba3). Ties chidiAI id:3eb6 + relay-proxy dotclaude id:e905. → routed to chidiai inbox <!-- routed:e8eb -->
- [ ] **Annotate id:903a as folded** into the generalized extractor (id:0711) in TODO.md (+ the ROADMAP dba3 sub-item note). <!-- id:0711 -->
- [ ] **Annotate id:241c** — status-page scan generalized + subsumed by the chidiAI degradation harness (`routed:e8eb`); the one-window 2026-06-16 check remains a valid free step. <!-- id:0711 -->
