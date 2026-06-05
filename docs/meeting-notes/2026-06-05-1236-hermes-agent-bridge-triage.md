# 2026-06-05 — hermes: agent ↔ meeting-skill ↔ Claude Code subscription (triage)

**Started:** 2026-06-05 12:36
**Session:** e25ec41d-948e-40f7-9568-e2468f231d6c
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🎛️ Orla (multi-agent orchestration / model-tier cost economics — re-onboarded)
**Topic:** Triage the `hermes` TODO stub — define what it is, whether it's warranted now, and (if deferred) its reopen trigger and natural home.

## Surfaced discoveries
- [2026-06-05 dotclaude-skills] Honcho eval note: Honcho's Claude Code MCP integrates with OpenCode, OpenClaw, **Hermes** — agents operating at harness level, orthogonal to skill files. `hermes` + agent-persona-separation flagged as same "external-state family" to fold into a meeting-rpg agent-infra wave. (see `docs/meeting-notes/2026-06-05-1213-honcho-memory-eval.md`)

## Agenda
1. What IS hermes? Pin a working definition by decomposing the three live interpretations.
2. Is any version warranted now, or is the honest move record-and-defer?
3. If deferred: what is the reopen trigger and the natural home?

## Discussion

### Agenda 1 — What IS hermes?

🏗️ Archie: Hermes = messenger god → literal reading is a *bridge*. Three things could sit in the arrow: (1) cost-arbitrage bridge running external/autonomous agent inference through the CC subscription seat; (2) autonomous *participant* — agent calls /meeting, answers prompts, runs unattended; (3) clean external-agent API surface (the broker) so frameworks invoke/observe meetings. Not the same project.

🎛️ Orla: Not even the same *layer*. (3) is IPC topology — already 80% built (broker `/event`, `/question`, `/await`, `/events`). An external agent is just another subscriber that can POST `/response`. (2) is orchestration policy — decision authority + human veto. (1) is a billing/transport question with a landmine.

😈 Riku: The landmine: the CC subscription is an interactive-developer seat with usage limits and terms that frown on driving automated/headless fleets. If hermes-cost-bridge = "point a non-Claude agent at my Max seat to dodge API billing", that's a ToS question that plausibly kills (1) before any box is drawn. Min evidence to change my mind: a current Anthropic terms clause explicitly permitting programmatic/agent use of the subscription.

⚙️ Sage: Two distinctions. (a) "AI agent" is overloaded — Claude Code itself already runs the skill. "agent ↔ meeting skill" might mean a Claude Code *subagent* (Agent tool) or headless `claude -p` driving `/meeting` — fully in-harness, no ToS issue, reuses broker. (b) Interpretation (3) is mostly *done*; broker treats all subscribers symmetrically. Only genuinely new work = the *policy* layer (who decides) + the *transport* question (the ToS minefield).

✂️ Petra: Scope knife. We're in triage. N=2 test: name two *current real* consumers needing hermes today. I can't name one — meeting-rpg is the only agent-infra consumer and it's mid Phase-2 polish. Deliverable = a crisp recorded taxonomy, not a chosen architecture.

🏗️ Archie: hermes = "bridge that lets a non-interactive driver participate in a meeting." **Axis A (transport/identity):** in-harness (CC subagent / headless `claude -p`) vs out-of-harness (external framework + separate billing). **Axis B (authority):** observer-only / answers-some-prompts / autonomous-with-veto / unattended. Interpretation (1) = the only cell crossing out-of-harness *and* subscription-billed → Riku's landmine cell.

🎛️ Orla: That 2-axis framing is the useful artifact. The in-harness column has *no* arbitrage — a CC subagent already costs your seat. "claude code subscription" only has teeth in the out-of-harness column = the ToS cell. The appealing part (free inference) and the fraught part are the *same* part.

😈 Riku: Push to the defensible core if you want to block it — but Tobias may want the full taxonomy kept live with a ToS tripwire rather than a pre-block. Leave (1) ambiguously inside hermes and someone (you, in 3 months) builds it without checking the terms.

**→ Decision 1 (Tobias): "Full taxonomy, nothing blocked."** Record the complete 2-axis taxonomy with all cells — including out-of-harness/subscription-billed — as open, equally-live options. The ToS question is *deferred and flagged*, not used to pre-block the cost-arbitrage cell.

### Agenda 2 — Is any version warranted now?

✂️ Petra: Build-now needs: (a) a real present consumer, (b) design non-obvious enough that deferring loses info, (c) cost of waiting > cost of building. All three negative. (a) zero current consumers — meeting-rpg is mid portrait-polish + token-savings gate (1/3 pilots). (b) the taxonomy *is* the non-obvious part and we've captured it. (c) waiting is free — broker already exists; integration is days not weeks.

🎛️ Orla: Orchestration-economics — an autonomous driver only earns its keep when there's a *queue* of meetings worth running unattended. Meetings are currently bespoke + high-stakes; you *want* turn-by-turn presence. Unattended-driver value is flat until meeting volume rises.

🏗️ Archie: Record one thing as *already-shipped*, distinct from "hermes the project": broker is a clean multi-subscriber API. Contract for any external driver = subscribe `/events`, POST `/response` to answer, optionally POST `/event` to inject. Stops a future session re-litigating IPC.

😈 Riku: Accept defer — but "nothing blocked" must not become "nothing flagged." Condition: the artifact carries an explicit precondition on the out-of-harness/subscription-billed cell — "MUST verify current Anthropic subscription terms permit programmatic/agent use BEFORE any implementation in this cell." A tripwire, not a block.

⚙️ Sage: Defer is the *right* default — hermes is in the external-state family the honcho note already named: Honcho (memory), hermes (agent runtime), agent-persona-separation (dialogue gen). Building hermes in isolation fragments any future agent-infra wave.

✂️ Petra: Converged — record-and-defer; taxonomy captured; broker/API noted as shipped; cost cell carries Riku's ToS tripwire.

**→ Decision 2 (Tobias): "Record-and-defer (full)."** No code this session.

### Agenda 3 — Reopen trigger and natural home

⚙️ Sage: Home = meeting-rpg (agent-runtime + broker already live there); dotclaude-skills keeps the record.

🎛️ Orla: Trigger = demand-pull. Three qualifying shapes: (a) you want to run a *queue* of low-stakes Class-3 meetings unattended; (b) meeting-rpg multiplayer/Phase-4 needs a non-human participant (same broker socket); (c) an external agent framework lands in your stack for unrelated reasons and asking it to observe/answer is near-free.

😈 Riku: Tripwire restated to survive out of context: "If reopened work targets the **out-of-harness + subscription-billed cell**, the FIRST gate is a citation from the then-current Anthropic subscription terms confirming programmatic/agent use is permitted. No code in that cell before that citation." In-harness cells carry no such gate.

🏗️ Archie: SHIPPED (no reopen): broker transport — multi-subscriber `/event`, `/question`, `/await`, `/events` SSE, `/response`. DEFERRED: (1) the *driver*; (2) the *authority policy*. Reopen starts at (1)+(2), not "design an API."

✂️ Petra: PRIMARY trigger (demand-pull): "a concrete non-interactive driver needs to participate in a meeting." SECONDARY (piggyback): "an agent framework or the honcho/agent-persona-separation wave opens in meeting-rpg, making hermes near-free to fold in."

🎛️ Orla: Bundles cleanly with honcho — both could reopen together as one agent-infra wave.

**→ Decision 3 (Tobias): "Decouple from honcho wave."** hermes reopens on its *own* demand-pull trigger, independent of the honcho/agent-persona-separation bundle. Home = meeting-rpg; reopen is *not* gated on a shared wave. The honcho note's secondary "(b) fold with hermes" pointer is now one-directional: honcho may opportunistically piggyback hermes, but hermes does not wait on honcho.

## Decisions

- **D1 — Definition (full taxonomy, nothing blocked):** hermes = "a bridge that lets a non-interactive driver participate in a meeting." **Axis A (transport):** in-harness (CC subagent / `claude -p`) vs out-of-harness (external framework + separate billing). **Axis B (authority):** observer-only / answers-some-prompts / autonomous-with-human-veto / unattended. All cells live, none pre-blocked. *Out of scope:* choosing an architecture now.
- **D2 — Record-and-defer (full):** No build this session. Zero current consumers; broker transport already shipped; autonomous-driver payoff flat until meeting volume rises. **SHIPPED:** broker multi-subscriber API — `/event`, `/question`, `/await`, `/events` SSE, `/response`. **DEFERRED:** (1) the *driver*; (2) the *authority policy*. *Out of scope:* re-designing the IPC/API.
- **D2-tripwire — ToS gate, cell-specific:** If reopened work targets the **out-of-harness + subscription-billed cell**, the **first gate** is a citation from the then-current Anthropic subscription terms confirming programmatic/agent use is permitted. No code in that cell before that citation. In-harness cells carry no such gate.
- **D3 — Reopen trigger + home (decoupled):** **Home** = meeting-rpg. **Record** stays in dotclaude-skills. **Trigger (standalone, demand-pull):** a concrete non-interactive driver needs to participate — shapes: (a) queue of unattended Class-3 meetings; (b) meeting-rpg multiplayer non-human participant; (c) external agent framework already in stack. **Decoupled from honcho/persona-separation wave** — hermes does not wait on that bundle; honcho may piggyback hermes, not vice-versa. *Out of scope until reopen:* driver, authority policy, out-of-harness billing (+ D2-tripwire).

## Action items

- [ ] **hermes — recorded as record-and-defer (2026-06-05).** 2-axis taxonomy: Axis A [in-harness CC-subagent/`claude -p` vs out-of-harness external framework] × Axis B [observer→unattended]; all cells live, none pre-blocked. Broker transport already shipped; deferred = driver + authority policy. **ToS tripwire:** out-of-harness + subscription-billed cell requires Anthropic-terms citation before any code. **Reopen trigger (standalone):** concrete non-interactive driver needs to participate (unattended Class-3 queue / meeting-rpg multiplayer / external agent already in stack). Home = meeting-rpg; record = dotclaude-skills. See this note. <!-- id:5c31 -->
