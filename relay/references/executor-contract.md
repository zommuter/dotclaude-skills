# Relay executor contract

This is the LEAN executor contract loaded by `/relay executor` at the start of an
executor session. It deliberately does NOT pull in the orchestrator (`relay/SKILL.md`):
a cheap Sonnet executor needs only the rules below.

## Executor contract <!-- relay-executor contract v15 -->

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
   pass is done (and **reported** via the `refactor:` self-report line, rule 4), and
   the FULL test suite is green. Nothing else counts.
   - **Driver ticks, not you (v12, id:5b12)**: when the item is done, DO NOT tick its
     `- [ ]` → `- [x]` checkbox in `ROADMAP.md` yourself. Return the item's 4-hex id in
     `worked_ids` and the **serialized integrator** ticks the box in the canonical checkout
     after your branch merges (`relay/scripts/roadmap-tick.sh`, driven from the integrate
     path). This is the one-writer inversion (meeting 2026-07-26-1922 D1): N parallel
     execute worktreees must not each edit the non-union checkbox line (`id:dc5b` C2), so the
     single integrator owns the tick. Your DoD is the green suite + the returned id — the
     checkbox flip is the driver's job, and it is idempotent, so a stray tick you leave does
     no harm but is not required and not your responsibility.
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

2c. **Mid-run context-budget check — checkpoint-and-handback before you die of
   `Prompt is too long` (id:5eeb)**: two loderite executors (run
   `relay-20260826-162405-7522`) died mid-unit with the verbatim API error
   `Prompt is too long`, orphaning partial work and suppressing re-dispatch until a
   human ran `/relay reconcile`. The cause was pure transcript accumulation — measured
   growth was LINEAR over 166-193 turns with no single line dominant — and both dead
   transcripts had already burned 64-77% of their budget INVESTIGATING BEFORE THEIR
   FIRST EDIT. Run the pure, read-only decision function `context-budget.sh` — this
   exact line, which needs no path you were never given (id:ff30):

   ```
   ~/.claude/skills/relay/scripts/context-budget.sh --self --marker "<your worktree path>"
   ```

   `--self` resolves YOUR OWN transcript via `self-transcript.sh` (id:ff30):
   `$CLAUDE_SESSION_ID` is the TOP-LEVEL session id, which is the *directory* holding
   your transcript — either `subagents/agent-<id>.jsonl` (flat) or, when you were
   dispatched by the Workflow pool, `subagents/workflows/wf_<id>/agent-<id>.jsonl`
   (nested); the resolver searches both shapes, so you need not know which you are
   (id:c219 — it once searched only the flat one, which made this check silently inert
   for every pooled child). `--marker` picks yours out from your sibling
   children — your worktree path is already in your dispatch brief above ("Your worktree
   `<wt>` on branch …"), so paste that. This is the whole reason the check is runnable:
   the pre-v14 form asked you for a transcript path that nothing in the dispatch chain
   has ever communicated to a child. `--bytes N` and `--transcript PATH` remain
   for callers that already know one. If resolution fails you get verdict `unknown` and
   exit 0 — a measurement failure never blocks your work, but it is never silent either.

   Run it at **two check points**:
   - **periodically** during a long unit (e.g. every several tool rounds, or whenever
     you notice the session feels long), and
   - **BEFORE your first edit** — i.e. at the end of the investigation phase, before
     you make your first `Edit`/`Write`/commit. This is the check point the 64-77%
     pre-first-edit spend demands: catching it only periodically still lets a unit
     burn most of its window before producing anything committable.

   On a `handback` verdict (exit 3): this is the id:8b1f **CUTOFF** branch, NOT rule
   2b's clean-worktree size-out branch — the disposition is the opposite. **Commit the
   work already done** (do not discard it), append a `HANDBACK: <item-id> context
   budget exceeded (<bytes> B)` line to RELAY_LOG.md and commit that too, then return a
   structured result with `contract_met=false` and `route="none"` — deliberately an
   EXISTING enum value (not a new one) so `handback-followup.py` needs no change and
   the item stays a plain, re-dispatchable `[ROUTINE]` item rather than being gated or
   re-tagged.

   **ZERO-COMMIT branch — the livelock guard (id:5eeb).** If the budget is exceeded and
   you have **nothing committed for this item**, a plain `route="none"` handback writes
   NOTHING durable: `handback-followup.py` makes `route="none"` a literal no-op and the
   `HANDBACK:` prose line has no machine reader, so re-dispatch reproduces the same
   investigation and the same empty handback forever, with no accumulating signal. This
   is not hypothetical — it is the measured case: the threshold was crossed at line 95
   of a unit whose first `Edit` was at line 133, so the pre-first-edit check point is
   precisely what GUARANTEES the empty handback in the case it was designed for.
   Therefore:
   1. Use the DISTINCT, greppable form — note the trailing marker:
      `HANDBACK: <item-id> context budget exceeded (<bytes> B) ZERO-COMMIT`
      The `ZERO-COMMIT` suffix is the machine-readable accumulator; without it the
      occurrence is invisible to the next executor and the loop closes again.
   2. **Before writing it, count prior occurrences** for this item:
      `grep -c "HANDBACK: <item-id> .*ZERO-COMMIT" RELAY_LOG.md`. If the count is
      **≥ 1** — this is the second or later zero-commit handback for the same item —
      return `route="hard-split"` instead of `route="none"`. `hard-split` is an
      EXISTING enum (see 2b), so this still needs no `handback-followup.py` change, and
      it routes the item to decomposition rather than to another doomed attempt.
   Commit the RELAY_LOG.md line even though you have no work commit: on a zero-commit
   handback that line IS the deliverable.

   A `warn` verdict is advisory only (exit 0) — **except at the pre-first-edit check
   point, where it is the actionable NARROW-SCOPE signal, not a shrug.** In both
   measured units the warn fired with 34 / 74 lines of headroom remaining: enough to
   produce a committable slice, not enough to finish a broad reading of the codebase.
   So on a pre-first-edit `warn`, stop investigating and NARROW — pick the smallest
   coherent slice of the item you can implement and commit NOW, then hand back the
   remainder as a normal scoped handback. This is what keeps the zero-commit branch
   above rare: it converts the doomed-broad-attempt shape into a small landed slice
   plus a scoped remainder. A periodic `warn` away from the investigate→edit boundary
   stays purely advisory — keep working, but budget your investigation accordingly.

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
   - **Refactor claim (id:108e)**: a self-report for substantive work MUST carry a
     `refactor:` line — either `refactor: <what you cleaned up>` (extracted a helper,
     removed the duplication the RED spec forced, deleted dead scaffolding, …) or
     `refactor: none needed — <one-line reason>` (e.g. "one-line change, no new duplication").
     A **blank/absent** `refactor:` line is a violation, exactly like an empty
     `# swallow-ok:` — it exists to make rule 2's refactor pass a **conscious, on-record
     decision** instead of a silently-skipped step. It is a **forcing function, not a
     proof**: `none needed` is a legitimate, common answer for a small item, and the
     reviewer only flags it when the committed diff visibly contradicts it (leftover
     duplication/cruft — review.md §2b). Do NOT invent a fake refactor to fill the line.
5. **Hygiene**: commit early and often with conventional messages; never force-push;
   never edit ROADMAP.md item definitions, and never tick its checkboxes — the DRIVER
   ticks from your `worked_ids` (rule 2, v12/id:5b12); pamac not pacman; uv for Python.
5b. **Clean-worktree exit gate (id:373e)**: leave your worktree CLEAN — at the end of the
   unit `git status --porcelain` in your worktree must be EMPTY. Reach that state by SENSIBLE
   means only: **commit** every piece of legitimate work (including a regenerated lockfile —
   `uv.lock`/`package-lock.json` — per the bump-includes-lockfile rule), and **gitignore**
   genuine throwaway (`__pycache__/`, `.pytest_cache/`, coverage/build outputs; gitignored
   files do NOT block worktree removal). You MUST NOT reach a clean tree by DISCARDING work —
   no `git checkout -- <path>`, `git restore`, `git reset --hard`, `git clean`, `git stash`
   (and never `git stash drop`/`clear`). That is **gaming**: the reviewer re-derives the
   roadmap and re-runs tests on the *committed* state (rule 3), so any change you reverted to
   look clean resurfaces as a missing feature or a red test, and the item is reopened.
   A tree still dirty at exit means the unit is INCOMPLETE → hand it back (structured handback
   per 2b, or a clean size-out), do not paper over it. The integrator retires worktrees
   **force-free** (`worktree-retire.sh`, id:373e): a dirty worktree is SURFACED and LEFT on
   disk for a supervised reconcile — it is NEVER force-cleaned — so a dirty exit strands your
   work visibly instead of getting silently discarded. Leaving the tree clean is therefore
   YOUR responsibility, not the integrator's to force.
5c. **Symbol-level exploration — prefer Grep/Glob/LSP over uncapped Read (id:6f1c)**:
   locate code by name or shape with **Grep**/**Glob** (find the file, the call site,
   the definition) and by symbol with **LSP** (`documentSymbol`/`goToDefinition`/
   `findReferences`/`hover` — enabled in this repo's `settings.json`) BEFORE reaching
   for a full-file `Read` or an uncapped `cat`/`grep -rn` shell-out. A full `Read` costs
   roughly 5-6x an `LSP documentSymbol` call on the same file (measured: ~3,500 tok vs
   ~600 tok) — reserve it for when you actually need the file's full body, not to locate
   something in it. **Never re-read a file already open in this session's context** — a
   file you have already Read (in full or in part) is already in your context; re-Read
   it only if you have positive reason to believe its on-disk content changed since your
   last read (e.g. you just edited it, or another process could have). Needing to look at
   it again with unchanged content is a signal to re-orient from what you already hold,
   not to re-fetch it. (Measured cost of ignoring this: one dead child re-read the same
   file five times across a session for ~28k tokens on that file alone, with zero Grep/
   Glob/LSP calls anywhere in its history.)
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

7. **Never write `@owner-accepted` (id:8089, v10 — provenance rule)**: the
   `@owner-accepted:YYYY-MM-DD` marker (review.md §5c) gates a user-visible/`@manual`-
   acceptance item's bump-close on genuine owner acceptance. Because the incident that
   motivated this rule was exactly a drain/executor session asserting acceptance on a
   "driver's directive," you as an executor or drain session **MUST NOT** write, add, or
   edit an `@owner-accepted` marker anywhere in this repo, under any circumstance — not
   even when told to by the driver. Only a genuine owner action may write it. The reviewer
   greps the diff for an executor-introduced marker (review.md §2b.7) and will FLAG +
   REOPEN the item if it finds one.

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

Do NOT tick the checkbox (`- [ ]` → `- [x]`) yourself (v12, id:5b12) — report the
item's id in `worked_ids` and the driver/integrator ticks it after the done-check passes
and your branch merges. Never edit the Acceptance / Tests / Done-check / Context fields.

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

**v11 → v12 (id:5b12, seam of id:ae08):** tick-ownership inversion. Execute/hard children
no longer tick their own `ROADMAP.md` checkbox; they return `worked_ids` and the serialized
integrator ticks the box in the canonical checkout (`relay/scripts/roadmap-tick.sh`). This is
behaviour an in-flight executor must know (rule 2 / rule 5 / the ROADMAP-format tick note), so
it bumps. Transition is safe: `roadmap-tick.sh` is idempotent, so an in-flight v11 executor
that still ticks in its worktree plus the new integrator tick is a harmless double-flip.

**v12 → v13 (id:5eeb):** new rule 2c, a mid-run context-budget check
(`relay/scripts/context-budget.sh`) run periodically AND before the first edit, with a
checkpoint-and-handback disposition (commit work done, `HANDBACK:` RELAY_LOG.md line,
`contract_met=false` / `route="none"`) on a `handback` verdict — this prevents the
`Prompt is too long` death class instead of the executor dying and orphaning a
worktree. This is behaviour an in-flight executor must know (a new check point and a
new disposition), so it bumps.

**v13 → v14 (id:ff30):** rule 2c's command is now RUNNABLE. v13 told you to run
`context-budget.sh --transcript <PLACEHOLDER>` — a path nothing in the dispatch
chain has ever communicated to a child (`grep -rn 'transcript_path\|transcriptPath' relay/`
returned nothing), and whose `--bytes N` alternative needed a size obtainable by no means
either. So v13's rule 2c could not be executed at all and prevented zero context deaths.
v14 names `context-budget.sh --self --marker "<your worktree path>"`, backed by the new
`relay/scripts/self-transcript.sh`, which resolves the calling agent's own
`<session>/subagents/agent-<id>.jsonl` and disambiguates siblings by a string from its own
dispatch prompt. This changes the command an in-flight executor must run, so it bumps.
(Historical note, id:c219: as shipped in v14 the resolver searched ONLY that flat path,
so it resolved nothing for a Workflow-dispatched child — whose transcript is one level
deeper, under `subagents/workflows/wf_<id>/` — and rule 2c was therefore silently inert
for every pooled executor until the resolver was made depth-agnostic on 2026-08-27. The
v14 COMMAND above is unchanged and remains correct, which is why that fix carried no
version bump.)

**v14 → v15 (id:5eeb, owner-ratified 2026-08-26):** rule 2c gains a ZERO-COMMIT branch
and promotes the pre-first-edit `warn`. v14's handback disposition was a LIVELOCK in the
exact case the pre-first-edit check point exists to catch: measured, the threshold was
crossed at transcript line 95 of a unit whose first `Edit` was at line 133, so the
handback fired with **zero commits** — and `route="none"` is a literal no-op in
`handback-followup.py:181` while the `HANDBACK:` prose line has no machine reader
(`grep -rn 'HANDBACK:' relay/scripts/` = 1 hit, a comment). Re-dispatch therefore
reproduced the same empty handback forever with no accumulating signal. v15 adds (a) a
distinct greppable `… ZERO-COMMIT` handback form whose prior-occurrence count the
executor itself reads, escalating to the EXISTING `route="hard-split"` enum on the
second occurrence, and (b) a pre-first-edit `warn` that is now an actionable
NARROW-SCOPE instruction rather than advisory, since in both measured units it fired
with 34 / 74 lines of headroom still available. Both change what an in-flight executor
must do on a verdict it can already receive, so it bumps. No new enum and no
`handback-followup.py` change — deliberately, per the ratified option (a).

For the human-facing picture of the whole relay (modes, artifacts, what the
user does between turns), see `docs/relay.md` in dotclaude-skills.
