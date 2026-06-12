# 2026-06-12 — Fable-harness fix: transcript + AskUserQuestion same-turn pattern

**Started:** 2026-06-12 07:49
**Session:** 170a2b88-824c-4774-90f0-7396bf17c12a
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Fix the meeting skill's interactive decision-point protocol for Fable-class harnesses, where assistant text preceding a tool call in the same turn is not rendered to the user.

## Context

On `claude-fable-*` harnesses, only the turn's final text message (no trailing tool calls) is guaranteed visible. This breaks `format.md` §Interactive mode step 2 and `SKILL.md` subject-mode step 5, both of which require printing the verbatim transcript chunk AND calling `AskUserQuestion` in the same response. On Fable, the transcript is emitted then hidden — the user sees only the options.

First live failure: isochrone kickoff meeting 2026-06-11 (session 3f648b35; user saw zero persona output before the first question). Session workaround that worked end-to-end: inline-prose decision points — transcript as final turn text, options as a numbered markdown list, user answers in prose, answer quoted verbatim as `**Decision provenance:**` ratification marker.

TODO item was cross-repo mirrored from isochrone kickoff meeting note (no `id:` token) and was open in `dotclaude-skills/TODO.md` in the `## meeting skill` section.

## Plan

Fable-gated fix: detect harness class from the model identity in the environment block; apply inline-prose protocol only on Fable (`claude-fable-*`); Sonnet/Opus/Haiku keep the existing same-turn `AskUserQuestion` clickable UI. Three files edited:

1. **`meeting/format.md`**: added `### Harness-class gate` + `### Fable inline-prose protocol` subsections to `## Interactive mode`. Added `**Decision provenance:**` note to the Decisions template for Fable runs. Default (Sonnet/Opus/Haiku) same-turn protocol unchanged and clearly labelled `### Default protocol`.
2. **`meeting/SKILL.md`**: rewrote subject-mode steps 4 and 5 to reference the harness-class protocol in `format.md` instead of hard-assuming `AskUserQuestion`. Added a sentence to the broker γ-branch blockquote (preceding end-of-meeting steps 3–5) specifying that Fable replaces those `AskUserQuestion` prompts with inline-prose numbered prompts.
3. **`meeting/broker-mode.md`**: added cross-reference sentence to both fallback clauses (decision-point and end-of-meeting probe-fails) pointing to `format.md` §Harness-class gate.

## Implementation findings

- `broker-mode.md` did name `AskUserQuestion` explicitly in both fallback paths (lines 44 and 78) — the cross-ref sentence was needed.
- The Fable-harness fix TODO item had no `<!-- id:XXXX -->` (it was mirrored as a cross-repo item without minting a local ID); closed directly with `[x]` in TODO.md.
- All three files are P2-symlinked (`~/.claude/skills/meeting/*` symlinks → `~/src/dotclaude-skills/meeting/`); edits to the real files update the live skill immediately.

## Decisions

- **D1 — Fable-gated protocol.** Inline-prose decision points (transcript as final turn text + numbered options + prose answer quoted verbatim) on Fable-class only. Sonnet/Opus/Haiku keep same-turn `AskUserQuestion`. No universal protocol change. Out of scope: universal inline-prose, universal two-turn, programmatic harness-detection helper (env var / statusLine probe not needed — model self-identifies from env block).
- **D2 — Single source in `format.md`.** The harness gate and Fable protocol live in `format.md` §Interactive mode (loaded at every meeting on every harness); `SKILL.md` references it rather than restating.
- **D3 — `**Decision provenance:**` convention.** On Fable runs, each decision in the meeting note carries a verbatim quote of the user's ratifying prose; a single section-level line is acceptable when all decisions were ratified under one protocol (pattern from isochrone note line 121).

## Action items

- (none — item closed in-session; no follow-up needed)
