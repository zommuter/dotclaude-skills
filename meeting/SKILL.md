---
name: meeting
description: Hold a structured design meeting with multi-persona scrutiny on a non-trivial decision. Trigger when a TODO item has ambiguous scope, a design has non-obvious trade-offs, or two plausible approaches exist and the wrong choice is hard to reverse. Skip for bug fixes, one-liners, or already-decided features. With no subject, audits TODO.md and recent meeting notes to recommend a session.
---

# Meeting Skill

## Setup (run at every invocation)

1. **Find project root**: run `git rev-parse --show-toplevel`. If not in a git repo, use cwd.
2. **Capture metadata**: run `echo "$CLAUDE_SESSION_ID"` and `date '+%Y-%m-%d %H:%M'` and `date '+%H%M'` and `git config user.name`. Store the results as literals — use them for the meeting-note filename, header lines, and in-transcript human attribution. Do not re-expand these in Write calls; embed the captured values directly.
3. **Load format spec**: read `~/.claude/skills/meeting/format.md`. If `<root>/docs/meeting-notes/meeting-style.md` exists, append its contents to your working context under "## Project-specific overrides". Honour any natural-language overrides (e.g. "exclude Riku", "include Sage as standing", "meetings here are casual") — no structured parsing, just follow them.
4. **Load persona registry**: read `~/.claude/skills/meeting/personas.md`. If the meeting calls for any persona by name, onboard them with their established lens from the registry — no re-introduction needed.
5. **Surface relevant discoveries**: read `~/.claude/skills/meeting/discoveries.md`. At the start of the meeting, mention entries that intersect the meeting topic.

## With a subject argument

1. **Warrantability self-check** (see format spec). If the request looks like a bug fix, one-liner, or already-decided feature, respond "are you sure you want a meeting?" and briefly explain why it might be overkill — before running the agenda. If it clearly passes, note that and proceed.
2. **Past-meetings audit**: scan `<root>/docs/meeting-notes/*.md` for action items not yet reflected in `<root>/TODO.md`. Flag orphans before the new agenda starts. "Tracked but not yet implemented" is fine; "neither done nor tracked" is not.
3. Call `EnterPlanMode`. Accumulate the transcript in the plan file the system creates.
4. **Run the interactive meeting**: open with attendees line + topic, then follow the format spec (agenda → named discussion → AskUserQuestion decision points → decisions → action items).
6. **Print transcript before every AskUserQuestion** — output the relevant meeting chunk as visible text before calling the tool, so the user has full context even if the plan file is not visible in the prompt UI.
6. Proceed to end-of-meeting steps.

## With no subject (default mode)

1. Read `<root>/TODO.md` (exact filename, no fallback). Read `<root>/docs/meeting-notes/*.md`.
2. Identify candidates: unchecked TODO items whose scope is ambiguous, approach is undecided, or trade-offs are non-trivial.
3. Recommend one candidate with 2–3 sentences of reasoning, or explain "no meeting-worthy topic found" and stop.
4. Ask via AskUserQuestion: "Run a meeting on `<candidate>`?" — options [run on this / pick another / not yet].
5. On "run": proceed as if `/meeting <candidate>` was invoked. On "pick another": ask follow-up. On "not yet": exit gracefully.

## End-of-meeting steps

1. **Write meeting note** to `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md`. Use the captured date, HHMM, and slug derived from the meeting title. Include `**Started:**` and `**Session:**` header lines populated with the captured literals.
2. **Memory classification**: for each key decision or finding, ask via AskUserQuestion [project / discovery / universal / discard]:
   - *project* → write a `project`-type memory entry to `~/.claude/projects/<slug>/memory/<topic>.md`; add pointer to `MEMORY.md`. Body: "Decision: ... **Why:** ... **How to apply:** ...".
   - *discovery* → append one line to `~/.claude/skills/meeting/discoveries.md`: `- [YYYY-MM-DD <project>] <one-sentence finding> — see <meeting-note-path>`.
   - *universal* → propose a concrete `~/.claude/CLAUDE.md` edit and ask approval. Do not write directly.
   - *discard* → skip.
3. **Persona registry**: for each new ad-hoc persona introduced, ask [save to global registry / meeting-only]. On save, append to `~/.claude/skills/meeting/personas.md`.
4. Call `ExitPlanMode`.

## Constraints during a meeting

- No file edits except the plan file and the final meeting note.
- No implementation work mid-meeting even if asked — defer until after ExitPlanMode.
- New topics that arise mid-meeting must be captured as "Amendment session" in the transcript, not silently inserted.
