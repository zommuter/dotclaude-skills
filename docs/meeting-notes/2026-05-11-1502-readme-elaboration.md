# 2026-05-11 — Elaborate the meeting skill README

**Started:** 2026-05-11 15:02
**Session:** fef220e8-ef9e-4f40-97a8-1e0c791e60b5
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing)
**Topic:** Elaborate `meeting/README.md` — document the no-arg classification flow, show on-screen example output, add subject-mode walkthrough, extend persona intro.

## Agenda

1. Scope of "elaborate" — just no-arg + example output, or also persona lenses, subject-mode walkthrough?
2. No-arg presentation — how to show the 3-class dispatch flow?
3. Example output content — inline snippet vs links only?
4. Subject-mode walkthrough + persona lens presentation?

## Discussion

### Item 1 — Scope

🏗️ **Archie:** README is install-and-allowlist heavy with little on what running the skill feels like. The no-arg flow gets one bullet; persona scrutiny gets one parenthetical. Proposed: fill holes a first-time GitHub reader would hit — no-arg flow, subject-mode walkthrough, persona lenses, example output (current links + inline snippet).

✂️ **Petra:** Named gaps: no-arg (no class breakdown, no bucket-summary example), subject mode (no AskUserQuestion cadence shown), personas (bare names, no lens), effort estimates + overrides (advanced topics, readme-bloat). N=2 satisfied for the four core inclusions; effort/overrides/cost-of stay in deeper specs.

😈 **Riku:** Pre-empted on **drift aversion** — duplicating the no-arg flow narrative from SKILL.md creates a third copy to maintain. Defensible only if README shows the *user-facing view* (what appears on screen) rather than the *operational spec* (how the runtime executes). Complementary abstraction levels, not duplicates.

⚙️ **Sage:** README is not in the symlink loop — editing it has no live-skill consequences; it's pure GitHub-side publishing. Freedom to elaborate without runtime-drift concern.

**Decision:** Archie's 4-piece scope — no-arg flow (user-facing), inline bucket-summary snippet, subject-mode walkthrough with AskUserQuestion snippet, persona lenses in intro.

### Item 2 — No-arg presentation format

Options: (a) prose narrative, (b) class table only, (c) step list + class table.

Personas converged on (c). Riku: (b) hides the step order; (a) hides the structure. (c) is the only one that doesn't lie by omission. Drift risk mitigated by keeping the step list short and abstract. Date-triggered nuance omitted from README (SKILL.md owns it).

**Decision:** Step list (5 steps: read → classify → print → recommend+ask → dispatch) + 3-row class table.

### Item 3 — Example output content

Options: (α) links only (current state), (β) links + inline bucket-summary snippet, (γ) links + snippet + meeting-note header excerpt.

Petra: (γ) is N=2 but the second is a duplicate of what links already provide. Riku: same. Sage: the on-screen bucket summary is the genuinely new artefact; the persisted note links already carry the format example.

Snippet drawn from real items in this repo's `TODO.md`, labelled illustrative. Existing three meeting-note links unchanged.

**Decision:** (β) — inline illustrative bucket-summary snippet + keep existing links.

### Item 4 — Subject-mode walkthrough + persona lens

Walkthrough options: (p) step list only, (q) step list + inline AskUserQuestion snippet, (r) no walkthrough.

Sage: (q) earns its lines — the AskUserQuestion cadence is the most distinctive thing vs. a plain plan-mode flow. Riku: same drift-mitigation applies (label illustrative, keep short).

Persona lens options: (x) separate 3-row table, (y) bullet list per persona, (z) skip. Riku: (x) creates a second source-of-truth alongside format.md. Compromise: extend the existing intro paragraph with one clause per persona. No separate table; no new drift surface.

**Decision:** Walkthrough = step list + inline illustrative AskUserQuestion snippet. Persona lenses = extended intro paragraph (no table).

## Decisions

1. Extend intro paragraph with one-clause lens per standing persona (🏗️ Archie / 😈 Riku / ✂️ Petra).
2. Add `## How it works` section between "What it does" and "Example output":
   - `### /meeting (no subject)` — 5-step list + 3-row class table + illustrative bucket-summary snippet.
   - `### /meeting <topic>` — 5-step list + illustrative AskUserQuestion-exchange snippet.
3. Existing `## Example output` section (3 meeting-note links) unchanged — it covers the persisted-artefact angle.
4. Out of scope: effort table, `meeting-style.md` overrides, `cost-of.sh` detail, separate persona table, meeting-note header inline excerpt, date-triggered nuance.
5. README is not in the symlink loop — no live-skill consequences; purely publishing-side documentation.

## Action items

- [x] Extend intro paragraph — one-clause lens per persona. Verified: `grep -c "anchors claims" meeting/README.md` = 1.
- [x] Add `## How it works` at line 12. Verified: `grep -n "^## How it works" meeting/README.md` = 12.
- [x] `/meeting` (no subject) subsection — 5-step list + class table + bucket-summary snippet added.
- [x] `/meeting <topic>` subsection — 5-step list + AskUserQuestion snippet added.
