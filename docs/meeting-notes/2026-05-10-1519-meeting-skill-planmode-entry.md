# 2026-05-10 — Meeting skill: should EnterPlanMode fire earlier?

**Started:** 2026-05-10 15:19
**Session:** 3f1c211c-0a9f-4976-baed-0a3418533c8c
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing)
**Topic:** Should `/meeting` invoke `EnterPlanMode` at the very start of the skill (before setup / warrantability / audit) rather than mid-flow, partly to flip into Opus when "opusplan" mode is configured?

## Agenda
1. What is the actual problem? (Or: is this purely theoretical?)
2. Map the current EnterPlanMode call sites and what would shift if we moved them.
3. Weigh the Opus-mode-quality benefit against the workflow / dispatch-path costs.
4. Decision: keep current placement, move to start, or hybrid.

## Discussion

### Item 1 — What is the actual problem?

🏗️ **Archie:** Two motivations are bundled. Split them:
- **(a) Conceptual:** A meeting *is* a planning activity, so plan mode is the natural container.
- **(b) Mechanical:** If the user has plan mode wired to Opus (the "opusplan" pattern), entering plan mode earlier makes more of the meeting run on the stronger model.

These need separate evaluation. Conceptually clean ≠ mechanically beneficial.

⚙️ **Sage:** Confirming the mechanical layer — discoveries.md, 2026-05-08:
> A skill can call `EnterPlanMode` from within its own execution and the full plan-mode experience activates (model switch, plan file creation) as if the user had entered it manually.

So whatever the user has configured for plan-mode model switching WILL fire when the skill calls EnterPlanMode. The question is only *when* in the skill flow.

😈 **Riku:** Audit which phases actually benefit from model quality:

| Phase | Workload character | Opus benefit |
|---|---|---|
| Setup (steps 1–6) | Bash + Read tool calls | Negligible — tool-use, not reasoning |
| Warrantability check | Light judgment ("is this a bug fix?") | Small |
| Past-meetings audit | File scan + orphan detection | Small–medium |
| Classification (no-arg flow) | Class 1 vs 2 vs 3 judgment | **Medium–high** |
| Interactive meeting | Persona simulation, decision framing | **High** |
| End-of-meeting steps | File writes + AskUserQuestion prompts | Negligible |

The current design enters plan mode right before the highest-benefit phase. The marginal gain from earlier entry is concentrated in classification (no-arg only) and is small for the with-subject flow.

✂️ **Petra:** And let's name what's *not* the problem. There's no reported pain. The user is asking a design question, not reacting to a regression. We should be wary of designing for a hypothetical "Opus would be nicer here" without an instance of it actually mattering.

### Item 2 — Map the call sites

🏗️ **Archie:** Current call sites for `EnterPlanMode` in `skills/meeting/SKILL.md`:

1. **With-subject flow, step 3** — after warrantability + past-meetings audit, before the interactive meeting.
2. **No-arg flow, dispatch step** — only for Class 2 and Class 3 items. Class 1 (impl-ready) explicitly proceeds in *normal* mode.

If we move entry "to the start", which start?
- **(A)** Before setup (steps 1–6) — earliest possible.
- **(B)** After setup, before warrantability / classification.
- **(C)** Status quo for with-subject; move only for no-arg classification.

😈 **Riku:** Option (A) collides with Class 1 dispatch. Class 1 says "proceed to implementation in normal mode (no plan mode, no meeting)". An immediate ExitPlanMode + model-switch-back is wasted round-trip.

Option (A) also means setup runs under plan-mode constraints. Setup is read-only anyway, so nothing breaks — but the user sees "plan mode active" before the skill has decided whether a meeting is warranted. Semantically weird.

⚙️ **Sage:** Plan-mode mechanics worth noting:
- The plan file is created by the *skill* writing to a path the runtime suggests; EnterPlanMode itself doesn't auto-create it. So an early entry that ends in "no, this isn't meeting-worthy" doesn't necessarily orphan a file — but if the skill writes to the plan file during setup, it does.
- The system reminder at EnterPlanMode time enforces "DO NOT write or edit any files (except the plan file)". The meeting skill's setup is all reads — fine. End-of-meeting writes already require ExitPlanMode first; current design handles this.

✂️ **Petra:** Option (A) is also out-of-scope-creep on the user's question. They asked "would it make sense?" — yes/no, not refactor-brief. Naming consumers: classification quality (one place), warrantability check quality (one place). N=2 barely passes; cost of change is non-trivial.

### Item 3 — Trade-off

🏗️ **Archie:** Net assessment:

**Pros of moving entry to the start:**
- Modest reasoning-quality boost on classification + warrantability check
- Conceptual neatness ("meeting = planning")
- Single mental model: `/meeting` always runs in plan mode

**Cons:**
- Class 1 no-arg dispatch needs an awkward ExitPlanMode round-trip
- The "are you sure?" gate becomes weirder — already in plan mode, must exit if user backs out
- Risk of writing setup output to the plan file (noise; transcript starts later anyway)
- No reported pain; speculative benefit

😈 **Riku:** Counter-question: is "opusplan" actually how you run? If plan mode isn't wired to Opus on your setup, motivation (b) collapses entirely and the question reduces to motivation (a) — "neater?" — which alone doesn't justify a workflow change.

Pre-emption (per profile, *Empirical-pilot preference*, high confidence, eligible): you'd likely want evidence that current placement misses something — a meeting where classification was wrong, or where the warrantability check let through something that wasted a session — before swapping placement. Speculative quality wins are exactly the kind of thing your profile says to defer.

⚙️ **Sage:** One mechanical wrinkle: when EnterPlanMode is invoked, the runtime injects a long Phase-1-through-5 workflow reminder. The meeting skill *overrides* that workflow with its own persona-driven flow. Earlier entry means the user sees plan-mode-styled chrome (UI indicators, possibly a persistent banner) for setup steps that aren't really planning. Not broken, but disorienting.

✂️ **Petra:** N=2 verdict: keep the current placement. The two consumers (classification, warrantability) are real but small-stakes. The cost (Class 1 round-trip, semantic muddiness) is concrete. Defer until there's a logged instance of model quality biting one of those phases.

### Convergence

Status quo (current placement) survives scrutiny. The "even counterproductive?" half of the user's question lands on: yes, mildly counterproductive in the no-arg flow because of Class 1.

A *narrow* hybrid is possible: move entry to just before classification in the no-arg flow only, leave with-subject untouched. But this trades a small gain for added skill complexity (two entry points instead of one). Probably not worth it.

## Decisions

- **Keep current EnterPlanMode placement** in `~/.claude/skills/meeting/SKILL.md`:
  - With-subject flow: step 3 (after warrantability check + past-meetings audit, before interactive meeting).
  - No-arg flow: only on Class 2/Class 3 dispatch; Class 1 stays in normal mode.
- **Explicitly out of scope:** moving entry earlier (to the start, or to just-before-classification). Deferred unless evidence emerges that classification or warrantability quality bit on a non-Opus run.
- **Rationale captured here so it doesn't get re-litigated:** the highest-Opus-benefit phase (interactive discussion) is already covered by the current entry point. Earlier entry would force a Class 1 ExitPlanMode round-trip, complicate the "are you sure?" gate, and trade concrete workflow cost for speculative reasoning-quality wins.

## Action items
- None. No skill edits, no TODO additions. The recorded decision serves as a guard against re-asking the same question.
