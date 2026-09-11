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
| Suite | **639 passed, 0 failed, 0 errored, 1 expected-red** -- run at close, exit 0. Up from 637 at the evening handover; this session added no tests, so the +2 came from elsewhere today. Changes here were ledger/docs only, so a green suite CONFIRMS rather than clears anything. |
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

# LATE NIGHT -- same session, continued after the pool. THIS IS NOW THE AUTHORITATIVE CLOSE STATE.

## State at close

| | |
|---|---|
| `main` | `6954170f`, 0 unpushed, clean except a peer's `meeting/personas.md` (still not mine, still theirs to commit) |
| Suite | **641 passed, 0 failed, 0 errored, 1 expected-red** (`roadmap:6217`, pre-existing and unrelated) |
| Latest ckpt | `relay-ckpt-20260910-2047`, label `integrate (claude-opus-5)` -- strong-watermark sync deliberately SKIPPED, see below |
| REVIEW_ME here | **84 open**, unchanged (this stretch opened none) |
| Shared inbox | **10 open** (was 7), **5 targeted here** |
| Parked orphans | 2, unchanged (`...-execute-b437-0` here, `...-execute-repo-1` on code.lawless) |
| Retirable relay residue | **8 worktrees / 762 MB, all code.lawless** -- UNCHANGED, still the owner's call |
| Agent-tool worktrees | **415 MB / 29 worktrees / 58 merged branches** -- NEW finding, `id:5d91` |

## What landed, and loderite is UNBLOCKED

Two authorised fixes, one delegated and one direct. The number that matters:

| loderite handoff | charged | tok |
|---|---|---|
| unsliced, before today | 1,670,936 B | **417,734** |
| after `id:1737` dedupe alone | 1,237,291 B | **309,323** -- STILL over the 300,000 budget |
| sliced via `id:a060` | 6,716 B | **~1,679** |

* **`id:a060`** (background agent, merged `64293502`, ticked) -- the `handoff` lane had NO slice
  shape, so it was always sized on whole ledgers and a big-ledger repo could never RECEIVE a
  handoff. Same class as the closed `id:f957` one lane over. `classify-repo.sh` now emits
  `unpromoted_ids` (promote+surface, same single pass as the counts per the `id:b09e` drift
  lesson); `relay-loop.js` gains `unpromotedIdsFor` and a fourth `!useHandoffSet` bail term.
  Shape is `--ids`, never `--id`, so the C2 SURVEY survives.
* **`id:1737`** (direct, `41da4120`, ticked) -- the prompt-size gate charged a detail note
  pointed at from BOTH ledgers TWICE, penalising exactly the repos following the mandated
  single-id-two-views convention correctly. 67 shared notes, 433,645 B, ~108,411 tok on loderite.
* **Global `~/.claude/CLAUDE.md`, both halves of `id:1ce0`** (`6fe77c39c`, `0d331dc88`) -- removed
  the stale `delete-when-id:0246-closes` CAUTION clause, and named BOTH `id:3743` twin-guard
  spellings in the adopt rule. Each defect had already produced a wrong claim that same day.
* **Filed, not built:** `id:6de0` (`sliceInstruction`'s singular "the item's own block", false for
  three of four lanes now, with an UNPINNED inline twin at `relay-loop.js:2666`), `id:5d91`
  (the 415 MB agent-worktree surface).

## READ FIRST: three separate leaks, one shared shape

All three found today, all invisible for the same structural reason -- **the tool that could
dispose of the residue does not enumerate it**:

1. `id:2b7a` -- 762 MB, 8 code.lawless worktrees, behind ONE missing `git diff` cross-check at
   `worktree-retire.sh:190`. `relay-reconcile.sh --all` correctly calls them "no work at risk"
   and then recommends the very command the log shows refusing them 30 times that day.
2. `id:5d91` -- 415 MB, 29 Agent-tool worktrees, 58 merged branches. `relay-reconcile.sh` cannot
   see them at all: not `relay/orphan/*`, not under `~/.cache/relay/worktrees`.
3. The quovadis report that started it all -- a leak that **never happened** (see below).

Both (1) and (2) are pure reclaimable residue with nothing at risk, and both are the owner's
call, not a cleanup pass. Neither was reaped.

## THE CORRECTION THAT MATTERS MOST: I refuted three claims correctly, then built on the fourth I never checked

A peer routed `routed:a5fc` claiming annex `.git`-symlink worktrees are unreapable and `id:de4a`
never fired. I verified before filing and **refuted three claims**: wrong mechanism (it is
`filter.annex.process`, proven at `worktree add`, not `git annex init`); the annex-symlink
correlation is dead (8 of 9 worktrees carry an annex entry, exactly ONE is symlinked); and
"silent" was half wrong in the load-bearing half (`id:a290` logs it; withholding it from
`RELAY_STATUS.md` is DELIBERATE, to keep the `id:77ce` PLAN/APPLY parity oracle byte-identical).

**Then I accepted the premise underneath all three -- that an incident happened at all -- and
filed `id:26ed` around a question that did not exist.** It did not: `relay-worktree-retire.log`
shows 6 normalized / 6 removed / 6 merged-branch deletions for quovadis and ZERO defers.
`id:de4a` worked 6 of 6. The pool REUSES one worktree path across rounds, so a point-in-time
`git worktree list` between a removal and the next re-create shows a LIVE worktree that reads as
residue. **I had read both scripts at source and never opened their runtime log**; one grep
answered it. That lesson is now a durable rule in the global `CLAUDE.md` ("Read the tool's own
log before its source or its current state"). `id:26ed` and its note carry the retraction with
the declared edit; **the quovadis instance must NOT be cited as corroboration for `id:2b7a`**.

## My own measurement errors today, all self-caught, none shipped as findings

Five, and the pattern is one thing: **a one-liner applied to a corpus I had not characterised.**

* **Defer count 92, then 90, then 30.** Real answer 30. Two compounding errors: `grep -oE` emits
  EVERY token occurrence and these lines name the run token twice; and my filter
  `defer|unremovable|fail|refus` was broader than `DEFER` and swept in `/tmp` fixtures -- **195
  of 225 DEFER lines today are harness fixtures.** A raw `grep -c DEFER` over-reports ~7.5x.
* **Two broken verification harnesses.** One mis-called `checkbox_line_owns_token` and returned
  "refused" for EVERY input including a valid control; one ran bash ERE under **zsh**, where
  `[[ =~ ]]` differs, and reported the INBOUND branch as non-matching when it matches. Either
  would have "confirmed" a false story. Only calibrating on a known-good input caught them.
* **A monitor pattern that matched a FILENAME.** `passed|FAIL|failed` fired on
  `test_integrate_failed_push_ratification_5155.sh` and reported one `PASS` line as the summary.
* **`.split(",")` on a JSON array**, which made the a060 agent's correct "14 ids" read as 0.

The rule that caught all five: **calibrate on a known-good input before trusting any negative
result.** A BEFORE side that errors is an unreached fixture, not a passing negative control.

## Method notes

* **A background agent's branch can render your own newer work as DELETED.** The a060 agent
  branched before `id:1737` landed, so `main..HEAD` showed 1737 removed -- a branch-point
  artifact. A diff-apply would have silently reverted it; a `--no-ff` 3-way merge kept both, and
  I verified AFTER (`_CHARGED_NOTES` present, 1737 test present, both effects live together).
* **Audit a delegated agent's relaxation of an EXISTING test.** a060 relaxed
  `test_hard_lane_slice_f957.sh` to a prefix match -- legitimate: the old assertion included the
  closing `) {` and so pinned EXACTLY three slice sources, an arity it never meant to assert.
  Verified rather than accepted; that is the shape test-weakening takes.
* **`integrate (...)` NOT `reviewer (...)`.** `ckpt-tag.sh` acknowledged the non-strong role and
  skipped the strong-watermark sync BY DESIGN. I audited specific claims but ran no full review
  pass, and `reviewer` would advance `last_strong_ckpt` for work nobody reviewed (`id:ecce`).
* **A `fails-against-assertion` must match the LAST FAIL line, and uniquely.** My first 1737 spec
  tripped three FAIL lines; matching a generic summary would be the vacuous-prefix case the same
  rule bans. Converting the test to fail-fast makes exactly one line-leading `FAIL:` possible.
* **`~/.claude` pushes need `--ff-only` while other sessions hold it tracked-dirty.** The
  `id:aa93` guard refuses to rebase over foreign dirt and exits 0 WITHOUT pushing; `--ff-only`
  takes the no-rebase branch where that hazard is structurally absent.
* **Name a token only AFTER minting it.** I wrote "filed as id:33fb" into a ticked item before
  minting; the real token was `6de0`, and the dangling reference had to be corrected.

# CLEANUP TAIL -- same session, after the late-night section. THIS IS NOW THE AUTHORITATIVE CLOSE STATE.

## State at close

| | |
|---|---|
| `main` | `045dea02` + the commits below; clean except a peer's `meeting/personas.md` |
| Suite | **642 passed, 0 failed, 0 errored, 1 expected-red** (`roadmap:6217`, pre-existing) -- run AFTER the archive merge, since the archives feed `orphan-scan`, `roadmap-lint` and the lane-vocab ratchet |
| Latest ckpt | `relay-ckpt-20260910-2115`, label `integrate (claude-opus-5)` |
| REVIEW_ME here | **84 open**, unchanged |
| Shared inbox | **9 open**, 4 targeted here |
| Parked orphans | 2, unchanged and both deliberate |
| **Relay worktrees** | **0 dirs, 0 bytes** (was 8 dirs / 762 MB) |
| **Agent worktrees** | **0 dirs, 0 bytes, 0 branches** (was 29 dirs / 415 MB / 58 branches) |

## ~1.16 GB reclaimed across TWO surfaces, both force-free, nothing lost

* **Relay side, 762 MB, 8 code.lawless worktrees** -- unblocked by fixing `id:1a5c` (below), then
  retired by the tool: `branch -d` never `-D`, residue archived and recoverable under
  `~/.cache/relay/discarded-residue/`.
* **Agent-tool side, 415 MB, 29 worktrees + 58 branches** (`id:5d91`) -- 28 retired by the
  UNMODIFIED `worktree-retire.sh --expect-merged`, plus 29 merged worktree-less branches deleted
  force-free. The 29 branch-only refs were HALF the surface and are a big part of why 415 MB stayed
  invisible: `relay-reconcile.sh` cannot see any of it.
* **The last holdout was resolved by COMMITTING, not discarding** (owner instruction): worktree
  `agent-a6bb08543e21587fe` held an uncommitted archive lane-delimiter migration. Verified pure
  BEFORE committing -- 85 removed / 85 added, every pair byte-identical after normalising dashes,
  ZERO non-delimiter changes, and only the LEADING lane tag converted so in-prose citations keep
  their em-dash (14 such lines). Committed on its branch, `--no-ff` merged, worktree then retired.
  The "never hand-swap a delimiter in isolation" hazard does not reach this surface: archived items
  are closed and never dispatched, and the ratchet blocks only the reverse direction (and per
  `id:2065` skips archive files regardless).

## READ FIRST: `id:1a5c` -- the annex normalization was STALE BY THE TIME IT MATTERED

`worktree-retire.sh` ran `id:de4a`'s `.git`-symlink normalization ONCE, at step 0. But the residue
steps run `git checkout -- .`, git-annex's `filter.annex.process` re-creates the symlink as a side
effect, and the `git worktree remove` at step 1 then fails its OWN validation with `'.git' is not a
.git file, error code 10`. So a worktree could have its residue successfully discarded and still be
unremovable, every run, forever. **Fixed** (`ecb6c22c`): the normalization is now an idempotent
function called TWICE, the load-bearing call immediately before the removal with no filtered git
read between. All 7 remaining worktrees then retired through the unmodified tool.

**IS IT A GIT OR ANNEX BUG? Neither -- an INTEROP gap, both sides reasonable.** annex deliberately
symlinks a linked worktree's `.git` so annexed relative symlinks (`../.git/annex/objects/...`)
resolve inside the worktree. git's worktree-remove validation requires a FILE and runs BEFORE
`--force`, so force cannot override it, even though a symlink resolving to the correct admin dir is
functionally equivalent -- that stricter-than-necessary check is the only half worth an upstream
report. annex itself calls the resulting status *"only a cosmetic problem affecting git status; git
add, git commit, etc won't be affected"*; git has no channel to hear it. **WHY THIS REPO ONLY:** the
filter only has work when the index is stale against annexed files (93 PNGs on code.lawless), which
is why zkWhale's 3 worktrees and quovadis's 6 normalize+remove pairs all succeeded. **A green run on
a clean-index repo proves nothing about this path.**

## THE CORRECTION THAT MATTERS MOST: I invented a deadlock out of my own contaminated measurement

I told the owner these worktrees were a TWO-STATE DEADLOCK -- that the two failure modes alternate
so neither `.git` state is removable -- and filed that on `id:2b7a`. **It was false.** With a proper
`gitdir:` file the code-10 validation PASSES; the failures are SEQUENTIAL. The claim came from a
diagnostic that reported `.git` as a regular file while running `git status` on the SAME SHELL LINE,
which tripped the filter before `worktree remove` was reached -- so the removal looked like the thing
re-creating the symlink. It is not; any filtered git read is. The owner corrected the framing
directly ("you can replace the .git symlink by the .git file a worktree usually sets up, we've had
this thousands of times before"). `id:2b7a` now carries an explicit disregard-that-paragraph
correction rather than a quiet edit. **The generalisable part:** a measurement and the thing it
measures must not share a shell line when the measurement has side effects.

## The test took FOUR attempts and the first three were vacuous or silent

`tests/test_worktree_retire_renormalize_1a5c.sh`. Worth reading before writing a fixture here:

1. symlinked `.git` UP FRONT -- so step 0 normalized it and the pre-removal call was never needed;
   the mutation passed and the test pinned NOTHING.
2. extracted the `--ack` token with `[0-9a-f]+`, which matches the **`ac` inside the word "ack"** and
   yields a stale token -- reporting a fix defect that was really a grep defect.
3. dropped a `|| true`, so the token-minting run's deliberate exit 3 propagated under
   `set -e`/`pipefail` and killed the script **SILENTLY** -- no ok, no FAIL, a truncated run that
   reads as a pass to a skimming eye.
4. drives the re-symlink with a **SMUDGE FILTER**, which is what annex actually uses and which DOES
   fire on a pathspec checkout -- a `post-checkout` hook does not. `make verify-negatives`:
   green-now OK, red-there OK; declared substring matches exactly one body line.

## Filed for next session

* **`id:8a76`** -- teach `relay-reconcile.sh` to enumerate and retire the agent-worktree surface,
  carrying the PROVEN recipe (28 retirals) plus the four things the implementation must get right:
  the three-part eligibility test (0 ahead AND clean AND merged); the residue flags' by-design
  refusal of non-`relay/*` branches, so a dirty one can only be SURFACED; worktree-LESS merged
  branches as a second independent surface; and liveness gating (plus: the shell must not be
  CWD-inside a worktree it is removing -- I tripped that myself).
* **`id:5d91`** part (b) still open: whether `/relay health` / `relay-doctor.sh` should REPORT this
  surface at all. Today nothing does, so a human can only find it by looking.
* **`id:ab95`** -- `archive-done.sh`'s `id:5355` own-date guard is blind to 48 of 61 dated items
  (regex anchors the date to EOL; the ledger convention puts `<!-- id:XXXX -->` there). Severity
  REDUCED and stated as such: `id:1d83` made the twin check archive-inclusive, verified here, so the
  residual harm is discoverability, not guard starvation.
* **`id:6de0`** -- `sliceInstruction`'s singular "the item's own block", now false for three of four
  lanes, with an UNPINNED inline twin at `relay-loop.js:2666`.

## Method notes

* **A measurement with side effects must not share a shell line with what it measures.** The whole
  phantom deadlock came from `stat` and `git status` in one `echo`.
* **`git worktree remove` cannot be beaten by `--force` on a symlinked `.git`** -- validation
  precedes force. The route is to repair the layout to git's own supported shape first.
* **`worktree-retire.sh` works UNCHANGED on Agent-tool worktrees** (`--expect-merged`), but its
  residue flags refuse a non-`relay/*` branch by design. Do not add a residue path there without an
  owner decision.
* **The destructive-git guard governs the AGENT's Bash tool, not the scripts it invokes.** A
  tree-wide `git checkout -- .` is refused for me and runs fine inside `worktree-retire.sh`. That is
  the intended asymmetry, not a bug to route around.
* **A markdown diff line reads `-- [x]`** -- the diff's `-` plus the checkbox's own `-`. A pattern
  like `^[+-][^+-]` therefore excludes exactly the lines you want, and silently reports 0 changes.

# RELAY-HUMAN SWEEP -- new session, 2026-09-10 late. THIS IS NOW THE AUTHORITATIVE CLOSE STATE.

## State at close

| | |
|---|---|
| `main` | `27a702a4`, clean, 0 unpushed to private `origin` |
| Suite | **645 passed, 0 failed, 0 errored, 1 expected-red** -- run at close on `27a702a4`, exit 0. The 1 is `test_dryround_single_definition_6217.sh`, a pre-existing open roadmap item, untouched all session |
| **Ledger ratchets** | **ARMED** -- `0` INERT via the installed path (was 4), 51 findings live, and TIGHTENED (3 length + 5 shape floors lowered) |
| REVIEW_ME here | **79 open** (was 84) |
| Shared inbox | **2 open** (was 9) |
| Parked orphans | 1 (`...-execute-b437-0`, deliberate) |
| Ratification queue | 0 pending |
| Public GitHub | **16 behind, all withheld by design** -- every push tonight went to private `fievel:` only |

## READ FIRST: `scan-routed.sh --apply --dry-run` DELETES REAL INBOX LINES

Its header at `:31` promises dry-run "writes NOTHING". `DRY_RUN` is consulted at exactly ONE
place in the body -- `:388`, the stub path. The twinned-drain branch at `:324` guards on `APPLY`
alone, so `append.sh inbox-done` runs and vanish-on-resolve removes the line. The summary then
prints **"APPLY DRY-RUN: no writes performed."**

Observed live: a dry-run drained `routed:b015` and `routed:51a4`; the log records
`resolved=2 apply=1 dry_run=1`. The PER-LINE output was honest (`RESOLVED ... removed from
inbox`); the SUMMARY lied -- and a dry-run is read for its summary. Filed **`id:f563`**.

The irony is on the record: `id:0246` re-landed earlier the same day after 9 review defects and
hardened *this exact branch* against counting a failed drain as success, leaving the dry-run hole
beside it.

## The `id:7c75` composer exists now, and it is what makes `/relay human` 3(a) performable

`relay/scripts/review-box-tick.py`. `md-merge.py` addresses a line only by an anchored
`<!-- id:XXXX -->` marker or a `## ` heading whose unit is the WHOLE section, and the common
REVIEW_ME shape is one coarse heading over many boxes. The composer extracts the section
verbatim, flips EXACTLY ONE checkbox, appends the rationale, and hands the section back to
`md-merge.py update-sections` under its flock.

**Measured by RUNNING it against all 431 open boxes fleet-wide, not by a predicate: 308 tick
well-formed, 120 refuse exit 4 (no `## ` heading), 3 refuse exit 9 (box markup already broken).**
Its own static estimate of 311 was 3 too high.

Refusals are code-distinguished per the `id:6d7e` ruling: 0 matches exit 2, 2+ exit 3, no heading
exit 4, **repeated heading exit 5** (md-merge keys on heading TEXT and rewrites every match, so
taking the first would duplicate one section into all of them), unbalanced inline markup exit 9.
`--dry-run` is inert BY CONSTRUCTION, not by a re-checked flag -- deliberately, because of
`id:f563` above.

**It shipped with a placement defect that its own tests missed, caught on first real use.** v1
appended to the box's first PHYSICAL line, splicing the rationale mid-sentence and leaving `**`
unclosed. **188 of 431 boxes (44%) have a wrapped title.** Fixed by appending as its own
paragraph at end-of-box -- uniform for wrapped and unwrapped, so no branch is left that can pick
wrong, and the checkbox line then changes by exactly its checkbox character, which keeps an
anchored id line-final.

## Ratchets: ARMED first, then TIGHTENED. Do not blanket-regen.

Both baselines were tracked in-repo and **absent from `~/.claude/skills/relay/`**, so they fired
for no repo. `make install-relay` fixed it: 0 INERT, 51 findings live.

Then the owner REFUSED a blanket regen on measurement. `todo-conformance.sh`'s own docstring
claimed *"A regen TIGHTENS the ratchet"*. **That claim was false** -- a regen RAISES a ceiling
whenever a line grew:

| id | old | blanket regen | |
|---|---|---|---|
| `2b7a` | 750 | **10,190** | +9,440, a 13.6x raise |
| `3770` | 2,209 | 2,536 | +327 |

plus 14 new length rows and 27 shape rows: **36,513 chars forgiven**, more than twice the remedy
rejected that morning in `48e51a83`. A grandfathering row has **no expiry**.

`id:7e3b` was built instead and applied: **3 length + 5 shape floors LOWERED, `2b7a` and `3770`
REFUSED by name in both families, 17,474 chars of forgiveness declined.** Verified independently
before landing: 0 rows rose, 0 minted, counts unchanged.

**Gotcha:** the documented invocation chains `--emit-baseline > file && mv`, but the tool exits
NON-ZERO whenever anything is refused -- which is the normal case -- so the `mv` never fires and
the regen looks like it ran and did nothing. `make baseline-tighten` inherits that exit.

## code.lawless was FALSE-DIRTY all day, and the mechanism generalises

111 paths ` M` with an EMPTY `git diff`. Cause: **unlocked git-annex pointer files**. The index
cached the 100 B pointer's stat; annex swapped in the 15,641 B content 0.3 s later; git never
re-stat'd. Content identical on all 111 (`git hash-object --path` vs index blob:
`identical=111 differing=0`).

**Why it never self-heals, proven with `GIT_TRACE`:** `git update-index --really-refresh` spawns
**ZERO** subprocesses, so it never runs the clean filter and compares a 15,641 B PNG to a 100 B
blob. `git diff --quiet` spawns `git-annex filter-process` and reports equal. `git status` and
the refresh path are filter-blind; `git diff` is not.

**btrfs contributes nothing** -- not a subvolume, cached dev matches. The discriminator was a
calibration: a LOCKED annexed file carries a genuinely stale device number and still reads clean,
so stat drift alone self-heals and only the filter-requiring size mismatch is fatal.

Two plausible checks did NOT discriminate and are recorded as such: `annex fsck --fast` printed
`ok` and left the file dirty; `restage.log` holds 837 queued entries of which **zero** are the
dirty paths.

**204 unlocked annexed files remain, so it WILL recur.** `id:8cc6` fixed `clean-tree-gate.sh`
(a `git diff` cross-check, demonstrated on a real annex repo the agent built), but its adversarial
pass correctly reported **this does NOT unblock dispatch**: the closed door is
`gather-repo-state.sh:191`, its own bare `git status --porcelain`. **That is the FOURTH instance
of one missing predicate** (`verify-isolation.sh:190` = `id:3016`, `worktree-retire.sh:190` =
`id:1a5c`, `clean-tree-gate.sh:60` = `id:8cc6`, and now the classifier). It was left alone
deliberately: relay-core's shadow binary reimplements those semantics, so a change there goes
parity-red cross-repo and needs inbox routing.

## What landed

* **`id:f563`** -- the dry-run deletion defect, filed.
* **`id:7c75`** -- the composer, plus its wrapped-title fix. **STILL OPEN** by owner choice.
* **`id:7e3b`** -- tighten-only baseline regen, built AND applied. Ticked by its own build commit.
* **`id:8cc6`** -- `clean-tree-gate.sh` cross-check. **STILL OPEN** by owner choice, correctly.
* **`id:099d`** -- `LEDGER_NOTE_POINTER_RE` (`classify-repo.sh:198`) is unanchored, matching any
  path-shaped `<4hex>.md` in raw text, and `:303` scans `REVIEW_ME.md` too. **Two confirmed
  instances in one evening**: this repo charged 32,768 B for `4983.md` named only in the box
  DESCRIBING the charge, loderite for `e57b.md` named only in *"no ... e57b.md exists"*. The
  `id:2964` class one tool over.
* **`id:1e82`** -- `expires-on-scan.sh` is installed, allowlisted, tested green, and **nothing
  invokes it**. 0 refs in `relay-loop.js` (control: `ledger-slice` = 10), 3 in the Makefile all
  MANIFEST vars not a recipe, 0 in SKILL/references. The `id:5367`/`id:2062` built-green-but-
  unwired class. `a192`'s residue is the narrower second half.
* **`docs/ledger-notes/4983.md`** created -- the 32 KB overcharge on every classification is gone.
* **loderite handoff MERGED** (`a11d993a`): 9 ids promoted reusing their TODO tokens, 4 RED specs
  verified red, `unpromoted-scan` now `45 laned / 5 surface / 0 promote`.
* **code.lawless handoff**: `a736` promoted `[ROUTINE]` with a RED spec, verdict flipped
  `hard` -> `execute`. `eb1f` re-laned `[HARD]` -> `[INPUT - meeting]` -- on the pool lane an
  `--afk` run would have tried to BUILD a design question whose done-check is a meeting note.
* **Inbox 9 -> 2**: 6 INBOUND stubs written and committed, twinned items drained.
* **`fe67` / `02fe` / `a192` promoted** after being confirmed ABSENT from all four ledgers.
* **toesnail `id:0720`**: `verify/dreamed_lean_pin.sh` added as its own CI step (0.02 s), NOT
  `tests/run.sh` which would drag a cold Mathlib build into every push.
* **zkWhale `id:bf66`**: ticked with `@owner-accepted:2026-09-10`, the repo's FIRST real marker.

## OWNER RULINGS this session

1. Inbox `--apply` **excluding loderite** while its handoff was live.
2. code.lawless orphan: **inspect and report**, decide after (still undisposed -- see below).
3. Ticks: **tick what is reachable AND build the composer** (both, not either).
4. Baselines: **install first, then build `id:7e3b`, then tighten** -- explicitly NOT a blanket regen.
5. ai-codebench **`515b`: accept the 1-judge matrix** -- the four `[INTENSIVE]` seams become
   ENRICHMENT, no GPU needed.
6. dotclaude-skills **`4983`: create the note** (not edit the archive, not fix the counter).
7. project_manager: **un-gate `71f5`, drop `cb9e`'s pool tag** -- both lint ERRORs cleared.
8. mathematical-writing **`f8d5`: lane `[ROUTINE]` and promote**.
9. **`fe67`/`02fe`/`a192`: promote all three.**
10. toesnail **`0720`: standalone guard as its own CI step.**
11. zkWhale **`bf66`: add `@owner-accepted` and tick.**
12. Of the three unticked items, **close `7e3b` only** -- `7c75` and `8cc6` stay open.
13. **File the `a192` residue** as tracked work (became `id:1e82`).

## Needs the owner

1. **`gather-repo-state.sh:191`** -- the fourth instance, and the only one still blocking
   dispatch. Needs inbox routing to relay-core because of shadow parity, not a local edit.
2. **ai-codebench's `515b` tick is on a SIDE BRANCH.** `git branch --contains 597d4e5` lists only
   `claude/opusplan` and its remote; `main` has no `Surface the peer-review matrix` line at all,
   so it is structurally different, not merely behind. **The ruling is recorded nowhere on `main`.**
3. **code.lawless parked orphan** `relay/orphan/relay-20260910-114832-18641-execute-repo-1`
   (`fd962dc`) is **NOT residue**: it adds a 168-line second write-up of the `id:f0de`
   investigation whose 194-line sibling is already on main. Different blobs, each carrying content
   the other lacks (the orphan uniquely has the bundle-size table and the playwright
   reproduction commands). **`--integrate` CANNOT work** -- the file did not exist at the
   merge-base, so it is an add/add conflict; reconcile will abort and re-park, correctly. The real
   choice is salvage-by-hand or discard.
4. **120 REVIEW_ME boxes have no `## ` heading** and are unreachable by any flock'd path.
   13 repos, including 4 with zero headings entirely (mathematical-writing, ai-codebench,
   project_manager, zkWhale). Closing them needs a decision `id:7c75` still poses: mint anchored
   markers onto the checkbox lines, or give the boxes headings. The composer deliberately mints
   neither.
5. **`02fe` was closed `[x]` on an agent's own judgement**, not on a stated ruling -- the owner's
   option said "file them as open items", and the closed-if-done path was authorised only for
   `a192`. Test-backed (`test_repo_section_quoting_02fe.sh` exit 0), flagged rather than passed
   off as ratified. One `md-merge` call to reverse.
6. **A guard for review-minted tokens that nothing owns** -- proposed, not built. Third instance.
   Two design questions left open deliberately: does a token in a COMMIT SUBJECT alone count as
   ownership (it is what surfaced `02fe`, but would flag transient tokens), and does REVIEW_ME
   PROSE count (which is where all three of tonight's tokens actually lived).
7. **toesnail's new CI step is unverified on Actions** -- pushed to private `origin` only, while
   Actions runs from `github`. `test_ci.sh` proves the file is well-formed, not that the run is green.

## THE CORRECTIONS THAT MATTER MOST

**I read an agent's silence as an answer, on the exact item I had filed that day for it.** I told
the owner `id:7e3b` was unticked and asked him to rule on it. `git blame` puts the tick at
`8713787b`, the build agent's OWN commit. Its report had a "what I did not do" section that never
mentioned ticking. That is `id:3f59` -- reasoning from a source that does not record the thing
being asked about -- and it cost the owner a question he should not have been asked.

**A `grep -c INERT` matched the PROSE of the item about inert ratchets.** My first verification
that the ratchets were armed returned "2 INERT remaining". Both hits were the text of a ROADMAP
item discussing inert ratchets. Anchoring to stderr and to `ratchet INERT --` gives 0. Same shape
as the `id:099d` pointer regex and the monitor pattern that matched a filename: **a pattern
matching a corpus that talks about the thing it is looking for.** Three instances, three tools,
one evening.

**My own brief sent an agent after the wrong file.** I told it `ROADMAP.archive.md:4584`'s pointer
named the missing `4983.md`. It does not -- it points at `6546.md`, which exists. The 32 KB charge
came from `REVIEW_ME.md:319`, the review box's own prose. The agent verified before acting, found
the premise wrong in mechanism but right in remedy, and said so instead of either stopping or
silently complying. That is the behaviour to keep.

## Method notes

* **`review-box-tick.py` is the `/relay human` 3(a) apply path.** Always `--dry-run` first and
  READ the diff -- the wrapped-title defect was invisible in tests and obvious in one dry-run.
* **Calibrate a wiring grep with a known-wired control.** `grep -c expires-on-scan relay-loop.js`
  = 0 means nothing until `grep -c ledger-slice relay-loop.js` = 10 proves the grep works. A
  Makefile hit may be a MANIFEST variable, not a recipe -- check which.
* **Use `token_marker_in_files` (`lib-anchored-id.sh`), never a bare `grep -c`, to ask whether a
  checkbox owns a token** -- and include BOTH archives (`id:1d83`). A multi-file `grep -c` in a
  zsh loop returns per-file lines and will produce garbage.
* **A measurement and the thing it measures must not share a shell line** when the measurement has
  side effects. Still true; still bit someone today.
* **`git-lock-push.sh` exit code is not evidence.** Verify with `git ls-remote`.
* **`| head` under `set -euo pipefail` is BLOCKED** by `tests/test_pipefail_sigpipe_lint.sh`.
* **A `fails-against-mutation` can be red for the WRONG reason** and the runner catches it. Three
  agents hit this tonight; each narrowed the declaration rather than loosening the check.

# INTENSIVE POOL RUN -- overnight 2026-09-10 23:46 -> 2026-09-11 02:00. THIS IS NOW THE AUTHORITATIVE CLOSE STATE.

Run `relay-20260910-234645-16942`, launched `--intensive --quota-7d 65` (intensive implies
`--afk`, so apex `hard` dispatch was live). 597 agents, 5.45 M subagent tokens, 2 h 18 m.

## State at close

| | |
|---|---|
| `main` (this repo) | `3541b328`, clean, 0 unpushed to private `origin` |
| Pool outcome | **17 units integrated, 17 handbacks, 6 rounds**, `stopReason: blocked-pending-human` |
| Quota | **NOT the stopper** -- `quotaStopped: false`; 7d went 46% -> 55% against the 65% cap, 5h 30% |
| REVIEW_ME here | 86 open |
| Shared inbox | **0 open** (3 stubs filed pre-launch, all twinned) |
| Residue | **10 leaked worktrees, 6 parked orphans** -- enumerated below, none disposed |
| MECHANICAL queue | **empty** -- `recipes/pending/` and `recipes/running/` both empty, daemon timer live |

Integrated: quovadis (x5), trustless-ai (x4), code.lawless (x2 `hard`), it-infra, toesnail,
project_manager, dotclaude-skills (review).

## READ FIRST: this repo cannot dispatch `execute` work at all -- 650 k tokens against a 100 k budget

Five consecutive handbacks, the id:4f9b/id:b018 prompt-size gate:

> the assembled execute prompt for dotclaude-skills is **~650,104 tok**, over the **100,000 tok**
> dispatch budget, so the child would die with "Prompt is too long"

The gate did its job -- it refused rather than burning a child. But dotclaude-skills is now
**structurally undispatchable on the execute lane** until the prompt is sliced. This is the same
family as the correction we sent loderite hours earlier (`routed:08c5`): their `id:a060` is "the
handoff lane has no slice shape at all". Ours is the execute lane, 6.5x over budget. Whether they
share one root cause is **not established** -- I did not verify it, and the loderite item is about
a different lane.

## Four children died `Prompt is too long`, and the knob that prevents it was not set

`execute` failures in loderite, project_manager, mathematical-writing, code.lawless -- all four
Sonnet, which is the id:c3c1 signature exactly (the ~82 k default delegated-subagent preamble is
46% of the Sonnet wall). **`EXECUTE_AGENT_TYPE` was unset for this run**, so every execute child
carried the full default preamble. `relay-implementer` is installed and is precisely the trimmed
definition for this. Recommendation for the next pool: pass
`--execute-agent-type relay-implementer`. I did not set it retroactively -- it is a per-run posture
change and the owner's call, and note it FAILS LOUD if the definition is not visible to the session.

## `id:c076` fail-closed fired 5 times across 4 repos -- classifier/queue wiring, not absent work

quovadis (x2), code.lawless, trustless-ai, project_manager all handed back with an **empty
permitted-id set**: the classifier dispatched a unit whose dispatch reason cited open `[ROUTINE]`
items while computing no permitted id for it. The children correctly refused to survey ROADMAP and
work something unauthorised. Every one of those reports says the same thing: *"a classifier/queue
wiring fault, not an absence of work."* Five instances in one run makes this the run's largest
systematic defect. Not filed as an item -- I did not diagnose it, and filing a cause I have not
established would be the `id:3f59` class.

## code.lawless: the predicted false-dirty class cost 7 dispatches, plus one landed-but-unfinished merge

* **7 repeat handbacks**, `id:34b7 pre-dispatch worktree provisioning failed -- no child dispatched`.
  The morning handover predicted this exactly: `gather-repo-state.sh:191`'s bare
  `git status --porcelain` is the fourth instance of the missing filter-aware predicate, and it was
  left alone deliberately because relay-core's shadow binary reimplements those semantics. **That
  decision has a measured price now: 7 dispatches in one run.** It still needs inbox routing to
  relay-core, not a local edit.
* **`id:5fe2` LANDED-BUT-UNFINISHED** (ids a736, 7627, b819, 25fd, e4a1): merge
  `866b226a` is **COMMITTED, TAGGED (`relay-ckpt-20260911-0031`) and PUSHED**; integrate.sh handed
  back at the POST-LAND `worktree-retire` step (handbackCode 28) because the worktree contains
  modified/untracked files. `relay.toml last_ckpt` was reconciled. **DO NOT re-merge or re-dispatch**
  -- a retry takes the zero-commit path and mints a SECOND checkpoint tag. Steps that did not run:
  worktree-retire, state-write, strong-state, push-seed. Needs a supervised reconcile.

## project_manager's 3 dirty-tree handbacks are EXPLAINED, not a defect

`integrate.sh handback=clean-tree handbackCode=20 ... dirty 1: M IDEAS.md`. A live
project_manager session was working that repo concurrently all evening -- it messaged this session
mid-run. The id:aa93 guard refusing to integrate over a concurrent edit is the guard **working**.
No action; expect it to clear once that session closes.

## Residue -- 10 leaked worktrees, 6 parked orphans, NONE disposed

Deliberately left for a supervised pass (`id:8a76` is the item that would mechanize this):

* worktrees: code.lawless x4, quovadis x2, project_manager x2, trustless-ai x2
* parked orphans: code.lawless x2, project_manager, mathematical-writing, loderite, and the
  pre-existing deliberate `dotclaude-skills ...-execute-b437-0`

Four of the orphans are `id:f272` WIP-UNVERIFIED residue auto-commits from the children that died
`Prompt is too long` -- **do not treat them as reviewed work.**

## The `[MECHANICAL]` queue is empty -- there was nothing to launch

Asked to run the remaining `[MECHANICAL]` tasks sequentially, I found **none runnable**, and the
count that looks obvious is wrong:

* A bare `grep '[MECHANICAL]'` over own-repo ROADMAPs reports **9** items. **3** is the truth.
  Six of the nine carry the word only in trailing prose while their primary lane is something else
  -- five ai-codebench items are `[INPUT - decision] [INTENSIVE - local-llm]` GPU runs, one
  isochrone item is `[HARD - hands]`. Resolved with `leading_lane_run` against the scraped
  vocabulary, not by eye. This is the third instance this week of **a pattern matching a corpus
  that discusses the thing it searches for**.
* Of the 3 real ones: isochrone `id:11c3` is a `@container`, GATED, and says in its own text *"pick
  those, not this container"*; isochrone `id:ac14` already ran its `--mode transit` recipe in July
  and its residue needs a **new recipe authored** (a sanctioned-author act) covering `--mode car` +
  `stop_matrix` + `extract_features.sh`; trAIdBTC `id:3a50` is scheduled LOW-PRIORITY for a
  *"next human-coordinated network-bulk session"*.
* The launcher is already automated regardless: `mechanical-daemon.timer` is live (ran 01:52, next
  02:22) and drains `recipes/pending/`, which is **empty**. `recipes/drafts/` holds 12 unapproved
  drafts -- including `bde7` (the decision-gated GPU run) and `11c3` (the gated container).
  **Promoting a draft to `pending/` unattended would have run exactly the work that is gated.** Not
  done.

## Also landed this session

* **`a1ec` re-laned `[INPUT - access]`** in it-infra (`841ded0`, pushed, remote verified). Flagged
  by the live project_manager session. It had been adopted untagged by the pre-launch
  `scan-routed.sh --apply` and was invisible to the lane detector -- verified with a negative
  control: the pre-fix line returns `[]` from `leading_lane_run`, the fixed line returns
  `[INPUT - access]`. Lane had to precede the `[INBOUND ...]` prefix to be seen, which is the shape
  `lib-anchored-id.sh:205` documents as canonical, so the inbox twin guard still matches (verified).
  Chose `access` over `meeting` despite its "no open judgment call" wording: the deliverable is a
  touch-ergonomics verdict and a meeting venue has no phone. Not split -- the poolable half opens no
  gate. Gates project_manager `id:c935`.
* **3 inbox dead-letter stubs filed** pre-launch: `a31f` (loderite), `a25f` (here, the `id:7e87`
  escalation trigger), `a1ec` (it-infra). Inbox is now 0 open. Safe to run attended because
  `0 twinned-resolvable` meant the run deleted nothing.

## Needs the owner

1. **The 650 k execute prompt here** -- this repo is undispatchable on its own execute lane. Needs
   a slice shape; related in family to loderite's `id:a060` but not proven to share a root.
2. **`EXECUTE_AGENT_TYPE=relay-implementer`** for the next pool -- 4 children died without it.
3. **`id:c076` x5** -- wants an actual diagnosis before anything is filed.
4. **`gather-repo-state.sh:191`** -- unchanged from this morning's list, but now carries a measured
   price (7 code.lawless dispatches). Inbox-route to relay-core.
5. **`id:5fe2` supervised reconcile** on code.lawless -- and the standing **DO NOT re-merge**.
6. **10 worktrees + 6 orphans** to dispose.
7. Still open from this morning, untouched: the code.lawless parked orphan salvage-vs-discard, the
   `02fe` closed-on-agent-judgement reversal, and the 120 heading-less REVIEW_ME boxes.

## Method notes

* **Resolve a lane with `leading_lane_run` + `lane_vocab_scrape`, never a grep.** The vocabulary is
  scraped from `hard-lanes.md` at runtime; sourcing `lib-lane-anchor.sh` alone leaves
  `all_lane_tags` EMPTY, so a standalone probe returns "no lane" for every line on earth. My first
  probe did exactly that and I nearly read its empty output as a finding -- an unpopulated fixture
  is not a negative control.
* **zsh's builtin `echo` eats backslashes**, so `echo '{"pattern": "\\["}' | md-merge` dies with
  "Invalid \escape". Use a quoted heredoc and validate the JSON before piping it.
* **A workflow result file is the wrapper's JSON with the real payload nested under `result`**;
  `json.load(...)['completed']` on the outer object silently returns 0 units for a 17-unit run.
