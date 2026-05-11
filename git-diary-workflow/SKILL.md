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

Then stage and commit — substitute the captured literal UUID directly into the Co-Authored-By line:

```bash
# Stage specific files (never git add -A)
git add <changed-files>
# <<'EOF' (quoted) — Claude Code's Bash matcher refuses unquoted <<EOF as a class; body has no $vars since UUID is captured first
git commit -m "$(cat <<'EOF'
descriptive message

Co-Authored-By: Claude Opus 4.6 (high) <PASTE-SESSION-ID-HERE@kienzler.dev>
EOF
)"
```

Replace `PASTE-SESSION-ID-HERE` with the UUID you captured above — never write the literal string `$CLAUDE_SESSION_ID` in the commit message.

```bash
# Push with parallel-safe locking (autostash + pull --rebase + push)
~/.claude/skills/git-diary-workflow/git-lock-push.sh
```

**Fill in Co-Authored-By yourself:**
- **Model**: from your system context (e.g. `Claude Opus 4.6`, `Claude Sonnet 4.6`)
- **Effort**: map your reasoning effort to `low` (≤33), `mid` (34–66), or `high` (≥67) — omit if unknown
- **Session ID**: the UUID you captured via `echo "$CLAUDE_SESSION_ID"` — embed the literal, never the variable name

### Step 1b: Commit and push ~/.claude (when running from a foreign project)

Skip this step when the cwd is `~/.claude` itself — Step 1 already handled that repo.

After committing the project repo, check for dirty state:

```bash
git -C ~/.claude status --porcelain
```

Empty output → nothing to do, proceed to Step 2.

Non-empty → `~/.claude` has uncommitted changes (e.g. a new meeting note, registry appends, settings edits). Commit and push them:

```bash
# Stage the specific files shown in the status output — never -A
git -C ~/.claude add <files-from-status>

# Commit — reuse the session ID captured above; describe what the skill wrote
git -C ~/.claude commit -m "$(cat <<'EOF'
<brief description of what changed in ~/.claude>

Co-Authored-By: Claude <Model> (<effort>) <PASTE-SESSION-ID-HERE@kienzler.dev>
EOF
)"

# Lock-push (uses /tmp lock file automatically for ~/.claude)
~/.claude/skills/git-diary-workflow/git-lock-push.sh ~/.claude
```

### Step 1c: Commit and push ~/src/dotclaude-skills (when skill spec files change)

Skip this step when the cwd is `~/src/dotclaude-skills` itself — Step 1 already handled that repo.

After Step 1b, check for dirty state:

```bash
git -C ~/src/dotclaude-skills status --porcelain
```

Empty output → nothing to do, proceed to Step 2.

Non-empty → a meeting skill spec file was modified via symlink (e.g. format.md, personas.md). Commit and push:

```bash
git -C ~/src/dotclaude-skills add <files-from-status>

git -C ~/src/dotclaude-skills commit -m "$(cat <<'EOF'
<brief description of what changed in dotclaude-skills>

Co-Authored-By: Claude <Model> (<effort>) <PASTE-SESSION-ID-HERE@kienzler.dev>
EOF
)"

~/.claude/skills/git-diary-workflow/git-lock-push.sh ~/src/dotclaude-skills
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

For specific file types once in the resolution step:
- **Diary**: Keep all entries from both sides, ordered chronologically. Entries are independent.
- **Config files** (CLAUDE.md, etc.): Keep both changes if different sections. Same section → use most complete/recent version and note the merge in diary.

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
