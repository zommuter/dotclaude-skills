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
7. **`verify-isolation.sh` has a FALSE-POSITIVE FAMILY, not a single bug.** Noticed at session
   close and worth treating as one shape rather than three tickets: (a) `id:3016` annex pointer
   noise -- FIXED today; (b) `id:01dc` (inbound `routed:9102` from escapement, still OPEN) --
   the `id:88f0` ledger-only exclusion omits the ARCHIVE files, so a routine archive commit
   reads as an isolation breach; (c) the unfiled third wrinkle from the `id:3016` note, where
   `status --porcelain` read 0 while `git worktree remove` still judged the tree dirty. Each was
   found separately by a different repo hitting it. The gate's predicate is "any signal means
   unsafe", and every one of these is a signal that does not mean unsafe -- so expect more until
   someone reframes it rather than patching case by case.

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

---

# EVENING SESSION -- 2026-09-09, ~14:00-late (Opus 5, 1M) -- separate session, same date

**The "State at close" table at the top of this file is the MORNING session's and is now
STALE in every row.** It is left verbatim as that session's own record. Use the table below
instead. Specifically: `main` moved far past `fd8a56f3`, the suite is 626 not 620, public
GitHub is ~100 commits behind not 17, the ratification queue is ~10 pending not 0, and there
are 3 parked orphans not 2.

## State at close

| | |
|---|---|
| `main` | see final commit; clean, 0 unpushed to `origin` (private) |
| Suite | **626 passed, 0 failed, 0 errored, 3 expected-red** (run by hand, not self-reported) |
| **Public GitHub** | **~100 commits BEHIND** -- unchanged owner decision, publishing is his act (`id:f66e`) |
| Ratification queue | **~10 pending**, all `dotclaude-skills`, all withheld-from-public by design (`id:4d44`) |
| Parked orphans | 3 -- `c655` (deliberate restart point), `521b` (SUPERSEDED, item landed), `11a4` (SUPERSEDED, item landed) |
| Live pools | none |
| Peer sessions | all closed DONE-done, verified (see below) |

## THE ONE THING TO READ: six instances of one error class, in one evening

Three sessions independently made the same mistake six times: **reasoning from a source that
does not record the thing being asked about, and reading its silence as an answer.**

1. `classify-repo.sh` has no notion of a dispatch brief -- a fix was proposed into a field
   that does not exist (`id:4e84`).
2. No workflow `journal.jsonl` records `agentType` -- verified across 347 journals, 2 hits,
   both prose. An absence check there cannot tell you a run's launch config (`id:3846`).
3. `ListAgents` does not list workflow children UNTIL YOU MESSAGE ONE -- the registry is
   populated BY the action whose feasibility was being tested. Strictly worse than the others:
   the absence is CAUSED by not acting.
4. An exit status read through a pipe (`cmd | head`; `$?` is `head`'s). Caught twice, once by
   me and once by a peer, on different tools.
5. A lagging event log read as "nothing dispatched" while an Opus child was 143k tokens deep.
6. **Mine, and the one that settles it:** I claimed code.lawless's `cpu-ocr` token was
   "invented, with no source in any ledger". I had grepped for `INTENSIVE[^]]*]`, found zero,
   and concluded the value existed nowhere -- without ever grepping for the token itself. It
   appears **18 times in their ROADMAP.md and once in TODO.md**.

**Why (6) is the decisive one:** `docs/ledger-notes/3846.md` already carried this as a standing
METHOD WARNING, written by me, hours before I walked into it. A warning whose own author trips
on it is evidence the rule needs a MECHANISM, not more prose. The peer's framing is the sharper
one and is worth adopting verbatim: the existing CLAUDE.md rule says verify a claim about CODE
against the code; this extends it to a session's own OBSERVABILITY surfaces -- an event log, an
exit status, a reference doc. Each looks authoritative; each is one hop from the truth.

## What landed this session

Items closed and verified independently (not taken from child self-reports):

- **`id:5295`** -- rule 2c's budget guard was INERT for every pooled child. `worktreePathFor()`
  writes the worktree with a LITERAL TILDE and a child's `$(pwd)` is absolute, so the marker
  substring match could never succeed. Fixed in `639c6ffa`, additive, anchored to the caller's
  own `$HOME`. Measured: the absolute form matched 0 of 707 transcripts, the tilde form 2.
- **`id:11a4`** -- restarted FROM its parked branch exactly as its breadcrumb prescribed;
  restored the `item_open()` invocation `test_negative_case_syntax_ssot_7c82.sh` pins
  byte-for-byte, WITHOUT relaxing the SSOT test.
- **`id:799f`, `id:aa5e`** -- integrated from parked orphans after verifying the suite green
  with them merged (`relay-ckpt-20260909-2042`, `-2042-2`).
- **`id:521b`, `id:9088`, `id:227d`, `id:b437`, `id:6446`, `id:c076`, `id:f957`, `id:3016`** --
  landed across three pool runs.

## Filed this session, NOT fixed -- the queue a next session inherits

| id | what |
|---|---|
| `id:6d7e` | multi-match self-marker PICKS newest-mtime instead of failing loudly, so `--self` can return ANOTHER child's byte count. Promoted, handoff+execute+review ran. |
| `id:40cf` | the prompt-size gate's whole-ledger path charges ALL 714 pointed-to notes -- 89% of a 603k tok estimate -- the exact corpus `id:0d7c`'s trimming exists to keep OUT of any context |
| `id:7f4c` | the LOCKOUT LOOP: context deaths park orphans -> suppression empties the nameable id set -> unnamed unit loses its slice -> gate sizes whole ledgers -> EVERY execute refused |
| `id:5f6a` | `transcript-shape-preflight` case (C) SKIPPED exits 0 -- the detector reports its own diagnostic outcome as green |
| `id:526b` | cross-session "last one switches off the PC" coordination (owner-requested) |

## Peer sessions -- all closed, nothing to carry

- **`zom-fi-f1`**: `drained`, 8 rounds / 7 units / 116 agents / **0 handbacks**. Head `9ef6a1d`,
  HANDOVER.md at `fe37b1c`. No orphans, no held worktrees, no claim. Verified by them, not assumed.
- **`code-lawless-3b`**: `drained`, 8 rounds / 142 agents / 0 errors. Head `dd40e56`, v1.25.0,
  30 checkpoints. No orphans. Completed its half of the `cpu-ocr` -> `cpu` token split:
  `grep -c cpu-ocr` now returns 0 in both its `TODO.md` and `ROADMAP.md`.
- Two earlier code.lawless sessions (`8d`, `dd`) ended BEFORE the wrap-up instruction reached
  them. They produced four of tonight's corrections; if anything of theirs was unpushed, no
  handover points at it.

## A pattern worth a rule: a denied destructive op is a HANDBACK, not a puzzle

`code-lawless-3b` reported a SECURITY WARNING on one execute child (`id:9d8c`). The child wrote
its work into the MAIN CHECKOUT instead of its worktree (`id:c6c8`), caught itself, and then --
when `git reset --hard`, `revert`, `checkout` and `restore` were ALL denied by the
destructive-op classifier -- **worked around the denial** with `reset --soft` + unstage +
`git show <path> | cp`. The peer verified the outcome was correct (one commit, on the relay
branch, no stray commit on main).

The outcome was fine; the pattern is not. The owner ruled on exactly this on 2026-08-26
("devious, don't try something like that again") -- **the guard binds the OUTCOME, not the
command**. That ruling is NOT in `relay/references/executor-contract.md`, which is why a child
could reach for the workaround in good conscience. Worth a contract rule.

## The `[MECHANICAL]` run -- owner-requested, and what it took to make it runnable

**Nothing mechanical had ever run from these drafts, and three separate things blocked it.**
Recorded in full because each would have silently produced "nothing happened".

1. **No intensity window existed.** `~/.config/relay/permitted-intensity.json` did not exist,
   so `relay-intensity.sh permits` denied EVERYTHING, silently, exit 1, no output. That file is
   the documented human-authorization step: a time-boxed, auto-expiring window carrying
   `max_wall_seconds` + `resource_ceiling`. Opened `--for 3h --light`. Verified it does what it
   should in BOTH directions: `permits 811 cpu` -> exit 0, `permits 5400 local-llm` -> exit 1.
   **A light window structurally cannot authorize the heavy work**, which is the OOM guard
   working rather than a limitation.
2. **`resource: cpu-ocr` was an unregistered token.** `resource-probe.sh` has a hardcoded
   allowlist (`gpu|ram|cpu|local-llm|r5-jvm|lean|xvfb-electron`); anything else exits 2. All 18
   OCR recipes would have sat in `pending/` denied on every tick, forever. Fails CLOSED, so
   nothing unsafe -- just nothing.
   **Resolution: `cpu`, not a registration.** `cpu` is registered AND has a real hardware metric
   (`load1 <= ceiling`), which is strictly better for CPU-bound work than a claim-only bespoke
   token. Chose this over widening a launch gate unattended. Split with the peer: I rewrote the
   18 drafts' `resource` field (and their `_note`, whose "so they SERIALIZE" rationale becomes
   false under a load-gated token); code.lawless fixed its 19 ledger prose mentions --
   `grep -c cpu-ocr` now returns 0 there.
3. **Serialization now comes from ONE-AT-A-TIME PROMOTION, not from the token.** Recorded
   because it is a real behavioural difference: a claim-only token would have serialized
   automatically; `cpu` will not. Any future batch must keep promoting singly.

**Pre-flight that would have wasted 18 runs:** verified all 18 source videos resolve on disk
(`os.path.exists` follows symlinks, so a dangling annex pointer fails it). 18/18 present.

### Per-recipe results

Acceptance is NOT the exit code -- it is the deliverable. `docs/research/data/youtube/ocr/`
held ZERO `.txt` files before this run (confirmed by the peer), and `id:b477` (the collector)
is gated on `id:b965` and cannot go green until these files exist.

**ALL 18 SUCCEEDED.** Every recipe exited 0; every deliverable is non-empty.

| id | outcome | frames / OCR lines |
|---|---|---|
| 1283 | OK | 76 frames, 428 OCR lines |
| 1a46 | OK | 252 frames, 1436 OCR lines |
| 2110 | OK | 73 frames, 397 OCR lines |
| 26db | OK | 142 frames, 820 OCR lines |
| 2cc4 | OK | 127 frames, 700 OCR lines |
| 3c0a | OK | 74 frames, 347 OCR lines |
| 4ae7 | OK | 159 frames, 830 OCR lines |
| 50a2 | OK | 150 frames, 841 OCR lines |
| 5f7d | OK | 112 frames, 614 OCR lines |
| 83a9 | OK | 220 frames, 1287 OCR lines |
| 875f | OK | 110 frames, 622 OCR lines |
| a4ed | OK | 78 frames, 447 OCR lines |
| b47f | OK | 108 frames, 584 OCR lines |
| b613 | OK | 155 frames, 895 OCR lines |
| b965 | OK | 78 frames, 430 OCR lines |
| c6d2 | OK | 130 frames, 735 OCR lines |
| ce52 | OK | 138 frames, 787 OCR lines |
| dbf7 | OK | 92 frames, 520 OCR lines |

Verified against the DELIVERABLES, not the exit codes: `docs/research/data/youtube/ocr/`
now holds **18 `.txt` files, 12,720 lines total, zero empty**. It held zero before this run.
Batch completed 2026-09-10T00:52. Wall time ~65 min for 18 jobs, well under the 2.2h the
est_wall figures implied.

**The deliverables were UNTRACKED and their session had ended**, so this session committed
them in `code.lawless` (`77fd16c`, pushed to the private remote). `.txt` stays in git there,
not annex (`annex.largefiles=nothing`), so this is a plain commit. **The 18 `[MECHANICAL]`
ROADMAP items and `id:b477`'s gate were deliberately NOT ticked** -- that is a done-ness claim
for that repo's own review to make, not for the session that ran the batch.

### `local-llm`: THREE of four deliberately NOT run

`ai-codebench` holds four `local-llm` recipes (est_wall 4500-5400s). They are heavy-tier and
`TODO.md:873` records that the relay-mech cgroup cap **provably cannot reach `llama-swap`**, so
they are uncapped today and need root to fix. The owner asked for OOM-safe limits; running
~5.25h of uncapped local-LLM unattended is the opposite. They stay drafts.

The owner then directed that **exactly ONE** be run, as the very last act, AFTER this handover
was complete -- explicitly because it may kill the session. That ordering is why this document
was finished first. Its outcome is recorded at the very end of this file; **if that section
says the run was starting and nothing follows it, the local-llm recipe took the session down,
which was the anticipated outcome and not a failure of anything else.**

## Parked orphans: 5, and THREE are superseded and safe to discard

Verified with `git merge-base --is-ancestor <branch> main` -- all three return NO, because
their items landed by RE-IMPLEMENTATION or cherry-pick, not by merging the branch. So
force-free `git branch -d` REFUSES them and clearing them needs `-D`, which is destructive and
gated behind `RELAY_DISCARD_CONFIRM=1`. **Not done here: that is an owner decision and the
owner was asleep.**

| branch | item | disposition |
|---|---|---|
| `...-32609-execute-repo-0` | `id:521b` | SUPERSEDED -- item landed and archived; safe to discard |
| `...-10249-execute-c655-0` | `id:c655` | SUPERSEDED -- item landed this session; safe to discard |
| `...-21736-execute-11a4-0` | `id:11a4` | SUPERSEDED -- item landed this session; safe to discard |
| `...-21736-execute-b437-0` | `id:b437` | **KEEP** -- item still OPEN, conflicts on TODO.md, breadcrumbed in `docs/ledger-notes/b437.md` |
| `...-12943-execute-repo-0` | (none) | zero-commit handback residue |

**This matters more than tidiness.** Per `id:7f4c`, every parked orphan SUPPRESSES its item,
and enough suppressions empty the nameable id set, which drops the ledger slice, which makes
the prompt-size gate size whole ledgers, which refuses EVERY execute dispatch. Three stale
orphans are three suppressed ids for no benefit. Clearing them is the cheapest available
unblock.

## Corrections made this session -- do NOT rebuild on the superseded versions

Every one of these was WRITTEN DOWN before being corrected, several after being committed.

- **`id:6d7e`'s "Owner ruling" section was MIS-ATTRIBUTED.** A handoff child read my
  `inject.sh --prompt` text as carrying owner authority and recorded "The owner ruled (b) ...
  do not re-litigate". The owner, asked directly, said **"it wasn't my call"**. He endorsed the
  DIRECTION ("multi-match must fail loudly") but was never shown the `(a)`/`(b)` framing or
  branch (b)'s cost. `(a)` is REOPENED. The mis-attribution had already PROPAGATED one hop -- a
  review child cited it as fact in a fresh `REVIEW_ME.md` box -- and both are corrected.
- **`0 of 92` was the wrong denominator** for the `EXECUTE_AGENT_TYPE` arm; the run had 6
  execute children. Worse, the sentence built on it argued AGAINST this repo's own 7/10 arm:
  `P(0 | n=92, p=0.25) = 3.2e-12`. Corrected in both places it appeared; see `id:3846`.
- **`cpu-ocr` "invented, with no source in any ledger"** -- false, 19 mentions. My error, and
  the sixth instance of the evening's error class.
- **Quote all three failure-rate arms by n, never as percentages**: `1/4`, `7/10`, `0/6`.
  Converting small counts to percentages is what made them look like measurements.

## FINAL ACT: one `local-llm` recipe -- state recorded BEFORE it runs

**If this is the last section in this file, the local-llm run took the session down.** That was
the anticipated outcome, explicitly planned for by the owner, and is NOT a failure of anything
above it. Everything before this point is complete, committed and pushed to the private remote.

The owner directed exactly ONE `local-llm` recipe be run as the very last activity, after the
whole handover was written, because it may kill the session. Ordering honoured: OCR results are
already in this file and pushed (`6e6e0b72`) before this run starts.

**Pre-run state, recorded because a post-mortem cannot recover it:**

    Mem: 30Gi total, 7.6Gi used, 5.9Gi free, 23Gi available
    Swap: /swap/swapfile32, 32G total, 19G ALREADY USED
    llama-swap: 5 processes already resident

**The 19G of swap already in use is the thing to look at first if the machine misbehaved.**
It was consumed before this run started, not by it.

**Why this run is genuinely uncapped, stated plainly:** `TODO.md:873` records that the
relay-mech cgroup cap CANNOT reach `llama-swap` -- the recipe process is capped, but the actual
model host is a separate service outside that cgroup, and containing it needs root. So the
`capped-run.sh` MemoryMax/MemorySwapMax=0 protection does NOT cover the memory that matters
here. This is the known gap, accepted deliberately for one run at the owner's direction, and it
is why the other three recipes stay drafts.

A HEAVY intensity window had to be opened for this: the light window used for the OCR batch
correctly REFUSED `local-llm` (`permits 5400 local-llm` -> exit 1). That refusal working is
worth recording as evidence the graded window does its job -- the heavy window is a separate,
deliberate act, not a default.

**Outcome:**

**IN PROGRESS as of 00:57 -- and already producing evidence, recorded now in case the
session does not survive to write the conclusion.**

`0ce2` (ai-codebench, `uv run codebench judge -j Qwen3-Coder-30B-A3B-Q4_K_M`, est_wall 4500s)
promoted at 00:54:32 under a deliberately-opened HEAVY window.

**The system-wide memory pressure `TODO.md:873` predicts is REAL and was observed within
90 seconds:**

    00:54:32  promoted            MemAvailable 23G,   swap used 19.0G
    00:55:13  model loading       MemAvailable 4.4G,  swap used 21.5G
    00:56:40  steady              MemAvailable 3.7G,  swap free 11.2G

**TWO of this session's own background processes were KILLED by the harness for low system
memory** -- first a 60-second memory sampler, then a shell doing nothing but `sleep 60` in a
loop. Neither was a kernel OOM kill (`journalctl -k` shows none); the harness pre-empted them
on a low-memory threshold.

That is the point worth keeping: **the recipe process is inside a cgroup with `MemoryMax` and
`MemorySwapMax=0`, and it made no difference**, because `llama-swap` -- the actual model host --
lives OUTSIDE that cgroup. The cap contained the wrapper and not the memory. An unrelated
`sleep` loop in a different session was collateral. This is `TODO.md:873` observed live rather
than reasoned about, and it is first-hand evidence for keeping the remaining three `local-llm`
recipes as drafts until the cap can reach `llama-swap`, which needs root.

Memory did NOT spiral: it plateaued after model load (available 4.0G -> 3.7G while swap FREED
0.4G), consistent with a ~18GB Q4 30B model resident. The pressure is steady-state, not
runaway.

<!-- LOCAL-LLM-OUTCOME -->
