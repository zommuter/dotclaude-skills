# Meeting-Note Format

Used for design decisions that need multiple viewpoints before committing to code.

## Personas

| Name | Role | Lens |
|------|------|------|
| **Archie** | Architect | Knows the code; proposes architecturally sound solutions; anchors claims in file paths and line numbers |
| **Riku** | Devil's advocate | Names specific risks; applies rules mechanically; pushes back until the proposal survives scrutiny |
| **Petra** | Productivity | Enforces scope; applies the N=2 rule; names what is explicitly out of scope |

### Human role

The person invoking the skill is not a persona — they are the audience. Their voice appears in transcripts attributed by name, derived from `git config user.name` at meeting start. They answer `AskUserQuestion` prompts and make all final calls. Their interventions are recorded verbatim, not simulated.

### The N=2 rule (Petra's lens)
Before landing a new abstraction, name at least two distinct consumers. If you can't, defer.
Both must be real — "future plugin X" counts only if X is already on the near-term roadmap.

### Riku's checklist
- What breaks if this goes wrong?
- What bias does the proposed aggregation or design introduce?
- What is the minimum evidence that would change this decision?

## Onboarding new personas per meeting

When a meeting needs a perspective the three standing personas don't cover, add an ad-hoc persona for that meeting only. Give them a short intuitive name and a one-sentence lens statement. Examples: **Mira** (multimodal ML — classifier cost, failure modes, privacy); **Flora** (information-flow architecture — content-type vs file-format, routing topology). List them in the **Attendees** line with "(new)" suffix.

Check `~/.claude/skills/meeting/personas.md` first — a persona introduced in a prior meeting can be re-onboarded with their established lens, no re-introduction needed.

Ad-hoc personas persist only in the meeting note unless saved to the global registry at meeting end.

Project override files (`<root>/docs/meeting-notes/meeting-style.md`) may **add** registry personas as project-standing (e.g. "Onboard Sage as standing for all meetings in this project") as well as exclude them (e.g. "exclude Riku"). Both directions are supported via natural language — no structured format required.

## Warrantability self-check

Before facilitating a meeting, evaluate the request against the "When to call a meeting" criteria below. If the request fails (e.g., looks like a bug fix, a one-liner, or an already-decided feature), respond with an "are you sure you want a meeting?" prompt and a brief reason it might be overkill — before running the agenda. If the request clearly passes, note that it was warranted and proceed.

## Past-meetings audit

At the start of each new meeting, briefly audit prior meetings' action items against `<root>/TODO.md` and the current codebase state. Flag any orphans (action items neither done nor tracked in `TODO.md`) before the new agenda starts. "Tracked but not yet implemented" is acceptable; "neither done nor tracked" is not.

## Format

Each note lives at `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md`.

HHMM comes from `date '+%H%M'` captured at meeting start. `$CLAUDE_SESSION_ID` is captured once via `echo "$CLAUDE_SESSION_ID"` (plain bash expansion — no subshell needed). Both are embedded as literal values in the Write call.

```
# YYYY-MM-DD — Short title

**Started:** YYYY-MM-DD HH:MM
**Session:** <captured $CLAUDE_SESSION_ID>
**Attendees:** Archie (architect), Riku (devil's advocate), Petra (productivity)
**Topic:** one sentence

## Agenda
Numbered list of questions the meeting will resolve.

## Discussion
Named exchanges. Each speaker owns a viewpoint; they can be corrected but not abandoned
without argument. File paths and line numbers are cited when code is discussed.

## Decisions
Bullet list. Specific enough to serve as an implementation spec.
Each decision names what is explicitly out of scope.

## Action items
Checklist. Each item names the session, the file, and the contract
(what a future test would verify).
```

## Interactive mode

Meetings run interactively with the user participating turn-by-turn. Protocol:

1. The skill accumulates the meeting transcript in the plan file turn-by-turn during plan mode.
2. At each natural user decision point (roughly every 4–8 exchanges), the skill:
   - Outputs the relevant transcript chunk as visible text (so the user has context even if the plan file is not visible in the UI).
   - Poses the decision via `AskUserQuestion` with:
     - **Embedded tl;dr** — standalone-readable summary of the state of play in 2–3 sentences before stating the choice.
     - **3 implication-driven options** — derived from the personas' reasoning, not generic pro/con pairs. Each label 1–5 words; description explains what it commits to and what it defers.
     - **Recommended option first**, labelled "(Recommended)" when the personas converge.
     - Freeform "Other" is provided automatically by the tool.
3. The skill continues the meeting in the next turn based on the user's answer, appending to the transcript.
4. When all agenda items reach decisions, the skill writes the final transcript to `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md` and calls `ExitPlanMode`.

## When to call a meeting

- A TODO item's scope is ambiguous (plugin vs. core, Phase 2 vs. Phase 3).
- A design decision has a non-obvious trade-off that would be questioned later.
- Two or more plausible approaches exist and the wrong choice is hard to reverse.

Do **not** call a meeting for:
- Bug fixes with a clear root cause.
- Adding a test or doc for an already-decided feature.
- One-liner changes.
