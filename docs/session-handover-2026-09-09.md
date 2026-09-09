# Session handover -- 2026-09-09 (Opus 5, 1M)

Point-in-time snapshot. Durable detail lives in the ledger items and notes cited below -- read
those; do not trust this doc if it disagrees with them. Supersedes nothing: the 09-08 handover
still stands for its own session, and its corrections (made this morning) are still valid.

## State at close

| | |
|---|---|
| `main` | `fd8a56f3`, clean, **0 unpushed to origin** |
| Suite | **620 passed, 0 failed, 0 errored, 4 expected-red** |
| **Public GitHub** | **17 commits BEHIND** -- see "Needs an owner decision" |
| Ratification queue | **0 pending** (16 resolved with landing evidence this session) |
| Parked orphans | 2, both breadcrumbed onto their items |
| Live pools | none of mine; a peer session (`code.lawless`) was launching at close |
| `mechanical-proxy.py` | pid 133800, digest `589ffc4251c0`, `current` |

## READ FIRST: the thing that cost the most time today

**An over-broad `permissions.ask` rule is indistinguishable from a hang in any unattended
context.** The 09-08 overnight pool did not crash -- it BLOCKED on a permission prompt for
`cd … && git checkout -- <one file>`, because `Bash(git checkout -- *)` sat in `permissions.ask`
and its glob matches the safe single-file form and the irrecoverable tree-wide form
identically. Nobody was awake. It sat wedged for two hours until the machine was shut down.
Diagnosis `id:76e4`; the four wrong things the previous handover said about it are corrected
in place there.

**Fixed** (`~/.claude` `8fa066f3f`): `checkout`/`restore` moved to `allow`, with the expressible
tree-wide spellings kept in `ask` as EXACT matches. Verified by running the exact incident
shape (`cd <repo> && git checkout -- f.txt` -> no prompt) and the dangerous one
(`git checkout -- .` -> refused, canary intact).

**The class is NOT closed.** Every remaining `ask` entry is currently SHADOWED by
`destructive-git-guard.py` (all 13 real command forms verified denied, and the hook fires
first), but shadowing is two mechanisms agreeing, not one design. If the hook is ever unwired,
all ten become live pool-hangs again. Nothing tests that the two lists agree. The owner
DECLINED widening the `allow` set to `reset --hard` / `clean` / `stash drop` -- correctly:
those have no bounded path-scoped form, so the property that made checkout/restore safe does
not hold for them. **Do not re-propose it.**

## What landed

* **`id:3016` -- annex false-dirty in `verify-isolation.sh`** (`53d43bcd`). A bare
  `status --porcelain` non-empty test called every git-annex worktree DIRTY, so an execute unit
  handed back on EVERY round on `code.lawless`/`zkWhale`. Relaxation is narrow ON PURPOSE: clean
  only when every entry is the exact ` M` pair AND `git diff --quiet` passes -- untracked stays
  dirty, which is most of what the gate exists to catch. Verified end-to-end on a real annex
  worktree (85 entries, exit 0, and it went on to report "2 commits beyond main"), not only on
  the fixture.
* **`id:f957` -- the HARD lane could never be sliced** (`6cb345a5`). `dispatchItemFor` read
  `actionable_routine_ids` only, which a `hard` unit has none of by construction, so it was
  sized on whole ledgers and `loderite` refused forever. Now slices on `open_hard_pool_ids` via
  `--ids`: 1,659,917 B -> 21,496 B, ~77x.
* **`id:0ec3` -- the delimiter migration**: built the missing converter
  (`lane-delimiter-convert.sh`) and converted **649 live lane tags across 39 repos**, one commit
  per repo. `dotclaude-skills` excluded by owner instruction. 8 deferred deliberately.
* **`id:1048` auto-integrate WIRED, OFF BY DEFAULT** (`3ffdc8cc`). Flag verified off across
  eight input forms including junk. Turning it on is an owner decision.
* **ack-token collision + `id:3016` remedy wording** (`fd8a56f3`) -- see "Two late defects".
* `parked_orphan` kind in `gather-human-backlog.sh`, so `/relay human` finally shows parked
  refs; breadcrumbs on `id:521b`/`id:c655` so the next executor does not rewrite parked work.
* `project_manager` `scan.py` dual-delimiter fix (`d1e3c58`, `a1bdf53`).

## Two late defects, both reported by the peer session AFTER the merge

Both real, both fixed in `fd8a56f3`:

1. **The `--discard-residue` `--ack` token collided across worktrees.** The digest covered
   residue BYTES but not worktree IDENTITY, so a token from one worktree authorised discarding
   another the operator had never inspected. On an annex repo that is the NORM (identical
   pointer noise everywhere), not an edge case. Reproduced both ways: pre-fix both minted
   `2c7ad767e895`; post-fix they differ. **Any `--ack` token minted before this is now invalid**
   -- deliberate, fails safe.
2. **The `id:3016` gate's own remedy line was wrong.** It told everyone to run
   `git annex restage`, which silently NO-OPS while `.git` is still a symlink -- the normal
   state of a fresh relay worktree. `id:de4a`'s `.git` normalisation is a PREREQUISITE, not an
   adjacent fix. The gate now detects the symlink case and says so.

## Needs an owner decision

1. **17 commits are unpublished to public GitHub.** `id:f66e` makes publishing never automatic.
   The last publish (85 commits) was explicitly authorised this session after a privacy audit;
   these 17 have had no such decision. Audit method that works, since the naive one does not:
   run all patterns from the private pattern file over `git diff github/main..main`, and
   **check that every pattern actually ran** -- a first attempt here silently executed 22 of 23
   and looked complete. The prior audit's only hits were the intentional-provenance class
   (session UUIDs, trailer addresses), already public at 6,753 lines.
2. **`id:79a9`** -- repeat handbacks re-dispatch the same item; `repeatHandbacks`
   (`relay-loop.js:4998-5016`) detects at threshold 2 and alters nothing. The `id:4d8e`
   detection-with-no-op-resolution class. Carries an UNRESOLVED gate-vs-selection question with
   two very different blast radii; needs an inside-the-loop diagnosis, not an outside patch.
3. **`id:1048` auto-integrate is wired but OFF.** Enabling it grants the pool autonomous
   merge-to-main. Note its reach is narrower than "all parked orphans": GATE 1 requires the
   bound item ticked `[x]`, and the executor contract forbids executors ticking their own boxes,
   so pool-produced id-bearing orphans normally FAIL it. It would not have taken either of our
   current two.
4. **The 4 remaining `[HARD — lane]` tags** need the VOCABULARY migration (`lane-convert.sh`)
   before their delimiter can move; and `relay-core`'s 4 were skipped for a dirty ledger.

## Open threads

1. **`/relay human --all`** is still the unlock for the fleet: 43 gate targets, and
   `58ca`/`9ee4`/`80d4` hold 21 items between them. Everything else is genuinely gate-blocked --
   verified, every open `[HARD]` in the nine candidate repos is gated, 0 ungated of 33. Best run
   in a FRESH session. Cross-check its `review_me` count against the mechanical collector's
   ~321; `id:9d06` has it reporting zero.
2. **`id:521b` and `id:c655` parked work** -- both reviewed NEEDS-WORK, both now breadcrumbed.
   `id:521b` is additionally blocked by `id:9088` (its RED spec's case 3 is unsatisfiable: the
   fixture title is 194 chars against the 200 it must exceed, so no implementation can pass).
3. **`id:73a0`** -- prevention hook for out-of-worktree child edits. Filed because the executor
   contract already says "worktree" 18 times and 6 of 12 children read no governing doc at all.
4. **`id:3846`** -- the trimmed `relay-implementer` STILL dies `Prompt is too long` (1 of 4 this
   session). `id:c3c1` step 4 is partially effective, NOT validated. Do not close it on dispatch
   success.
5. **`id:95c8`** -- `control-board.sh` under-counts human-lane items (helferli 2 of 19). Three
   hypotheses already tested and rejected in the note; do not re-run them.
6. **Four `manual/*` branches are merged but not deleted** -- safe to delete whenever.

## Method notes, so they are not re-derived

* **`node --check` CANNOT parse `relay-loop.js`** (top-level `return`); it errors on unmodified
  code. Use `workflow_node_check` from `tests/lib-workflow-check.sh`, AND the `id:aec5`
  all-builders exec harness, which actually evaluates every prompt template.
* **Grepping transcripts for `Prompt is too long` overcounts ~21x** -- mechanical `bash` hops
  quote it in RELAY_STATUS payloads. Filter to `isApiErrorMessage:true` / `model:"<synthetic>"`.
* **Installed relay scripts are per-file SYMLINKS into the repo**, so an edit is live in any
  running pool the instant it is SAVED. `make install-relay` matters only for a NEW file.
  Waiting for someone's commit or install is NOT protection; only not-editing is.
* **A merge that changes `ALLOWED_RELAY_SCRIPTS` requires a `mechanical-proxy.py` restart**, or
  the next launch refuses at step 0b on a STALE digest. `systemctl --user restart
  mechanical-proxy` suffices (user unit, no sudo).
* **Three counting misreads happened today**, all the same shape: measuring something ADJACENT
  to what the code measures (all ASCII occurrences vs open ROADMAP items; 21 grep hits vs 1 real
  API error; 2-of-19 vs the tag count). Measure the thing the code measures.
