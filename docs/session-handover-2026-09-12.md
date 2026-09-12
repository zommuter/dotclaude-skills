# Session handover -- 2026-09-12 (Opus 5, 1M context)

Successor to `docs/session-handover-2026-09-11.md` (318 lines, two stacked sections). That file
stays as the previous day's record. Its **AUTHORITATIVE CLOSE STATE table is now stale in every
row** -- see the comparison below rather than reading it as current.

Point-in-time snapshot. Durable detail lives in the ledger items and `docs/ledger-notes/<id>.md`
files cited here; read those, and do not trust this doc where it disagrees with them.

This session was a single `/relay --afk --exclude unidle` run, a handover check, and then four
owner decisions taken and executed at close.

> **READ THE `AT CLOSE` SECTION AT THE END OF THIS FILE FIRST.** The table immediately below was
> written BEFORE those decisions and several of its rows are superseded there (published to
> GitHub, ratification queue drained, inbox drained, sentinel reaped, 9 worktrees retired, suite
> 657). It is kept because the AT CLOSE section is a delta against it, not a replacement.

## State at close of the pool run (PRE-decision -- superseded below)

| | |
|---|---|
| `main` | clean, 0 unpushed to private origin |
| **Public GitHub** | **0 behind -- PUBLISHED at close on the owner's decision.** See the AT CLOSE section; the table row below describes the state BEFORE that decision |
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

---

# AT CLOSE -- four owner decisions taken and executed. THIS IS THE AUTHORITATIVE CLOSE STATE.

The "Needs the owner" list above was put to the owner as one batched question and answered.
Everything below supersedes the corresponding rows of the table at the top of this file.

## State at close

| | |
|---|---|
| `main` | `5ea7793c` (this file's own commit; the substantive close is `f7fa822c`), clean, 0 unpushed |
| **Public GitHub** | **0 behind -- PUBLISHED TWICE** (`e9b5d1e3..f7fa822c`, 41 commits + 4 checkpoint tags; then `..5ea7793c`, this file) |
| Suite | **657 passed, 0 failed, 0 errored, 1 expected-red** -- re-run after the change, not inherited |
| Ratification queue | **0 pending** (all 4 resolved, each verified against the remote by `ratify-queue.sh`) |
| Parked orphans | **3** -- unchanged; the gate REFUSED all three, see below |
| Retirable worktrees | 9 retired; **unidle's 4 deliberately left** |
| Shared inbox | **0 open** |
| Stale STOP sentinels | **0** |

## D1 -- `relay-implementer` is now the DEFAULT execute agent type (`id:5e5a`)

Owner chose "default it AND fix the class". Both halves landed.

The flip AMENDS the in-code "Do not flip the default" instruction, which is quoted verbatim
where it stood rather than deleted, because the warning it carries is still true: a custom
definition replaces the system prompt and a bad one degrades quality silently. What changed is
the other side of the trade.

**The defect the spec pins is not "the default is wrong".** It is that flipping a default
COLLAPSES TWO INPUTS THAT USED TO BE IDENTICAL. While OFF, `undefined` and `''` both meant "no
custom agent", so any falsiness test was right by accident; they now mean OPPOSITE things, and
`A.EXECUTE_AGENT_TYPE || DEFAULT` silently destroys the opt-out. That is assertion (B) of
`tests/test_relay_execute_agent_type_default_5e5a.sh`, and the negative case was verified BY HAND
to redden there and nowhere else.

**Two self-inflicted defects in that spec's own declarations, caught before shipping green** --
worth recording because both would have produced a vacuous test that looked fine:
1. The first `fails-against-mutation` used `|` as the `s|||` delimiter, which collides with the
   `||` being inserted. Perl aborted, the mutation never applied, and the spec "passed" against
   an unmutated file. An UNREACHED FIXTURE, not a passing negative control -- exactly the shape
   the memory rule about before/after harnesses warns of. Read the output, not the exit code.
2. The declared assertion named the RUNTIME value (`"relay-implementer"`), which appears nowhere
   in the source line (it reads `got \"$(get blank)\"`), and both `(B)` assertions shared
   identical text. `test_negative_case_runner_a73c.sh` caught this as a CONFIG ERROR. **Declare
   the static prefix of the assertion, never the interpolated output.**

**New exposure this creates, stated because it did not exist while the default was OFF:**
dispatch FAILS LOUD on a missing agent type, so a checkout that has not run `make install` now
hands back EVERY execute unit rather than only opt-in ones. `make install` does include
`install-agents`. **Never "fix" this with a silent fallback** -- that is the `id:4347` failure the
loud path exists to prevent.

`id:f043` is the class half: nothing in the relay front door reads the previous handover, so a
standing ruling is invisible at launch. WARN-only like `id:83c3`, never a gate (it would wedge
every `--afk` run), never a parser (it would rot and silently surface nothing, reintroducing the
bug one layer down).

## D2 -- PUBLISHED, on a controlled before/after audit

Owner chose "audit, then publish". The audit was a measurement, not a judgement, per the 09-11
method note: a detached worktree at `github/main`, `tools/privacy-audit.sh` run there, diffed
against the same report at HEAD.

**Both sides byte-identical: 309 occurrences across 222 file-hits, all 8 pattern indices
unchanged.** So 41 commits added ZERO new occurrences in ZERO new files. Published on that basis,
then all 4 ratification entries resolved -- `ratify-queue.sh resolve` verifies the remote with
`git ls-remote` itself and would have refused otherwise.

## D3 -- the orphans were NOT safe, and the gate is what established that

Owner chose "auto-integrate the safe ones". `auto-integrate-orphan.sh` ran on all three and
**refused all three**, each on the COMPLETE check: `id:b437`, `id:ccf7` and loderite's `id:6371`
all still have an OPEN checkbox on their orphan (PARTIAL). Main unchanged, all three still parked,
surfaced for a human `/relay reconcile`.

**This is the better outcome than the inspect-first alternative**, and worth noting as a method
point: the gate PROVED partiality mechanically, where a hand inspection would have produced a
judgement. The `id:677b` precedent (an `id:f272` residue commit holding 24 completed shrink pairs)
is exactly why they could not be discarded unexamined -- and equally why they could not be merged
unexamined. They are neither finished nor worthless.

## D4 -- housekeeping, with one deliberate deviation

Inbox dead-letter `routed:5915` filed as `id:0682` (twin-guard verified present, inbox now 0).
Stale sentinel reaped. **9 of the 15 worktrees retired, not 15**: two unidle entries vanished
between the listing and the retirement, which means a session is live in that repo. unidle was
excluded from this whole session by the owner, so its 4 remaining worktrees were left to it rather
than reaped under a live session.

## Found while checking `routed:5915`, and NOT acted on -- the owner's call

**`id:8df5` now has 11 open inbound items citing its pre-registered escalation trigger** -- from
project_manager (x3), escapement, leAIrn2learn, inflownistration, lean4btc, trustless-ai and
unidle (x2). The parent item's own head line still reads *"the pre-registered trigger has now
FIRED TWICE with nowhere to land"*.

That count is stale by a factor of five, **and the staleness IS the pathology the item names**:
evidence keeps arriving and accreting as separate inbox stubs instead of forcing the decision the
trigger was pre-registered to force. The memory note `fabled-escalation-trigger-fired-4` is behind
too (it says 5).

Two further wrinkles: `routed:1b5a` and `routed:5915` are BOTH from the same unidle session on the
same day, filed as two items covering the same firing, and they DISAGREE on magnitude -- 1b5a says
"5 forces-amendment findings", 5915 says "~12 amendments". At least one is wrong about one event.

`id:8df5` is `[HARD] [INTENSIVE]`, so the build-vs-defer call is the owner's and was left
untouched. The stale count is a plain factual error and could be corrected independently of that
decision; it was surfaced rather than edited.

## Method notes from this half

* **The zsh `path`-is-tied-to-`PATH` trap fired a THIRD consecutive session.** A loop variable
  named `path` destroyed `PATH` mid-sweep and every subsequent command failed `command not found`.
  It failed LOUDLY here and nothing was half-done, unlike the 09-11 instance which produced a
  confident wrong answer. Three sessions running is an argument for the lint that handover
  proposed -- prose in a method-notes section is not a mechanism, which is `id:f043` again.
* **`worktree-retire.sh` takes a repo PATH, not a repo NAME**, and the name form fails with
  "is not a git repository". Resolve via `lib-own-repos.sh`'s `own_repos` with `RELAY_TOML` and
  `SRC_DIR` exported -- WITHOUT those it returns zero repos and exit 0, which is the `id:0fa0`
  silent-empty trap in its own right.
* **`node --check` cannot parse `relay-loop.js`** -- a Workflow script legitimately uses top-level
  `return`, so the checker fails at line 5389 on the UNMODIFIED file too. Confirm against
  `git show HEAD:` before reading such a failure as your own; the real gate is
  `test_workflow_node_check_62c9.sh`.
* **Filing a finding is not exempt from the ledger's own ratchet.** Today's items went in at 1213
  and 1337 chars against a 500 budget. The fix was NOT `ledger-shrink.py --apply` -- it has no
  per-id filter and its dry run showed it would move 15 unrelated items. Author
  `docs/ledger-notes/<id>.md` directly and keep the head line short.

## Publishing this file required its OWN audit, and that generalises

The AT CLOSE section above was written after the publish, so publishing IT needed a second
before/after run. That result: **still 309 occurrences / 222 file-hits, all 8 indices identical**
to the pre-publish baseline. Published on that basis.

**The general point, which cost nothing here but will not always:** a handover documenting a
publish can never itself be covered by the audit that authorised that publish. Prose ADDS
occurrences even when it adds no secrets -- the 09-11 note records a publish that moved index
`#2` by +1 across +2 files purely because a ledger shrink relocated one occurrence and the
handover added another, every hit being inside the ordinary English word "Evidence". So the
sequence is: audit, publish, write the handover, **audit again**, publish the handover. Do not
assume the second run is a formality because the first was clean; run it.

There is a small terminal recursion here -- the sentence you are reading was not covered by the
audit that published it. It is bounded and harmless (a handover's final bookkeeping paragraph
introduces no new file and no new identity string), and the alternative is an infinite regress.
Noted rather than hidden, so a future reader does not "discover" it as a gap.

## What was NOT done, and is the next session's first question

* **`id:8df5`, eleven inbound firings against a head line saying "FIRED TWICE."** The owner's
  call, deliberately untouched. The stale COUNT is a plain factual error and can be corrected
  without pre-judging the build-vs-defer decision.
* **3 parked orphans**, all refused by the auto-integrate gate as PARTIAL. They need a human
  `/relay reconcile`, and `id:677b`'s precedent says do not discard them unexamined.
* **unidle's 4 retirable worktrees**, left to that repo's live session.
* **`id:cbee`** (the `id:c076` recurrence) and **`id:f518`** (the sentinel reaper) are filed and
  unworked. `id:f043` (surface standing rulings at launch) is filed and unworked, and is the one
  that would have prevented this session's founding mistake.
