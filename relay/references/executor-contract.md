# Relay executor contract

This is the LEAN executor contract loaded by `/relay executor` at the start of an
executor session. It deliberately does NOT pull in the orchestrator (`relay/SKILL.md`):
a cheap Sonnet executor needs only the rules below.

## Executor contract <!-- relay-executor contract v7 -->

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
   - **Host gate (multi-host config monorepos only, id:43b9)**: if the item carries a
     `[host:<name>]` tag (e.g. `[host:zomni]`/`[host:fievel]`; absent ⇒ `host:any` ⇒ this
     gate is a no-op, which is every ordinary single-host repo), run
     `~/.claude/skills/relay/scripts/host-gate.sh '<the item line>'` BEFORE you verify.
     On exit 3 (host mismatch) you CANNOT establish the definition-of-done here — the item's
     `make install`/tests are HOST-BOUND (you cannot validate another machine's apt path,
     udev rule, etc. on this host). **DEFER**: append `DEFERRED: <item-id> needs host:<X>
     (on <this-host>)` to RELAY_LOG.md, leave the checkbox UNticked, and pick another item.
     Do NOT run install/tests on the wrong host. EDITING the files is host-agnostic and fine;
     only the verification is gated. (Documented future option, NOT built: ssh-to-host
     verification — for now defer is the safe default.)
2b. **Size-out (ROUTINE items)**: if you pick a `[ROUTINE]` item and determine it is
    too large to land green in one session AND you cannot partially advance it to a
    committable sub-seam, you MUST NOT silently leave it open. Soft notes (`friction:`
    commit line, `BLOCKED:` RELAY_LOG line) are **not sufficient** — the integrator's
    durable handback follow-up (`handback-followup.py`, id:3801) reads ONLY the
    structured return fields, never the soft notes, so a soft-only size-out leaves the
    item a plain open `[ROUTINE]` and the next discovery round re-dispatches the same
    un-doable item to another executor (the re-dispatch spin).

    **Required action**: return a structured handback:
    - `contract_met=false`
    - `handback_item` = the 4-hex id of the sized-out item
    - `route` = `"hard-split"` (item is too large but decomposable into smaller seams;
      populate `proposed_split` with an ordered seam array) **or** `"decision-gate"`
      (needs a design decision before it can be built) **or** `"human"` (needs a
      manual human action)
    - `gate_reason` = one short line for the inline ROADMAP note

    Exactly like the `[HARD]` size-out discipline (id:8b1f): leave the worktree
    **completely clean** — make NO commit; write the rationale ONLY in the `handback`
    field, not in RELAY_LOG.md / ROADMAP.md / REVIEW_ME.md. A clean worktree is
    auto-reaped; any commit on a refusal strands as an orphan worktree.

    The id:3801 gate then re-tags the `[ROUTINE]` parent to `[HARD — decision gate]`
    (or applies the appropriate split/human follow-up), stopping the re-dispatch spin.

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
6. **`@needs-auth` wall — record-and-continue, never strand (D3, id:a505)**: if you
   hit an interactive-auth or human-held-secret wall you cannot clear unattended (sudo/
   askpass, polkit/pamac, ssh/login, gpg/credential, browser-OAuth, a decryption
   passphrase, a private export), do NOT fail the whole unit and do NOT `sudo`. RECORD a
   conforming `@needs-auth` box in this repo's `REVIEW_ME.md` with all FOUR mandatory
   fields — **what-secret · where-it-goes · exact-command · why** — then clean-continue
   the SEPARABLE remainder of your unit (the work that does not depend on the secret).
   **When separability is uncertain, default to a clean handback of the gated remainder**
   (leave it for a human) rather than guessing. `@needs-auth` is the convention defined in
   `relay/references/hard-lanes.md`; it is ORTHOGONAL to `@manual` (an item may carry both:
   `@needs-auth` = a human must PROVIDE a secret; `@manual` = a human must RUN/verify). The
   box is the durable record — the offline lister (`gather-human-backlog.sh`, id:1750)
   surfaces it to the human; a stranded unit with no box is the failure this rule prevents.

## ROADMAP item format (reference)

Each ROADMAP.md item you pick has this shape:

```
- [ ] <title> [ROUTINE] [host:<name>] <!-- id:XXXX -->
  - **Acceptance**: what "done" means (observable behaviour, not process).
  - **Tests**: `tests/test_<name>.sh` (`# roadmap:XXXX`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_<name>.sh` then full `make test` after ticking
  - **Context**: key files, related TODO ids, scope guards.
```

The `[host:<name>]` modifier is OPTIONAL (multi-host config monorepos only) — see rule 2's
host gate. Absent ⇒ `host:any` ⇒ verifiable on any host.

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

### Purity-test-as-contract

Any component documented as **read-only / snapshot / pure** (e.g. a discovery producer,
a classifier shard, a status reporter) MUST ship a purity test built on the shared
helper `tests/lib/assert-repo-unchanged.sh`: PLANT a repo (a commit + a dirty/untracked
file + a live worktree), run the component, and assert the repo state is byte-identical
afterwards (`repo_state_snapshot` / `assert_repo_unchanged` — no commits, no ref moves,
no worktree add/remove, HEAD/reflog/porcelain unchanged). This generalizes the pattern
`tests/test_discovery_producer_readonly.sh` proved against a real near-miss (id:758e,
2026-07-07): a component *labeled* read-only had an undetected side-effecting path, and
without a purity test that label was unverified tribal knowledge. Write the purity test
cheaply from the shared helper instead of hand-rolling a bespoke snapshot/diff each time.

## Maintenance

**Bump the version number** (v1 → v2, etc.) **only** when a rule or artifact
format above changes in a way an in-flight executor session must know about.
Typo fixes and clarifications that don't change behaviour do **not** bump.

After bumping: update the `## Relay contract <!-- relay-executor contract vN -->`
pointer in the managed repo's `CLAUDE.md` to match.

For the human-facing picture of the whole relay (modes, artifacts, what the
user does between turns), see `docs/relay.md` in dotclaude-skills.
