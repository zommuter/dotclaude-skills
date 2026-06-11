---
name: meeting-cross
description: Cross-project /meeting — scan all registered projects' TODO.md files, surface the highest-priority item globally, and dispatch to /meeting or implementation. Use instead of /meeting when you want to pick the most important work across your full project portfolio, not just the current repo.
---

# Meeting-Cross Skill

## Setup (run at every invocation)

1. **Capture metadata** — each as a **separate Bash call**:
   - `echo "$CLAUDE_SESSION_ID"`
   - `date '+%Y-%m-%d %H:%M'`
   - `date '+%H%M'`
   - `git config user.name`
2. **Load format spec**: read `~/.claude/skills/meeting/format.md`.
3. **Load persona registry**: read `~/.claude/skills/meeting/personas.md`.
4. **Load user profile**: run `~/.claude/skills/meeting/profile-active.sh --filter`.

## Classify all projects

1. **Discover projects** — read the project list:
   ```bash
   grep -E '^(path|paused) = ' ~/.config/project_manager/include.toml
   ```
   Parse into `(path, paused)` pairs. Skip any project where `paused = true`. For each remaining path, check if `<path>/TODO.md` exists — skip if not.

2. **Run classify.sh per project**:
   ```bash
   ~/.claude/skills/meeting/classify.sh <project-path>
   ```
   Collect and prefix each output line with `[<project-name>]`. Projects returning no output: skip silently.

3. **Apply model judgment** to the combined output:
   - Skip items that are purely **date-triggered** (activation date in text, e.g. "Revisit on 2026-08-13", "checkpoint 2026-06-28").
   - Skip items explicitly **deferred/reopen-gated** (body says "Deferred", "reopen trigger", "gated on" with an unmet condition — check the condition text).
   - Note when a gate that was previously blocking has now been met.
   - Surface **cross-project connections**: TODO items that reference paths in other registered projects (`see ~/src/<other>/...`, linked meeting notes in sibling repos).

4. **Print the classified bucket summary** as visible text — grouped first by class (C1 > C2 > C3), then by project. One-liner per item with `[PROJECT]` prefix. If an item has `GATED` in the 5th TSV field, append `[GATED]` to its one-liner.

5. **Pick the top candidate**: highest class, then most-recently-active project as tiebreaker:
   ```bash
   ls -t <project>/docs/meeting-notes/*.md 2>/dev/null | head -1
   ```

6. **Surface orphan-scan** (ADVISORY) for the top-candidate project only:
   ```bash
   ~/.claude/skills/meeting/orphan-scan.sh <project-path>/TODO.md
   ~/.claude/skills/meeting/orphan-scan.sh --reverse
   ```
   Display any results labelled `ADVISORY — not yet authoritative` before asking the user.

7. Ask via AskUserQuestion: `[Dispatch top pick / Choose different item]`. Embed a 2-sentence tl;dr of the top pick and its project in the question.

## Dispatch

**Establishing the project root override:** before invoking canonical `/meeting`, establish `<root> = <project-path>` as the active project root for this dispatch. The canonical /meeting's setup step 1 checks `$MEETING_ROOT_OVERRIDE`; since that env var is not available as a persisted shell export across Bash calls, communicate the override via explicit context: state "**MEETING_ROOT_OVERRIDE = <project-path>**" in the same turn as the Skill tool call. The canonical skill will use this contextually-established root throughout.

**Dispatch by class:**
- **C1** → invoke canonical `/meeting` via Skill tool with override established. Canonical no-arg flow re-confirms C1 and proceeds to implementation in the target project.
- **C2** → invoke canonical `/meeting` via Skill tool with override. Canonical handles Class 2 planning-mode dispatch.
- **C3** → invoke `/meeting <item-subject>` via Skill tool with override. Full persona meeting against the target project's context.

**On "Choose different item":** re-ask with the next candidate from the bucket summary.

## Routing-trail note

After dispatch completes (regardless of outcome), write a lightweight record to:
`~/src/dotclaude-skills/docs/meeting-notes/<YYYY-MM-DD>-<HHMM>-cross-classification.md`

```markdown
# YYYY-MM-DD — Cross-project classification

**Session:** <session-id>
**Mode:** /meeting-cross routing record

## Projects scanned
- <project-name>: N items (C1: X, C2: Y, C3: Z)
...

## Top pick
[PROJECT] CLASS: <item summary> → dispatched to /meeting [<subject if C3>]

## Cross-project connections noted
- <connection if any, else "none">

## Cost
Input tokens: NNNN  (uncached=N  cache_read=N  cache_create=N)
Output tokens: NNNN
Threshold (250k): BELOW / EXCEEDED
```

No action items to mint (routing records don't outlive the session).

## Ctx-bloat instrumentation (D4 gate)

After dispatch completes, run cost-of.sh and embed the key metrics in the routing-trail note's `## Cost` section:
```bash
~/.claude/skills/meeting/cost-of.sh <session-id>
```
Copy `Input tokens:` and `Output tokens:` lines verbatim; set `Threshold (250k): BELOW` or `EXCEEDED` based on total output tokens.

**If EXCEEDED:** add a TODO item to `~/src/dotclaude-skills/TODO.md` to design the handover-file mechanism before further cross-meetings (see D4 in `docs/meeting-notes/2026-05-28-1138-meeting-cross-architecture.md`).

**Gate-close:** once 3 routing-trail notes (`*-cross-classification.md`) all show `Threshold (250k): BELOW`, mark `id:b427` done in `~/src/dotclaude-skills/TODO.md` via the flock'd merge helper. Count existing notes:
```bash
ls ~/src/dotclaude-skills/docs/meeting-notes/*-cross-classification.md 2>/dev/null | wc -l
```
See `docs/meeting-notes/2026-05-28-1138-meeting-cross-architecture.md` D4. <!-- id:b427 -->
