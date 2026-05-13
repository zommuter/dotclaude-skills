# todo-update — Claude Code skill

A mandatory post-work skill for Claude Code. After every prompt where substantive work was done it updates the project's `TODO.md` — marking completed tasks, adding newly discovered ones, and keeping the Done section as auditable history. Runs alongside `git-diary-workflow`.

**Trigger:** `todo-update` skill — no arguments; always runs after substantive work.

## How it works

1. **Ensure TODO.md exists** — creates it from scratch or migrates a legacy `PROGRESS.md` if present.
2. **Add newly discovered tasks** — items surfaced during the session go under `## Current`.
3. **Mark completed tasks** — only moved to `## Done` when the user explicitly confirmed or tests pass; never on Claude's own judgment.

## Install

```bash
git clone https://github.com/zommuter/dotclaude-skills.git ~/src/dotclaude-skills
cd ~/src/dotclaude-skills
make install-todo-update
```

This symlinks `SKILL.md` into `~/.claude/skills/todo-update/` (P2 per-file pattern). No local-only personal files are created for this skill.

Then wire it up in `~/.claude/CLAUDE.md`:

```markdown
## After every prompt (when substantive work was done)
Run the `todo-update` skill — maintains TODO.md.
```

## Files

| File | Published | Notes |
|---|---|---|
| `SKILL.md` | ✓ | Skill frontmatter + full procedure |
