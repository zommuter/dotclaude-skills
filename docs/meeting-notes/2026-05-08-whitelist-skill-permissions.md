# 2026-05-08 — Whitelist permission prompts for global skills

**Attendees:** Tobias (product owner), Archie (architect), Riku (devil's advocate), Petra (productivity)
**Topic:** When `/meeting` (or any global skill) runs from a non-`~/.claude` project, reading skill support files like `~/.claude/skills/meeting/format.md` triggers per-prompt permission requests. Decide what to whitelist, where, and how broadly.

## Past-meetings audit (orphans)

From `2026-05-08-parallel-edit-safety.md`, two action items were **not tracked** in `~/.claude/TODO.md`:
- Volume-marker flag write at 50 entries (`~/.claude/logs/parallel-edit-review-due.flag`)
- Schedule one-time reminder for 2026-05-22 via `schedule` skill

Action: folded into the existing "Parallel edit logger" item in TODO.md.

## Agenda

1. **Failure scope.** Which prompts trigger today? Just `Read(~/.claude/skills/meeting/*)`, or also `Skill(meeting)`, `EnterPlanMode`, ad-hoc `Read(~/.claude/...)` from other skills?
2. **Settings location.** Global `~/.claude/settings.json` vs per-project `.claude/settings.json` vs a new `~/.claude/settings.local.json`.
3. **Pattern breadth.** Three candidate scopes: narrow / medium / wide.
4. **Process.** Manual edit now, or invoke `fewer-permission-prompts` skill, or both?

## Discussion

### Framing — what's actually prompting

**Archie:** The default Claude Code permission model lets `Read` happen freely *inside* the current working directory. When the cwd is `~/src/zkm` and a skill reads `~/.claude/skills/meeting/format.md`, the path is outside the project sandbox, which is what triggers the prompt. Same pattern would hit any global skill that ships support files. The settings.json `permissions.allow` list at `~/.claude/settings.json:5-37` currently has zero `Read(...)` entries — only Bash, Write, and Skill rules.

**Riku:** The blast radius of a wide allow rule is real. `Read(~/.claude/**)` would also cover `~/.claude/projects/**/*.jsonl` (full conversation transcripts including any pasted secrets) and `~/.claude/.credentials*` if such a file ever appears. Be deliberate.

**Petra (N=2):** Two concrete consumers exist for skill-file reads: (1) the meeting skill loading `format.md`/`personas.md`/`discoveries.md`; (2) the git-diary-workflow / todo-update skills, which already work because they don't read external files — they're pure prompts. So actually only meeting *needs* this today. Anything broader is speculative.

**Archie counters Petra:** Speculation, but cheap speculation. Every future skill we put in `~/.claude/skills/<x>/` with sibling support files will hit the same prompt. The pattern `Read(~/.claude/skills/**)` is no more dangerous than `Read(~/.claude/skills/meeting/*)` — skill source files are user-authored, low-secret, and already on disk where the user controls them.

**Riku:** Agreed on `~/.claude/skills/**` being safe. The line I want to hold is *not* `~/.claude/**` — that crosses into transcript territory.

### Settings location

**Archie:** Global skills live in `~/.claude/skills/`. Permissions to read them must be visible from any project, which means they belong in **global** `~/.claude/settings.json`, not per-project. Per-project would mean adding the same allow rule to every repo Tobias works in — exactly the friction we're trying to remove.

**Petra:** Confirms. Single file, single rule, applies everywhere.

### "Other unnecessary prompts" scan

**Archie:** Worth enumerating what else fires from a typical session:
- `Skill(<name>)` invocations — currently only `git-diary-workflow` and `todo-update` are whitelisted (`settings.json:34-35`). User-typed `/meeting` does not appear to prompt; auto-firing skills do (hence the existing two rules).
- `EnterPlanMode` / `ExitPlanMode` — tested experience says they don't prompt in normal use.
- `WebFetch`, `WebSearch` — would prompt; unrelated to the meeting skill issue.
- `Write(~/.claude/skills/meeting/discoveries.md)` and `Write(~/.claude/docs/meeting-notes/*)` — the meeting skill *writes* to these at end-of-meeting. The only Write rule today is `Write(.diary-entry.*)`. From a non-`~/.claude` project, these writes will prompt.

**Riku:** Writes are the more dangerous side. A wide `Write(~/.claude/**)` would let any skill clobber `CLAUDE.md`, `MEMORY.md`, `settings.json` itself. Don't go there. Targeted writes for the meeting skill's known outputs only.

**Petra:** Real meeting-skill-from-foreign-project list:
- `Read(~/.claude/skills/meeting/*)` (or broader `~/.claude/skills/**`)
- `Write(~/.claude/skills/meeting/personas.md)` — registry append
- `Write(~/.claude/skills/meeting/discoveries.md)` — discovery append
- `Write(~/.claude/docs/meeting-notes/*)` — meeting note creation
- `Write(~/.claude/projects/*/memory/*)` — project-memory writes (when memory category = "project")

### Process — manual or use the existing skill?

**Archie:** The `fewer-permission-prompts` skill exists for exactly this. Two caveats: (a) it targets *project* settings, not global; (b) "Bash and MCP tool calls" — may not cover Read/Write. May not solve our case directly.

**Petra:** Don't run the skill blind. We already know what we want. Manual edit to `~/.claude/settings.json` is precise, reviewable, and one-shot. The skill is for the long-tail discovery problem.

**Riku:** Concur — manual now, skill later if a long tail emerges.

### Decision 1 — Read scope

**Resolved:** `Read(~/.claude/skills/**)`. Covers meeting today and any future global skill that ships support files. Stays inside Riku's red line (does not touch `~/.claude/projects/` transcripts).

### Write scope — what to allow

**Archie:** Three meeting-skill writes from a foreign project:
1. `Write(~/.claude/docs/meeting-notes/*)` — every meeting end. High frequency, well-defined path.
2. `Write(~/.claude/skills/meeting/personas.md)` and `Write(~/.claude/skills/meeting/discoveries.md)` — only when meeting introduces new persona / discovery.
3. `Write(~/.claude/projects/*/memory/*)` — when meeting memory classification = "project". Writes to *another* project's memory dir.

**Riku:** Item 3 deserves scrutiny. The path lets *any* skill running from any project write into any *other* project's memory.

**Petra:** Memory writes are user-confirmed via AskUserQuestion in the skill flow itself — there's a human gate before the Write fires.

**Archie:** Compact alternative: `Write(~/.claude/skills/meeting/*)` + `Write(~/.claude/docs/**)`.

**Riku:** `Write(~/.claude/docs/**)` is fine — `docs/` is human-curated, not secret-bearing.

### Decision 2 — Write scope

**Resolved:** Strict per-file. Three rules:
- `Write(~/.claude/skills/meeting/personas.md)`
- `Write(~/.claude/skills/meeting/discoveries.md)`
- `Write(~/.claude/docs/meeting-notes/*)`

No `Write(~/.claude/projects/*/memory/*)` — those rare events keep their second confirmation prompt. Tobias overrode the compact-pattern recommendation in favor of the most conservative scope.

## Amendment session 1 — git-diary-workflow auto-firing after a foreign-project meeting

**Tobias's concern:** When `/meeting` runs from `~/src/zkm`, the meeting writes files into `~/.claude/`. The mandatory `git-diary-workflow` auto-fires after substantive work — but its cwd is `~/src/zkm`, so its `git ...` calls operate on the wrong repo.

**Archie:** Two layered problems:
1. **Repo targeting.** `git-diary-workflow` only sees cwd. The `.claude` changes won't be detected, committed, or pushed.
2. **Permissions.** Even if fixed, none of the `Bash(git -C ~/.claude *)` patterns are in `settings.json`. Each git operation would prompt.

**Riku:** Problem 1 is load-bearing. Permissions are downstream.

**Petra:** Out of scope for this meeting. Capture problem 1 as a follow-up TODO.

### Decision 3 — git-on-~/.claude block

**Resolved:** Defer. No `Bash(git -C ~/.claude *)` rules added today. Capture as a follow-up TODO that pairs with the diary-workflow repo-targeting fix; revisit at that time.

## Decisions

- **Read allowlist** — add `Read(~/.claude/skills/**)` to `~/.claude/settings.json`. Stops short of `~/.claude/projects/` transcripts.
- **Write allowlist** — add three exact-path rules: `Write(~/.claude/skills/meeting/personas.md)`, `Write(~/.claude/skills/meeting/discoveries.md)`, `Write(~/.claude/docs/meeting-notes/*)`.
- **No project-memory write rule.** Cross-project memory writes keep their second confirmation prompt.
- **No git-on-`~/.claude` rules.** Deferred until the diary-workflow repo-targeting fix is designed.
- **Process** — manual edit to global `~/.claude/settings.json`. Reserve `fewer-permission-prompts` skill for long-tail discovery.
- **Out of scope** — `Skill(meeting)` allow rule (user-invoked); MCP/WebFetch/WebSearch; Bash-mediated edits.

## Action items

- [x] Edit `~/.claude/settings.json`: append four allow rules (one Read, three Writes) under `permissions.allow`.
- [x] Update `~/.claude/TODO.md`: add diary-workflow cross-repo item; fold orphan sub-items into "Parallel edit logger".
- [x] Write project memories: `permission_allowlist_heuristic.md`, `git_diary_cross_repo_limitation.md`. Update `MEMORY.md` index.
- [ ] Verify: run `/meeting` from `~/src/helferli` — confirm `Read(~/.claude/skills/meeting/*)` does not prompt; trigger end-of-meeting write to confirm no prompt for `Write(~/.claude/docs/meeting-notes/*)`.
