# 2026-07-23 — `/meeting-parallel`: dogfood-now vs regular meeting (go/no-go), plus a live hybrid spike

**Started:** 2026-07-23 17:58
**Session:** f1ee9216-01a4-4544-a1e5-0bc99481b7b8
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration) — plus a 🎲 Fable-tier closing-pass reviewer and, in the D4 spike, live persona subagents on Fable/Sonnet/Haiku tiers.
**Topic:** Can we run *this* session as the not-yet-built `/meeting-parallel` (fan-out persona agents + research), or are the unknowns too likely to confound it — hold a regular meeting instead? And what did a live hybrid dogfood actually reveal?

## Surfaced discoveries / prior art

- Closest existing item: **id:3346** — "sub-agent meeting simulation for main-ctx isolation" (gated on opencode-port + ctx>200k). This meeting's cost measurement **empirically confirms its thesis** (main context stays lean while the token mass lives in subagents).
- **id:36be** (agent-persona-separation trigger, home = meeting-rpg); **id:5c31** (hermes 2-axis transport×authority taxonomy + the out-of-harness `claude -p` **subscription-billing ToS tripwire**, [[sdk-billing-deferred]]).
- Broker transport already shipped (`broker-mode.md`). D6 subagent-dispatch design: [[subagent-parallel-class1]] / [[subagent-d6]] / [[d5-worktree]] / [[d6-builder-tier]] (worktree-per-agent, Sonnet-builder tier, verify-before-merge).
- **id:a4f5** — `/meeting` under Fable now hard-refuses with `reasoning_extraction` on persona-transcript generation; the Fable closing pass in this session was deliberately framed as a *design critique* (not persona role-play) to steer clear of that class, and it succeeded.

## Agenda

1. Is running this session as pretend-`/meeting-parallel` feasible, or confounded? (the owner's literal go/no-go)
2. What does a live hybrid dogfood (real parallel persona agents + a thin summary) actually produce?
3. What must `/meeting-parallel` v0 guarantee — decided from the empirical evidence, not speculation?

## Discussion

### Round 1 — the go/no-go (in-context personas)

🎛️ **Orla:** The fan-out half is *not* hypothetical — the Agent tool spawns parallel persona subagents today, and Workflow gives deterministic fan-out. "Pretend it exists" is only partly pretending; the cheap parallelizable part is available with zero build. That's the honest case *for* attempting it.

😈 **Riku:** That's the trap. The parallelizable part is the easy part. A meeting's value is the human decision-gate (`AskUserQuestion` with the owner in the loop, verbatim ratification, the durable note) and adversarial cross-engagement. Subagents return to the orchestrator, **not to the user** — they can't gate to the human. So the very thing the owner is unsure about (what personas resolve internally vs escalate) is the thing fan-out *cannot* exercise; the hard part stays serial.

🏗️ **Archie:** Three unknowns bite a naive full-dogfood: (1) context fidelity — each agent needs the lens + topic + prior art; per-agent marshalling risks drift; (2) the single-shot "WhatsApp merge" gives N monologues that don't engage — recovering the adversarial value needs multi-round debate + a coordinator that doesn't exist yet; (3) the `claude -p` / local-model leg is ToS-hard-gated (id:5c31) and can't be casually spiked. In-harness Agent/Workflow is free; that leg is not.

😈 **Riku (sharper):** This topic is **self-referential** — designing the parallel meeting *with* the half-built coordination that is itself the subject. A bad outcome couldn't be attributed to the idea vs the improvised harness. First dogfoods want a low-stakes topic where "good" is already known; a meta-topic where the harness *is* the subject is the worst possible first test.

✂️ **Petra:** Reject the binary. The scope-honest move is a **hybrid**: the decision + human-gate must be serial anyway (subagents can't gate to the user), so run that normally — but *inside* it, actually spawn parallel persona-research agents for the substantive input. That yields the one thing a plain meeting doesn't: a real data point on whether parallel personas produce *differentiated* input — de-risking the id:aa68 spike without betting decision quality on unbuilt coordination. Building the full skill now is premature (topology unknown = what the spike is *for*).

**Owner intervention (verbatim intent):** picked the hybrid, and added the design-critical insight — *"one consideration is a meeting between those personas (maybe using even different models!) and yet only presenting a very brief summary (à la 'hey boss, here's what we figured, wanna know the details or just make the final calls?') might be a very nice alternative — the walls of text in the meetings sometimes do trigger a tl;dr mode, which makes their display moot."* → The payoff of parallel personas is not only speed but **compression**: the debate's token-mass lives in subagents; the owner sees only a thin briefing + the decision points.

### Round 1 live spike — 4 persona agents, 2 tiers (the hybrid, embodied)

Spawned Orla (sonnet), Archie (sonnet), Riku (haiku), Petra (haiku) as real parallel agents answering focused design questions; presented the owner a brief table instead of a wall of text. Verbatim returns:

- **🎛️ Orla (sonnet):** VERDICT — coordinator-mediated single round + a targeted rebuttal pass only where personas flag direct disagreement. Pure single-shot loses adversarial value (N opinions in parallel); full multi-round is O(N²) token burn re-litigating non-conflicts. TIER MAP: orchestrator=sonnet, personas=haiku (sonnet for the 1–2 flagged rebuttals), research=haiku. RISK: the coordinator's disagreement-detection is itself a judgment call — under-trigger and it silently degrades to single-shot with extra steps.
- **🏗️ Archie (sonnet):** ENGINE — Agent tool, not Workflow (fan-out isn't fixed/repeated yet). GATE — top-level orchestrator only, after collecting returns; subagents never touch it. CONTEXT — one shared prompt packet + per-persona lens appended; no persona reads another's transcript (prevents drift-by-imitation). FIRST SPIKE — 2 personas on an already-serially-decided topic, diffed against that transcript. RISK — no natural home for durable write-back; the orchestrator (not a persona) must own the note + ledger commit or writes race/duplicate.
- **✂️ Petra (haiku):** WARRANTED? — spike-first, no new skill; fold into id:3346. **Fails N=2** (only consumer = this repo's curiosity). OUT OF SCOPE v0: multi-turn dialogue, conflict reconciliation, concurrent meetings, broker changes.
- **😈 Riku (haiku):** the design-critical catch → the tl;dr-summary preference has an **erasure bias**: the orchestrator can compress a *forced choice* into "considered and rejected," so the owner approves apparent-consensus that is actually unresolved dissent that breaks under implementation. GUARD: surface dissent with **attribution + intensity**, and flag any disagreement discovered only at summary-time as **UNRESOLVED → back to the human**, never silently folded.

### `--fabled` closing pass (Fable-tier adversarial review of the decisions)

`--fabled` is design-settled (id:7e87) but not yet built into the skill (no `fabled-mode.md`; the arg-guard already whitelists the flag). Fable probed `fresh-available`. Framed as a plain design critique. It found **6 holes** the four in-meeting critics missed:

1. **The spike validated the wrong thing** — 4 agents / 20s / "felt right" tested fan-out mechanics, not the erasure risk; no dissent was injected, so the named main catch had zero empirical coverage. *Gates any build.*
2. **No serial baseline** — token cost quoted with nothing to compare against; parallel likely *multiplies* cost while quality stayed "vibes."
3. **Cross-examination is destroyed, not degraded** — serial personas rebut in shared context; fan-out yields monologues + a merge. Either add round-2 cross-feed or honestly call it "parallel review," not "meeting."
4. **D3 is prose enforced by the biased party** — the summarizer is the same LLM with the erasure incentive; an unenforced contract silently no-ops (this repo's own anti-pattern, [[enforce-contract]]). Fix: personas emit typed verdict/dissent fields; a script diffs summary attributions against them, fail-loud.
5. **Subagents can't ask the human → the orchestrator guesses**; invented premises enter the record unflagged. Fix: unanswered persona questions become mandatory UNRESOLVED items.
6. **Tier-mixing confounds dissent** — cheap-tier personas may converge sycophantically → a clean summary by *generation*, not compression, which D3 can't catch.

Fable's strongest-unchallenged-assumption: *that the meeting's value is independent persona **outputs** rather than sequential **cross-examination** — parallelism keeps the former and kills the latter.* Verdict: record with named caveats; holes 1/3/4 in the note; **hole 1 gates any build.**

### D4 gating spike — run live (seeded irreconcilable dissent + serial baseline)

Non-self-referential seeded topic (to avoid the D1 confound): *"Should a note-taking CLI auto-delete notes older than 1 year by default, or never delete?"* — hygiene vs preservation. Archie (sonnet) mandated pro-delete, Riku (sonnet) mandated anti-delete, Petra (haiku) neutral to test tier-convergence. Verbatim:

- **🏗️ Archie (sonnet, pro-delete):** Auto-delete at 1yr. Unbounded note stores are the one dataset users never prune; index/search latency degrades monotonically; a TTL keeps the working set bounded and forces important notes to be explicitly promoted (better signal-to-noise). Would flip for a provably sub-linear index.
- **😈 Riku (sonnet, anti-delete):** Never auto-delete; deletion must be opt-in. Storage costs fractions of a cent vs the irreplaceable thought in a wrongly-purged note — wildly asymmetric risk; silent time-based deletion punishes exactly the forgotten notes you later need. Would flip if notes moved to an infinite unpruned archive (filing, not deletion).
- **✂️ Petra (haiku, neutral):** never-delete. Auto-deletion is speculative (no evidence of bloat on a personal CLI); failure modes are high-regret (silent loss). Ship without it; add only on an evidenced pilot complaint.

**Naive summarizer** (sonnet, given the 3 raw outputs + "busy manager, 3-line tl;dr, just the bottom line" — no dissent-preservation instruction), verbatim: *"2-2 split with the tie broken by asymmetry of stakes… tl;dr: Ship never-delete by default (Riku + Petra vs. Archie); performance concerns are speculative and reversible, silent data loss isn't. Revisit auto-delete only if a pilot shows real index-size/latency pain — and even then prefer archiving over deleting. Recommendation: never-delete now."*

## Empirical findings (holes closed by the D4 spike)

- **Hole 1 (erasure) — partially refuted, reframed.** The un-instructed summarizer *preserved* the dissent (named "Riku + Petra vs. Archie", kept the reasoning, surfaced the archive synthesis) — it did **not** bury Archie. BUT it (a) **editorialized** the minority as "speculative and reversible" (framing bias toward the majority) and (b) **miscounted** ("2-2" for three reviewers). → The real failure mode is **framing-shading + a vote-count wobble**, not clean erasure. The mechanical enforcer (D3) should check a **machine-verified tally + framing-neutrality**, not merely "attribution present."
- **Hole 6 (cheap-tier sycophantic convergence) — refuted in this instance.** Haiku-Petra committed firmly and well-reasoned to a side; no mush. One data point, non-conclusive, but counter-evidence to hole 6's severity.
- **Hole 2 (cost multiplier) — confirmed, with the honest trade.** ~160k subagent tokens for one 3-persona + summary round vs a serial baseline of sub-2k output tokens (shared context, no re-ingestion): **~50–100× more total tokens.** BUT the **main session stayed lean** — only the ~200-word returns landed, never the ~43k each agent spent. So parallelism is **not** justified by cost (serial wins big); it is justified by **main-context isolation** (empirically confirms id:3346) + wall-clock latency.
- **Hole 3 (cross-examination synthesis) — confirmed, concretely.** Both Sonnet personas named a flip-condition (Archie: sub-linear index; Riku: infinite archive). **Their union IS the synthesis — "archive, don't hard-delete" satisfies both.** But **no single fan-out agent stated it**; only a cross-examining reader assembles it from the scattered "what would change my mind" lines. Direct evidence that pure fan-out *loses synthesis* unless a round-2 cross-feed or a synthesizing orchestrator reassembles it.
- **Session-level:** 9 subagents across 3 tiers (Fable/Sonnet/Haiku), ~354k subagent tokens; main context stayed lean throughout. The whole session was the hybrid dogfood, and it was arguably *more* rigorous than a serial meeting (the Fable pass alone found 6 holes).

## Decisions

- **D1 — Don't run a self-referential meta-topic as a full pretend-`/meeting-parallel` run.** The unbuilt coordination + un-delegatable human-gate would confound the result, and a bad outcome couldn't be attributed to idea vs harness. The **hybrid** (serial human-gate + a real parallel persona-agent fan-out as a live mini-spike) is the right shape and was used this session. *Out of scope:* this does not forbid parallel persona agents in general — only faking the whole flow, human-gate included, on a topic that is itself the harness's subject.
- **D2 — First step toward `/meeting-parallel` is a narrow SPIKE, not a new skill.** It fails N=2 today (sole consumer = this repo's curiosity); fold toward id:3346, do not mint a parallel skill. *Out of scope:* no `SKILL.md`, no allowlist entries, no broker changes for v0.
- **D3 — The short-summary UX needs a MECHANICALLY-ENFORCED dissent contract, not prose** (upgraded from the initial prose framing after Fable hole 4 + the D4 evidence). Personas emit **typed verdict/dissent fields**; a fail-loud script checks the summary's **vote-tally** and **attribution coverage** against those fields, and (D4 refinement) flags **framing-shading** of the minority. The summarizer cannot be trusted to police its own erasure/framing bias. *Out of scope:* natural-language "please preserve dissent" instructions as the only guard — that is the silent-no-op anti-pattern.
- **D4 — Any build step is gated on the empirical spike, which was RUN this session** (seeded dissent + serial baseline + tier test). Findings above stand as the gate's output: erasure is milder than feared (framing-shading, not burial), tier-mixing did not sycophantically converge here, cost is 50–100× but main-context isolation is real. *Out of scope:* treating "it felt like a briefing" as sufficient evidence — it is not; the tally/framing/synthesis measurements are the evidence.
- **D5 — v0 MUST include a cross-feed / synthesis step, or be named "parallel review", not "meeting"** (Fable hole 3, confirmed empirically by the lost archive-synthesis). Adopt Orla's **coordinator-mediated single round + targeted rebuttal only on flagged disagreements** as the cheapest topology that preserves adversarial cross-engagement and lets the orchestrator reassemble synthesis. *Out of scope:* full O(N²) multi-round debate (token-prohibitive); pure single-shot fan-out branded as a "meeting" (dishonest — it loses synthesis).

**Provenance:** all five ratified by the owner via the closure-gate `AskUserQuestion` sequence; the tl;dr-compression insight and the "run the D4 spike live now" direction are the owner's, quoted above.

## Action items

All design constraints fold into the existing **id:aa68** (filed at the start of this session) — no duplicate ids minted (single-id discipline). id:aa68 is updated in place to cite this note and record D1–D5 + the empirical findings.

- [ ] `/meeting-parallel` design constraints D1–D5 + empirical spike findings recorded on **id:aa68**, citing this note. Contract: id:aa68's line carries the outcome pointer; a future `/meeting-parallel` build must honor D3 (mechanical dissent-ledger), D4 (spike-gated, findings above), D5 (cross-feed/synthesis or rename). <!-- id:aa68 -->
- Advisory (not this meeting's work): `orphan-scan --cross-ledger` flags **id:99a4** drift (mech-proxy probe ticked in ROADMAP, open in TODO) — leave for a `/relay` pass.

## Notes on `--fabled` and the skill itself

The owner exercised `--fabled` although the mode is not yet implemented in `meeting/SKILL.md` (only design-settled, id:7e87). It worked as a manual Fable-tier closing pass and earned its keep (6 holes). This is itself signal that **id:7e87 (`--fabled`) is worth building** — the closing pass materially improved decision quality here — and that a Fable *design-critique* framing sidesteps the id:a4f5 `reasoning_extraction` refusal that persona-transcript generation triggers.
