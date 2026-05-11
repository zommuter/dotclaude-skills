# 2026-05-08 — Promote `meeting-style.md` to a global skill

**Attendees:** Tobias (product owner), Archie (architect), Riku (devil's advocate), Petra (productivity), **Sage (skill-runtime, new)**
**Topic:** Convert `~/src/zkm/docs/meeting-notes/meeting-style.md` into a Claude Code skill at `~/.claude/skills/meeting/`, with an optional `<subject>` arg defaulting to "audit TODO + past meetings, recommend next planning session".

## Agenda

1. Skill location & coupling — global vs project-scoped; embed inline vs reference.
2. Default (no-arg) behaviour — what happens on bare `/meeting`?
3. Project-awareness — finding `TODO.md` / `docs/meeting-notes/` outside zkm.
4. Interactive mode — skill calls `EnterPlanMode` itself or assumes plan mode?
5. Persona persistence — keep personas in skill or load from project file?

*Amendment:* 1' (augment not replace), 5' (global persona registry), 6 (cross-meeting memory).

## Discussion

### Onboarding Sage

**Sage (new — skill-runtime lens):** A skill is a directory under `~/.claude/skills/<name>/` with `SKILL.md` and YAML frontmatter. Slash-form `/meeting` auto-registers. Skills are prompts, not sandboxed code. Optional args come as freeform text.

### Decision 1 — Skill location & coupling

Archie proposed (a) embed inline, (b) reference zkm file by absolute path, (c) project-local override with fallback. Petra rejected (c) under N=2 (only zkm today). Riku rejected (b) as creating a hidden cross-repo dependency. Tobias overrode on two fronts: (1) put the spec in a sibling file for context-window efficiency; (2) support project overrides from day 1.

**Revised resolution:** Two-file skill (`SKILL.md` procedural, `format.md` canonical spec). Project file at `<root>/docs/meeting-notes/meeting-style.md` **augments** the global format via textual append under "## Project-specific overrides" — no replace, no structured merge. Natural-language overrides ("exclude Riku") honoured by the model. zkm's file reduces to "Past meetings" + any zkm deltas.

### Decision 2 — Default (no-arg) behaviour

Riku: auto-run is hostile if audit picks wrong topic. Petra: audit-only needs two invocations. Resolution: **audit → confirm → run** via AskUserQuestion [run / pick another / not yet]. No meeting warranted → stop with explanation.

### Decision 3 — Project-awareness

Project root = first ancestor with `.git/`, else cwd. `<root>/TODO.md` exact name (no BACKLOG.md fallback). `<root>/docs/meeting-notes/*.md` for past meetings. All optional; missing files degrade gracefully.

### Decision 4 — Interactive mode + plan-mode

Skill calls `EnterPlanMode` as first action. Tobias asked: does opusplan trigger even when the skill (not the user) calls it? Sage: yes — opusplan keys off plan-mode state, not who initiated. The model swaps on state transition.

### Decision 5 — Persona registry (amended)

Standing four (Tobias, Archie, Riku, Petra) in `format.md`. Ad-hoc personas tracked in global `~/.claude/skills/meeting/personas.md` with name + one-sentence lens. Skill loads registry on start; named personas onboarded with established lens without re-intro. New personas appended at meeting end with confirmation. Future: OpenClaw SOUL.md persona-agency extension deferred.

### Decision 6 — Cross-meeting memory (new)

Three categories of meeting output:
1. **Project decisions** → existing auto-memory (`~/.claude/projects/<slug>/memory/`), loaded every session in that project.
2. **Cross-project discoveries** (facts about the world: hardware capabilities, model benchmarks) → `~/.claude/skills/meeting/discoveries.md`, loaded by meeting skill at audit time in any project.
3. **Universal rules** → skill proposes `~/.claude/CLAUDE.md` edit, Tobias approves.

At meeting end, skill classifies each finding via AskUserQuestion [project / discovery / universal / discard].

## Decisions

- Skill at `~/.claude/skills/meeting/` with `SKILL.md` + `format.md` + `personas.md` + `discoveries.md`.
- Project file augments (textual append), not replaces. One file kind: delta.
- Default mode: audit → confirm → run via AskUserQuestion.
- Skill calls `EnterPlanMode` itself; opusplan triggers normally.
- Ad-hoc persona registry global; standing four in `format.md`.
- Three-tier memory: project auto-memory / discoveries.md / CLAUDE.md.
- zkm's `meeting-style.md` reduced to "Past meetings" + zkm-specific overrides.
- Discoveries.md seeded with two cross-project findings from zkm sessions.

## Action items

- [x] Create `~/.claude/skills/meeting/SKILL.md` — procedural prompt
- [x] Create `~/.claude/skills/meeting/format.md` — canonical format spec
- [x] Create `~/.claude/skills/meeting/personas.md` — ad-hoc persona registry seeded with Mira, Flora, Sage
- [x] Create `~/.claude/skills/meeting/discoveries.md` — seeded with two zkm discoveries
- [x] Reduce `~/src/zkm/docs/meeting-notes/meeting-style.md` to delta
- [ ] Save this meeting's key decisions to project auto-memory (`.claude` project)
- [ ] Test: `/meeting` from `~/src/zkm/` — confirm audit finds session 12 zkm-pdf as candidate
