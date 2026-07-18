# Meeting-Note Format

Used for design decisions that need multiple viewpoints before committing to code.

## Personas

| Name | Role | Lens |
|------|------|------|
| 🏗️ **Archie** | Architect | Knows the code; proposes architecturally sound solutions; anchors claims in file paths and line numbers |
| 😈 **Riku** | Devil's advocate | Names specific risks; applies rules mechanically; pushes back until the proposal survives scrutiny |
| ✂️ **Petra** | Productivity | Enforces scope; applies the N=2 rule; names what is explicitly out of scope |

**Emoji rule:** Always prefix persona names with their emoji in every output — attendees line, discussion exchanges, AskUserQuestion attribution. Never omit the emoji.

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
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity)
**Topic:** one sentence

## Surfaced discoveries
Bullet list of `discoveries.md` entries mentioned at meeting start as relevant to the topic.
Omit section if no discoveries were surfaced. Format: `- [YYYY-MM-DD <project>] one-sentence finding`

## Agenda
Numbered list of questions the meeting will resolve.

## Discussion
Named exchanges. Each speaker owns a viewpoint; they can be corrected but not abandoned
without argument. File paths and line numbers are cited when code is discussed.

## Decisions
Bullet list. Specific enough to serve as an implementation spec.
Each decision names what is explicitly out of scope.
On Fable-class runs: prepend a `**Decision provenance:** "…"` line quoting the user's verbatim ratifying prose (one line covers the whole session if all decisions were ratified under one protocol).

## Action items
Checklist. Each item names the session, the file, and the contract
(what a future test would verify).
```

## Class 2 template (planning record — no meeting)

Class 2 dispatches (no-arg mode step 5) produce a **planning record**, not a persona meeting. Use this template instead of the Class 3 format above. Same path/naming convention (`<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md`); structurally distinct so citations aren't misleading.

```
# YYYY-MM-DD — Short title

**Started:** YYYY-MM-DD HH:MM
**Session:** <captured $CLAUDE_SESSION_ID>
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** one sentence

## Context
Why this work was scheduled / what TODO item it addresses.

## Plan
The approach taken (explore → design → present, native plan-mode flow).
Reference key files, patterns considered, and why the chosen approach was picked.

## Implementation findings
What surfaced during implementation: surprises, test results, deviations from plan.
Omit if implementation hasn't run yet (design-only Class 2).

## Decisions
Bullet list — same shape as Class 3. Specific enough to serve as an implementation spec.
Each decision names what is explicitly out of scope.

## Action items
Checklist — same shape as Class 3. Each item names the file and the contract.
```

**Key differences from Class 3:**
- `**Mode:**` replaces `**Attendees:**` — makes the absence of a meeting structurally unambiguous.
- No `## Discussion` — that heading implies persona dialogue that did not happen.
- `## Plan` + `## Implementation findings` replace `## Discussion` as the narrative body.
- `## Decisions` and `## Action items` are identical in shape to Class 3 (so tooling and cross-citations work).

**Content flow:** Synthesise the plan file content (no fresh summary from scratch). The plan file is left to Claude Code's auto-cleanup — no skill-level move or delete.

## Interactive mode

Meetings run interactively with the user participating turn-by-turn.

### Harness-class gate (check once at meeting start)

Read your own model identity from the environment block.
- **Fable-class** (`claude-fable-*`): use the **Fable inline-prose protocol** below for ALL decision points — never pair visible transcript text with a same-turn tool call.
- **Sonnet / Opus / Haiku** (all other models): use the default **same-turn `AskUserQuestion` protocol** further below (unchanged).

The end-of-meeting `AskUserQuestion` prompts (steps 3–5) follow the same gate: on Fable, replace them with inline-prose numbered prompts; on all other harnesses, use `AskUserQuestion` as written.

### Plan-mode gate (check once at meeting start — governs EVERY `EnterPlanMode`/`ExitPlanMode` in the skill, subject-mode + Class-2 + Class-3)

Read your own model identity from the environment block (the same read as the harness-class gate). It decides whether the skill's `EnterPlanMode`/`ExitPlanMode` steps run **at all** (id:fc0f):

- **Opus-class (`claude-opus-*`) or Fable-class (`claude-fable-*`) — SKIP plan mode.** Do NOT call `EnterPlanMode` or `ExitPlanMode`; run the meeting / planning in normal mode. Rationale: the session is already at the strong tier, so plan mode's only surviving live benefit — the `/opusplan` Sonnet→Opus tier switch — cannot apply here; and plan mode's read-only guard would block a session that holds **background executors** from integrating their branches (the 2026-07-17 cost). The discussion is emitted as visible chat (§Interactive mode) and the meeting note is the durable record, so the plan file adds nothing.
- **Sonnet-class (`claude-sonnet-*`) or Haiku-class (`claude-haiku-*`) — USE plan mode** exactly as the SKILL.md steps specify. Under `/opusplan` this upgrades the design/discussion phase to Opus (the whole point of keeping it); under a plain Sonnet/Haiku session it is harmless and preserves the read-only guard.

Read every SKILL.md `EnterPlanMode`/`ExitPlanMode` step as "…**if this gate says to**." A skipped `EnterPlanMode` means its paired `ExitPlanMode` is skipped too. When plan mode is skipped, the "no file edits / no implementation mid-meeting" constraints (SKILL.md §Constraints) still bind — as prose, exactly as they already do in every non-plan-mode part of the skill.

### Fable inline-prose protocol

At each decision point:
1. Emit the complete, verbatim transcript chunk for the current agenda item as the turn's **FINAL text** — no tool call after it (so it renders on Fable).
2. End that same message with the decision framed as a **numbered markdown list** of implication-driven options (same content `AskUserQuestion` options carry): embedded tl;dr first, 2–4 options, recommended option marked, an explicit `N. Other — freeform` line (the tool's auto-"Other" is absent).
3. The user answers in prose in the next turn. Quote their answer **VERBATIM** in the meeting note as the `**Decision provenance:**` ratification marker for that decision (see Decisions template below).
4. Do **NOT** call `AskUserQuestion` at meeting decision points on Fable.

### Default protocol (Sonnet / Opus / Haiku)

1. The skill accumulates the meeting transcript in the plan file turn-by-turn during plan mode.
2. At each natural user decision point (roughly every 4–8 exchanges), the skill emits the transcript chunk **and** calls `AskUserQuestion` **in the same response** — never end a turn on bare prose and send the question in a subsequent turn:
   - Outputs the relevant transcript chunk as visible chat content (not a summary), so the user sees the discussion before the options appear.
   - Immediately (same message) poses the decision via `AskUserQuestion` with:
     - **Embedded tl;dr** — standalone-readable summary of the state of play in 2–3 sentences before stating the choice.
     - **3 implication-driven options** — derived from the personas' reasoning, not generic pro/con pairs. Each label 1–5 words; description explains what it commits to and what it defers.
     - **Recommended option first**, labelled "(Recommended)" when the personas converge.
     - Freeform "Other" is provided automatically by the tool.
3. The skill continues the meeting in the next turn based on the user's answer, appending to the transcript.
4. When all agenda items reach decisions, the skill calls `ExitPlanMode`, then writes the final transcript to `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md` and completes the remaining end-of-meeting steps.

## Effort estimate units

**Rule:** Express implementation effort in **session-equivalents** (`~1s`, `~2s + 200k tok`). Never use calendar days or weeks for implementation effort. Calendar dates are reserved for observation windows and external deadlines only.

**v0 rule-of-thumb table** (seeded 2026-05-08, 7 sessions; revise after 10 logged meeting sessions — see `~/.claude/logs/meeting-cost.log`):

| Task class | Median sessions | Median ~tokens | 90th pct |
|---|---|---|---|
| Logger / hook (script + settings reg) | 1 | 60k | 2s / 130k |
| Skill spec edit (format.md / SKILL.md only) | 0.3 | 20k | 1s / 50k |
| Cross-repo design + impl | 2 | 240k | 4s / 500k |
| Pure design meeting | 1 | 100k | 1.5s / 180k |

To look up the actual cost of a past session: `bash ~/.claude/skills/meeting/cost-of.sh <session-id>`

## User profile and persona pre-emption

Profile file: `~/.claude/skills/meeting/user-profile.md` (loaded at setup step 6).

**Pre-emption rule:** A persona may insert "I suspect you'd argue X" only when ALL THREE hold:
- `Pre-emption-eligible: yes` on the profile entry
- `Confidence: med` or `high`
- the current proposal directly contradicts the profile fact

Riku handles most pre-emption; Archie/Petra/Sage rarely do.

## When to call a meeting

- A TODO item's scope is ambiguous (plugin vs. core, Phase 2 vs. Phase 3).
- A design decision has a non-obvious trade-off that would be questioned later.
- Two or more plausible approaches exist and the wrong choice is hard to reverse.

Do **not** call a meeting for:
- Bug fixes with a clear root cause.
- Adding a test or doc for an already-decided feature.
- One-liner changes.
