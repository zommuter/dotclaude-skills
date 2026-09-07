# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

## Review 2026-09-04 (run `relay-review-relay-20260904-140928-23126` -- the 80-commit window)

Window `relay-ckpt-20260902-1807`..HEAD, **80 commits** (the scoping prompt said 76). **One
declared test tier exists and it RAN**: `make test` (runs `lint` first) -- **578 passed, 0 failed,
4 expected-red** (`6217`, `8679`, `7408`, `64f9`, each an open item whose red test IS its spec).
No `e2e`/`integration` tier is declared (no `.github/workflows`, no other `test*` target), so
nothing was silently skipped. `make verify-negatives` is opt-in and NOT part of `make test`; I ran
it on the 12 files this window touched for its named items. `gaming-scan.sh` raised two
`REMOVED_ASSERT` lines, both in the `id:2eba` stub inversion and both **adjudicated legitimate**:
the owner ratified "stop leaving a stub at all", the test file declares its own contract inversion
in a HISTORY header, and the idempotency guard was REPLACED (archive membership, one definition in
`lib-archive-idempotency.py`) before the stub was removed. Provenance greps are CLEAN: no
`@owner-accepted` / `@owner-answered` / `answer-src:` marker was minted this window (the two
`@owner-answered` lines that left `ROADMAP.md` were DUPLICATE live copies of items already present
verbatim in `ROADMAP.archive.md:4403/4405` with markers intact -- archiving removed the duplicate,
not the marker; counts verified per file at both ends). Contract pointer `v18` == canonical.
`relay-doctor`: no per-repo findings for this repo. `orphan-scan --cross-ledger`: clean.
`roadmap-lint`: 4 pre-existing DEAD-GATE warnings plus one NO-ACCEPTANCE-NO-TWIN (`da55`), no errors.

**Both self-tests were verified BY MUTATION, not by reading** (the prompt's priority 2). Seven
mutations of `tools/ledger-continuations.py`, each exiting 4 and naming the specific assertion:
`cited_by` forced True and forced False; `reads_notes` forced True and forced False; and
`corpus_at` pinned to each of `CORPUS_LEDGER` / `CORPUS_UNION` / `CORPUS_OTHER`. Both halves
discriminate in both directions. One methodology note against myself: my first `corpus_at` mutation
matched the wrong signature and silently no-opped, and all three variants "passed" at exit 0 --
an unreached fixture, not a green. Caught by reading the output rather than the exit code.

## Review 2026-09-07 (chain-end re-ask, run `relay-20260907-100619-27900` -- `relay-ckpt-20260907-1614`..HEAD)

- [ ] **`id:8372` was closed on a spec whose fixture does not have the shape of the incident it represents, so its founding case still reproduces -- I REOPENED it; confirm the call.** The landed fix (`01f233c3`) drops a backticked `@marker` only when the very next word is "marker"/"markers". The RED spec's case-(A3) fixture writes exactly that shape (``a `@manual` marker is prose``), so it goes green. The REAL `ee62` note -- the case named in the item's own title -- writes ``(`[id:6ab8]`, `@manual`, `@impl`, ...)``, a COMMA list, which the discriminator does not match. **Reproduced against the post-fix tree**: shrinking the real `ee62` prose still emits ``-- detail: `docs/ledger-notes/ee62.md` `@manual` <!-- id:ee62 -->``, byte-identical to the corrupted live `TODO.md:34`. This is NOT gaming -- the executor's reasoning is documented and its constraint is real (`test_ledger_shrink_0d7c.sh` case B keeps a list of GENUINE markers joined with "and", so "followed by prose/comma/and" cannot be the rule). The two shapes are not separable by the following token at all; a POSITIONAL rule (only the trailing marker run is the item's own) is the obvious candidate but is a DESIGN CALL I deliberately did not settle. Second, separable residue: the item's note says "30 ledger lines" carry this corruption and "the census is the first task" -- no census was run and no line repaired; `TODO.md:29/393/557` still carry hoisted `routed:XXXX`/`settles:XXXX`/`gated-on:XXXX` placeholders, and re-running the shrinker cannot un-hoist them. Also note `CHANGELOG.md` and the commit subject overclaim the fix as covering the `@manual` family generally; left unedited (derived, date-bucketed) and corrected in `docs/ledger-notes/8372.md` instead. <!-- id:8372 -->
- [ ] **`id:7c82`'s done-check is unsatisfiable as written -- BOTH clauses are false at HEAD, and the item is still open against them.** Clause 1 says `tests/test_todo_conformance_title_chrome_60eb.sh` "has a recorded but unverifiable mutation today" and will report `red-there OK` once `id:60eb` is ticked. `id:60eb` IS ticked (`ROADMAP.md:164`) and `roadmap_item_open('.','60eb')` correctly returns False, but that file carries **zero** `# fails-against` lines and never has -- it was created with none in `40db09d9`, and `git show relay-ckpt-20260902-1807:` confirms it did not exist at the tag. With no machine-readable case it can never report `red-there`; it lands in the deliberate "closed roadmap-spec file with NO declaration is NOT moved into UNDECLARED" branch. Clause 2 says `lint-vacuous-fixtures.py`'s count "drops by the 2 measured false positives"; measured at both ends it is **9 at the tag and 9 at HEAD** (562 -> 582 files scanned, so the 20 new files ARE all declared -- the mechanism works, the metric just never moved). **The mechanism itself is demonstrably live and should not be doubted:** four files whose carve-out expired are now executed rather than shadowed (`1608`, `ff7c`, `5f34`, `b048`). What is needed is a corrected acceptance naming a file that actually carries a declaration, or an explicit "the metric was already at its floor" amendment. I did NOT rewrite the clause: choosing the replacement acceptance is the item's design, not a review fix. <!-- id:7c82 -->
- [ ] **Both head-line ratchet baselines are STALE at HEAD, so `id:0d7c`'s floor currently forgives 4,060 characters of regrowth -- and this is the exact failure `id:2654` was built to make visible.** `make baseline-staleness` reports **8 stale + 1 orphaned** entries for `TODO.md` (3,223 chars of total slack; e.g. `9876` current 245 vs baselined 754, `5ccc` current 423 vs 919) and **1 stale** for `ROADMAP.md` (`931c`, current 157 vs baselined 994, 837 chars). The orphan is `2d17`: baselined 84, but the id is no longer in `TODO.md` because it was ticked and archived this window. Nothing here is broken -- the detector is read-only by the owner's own 2026-09-02 ruling ("mandatory regen plus a read-only staleness detector, self-tightening rejected"), it exits 0, it writes nothing, and its printed remedy is now the two-ledger recipe that will not truncate the shared file. **The point is that the mandatory half did not fire:** `69456bd2` regenerated the SHAPE baseline after `a580`, and then `e567`'s 784-header migration, `64f9`'s 98 title rewrites and `a580`'s anchoring all shrank head lines again with no regen after them. Deciding when a regen commit fires, and whose turn it is, is the judgment I am surfacing rather than taking -- regenerating baselines mid-review would rewrite the floor for 239 entries on the strength of a review turn nobody asked to move it. <!-- id:2654 -->
- [ ] **A CLOSED `[x]` item's deliverable is absent from the tree: `id:d119` claims to have replaced `id:540f`/`id:c179`'s dead `gated-on:b0b1` marker with an owner-hold annotation, and at HEAD both items still carry it and `roadmap-lint` still emits the false DEAD-GATE for both.** `TODO.archive.md:644` is `- [x] [ROUTINE] **Replace id:540f/id:c179's dead gated-on:b0b1 marker with an explicit OWNER-HOLD annotation roadmap-lint understands** (owner-decided 2026-08-13)`, and it names two deliverables: (1) an owner-hold marker grammar and (2) `roadmap-lint` treating it as INTENTIONAL. At HEAD the `gated-on:b0b1` typed edge (written as an HTML comment, de-literalised here so this box stays addressable by `md-merge`, per `id:6059`) still appears 4 times in `ROADMAP.md`, and `roadmap-lint` still reports DEAD-GATE for `540f` and `c179`. **Pre-existing, NOT this window's regression** -- the line was already `- [x]` at `relay-ckpt-20260902-1807`, so no commit reviewed here closed it. Two things make it worth a box rather than a shrug: an owner-hold grammar demonstrably EXISTS (`id:6446` carries `@owner-gated` on its live line), so deliverable (1) may simply never have been applied to these two; and the archived rationale records the owner explicitly REJECTING the obvious alternative (promoting `b0b1` to ROADMAP would convert an owner hold into a technical one and auto-dispatch both items the moment it ticked). Reopening a closed-and-archived item is the owner's call, not mine. <!-- id:d119 -->

## Review 2026-09-02b (run `relay-20260902-164744-26939` -- id:4983 window)

Window `relay-ckpt-20260902-1748`..HEAD (one executor unit, `id:4983`). **One declared tier
exists and it RAN**: `make test` (runs `lint` first) -- **561 passed, 0 failed, 1 expected-red**.
`make verify-negatives` SKIPPED-TIER: opt-in by design, not part of `make test` (seconds per
case over 546 files), and `id:4983`'s spec declares a PROSE-only `# fails-against`, so that
runner structurally cannot verify it -- I ran the negative case by hand instead (below).
`id:4983` is VERIFIED GREEN: `gaming-scan.sh` clean, the spec was authored at handoff
(`44ed2bc6`) and is byte-untouched by the fix commit, and the current spec run against the
pre-fix `tools/ledger-shrink.py` fails at exactly the assertion its header predicts --
`(e) ledger-shrink _LANE_PATTERNS recognises undeclared lane tokens`.

- [ ] **`id:4983`'s detail pointer points at ANOTHER item's note, and it is now a live input rather than dead decoration.** The ROADMAP line reads ``-- detail: `docs/ledger-notes/6546.md` `` followed by its own id marker; `docs/ledger-notes/4983.md` does not exist, and `6546.md` is `id:6546`'s note (strict-shape shrink wave 2 -- the 460-of-840 prose census), which says nothing about lane grammar. Introduced by the handoff commit `109d6f10`, where the two sibling items promoted in the SAME commit got correct pointers (`5f34`->`5f34.md`, `1608`->`1608.md`) -- so this is a slip on one line, not a convention. **Measured blast radius: 2 of 773 pointer-bearing item lines across all five ledgers, and both are this same item (`ROADMAP.md:1698` + its `ROADMAP.archive.md:4584` copy).** Isolated, not systemic. It did no harm HERE only because the ROADMAP block carried its Acceptance/Tests/Done-check inline; a reader or slicer following the pointer gets wave-2-shrink prose instead. Load-bearing now because `id:1608` (closed LAST review) made pointer-following live in `orphan-scan --shipped`, and `id:2ee1` exists precisely so `ledger-slice.sh` follows these pointers into executor prompts -- this is the `id:b015` shape (body relocated, address wrong). **Fix is either creating `docs/ledger-notes/4983.md` or dropping the pointer; I did NEITHER, because the item is closed+archived and rewriting an archived line is the owner's call.** <!-- id:4983 -->
- [ ] **`id:dd44` cites `id:4983` as an instance of "a checker that derives its notion of correctness from the thing it checks cannot fail" -- for the LANDED test that premise does not hold, and the hazard-class item should not be built on it.** `TODO.md:848` (INBOUND `routed:4dc2` from loderite) names three instances, the third being *"your lane check borrowing the shrinker's own regex, id:4983"*. Measured against the file: `tests/test_lane_grammar_ssot.sh` derives its EXPECTED set by scraping `relay/references/hard-lanes.md` (the SSOT doc, `SSOT_DOC` at line 56) and imports `_LANE_PATTERNS` only as the SUBJECT under test (line 145). Expectation and subject are different sources, and the test genuinely fired RED against the pre-fix implementation -- a self-referential check could not have. **The narrower residue IS real and is worth keeping in `dd44`:** the doc SCRAPER (`DASH_RE`, line 90) uses the same permissive `[A-Za-z0-9 _./-]+` bracket shape the fix just removed from the shrinker, so a lane the SSOT declares in an unusual spelling would be invisible to the scraper AND to the consumer, and assertion `(a)` only guards against total vacuity (`len(ssot) < 5`). That is a coverage limit, not a tautology. **Confirm the correction so `dd44` is filed on the accurate claim.** <!-- id:dd44 -->
- [ ] **All 7 open `[ROUTINE]` items are gated or owner-bound, so this repo has ZERO executor-actionable routine work -- I am returning `routine_open: 0`, not 7; confirm the call.** Raw count of open `- [ ] ... [ROUTINE]` in `ROADMAP.md` is 7. `resolve-gates.sh` reports `d4ca`, `540f`, `c179`, `554b`, `8524` all blocked=1; `6446` carries `🚧 @owner-gated` + `gated-on:f391`; `cf2d` is `@owner-verify` and its own body states it *"can only be produced by exercising a real `/meeting`, which the pool cannot manufacture"*. `review.md` defines this field as *"is there executor work left"*, and reporting 7 would re-enqueue an execute unit that finds nothing dispatchable -- **which is exactly `id:59f2`, the defect this repo already tracks, reproduced live.** Reporting the actionable count answers the question the field is for; flagging it because the raw/actionable split is a judgment the supervisor cannot see. <!-- id:59f2 -->

## Review 2026-08-31c (chain-end re-ask, run `relay-20260831-220243-21277` -- id:8123)

Window `relay-ckpt-20260831-1933`..HEAD (the S4/S5/S7/S8/S9 delimiter-migration chain plus the
`id:c442` tracker seam). **One declared tier exists and it RAN**: `make test` (which runs `lint`
first) -- **532 passed, 0 failed, 1 expected-red** (`6217`, an open item whose red test IS the
spec). No `e2e`/`integration` tier is declared anywhere (no `.github/workflows`, no other
`test*` Makefile target), so nothing was skipped. `gaming-scan.sh` raised exactly one line,
`ADDED_SKIP:tests/test_gather_lane_canonical_delimiter.sh:52` -- **adjudicated a false positive**:
line 52 is a prose comment ("...this item is skipped and top_intensive_hard falls through...")
inside the fixture-ordering rationale, not a skip directive. No test file was deleted. **Resurrection
check RUN over all 71 MODIFIED test files** (each `$LAST` version restored into a scratch copy of the
CURRENT tree and executed): 69 pass unchanged; the 2 that fail do so for non-spec reasons, both
verified -- `test_relay_intensive_criteria.sh` pinned the literal U+2014 heading in `conventions.md`
that S7 was REQUIRED to migrate (its replacement is a two-delimiter alternation, i.e. STRICTLY more
general, and still asserts the section exists), and `test_backtest_fidelity.sh`'s original heredoc is
blocked by the lane ratchet, not by the implementation. No `@owner-accepted` / `@owner-answered` /
`answer-src:` marker appears anywhere in the window. Contract pointer `v17` == canonical. `relay-doctor`:
0 per-repo issues (cross-ledger clean, roadmap-lint clean, todo-conformance clean, main checkout clean).

**S9's conservation claim verified INDEPENDENTLY** (not taken from the authoring agent): running
`lane-delimiter-scan.sh --live-only` per ledger gives TODO.md 0, ROADMAP.md 0, REVIEW_ME.md 0,
TODO.archive.md 38, ROADMAP.archive.md 47 -- exactly the 85 archive tags the item says are held for
the `id:2065` ruling. `id:6958` correctly stays OPEN.

- [ ] **`id:1a03` (S5) was closed while its OWN declared done-check still fails, and the residue is a
  LIVE WRITER.** The migration doc's rule is *"Every **emitter** and every **stored** tag is rewritten
  to the hyphen"* (`docs/migration-em-dash-delimiter.md:36`), and S5's stated done-check --
  `git grep -nE '\[(HARD|INPUT|INTENSIVE) <U+2014> ' relay/scripts/*.js *.mjs *.py` returns nothing --
  still returns **48 hits**. Most are comments and are harmless, but two are emitters that WRITE into a
  ledger: `relay/scripts/handback-followup.py:60` (`GATE_TAG`, substituted into a ROADMAP line at
  :114/:116, wired from `relay-loop.js` in 13 places) and `relay/scripts/lane-convert.sh:185-186`.
  The next handback gate or vocabulary conversion therefore re-introduces the legacy delimiter into the
  ledgers S9 just brought to zero, and breaks S10's closing condition. **I did NOT reopen the archived
  seams** -- their reader half is genuinely done and re-opening an archived item is worse than a tracked
  successor -- but that is a judgment call for you to overrule: the residue is filed as `id:32f9` with
  the three emit-pinning tests named. Question: should the archived S4/S5 ticks be amended in place
  instead?
- [ ] **`lane-delimiter-scan.sh` -- S10's own closing-condition detector -- returns exit 1 (its "live
  findings exist" code) when handed a directory, so a mis-pathed invocation is indistinguishable from an
  unfinished migration.** Measured: `--live-only /tmp` exits 1 after a bash `unbound variable` trace,
  while a MISSING path correctly exits 2. Filed as `id:4ce8`; flagging it here because `id:da55` gates
  the irreversible half of the migration on this script's exit code.
## Review 2026-08-26b (chain-end re-ask, run `relay-20260826-162405-7522` — id:8123)

Window `relay-ckpt-20260826-1449`..HEAD = **18 commits, all owner-attended (`Co-Authored-By: Claude
Opus 5`), zero executor units** — the classifier re-asked at chain end because the previous chain
returned `contract_met:false`. **All four declared tiers RUN, none skipped**: `make lint` (0
violations, within baseline), `make test` (**504 passed, 0 failed, 1 expected-red** — `6217`, an
open item whose red test IS the spec), `make gaming-canary` (3/0), `make shard-canary` (6/0).
`gaming-scan.sh` raised exactly one line (`REMOVED_ASSERT:tests/test_git_lock_push_remote_select_4d44.sh`
removed=1 added=0) — **adjudicated benign**: assertion (3) was re-pointed from "absent flag → all
remotes" to "`--all` → all remotes" because the owner deliberately flipped that default, and the
same commit ADDS a new mutual-exclusion assertion (4b) plus a dedicated 7-assertion file
`tests/test_git_lock_push_default_origin.sh`. The four `integrate` test-stub edits are one-token
additions to an arg-parser skip-list inside a **fixture**, not weakened assertions. No
`@owner-accepted` anywhere in the window; no discard-verb (`stash`/`reset --hard`/`checkout --`) in
any commit message; contract pointer `v12` == canonical; `relay-doctor` 1 per-repo issue
(the `id:758a` cross-ledger drift, resolved below).

`id:758a` **verified green and CLOSED** against the RED spec the PREVIOUS review authored
(`tests/test_base_ref_checked_out_branch_758a.sh`) — the fix commit `478d70d2` did not touch that
file, so it is a genuinely independent spec, and its ROADMAP checkbox is now ticked to match the
already-`[x]` TODO twin.

- [ ] **An entire prior review's ledger output never reached `main` — it is stranded on the parked
  orphan branch `relay/orphan/relay-20260826-122101-7415-review-repo-0` (`3d9ca6f3`).** Not just a
  branch left lying around: that commit carries **+43 lines of `REVIEW_ME.md`** (a whole review
  section with 2 open boxes addressed to you — the `391b`/`2c2a` "filed `[ROUTINE]` but opens with a
  question only the owner can answer" lane question, and the `7354` hypothesis correction), **+6
  lines of `ROADMAP.md`** (the full `id:7354` promotion with Acceptance / Tests / Done-check /
  Context), **+56 lines of `RELAY_LOG.md`**, and one test file. None of it is in `HEAD`. You
  independently reached the same two conclusions hours later in this window (`242bebc5` ratifies
  391b option A; `d9b6c3c8` refutes the 7354 hypothesis), so nothing was lost in substance **this
  time** — that is luck, not a mechanism. **Owner's call:** whether stranded-review-output is a
  `[ROUTINE]` fix (auto-integrate or loudly surface an orphan carrying ledger diffs) or belongs to
  the existing `id:dd7d`/`id:7809` reconcile family. The generic parked-orphan warning
  `relay-doctor` already prints does NOT distinguish "stale branch" from "unread questions for the
  owner", which is why this sat unnoticed.

- [ ] **`id:7354` is now INDEPENDENTLY verified — recording it because the shipped test alone would
  not have proven it.** The fix (`01ce9b9c`) and its test (`tests/test_repeat_handback_wiring_7354.sh`)
  were authored in the same commit — the [[feedback-verify-delegated-work-independently]] shape,
  where a green suite proves only self-consistency. The prior review's *separately authored* RED
  spec was one of the stranded files above; this review restored it as
  `tests/test_handback_tracker_all_sites_7354.sh` and ran it **both ways**: it FAILS against
  `01ce9b9c^` naming all 10 unwired sites, and PASSES against `HEAD` (4/4). So the fix is real, and
  the repo now keeps the independent spec. **Confirm you want both files retained** — they overlap
  deliberately (different authors, same contract); say so if you would rather they were merged.

- [ ] **`tests/test_diary_push_remote_narrowed_f66e.sh` lost a check it used to have: a mandatory
  post-prompt step naming a PUBLIC remote now passes every assertion.** The old assertion (2)
  required ≥3 invocations to carry `--remote origin` specifically, with the stated reason
  *"`--remote` alone is not enough: `--remote github` would satisfy (1) while publishing"*. The
  rewrite replaced it with a prose grep (`SKILL.md documents that origin is the default`), and the
  rewritten (1) rejects only `--all`. Meanwhile assertion (3) still REQUIRES the literal string
  `--remote github` to appear in the file. Net effect: if Step 1's bare
  `git-lock-push.sh` (SKILL.md:58) were ever edited to `--remote github`, all four assertions still
  pass. The rewrite is otherwise correct — the default flip genuinely made bare calls private, so
  the old (1) had to invert — this is a narrow hole, not a wrong test. **Suggested fix** (owner's
  call, not applied here since it is the owner's own test): re-add a positive check that the
  post-prompt invocations at SKILL.md:58/125/149 are bare-or-`--remote origin`, i.e. never name a
  non-private remote.

- [ ] **The `id:a73b` publish-by-default fix does not reach the busiest push path — `integrate.sh`
  now passes `--all` explicitly.** The owner directive closed the footgun at the helper's default;
  the diff then added an explicit `--all` at `integrate.sh`'s non-substantive push branch (plus
  `auto-integrate-orphan.sh` and `relay-reconcile.sh --integrate`) to keep those byte-identical. The
  commit message says so plainly, so this is disclosed, not hidden — **and it is not a regression**,
  those paths pushed every remote before too. But it means the relay's own merge-to-main path is
  still publish-to-every-remote-including-public, unattended, which is the exact shape the directive
  was written against. **Owner's call:** intended (integrate is a deliberate publish point), or
  should integrate narrow to origin + an explicit publish step like `git-diary-workflow` does?

## Review 2026-08-26 (chain-end re-ask, run `relay-20260826-122101-7415` — id:8123)

Window `relay-ckpt-20260822-1619`..HEAD. One executor unit (**`id:f2ef`**, flake-log width=1
confirmation run #2) plus ~60 owner/`/relay human` commits. **`id:f2ef` verified GENUINELY green,
not gamed**: it is a pure observational re-run with NO repo diff, and its acceptance artifact was
confirmed independently at the source — `~/.cache/dotclaude-flake/runs.jsonl` carries the row
`ts=20260826T102748Z, mode=suite, width=1, wall_s=419.4, pass=498, fail=0, xred=1`, after the
required `2026-08-21T10:58:33Z` threshold. `gaming-scan.sh` clean (no DELETED_TEST / ADDED_SKIP /
REMOVED_ASSERT); no executor-introduced `@owner-accepted` in the window (the three hits are the
owner's own `chore(046a)` archive MOVES of pre-existing text). Contract pointer `v12` == canonical.
Full `make test` re-run independently: **498 passed, 0 failed, 1 expected-red** — this repo declares
exactly ONE tier (`make test` → `tests/run-tests.sh`; no CI workflows, no e2e/integration target),
so no tier was skipped.

- [ ] **`id:ebd0` was ticked + archived 2026-08-26 as "owner-authorized" but carries NO greppable
  `@owner-accepted:YYYY-MM-DD` marker** — the exact provenance shape review.md §5c fail-closes on,
  and the second instance in this repo (`id:ad7c`, 2026-08-01, is the first). **NOT reopened, and
  deliberately so: I verified the acceptance evidence myself rather than taking the prose.**
  `~/.claude/logs/privacy-gate.log` is 49 lines with **34 naming
  `https://github.com/zommuter/dotclaude-skills.git`** (the public remote), `git config --local
  --get core.hooksPath` exits 1 (the `id:293f` local override that shadowed the global hook is
  genuinely gone), and `--global` resolves to `~/.config/git/hooks`. The close is CORRECT; what is
  missing is the machine-checkable trace of the owner's authorization. **Owner's call:** stamp
  `@owner-accepted:2026-08-26` onto the `id:ebd0` line in `ROADMAP.archive.md`, or say the tick was
  premature. Two unmarked owner-authorized closes in a month is the signal worth acting on — the
  marker only helps if writing it is the habit, not the exception.

- [ ] **`relay-core` shadow parity is 13,994 mismatches across 227,265 rounds and nothing is
  clearing it** (`id:82c4`, surfaced by `relay-doctor` this pass). Bash stays authoritative so
  nothing is BROKEN today, but the stated flip gate is *100% parity + N=5 clean rounds*, and at a
  ~6% mismatch rate that gate cannot be approached by waiting. Report-only, pre-existing, not this
  window's regression — recorded because a standing 6% divergence in a shadow binary is a decision
  the owner should take deliberately (investigate, re-scope the gate, or retire the shadow) rather
  than let accumulate silently. See memory `classify-shadow-parity`: editing
  `classify-verdict.sh`/`gather-repo-state.sh` semantics reddens parity further, and the fix lives
  in a DIFFERENT repo.

- [ ] **Four `roadmap-lint` DEAD-GATE / DEP-PROSE-UNTYPED WARNs are now ~13 days stale and have
  survived three reviews** (`id:d4ca`, `id:e405` — both classes; `id:540f`, `id:c179` — DEAD-GATE).
  All four are open ROADMAP items gated on `id:09e4` / `id:b0b1`, which live ONLY in `TODO.md` and
  were never promoted, so **nothing in `ROADMAP.md` can ever clear them** — they are permanently
  blocked by construction, not by design. Each successive review has correctly recorded them as
  "pre-existing"; that is precisely how a dead gate becomes furniture. Resolution is handoff C2's
  call (promote `09e4`/`b0b1` with a lane, or re-target the markers) and explicitly NOT a reviewer
  guess — surfaced here so the next handoff turn inherits it as a task rather than as background
  noise.

## Review 2026-08-19 (chain-end re-ask, chain `relay-ckpt-20260819-1530` — id:8123)

Window `relay-ckpt-20260819-1507`..HEAD = one executor unit, **`id:5bef`** (author the hardened
`relay-ro`/`relay-svc` systemd `--user` units + shared EnvironmentFile + opt-in uid guard + `make
install-relay-hardened-units`). **Verified honest + green.** `gaming-scan.sh` clean (only a new test
file added, none modified/deleted); no `@owner-accepted` in the window; §2b resurrection/fixture/
faked-clean-tree/refactor-claim all clean; §2d over-reach: diff is faithful to the authoring-ONLY
scope the owner ratified (`/relay human .` 2026-08-18, id:e175 split; Amendment-2 F3 literal-paths
correction) — no superset (never installs, never sudo-invokes, never enables; the `make` target
copies but does not enable; the uid guard is a no-op unless `RELAY_REQUIRE_SERVICE_USER` is set, so
the existing tobias-run units + every hermetic test are unaffected). Full `make test` green: 446
passed, 0 failed, 3 expected-red (item ticked). Contract pointer `v12` == canonical. Honest drift
disclosure (inject.d/inject.done ACL gap) surfaced in the unit comments, not silently fixed — already
tracked as `id:dc80`.

- [ ] **`id:8e7a` (RUN residue, `[INPUT — access]`) is now GATE-CLEARED — ready for the human.** Its
  only gate was `gated-on:5bef` (the authoring half), now DONE. The residue is device work relay never
  auto-runs: `make install-relay-hardened-units` (root-owned install into `/etc/systemd/user/` via
  sudo), deliberate per-user enable, and runtime verification (e0f8-class blocked + cross-uid heartbeat
  round-trip). **Order note (from the item + `id:dc80`): run `id:e8a3` BEFORE the unit migration** —
  afterwards an ACL denial and a `ProtectHome` mount-namespace failure are indistinguishable — and
  close the `heartbeats.done/`+`inject.d/` ACL gap (`id:dc80`) first, or a service-user write there
  fails once the daemons switch uid.
  — ✅ **GATE-CLEARANCE INDEPENDENTLY VERIFIED 2026-08-20 (`/relay human --all`) — the box is
  right. Kept OPEN because it is real human work, not a decision.** Checked because a stored
  memory (`sandbox-relay-os-users-2026-07-08`) asserted the OPPOSITE — that `id:5bef` was
  TODO-only, never promoted, so the pool could not author the units and `id:8e7a` stayed gated.
  **That memory is STALE:** `id:5bef` is `- [x] [ROUTINE]` at `ROADMAP.md:1588` ("Author the
  systemd units + hardening for the two relay service users"), also archived. The authoring half
  is done and the gate IS cleared. Memory corrected in the same pass rather than left to mislead
  the next session.
  **This stays on the "you run these" list** — device work the relay never auto-runs: root-owned
  install into `/etc/systemd/user/` via sudo, deliberate per-user enable, and runtime verification
  (e0f8-class blocked + cross-uid heartbeat round-trip). **The ORDER is the load-bearing part, and
  it is not arbitrary:** run `id:e8a3` FIRST — after the unit migration an ACL denial and a
  `ProtectHome` mount-namespace failure become indistinguishable, so diagnosing anything gets much
  harder — and close the `heartbeats.done/` + `inject.d/` ACL gap (`id:dc80`) before switching
  uids, or a service-user write there fails immediately. Doing these out of order is recoverable
  but costs a debugging session for no reason.

## Review 2026-08-13d (chain-end re-ask, chain `relay-ckpt-20260813-2045`..`-2119` — id:f657)

Chain-end re-ask: HEAD == the `-2119` checkpoint, so the reviewed window is the just-ended
execute chain (the reviewer C2 checkpoint `-2045` → the `id:f657` execute at `-2119`).
`gaming-scan.sh` clean; `orphan-scan --cross-ledger` clean; contract pointer v12 == canonical v12.

**`id:f657` VERIFIED green (not gamed, not over-reach).** Doc-only: `ARCHITECTURE.md` §11
records the pool ∥ meeting same-repo concurrent-safety convention, citing the three built
mechanisms (distinct claim keys `id:0ee1`, ledger-only writes not lease-gated `id:c144`,
flock+atomic commit). The RED spec `test_architecture_pool_meeting_convention_f657.sh` is a
legitimate DOC-content contract (the `lint-source-grep-assertions.py` carve-out), and it went
RED→GREEN by genuine content, not a weakened assertion. §2d over-reach: NONE — the subsection
correctly BOUNDS the convention (does NOT extend to two executors; explicitly notes no
dispatch-time pool→meeting skip exists, that skip being the gated `id:9000`/`id:5a39` proposal),
matching the ratified topology facts; no mutable checkbox state restated (CLAUDE.md
ARCHITECTURE-carries-conventions-not-status). Already ticked + archived (`ROADMAP.archive.md`).

**`id:292b` CLOSED this pass (was open-but-green).** Its implementation (`tests/lint-vacuous-fixtures.py`,
commit `55900b6`) IS merged into HEAD and `tests/test_vacuous_fixture_lint_292b.sh` passes 4/4
(headerless flag / declared-negative pass / roadmap-spec exempt / `--strict` non-zero) — a genuine
behavioural lint, not gamed. It stayed unticked only because its closing tick landed on an
unmerged parked orphan branch (`relay/orphan/relay-20260813-180303-4214-review-repo-0`, commits
`c3856b6`/`f86bcba`) that never integrated. Ticked here in both `ROADMAP.md` and its `TODO.md`
twin (single-id-two-views).

`routine_open` = **1** — after closing `id:292b`, the only ungated, non-container, RED-spec-backed
open `[ROUTINE]` is `id:d119` (`roadmap-lint` OWNER-HOLD marker suppresses false DEAD-GATE;
`test_roadmap_lint_owner_hold_d119.sh` confirmed still RED). The other 4 open `[ROUTINE]` items
(`d4ca`/`540f`/`c179`/`554b`) stay 🚧 GATED (owner/technical gates), and `id:f91a` is an
`@container`. Nothing reopened.

Advisory (report-only, pre-existing, owner/design's call — not executor work):
- `relay-doctor`: 12 cross-repo dead-letters routed to this repo not yet ingested (relay-core
  parity items `9178`/`f968`/`ca39`/`8b2a` et al.) + the 416-mismatch relay-core shadow still
  short of the flip gate — inbox-reconcile backlog, surfaced not acted.
- `orphan-scan --shipped`: `id:ebbe` now GATE-READY (all gates `[x]`); `id:6c6e` GATE-STALE 24d
  (carried from 13b); several UNMARKED-GATE items in `TODO.md` — typed-edge back-fill for a
  strong/human turn, not this review.
- `roadmap-lint` WARNs (DEAD-GATE/DEP-PROSE-UNTYPED on the gated `d4ca`/`e405`/`540f`/`c179`
  cluster; DECOMPOSED-CONTAINER `id:ae08`; NO-ACCEPTANCE-NO-TWIN `id:1b13`) — all pre-existing
  gated/[INPUT — decision] items previously surfaced.

## Review 2026-08-11c (chain-end re-ask, window `relay-ckpt-20260811-1838`..HEAD — two executor units, id:8123)

Chain of TWO execute units verified GENUINELY GREEN and non-gamed (window base is the last reviewer checkpoint `ecd3f48`/1838; the chain's own executor checkpoints 1923/1934 are the units under review):

- **id:34b7** (DISSOLUTION half of id:f91a — the PARENT creates + provisions the child's worktree before dispatch): `relay-loop.js` gains a `provisionWorktree()` mechanical hop (MECH_MODEL/`relay-mech` fence) dispatched from `runUnit()` BEFORE the child `agent()` call, reusing `worktreePathFor()`/`branchFor()`; a provisioning failure hands back instead of dispatching a child into nothing. New `relay/scripts/provision-worktree.sh` (single-target `git worktree add` + best-effort `node_modules`/`.venv` symlinks). Both prompt sites (`unitPrompt`/`resumePrompt`) drop `main checkout: ${unit.path}` and the "Create your worktree first" instruction (part 3, correctly gated behind parts 1+2). Script registered in `mechanical-proxy.py` `ALLOWED_RELAY_SCRIPTS` (id:5bbb completeness) and the Makefile `relay_FILES`/`relay_EXEC`/`relay_ALLOW` manifest. RED spec `tests/test_parent_creates_worktree_34b7.sh` 8/8 green; honest source-shape coverage caveat stated in-file (relay-loop.js has no hermetic runner).
- **id:37f2** (seam 1 of id:c7dc — `discover-repo.sh` carries `verdict`/`priority_rank` on the no-unit paths): blocked/AMBIGUOUS surfaced + idle skipped entries now carry `{verdict, priority_rank, reason}`; the substitutive repo-level-block path emits an honest `verdict:""` (reconcile never classifies) rather than omitting the field. Test additions to `tests/test_discover_repo.sh` are purely ADDITIVE new assertions (cases 2/3/4 field checks + a source-shape check for the dormant AMBIGUOUS branch), no existing assertion weakened.

Verification: `gaming-scan.sh` clean (no deleted test / added skip / removed assert); no test weakened or rewritten (§2b.1 — the id:37f2 test diff strengthens, the id:34b7 test is new); `refactor: none needed` self-reports present for BOTH units and consistent with additive/new-code diffs; no executor-introduced `@owner-accepted` in the window; §2d over-reach — both diffs match their cited sources (id:34b7 stays DISSOLUTION-only, does not touch the owner-barred enforcement child id:d464; id:37f2 additive fields per id:c7dc D-seams). Full `make test`: **381 passed, 0 failed, 3 expected-red** (unrelated open items). Cross-ledger drift reconciled: `id:34b7` was `[x]` in `ROADMAP.archive.md` but still `[ ]` in `TODO.md` line 436 — ticked (single-id-two-views D2; `orphan-scan --cross-ledger` misses it because the item is archived out of `ROADMAP.md`). `id:f91a` correctly stays OPEN — its close condition (34b7 done AND owner rules on d464) is unmet.

Re-derivation: after this chain, seam 2 **`id:e87d`** is now UNGATED (its blocker id:37f2 landed) and executor-ready → `routine_open` reflects it. relay-doctor + roadmap-lint findings (DEAD-GATE 2b49/540f/c179, parked orphans, relay-core shadow, f91a/34b7 promotion) are ALL already boxed above — no duplicate boxes added. NOTE for the human: relay-doctor reports **4 inbox dead-letters targeting this repo** (routed:4728/b7d8/c2b9/a808, all from today's 2026-08-11 escapement-scoping session — onboard escapement into relay.toml, re-scope cb1c, two Fable-protocol discussion items, and the --fabled 7-forced-findings evidence for id:8df5). They live durably in the git-tracked inbox and are surfaced by `/relay human`; route them via inbox-reconcile (`scan-routed.sh --apply`) or file into TODO — not re-recorded here to avoid a third parallel copy.

## Resolutions — `/relay human .` 2026-08-13 (apex, claude-opus-5)

Tier-(a) auto-answers. Each is a re-checkable CLAIM the next `/relay review`
re-derives from the evidence named here; reopen any whose evidence does not hold.

- **`edbc462` salvage / id:3d78** — box stated its own resolution ("no action needed");
  successor `id:3d78` verified filed in `TODO.md` (2 refs). Nothing outstanding.
- **Inbox dead-letter `routed:7b8f` / id:8df5 "absent from TODO.md/ROADMAP.md"** — premise
  is FALSE as of today: `grep -c id:8df5` = **2 in `ROADMAP.md`, 11 in `TODO.md`**. The item
  IS filed; the box's "never filed" claim is stale. Re-check: `grep -c 'id:8df5' ROADMAP.md TODO.md`.
- **id:cc90 / id:923b wiring before ticking** — the box's own prescribed check RUN and PASSED.
  Both are edits *inside* `relay-loop.js` (not standalone scripts), so the
  `[[relay-builtgreen-but-unreferenced]]` class does not apply, and both are control-flow
  reachable: `chainDepth` gates the re-enqueue at `relay-loop.js:3107`, increments at `:3108`,
  threads into the enqueued unit at `:3112`; `unitKey` (`:2147`) drives `worktreePathFor`/
  `branchFor` (`:2155`/`:2156`) and the inFlight push/filter (`:3043`/`:3078`). Both tests green
  in isolation. Both ids already `- [x]` in `ROADMAP.archive.md` (3534/3719, 3743) with **no open
  TODO twin** (TODO.md:66/79 are parent containers that merely cite them) — so no tick was owed.
  NOTE for the next review: `relay-loop.js:3123` records that cc90's *originally ratified*
  `chainDepth === K` forced-review trigger was REFUTED and REPLACED by the chain-end re-ask
  (id:8123). The id is closed on the replacement mechanism, not the original design.
- **`test_git_lock_push_slash_branch.sh` flake** — re-ran in isolation: **exit 0**. Known,
  self-documented class (SSH-agent state under the parallel suite; id:05e8 lineage). Closed as
  informational. **Residue, deliberately NOT minted as work**: a durable de-flake (hermetic
  ssh-agent isolation) is still unfiled — surfaced to the owner rather than self-assigned.
- **id:93ac gate — "lift it or keep d4ca/e405 blocked?"** — the question is **MOOT**: `id:93ac`
  is `- [x]` DONE at `ROADMAP.archive.md:3951`, its fix independently verified in the Run 72
  audit (`ROADMAP.md:1124` — "excises the stdin payload span before command extraction so a
  payload can't supply the command"), and the `d4ca`/`e405` gates were **re-targeted 2026-08-13**
  off `33b2`/`93ac` onto `id:09e4` + `id:b0b1`. There is no 93ac gate left to lift. Both items
  remain blocked, on different and still-live gates.
- **Run 71's "disjoint by construction" overclaim** — the correction was made inline in the
  id:93ac item (now archived) rather than by rewriting the historical audit note, which is the
  right disposition; the corrected reasoning is recorded at `ROADMAP.md:1124`. Action complete.

### Owner decisions — `/relay human .` 2026-08-13 (tier-(b), captured via AskUserQuestion)

- **id:ecce part 4 — empty audit window ⇒ NON-ZERO EXIT, abort the unit** (owner). A vacuous
  review becomes a handback the pool records and stops re-dispatching, rather than a surfaced
  no-op nobody reads — the id:ecce failure mode itself (an unread surface let a 42-commit
  unreviewed window read as 0). Spec case owed: `tests/test_integrate_label_not_strong_ecce.sh`
  covers parts 1–3 only; part 4 is now DECIDED and needs an assertion. Filed as `id:f544`.
- **Parked orphans — NO ACTION TAKEN; the boxes were STALE.** Owner chose "integrate the review
  branch, discard the two execute branches", but on inspection all three refs were **already
  gone** (`relay-reconcile.sh` and `--all`: 0 parked orphans, here and fleet-wide); `27c7fd7` and
  `6c20004` survive only as unreferenced dangling objects, neither an ancestor of HEAD. A
  **2026-08-12 `/relay reconcile --all` sweep had already disposed of them** and recorded its
  analysis in `TODO.md:56` (`id:4174`): 5 of 6 parked orphans provably redundant, and this exact
  review branch would have "re-added two REVIEW_ME boxes whose items are now `[x]` on main
  (`id:1f8e`, `routed:c555`) plus a stale ROADMAP review note". Verified independently: `id:1f8e`
  is `[x]` in both archives, `routed:c555` has 0 inbox hits, and the `## Review 2026-07-31`
  section is already present here. **Integrating would have been a regression** — the box's "looks
  integrable" assessment had rotted. Disposal stands as done.
- **relay-core shadow — LIVE track, investigate the 350 mismatches** (owner). A stable nonzero
  mismatch rate over 106,536 rounds is treated as evidence of a real port defect, not instrument
  noise; bash stays authoritative meanwhile. Characterisation item filed as `id:04d6`.
- **id:ef9e wiring — BOTH, and prioritize the framework** (owner). Wire
  `lint-embedded-literals.mjs` into the relay integrate step NOW (available today, no dependency),
  AND into pre-commit via the shared git-hook framework once it exists — with `id:7a05`/`id:077d`
  explicitly PRIORITIZED so the authoring-time catch is not deferred indefinitely. Integrate-step
  wiring filed as `id:7be4`; the pre-commit half as `id:7e2a` (gated on the framework).
- **id:540f / id:c179 — EXPLICIT OWNER-HOLD ANNOTATION** (owner), not promotion of `id:b0b1`.
  Promoting b0b1 would convert an owner hold into a technical one: once b0b1 ticked, both items
  would auto-unblock into dispatch without the owner saying so — exactly what the 2026-07-31 owner
  gate exists to prevent. The annotation must be one `roadmap-lint` understands as INTENTIONAL, so
  it stops reporting a false DEAD-GATE. Filed as `id:d119` (relates `id:8de9`, the lint
  resolution-span defect).
- **id:f91a — BOTH prior calls CONFIRMED CORRECT** (owner). `@container` is right (the item
  carries no fix of its own, only a problem statement plus two candidate directions; promoting it
  alongside its own child would double-count, per handoff.md's id:8504 rule), and the 2026-08-01
  handoff DOES supersede the 2026-07-30 hold **for `id:34b7` only**. `id:d464` stays
  DISCUSSION-ONLY / DO NOT BUILD, unamended. No revert needed.
- **Inbox — file all three targeted items** (owner): `routed:790b`, `routed:ed25`, `routed:1c50`.
  Filing records them as open work; it does not decide or schedule them.
- **9 INBOUND items — promote only the unambiguous ones** (owner): those whose lane is already
  tagged and whose scope is self-contained; anything touching in-flight dispatch semantics stays
  for the owner. Filed as `id:eb16`.

- [ ] **id:5eeb — a context handback firing BEFORE the first edit commits NOTHING, and `route="none"` writes nothing durable: a LIVELOCK.** -- detail: `docs/ledger-notes/5eeb.md` <!-- id:5eeb -->
- [ ] **id:5eeb — spec hole: 2 of 5 sub-assertions in `tests/test_context_budget_handback_5eeb.sh` block (8) are VACUOUS** -- detail: `docs/ledger-notes/5eeb.md` <!-- id:5eeb -->
- [ ] **id:1ccd -- `roadmap-lint` NO-ACCEPTANCE-NO-TWIN (id:213a) fires on 7 workable by-reference items.** -- detail: `docs/ledger-notes/1ccd.md` <!-- id:1ccd -->
- [ ] **id:6e8d -- `meeting/SKILL.md` falls BETWEEN seams S6 and S7 of the em-dash migration.** -- detail: `docs/ledger-notes/6e8d.md` [HARD - pool] [INPUT - decision] [INPUT - meeting] <!-- id:6e8d -->
- [ ] **id:62b4 -- the INSTALLED lane-ratchet rule block in `~/.claude/CLAUDE.md` is now STALE against `hooks/lane-vocab.claude-rule.md`.** -- detail: `docs/ledger-notes/62b4.md` <!-- id:62b4 -->
- [ ] **id:ad2a -- the em-dash migration's recorded emit-side done-check is PROSE-BLIND and can never return 0, so a future reader will re-file `id:32f9` off it.** -- detail: `docs/ledger-notes/ad2a.md` <!-- id:ad2a -->
- [ ] **id:9e86 -- `id:4ce8`'s fix added a DEAD branch, and its `refactor: none needed` self-report glossed it.** -- detail: `docs/ledger-notes/9e86.md` <!-- id:9e86 -->
- [ ] **id:d8b3 -- CONFIRM THE STORE: the ZERO-COMMIT accumulator should live in `relay-state-write.sh event-append`, not `relay.toml`.** -- detail: `docs/ledger-notes/d8b3.md` <!-- id:d8b3 -->
- [ ] **id:9fa2 -- LEFT IN TODO, deliberately NOT promoted: the mirror rule's mechanism is a genuine fork, not an implementation detail.** -- detail: `docs/ledger-notes/9fa2.md` [ROUTINE] <!-- id:9fa2 -->
- [ ] **id:8302 was TICKED AND ARCHIVED on a PARTIALLY-MET acceptance -- I did NOT reopen it; confirm that call.** -- detail: `docs/ledger-notes/59c5.md` <!-- id:59c5 -->
- [ ] **id:8524 -- its only typed gate closed this review, so it became dispatchable with a done-check it cannot reach; I typed `gated-on:2d17` onto it, confirm the call.** `8524` promotes `shape-prose` from WARN to ERROR and its own **Acceptance** says *"Blocked until the remaining prose-carrying items are shrunk or exempted: 231 on `TODO.md`, 51 on `ROADMAP.md`"* -- a prerequisite carried only as PROSE, with `gated-on:1608` as the sole typed edge. Ticking `1608` this review therefore left `8524` as one of just two actionable `[ROUTINE]` items, while its stated done-check (`relay/scripts/todo-conformance.sh --strict TODO.md` exits 0) is unreachable against ~114 standing findings: an executor picking it up burns a unit on a gate it cannot clear. `id:2d17` (promoted to ROADMAP this window, `[HARD]`, owner-directed) is the identity-set baseline whose own text says the WARN-to-ERROR promotion *"does not fix it"*, so that edge is the honest one and I typed it. The OTHER named prerequisite, the wave-2 shrink `id:6546`, lives ONLY in `TODO.md`; typing it would have minted a DEAD-GATE warning (`id:49e0`) instead of a real edge, so it is recorded here rather than faked into the ledger. Owner's call whether `6546` should be promoted so that half can be typed too. <!-- id:8524 -->
- [ ] **`todo-conformance.sh --fix` REFUSES the repo's one `missing-id` finding and says so on STDERR only, so the hand-migration it asks for is tracked nowhere.** `TODO.md` line 907 (the `[INPUT - decision]` item on whitelisting the destructive-git ops in a provably-disposable worktree) is the single `missing-id` line; `--fix` correctly declines to mint, printing *"line 907 has a non-canonical inline id -- NOT auto-minted (migrate to an id comment by hand to avoid a duplicate id)"*. That is the same-or-sibling-id ambiguity review.md 4b tells a reviewer NOT to guess: the body cites `id:3a09`, `id:458c`, `id:9320`, `id:5937` and `id:2840` as related work, and adopting any of them as this line's own key would collide. It needs a human to mint or adopt one. Two things to note while it stands: the item is invisible to every id-keyed collector (orphan-scan, unpromoted-scan, the typed-edge engine), and the refusal reaching only stderr means a `--fix` run that resolves nothing still exits 0 and reads as a clean pass. <!-- id:a9c5 -->
- [ ] **id:3bd4 -- the spec invents an opt-in flag `--allow-noop`, and it takes a position on what counts as a no-op. Confirm both.** The item's FIX text says a deliberate no-op "can opt in via an explicit flag" without naming it; case (G) of `tests/test_md_merge_silent_noop_3bd4.sh` pins the spelling `--allow-noop`. It exists because an idempotent caller re-running its own delta would otherwise hit the new hard failure. The second, larger call: the spec treats a `regex_sub` whose PATTERN DOES NOT MATCH as the no-op, and deliberately says nothing about a pattern that matches but whose replacement is byte-identical (`sub('a','a')`). Both are "nothing changed", but only the first is unambiguously a caller mistake; failing the second would break a genuinely idempotent normalisation. If you want both to fail, the spec needs a case for it. <!-- id:a03e -->
- [ ] **id:4f0f -- the JSON key `scope` and the value `item` are the SPEC's choice, not yours. Confirm the surface before an executor builds it.** The TODO item ratified the BEHAVIOUR (an item-scoped mode over the head line plus its continuation lines) and named no spelling. `tests/test_md_merge_item_scope_4f0f.sh` pins `{"id":"XXXX","scope":"item","regex_sub":{...}}` because it composes with the existing per-op shape rather than adding a parallel op family, and because `id:5d7e` already folds several ops per id. Two consequences worth ratifying with it: the spec makes an unsupported `scope`+op combination and an unrecognised `scope` value LOUD refusals rather than a silent fall-back to line scope (cases B and C), which is a deliberate widening of the failure surface; and item-scoped `append` and item-scoped whole-block replacement are deliberately NOT specced, because each needs its own answer to where the text lands and what happens to the id marker. The block boundary itself is NOT a judgment call -- it reuses the definition already in `tools/ledger-continuations.py`. **Input aus id:f833 (2026-09-07, kienzler-solutions id:9f11 verdreifacht):** ein whole-block-replace (`{"id","block"}`) wurde prototypisiert und WIEDER ZURUECKGEZOGEN, weil er eine ZWEITE Continuation-Definition einfuehrte -- genau die id:4983-Klasse, die dieser Spec vermeiden will. Zurueck blieb nur ein enger Guard: ein mehrzeiliges `line` wird refused, WENN das Zielitem bereits wrappt. Zwei Befunde fuer die Ratifizierung: (a) der Guard darf NICHT pauschal sein -- `relay/scripts/handback-followup.py:172` sendet fuer JEDEN Seam legitim ein mehrzeiliges `line` (Kopfzeile + eingerueckte Acceptance/Done-check/Context, Owner-Anforderung 2026-07-26), und ein pauschaler Guard hat prompt `test_handback_followup.sh` und `test_seam_emitter_acceptance_44a1.sh` rot gemacht; die Grenze verlaeuft also zwischen 'Ziel wrappt schon' (Duplikation) und 'neu oder einzeilig' (korrekt, in Produktion). (b) Damit hat `scope:item` fuer den REPLACE-Fall bereits einen Konsumenten und eine Abgrenzung, die der Spec bisher offenlaesst. <!-- id:b5c1 -->

## Review 2026-09-05 (chain-end re-ask, run `relay-20260905-083048-18379` -- id:8123)

**The diff window is EMPTY and that is the honest headline.** `LAST=relay-ckpt-20260905-0852`
resolves to `3fd942ba`, which IS `HEAD`: `git rev-list --count $LAST..HEAD` = **0**. The chain
that just ended was this morning's handoff (C2/C3/C4, promoting `id:3bd4` + `id:4f0f` with two
verified-red specs), and it checkpointed itself. So there is **no executor work to audit in this
window** -- `gaming-scan.sh` returned empty, and it returned empty *by construction*, not because
an executor was found clean. `verified_green` is deliberately `[]`: nothing went red-to-green here,
and crediting the 579 passing tests as "verified green this review" would be exactly the
subset-green wording §3(c) bans. The §2b judgment-residue checks, the §2b.7/§2b.9 provenance greps
and the §2d over-reach check all have an empty input set; I ran the greps anyway and they are
clean, but a clean grep over zero commits is not evidence of anything and is recorded as such.

**Test tiers, enumerated then run-or-skipped (§3).** Declared tiers from `Makefile` (there is no
`.github/workflows`, so CI declares none): `make test` (runs `lint` first) -- **RAN, 579 passed /
0 failed / 12 expected-red**, each expected-red an open roadmap item whose red test IS its spec.
`make baseline-staleness` -- **RAN**, both ratchets current (230 baselined TODO entries, 37 ROADMAP,
none below floor). **SKIPPED-TIER: `verify-negatives`** -- opt-in by design, seconds per case, and
with a zero-commit window `--changed` selects nothing; no item's done-check depends on it here.
**SKIPPED-TIER: `gaming-canary` / `shard-canary`** -- both spawn real agents and cost tokens
(`Makefile`: "on-demand, NOT in `make test`"); neither gates any item closed this window. No item
was closed on the strength of a skipped tier, because no item was closed at all.

- [ ] **VERIFIED DEFECT -- the `id:0d7c` head-length and `id:2d17` shape-prose ratchets are INERT
  for every caller that uses the INSTALL path, which is the path `review.md` §4b and `relay-doctor`
  both prescribe.** Measured, not inferred, on this worktree's own `TODO.md`:
  `bash relay/scripts/todo-conformance.sh TODO.md` emits **1** `head-length-regrowth|shape-prose`
  line; `bash ~/.claude/skills/relay/scripts/todo-conformance.sh TODO.md` emits **216**, and prints
  `head-length ratchet INERT -- no baseline at .../skills/relay/../head-length-baseline.txt`
  plus the same for the shape baseline. Cause: the script resolves its baselines as
  `$(dirname $0)/../<name>`, the two files live at `relay/head-length-baseline.txt` and
  `relay/shape-prose-baseline.txt` in the repo, and the `relay_FILES` manifest declares
  `scripts/*` + `references/*` only -- so `make install` symlinks the script and never the
  baselines. **Direction matters and I had it backwards at first: this fails OPEN (216 ungrandfathered
  findings), not silent.** The loss is not a missed defect, it is the RATCHET SEMANTIC itself -- with
  no baseline there is no "regrowth vs grandfathered" distinction, so the 1 genuine regrowth is
  indistinguishable from 215 forgiven ones, and `id:0d7c`'s monotonic-shrink guarantee is
  unavailable to precisely the callers built to enforce it. Two aggravations: `relay-doctor.sh:298`
  invokes it as `2>>"$LOG"`, so the two INERT warnings never reach the reviewer who is reading its
  output; and `relay-doctor`'s own `install-drift` check walks `scripts/*`+`references/*`, so it
  **structurally cannot see** a manifest gap in a non-script file. Fix is one line of manifest plus
  widening install-drift's walk. **AMENDED 2026-09-05 -- THAT LAST SENTENCE IS WRONG, and
  implementing it as written SHIPS A REGRESSION.** The defect has THREE dimensions, of which
  only (a), above, was originally filed; (b) and (c) are verified on this tree. **(b) the
  baseline KEY has no repo dimension** -- rows are `<ledger BASENAME>TAB<id>TAB<len>` and the
  lookup is `basename/$id` (`:769`, `:725`, `:522`), so every repo's `TODO.md`/`ROADMAP.md`
  satisfies the same key. Token `55c7` is baselined here as `ROADMAP.md 55c7 642` and exists
  unrelated in loderite, whose `ROADMAP.md` line (968 chars) would read as REGROWTH against
  our ceiling while its 208-char `TODO.md` twin would be silently GRANDFATHERED -- both
  directions, one entry, no warning; and `tracker/homonym-allowlist.txt:129` already lists
  `55c7` among 187 adjudicated cross-repo homonyms. **(c) the length metric is
  locale-dependent** -- every site measures with bash `${#r}`, which counts CHARACTERS under
  UTF-8 and BYTES under `LC_ALL=C` (measured 968 vs 986 on one real line, 365 vs 367 on
  `TODO.md:983`), and the baseline records no locale, so a line within ~18 chars of its
  ceiling flips class on the invoking environment alone. **ORDERING IS ACCEPTANCE:** shipping
  the manifest line alone converts an ANNOUNCED INERT into an UNANNOUNCED WRONG on 46 repos,
  so the manifest change must NOT land first. Corrected scope, evidence and done-checks:
  `docs/ledger-notes/4839.md`; filed as a `[ROUTINE]` unit under the same id. <!-- id:4839 -->

- [ ] **`todo-conformance.sh --fix` can never fix `TODO.md:907`, and the reason generalizes to most
  of this ledger.** The one `missing-id` finding is a real one -- the line carries no
  `<!-- id:XXXX -->` of its own -- but `--fix` refuses it with
  `line 907 has a non-canonical inline id, NOT auto-minted`. That duplicate-id safety guard is
  `grep -qP '\bid:[0-9a-f]{4}\b'` over the WHOLE line, and line 907 cites `id:458c`, `id:3a09`,
  `id:9320` and `id:5937` in its PROSE. So a prose citation of another item's token is
  indistinguishable, to the guard, from the item wearing a non-canonical id of its own. Fail-closed
  is the right direction and the refusal is LOUD, so this is not the silent-no-op class -- but in a
  ledger where cross-citation is the norm, "auto-fixable via `--fix`" (the wording `relay-doctor`
  prints) is a promise the tool cannot keep, and the item stays permanently non-conforming. The
  narrow fix is to test for an id OUTSIDE backticks and outside a `docs/ledger-notes/` pointer.
  Owner's call whether that is worth the parsing. <!-- id:c773 -->

- [ ] **`relay/scripts/lib-archive-idempotency.py` is declared in `relay_FILES` but is not present
  in the install tree** (`relay-doctor` install-drift, id:1102, found this itself; recorded here so
  it is not lost with the run log). Same family as the baseline gap above -- worth fixing in one
  pass. <!-- id:c47f -->

- [ ] **`REVIEW_ME.md` carries 31 open boxes against its own header's "Max ~10 open boxes; the
  reviewer prunes resolved ones each review turn", and I could prune NONE of them: the file has
  **zero** `- [x]` boxes.** Under this repo's ratified convention (CLAUDE.md: REVIEW_ME is out of
  the ledger line-shrink and is compacted by ARCHIVING resolved boxes), archiving is the only
  sanctioned lever and it has nothing to grip -- boxes are accumulating open across eight review
  sections back to 2026-08-11 because nobody is resolving them, not because nobody is archiving
  them. That is a queue-throughput problem, not a formatting one, and it is the owner's to act on.
  <!-- id:62fd -->

- [ ] **A landed item's verification self-report is contradicted by this repo's own verifier: `id:9628`'s ledger line claims its spec "was verified to discriminate all three variants", and `make verify-negatives` reports that spec VACUOUS.** The FIX is sound -- I re-derived it by hand: with the pre-fix pattern restored, `split_head` keeps `@owner-accepted` and drops `:2026-09-01`, so assertion (A) does fire. What did not work was the DECLARATION. It was authored as a `python3 - <<'EOF'` heredoc spread over 8 comment lines, and `verify-negative-cases.py` takes only the remainder of the MATCHED LINE as the command, so what actually ran was the bare fragment `python3 - <<'EOF'`: bash warns about the unterminated heredoc, python reads an empty stdin, and it exits 0. A silent no-op that the runner's own `rc != 0` check cannot see. The test then ran against the UNMUTATED tree and passed. **Two things for the human, because they point in opposite directions.** (1) The mechanical layer WORKED -- `verify-negatives` is opt-in and not part of `make test`, and running it is what caught this; the handoff's `make test` green was never going to. (2) Its verdict named the wrong culprit: it says the TEST demonstrates no killing power, when the test was fine and the DECLARATION was unrunnable. A reader trusting that message rewrites a sound fixture. Repaired here (one-line `python3 -c`, target substring unique, `assert n != s` so a missed match exits nonzero; re-verified `red-there OK`), corpus swept for a second instance (none), and the generator gap filed + promoted as `id:b890` with a red spec. Left open for the human because the judgment call is upstream of the code: `# fails-against-mutation:` is documented in `CLAUDE.md` as machine-readable, and nothing in that documentation says it must be ONE LINE. <!-- relates:a73c --> <!-- id:b890 -->

- [ ] **The `verify-negatives` tier is RED with 6 pre-existing violations, and because it is deliberately NOT part of `make test` nothing has been forcing them.** Full-corpus run this review (154 files executed, ~35 min at load 20-24): `test_ledger_shrink_0d7c.sh`, `test_orphan_scan_gate_ready_container_5b1f.sh` and `test_privacy_pattern_lint.sh` are WRONG REASON via the non-exiting-accumulator rule (they go red, but not at the assertion they declare -- the declaration must match the LAST fired FAIL line); `test_ledger_shrink_lane_promotion_6546.sh` is WRONG REASON at a different assertion; `test_roadmap_lint_follows_pointer_e95b.sh` is VACUOUS against `rev: HEAD~1`; and `test_personas_extend_preserves_text_81b8.sh` is a RUNNER ERROR, not a test defect at all -- `OSError: [Errno 39] Directory not empty: '/tmp/negcase-.../tree/.git/objects'` during its GREEN-NOW phase, i.e. the harness's own scratch teardown racing itself. **None of the six was touched in this review's window** (`git log --name-only` over `relay-ckpt-20260905-0911..HEAD` returns nothing for any of them), so all six pre-date it; the count went 7 -> 6 here because `id:9628` was repaired. Two things for the owner, and they are different decisions. (1) The RUNNER ERROR belongs with `id:b890` -- both are the harness mis-attributing its own failure to the test under it, and a fix for one is the natural place to fix the other. (2) The other five are a THROUGHPUT question, not a correctness emergency: the tier costs seconds per case and ~35 min for the corpus, which is exactly why it was kept out of `make test` (a deliberate, documented choice in CLAUDE.md), and the consequence is that its findings accumulate unread. Whether that tier gets a cadence, a CI home, or stays on-demand is the owner's call, not a reviewer's. <!-- relates:b890 --> **RE-MEASURED 2026-09-07 (chain-end review, run `relay-20260907-100619-27900`): the tier is RED with FIVE violations, and the SET is not the one recorded above -- which is itself the finding.** Full-corpus run, 156 files executed. Stable and deterministic: `test_ledger_shrink_lane_promotion_6546.sh` (WRONG REASON), `test_orphan_scan_gate_ready_container_5b1f.sh` (WRONG REASON, non-exiting accumulator), `test_roadmap_lint_follows_pointer_e95b.sh` (VACUOUS). I re-ran those three against the PRE-window verifier (`git show relay-ckpt-20260907-1216:tests/verify-negative-cases.py`) and got byte-identical verdicts, so they are pre-existing and `id:b890` neither caused nor masked them. The other two are `RUNNER ERROR ... OSError: [Errno 39] Directory not empty` on `test_ledger_shrink_0d7c.sh` and `test_relay_pool_singleton.sh` -- the `id:167f` scratch-teardown race, and note these are DIFFERENT files than the one it hit last review (`test_personas_extend_preserves_text_81b8.sh`), while `test_privacy_pattern_lint.sh` did not violate at all this run. **The consequence for this box: its count and file list are not a stable quantity, and cannot become one while `id:167f` is open.** Two of five slots are occupied by a race that reshuffles between runs, so "6 pre-existing violations" and "5" are not evidence of progress or regression -- they are partly noise, and a future review comparing counts will draw a false conclusion in one direction or the other. That makes `id:167f` a de-facto PREREQUISITE for this box being measurable at all, which is an ordering the ledger does not currently record. Deliberately NOT filed as a typed `gated-on:` edge: whether to gate, or to fix `id:167f` first, or to give the tier a cadence, is the owner's throughput call that this box already reserves for him. <!-- id:2724 -->
- [ ] **`id:7c82` shipped on 2026-09-04 and sat UNTICKED in `TODO.md` for three days, and its own done-check cannot be satisfied as written because the file it names never carried a declaration.** Ticked in this review after verifying all THREE acceptance clauses independently, not by trusting the commit message: (1) the carve-out now keys on the CHECKBOX -- `verify-negative-cases.py:701` is `carved = bool(rm_token) and roadmap_item_open(root, rm_token)`, and the live `--list` run names 5 files whose carve-out EXPIRED and are now executed; (2) `lint-vacuous-fixtures.py` accepts the ratified suffixed spellings -- its count moved 11 -> 9, EXACTLY the 2 false positives the note predicted; (3) both tools import ONE definition from `tests/lib/negative_case_syntax.py` rather than each carrying its own regex. `make test` is 585/0/16-expected-red with `test_negative_case_syntax_ssot_7c82.sh` green. **The part for the human.** The note's done-check reads: "`tests/test_todo_conformance_title_chrome_60eb.sh` (which has a recorded but unverifiable mutation today) reports `red-there OK` once `id:60eb` is ticked". `id:60eb` IS ticked (`ROADMAP.archive.md:4593`), so the check is live -- but that file carries no `fails-against` line at all, and `git log -S'fails-against'` over its whole history returns NOTHING, so it never had one. The runner correctly buckets it `roadmap-spec (not verified)`: with the carve-out spent and no case to execute, there is nothing to run. So the clause rests on a FALSE PREMISE about the tree, not on unfinished work -- the `id:7c82` fix is complete and the check is unsatisfiable by construction. Recorded because the next reader who runs this done-check will get a non-answer and may reopen a delivered item, or author a mutation for a file that owes none (it is not a defect-fix test; the lint deliberately exempts it). This is the CLAUDE.md "a claim about CODE behaviour is a derived doc too" class, inside an item whose own subject is two tools disagreeing about one marker. **MAGNITUDE MEASURED 2026-09-07c (chain-end review, run `relay-20260907-100619-27900`): the class this box describes is 389 files, not one.** Counted with the runner's OWN `roadmap_item_open()` predicate rather than a hand-rolled closed-set, over every `tests/test_*.sh` carrying a `# roadmap:` token and NO `# fails-against` declaration: **389 have a CLOSED item, 14 are still open** (10 further roadmap-token files DO carry a declaration and are executed normally). So of the bucket `verify-negative-cases.py --list` labels `roadmap-spec (skipped: redness IS the spec while the item is OPEN)`, the stated justification is FALSE for the overwhelming majority of its members -- their items closed, and with them the reason for the skip, but the file has no case to execute so nothing moves it out. `id:7c82` made the RUNNER's carve-out expire on the checkbox, and that works; it buys these 389 nothing, because expiry only reaches a file that HAS a declaration. This review's own item is a fresh instance: `tests/test_archive_done_same_session_5355.sh` is materially a defect-fix test (it pins an inbound cross-repo defect report) that merely also carries a roadmap token, its negative case is real -- I ran it by hand and it reddens at exactly its three declared assertions -- and nothing durable records that. **Not filed as a new item and not a reopen:** the lint's presence-keyed carve-out is DELIBERATE and documented in its own source ("a roadmap-spec file is not a defect-fix test whatever its item's checkbox says"), so whether the category boundary should survive an item's close is a design call the owner reserved, not a reviewer fix. The number is offered so the call is made against the real size rather than against a single example. <!-- id:c7dd -->

**Everything else checked and clean, stated so a silent pass is distinguishable from not looking.**
Contract pointer `CLAUDE.md:258` is `v18`, matching the canonical marker in
`relay/references/executor-contract.md:7` -- no refresh needed. `orphan-scan --cross-ledger`: clean.
`orphan-scan --shipped`: **0 TICK-READY, 0 GATE-STALE** -- the `id:4425` fix continues to hold
(it took those emissions 2 -> 0 on 2026-09-01 and they have stayed there). `roadmap-lint`: every
open item carries a recognized lane tag + id. `clean-tree-gate`: main checkout has no residue.
`mechanical-orphan`: every open `[MECHANICAL]` item has an authored recipe. `relay.toml` parses.
Lean toolchain pins agree. Spec-drift (§4) is vacuous this window -- nothing shipped, so
`ARCHITECTURE.md`/`README.md` cannot have drifted from it. Ambient, unchanged, recorded for
continuity: relay-core shadow parity is **30,540 mismatches over 302,652 rounds** (bash stays
authoritative; the flip gate is 100% parity + 5 clean rounds), and 3 parked orphan branches sit
across the fleet (loderite, lean4btc, git-annex).

## Review 2026-09-07 (chain-end re-ask, run `relay-20260907-100619-27900` -- id:8123)

- [ ] **The `id:2964` fix landed in TWO halves and only ONE of them is pinned by any assertion.** `d7685ee4` both (1) anchored the keep-set to a marker SHAPE (`_MARKER_RE`, the half its own commit subject names) and (2) added `_MASK_QUOTED_MARKERS`, which drops a comment-shaped keep beginning inside an inline-code span. Reverting (1) ALONE leaves the entire suite green. Every over-match fixture in `tests/test_ledger_shrink_marker_grammar_2964.sh` (cases A, C) and in `tests/test_shrink_example_marker_hoist_8372.sh` writes its prose `<!--` inside backticks -- 5 fixture lines, 5 backticked -- so the mask suppresses the over-match before the shape rule is consulted. Replaying case C's body against the OLD `<!--[^>]*-->` and the code-span list directly: one 366-char over-match, and it STARTS inside a code span. Case (E) does not discriminate either -- it pins that an unenumerated marker NAME survives, which the old pattern also satisfied. Consistently, the file's `# fails-against-assertion:` names the MASK half, and `make verify-negatives` reports `red-there OK` against the two-half mutation; that verdict is honest, it simply cannot see that one half is carrying the whole result. **This is NOT a reopen of `id:2964`** -- its acceptance is met and I re-verified it independently (`make test` 581/0/19-expected-red; `ee62` 169 chars and `5817` 233, the two measured corruptions; hoisted `id:XXXX` down to one genuinely-unbackticked prose mention at `TODO.md:668`). The commit itself declared the adjacent gap ("NOT verified: that each fix half reddens independently -- the sandboxed copy-and-mutate probe was denied"); the same probe was denied to this review, and I did not route around the guard. What is new here is WHICH half is unpinned, established by reading rather than mutating. The shape anchor is untested, not unnecessary: `TODO.md:668` carries an UNBACKTICKED `'<!-- id:XXXX -->'` in prose, so the unmasked class exists in the live corpus. Filed + promoted as `id:32ba` with acceptance and a done-check. <!-- relates:2964 --> <!-- id:32ba -->

- [ ] **`relay-doctor` install-drift: `relay/scripts/lib-archive-idempotency.py` is declared in `relay_FILES` but is not installed under `~/.claude/skills/relay`.** A declared-but-uninstalled library is the `id:1102` class -- the manifest and the install tree disagree, so a caller resolving it through the install path fails at runtime while every in-repo test passes. One file; `make install-relay` is the likely resolution, but which side is authoritative (drop the declaration, or install it) is the owner's call. <!-- id:168c -->

- [ ] **Four parked orphan branches now sit on this repo, and one of them is THIS run's own execute worktree.** `relay/orphan/relay-20260907-100619-27900-execute-64f9-0` (`ca6a4a04`) is the WIP residue of the execute unit whose agent-error triggered this chain-end re-ask -- expected, but it means `id:64f9` was attempted and left unfinished this round. The other three are `recovered-20260826-review-3d9ca6f3` and the two 2026-09-05 execute residues, of which `relay/scripts` reconcile already mined `id:be51` and `id:ceca`. Nothing here is lost work; the question for the owner is whether the 2026-08-26 recovered review branch still has anything unmerged worth taking, since it is the oldest and is the only one that is not an executor WIP auto-commit. <!-- id:5121 -->

- [ ] **`scan-routed` reports 2 twinned-resolvable inbox items -- 0 dead-letters.** Both have their `routed:` twin already present in the target repo, so `--apply` would simply drain them from the inbox. Report-only per the review contract; a `/relay human` or a `--apply` pass closes them. <!-- id:b555 -->

**Everything else checked and clean, stated so a silent pass is distinguishable from not looking.**
`gaming-scan.sh` over `relay-ckpt-20260907-0736..HEAD`: no output -- 0 `DELETED_TEST`, 0
`ADDED_SKIP`, 0 `REMOVED_ASSERT`. No test file was MODIFIED in the window (one was added), so the
resurrection check (§2b.1) has no candidate. Provenance (§2b.7/9/10): no commit in the window
introduces `@owner-accepted:`, `@owner-answered:` or `<!-- answer-src:`, and no line carrying one
was modified. Over-reach (§2d): `id:2964`'s diff is a NARROWING of an over-matching regex plus a
mask deliberately scoped to comment shapes only -- explicitly NOT extended to lane brackets
(`id:1254`, where masking would put this tool into disagreement with `classify-repo.sh`) nor to
the `@marker` family, which is left to `id:8372`; I confirmed that scoping by running the `8372`
spec, which now advances past its A1/A2 cases and fails at `(A3)` -- the backticked `@manual` --
exactly as the commit claims. No superset. Test tiers (§3) enumerated from the `Makefile`, there
being no CI config: `make lint` + `make test` RAN green (581 passed / 0 failed / 19 expected-red,
against the commit's claimed 581/0/19 baseline 580/0/19); `make verify-negatives` RAN for the new
file (`green-now OK` / `red-there OK`); `make gaming-canary` and `make shard-canary` are the Tier-B
model canaries, deliberately out of `make test` because they cost tokens -- SKIPPED-TIER, not folded
into the green claim. Contract pointer `CLAUDE.md:258` is `v18`, matching
`relay/references/executor-contract.md:7` -- no refresh needed. Spec drift (§4): `CLAUDE.md`'s
Layout table was updated in the same commit that changed the tool, and no longer endorses the old
`<!--[^>]*-->` spelling. `orphan-scan --cross-ledger`: clean. `roadmap-lint`: exit 0, 4 DEAD-GATE
warnings (`d4ca`, `e405`, `540f`, `c179` -- all gated on `09e4`/`b0b1`, which live only in
`TODO.md`) and 1 NO-ACCEPTANCE-NO-TWIN (`da55`), all pre-existing and unchanged by this window.
Reverse-handoff (§5b): the only genuinely new open items this window are `id:be51` and `id:ceca`,
and both already carry a `[ROUTINE]` lane, a detail pointer, an Acceptance and a Done-check -- no
mini-handoff was owed. Ambient, unchanged, recorded for continuity: relay-core shadow parity is
31,272 mismatches over 306,597 rounds (bash stays authoritative; the flip gate is 100% parity + 5
clean rounds), and the Lean toolchain pins agree at `v4.30.0-rc2`.

## Review 2026-09-07b (chain-end re-ask, run `relay-20260907-100619-27900` -- id:8123)

Window `relay-ckpt-20260907-1308`..HEAD, **6 commits**, one worked item: **`id:b87b`** (the
`id:b54b` hermeticity backstop firing on the runner's OWN advancing relay branch).

**`id:b87b` VERIFIED GREEN, and verified the hard way.** The RED spec
`tests/test_hermeticity_own_branch_b87b.sh` was authored by the prior review (`d1351d61`,
a confirmed ancestor of the fix `a1d21ef2`) and the executor **did not touch it** -- the only
test-directory change in the whole window is `tests/run-tests.sh` itself. I ran the spec
against the PRE-fix runner (`a1d21ef2^`) in a scratch repo: it fails at exactly assertion
**(1)**, the one it claims to pin, while assertions **(2)** and **(3)** still pass. That is
the shape a narrow fix must have -- had the executor "fixed" it by dropping object names from
the snapshot, (3) would have failed too. `gaming-scan.sh`: clean (no deleted test, no added
skip, no removed assert). Provenance greps (§2b.7/2b.9/2b.10): no `@owner-accepted`,
`@owner-answered` or `answer-src:` marker was minted or modified this window.

**Over-reach (§2d): not a superset.** The cited ratified source is `docs/ledger-notes/b87b.md`,
read directly rather than through the ROADMAP restatement. It authorises exactly two things,
and the diff does exactly those two: exclude **only** the ref `git symbolic-ref HEAD` names
from the object-name comparison (not object names generally), and split the breach message
into added/removed/moved findings. The exclusion is keyed on a single ref, so a fixture moving
any OTHER `refs/heads/relay/*` ref still trips the guard -- which the spec's cases (2) and (3)
independently hold.

**Test tiers (§3), enumerated from the `Makefile` (there is no CI config):** `make lint` RAN
green (0 bare-`rm -f` violations, within baseline); `tests/run-tests.sh` RAN green, **587
passed / 0 failed / 14 expected-red**, matching the executor's claimed 587/0/14 exactly, and
**588 / 0 / 14** on a second full run once this review's own regression-guard was added.
`make verify-negatives` is opt-in, seconds-per-case, and NOT part of `make test`; I ran its
logic by hand for the two files that matter here (both negative controls below) rather than
the whole tier -- **SKIPPED-TIER: verify-negatives (opt-in, full-tier not run)**, not folded
into the green claim. `make check-statusline-deps` is a dependency probe, not a test tier.

**One real gap found, and closed rather than filed.** `id:b87b` had TWO acceptance clauses;
the pre-authored RED spec covers the first fully and the second **not at all**. The note's own
Done-check case (3) was *"assert the breach text for case (2) names the addition"*, and the
spec that got written substituted a force-moved-ref coverage assertion for it. So the ~20 lines
of added/removed/moved classification in `run-tests.sh` shipped **green with zero tests** --
the executor built what was asked, and the spec simply did not ask for the second half. I
verified the classification by hand end-to-end (all three labels fire, each naming the right
ref) and then made that check durable as
`tests/test_hermeticity_breach_classification.sh`. Box `id:d06a` below is the §2b.3 entry that
a green regression-guard is required to carry.

- [ ] **`id:d06a` -- new GREEN regression-guard `tests/test_hermeticity_breach_classification.sh`: is the pinned message format correct, or am I freezing a shape you would rather change?** Written by this review, not by an executor, because the behaviour it pins already worked. It drives the REAL `tests/run-tests.sh` in a `mktemp -d` repo checked out on a `relay/*` branch and asserts that an ADDED, a REMOVED and a MOVED `refs/heads/relay/*` ref each produce their own label naming the right ref, that the two WRONG labels are absent in each case, and that an own-branch commit produces no breach at all. **Non-vacuous, proven by mutation:** against the pre-fix runner (`a1d21ef2^`) all 4 assertions fail; against HEAD all 4 pass. Two authoring traps I hit and am recording because both are the "unreached fixture is not a passing negative control" class: (a) `"removed ref(s):"` CONTAINS `"moved ref(s):"` as a substring, so the first draft's unanchored negative assertion reported the removed case as also claiming a move -- every label pattern is now line-anchored on the runner's two-space indent, and that anchoring is load-bearing, not tidiness; and (b) my first fixture ran `git init` on a default `main` branch, which puts the runner's own ref OUTSIDE the watched `refs/heads/relay/` namespace, so case (4) could never have detected a `b87b` regression and passed against the pre-fix runner too -- the fixture now inits on `relay/fixture-review-repo-0` and case (4) correctly fails pre-fix. **What needs your call:** the guard pins an exact human-readable message format (label text and indentation), which is deliberately more brittle than pinning behaviour. If you would rather the classification be asserted structurally, say so and it should be narrowed. <!-- relates:b87b --> <!-- id:d06a -->

**Nothing else new.** Reverse-handoff (§5b): the window adds no new open `- [ ]` line to
`TODO.md` or `ROADMAP.md` -- the only ledger edits are `b87b`'s own close (removed from
`ROADMAP.md`, appended to `ROADMAP.archive.md`, TODO twin ticked at `TODO.md:845`) and the
CHANGELOG entry. No mini-handoff was owed. Contract pointer `CLAUDE.md:258` is `v18`, matching
`relay/references/executor-contract.md:7` -- no refresh. Spec drift (§4): the change is
internal to the test harness and `CLAUDE.md` §Testing does not describe the hermeticity
backstop's message format, so nothing there went stale. `orphan-scan --cross-ledger`: clean.
`roadmap-lint`: exit 0; the 4 DEAD-GATE warnings (`d4ca`, `e405`, `540f`, `c179`) and the one
NO-ACCEPTANCE-NO-TWIN (`da55`) are pre-existing, unchanged by this window, and already boxed
above -- no duplicate boxes added. `todo-conformance`: all findings grandfathered or
pre-existing. `relay-doctor`: 1 install-drift MISSING
(`relay/scripts/lib-archive-idempotency.py` declared in `relay_FILES` but absent from the
install tree -- a `make install-relay` would clear it), 7 parked orphans, 4 inbox dead-letters
targeting this repo (`routed:de13`, `routed:f83a`, `routed:1fd4`, `routed:37ce`); all live
durably in the git-tracked inbox and are surfaced by `/relay human`, so they are pointed at
rather than re-copied into a third parallel record. One escalation on an EXISTING box rather
than a new one: `classify-repo.sh` now emits `ledger-note pointer names a MISSING/unreadable
detail file: docs/ledger-notes/4983.md -- counting 32768 B conservatively` on every run of this
repo. That is the box already open at `REVIEW_ME.md:49`, and its own text predicted this
("load-bearing now because `id:1608` made pointer-following live"); it has now moved from a
latent wrong-address to a standing 32 KB over-charge against this repo's prompt-size gate on
every classification. Still the owner's call, since the fix means rewriting an archived line.
Ambient and unchanged: relay-core shadow
parity 31,422 mismatches over 309,382 rounds (bash stays authoritative), Lean pins agree at
`v4.30.0-rc2`.

## Review 2026-09-07c (chain-end re-ask, run `relay-20260907-100619-27900` -- id:8123)

Window `relay-ckpt-20260907-1418`..HEAD, **6 commits**, one worked item: **`id:5355`** (the
inbound `routed:3b3a` report from loderite: `archive-done.sh` sweeping same-session closes).
Note on the base: the repo's latest tag is `relay-ckpt-20260907-1429`, which is the checkpoint
OF the work under review, so the `git tag | tail -1` recipe in `review.md` §1 yields an EMPTY
window here. The dispatched `-1418` is the correct base and is what was used.

**`id:5355` VERIFIED GREEN, by an independent negative control.** The RED spec
`tests/test_archive_done_same_session_5355.sh` was authored by an earlier review (`5d388655`)
and the executor **did not touch it** -- `git diff --stat <base>..HEAD -- tests/` is empty, so
nothing in the test surface moved at all. I swapped the PRE-fix `todo-update/archive-done.sh`
(`3c3e1b77^`) under the untouched spec: it fails at exactly assertions **(1)**, **(1b)** and
**(1c)**, the three it claims to pin, while case **(2)** -- the over-correction trap, "a
genuinely old entry still archives" -- still PASSES. That is the shape a narrow fix must have:
had the executor "fixed" it by deleting the `prior_done` branch, (2) would have gone red too.
Tree restored, re-run 4/4 green. `gaming-scan.sh`: clean (no deleted test, no added skip, no
removed assert).

**The spec is ARMED, which is the part worth stating.** Its dateless canary is a hard
FIXTURE-BROKEN gate, not an assertion: `archive-done.sh` resolves `prior_done` via
`git rev-parse --show-toplevel` against the CURRENT directory, so invoking it from outside the
fixture repo yields an EMPTY `prior_done` and every assertion below would pass for the wrong
reason. The gate did not fire on either side of my control, so the branch under test genuinely
executed both times. This is the "an unreached fixture is not a passing negative control"
class, and here the spec's author had already closed it.

**Over-reach (§2d): not a superset.** The cited ratified source is `docs/ledger-notes/5355.md`,
read directly rather than through the ROADMAP restatement. Its acceptance is verbatim: "An
`[x]` item carrying a trailing `on YYYY-MM-DD` date newer than the archive cutoff is NOT
archived, even when that exact line is present in the prior commit." The diff implements that
predicate (`own_date > cutoff` short-circuits the `prior_done` branch) and nothing wider.
Notably it keys on the CUTOFF rather than on "today", which is what the source authorises --
narrowing it to same-day would have been a DIFFERENT rule than the one ratified, not a safer
one. The note's second clause (genuinely old entries still archive) is independently held by
the spec's case (2).

**Test tiers (§3), enumerated from the `Makefile` (there is no CI config):** `make test`
(which runs `lint` first) RAN green -- **590 passed / 0 failed / 12 expected-red**, matching
the executor's claimed 590/0/12 exactly. **SKIPPED-TIER: `verify-negatives`** -- opt-in,
seconds per case, deliberately not part of `make test`; I ran its logic by hand for the one
file that matters here rather than the ~35-minute corpus. **SKIPPED-TIER: `gaming-canary`** --
on-demand and costs tokens by design. Neither is folded into the green claim.

**Provenance and residue: clean.** §2b.7/2b.9: no `@owner-accepted`, `@owner-answered` or
`answer-src:` marker was minted this window. §2b.10: no line already carrying one was modified.
§2b.6: the `refactor: none needed` self-report is honest and the diff supports it -- the change
HOISTS the date parse out of the `else` arm and reuses it in both new arms, so it removes a
duplication rather than leaving one. §2c: `id:5355` carries no `[host:]` tag, so the host gate
does not apply. §5b reverse-handoff: the window adds no new open `- [ ]` line to `TODO.md` or
`ROADMAP.md`, so no mini-handoff was owed. Contract pointer is `v18`, matching
`relay/references/executor-contract.md` -- no refresh.

**Spec drift (§4): one real gap, FIXED INLINE.** `CLAUDE.md`'s Gotchas entry for
`archive-done.sh` stated the prior-commit rule as UNCONDITIONAL ("only archives `[x]` items
that were already done in the prior commit, or are >=30 days old"), which is precisely the
shape `id:5355` removed. Left alone it is the CLAUDE.md "a claim about CODE behaviour is a
derived doc too" class pointing at a defect that was just fixed, and a reader restoring the
documented behaviour would reintroduce the bug. The entry now records the precedence and why
the branch must never be made unconditional again. `orphan-scan --cross-ledger`: clean.
`roadmap-lint`: exit 0, same pre-existing DEAD-GATE / NO-ACCEPTANCE-NO-TWIN warnings as the two
earlier reviews in this run, already boxed. `relay-doctor`: unchanged from Review 2026-09-07b
-- same install-drift (`lib-archive-idempotency.py`, boxed as `id:168c`), same 7 parked
orphans, same 4 inbox dead-letters (`routed:de13`, `f83a`, `1fd4`, `37ce`), which that review
deliberately pointed at rather than copying into a third parallel record; I did not re-copy
them either.

**NO new boxes added, deliberately.** The queue stands at **42 open against a stated max of
~10**. Every finding this review reached was either already boxed or belongs on an existing
box, so the one genuinely new measurement went onto `id:c7dd` as an escalation rather than
opening a 43rd. Flagged for the owner as a queue-health note, not as a new item: the prune
this file's own header promises ("the reviewer prunes resolved ones each review turn") is not
keeping up, and `archive-closed.sh --only review_me` only reaches boxes already ticked `[x]`,
so an over-budget queue of OPEN boxes is structurally outside the one tool wired to compact it.

## Review 2026-09-07d (chain-end re-ask, run `relay-20260907-100619-27900` -- id:8123)

Window `relay-ckpt-20260907-1516`..HEAD, **6 commits**, one worked item: **`id:0176`**
(`cited_by`'s surviving-text escape evaluated against the wrong future state in a batch move).
Same base caveat as Review 2026-09-07c: the repo's latest tag is `relay-ckpt-20260907-1540`,
which is the checkpoint OF the work under review, so `review.md` §1's `git tag | tail -1`
recipe yields an EMPTY window. The dispatched `-1516` is the correct base and is what was used.

**`id:0176` VERIFIED GREEN by an independent negative control.** The RED spec
`tests/test_cited_body_batch_state_0176.sh` was authored at handoff (`5017bf07`) and the
executor **did not touch it**: `git diff --name-only <base>..HEAD -- tests/` is EMPTY, so no
part of the test surface moved. I rebuilt the pre-fix tree (`tools/ledger-continuations.py` at
`relay-ckpt-20260907-1516`, plus its `ledger-shrink` sibling import) under the UNTOUCHED spec.
It fails at exactly case **(A)** -- the named defect -- and not at an earlier setup assertion:
`FAIL: (A) neither cc01 nor cc02 was reported -- each was cleared by text in the OTHER block`.
Controls (B) site-named, (C) an unread block still moves, and (D) single-block behaviour
unchanged all pass on the new implementation. (C) is the load-bearing control here: abandoning
the escape wholesale would have turned it red, so the fix could not have been a blunt
disablement. `gaming-scan.sh`: clean -- no deleted test, no added skip, no removed assert.

First attempt at that control failed for the WRONG reason (`ModuleNotFoundError: ledger-shrink`
-- my scratch tree, not the code), which the spec caught as a `setup:` failure rather than
reporting a false red. Recording it because an unreached fixture that LOOKS like a passing
negative control is the failure mode this repo has been bitten by before.

**Over-reach (§2d): not a superset.** The cited ratified source is `docs/ledger-notes/0176.md`,
read directly rather than through the ROADMAP restatement. It authorises exactly two repairs
verbatim -- "Compute `elsewhere_lines` against the ledger state AFTER the whole batch" or
"the escape must be disabled for a multi-block run and the sites reported". The diff implements
the FIRST and nothing wider. The source's own acceptance requires "a single-block move behaves
as it does today", and the new code satisfies that structurally rather than by special-casing:
with one candidate, `batch_rest` is `lines` minus that one body, which is byte-identical to the
old `lines[:i+1] + lines[j:]`.

**Test tiers (§3), enumerated from the `Makefile` (there is no CI config):** `make test` RAN
green -- **592 passed / 0 failed / 10 expected-red**, matching the executor's claimed 592/0/10
exactly. **SKIPPED-TIER: `verify-negatives`** -- opt-in, seconds per case, deliberately not part
of `make test`; I ran its logic by hand for the one file that matters here. **SKIPPED-TIER:
`gaming-canary`** -- on-demand and costs tokens by design. Neither is folded into the green
claim.

**Provenance and residue: clean.** §2b.7/2b.9: no `@owner-accepted`, `@owner-answered` or
`answer-src:` marker was minted this window. §2b.10: no line already carrying one was modified.
§2b.6: `refactor: none needed` is honest -- the change restructures `scan()` into two passes and
moves the reporting block verbatim; no duplication is left behind. §2b.4 invariants survived the
refactor: `REFUSE_IDS` still appears only in the two prose warnings against it, and
`selftest_predicate()` still runs before every scan. §2c: `id:0176` carries no `[host:]` tag.
§5b reverse-handoff: the window adds no new open `- [ ]` line to `TODO.md`/`ROADMAP.md`, so no
mini-handoff was owed. Contract pointer is `v18`, matching the canonical marker -- no refresh.

**The 4 inbox dead-letters are now INGESTED, which is the change from Reviews 07b/07c.** Both
pointed at `routed:de13`, `f83a`, `1fd4`, `37ce` rather than copying them into a parallel
record; that was right while nothing had adopted them, but it left `scan-routed.sh` reporting
the same four every run with no path to resolution. They are now filed as `TODO.md` items with
their `[INBOUND routed:XXXX from ...]` breadcrumb -- `id:b115`, `id:9a72`, `id:bf91`, `id:f03d`,
each with a detail note. `append.sh inbox-done` is deliberately NOT run here: the next
`scan-routed.sh --apply` auto-drains an item whose target already carries the twin, so planting
the twin is the whole obligation and running the delete from a review child is the half that
can go wrong.

**Two of the four were re-verified against this tree rather than adopted on the filer's word,
and one of those verifications changes the diagnosis.** `routed:1fd4` (roadmap-lint's
DETAIL-POINTER-MISSING false positive) is CONFIRMED, and the cause is not quite what was filed.
`item_detail_path` (`relay/scripts/roadmap-lint.sh:394`) captures with `grep -oP -m1` under a
comment explaining that `-m1` was chosen over `| head -1` to avoid SIGPIPE under `pipefail`
(`id:81d5`). That reasoning is correct for the hazard it names and does not do what the code
needs: **`-m1` bounds matching LINES, never matches WITHIN a line.** Measured here on a
one-line here-string carrying the same note path twice, `-m1` emits BOTH. So the repair must
take the first match explicitly while KEEPING the no-pipe property -- swapping in `| head -1`
would restore the exact SIGPIPE hazard that comment exists to prevent. `routed:f83a` is
confirmed by reading `classify-repo.sh:187`: `LEDGER_NOTE_POINTER_RE` is a bare
`<dir>/<4hex>.md` path shape with no `detail:` anchor, so prose is collected as a pointer. It
over-counts only, so the gate goes pessimistic -- the safe direction, and filed as a defect
rather than an incident for that reason.

**Spec drift (§4): one gap, FIXED INLINE.** `CLAUDE.md`'s `tools/` entry described
`ledger-continuations.py`'s `cited_by` but said nothing about the two-pass structure the fix
just made load-bearing. A reader optimising `scan()` back into a single loop would silently
reintroduce `id:0176`, and the entry already carries a "do NOT re-spell this" warning for the
neighbouring `ledger-shrink.py` for the same reason. The entry now records the two passes, the
shared `batch_rest`, what the per-block state got wrong, and the consumer it silenced.
`orphan-scan --cross-ledger`: clean. `roadmap-lint`: clean -- every open item carries a
recognised lane tag and id. `relay-doctor`: otherwise unchanged from Reviews 07b/07c -- same
parked orphans, same relay-core shadow mismatch count, same `todo-conformance` shape-prose
backlog, all already boxed or tracked under the `id:0d7c`/`id:2d17` line-shrink work.

**NO new boxes added, deliberately -- for the second review running.** The queue stands at
**42 open against a stated max of ~10**. Every finding here either resolved into `TODO.md` (the
four dead-letters) or was fixed inline (the `CLAUDE.md` drift), so opening a 43rd box would have
recorded work that is already done. The queue-health note Review 07c raised for the owner still
stands unchanged and I am not restating it as a new item: `archive-closed.sh --only review_me`
reaches only boxes already ticked `[x]`, so a backlog of OPEN boxes is structurally outside the
one tool wired to compact this file.

## Review 2026-09-07e (chain-end re-ask, run `relay-20260907-100619-27900` -- id:8123)

**Diff-window note, because it changes what was reviewed.** `git tag | sort | tail -1` gives
`relay-ckpt-20260907-1105`, which is at HEAD, so the literal review.md §1 window is EMPTY. That
tag is an EXECUTOR checkpoint (`executor (sonnet, relay-loop)`), written by the unit that closed
`id:c132`. Reviewing the literal window would have silently passed that unit unreviewed. The
window actually reviewed is `relay-ckpt-20260907-1045..HEAD` -- the last REVIEWER checkpoint.
This is structural, not a one-off: every execute unit checkpoints, so the tail-1 rule hides
exactly the work a chain-end review exists to check.

- [ ] **`id:c132` is genuinely green, but it silently NARROWED the ref half of the hermeticity
  guard, and the narrowing realised the exact hazard `id:b87b`'s acceptance had named.** `c132`
  was specified as a worktree-only exclusion -- its note says in as many words that "the ref half
  of the snapshot is untouched by this change", and its control case (C) is worded from that
  belief. It could not be true: case (A)'s own fixture runs `git branch relay/20260904-child`
  MID-RUN, so a new ref appears in the after-snapshot and a worktree-only exclusion leaves case
  (A) red. The delivered fix therefore also drops the refs checked out by worktrees under
  `$RELAY_WORKTREE_BASE`. Measured, one probe repo per configuration, each driving the REAL
  `tests/run-tests.sh`: (1) a relay-base runner committing on its own branch mid-run -> no
  breach, rc=0 (this DISCHARGES `id:b87b`'s stated symptom, as a side effect rather than by
  design); (2) a plain checkout on a `relay/*` branch NOT under the relay base, same commit ->
  BREACH, rc=1 (so `b87b` survives, keyed on the wrong thing -- its acceptance asked for "the ref
  `HEAD` points at", `c132` delivered "any relay-base worktree's branch"); (3) a fixture
  force-moving a SIBLING relay-base worktree's ref -> NO breach, rc=0, verified by the ref itself
  moving `0812b8ce` -> `1304cb76`, not by an exit code. Row (3) is `b87b`'s own words: the fix
  must "NOT [drop] object names entirely, which would stop the guard noticing a fixture
  force-moving some other relay ref". This repo routinely holds two relay worktrees at once
  during a pool round (this review observed its own branch plus
  `relay/relay-20260907-100619-27900-execute-4839-0`), so the blind set is not hypothetical.
  **Disposition: `id:c132` is NOT reopened** -- its acceptance is met and the widening was FORCED
  by its own ratified RED spec, so this is an honest superset (review.md §2d), not gaming.
  `id:b87b` is RE-SCOPED instead, in ROADMAP.md and TODO.md, with the three measured rows, a
  revised acceptance (re-key the exclusion to `HEAD`'s ref so rows (1) and (3) hold together) and
  a revised done-check. `docs/ledger-notes/c132.md` had its false sentence struck and corrected,
  with the edit declared in its header per the notes-are-editable convention. <!-- relates:c132 --> <!-- id:b87b -->

- [ ] **The inbox now holds 4 dead-letters addressed to this repo, up from 0 at the 10:45
  review.** `routed:de13` (relay worktrees symlink `node_modules` into the main checkout, so
  `pnpm <script>` aborts and every pnpm-shelling test reads red; the obvious `CI=true` /
  `confirmModulesPurge=false` fix would purge the MAIN checkout's `node_modules` through the
  symlink and must be refused explicitly), `routed:37ce` (a CORRECTION to `de13`: pnpm DOES run
  in a relay worktree with `PNPM_CONFIG_VERIFY_DEPS_BEFORE_RUN=false`, which authorises no
  removal; verified in zkWhale 2026-09-07, and it proposes setting it in the relay child env),
  `routed:f83a` (`classify-repo.sh`'s `LEDGER_NOTE_POINTER_RE` matches a note path quoted in
  PROSE, not only a `detail:` pointer, and charges the fail-safe 32,768 B for it -- over-counts
  only, so the direction is safe, but it is the `id:fff8` measurement-artefact class inside the
  measuring tool), and `routed:1fd4` (`roadmap-lint` DETAIL-POINTER-MISSING false-positives when
  one line carries the same note path in BOTH an `answer-src:` and a `detail:` pointer -- it
  JOINS the two captures with a newline and reports the concatenation missing). I did NOT ingest
  them: `scan-routed.sh --apply` is the canonical writer and it resolves the target from
  `relay.toml` to the MAIN checkout, which is outside this child's worktree, and it also DELETES
  inbox lines. Surfaced rather than acted on, per the conservative-default rule. Resolution is
  one `scan-routed.sh --apply` from a `/relay human` pass in the main checkout; note that `de13`
  and `37ce` are one topic and `37ce` supersedes `de13`'s proposed fix, so they want adopting
  together (as two lines -- one `routed:` breadcrumb each, per `id:6059`). <!-- id:7b8d -->
- [ ] 🔴 **The `id:f91a` hazard is LIVE right now: this repo's MAIN checkout carries 35 lines of uncommitted, unreviewed work that no worktree contains, and it will DEFER this repo from every later pool round.** Observed at 11:56 while confirming my own worktree was clean: `git -C ~/src/dotclaude-skills status` shows `M meeting/md-merge.py` (mtime 11:52) and untracked `tests/test_md_merge_multiline_line_guard_f833.sh` (mtime 11:54) -- both written DURING this review (started 11:44), neither by me (I only ever invoked `md-merge.py`, never edited it, and all my writes are in my worktree and committed at `486e6737`). The work itself looks sound and deliberate: a real defect fix for `id:f833` (`md-merge.py update-ids` replaces only the marker line, so a multi-line `line` payload DUPLICATES an item instead of updating it -- found in kienzler-solutions' TODO.md) with a matching hermetic test that deliberately carries no `# roadmap:` header. So this is MISLOCATED, not bad: the conventions.md `id:f682` recovery doctrine says favour salvage over discard, and nothing here should be reverted. Two facts make it urgent rather than cosmetic. (1) It is the exact `verify-isolation.sh` failure signature -- the sibling execute worktree `relay/relay-20260907-100619-27900-execute-4839-0` is CLEAN and sits **0 commits beyond main**, i.e. an empty worktree beside a dirty main checkout, which is precisely the shape `id:f682` describes as a silently-wrong 'commit in the worktree' self-report. (2) A dirty main checkout trips the `id:aa93` dirty-guard, so every later pool round DEFERS this repo -- the self-perpetuating backlog review.md §5 exists to prevent. I did NOT commit it (it is another actor's in-flight work, unreviewed, and committing it under my review's checkpoint would launder it as reviewed) and did NOT revert it. I also cannot prove WHO wrote it: no `execute-4839` process survives, and the run's children share one `CLAUDE_SESSION_ID`, so authorship is inferred from timing and location, not established. There is no `id:f833` item in this repo's TODO.md or ROADMAP.md -- only a `routed:f833` mention inside `id:689e` -- so if this came from a cross-repo child it also bypassed the shared-inbox rule. Owner/integrator call: salvage-commit it in the main checkout under the held lease, or hand it back to whoever owns it. <!-- relates:f91a --> <!-- id:b923 -->

**Everything else checked and clean, stated so a silent pass is distinguishable from not
looking.** `gaming-scan.sh` over `relay-ckpt-20260907-1045..HEAD`: no output -- 0 `DELETED_TEST`,
0 `ADDED_SKIP`, 0 `REMOVED_ASSERT`. No test file was added OR modified in the window (the `c132`
RED spec was authored earlier, in `5017bf07`), so the resurrection check (§2b.1) has no candidate
and the spec that went green is byte-identical to the one authored before the implementation --
the strongest form of that check. Fixture special-casing (§2b.2): none -- the exclusion is
derived from `$RELAY_WORKTREE_BASE` and from `git worktree list --porcelain`, and the spec
deliberately points that variable at a `mktemp` path so a hardcoded literal cannot satisfy it.
Provenance (§2b.7/9/10): no commit in the window introduces `@owner-accepted:`,
`@owner-answered:` or `<!-- answer-src:`, and no line carrying one was modified. Faked-clean-tree
(§2b.5): the acceptance behaviour is present in the diff and re-derived here by probe, not
inferred. Refactor claim (§2b.6): `none needed -- scoped guard fix` is consistent with a 26-line
single-function change. Host gate (§2c): no `[host:]` tag on the item. Test tiers (§3)
enumerated from the `Makefile`, there being no CI config and no `package.json`: `make lint` +
`make test` RAN green -- **582 passed / 0 failed / 18 expected-red, exit 0, no hermeticity
breach**, matching the executor's claimed 582/0/18 (suite wall-clock measured at `load average:
18.7-21.0` on 8 cores, so timing here says nothing about the suite). `make verify-negatives` RAN
for the `c132` spec: 0 failures, correctly reported `roadmap-spec` -- I chased that label,
suspecting the `id:7c82` carve-out had been reintroduced through the ARCHIVE path, and it had
NOT: `roadmap_item_open()` returns False for `c132`, the carve-out is SPENT, and the file lands
in `roadmap_spec` only because it carries no machine-readable case and, as a roadmap-spec file,
owes none. (One cosmetic residue: the summary line prints "skipped: redness IS the spec while the
item is OPEN" for files whose carve-out has EXPIRED, which is what sent me looking.)
`make gaming-canary` and `make shard-canary` are Tier-B model canaries, deliberately out of `make
test` because they cost tokens -- SKIPPED-TIER, not folded into the green claim. Contract pointer
`CLAUDE.md` is `v18`, matching `relay/references/executor-contract.md` -- no refresh needed.
Spec drift (§4): the window touched one guard function in `tests/run-tests.sh`; `CLAUDE.md`'s
Testing section describes the hermeticity backstop's semantics only in terms of `# fails-against:`
and expected-red, neither of which changed, and `README.md` does not document the backstop -- no
drift. `orphan-scan --cross-ledger`: clean, no output. `roadmap-lint`: exit 0, the same 4
DEAD-GATE warnings (`d4ca`, `e405`, `540f`, `c179` -- all gated on `09e4`/`b0b1`, which live only
in `TODO.md`) and 1 NO-ACCEPTANCE-NO-TWIN (`da55`), all pre-existing and unchanged by this
window. `orphan-scan --shipped`: no TICK-READY hits; the 90 candidates are UNMARKED-GATE and
container advisories, pre-existing. Reverse-handoff (§5b): the window added NO new open ledger
item -- its only ledger edits were ticking `c132` and archiving it -- so no mini-handoff was
owed. Parked orphans are unchanged at 4 for this repo and remain covered by `id:5121`; the
2026-09-05 execute residues and this run's own `execute-64f9-0` are all `id:f272` WIP
auto-commits. Ambient, unchanged, recorded for continuity: relay-core shadow parity is 31,292
mismatches over 307,113 rounds (bash stays authoritative; the flip gate is 100% parity + 5 clean
rounds), Lean toolchain pins agree at `v4.30.0-rc2`, and `hooks-path-shadow-scan` reports 57 own
repos, 0 EMPTY-SHADOW, 2 DELIBERATE.
