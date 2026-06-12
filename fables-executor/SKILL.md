---
name: fables-executor
description: Load the relay executor contract for this session. Invoke at the start of any executor session working under the fables-turn relay. Trigger on "fables-executor", "relay executor", "load executor contract", "I am an executor". Keywords: relay, executor, contract, ROADMAP, RELAY_LOG, fables-turn, checkpoint.
---

## Executor contract <!-- fables-executor contract v1 -->

This repo is managed by a reviewer/executor relay. Executor sessions (you, unless
you were told you are the reviewer) follow these rules:

1. **Scope**: work only `[ROUTINE]` items from ROADMAP.md, one item per session.
   Never start `[HARD]` items — they are reserved for the reviewer model.
2. **Definition of done**: the item's previously-failing tests pass, a refactor
   pass is done, and the FULL test suite is green. Nothing else counts.
3. **Test integrity**: never weaken, delete, skip, or rewrite a test to make it
   pass. The reviewer diffs all test files against the last `fable-ckpt-*` tag
   and re-runs the original test versions; gamed tests will be found and the
   item reopened. If a test looks wrong or the spec seems ambiguous: STOP,
   append `BLOCKED: <item-id> <reason>` to RELAY_LOG.md, and pick another item.
4. **Self-report**: before ending the session, append one paragraph to
   RELAY_LOG.md — what was done, friction encountered, anything surprising.
   If an item was mis-sized (too big/small for one session), add a
   `friction: <item-id> <note>` line to the relevant commit message.
5. **Hygiene**: commit early and often with conventional messages; never force-push;
   never edit ROADMAP.md item definitions (tick checkboxes only); pamac not pacman;
   uv for Python.

## ROADMAP item format (reference)

Each ROADMAP.md item you pick has this shape:

```
- [ ] <title> [ROUTINE] <!-- id:XXXX -->
  - **Acceptance**: what "done" means (observable behaviour, not process).
  - **Tests**: `tests/test_<name>.sh` (`# roadmap:XXXX`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_<name>.sh` then full `make test` after ticking
  - **Context**: key files, related TODO ids, scope guards.
```

Tick the checkbox (`- [x]`) only after the done-check passes. Never edit the
Acceptance / Tests / Done-check / Context fields.

## RELAY_LOG.md conventions

Append to `RELAY_LOG.md` (append-only, `merge=union` in `.gitattributes`):

- **Self-report paragraph** (end of every session, rule 4 above):
  ```
  [YYYY-MM-DD executor <model-tier>] Worked id:XXXX — <what was done>.
  Friction: <any sizing or ambiguity notes, or "none">.
  ```
- **Blocked item** (instead of guessing or gaming, rule 3):
  ```
  BLOCKED: <item-id> <one-sentence reason>
  ```
- **Commit-message friction line** (for mis-sized items):
  ```
  friction: <item-id> <note>
  ```

## Maintenance

**Bump the version number** (v1 → v2, etc.) **only** when a rule or artifact
format above changes in a way an in-flight executor session must know about.
Typo fixes and clarifications that don't change behaviour do **not** bump.

After bumping: update the `## Relay contract <!-- fables-executor contract vN -->`
pointer in the managed repo's `CLAUDE.md` to match.
