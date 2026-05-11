# git-diary-workflow — Claude Code skill

A post-work automation skill for Claude Code. After every prompt where substantive work was done it commits and pushes the project repo, appends a timestamped diary entry to `~/src/claude-diary/DIARY.md`, and commits + pushes the diary repo — all in one repeatable step. Invoked as a mandatory post-work step via the global `~/.claude/CLAUDE.md`.

**Trigger:** `/git-diary-workflow` — no arguments; always runs after substantive work.

## How it works

1. **Commit and push the project repo** — stages specific changed files, commits with a `Co-Authored-By: Claude …` footer, then calls `git-lock-push.sh` to stash, pull --rebase, and push in a flock'd sequence (safe against parallel Claude sessions writing to the same repo).
2. **Commit `~/.claude` if dirty** — any meeting notes, registry appends, or settings edits that landed in `~/.claude` during the session get committed and pushed.
3. **Commit `~/src/dotclaude-skills` if dirty** — spec files modified via symlink (e.g. `format.md`, `personas.md`) are picked up here.
4. **Append diary entry** — `diary-append.sh` writes a `## timestamp host:session path` header and the session summary to `$DIARY_REPO_DIR/DIARY.md` (default `~/src/claude-diary/DIARY.md`), then commits and pushes the diary repo atomically under the same flock.

`git-lock-push.sh` uses `flock` with a per-repo lock file (`.git-lock-push.lock` at repo root, `/tmp/claude-git-dotclaude.lock` for `~/.claude`) so concurrent sessions serialize instead of racing.

## Install

```bash
git clone https://github.com/zommuter/dotclaude-skills.git ~/src/dotclaude-skills
cd ~/src/dotclaude-skills
make install-git-diary-workflow
```

This symlinks the three published files into `~/.claude/skills/git-diary-workflow/` (P2 per-file pattern) and marks the scripts executable. No local-only personal files are created for this skill.

Then wire it up in `~/.claude/CLAUDE.md`:

```markdown
## After every prompt (when substantive work was done)
Run the `git-diary-workflow` skill — commits, pushes, and writes diary entry.
```

## Files

| File | Published | Notes |
|---|---|---|
| `SKILL.md` | ✓ | Skill frontmatter + full procedure |
| `diary-append.sh` | ✓ | Appends entry to `$DIARY_REPO_DIR/DIARY.md` (default `~/src/claude-diary/`) — `chmod +x` required |
| `git-lock-push.sh` | ✓ | Per-repo flock'd stash+pull+push sequencer — `chmod +x` required |
