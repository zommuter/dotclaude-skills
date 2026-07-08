---
name: git-diary-workflow
description: Auto-commit, push, and write diary entry after every substantive prompt. Trigger on ANY code change — this is a mandatory post-work step, not optional.
---

# Git Diary Workflow

## When to Use

After every prompt where substantive work was done. This is a **mandatory** post-work step defined in the global CLAUDE.md. If you changed files, you must:
1. Commit and push the project repo
2. Append a diary entry and push the diary repo

## Procedure

### Step 1: Commit and push the project repo

First, **capture the session ID** in a separate Bash call so the literal value is in your context before you write the commit:

```bash
echo "$CLAUDE_SESSION_ID"
```

Then **run `git status --short`** (separate Bash call) to see every dirty file before staging. Stage ALL modified work artifacts — not just the primary task files. Side-effect edits (e.g. personas.md, meeting notes updated mid-task) must be included. Omit only generated outputs, temp files, and secrets.

```bash
# Stage specific files (never git add -A) — include side-effect edits surfaced by git status
git add <changed-files>
# <<'EOF' (quoted) — Claude Code's Bash matcher refuses unquoted <<EOF as a class; body has no $vars since UUID is captured first
git commit -m "$(cat <<'EOF'
descriptive message

Co-Authored-By: Claude Opus 4.6 (high) <PASTE-SESSION-ID-HERE@kienzler.dev>
EOF
)"
```

Co-Authored-By fields: **Model** from system context (e.g. `Claude Sonnet 4.6`); **Effort** = `low` (≤33), `mid` (34–66), `high` (≥67); **Session ID** = the captured UUID — never the literal `$CLAUDE_SESSION_ID`.

```bash
# Push (parallel-safe: flock'd dirty-guard + pull --rebase + push)
~/.claude/skills/git-diary-workflow/git-lock-push.sh
```

### Step 1b: Commit and push ~/.claude (when running from a foreign project)

Skip this step when the cwd is `~/.claude` itself — Step 1 already handled that repo.

Identify `~/.claude` files you **edited/created this session** — do NOT use `git status` (it shows all sessions' dirty files). If none → proceed to Step 2.

If you did make changes, write your file list to a temp manifest and call `git-lock-push.sh` in manifest mode (stage+commit happen inside the lock — no separate `git add` or `git commit`):

```bash
# Temp manifest — one absolute path per line (only files you edited/created this session)
manifest=$(mktemp)
printf '%s\n' \
  "/home/tobias/.claude/<file1>" \
  "/home/tobias/.claude/<file2>" \
  > "$manifest"

# Commit message in a var first (quoted heredoc so no $-expansion)
msg="$(cat <<'EOF'
<brief description of what changed in ~/.claude>

Co-Authored-By: Claude <Model> (<effort>) <PASTE-SESSION-ID-HERE@kienzler.dev>
EOF
)"

# Stage + commit + pull + push atomically inside the per-repo flock
# NOTE: flags MUST precede REPO_PATH — getopts stops at the first non-flag arg
~/.claude/skills/git-diary-workflow/git-lock-push.sh -f "$manifest" -m "$msg" ~/.claude
rm -f "$manifest"
```

### Step 1c: Commit and push ~/src/dotclaude-skills (when skill spec files change)

Skip this step when the cwd is `~/src/dotclaude-skills` itself — Step 1 already handled that repo.

After Step 1b, **always run** (separate Bash call):
```bash
git -C ~/src/dotclaude-skills status --short
```
If empty → nothing to do, proceed to Step 2.

If non-empty → **attribute each dirty file before committing**. The repo is single-user but NOT single-session: parallel Claude sessions (e.g. relay turns) leave their own WIP dirty here, and committing another live session's half-finished edits under your session ID mis-attributes work and can race its own end-of-turn commit (observed 2026-06-12: a relay session's relay-loop.js WIP was dirty while still in flight).

- **Yours** — you edited the file this session, either directly or through a symlink (e.g. `~/src/meeting-rpg/broker.py → ~/src/dotclaude-skills/meeting/broker.py`). Symlink edits are the reason this step exists: they never show up in the foreign project's git status, so check your session's Write/Edit targets against `realpath` into dotclaude-skills — **do not rely on the foreign repo's git status to surface them**.
- **Not yours / can't attribute** — leave it uncommitted and mention it in the end-of-session summary; the owning session's workflow will commit it.

**Known residual race**: attribution is file-granular. If two sessions edit the SAME file concurrently, staging "your" file scoops the other session's hunks. (git-lock-push's `--autostash` was dropped 2026-07-08 — the id:aa93 guard refuses tracked-dirty trees, and a tracked edit landing in the check→pull race window now makes the rebase refuse loudly instead of being silently stashed and popped over a rewritten tree.) The real fix is worktree-per-session with a flock'd merge to canonical — see dotclaude-skills TODO id:3558 (build opened 2026-06-12). Until that lands: before committing a shared spec file (SKILL.md, format.md, personas.md), eyeball `git diff` for hunks you don't recognize and drop them from the commit.

For YOUR files only: build a manifest and msg exactly as in Step 1b, using `~/src/dotclaude-skills/<file1>` paths and a dotclaude-skills description, then:

```bash
~/.claude/skills/git-diary-workflow/git-lock-push.sh -f "$manifest" -m "$msg" ~/src/dotclaude-skills
rm -f "$manifest"
```

### Step 2: Append diary entry

Use the diary-append script — it handles git pull, flock, commit, and push atomically:

1. Run `mktemp -u .diary-entry.XXXXXX` in Bash to get a unique temp file path. (`-u` = name only, file not created yet — Write creates it.)
2. Use the **Write** tool to write the entry body to that temp file (no header — the script generates it):
```
1. Step one — concise but reproducible
2. Step two
```
3. Run diary-append with `-f` and `-p` to append the entry (script auto-generates the `## timestamp host:session path` header). Do **not** pass `-s` — the script reads `$CLAUDE_SESSION_ID` from env automatically via the SessionStart hook:
```bash
~/.claude/skills/git-diary-workflow/diary-append.sh -m "diary: brief description" -p project/path -f .diary-entry.XXXXXX
```

### Step 3: Update TODO.md

Run the `todo-update` skill to update the project's `TODO.md`.

## Gotchas

- **Use `git pull --rebase` only after committing** — never with a dirty working tree. The commit-first pattern in Step 1 ensures this is always safe.
- **Never use `git add -A` or `git add .`** — risk of committing secrets (.env, credentials) or large binaries. Stage files by name.
- **Never skip hooks** (`--no-verify`) or bypass signing (`--no-gpg-sign`) unless the user explicitly asks.
- **Never amend commits** unless the user explicitly asks — always create new commits.
- **diary-append.sh handles its own git operations** — do NOT `git pull` on the diary repo before calling it, or you'll conflict with the flock.
- The diary is append-only. If previous entries become outdated, strike them through with `~~text~~` and add a brief explanation with current timestamp.

## Merge Conflicts

If `git pull --rebase` fails with conflicts:

1. **Show the conflict**: run `git diff` and list the conflicting files. Report to the user.
2. **Suggest a resolution**: based on the content, propose which version to keep or how to merge.
3. **Let the user decide**:
   - User approves: resolve the files, `git add <files>`, `git rebase --continue`, then push.
   - User declines: `git rebase --abort` to restore pre-rebase state. Commit is preserved locally, not pushed.
4. **Never force-resolve silently.**

File-type guidance: **Diary** — keep all entries from both sides, chronological. **Config files** (CLAUDE.md, etc.) — keep both if different sections; same section → most complete/recent, note the merge in diary.

## Error Handling

- Check exit code of every git command. Stop and report to the user on failure.
- Never retry a failed push with `--force` unless the user explicitly requests it.

## Verification

```bash
# Project repo pushed?
git log --oneline origin/main..HEAD  # should be empty (all pushed)
git status                           # should be clean

# Diary pushed?
# diary-append.sh prints success/failure — check its output
```

If either step fails, report the error — do not silently continue.
