# Strong-model audit -- id:401c Run 73 (2026-09-12 21:42)

Reviewer-model (Opus apex) 3-pass adversarial audit, run as a relay HARD-execute child of
`relay-20260912-191938-25818` on branch `relay/relay-20260912-191938-25818-hard-repo-1`.

## 0. Window: DECLARED BOUNDED, and the residue is named

The item's own rule is "diff against the most recent checkpoint", and the run log's practice
is the stricter "first-seen code since the previous run's audit commit". Applying the strict
rule here gives `1b7e9bb..HEAD` (Run 72's HEAD, 2026-08-12):

| measure | value |
|---|---|
| commits | 4,940 |
| changed `*.sh` / `*.py` / `*.js` / `*.mjs` files | 649 |
| insertions, all of the above | 81,429 |
| insertions EXCLUDING `tests/` and `tracker/fixtures/` | ~28,000 |

**A full 3-pass adversarial audit of ~28 kLOC of production change is not soundly performable
in one turn**, and manufacturing a verdict over it would be worth less than no verdict. This
run therefore takes the **Run 70 precedent explicitly**: Run 70 met a 1,709-commit window,
declined it, ran a bounded pass over the newest surface, and recorded that the earlier windows
stay uncertified. Same shape here.

**Bounded surface audited, chosen as "every production file ADDED since 2026-09-10"** -- the
newest code, brand-new rather than modified, so nothing in it has ever been audited:

| file | new lines |
|---|---|
| `decision-brief/docket.sh` | 737 |
| `relay/scripts/review-box-tick.py` | 500 |
| `relay/scripts/expires-on-scan.sh` | 197 |
| `relay/scripts/lib-clean-tree.sh` | 138 |

That is ~1,570 lines, comparable to Run 15 (~1.9 kLOC) and Run 8 (615 lines).

**RESIDUE, stated so it is not mistaken for coverage:** `1b7e9bb..HEAD` minus those four files
is **UNAUDITED**, including the ~3.3 kLOC of MODIFIED production code in the same two-day
window (`relay-loop.js` +333, `todo-conformance.sh` +292, `meeting/append.sh` +187,
`worktree-retire.sh` +167, and others). Windows before Run 70 also remain uncertified. The
watermark defect behind the original starvation is `id:da95` and is untouched by this run.

## 1. Pass 1 -- code review

### F1 (MEDIUM, FIXED INLINE) -- `docket.sh draft-answer` duplicates the anchored id marker

`cmd_draft_answer` composed its proposed line with

```bash
proposed="${existing%%<!-- id:$item_id -->}"
```

`%%` strips a **suffix**. On a ledger line whose anchored marker is not line-final the strip
silently no-ops, and the function then appends a second `<!-- id:XXXX -->`. The written line
carries **two** anchored markers -- and `meeting/md-merge.py` and
`relay/scripts/lib-typed-edges.sh` both REFUSE a multi-marker line (`id:6059`). The item
becomes unaddressable by every anchored-id writer and `typed_edges_own_id_of_line` resolves it
to nothing.

This is silent ledger damage produced by **the one write path in a skill whose entire stated
contract is that it never writes without owner confirmation**. The pre-existing guards do not
catch it: the `marker_count != 1` check counts markers, it does not check the marker's
POSITION, and a line with one non-final marker passes it.

**Reachable, and not a corner case.** Measured on this repo 2026-09-12: **14 open `TODO.md`
items and 22 open `ROADMAP.md` items** carry a non-line-final anchored marker.
`ROADMAP.md`'s `id:32c3` is one of them **and** is an `[INPUT - decision]` item -- precisely
the row class the docket ranks and `draft-answer` is then pointed at. Reproduced against a
fixture carrying that exact shape, with a line-final control alongside that came out at one
marker, so the probe discriminated:

```
id:aaaa (line-final)      markers_in_proposal=1
id:bbbb (prose after it)  markers_in_proposal=2
```

**Fix: REFUSE (new exit 7), do not guess.** Splicing the text "somewhere before the trailing
run" is exactly the guess this repo's sibling tool refuses for the stated `id:6d7e` reason
(`review-box-tick.py`: a physical ledger line is not a semantically complete unit, so there is
no safe insertion point to infer). The refusal names the condition and the remedy; the repair
belongs at the source line. RED spec first, then the fix:
`tests/test_decision_brief_draft_answer_marker_final.sh`, with a `# fails-against-rev:`
declaration verified by `make verify-negatives` (green-now OK, red-there OK, matched the LAST
of 3 fired FAIL lines).

### F2 (LOW, TRACKED -- needs a decision, not a patch) -- `review-box-tick.py`'s mirrored heading grammar is not actually identical to md-merge's

`review-box-tick.py`'s module docstring states: *"This file uses the identical regex for both
the upward search and the section end, so the block we extract is exactly the block md-merge
will replace."* **That claim is false for a titleless heading**, and md-merge is itself
inconsistent there. Measured:

| line | md-merge OPENS a section | md-merge ENDS a section | review-box-tick sees a heading |
|---|---|---|---|
| `## Open` | yes | yes | yes |
| `###` (no title) | **no** | **yes** | **no** |
| `##   ` (spaces) | yes | yes | yes |

md-merge tests its opener against `line.rstrip('\n')` (`md-merge.py:849`) but scans for the
section end against the raw line (`:854`), so a bare `###` closes a section it could not have
opened. `review-box-tick.py` mirrors the OPENER for both of its own purposes, so it would
compose a section extending PAST a bare `###` that md-merge will stop at -- and md-merge
writing the longer content over the shorter span duplicates the tail.

**Not fixed here, and deliberately so:** the fix is to decide which of md-merge's two
disagreeing regexes is canonical and change both files in one commit, which is a contract
decision on a shared writer, not a local patch. **Not live today:** zero titleless headings in
this repo's `REVIEW_ME.md` / `TODO.md` / `ROADMAP.md` (measured). Forward-robustness.

### F3 (LOW, ACCEPTED) -- `docket.sh` coverage footer can emit a doubled count

`emit "COVERAGE...$(grep -c . "$collector_err" || echo 0)"` prints `0` twice when
`collector_err` is non-empty but contains no non-blank line (`grep -c .` returns 1 and prints
`0`, then `|| echo 0` prints another). Guarded by `[[ -s ... ]]`, so it needs a stderr file of
pure whitespace. Cosmetic, affects one footer field, no control flow. **Accepted.**

### F4 (ACCEPTED with rationale) -- `docket.sh draft-answer --answer` is mandatory but never written

`--answer TEXT` is required and appears only in the printed proposal; the marker the tool
writes is `@owner-answered:<date>` plus the `answer-src` citation. That matches the marker
contract in `hard-lanes.md` (date + citation, not free text), and the answer text is what the
owner reads when confirming. **Accepted as designed**, recorded because "mandatory argument
that reaches no output" reads as a defect on a cold read.

### Clean under this pass

`lib-clean-tree.sh` -- the ` M`-only relaxation is correctly narrowed (anything staged,
untracked, added, deleted or conflicted keeps a non-` M` XY pair and stays dirty), the
`git status` exit is captured separately so an error is rc 2 and never folded into "clean",
and `git diff --quiet` failing for ANY reason stays dirty. The `[[ ... ]] && ...` tails are
safe under `set -e` (a non-final member of an AND list). No defect found.

`expires-on-scan.sh` -- the one-pass id-set build is the right answer to the warning-cardinality
problem it documents; `IFS=:` with two `read` targets keeps the colon inside the marker text
intact; the CSV form is refused rather than interpreted; exit precedence (2 config-error over
1 finding) matches the header. No defect found.

`review-box-tick.py` -- the `%%`-class mistake F1 found in `docket.sh` is **not** present here:
this file inserts a whole paragraph at the end of the box rather than appending to the
checkbox line, which is exactly the placement its docstring argues for, and the one-box
invariant is CHECKED (`differing != [rel]`, open-box count decrement) rather than asserted in
prose. `--dry-run` inertness is structural as claimed -- `_run_md_merge` has one call site and
the dry fork hands it a temp copy, so the real path is unreachable from the dry branch.

## 2. Pass 2 -- security

**CLEAN.** No injection, path-traversal, secret-exposure or permission defect found in the
audited surface.

- `docket.sh draft-answer` builds its md-merge payload with
  `python3 -c 'print(json.dumps(sys.argv[1]))'` for the untrusted line text -- correct, not a
  hand-rolled quote. The `$item_id` interpolated raw into the heredoc is constrained upstream:
  the line must already exist under a literal `grep -F -- "<!-- id:$item_id -->"` and pass a
  `<!-- id:[0-9a-f]\{4\} -->` count, so a quote-bearing id cannot reach the JSON. Accepted.
- `expires-on-scan.sh` greps with `-- "$MARKER_RE"` (option-safe) and never evals a marker.
  `EXPIRES_ON_EXTRA_PATHS` is an explicit opt-in; nothing reaches outside the tracked set by
  default, which is the stated design.
- `docket.sh` deliberately CAPTURES the collector's stderr and replays it rather than
  `2>/dev/null` -- the no-silent-swallow rule honoured on a collector whose contract is to
  fail loudly.
- `review-box-tick.py` passes its payload on stdin to `subprocess.run` with a list argv, no
  shell. Temp dirs via `TemporaryDirectory`. `--rationale` is validated (single line, no em/en
  dash, balanced markup) before it can reach a ledger.

## 3. Pass 3 -- design coherence

### F5 (MEDIUM, TRACKED -- owner's call) -- the relay driver has no recurring-audit carve-out, so completing id:401c CLOSES it

`id:401c` states "recurring item -- stays open by design", and `gather-repo-state.sh` plus
`backtest-historical.py` both honour a `<!-- relay:recurring-audit -->` gate so an audit item
with nothing new to audit does not count as dispatchable. **`relay/scripts/roadmap-tick.sh`
contains no recurring handling at all** (`grep -n 'recurring' relay/scripts/roadmap-tick.sh`
-> nothing). Under executor-contract v12 (`id:5b12`) the driver ticks every id a child returns
in `worked_ids`, so a completed audit run flips `- [ ]` to `- [x]` and the recurring audit
leaves the queue until a human re-opens it.

The two halves of the design disagree: the DISPATCH side knows the item is recurring, the
TICK side does not. Historically the reviewer both ticked and re-opened it in one turn, which
is why this never surfaced -- the split-brain only appears once the tick moved to the driver.

**This is surfaced, not decided.** The remedies are opposite in spirit (teach `roadmap-tick.sh`
to skip a `relay:recurring-audit` line, versus have the child omit the id from `worked_ids` and
lose the provenance), and choosing between them is a contract change on the one-writer
inversion. Recorded in `REVIEW_ME.md` for the owner. **Consequence for THIS run:** `401c` is
returned in `worked_ids` (it is what was worked, and the id:de69 contract asks for the truth),
so the box will be ticked at integrate and **needs re-opening**.

### Coherent under this pass

- The `decision-brief` skill's delegation to `gather-human-backlog.sh` with a local ANCHORED
  re-resolution is the right shape rather than a third collector, and its calibration gate
  (10 controls, including two NEGATIVE controls and an exact-value classifier control) is a
  genuine negative control, not an unreached fixture -- the failure mode it exists for is
  documented as having been hit live on 2026-09-11.
- `expires-on-scan.sh`'s refusal to infer expiry from prose, and its explicit statement that
  non-monotonic closure (reopened items) is documented-not-built, are both honest about their
  own limits rather than over-claiming.
- `lib-clean-tree.sh` extracting ONE predicate that two callers had diverged on is the
  correct direction, and it names the one caller that deliberately keeps different rc-2
  handling at its own call site.
- No gate found that can never fire in the audited surface.

## 4. Disposition summary

| # | severity | disposition |
|---|---|---|
| F1 | MEDIUM | **FIXED INLINE** + RED spec + verified negative case |
| F2 | LOW | TRACKED (REVIEW_ME) -- needs a shared-writer contract decision |
| F3 | LOW | ACCEPTED (cosmetic, one footer field) |
| F4 | -- | ACCEPTED as designed, recorded |
| F5 | MEDIUM | TRACKED (REVIEW_ME) -- owner's call; `401c` needs re-opening after this run |

No finding was silently dropped.

Suite: **656 passed / 0 failed / 0 errored / 1 expected-red**, on a full clean run
(load average 1.27 at start, no local-LLM or Lean build in flight).
