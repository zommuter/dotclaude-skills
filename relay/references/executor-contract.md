# Relay executor contract

This is the LEAN executor contract loaded by `/relay executor` at the start of an
executor session. It deliberately does NOT pull in the orchestrator (`relay/SKILL.md`):
a cheap Sonnet executor needs only the rules below.

## Executor contract <!-- relay-executor contract v4 -->

This repo is managed by a reviewer/executor relay. Executor sessions (you, unless
you were told you are the reviewer) follow these rules:

0. **Cross-session lease (id:ebfb)**: BEFORE any work, acquire this repo's relay lease so you
   never collide with a running pool or another executor on the same repo —
   `~/.claude/skills/relay/scripts/claim.sh acquire "$(basename "$(git rev-parse --show-toplevel)")" --run "executor-$CLAUDE_SESSION_ID" --mode execute`.
   If it exits non-zero, a live relay run already holds this repo: STOP — do not work it (tell the
   user a pool or another session holds it). When your session ends, release it:
   `claim.sh release "$(basename "$(git rev-parse --show-toplevel)")" --run "executor-$CLAUDE_SESSION_ID"`
   (or let it auto-expire via the claim's mtime+TTL).
1. **Scope**: work only `[ROUTINE]` items from ROADMAP.md, one item per session.
   Never start `[HARD]` items — they are reserved for the reviewer model.
2. **Definition of done**: the item's previously-failing tests pass, a refactor
   pass is done, and the FULL test suite is green. Nothing else counts.
3. **Test integrity**: never weaken, delete, skip, or rewrite a test to make it
   pass. The reviewer diffs all test files against the last relay checkpoint tag
   (`relay-ckpt-*`, or a historical `fable-ckpt-*`) and re-runs the original test
   versions; gamed tests will be found and the
   item reopened. If a test looks wrong or the spec seems ambiguous: STOP,
   append `BLOCKED: <item-id> <reason>` to RELAY_LOG.md, and pick another item.
4. **Self-report**: if the session did substantive work or hit a blocker,
   append one paragraph to RELAY_LOG.md — what was done, friction
   encountered, anything surprising — and COMMIT that append before the
   session ends (fold it into the final work commit or its own
   `chore(relay): session log` commit; never leave RELAY_LOG.md dirty).
   A session with nothing to report — e.g. the ROUTINE queue is empty —
   appends NOTHING and leaves the working tree untouched: an uncommitted
   "no work done" note is noise the reviewer has to clean up, not signal.
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

Append to `RELAY_LOG.md` (append-only, `merge=union` in `.gitattributes`).
Every append is COMMITTED in the same session (rule 4); append only when
there is something substantive to record — work done, a BLOCKED item, or a
surprise. No-op sessions write nothing:

- **Self-report entry** (end of every working session, rule 4 above; same
  heading format ckpt-tag.sh and all existing entries use):
  ```
  ## YYYY-MM-DD — executor (<model-tier>)

  Worked id:XXXX — <what was done>.
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

After bumping: update the `## Relay contract <!-- relay-executor contract vN -->`
pointer in the managed repo's `CLAUDE.md` to match.

For the human-facing picture of the whole relay (modes, artifacts, what the
user does between turns), see `docs/relay.md` in dotclaude-skills.
