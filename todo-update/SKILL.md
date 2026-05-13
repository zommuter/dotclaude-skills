---
name: todo-update
description: Update TODO.md after substantive work. Trigger after every prompt where code was changed or tasks were completed. Mandatory alongside git-diary-workflow.
---

# TODO Update

## When to Use

After every prompt where substantive work was done — always run alongside `git-diary-workflow`. Maintains the project's `TODO.md` so the next session starts with a clear picture of what's left.

## Procedure

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

### Step 2: Add newly discovered tasks

If work revealed new tasks (new bugs, missing steps, follow-ups), add them under `## Current`:

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
