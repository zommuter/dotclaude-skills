# Session handover -- 2026-09-12 (Opus 5, 1M context)

Successor to `docs/session-handover-2026-09-11.md` (318 lines, two stacked sections). That file
stays as the previous day's record. Its **AUTHORITATIVE CLOSE STATE table is now stale in every
row** -- see the comparison below rather than reading it as current.

Point-in-time snapshot. Durable detail lives in the ledger items and `docs/ledger-notes/<id>.md`
files cited here; read those, and do not trust this doc where it disagrees with them.

This session was a single `/relay --afk --exclude unidle` run plus a handover check. It is a
THIN day by comparison: one pool, no owner rulings, no publish.

## State at close

| | |
|---|---|
| `main` | clean, 0 unpushed to private origin |
| **Public GitHub** | **38 behind** -- NOT published today; 4 of those merges are ratification-gated (below) |
| Suite | **656 passed, 0 failed, 0 errored, 1 expected-red** -- re-run independently at load ~5.4 with one `lake build` active, not taken from an agent's report (it happens to match the `id:401c` child's claim) |
| Parked orphans, fleet-wide | **3** (dotclaude-skills x2, loderite x1) -- all `id:f272` WIP-residue auto-commits |
| Retirable relay worktrees | **15**, flagged no-work-at-risk by `relay-reconcile.sh --all` |
| Shared inbox | **1 open** -- `routed:5915`, a genuine dead-letter (twin verified ABSENT) |
| REVIEW_ME here | 96 open (was 86) |
| Stale STOP sentinels | 1, now 17 days old -- FILED at last as `id:f518` |

### What changed since yesterday's close, row by row

Yesterday's afternoon table is reproduced here only to show the delta. Do not read the left
column as current state.

| Row | 09-11 close | Now |
|---|---|---|
| Public GitHub | 0 behind, published twice | **38 behind** |
| Parked orphans, fleet | 0 across 61 repos | **3** |
| Leaked/retirable worktrees | 0 | **15 retirable** |
| Shared inbox | 0 open | **1 open** |
| REVIEW_ME here | 86 | **96** |

## READ FIRST: `EXECUTE_AGENT_TYPE` was forgotten again, and that is now the strongest fact about it

Yesterday closed with the posture **"Flag stays ON, unpromoted"** and Needs-owner #1: decide
whether `relay-implementer` becomes the DEFAULT execute agent type. It is still not the default.
**Today's pool did not pass it.**

That is the THIRD recorded instance of the same shape, and `id:3846` already names it:
code.lawless adopted the flag at 15:55 on 09-11 and had silently dropped it by 20:18; yesterday's
own close pool carried it; today's did not. The note's conclusion stands and is now better
evidenced than any success count: *"a mitigation that must be remembered per launch was in fact
forgotten, silently, by a session that had it working"* is **a better argument for making the
flag a default than any success count is.**

**Two process failures produced today's instance, and both are mine, not the owner's.** The
front-door procedure has no step that reads the previous handover's standing rulings, so nothing
surfaced ruling #7 at launch. And when the deaths appeared I told the owner the flag was "the
remedy" that had merely not been passed -- overstating a mitigation this repo's own ledger
records as *"partially effective, not validated"* (`id:3846`) and as structurally unable to
prevent the mid-run death mode (`id:677b`). The correction came from reading the handover, which
is the document that already said so. **If you build one thing from this file, make it the launch
-time surfacing of standing rulings**; the measurement below is secondary to it.

## The measurement: a second without-flag arm, and `7/10` should stop being quoted

Banked as an additive section on `docs/ledger-notes/3846.md` (nothing above it edited).

Counted by that note's OWN mandated method -- execute-lane denominators from the workflow
journal's `"label":"execute*"` records (the `id:c3c1` DENOMINATOR CORRECTION method), deaths from
the harness's structured `type:"failed"` records rather than a transcript grep, so the 21x
quoted-mention overcount the METHOD NOTE warns about cannot arise. The two sources agree exactly
at 5.

| repo | died / execute children |
|---|---|
| dotclaude-skills | **3 / 6** |
| loderite | 2 / 3 |
| mathematical-writing | 0 / 5 |
| code.lawless | 0 / 1 |
| project_manager | 0 / 1 |

Fleet 5/16. All five on `execute`; 0 on `review`/`hard`, which run Opus -- the same lane
selectivity every prior arm found.

**Standing arms on THIS repo, quoted as n/N per that note's rule:** `1/4` with the trim, `7/10`
without (09-09), **`3/6` without (today)**. Plus `0/6` with, cross-repo.

**What this does and does not license.** The two without-flag arms are nominally the same
condition on the same repo and they are far apart. Under the owner's pilot-sample heuristic
(n=10 cannot separate rates within ~10pp) neither is impeached and this is not a contradiction.
But `7/10` must stop being quoted as THE without-flag baseline: pooled it is `10/16`, and `3/6`
alone sits close enough to the with-flag `1/4` that the gap is no longer visible at these sizes.
**Any statement of the form "the trim cuts 70% to 25%" is unsupported** -- and was already
forbidden by that note's own never-as-percentages rule.

**The confound matters more than the arms.** `id:677b` (filed 09-11, after both earlier arms)
establishes at least one death is MID-RUN context accumulation, which the flag structurally
cannot prevent. So the arms pool two mechanisms, which is why the numbers move. **Split the arms
by death mode before collecting a fourth**; a fourth undifferentiated arm answers nothing. The
first question is still `id:677b`'s: did executor-contract rule 2c fire, return `unknown`, or
never get reached?

## The pool run

`relay-20260912-191938-25818` (`--afk --exclude unidle`, no `--once`, no
`--execute-agent-type`, no `--quota-7d`): **7 rounds, 679 agents, 20 units integrated, 15
handbacks, `stopReason: blocked-pending-human`**, quota never the stopper.

All four preflights green at launch: `mech-preflight` `proceed` and therefore the `id:0384`
currency check, which reported `current` (proxy pid 2735). `check-install-drift` clean.
`transcript-shape-preflight` exit 4 INDETERMINATE -- a fresh session with no children yet, which
is "could not look", NOT an all-clear, and is the expected value at launch.

Integrated across project_manager, code.lawless, it-infra, mathematical-writing, loderite and
here. Four checkpoints on this repo: `2004` (review: `0fad`/`fac7`/`6294`/`6fda`), `2038`
(hard `6294`), `2102` (hard `68c1`), `2151` (hard `401c`). `backtest-verdict.py --append-log`
posted `agree=2 diverged=65 red=0 expected=65 crashes=0` -- both gates green.

**The larger loss was not the 5 deaths.** 4 of 16 execute children never got a workable item at
all (`empty permitted-id set`). See `id:cbee` below.

## Filed today

* **`id:cbee`** -- `empty permitted-id set (id:c076)` is BACK: 4 execute handbacks across
  dotclaude-skills, loderite and mathematical-writing (x2), each self-classified as a
  classifier/queue wiring fault and each correctly refusing to survey ROADMAP.md and pick
  something that looked open. This is a REGRESSION signal: `id:677b` records the prior run
  producing `item=b437 eligible=1` and calls the c076 fix working. Either a second path into the
  same empty set, or a partial fix. **Deliberately NOT re-fixed from the handback text** -- those
  children saw only the dispatch-time condition, never the classifier. Start from the run's
  discovery objects.
* **`id:f518`** -- nothing reaps a targeted STOP sentinel whose run never reached a dispatch
  decision. `STOP.relay-20260826-162405-7522` is 17 days old and was carried forward as "still
  unfiled" by BOTH the 09-10 and 09-11 handovers. Harm is low by construction (`id:cd94`
  targeting means it cannot false-stop another pool, which is why it survived) but the litter is
  indistinguishable by eye from a live pending stop, and the same missing reaper applies to the
  un-targeted broadcast `STOP`, which CAN false-stop the next pool. Shape: reap a targeted
  sentinel whose runId is absent from `heartbeat.sh live-runs` -- the same liveness source
  `stop-request.sh` already resolves against, so no new notion of liveness is introduced.

## Also landed

* **5 inbox dead-letters auto-filed** from unidle by `scan-routed.sh --apply` (invariant 1),
  each committed separately: `8ecc` (`/relay human` skips `bucket == "untagged"`, so unlaned
  items are invisible to the interactive mode while verdict `human` files them pool-only),
  `28ad` (`roadmap-lint.sh --strict` has no duplicate-id check; root cause is `md-merge.py:850`
  half-applying a `## ` payload containing a `###`), `567f` (`RELAY_QUOTA_DECAY_7D` accepts a
  descending schedule silently), `fe6a` (measure whether strict-priority dispatch is near-optimal
  under the two-resource quota trade), `df26` (`id:8df5` escalation trigger fired).
* **8 `docs/ledger-notes/*.md` committed** (`3a82 3eb0 625a 7295 7398 a25f cb1c fd49`), left
  untracked by a handed-back child. **Verified before committing: `id:64f9`'s title rewrite did
  NOT land.** All 8 ids are live in `TODO.md`, each line is still byte-identical to the note's
  preserved "Original title (verbatim)", and NOTHING in the tree points at the files -- no
  `-- detail:` pointer, no reference from any ledger or archive. Committed for recoverability,
  not because they are wired. Wiring the pointers and applying the rewrite remain `id:64f9`'s job.

## Needs the owner

1. **Make `relay-implementer` the default execute agent type, or decide explicitly not to.**
   This is yesterday's Needs-owner #1, unchanged, and today supplies the argument that matters:
   not a success count but a third silent non-adoption. Until it is a default it must be
   remembered per launch, and the record now shows it will not be.
2. **Push the 4 ratification-gated merges to GitHub**, then
   `ratify-queue.sh resolve <ckpt>` for each: `relay-ckpt-20260912-{2004,2038,2102,2151}`
   (`0fad/fac7/6294/6fda`, `6294`, `68c1`, `401c`). Private `origin` is current; the public
   remote is withheld BY DESIGN (`id:4d44`), not by accident. GitHub is 38 behind overall.
3. **`routed:5915`** is an open inbox dead-letter targeting this repo (fire the closing Fable
   pass per-decision rather than once at the end). Twin verified ABSENT via
   `token_marker_in_files`. It arrived after this run's 19:19 sweep, so the pool never saw it;
   `scan-routed.sh --apply` will file it.
4. **3 parked orphans and 15 retirable worktrees** from this run.
   `relay-reconcile.sh --all` lists them; the retirables are `--expect-merged` disposals.
5. Yesterday's items 2-5 are all still open and untouched today: `id:153f` scope needs a real
   count, `id:3dea`'s content-predicate half, `id:b545` fail-closed decision, and the 12
   unapproved `[MECHANICAL]` drafts.

## Method notes

* **A standing ruling in a handover is invisible to the next run unless something reads it.**
  The relay front door has a 4-step preflight and none of it consults the previous handover, so
  ruling #7 was never surfaced at launch. This is the `id:4d8e` shape one level up: the detection
  (a written ruling) exists and the resolution silently no-ops. Prose in a handover is not a
  mechanism.
* **Read the repo's own ledger before diagnosing a failure you recognise.** Five
  `Prompt is too long` deaths look exactly like `id:c3c1`, and I named that remedy before opening
  `id:3846` or `id:677b`, both of which say it is not sufficient and one of which says it is
  structurally the wrong lever. The ledger had the answer; recognition ran ahead of it.
* **Count a denominator from the structured source, never from a transcript grep.** The journal's
  `type:"failed"` records and the harness's own failure list agreed at 5. `id:3846`'s METHOD NOTE
  records a 21x overcount from grepping transcripts for the literal string, because mechanical
  hops QUOTE it in their status payloads.
* **`archive-done.sh` carved out the staged archive file** (`lane-vocab: skipping staged archive
  file (id:2065 carve-out)`) during the ledger commit. Expected, not an error.
* **A handover check is cheap and found four stale rows plus an unfiled 17-day-old item.** Three
  consecutive handovers carried the sentinel forward as "still unfiled"; noting a thing in a
  handover is not filing it.
* **Filing a finding is not exempt from the ledger's own ratchet.** Both items filed today went
  in at 1213 and 1337 chars against a 500 budget, and `todo-conformance.sh` caught them. The fix
  was NOT `ledger-shrink.py --apply`: it has no per-id filter and its dry run showed it would
  move **15 unrelated items**. Authoring `docs/ledger-notes/<id>.md` directly and keeping the
  head line short is the sanctioned route (`README.md` "Authored notes"), and it reaches the
  same end state without a 15-item sweep nobody asked for.
