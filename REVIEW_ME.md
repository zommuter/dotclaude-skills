# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

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
- [ ] **Three inbox dead-letters addressed to this repo were never ingested** (surfaced by
  `relay-doctor` / `scan-routed.sh`): `routed:5fa9` (the adoption-form vs multi-marker-refusal
  contradiction), `routed:de8f` (`roadmap-lint` DEAD-GATE never reads `ROADMAP.archive.md`) and
  `routed:f854` (the consumed-state sweep script). I filed all three into `TODO.md` as `id:41d3`,
  `id:d3bf`, `id:bfee` using the `[INBOUND routed:TOK from ...]` bracket-prefix form. A fourth,
  `routed:7ad4`, targets **relay-core** (the shadow binary must follow `id:098a`'s lane changes or
  classify parity goes red) and is left for that repo -- I did not write into it.

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

- [ ] **id:5eeb — a context handback firing BEFORE the first edit commits NOTHING, and `route="none"` writes nothing durable: a LIVELOCK.** MEASURED (apex review, 2026-08-26): the 300,000 B threshold is crossed at transcript line **95** of `execute-repo`, whose first `Edit` was at line **133** — 38 lines of headroom, **zero commits**. `handback-followup.py:181` makes `route == "none"` a literal no-op, and the RELAY_LOG `HANDBACK:` prose line has **no machine reader** (`grep -rn 'HANDBACK:' relay/scripts/` = 1 hit, a comment). So re-dispatch reproduces the same investigation and the same empty handback, forever, with no accumulating signal. Rule 2c has no zero-commit branch. Note the pre-first-edit check point — the one the 63.9%/76.8% measurement demands — is precisely what GUARANTEES the empty handback in the case it was designed for. Owner's call: **(a)** distinct greppable zero-commit `HANDBACK:` form + escalate to `route="hard-split"` on the second occurrence (no new enum, no `handback-followup.py` change), or **(b)** make the PRE-FIRST-EDIT `warn` — which fires with 34 / 74 lines of headroom in both observed units — the actionable narrow-scope signal instead. NOT a defect in the delivered unit; the spec did not ask for it. <!-- id:5eeb -->
- [ ] **id:5eeb — spec hole: 2 of 5 sub-assertions in `tests/test_context_budget_handback_5eeb.sh` block (8) are VACUOUS** (pre-satisfied by the v12 contract, so they can never fail): `*heckpoint*` (1 hit in the OLD contract) and the `*'route'*'none'*` glob (matches anywhere across a 250-line document, in any order). **Consequence: the `route="none"` disposition — the exact thing the livelock finding turns on — is NOT pinned by the spec**; a future edit could delete it with the suite still green. The contract itself states it correctly today, so this is latent, not a present defect. Tighten to a phrase-level match. Handoff-authored, untouched by the executor. <!-- id:5eeb -->
- [ ] **id:1ccd -- `roadmap-lint` NO-ACCEPTANCE-NO-TWIN (id:213a) fires on 7 workable by-reference items.** S2/S4/S5/S6/S8/S9/S10 of the em-dash migration (id:098a, e8d4, 1a03, d0aa, ee31, 6958, da55) each carry a sub-bullet "Full acceptance, Done-check and Context: `docs/migration-em-dash-delimiter.md` §2" instead of inline clauses, so the lint calls them "structurally un-workable" when they are not -- the doc holds real Acceptance and Done-check text for every seam. The three CLOSED seams (S0/S1/S3) escaped only because a `**Spec**:` line was added to them. Owner's call, two ways to resolve: teach 213a to accept a cited-acceptance sub-bullet, or require every promoted seam to inline the clause. Left unresolved this is 7 permanent WARNs that train readers to ignore the check. <!-- id:1ccd -->
- [ ] **id:6e8d -- `meeting/SKILL.md` falls BETWEEN seams S6 and S7 of the em-dash migration.** S6 (id:d0aa) names five files -- `meeting/classify.sh`, `meeting/orphan-scan.sh`, `meeting/SKILL.md`, `Makefile`, `hooks/lane-vocab.claude-rule.md` (both the ROADMAP line and `docs/migration-em-dash-delimiter.md` §2 S6). The executor converted four and deliberately left `meeting/SKILL.md` untouched, reporting the reason honestly in RELAY_LOG: its em-dash lane tags are prose documenting the ACCEPTED old vocabulary for a human reader, and S6's acceptance clause only demands identical ROUTING, which review verified independently (classify.sh routes `[HARD - pool]`->POOL, `[INPUT - decision]`->HUMAN, `[INPUT - meeting]`->C3 exactly as their em-dash twins). That reasoning is defensible, but S7's normative-doc file list does NOT contain `meeting/SKILL.md` either -- so the file is now covered by no seam. S6 was NOT reopened (its acceptance is met); the residue is a scope question for the owner: does `meeting/SKILL.md` join S7's normative set (it is a skill spec, i.e. normative), or is it deliberately out? Resolve before S10 drops the dual-vocab tolerance. <!-- id:6e8d -->
- [ ] **id:62b4 -- the INSTALLED lane-ratchet rule block in `~/.claude/CLAUDE.md` is now STALE against `hooks/lane-vocab.claude-rule.md`.** The S6 close (id:d0aa) edited the rule doc to say the ratchet's old-vocab detection accepts either delimiter, but that block is copied into the global `~/.claude/CLAUDE.md` by `make install-lane-ratchet-claude-rule` -- and the installed copy still carries the pre-S6 wording. Verified by reading the live global CLAUDE.md during this review. Not fixed here: `~/.claude/CLAUDE.md` is outside this worktree and is a protected path a relay child must not write. Re-run `make install-lane-ratchet-claude-rule` (or `make install`) to refresh. Same install-drift class as the 2026-08-27 handover note. <!-- id:62b4 -->
- [ ] **id:ad2a -- the em-dash migration's recorded emit-side done-check is PROSE-BLIND and can never return 0, so a future reader will re-file `id:32f9` off it.** `id:1a03`'s own declared done-check, quoted verbatim in the now-closed `id:32f9` line (`ROADMAP.archive.md`), is a naive `git grep -nE` for an em-dash-delimited lane bracket over `relay/scripts/*.js *.mjs *.py`. MEASURED this review: the count fell 53 -> 49 across this window (the S5b emitter flip), and I read all 49 remaining hits individually -- every one is PROSE: docstrings and `#` comments in `handback-followup.py`(3), `backtest-historical.py`(6), `tracker/ledger-map.py`(5, incl. two `%s` error-message templates that quote the offending raw tag back to the user), `drain.mjs`(1), and log/prompt/refusal-reason string literals in `relay-loop.js`(32) + `handback-guard.mjs`(2) that deliberately name the RETIRED spelling so a child does not sweep for it (the id:7517/routed:2d94 failure). ZERO are ledger emitters. So no emit-side work is owed and `id:32f9` is genuinely closed. S10 (`id:da55`) already gates on the right thing -- `lane-delimiter-scan.sh --live-only` over the ledgers, which exits 0 here -- so nothing is broken; the risk is purely that the stale grep reads as an unfinished migration. Owner's call: correct the recorded done-check in `docs/migration-em-dash-delimiter.md` to cite the scanner, or leave it and accept the re-file risk. <!-- id:ad2a -->
- [ ] **id:9e86 -- `id:4ce8`'s fix added a DEAD branch, and its `refactor: none needed` self-report glossed it.** `relay/scripts/lane-delimiter-scan.sh:79-83` now tests `[[ ! -e "$f" ]]` and prints `lane-delimiter-scan: cannot read $f`; the pre-existing `[[ ! -r "$f" ]]` branch six lines below prints the IDENTICAL message with the identical `rc=2; continue`, and a non-existent path fails `-r` too -- so the new branch is unreachable-equivalent duplication. Only the middle `[[ ! -f ]]` branch (the directory guard) is load-bearing, and it is the only one the new test asserts. The executor's RELAY_LOG line calls this `one-line guard addition, no new duplication` for what is a 10-line addition of which 5 lines are redundant. NOT reopened: the acceptance (exit 2 + `not a regular file:` message, never an unbound-variable trace) is genuinely met and re-verified this review, and behaviour is identical with or without the dead branch. Fix is a 5-line deletion next time anyone touches the file. <!-- id:9e86 -->
