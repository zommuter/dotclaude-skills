---
name: todo-update
description: Update TODO.md after substantive work. Trigger after every prompt where code was changed or tasks were completed. Mandatory alongside git-diary-workflow.
---

# TODO Update

## When to Use

After every prompt where substantive work was done — always run alongside `git-diary-workflow`. Maintains the project's `TODO.md` so the next session starts with a clear picture of what's left.

## Procedure

> **Scope discipline:** The CWD `TODO.md` is the *sole* authority for this invocation. Do **not** read or write any other `TODO.md` — not the parent repo's, not a sibling worktree's, not one textually referenced from within this file (e.g. `> Subset of ../../TODO.md`). An empty `## Current` section, or one where all items are checked, is a valid terminal state — report done and stop; do not look elsewhere for "real" work. The create-if-missing path below applies only to the CWD file; never seed it from a parent-path TODO.md.

### Step 1: Ensure TODO.md exists

If `PROGRESS.md` exists but `TODO.md` does not:
1. Read `PROGRESS.md` and migrate its content into `TODO.md` format (pending items → `## Current`, completed items → `## Done`)
2. Delete `PROGRESS.md`
3. Stage both changes (`git add TODO.md` and `git rm PROGRESS.md`)

If neither exists, create `TODO.md`:

```markdown
# TODO

## Current
- [ ] (add tasks here)

## Done
```

### Step 1.5: Warn about subdirectory TODO.md files

Run:
```bash
~/.claude/skills/meeting/find-todos.sh
```

If any paths are returned, print:
```
WARNING: subdirectory TODO.md files found — consider merging into root TODO.md: <paths>
```

Do not block or auto-merge. Proceed with normal steps; the user decides whether to merge.

### Step 2: Add newly discovered tasks

Before adding a new task, grep the file for keywords to avoid duplicates:

```bash
grep -i "keyword" TODO.md
```

If a matching open item already exists, update it in place rather than adding a duplicate. Only add a new line if no near-match is found:

```markdown
- [ ] brief description of new task
```

### Step 3: Mark completed tasks — ONLY with verification

Move a task from `## Current` to `## Done` **only if**:
- The user explicitly confirmed it ("done", "looks good", "verified"), OR
- Unit tests that cover this task pass

When moving, append a verification note:

```markdown
- [x] task description — verified by user on 2026-03-21
- [x] task description — covered by tests (test_foo.py) on 2026-03-21
```

**Never mark a task done based solely on Claude's own judgment that the work is complete.**

**For items tagged `<!-- id:XXXX -->`**: use the flock'd merge helper instead of a direct Edit, to avoid clobbering concurrent session edits:

```bash
~/.claude/skills/meeting/md-merge.py update-ids --file TODO.md <<'JSON'
{"updates": [{"id": "XXXX", "line": "- [x] task description — verified by user on YYYY-MM-DD <!-- id:XXXX -->"}]}
JSON
```

The helper acquires an exclusive flock, re-reads TODO.md, replaces the `<!-- id:XXXX -->` line in-place, and writes back atomically. Multiple IDs can go in one call. Items without an ID tag use a direct Edit as before.

### Step 4: Archive old done entries

Once per session, run:

```bash
~/.claude/skills/todo-update/archive-done.sh TODO.md
```

This prunes empty (zero-task-line) non-protected sections unconditionally, and moves `[x]` entries dated ≥30 days ago to `TODO.archive.md` when the file has ≥50 lines. Undated entries are left in place.

## Format Rules (Sonnet-friendly)

- Flat list only — no nesting, no subtasks, no priority markers
- One line per task
- Do not reorder existing items
- `## Current` first, `## Done` second
- Keep `## Done` entries (they're the project history)

## Example TODO.md

```markdown
# TODO

## Current
- [ ] Add input validation to login form
- [ ] Write tests for auth module

## Done
- [x] Set up project scaffold — verified by user on 2026-03-20
- [x] Configure CI pipeline — tests passing on 2026-03-21
```

## Gotchas

- **Do not mark done without verification** — this is the key rule
- If unsure whether a task is truly done, leave it in `## Current` or ask the user
- If a task is partially done, leave it in `## Current` and add a comment inline if helpful
- TODO.md should be committed as part of the normal `git-diary-workflow` commit
- If `PROGRESS.md` is found alongside `TODO.md`, migrate and delete it on the spot
