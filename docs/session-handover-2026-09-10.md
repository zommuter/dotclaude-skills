# Session handover -- 2026-09-10 (Opus 5, 1M context)

> **The "State at close" table below is from the MORNING half and is STALE in several rows.**
> It is left verbatim as that half's record. The authoritative close state is the
> **AFTERNOON section at the end of this file** -- specifically: public GitHub is now **0 behind**
> (195 commits PUBLISHED on the owner's decision), the ratification queue is **drained for this
> repo** (19 resolved with remote verification), `id:0246` is **reverted and reopened**, and
> `id:aa0d` **landed**.

Point-in-time snapshot. Durable detail lives in the ledger items and `docs/ledger-notes/<id>.md`
files cited below -- read those; do not trust this doc where it disagrees with them.

## State at close

| | |
|---|---|
| `main` | see final commit; clean, 0 unpushed to `origin` (private `fievel:`) |
| Suite | **633 passed, 1 failed, 2 expected-red** -- the 1 failure IS `id:0246`'s headerless RED spec (intended; see below) |
| **Public GitHub** | **182 commits BEHIND, and NOT published this session** -- audit found 7 pattern hits, see "Needs the owner" |
| Parked orphans | 3, all deliberate (`b437` open + 2 zero-commit session logs) |
| Stranded branches | 0 -- the one stranded branch was retired force-free and is now a reachable parked ref |
| `1048` auto-integrate | trial AUTHORISED per-run; deliberately NOT enabled on the unattended pool (see below) |

## READ FIRST: one non-hermetic test had been eating live production state for a fortnight

`tests/test_prelude_mechanized_86a2.sh` executes `discover-prelude.sh`, whose step 6 is a
**CONSUMING** `inject.sh take`. It isolated `RELAY_TOML` and nothing else, so `$INJECT_BASE`
defaulted to the real `~/.config/relay` and **every `make test` run drained the live injection
queue**. It destroyed 19 real injected review units this morning (18 code.lawless OCR reviews plus
ai-codebench `0ce2`), and the `repos=2` fixture signature in `discover-prelude.log` goes back to at
least **2026-08-26** -- so it had been doing this on every suite run for over two weeks. It only
became visible because the queue was non-empty for the first time.

Fixed (`id:1975`): the test now isolates `INJECT_BASE`, `CLAIM_BASE`, `STOP_PATH`, the prelude log
and `INJECT_LOG`. Guarded by new `tests/test_inject_queue_test_hermeticity.sh`, which plants a
canary and asserts every prelude/inject-executing test leaves it untouched, with the candidate set
DERIVED from execution shape so a future test is covered automatically.

**Deliberately not a static lint**: 9 test files match that execution shape and only ONE leaked, so
a "must set INJECT_BASE" rule would be wrong 8 times in 9 and get muted.

**The diagnosis was initially wrong and the method is the lesson.** A peer session attributed it to
the discovery-producer daemon from heartbeat correlation alone. `grep -c inject
discover-repos-mechanical.sh` returns **0** -- it cannot take anything. What settled it was
`repos=2` in the prelude log at the same second as the take: a real pool reports `repos=60`.

## What landed

* **`id:1975`** -- the leak above, plus its guard.
* **`id:1d83`** -- the cross-repo inbox twin check now spans `TODO.archive.md` and
  `ROADMAP.archive.md`. `archive-done.sh` sweeps an undated same-session close, which carried a
  `routed:` breadcrumb out of the live ledger and made `inbox-done` refuse on work that had
  demonstrably landed. Both call sites widened together with identical file sets.
* **`id:aedf`** -- executor contract **v19**, new rule 5d: a DENIED destructive op is a HANDBACK,
  not a puzzle. Transcribes the owner's 2026-08-26 ruling, which lived only in `~/.claude/CLAUDE.md`
  and a memory file -- neither loaded by an executor child.
* **`id:a192`** -- the `expires-on:` edge plus `relay/scripts/expires-on-scan.sh`. A clause declares
  its own expiry and is reported once that item closes. Report-only.
* **`id:ed35`** -- `auto-integrate-orphan.sh` binds an orphan by BRANCH NAME, not commit prose.
* **`id:4e84`** -- the chain-end re-ask now reaches `hard` and `handoff` (was `review`-only), with
  `--exclude` naming this round's actual dispatches. Four review defects fixed on top, including a
  live apex-gate bypass.
* **`id:0246`** -- implemented, reviewed, and **REVERTED**. Still OPEN. See below.
* Promoted by hand: `id:32c3` and `id:4e84`.

## OWNER RULINGS recorded this session -- six, all in the ledgers

1. `id:32c3` mark-reading contradiction: **NEITHER mode reads the `●◐○` marks.** `id:93d6`'s
   constraint on (b) stands; the `inflownistration/CLAUDE.md` (c) amendment's contradicting
   parenthetical is SUPERSEDED and struck through in place there.
2. `id:5a5a`: **make the skip LOUD** -- keep inbox deletion ATTENDED, do NOT wire `--apply` into
   the pool.
3. The inflownistration **carve STAYS PARKED**.
4. An **instance row is APPROVED** and now written (`inflownistration/docs/instances.md`), graded
   `T ● M ● C ○ H ● S ● G ◐ R ○`.
5. `id:4e84`: the **apex-gate restoration STANDS** -- a chain-end `hard` obeys `enforceApexGate`.
6. `id:0246`: **REFUSE on a multi-marker line is WANTED**, accepted with its cost -- both live
   inbox items cannot drain until their literal HTML-comment citations are de-literalised by hand.

Also ruled: widening the chain-end re-ask is an **implementation of A1**, not an amendment (so the
budget/round-robin and starvation-counter options stay closed), and the **apex cost is accepted**.

## Needs the owner

1. ~~**PUBLISH DECISION, not taken.**~~ **RESOLVED later the same day -- 195 commits PUBLISHED on
   the owner's decision after the 8 indices were classified; see the AFTERNOON section. The text
   below is the morning state, kept because its AUDIT METHOD is the reusable part.**
   182 commits behind public GitHub. The tree-scoped audit
   (`tools/privacy-audit.sh`, exit **1** = findings) found **8 pattern indices with hits**: `#2`
   (76 occurrences / 41 files), `#7` (2/1), `#8` (2/2), `#9` (2/2), `#12` (155/149), `#13` (1/1),
   `#16` (3/1), `#21` (66/23).
   *(I first reported 7 of these, having read the output file WHILE IT WAS STILL BEING WRITTEN --
   `#21` was missing. Same error class as the rest of the day, on my own measurement. The audit's
   real exit status also had to be recovered from the background wrapper's output, because the
   "exit code 0" the harness reported was the wrapper shell's, not the audit's.)*
   **I did NOT publish**, deliberately: `#2` is the documented 3-character UNANCHORED pattern whose
   substring noise camouflaged a genuine hit on 2026-08-22, and adjudicating 7 classes unattended
   against that history is not a call to self-authorize. Resolve indices with
   `tail ~/.claude/logs/privacy-audit.log` or `--show-patterns` -- **terminal only, never into a
   tracked file** (the gate's own output spells the private pattern). Prior audits found only the
   intentional-provenance class (session UUIDs, trailer addresses), which are NOT leaks.
2. **De-literalise the two live inbox lines** so they can drain (owner ruling 6). Note there is **no
   tooling path**: `append.sh` has no edit verb and `md-merge` anchors on `id:` while the inbox uses
   `routed:`. Worth an item if it annoys twice.
3. **`id:fcde`** -- `/relay --once` and `--after N` gain NOTHING from `id:4e84` (the wave budget is
   snapshotted before the wave, so every chain-pushed follow-on is refused). Recommendation: leave
   it; the bound is the point of the flag.
4. **`id:206e`** (archiver-side invariant, recommendation DEFER) and **`id:d9ff`** (the
   backtick-quoted marker hole, 2 -> 15 false accepts after `1d83`) are filed and unscheduled.

## The error class that dominated the day, and it has a mechanism item now

**Reasoning from a source that does not record the thing being asked about, and reading its silence
as an answer.** Filed as `id:3f59` ([INPUT - meeting]) because the prose layer is saturated --
`docs/ledger-notes/3846.md` already carried it as a standing warning, written by the author who then
walked into it.

Instances today, mine unless noted: the daemon misattribution (peer's, corrected); reading an exit
status through a pipe **twice**, once while investigating the first instance; claiming `ed35`'s
GATE 1 passes after testing one of its two clauses; asserting `relay-loop.js:2048` blanked
`intensive` when `:2044` does it on a different path, correctly -- my brief's literal wording would
have re-introduced `id:2799`, and the spec author refused to implement it; and my "fix" to a
misleading log line reproducing the same sin on the one input I had not enumerated (`quotaStopped`).

## In flight / next

* **`id:0246` is the biggest single thing waiting, and it is REVERTED, not pending.** The
  implementation landed as `6d5befed`, the adversarial review found **9 defects (2 HIGH) on a
  DESTRUCTIVE write path**, and I reverted it (`eb2587fd`) without pushing. Full prescription:
  **`docs/ledger-notes/0246-review.md`**.
  - The extractor and the spec are SOUND -- 19 constructed false-resolution attacks all correctly
    handled, all three sites genuinely adopting, both live items refusing as ruled, nothing in the
    spec surviving a revert. **Do not redo that work.**
  - Reverted rather than fixed because you were away, `meeting/append.sh` is symlink-LIVE for every
    session, and D2/D5/D7 are live behaviour changes. Fixing six defects on a destructive path
    unattended risks a seventh.
  - Worst two: **D1**, `mktemp` + `mv` replaces a SYMLINKED inbox with a regular file and never
    drains the real store, exit 0 -- a class this same file already fixed for `personas.md`
    (`id:00b1`/`id:96da`); and **D2**, the add path exits 1 AFTER durably appending, so a naive retry
    DOUBLE-FILES. Measured good news: the live inbox is a regular file, so D1 was latent.
  - **D5 and D6 need YOUR ruling** -- is an indented inbox line legal, and does your multi-marker
    refusal extend to a line that merely CITES the token (it currently blocks a conforming sibling
    permanently, with a misattributing message)? Both are regressions against the parent, both
    safe-direction.
  - A **FOURTH live opinion** about inbox line shape surfaced: `todo-conformance.sh --inbox` calls the
    `id:798d` legal shape `shape-prose` non-conforming, so one `--apply` run printed the same line as
    both non-conforming and `RESOLVED`. Needs its own id.
  - Follow-up NOT built: the broad un-swallowing of `2>/dev/null || true` across `scan-routed.sh`,
    which also eats `inbox-done`'s legitimate exit-3 twin refusal.
* `id:45c8` -- two non-reproducing suite failures today, both with an agent writing the same
  checkout. Filed as a LOGGER (fingerprint the tree at start/end of a run), explicitly NOT a guard,
  NOT a retry.
* `id:6fda` -- owner-requested skill: turn open ledger decisions into brief + recommendation + one
  batched `AskUserQuestion`.
* `id:5a5a`/`id:0246`/`id:d9ff` are the inbox cluster; `id:0246` is the one that misreads live data.

## Method notes

* **`node --check` CANNOT parse `relay-loop.js`** (top-level `return`). Use `workflow_node_check`
  from `tests/lib-workflow-check.sh` plus the `id:aec5` all-builders harness.
* **Installed relay scripts are per-file SYMLINKS** into this repo, so an edit is live in any
  running pool the instant it is saved. The `id:4e84` apex-gate bypass was live from the moment it
  was pushed.
* **A declared `fails-against-mutation:` must be ONE complete command on ONE line** -- a heredoc
  split across comment lines contributes only its first line (`id:b890`), and a `sed` address can
  silently match nothing (the `4e84` declaration was a proven no-op until re-anchored).
* **`| head` under `set -euo pipefail` is BLOCKED** by `tests/test_pipefail_sigpipe_lint.sh`
  (`id:81d5`). It caught three of my own edits today. Use `head -1 < <(...)` or drop the pipe.
* **The `id:aa93` dirty-guard refuses a push while another session's work is uncommitted** -- that
  is correct; use a plain fast-forward `git push`, never commit their files.

---

# AFTERNOON -- same session, continued. THIS IS THE AUTHORITATIVE CLOSE STATE.

## State at close

| | |
|---|---|
| `main` | see final commit; clean |
| **Public GitHub** | **0 behind -- 195 commits PUBLISHED 2026-09-10 on the owner's decision** |
| Ratification queue | **drained for this repo** (19 resolved, each verified via `git ls-remote`, 0 refused). 2 `toesnail` entries remain, not ours. |
| Suite | 635 passed, 1 failed, 1 expected-red -- the 1 failure IS `id:0246`'s headerless RED spec (reopened item) |
| Parked orphans | 4, all deliberate |
| Shared inbox | 3 open, NONE targeted here (cartulary `3e13`, meeting-rpg `cef7`, leAIrn2learn `784a`) |

## The publish decision, and how it was actually resolved

The audit exited **1** with **8** pattern indices. Rather than treat that as a blocker, each index
was resolved to a CLASS (never to pattern text -- the gate's own output spells the private pattern,
so it must never reach a tracked file):

* `#12` (155 hits / 149 files) -- **139 are session-id provenance**, the owner's explicitly ratified
  not-a-leak class.
* `#21` (66 / 23) -- **65 are absolute `/home/<user>/...` paths.** The only substantive class.
* `#2` (76 / 41) -- 71 prose: this is the documented 3-character UNANCHORED pattern whose substring
  noise once camouflaged a genuine hit.
* `#16` (3 / 1) -- 2 commit-trailer provenance, all inside the doc that EXPLAINS the intentional
  trailer. `#7`/`#8`/`#9`/`#13` -- 1-2 hits each, trivial.

**The decisive measurement: of the 23 files carrying the home-path class, 22 are ALREADY on
`github/main` with the same content.** So publishing propagated an existing exposure rather than
creating one. That is what turned a blocker into a decision. The owner published.

If you want to REDUCE that class, it is a separate cleanup item and the time to do it is before a
push, not after.

## What landed in the afternoon

* **`id:aa0d`** -- a `gated-on:XXXX=<condition>` edge parsed to EMPTY, so the gate was invisible and
  the item dispatched as UNGATED. Fixed, and **verified end-to-end against the original incident**
  rather than its own fixtures: `resolve-gates.sh ~/src/leAIrn2learn` now emits
  `89ef 1 unparseable:0d8e=pass` with 10 loud refusals, and `classify-repo.sh` returns
  `actionable_routine_ids: []`, verdict `human`. The over-dispatch cannot recur.
* **Salvage of the pool's stranded review branch** -- 4 ledger notes recovered, `id:4e84` and
  `id:ed35` ticked with their tests re-run on `main` as evidence. `id:aa5e` deliberately NOT ticked:
  `main` had already closed and archived it, and the branch's hunk would have re-added a duplicate.
* **4 inbox dead-letters routed** -- `id:ac90`, `id:8cc6`, `id:3dea`, plus `routed:4887` FOLDED into
  the existing `id:3770` rather than opened as a second item for one defect.
* **3 defects filed from the first pool run** -- `id:aa0d`, `id:0923` (both ledger ratchets INERT for
  every consumer of the INSTALLED path), `id:36bc` (relay-doctor substring-matching `[MECHANICAL]`).

## OWNER RULINGS -- ten this session, all in the ledgers

The morning six, plus: **`id:0246` D5** refuse an indented inbox line LOUDLY (the defect was the
silent exit-0 no-op, not the strictness); **`id:0923`** regenerate each repo's baseline, then arm;
**publish** after classification; and **D6 DISSOLVED rather than answered** -- the owner asked
"should decoy lines exist at all?", and the answer is no. Nothing currently prevents a multi-marker
inbox line (`todo-conformance --inbox` has no such check), the inbox rule already says ONE line, and
`id:6059`'s ambiguity is MANUFACTURED by spelling a citation in the owning comment form. So: reject
a multi-marker inbox line at WRITE time, lint the existing ones, keep the resolver refusal as a
backstop. Consequence: both live inbox lines need de-literalising before they can drain, and
`routed:3e13` -- which is literally an item about quoted markers being misread -- gets to fix itself.

## THE CORRECTION THAT MATTERS MOST: I verified a null result as a success

`id:3dea` (inbound `routed:82ec`, verified before ingesting). A `[MECHANICAL]` recipe's
`acceptance_artifact` is checked for EXISTENCE only. All three of `id:0ce2`'s `verdicts.json` carry
`"verdict": null` -- well-formed JSON, 7 keys, correct schema, **no judgment in any of them**.

Last night I recorded that run as *"SUCCEEDED -- 3 verdicts.json verified"* and described parsing one
to confirm a real judgment record, listing `verdict` among the fields present. **I checked that the
field EXISTED and never looked at its VALUE**, then committed that into a handover as evidence. The
fleet's own diagnostic is *"if this were broken, would this check look different?"* -- mine would not
have. The note names me, because the daemon-side gap and mine are the same shape one layer apart:
fixing only the daemon leaves the reviewer free to repeat it.

## The day's dominant failure mode, and the argument it settles

**A check whose output does not depend on the thing it reports.** Three instances today: the two
ledger ratchets silently INERT (`id:0923`), `transcript-shape-preflight` case (C) reporting SKIPPED
while exiting 0 (`id:5f6a`), and the acceptance-artifact existence check (`id:3dea`). Plus my own:
an exit status read through a pipe twice, one of two gate clauses tested and generalised, an audit
file read while it was still being written, and a harness exit code that belonged to the wrapper
shell.

`id:3f59` asks for a MECHANISM rather than more prose. The strongest evidence for it is that the
prose rule was in front of me and I wrote the claim anyway.

**And the two highest-value findings of the day both came from something REFUSING, not from
analysis:** a review agent that would not ship (the apex-gate bypass my own commit opened), and an
executor child that would not work an item it judged gated (`id:aa0d`). Worth weighting when
deciding how much adversarial review to keep buying.

## FINAL: the `EXECUTE_AGENT_TYPE` experiment (`id:3846`) -- PROMISING, and INCONCLUSIVE

Run `relay-20260910-143324-11403`, launched with `EXECUTE_AGENT_TYPE=relay-implementer` and
`--exclude dotclaude-skills` (so it could not collide with the salvage running in this checkout).
Ended `stopReason: "user-stop"` -- the targeted sentinel was consumed at 15:29 and logged with
`scope=targeted` plus the run id, so the graceful stop path worked end to end.

| | previous run (no agent type) | this run (`relay-implementer`) |
|---|---|---|
| agents | 396 | 94 |
| **agent errors** | **6** (3 of them `Prompt is too long`) | **0** |
| execute dispatches | ~6 | 3 (2 completed, 1 gate-handback) |
| rounds | 8+ | 2 (stopped early, by request) |

**The one genuinely paired observation:** `trustless-ai`'s execute child DIED on
`Prompt is too long` in the previous run and COMPLETED substantively here (`id:eb00`, checkpoint
`relay-ckpt-20260910-1445`). Same repo, same lane, across the flag change. That is the most
suggestive evidence available and it is n=1.

**Verdict: do NOT promote the flag on this.** Three execute dispatches cannot distinguish a real
fix from chance -- this repo's own pilot-sample rule says n=10 cannot separate rates within ~10pp,
and 0/3 is consistent with both outcomes. Recording it as promising-and-unproven is the same
discipline `id:0b6c` demands of the `1048` trial: **zero events is inconclusive, not a pass.** What
it needs is a full unbounded run with the flag on and no early stop, then the same table.

## The other findings from that run

* **`leAIrn2learn` `id:89ef` was dispatched and handed back AGAIN** -- and this is the OLD defect
  recurring, not the fix failing. The pool launched at 14:35, before `id:aa0d` was committed
  (`d4f16c18`), so its round-1 discovery classified with the unfixed parser. Measured directly after
  the fix: `classify-repo.sh --repo leAIrn2learn` now returns `actionable_routine_ids: []`, verdict
  `human`, so it cannot recur. The child refused correctly both times.
* **`code.lawless` landed-but-unfinished AGAIN** (`relay-ckpt-20260910-1528`, merged + tagged +
  pushed, `worktree-retire` deferred because the worktree holds modified/untracked files). That is
  now the third time today on that repo specifically, and it is an ANNEX repo -- the
  `id:5239`/`id:3016` family, where annex pointer/availability noise reads as uncommitted work.
  **Do NOT re-dispatch or re-merge**: a retry takes the zero-commit path and mints a second
  checkpoint tag. Needs a supervised reconcile in that repo.
* **3 repos queued as `mechanical` and pool-inert by design** -- `trAIdBTC`, `llm-from-scratch`,
  `isochrone`. They are waiting on the host daemon, not on the pool. Nothing is stuck.

## Sentinel litter, worth one line

A targeted STOP sentinel is only consumed if the pool reaches a dispatch decision. A run that ends
any other way leaves its file behind and nothing reaps them -- `~/.config/relay/STOP.relay-20260826-162405-7522`
has sat there since 26 Aug. Harmless (keyed to a run id, so it cannot false-stop another pool; that
scoping is exactly what `id:cd94` bought) but it accumulates. Unfiled.

---

# EVENING -- same day, a `/relay human --all` sweep. THIS IS NOW THE AUTHORITATIVE CLOSE STATE.

## State at close

| | |
|---|---|
| `main` | `102a499d` at the time of writing, plus whatever the in-flight agent below adds. Clean except a peer's `meeting/personas.md`. |
| Suite | **637 passed, 0 failed, 0 errored, 1 expected-red** -- `id:0246` re-landed, so the repo is no longer red at HEAD |
| REVIEW_ME here | **90 -> 84 open** |
| Parked orphans | **1** (was 6): only `...-execute-b437-0` survives |
| Shared inbox | 4 open, none targeted here |
| Ratification queue | 0 pending, verified with `ratify-queue.sh list` |

## READ FIRST: `md-merge.py` cannot tick most REVIEW_ME boxes, and that is why tier-(a) looks empty

`/relay human` section 3(a) mandates an apply step its own tooling cannot perform. `md-merge.py`
addresses a line only by an anchored `<!-- id:XXXX -->` marker or a `## ` heading; most repos' boxes
carry neither on the checkbox line. **Six independent agents hit this and all six refused to reach
for Edit**, which bypasses the flock exactly as `sed -i` does. So *zero applied auto-answers across
nine repos was the correct behaviour, not a shortfall* -- and a prior run DID tick boxes
(`ai-codebench@20e4e90`), which means it used a flock-bypassing path.

Filed as `id:7c75`, with the measurement across 26 repos on the item. **There are TWO viable
anchors, not one** -- the part worth carrying forward: wisenheimer has zero id markers but exactly
one `## ` heading per box, which gives `update-sections` a working handle with no marker at all. The
hard case is one coarse heading over many boxes (csgebra's `## Open` over 7, jobAI's 3 over 9). The
dotclaude-skills agent proved the section door at scale: a composer that extracts a section verbatim,
flips exactly one checkbox, and hands the payload to md-merge under flock, dry-run diffed first.

## What landed

* **`id:0246` re-landed green** (`69587e46`) with all 9 review defects fixed -- D1 now follows the
  `personas.md` realpath pattern, D2 rejects at WRITE time so a retry cannot double-file. Suite
  637/0. The red-suite box closed itself.
* **5 of 6 parked orphans disposed.** trustless-ai integrated (`relay-ckpt-20260910-1559`, a 100-line
  results expansion recovered); the dotclaude-skills review orphan cherry-picked for its 4 unsalvaged
  REVIEW_ME boxes then discarded; 2 zero-commit session logs discarded; **5 ledger-shrink pairs
  completed** off b437 (`8d42e18d`).
* **Fleet defects filed:** `id:b9f3`, `id:7c75`, `id:c293`, `id:302f`, plus `id:a715` from a peer.
* **`hard-lanes.md` corrected** (`b0724d28`) -- see the consumer-divergence section below.
* **loderite marker repair** (`6f4d1573`, `f9391bb8`, `e34b9221`) -- see the correction below.
* Ticks applied elsewhere: ai-codebench `id:515b` (`597d4e5`), leancow (`294bff3`), lean4btc
  (`d6377a3`), trustless-ai (`26cd318`), mri (`4671697`).

## The three late owner rulings -- ALL LANDED (this section was written while they were in flight)

1. **Ratchet baselines: ORPHAN ROWS ONLY** (`48e51a83`). Exactly 5 rows dropped, each forgiving a
   line no longer in its ledger; all three ids verified to appear only as prose citations, never as
   an owning item. No row regenerated, none added. `make baseline-staleness` before/after: TODO
   `8 of 283 ... 2 orphaned` -> `8 of 281 ... 0 orphaned`; ROADMAP `3 orphaned` -> current. **The 8
   stale rows are untouched by design** -- the rejected remedy would have MINTED 13 new
   grandfathering rows, forgiving ~15,700 chars to reclaim ~371. Tighten-only regen filed as
   `id:7e3b` (row-scoped, LOWERS a floor when the line shrank, REFUSES loudly to raise or mint).
2. **`verify-negatives --changed <base>` folded into integrate** (`bf49929e`, `id:abcc`), as
   `integrate.sh` **step 3d**, PRE-LAND with the other pre-mutation gates. The base is `iso_base`
   (the canonical checkout's HEAD, id:8739), deliberately NOT `origin/main`, which id:4d44 freezes
   and which would widen the diff to the whole unratified backlog. Non-zero is
   `HANDBACK[verify-negatives]`, `handbackCode=38`. No `2>/dev/null`, no `|| true`.
3. **`id:c076`: permitted-id set threaded into dispatch** (`af47190d`). `permittedIdsFor(unit)` =
   classifier's `actionable_routine_ids` minus the b09e/a360 orphan+stranded subtraction, with an
   injected `--item` unioned in first. The prompt now carries a CLOSED PERMITTED SET declaring
   unlisted ids out of scope. **Empty set FAILS CLOSED**: `EXECUTE_NO_PERMITTED_SET` authorises no
   work and instructs an immediate handback -- the unit still dispatches, so a wiring fault surfaces
   with repo and run attached instead of a repo silently vanishing from the round.

Suite after all three: **639 passed, 0 failed, 0 errored, 1 expected-red**.

**Two things the applying agent flagged that are worth more than mechanics:**

* It changed two existing tests and **declared both narrowings in-file rather than quietly weakening
  them**. For `test_executor_sizeout_signal.sh` it dropped the loosest `hand ?back` disjunct and then
  confirmed the assertion still discriminates by deleting `+ EXECUTE_SIZEOUT` and watching the case
  go red. That check is the difference between a narrowing and a vacuous test.
* It reported that `test_dispatch_names_item_b09e.sh` was granted `EXPECTED-RED` although `id:b09e`
  is `[x]` in `ROADMAP.archive.md`, concluding that an archived-closed item's spec is forgiven
  forever. **CHECKED, and the defect does not exist as described.** `item_open()`
  (`tests/run-tests.sh:97-106`) greps ONLY the live `ROADMAP.md` for an unticked line and returns 1
  when the token is absent; `:265` grants expected-red only when `item_open` returns 0. Measured:
  `grep 'id:b09e -->' ROADMAP.md` is empty, the archive carries it, so that file takes the `else`
  branch and **FAILS LOUDLY**. The blindness runs in the SAFE direction -- an archived token cannot
  buy expected-red. Nothing filed. Recorded because the claim was nearly transcribed into this
  handover as fact: a delegated agent's incidental observation is a claim to verify, not a finding
  to bank, and this one was one command away from being disproved.

## Needs the owner

1. **`code.lawless` (29 boxes) is the only untriaged queue**, parked deliberately for a supervised
   annex pass. It has landed-but-unfinished three times; a retry mints a second checkpoint tag.
2. **loderite's nested worktree** (`~/src/loderite/github`) makes its counts unreliable, and 10
   `PARKED-POOL-LANE` errors sit there -- an executable lane under a parked heading, the `id:d35a`
   invisibility shape.
3. **cartulary's committed `uv.lock` is stale**, so ANY `uv run` there dirties the tree and the
   `id:aa93` dirty-guard will defer that repo in every pool round until it is refreshed deliberately.
4. **jobAI is one sitting**: `uv sync; uv run jobai scan --since 2026-04-21` starting with `id:b455`,
   which produces the data the other seven boxes are judged against. `id:5d2e` needs a separate
   sitting because a FRESH Claude session is the point.
5. **inflownistration** is the most consequential blocked queue in the fleet: a 3-step ratification
   chain gating `id:466d` then `id:431c`, with every box saying in its own text that nothing is
   model-answerable.

## THE CORRECTION THAT MATTERS MOST: I put a false premise in front of the owner

I asked him to rule on repairing a shrink that had "ticked an item you explicitly rejected"
(`id:718c`). The repair agent verified before editing and found the pre-shrink line carried a LATER
clause the triage report had not quoted: `@owner-accepted:2026-09-04 -- owner looked on-device
(dev-menu checks 1 and 3) and accepted`, where check 3 is precisely the short-coordinate badge
overprint the 2026-09-02 look rejected. `git show` across six revisions places the `- [x]` at
`bfe95a5e`, the commit that recorded the acceptance, not at the shrink. **Only the two UNDATED
copies were residue; the agent refused to reopen the item and was right.**

The chain is the lesson: a triage agent quoted a real negation, I compressed it into a question, and
the owner ruled on my compression. What caught it was the applying agent re-verifying a premise it
had been handed as settled. Same shape as the `id:3f59` class -- reasoning from a source that does
not record the thing being asked about -- one layer further out, since here the source DID record it
and the summary dropped it.

Two smaller ones, same day: my b437 option said "3 missing notes" when it was FIVE paired edits, and
landing notes without their line replacements would have duplicated prose with nothing pointing at
it (caught by inspecting pairing, reverted, re-done with verification). And the loderite agent's
first repair text spelled `@owner-accepted` literally, putting the guard's grep string back onto two
OPEN lines -- the same lifted-out-of-a-negation shape, self-inflicted, caught in a third commit.

## The consumer divergence worth knowing before touching lanes

`hard-lanes.md` taught BOTH answers for a bare `[HARD]`. Its rename table and 2026-09-09 banner make
it the canonical capability-keyed POOL lane; its "Canonical marker set" block still called it
untagged/LOUD-reject. So `gather-human-backlog.sh:74,:492` buckets it `hard_pool` while
`project_manager/scan.py:299,:333` buckets it `untagged`, and a NEW project_manager guard test now
FREEZES the scan.py reading -- `id:b466`'s sync contract is broken today. **The doc is fixed
(`b0724d28`); neither consumer is changed**, deliberately, because aligning them is a dispatch
change in two repos. That is `id:c293`.

## Verified defects other repos should know about

* **`lib-private-remote.sh` returns NOT-PRIVATE when SOURCED from zsh** and not-private means
  publish. `mapfile` is a bash builtin; `zsh -c 'source ...; is_private_remote_url fievel:src/x.git'`
  exits 1 where bash exits 0. Verified directly. A triage agent hit it live and nearly classified
  `fievel` as public. `id:b9f3`. **Until it is fixed, run that predicate under `bash`.**
* **Two `gated-on:` markers on one line concatenate into an unparseable payload**, so neither gate
  can ever resolve or expire. Fails SAFE since `id:aa0d` (both read as gated) but the item is then
  permanently blocked. Four repos: lean4btc `191a`/`abc7`, linguistic-universals `cc76`, loderite
  `27f7`. `abc7` is inside lean4btc's live pinned-statement cluster, so it blocks real work.
  `id:302f`.
* **`ROADMAP_PARKED_HEADING_WORDS` excludes the hyphen** (`lib-roadmap-sections.sh:85`), so
  `### Meeting-gated backlog` is NOT recognised as a parked heading and rule 3(g) never runs there.
  Tracked as `id:6446`. This inverted a linguistic-universals box's whole question.
* **ai-codebench's Peer-Review Matrix had never rendered, in any judge run**, because `judge.py:442`
  spells `prompt_label.replace("/", "/")` (a no-op) producing a five-segment path while both readers
  glob four. Owner ruled `1899`/`7772` stay closed; `id:027e` is the fix.

## Screen captures in the repo root, and the deny rule

Six untracked files named `argparse`, `fcntl`, `json`, `re`, `subprocess`, `sys`, 11.8 MB each,
71 MB total, were ImageMagick `import(1)` SCREEN CAPTURES of the desktop -- something ran a Python
import line in a shell and `import` is ImageMagick's screenshot tool. Untracked AND not gitignored,
in a repo with a public remote. Deleted on the owner's instruction, and `import` / `magick import` /
`xwd` are now in `~/.claude/settings.json` `permissions.deny`.

## Method notes

* **In zsh, the variable `path` is TIED to `PATH`.** A `while read -r name path` loop destroyed the
  environment mid-sweep (`env: 'bash': No such file or directory` for every subsequent repo). Name
  the loop variable anything else.
* **`git checkout -- <dir>` is refused by the destructive-git guard** even to undo your own staged
  adds. Scope the revert to enumerated paths; the guard allows that.
* **`git-lock-push.sh` can print "Everything up-to-date" for a commit that DID land.** Verify with
  `git ls-remote`, never the exit code or the message (`id:f5d9`/`dc4f`).
* **A relay-toml parser must expect QUOTED section names** -- `[repos."code.lawless"]`. A regex
  capturing `[^\]]+` yields `"code.lawless"` with quotes and silently drops every dotted repo.
* **The `--all` gather counts INDENTED sub-boxes** while `grep -c '^- \[ \]'` does not. loderite's
  55-vs-49 gap was that, not its nested worktree. Cross-check with `grep -cE '^\s*- \[ \]'` before
  blaming a second tree.

# NIGHT -- same day, a `/relay --afk --quota-7d 60` pool plus a cross-session annex investigation. THIS IS NOW THE AUTHORITATIVE CLOSE STATE.

## State at close

| | |
|---|---|
| `main` | `e3e65bad`, clean except a peer's `meeting/personas.md` (predates this session, attributed to `project_manager/quovadis-522a-scoping`; its owning session should commit it) |
| Suite | see the Suite row addendum at the end of this section -- run at close, ledger/docs-only changes |
| REVIEW_ME here | **84 open**, unchanged (this session opened none) |
| Parked orphans | **2** (was 1): the surviving `...-execute-b437-0` plus a NEW `code.lawless/...-114832-18641-execute-repo-1` |
| Retirable residue | **8 worktrees, 762 MB, ALL code.lawless** -- see the section below, this is the headline |
| Shared inbox | **7 open** (was 4), **4 now targeted here**; 1 twinned-resolvable (`routed:b015`) |
| Ratification queue | 0 pending, verified with `ratify-queue.sh list` |
| Relay run | `relay-20260910-173729-12338`: 2 rounds, 2 integrated+pushed, 1 handback, `stopReason: blocked-pending-human` |

## READ FIRST: 762 MB of leaked worktrees, and the fix is ONE missing predicate

`worktree-retire.sh:190` gates removal on `git status --porcelain` with **no `git diff`
cross-check**. That is the EXACT predicate `id:3016` fixed in `verify-isolation.sh:190` on
2026-09-09 -- same line number, same shape -- and it was never applied to the retire side. So
`id:3016` fixed the false-handback half and left the false-refuse-to-reap half live.

On an annex repo the pointer noise reads as dirt and retire refuses forever. Measured across all
8 residual worktrees, every one IDENTICAL: `porcelain=93`, `untracked=0`, `git diff --stat`
**empty**, `rev-list --count main..HEAD` **0**. Nothing to lose in any of them.

**`relay-reconcile.sh --all` independently agrees** -- it classifies all 8 as `RETIRABLE RESIDUE
(merged or unregistered -- no unmerged work, id:ba95)`, "8 retirable item(s) -- no work at risk".
And then it hands you `worktree-retire.sh --expect-merged` as the disposition, which is precisely
the command the log shows refusing them. **The reconcile tool correctly identifies safe residue
and recommends the one command that cannot dispose of it.** That closes the loop on why this
accumulated silently all day rather than being cleared by the normal path.

Filed on `id:2b7a`, which was already the open reproduction item. Root cause, scope, and the
corrected count are all on the item. **I reaped none of the 8** -- supervised-reconcile is the
owner's call.

## The defer count: 30, not 92, and the method is the lesson

`relay-worktree-retire.log` has **225 `DEFER` lines today, of which 195 name `/tmp/tmp.*`
HARNESS FIXTURES**. Only **30 are real**: `114832-18641` x24, `143324-11403` x3,
`074741-25003` x2, `173729-12338` x1.

**24 of 30 in a single run is the substantive finding, ahead of the raw count**: the refusal
repeats PER ROUND, not once per worktree. The disk figure is residue; the repeat rate is the
behaviour.

I first stated **92**, a peer countered **90**, and both were wrong. Two compounding errors in
mine: `grep -oE 'relay-[0-9]{8}-[0-9]{6}-[0-9]+'` emits EVERY occurrence on a line and these
lines name the run token twice (in `wt=` and again in the inspect hint), so a per-line count
became per-occurrence; and the filter `defer|unremovable|fail|refus` is broader than `DEFER` and
swept in fixtures. I produced THREE different wrong numbers -- the third from a greedy `sed`
that silently took the LAST token -- before classifying lines by kind and getting a defensible
one. **Durable rule, now on the item: filter on `\.cache/relay/worktrees` and extract at most
ONE run token per line.** A raw `grep -c DEFER` over-reports by ~7.5x today.

## THE CORRECTION THAT MATTERS MOST: I refuted a report correctly and then built on its false premise anyway

A peer routed `routed:a5fc` claiming annex `.git`-symlink worktrees are unreapable and that
`id:de4a` never fired. I verified before filing and **refuted three of its claims**:

1. **Mechanism**: not `git annex init`. `id:de4a`'s own closure record proves the symlink appears
   at `git worktree add`, before any annex command -- it is `filter.annex.process`, and the
   post-checkout-hook hypothesis was tested and DISPROVED.
2. **Correlation**: dead. 8 of 9 worktrees carried an `annex` gitdir entry and exactly ONE was
   symlinked; 7 annex worktrees in the SAME repo had normal `gitdir:` files. An annex-keyed
   detector would fire on 8 of 9, seven wrongly. Shape (`-L`) is the right predicate, which is
   what de4a already uses.
3. **"Silent"**: half wrong in the half that mattered. `id:a290`'s `report_retire_failure` DOES
   log it; withholding it from `RELAY_STATUS.md` is DELIBERATE
   (`reconcile-repo.sh:481-482`) to keep the `id:77ce` PLAN/APPLY parity oracle byte-identical.
   Any "surface it in RELAY_STATUS.md" proposal must address that oracle first.

**And then I accepted the framing that SOMETHING had failed, and filed `id:26ed` around a
question that did not exist.** The peer retracted hours later: quovadis never leaked, and de4a
did not merely fire, it **WORKED 6 of 6** -- 6 normalizations, 6 removals, 6 merged-branch
deletions, and `grep -icE 'defer|fail|refus|unremovable'` over every quovadis line returns
**0**. The pool REUSES one worktree path across rounds, so their point-in-time `git worktree
list` between a removal and the next re-create showed a LIVE worktree; they then ran raw
`git worktree remove`, hit its expected `error code 10`, and read that as an auto-reap failure.

**I had read both scripts at source and never opened their runtime log.** One grep answered it.
Refuting three claims correctly gave me false confidence in the fourth, unexamined one -- that
the incident was real at all. `id:26ed`'s line and its detail note both carry the retraction,
with the required edited-declaration in the note header. **The quovadis instance must NOT be
cited as corroboration for `id:2b7a`** -- it would be a false second data point.

## Two of my own verification harnesses were broken, and I nearly reported their output

Both discarded, neither reported as a finding, and only caught by calibrating against a
known-good line first:

* One mis-called `checkbox_line_owns_token` and returned "refused" for **every** input,
  including a trivially valid `- [ ] simple <!-- id:abcd -->`. Had I not calibrated, it would
  have "shown" that my own filed line was malformed.
* One ran **bash ERE under zsh**, where `[[ =~ ]]` differs, and reported the INBOUND branch as
  non-matching when it does match. It would have "shown" that INBOUND precedence does not exist.

The peer hit the same class in real time (a missing `<closed_only:0|1>` argument put a filename
into `[[ "$closed_only" -eq 1 ]]`, erroring every line) and discarded it because this failure
mode had just been named. **A BEFORE side that errors is an unreached fixture, not a negative
control** -- calibrate on a known-good input before trusting any negative result.

## What landed

* **`id:26ed`** filed with detail note, then **retracted in part** and the note edited with an
  explicit header declaration (`edad18c8`, `68bf2e6d`, `fa0fd140`, `c735cda6`).
* **`id:2b7a`** carries the live reproduction, the `:190` root cause, the 8-worktree/762 MB
  scope, and the corrected 30-count with its filtering rule (`0840864a`, `fa0fd140`, `e3e65bad`).
* **`id:1ce0`** filed (`ad456e4f`): the global `~/.claude/CLAUDE.md` inbox section has TWO
  defects that EACH produced a wrong claim today -- see Needs the owner.
* Relay pool integrated and pushed 2 units: `code.lawless` execute `id:d6f3` (substantive) and
  `project_manager` review `51a4`/`d1dc`.

## Needs the owner

1. **Dispose the 8 retirable worktrees (762 MB), or fix `worktree-retire.sh:190` first.** The
   one-line fix makes the normal path work and prevents recurrence; hand-disposal clears today's
   residue but the next annex run leaks again. Recommend the fix, then let reconcile drain it.
   Not mine to reap.
2. **`id:1ce0` -- your `~/.claude/CLAUDE.md`, deliberately not allowlisted, so surfaced not
   edited.** (a) Its `CAUTION, delete this clause when id:0246 closes` block about
   `scan-routed.sh --apply` is now STALE -- `id:0246` closed today and the clause instructs its
   own deletion on that event. (b) Its adopt-the-breadcrumb sentence names only the
   `routed:XXXX` HTML-comment spelling, never the `id:3743` `[INBOUND routed:TOK from X]`
   BRACKET-PREFIX form -- even though `scan-routed.sh --apply` writes exactly that shape and 176
   lines in `TODO.md` + 52 in `TODO.archive.md` use it. A peer trusting that sentence concluded a
   correctly-filed stub was missing its twin; the guard was green all along
   (`token_marker_in_files a5fc` -> 0).
3. **loderite is BLOCKED and handed back twice**: its assembled handoff prompt is ~484k tokens
   against the 300k `id:4f9b` budget. Almost certainly wants the `id:0d7c` line-shrink it is
   already mid-migration on.
4. **Shared inbox: 7 open, 4 targeted here, 1 twinned-resolvable (`routed:b015`).** I did NOT run
   `scan-routed.sh --apply` -- `id:5a5a` carries TODAY's owner ruling that inbox deletion stays
   ATTENDED and `--apply` must not run in the pool. Today's containment was kept on purpose.
5. **A pre-existing grammar sharp edge, deliberately NOT touched.** `checkbox_line_owns_token`
   tests the INBOUND branch FIRST and returns, so an INBOUND stub owns its `routed:` token and
   its OWN `<!-- id: -->` is SHADOWED: `token_owned_by_checkbox_in_files 26ed` -> 1 (not found),
   `a5fc` -> 0, while `token_marker_in_files 26ed` -> 0. Closure-tracking an INBOUND stub by its
   own id through that path does not see it. **176 lines in `TODO.md` + 52 in `TODO.archive.md`
   share the shape** -- a 228-line grammar decision, not a cleanup pass.

## Method notes

* **`relay-worktree-retire.log` is ~7.5x contaminated by the test harness's own `/tmp` fixture
  lines.** Any count over it needs a `\.cache/relay/worktrees` filter. This bit two sessions
  independently on the same day.
* **These log lines name the run token TWICE** (`wt=` and the trailing inspect hint), so
  `grep -oE` counts occurrences, not lines. Add `| head -1` per line.
* **`-f` follows symlinks.** `reconcile-repo.sh:249`'s `[[ -f "$wt/.git" ]]` is FALSE for an
  annex-symlinked `.git` (it points at a directory), so `wt_admin` stays empty. That only gates
  the SUBMODULE prediction, not the reap plan -- worth knowing before reading it as the cause.
* **The `git-lock-push.sh` id:aa93 dirty-guard refuses to rebase over a peer's tracked-dirty
  file and exits 0 WITHOUT pushing.** `--ff-only` takes a different branch that does no rebase
  and no SHA rewrite, so the guard's hazard is structurally absent; with 0 commits behind it is
  the right call and keeps the flock, unlike the bare `git push` the guard's own message suggests.
* **The annex smudge filter can FAIL to install its symlink** -- `unable to convert .git file to
  symlink ... createSymbolicLink '../../annex' to './.git/annex': already exists`. That, not a
  transient rewrite-back, is the better explanation for 7-of-8 worktrees carrying normal
  `gitdir:` files. **Do NOT read `.git` mtime ordering as evidence of a transient window** -- a
  failed conversion produces the identical ordering. I over-read that and corrected it.
* **`transcript-shape-preflight.sh` exit 4 INDETERMINATE at launch is normal**, not a fault: a
  fresh session has no child transcripts yet. Distinct from exit 3 by design.
