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
