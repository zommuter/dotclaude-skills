# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

## Review 2026-09-09f (chain-end re-ask, run `relay-20260909-205831-5121` -- id:8123)

Window `relay-ckpt-20260909-2245..HEAD` (8 commits) -- the last *reviewer* checkpoint, not the
literal latest tag (`relay-ckpt-20260909-2256` is this chain's own executor checkpoint and IS
HEAD, so the literal rule would have given an empty window). One executor unit, `id:11a4`,
**verified GENUINELY green by spec-replay rather than by taking the suite's word**: its new spec
`tests/test_container_never_expected_red_11a4.sh` was re-run against the pre-fix
`tests/run-tests.sh` extracted from `relay-ckpt-20260909-2245` and reddens at `FAIL: (B) the
runner exited 0 with a real failure hidden under a @container umbrella` -- exactly the assertion
the item names -- while control case (A) still passes, so the fix is not an overcorrection. The
five retargeted `# roadmap:` headers are comment-only diffs; no assertion text changed anywhere
in the window. The SSOT twin the parked attempt broke, `tests/test_negative_case_syntax_ssot_7c82.sh`,
is PASS, and the live example the item was filed on, `test_title_rewrite_batch_acceptance_64f9.sh`,
is PASS rather than EXPECTED-RED. Tiers RUN: `make test` (runs `lint` first) **626 passed / 0
failed / 0 errored / 3 expected-red**, `make gaming-canary` (3/0), `make shard-canary` (6/0/0),
`make baseline-staleness` (advisory, see box below). RECORDED-SKIP: `make verify-negatives` and
`make check-statusline-deps` -- opt-in, not part of `make test`, not folded into the green claim.
No e2e/integration tier is declared (no `.github/workflows`). `gaming-scan.sh`: clean, no output.
Provenance greps (S2b.7/9/10): no `@owner-accepted`/`@owner-answered`/`answer-src` introduced or
modified. `orphan-scan --cross-ledger`: clean. `roadmap-lint`: 3 pre-existing WARNs (two b0b1
dead-gates, one no-acceptance-no-twin on `id:da55`), unchanged by this window.

- [ ] **`id:11a4` shipped a DELIBERATE NARROWING of its own written premise, and an executor made
  that call.** The item's body says a `@container` / `DECOMPOSED` / **`[INPUT - decision]`** item
  "is open indefinitely BY DESIGN", and its measured blast radius counted 9 files on that basis.
  The landed predicate in `run-tests.sh:item_open()` matches only `@container|DECOMPOSED` on the
  item's own line; the four remaining files (`test_dispatch_skill_countermand_9eb7.sh`,
  `test_dryround_single_definition_6217.sh`, `test_shrink_example_marker_hoist_8372.sh`,
  `test_tracker_derived_index.sh`) all key `[INPUT - decision]` ids (`9eb7`, `6217`, `8372`,
  `dcf3`) and were reclassified as legitimately-expected-red rather than fixed. I think the
  narrowing is RIGHT and I am not reopening on it: a container never ticks even after all its
  seams land, whereas a decision-gated item ticks when its decision lands, so the umbrella is
  permanent in the first case and temporary in the second -- and the reasoning is written into
  the new spec's header, not left implicit. Two things are still worth your eye. (a) One of those
  four, `test_dryround_single_definition_6217.sh`, is RED and swallowed RIGHT NOW under
  `[INPUT - decision] id:6217`, and stays swallowed until an owner ruling lands -- the item's
  "3 of them red and swallowed today" figure is therefore only partly discharged. (b) The scope
  cut was decided inside an execute turn, against the item's own text, which is the kind of call
  the ledger usually routes to you. Verified mechanically, not inferred: zero `tests/test_*.sh`
  now key an open `@container`/`DECOMPOSED` ROADMAP item. <!-- relates:11a4 -->

- [x] **The parked orphan `relay/orphan/relay-20260909-143257-21736-execute-11a4-0` is now fully
  SUPERSEDED but is still parked, still counted, and still suppressing.** `id:11a4`'s executor
  restarted FROM that branch and cherry-picked its commit, so every line it held is on `main`
  (its `item_open()` reshape, the 5 retargeted headers, the new spec) plus the twin fix the park
  existed to force. `relay-doctor` still lists it among 5 parked orphans for this repo, and per
  `id:7f4c` a parked orphan SUPPRESSES its item -- so a branch whose entire content has landed
  keeps voting. Disposition is a retire, not a merge: `worktree-retire.sh` on that branch. I did
  not run it -- branch deletion is destructive and outside a review child's remit. Same question
  applies to `docs/ledger-notes/11a4.md`, whose "Parked work" section I have UPDATED in place
  (edit declared in its header) because it asserted "the branch is not merged and nothing here
  ticks the item", which is now false and is exactly the breadcrumb a future executor would read.

  RESOLVED 2026-09-10 (`/relay human`, tier-(a)): the branch is GONE, so there is nothing left to
  retire or suppress. `git for-each-ref refs/heads/relay/orphan/` now returns exactly ONE ref,
  `relay/orphan/relay-20260909-143257-21736-execute-b437-0`, and that one is a different item
  still carrying unmerged residue (see the b437 note in the 2026-09-09d section).
  Re-check: `git for-each-ref --format='%(refname:short)' refs/heads/relay/orphan/`.

- [ ] **`make baseline-staleness` reports 1 of 230 baselined `TODO.md` entries below its recorded
  floor (371 chars of slack), and I did NOT regenerate.** It is pre-existing, not caused by this
  window. The printed remedy regenerates ALL rows for BOTH ledgers in one shot, which sets every
  floor to its current length -- tightening the one that shrank, but also re-baselining the other
  229 in the same act. That is precisely the shape the global grandfathering rule warns about
  (a baseline whose predicate re-grants silently), so it is a deliberate act for you or a
  `/meeting`, not a reviewer's cleanup. `ROADMAP.md`'s 37 entries are all current.

## Review 2026-09-09e (run `relay-20260909-205831-5121`, chain-end re-ask)

Window `relay-ckpt-20260909-2156..HEAD` (12 commits) -- the last *reviewer* checkpoint, not the
literal latest tag, which is this chain's own executor checkpoint `relay-ckpt-20260909-2225`. Two
executor units: `id:799f` and `id:6d7e`, **both verified GENUINELY green by spec-replay, not by
taking the suite's word.** Tiers: `make test` (runs `lint` first) **625 passed / 0 failed / 0
errored / 3 expected-red**, plus `make gaming-canary` (3/0), `make shard-canary` (6/0/0) and `make
baseline-staleness` -- all four RAN. `make verify-negatives` and `make check-statusline-deps` are
opt-in, not in `make test`: RECORDED-SKIP, not folded into the green claim. No e2e/integration tier
is declared (no `.github/workflows`). `gaming-scan.sh`: clean, no output. Provenance greps (§2b.7,
§2b.9, §2b.10): no `@owner-accepted`/`@owner-answered`/`answer-src` marker introduced or modified
anywhere in the window. `relay-doctor`: cross-ledger drift clean, roadmap-lint lane grammar clean.
`orphan-scan --shipped`: zero TICK-READY, so nothing was ticked on a scan's say-so.

- [ ] **`id:6d7e`'s executor converted a THIRD test case that the handoff's collateral survey
  explicitly said would not need converting -- the conversion is correct, but it means one case now
  reaches its subject only through the opt-in flag.** The handoff authorised exactly two rewrites
  (`test_self_transcript_wiring_ff30.sh` case 6, `test_self_transcript_workflow_nesting_c219.sh`
  case 7) and stated that `tests/test_self_transcript_tilde_marker_5295.sh` *"case 8 already
  tolerates a non-zero rc and stays green as written"*. The executor also added `--allow-ambiguous`
  to that file's **case 2**. I replayed the ORIGINAL file against the new implementation: it dies at
  case 2 with `2 transcripts matched ... refusing to guess`, naming case 1's `F_ME` and case 2's
  `F_ABSPROMPT` -- so the ambiguity is REAL and the executor's diagnosis is right, not an excuse.
  The case also still discriminates its own subject: with a tilde marker, `F_ABSPROMPT` (absolute
  prompt) can only become a candidate at all if tilde/absolute normalisation works, so a
  two-candidate ambiguity is itself the proof, and the surviving assertion (the newer
  `F_ABSPROMPT` wins) is unchanged. **Not flagged as gaming -- flagged as fixture coupling:** case 2
  now depends on case 1's leftover transcript and exercises the opt-in path rather than the default
  one. A one-line fixture isolation (build case 2 in its own session dir, or remove `F_ME` first)
  would restore it to a single-candidate test of normalisation alone, which is what it was written
  to be. Worth doing before someone reads the flag as evidence that normalisation needs it.
  <!-- relates:6d7e --> <!-- relates:5295 -->

- [ ] **The exit-code question the handoff raised against `id:6d7e` has now SHIPPED as exit 4 --
  the decision window is closed unless you reopen it deliberately.** The open box in the
  `Handoff 2026-09-09` section below asks whether the ambiguity refusal should mint a distinct exit
  code instead of reusing `4`. The executor implemented `4`, the spec pins only that the two
  MESSAGES differ, and `make test` is green on that basis, so the item is closed and archived.
  Nothing about that is wrong -- the handoff proposed 4 and nobody objected in time -- but a shipped
  exit table is a compatibility surface, so adding a distinct code later is a breaking change rather
  than a free choice. Decide now if you want one. <!-- relates:6d7e -->

- [ ] **Two open `[ROUTINE]` items are gated on `id:b0b1`, which lives ONLY in `TODO.md` and was
  never promoted, so nothing in `ROADMAP.md` can ever clear the gate.** `roadmap-lint.sh` reports
  this as `DEAD-GATE` for `id:540f` and `id:c179` (both `🚧`). It is a structural dead end, not a
  wait: the executor queue can never reach either item. Fix is promote `b0b1` to the execution queue
  (handoff C2's call -- lane must not be guessed) or re-target the two markers (`id:49e0`). Same
  scan also reports `NO-ACCEPTANCE-NO-TWIN` for `id:da55` (`[INPUT - meeting]`, no acceptance clause
  and no TODO twin, so structurally un-workable, `id:213a`). Pre-existing, not from this window;
  surfaced because both make items permanently undispatchable while still counting as open.

- [ ] **`make baseline-staleness` reports the TODO.md ledger ratchet STALE and I deliberately did
  NOT regenerate it.** 1 of 230 baselined `TODO.md` entries now sits BELOW its recorded floor (371
  chars of total slack, 0 orphaned); `ROADMAP.md`'s 37 entries are all current. Regenerating records
  the new, lower floor -- which is the ratchet working as designed after a shrink -- but it is still
  an action that LOWERS a guard's threshold, and the global CLAUDE.md rule about grandfathering-vs-
  ratchet says that is the owner's ledger-shrink program (`id:0d7c`/`id:2d17`), not a review turn's
  housekeeping. The command the tool prints appends to `relay/head-length-baseline.txt`; note its
  own warning that regenerating only one ledger DELETES the other's rows.

- [x] **Three cross-repo inbox items are addressed to THIS repo and have never been ingested --
  surfaced, not filed, because filing them means inventing their scope.** `scan-routed.sh` reports
  them as dead-letters: `routed:fa6d` (running Workflow/pool children ARE addressable mid-run via
  SendMessage to the raw agent id from `agent-<id>.meta.json`; `ListAgents` does not list them until
  you send, so its silence is not evidence -- verified end-to-end on run
  `relay-20260909-212820-29294`; `docs/relay.md` and `inject.sh --prompt-only` both understate what
  is reachable), `routed:1107` (`context-budget.sh` thresholds are hard-coded for a 200k window, so
  every `claude-opus-5[1m]` child gets a spurious `handback` verdict -- in zom.fi the baseline
  transcript alone exceeds the 300000 B default before any work, making executor rule 2c an
  unconditional zero-commit livelock there) and `routed:526b` (cross-session "last one switches off
  the PC" coordination; the owner sketched two marker shapes and the note is explicit that it should
  COMPOSE `heartbeat.sh` + `claim.sh`, not build new lockfile machinery). `routed:1107` looks like
  the one with live blast radius. Run `scan-routed.sh --apply` to write stubs, or file them by hand
  with the lanes you want -- an unattended review picking lanes for three items is exactly the
  overstep the global CLAUDE.md forbids.

  RESOLVED 2026-09-10 (`/relay human`, tier-(a)): all three ARE ingested now and all three are
  drained from the inbox -- `routed:fa6d`, `routed:1107` and `routed:526b` each appear in
  `TODO.md` and none appears in `~/.claude/projects/todo-inbox.md`. No lane was invented by this
  turn; the filing happened upstream. The one inbox item targeting this repo TODAY is a NEW,
  unrelated one (`routed:b015`, from quovadis, on `relay-state-write.sh` having no `repo-add`).
  Re-check: `bash relay/scripts/inbox-scan-repo.sh dotclaude-skills` and
  `grep -c 'routed:fa6d\|routed:1107\|routed:526b' TODO.md`.

## Review 2026-09-09d (run `relay-20260909-205831-5121`, chain-end re-ask)

Window: the literal latest tag `relay-ckpt-20260909-2121` IS HEAD (the chain ended on a handoff),
so that window is empty and vacuous. Widened to the last *reviewer* checkpoint,
`relay-ckpt-20260909-1939`..HEAD -- 21 commits, no executor unit among them: one handoff (promoting
`id:6d7e`) and two reconcile integrates of auto-parked residue. **No item was closed this review, so
nothing was verified-green and the §2d over-reach check has no closed item to test.** Tiers: one
declared tier, `make test` (runs `lint` first) -- **623 passed / 0 failed / 0 errored / 5
expected-red** (`4839` x2, `6217`, `799f`, `6d7e`, all open items). `make verify-negatives` and
`make check-statusline-deps` are opt-in and NOT in `make test`; RECORDED-SKIP, not folded into the
green claim. No e2e/integration tier is declared (no `.github/workflows`). `gaming-scan.sh`: clean
over both the literal and the widened window. Provenance greps (§2b.7/2b.9/2b.10) CLEAN -- no
`@owner-accepted` / `@owner-answered` / `answer-src:` minted or modified. §2b.1 resurrection: the one
modified closed-item test, `tests/test_self_transcript_tilde_marker_5295.sh`, changed **comments
only** -- no assertion touched; legitimate. `relay-doctor`: cross-ledger drift clean, `roadmap-lint`
grammar clean (2 pre-existing DEAD-GATE warns on `540f`/`c179` and 1 NO-ACCEPTANCE-NO-TWIN on
`da55`, all previously known).

- [ ] **`id:6e02`'s observe-first gate has FIRED -- this review child's own worktree and branch were
  destroyed TWICE mid-run, while it held the repo lease.** `id:6e02` was filed 2026-07-01 as
  `[INPUT - meeting]` and closes "Observe-first: first logged instance". That is no longer true.
  Same repo, same shape, same ~1-minute window: the pre-created worktree
  `relay-20260909-205831-5121-review-repo-0` and its branch vanished mid-audit while `claim.sh peek`
  still showed this run holding the lease **with that exact worktree path recorded in the claim**;
  re-provisioning produced a replacement that was destroyed again about a minute later. Only the
  third attempt survived, because it made an empty marker commit immediately -- the workaround the
  2026-07-01 note already describes. **The new evidence is that a shipped tool actively RECOMMENDS
  the deletion:** `relay-doctor.sh`, run by this child minutes before the first reap, listed the
  child's own live worktree under `RETIRABLE RESIDUE ... 4 retirable item(s) -- no work at risk;
  retire with worktree-retire.sh --expect-merged`. "No work at risk" was false as printed. A review
  child is the worst case, because it accumulates no commits until its ledger edits at the very end,
  so its tip equals `main` for nearly its whole life and is `branch -d`-deletable throughout.
  **`id:7570` does not cover this** -- it is keyed on the same zero-commit predicate, so it is inert
  for exactly the window in which a review child is vulnerable. **Your call, and the lane stays
  `[INPUT - meeting]`:** the note poses two options, and the marker-commit-at-birth one is now much
  the cheaper to evaluate -- `provision-worktree.sh` is already the single pre-dispatch creation
  point (`id:34b7`), so it is one `git commit --allow-empty` in one place and closes the window
  structurally, rather than asking every present and future sweep to remember to consult the claim.
  That is a cost argument, not a recommendation to adopt it; consulting the claim may still be the
  right or the additional answer. Full recurrence write-up appended to `docs/ledger-notes/6e02.md`
  (edit declared in its header). <!-- id:6e02 -->

- [ ] **`id:0165`'s implementation landed GREEN on main inside an UNVERIFIED park labelled for a
  different item, and the item's lane disagrees across the two ledgers.** The residue commit
  `18359d7a` says *"for worktree ...-execute-aa5e-0"*, but its entire content is `id:0165`'s work:
  62 lines adding the `(b3)` sed-TOCTOU and `(b4)` awk-failure mutation-pinning cases to
  `tests/test_workflow_check_hardening.sh`. The 20:42 reconcile merged it to main and those cases now
  pass, so `id:0165`'s two named unpinned mechanisms appear to be pinned. **I did not tick it**, for
  two reasons: it arrived through a path stamped "do NOT treat as reviewed", and the item is
  `[INPUT - decision]` in `ROADMAP.md:177` but `[ROUTINE]` in `TODO.md:869`. **That lane divergence is
  invisible to `orphan-scan --cross-ledger`, which compares checkbox state and both are `- [ ]`** --
  worth knowing independently of this item. Needs your call on whether the landed cases close it and
  which lane is correct. <!-- id:0165 -->

- [ ] **`id:7f4c` is `[ROUTINE]` in TODO but its acceptance clause does not name a fix -- it asks the
  reader to pick one of three.** Added to `TODO.md` this window with a full Acceptance and Done-check,
  which is why it reads as execution-ready, but the acceptance literally says *"Pick one and state
  which: (a) ... (b) ... (c) ..."*. Its own note recommends (a) and rejects (c). Per review.md §5b I
  did **not** mini-handoff it to `ROADMAP.md`: promoting it as `[ROUTINE]` would settle a live design
  choice on your behalf, which is the delegated-verdict class. It is load-bearing right now -- it
  describes the exact orphan-suppression lockout this repo is sitting in (3 of 6 actionable
  `[ROUTINE]` ids suppressed today). Either pick (a)/(b) so it can be promoted, or re-lane it
  `[INPUT - decision]`. <!-- id:7f4c -->

- [ ] **Five parked orphans are suppressing 3 of this repo's 6 actionable `[ROUTINE]` items, and two
  of the five are unnamed.** `discover-repo.sh` publishes `suppressed_item_ids = [11a4, b437, c655]`,
  leaving only `aa5e`, `799f`, `6d7e` dispatchable. Per `docs/ledger-notes/7f4c.md` these are NOT one
  class and must not be swept together: `c655` is a deliberate, owner-ratified park kept as the
  documented restart point, whereas `11a4`/`b437` are run-1 context-death residue. The two
  `-execute-repo-0` branches (from runs `relay-20260908-231617-32609` and
  `relay-20260909-185356-12943`) are unnamed -- they carry no item id in their key, which is itself
  the `id:7f4c` unnamed-unit signature. Disposition is a `/relay reconcile` decision, i.e. yours.

## Review 2026-09-08 (run `relay-20260908-174448-4421`, chain-end re-ask)

Window `relay-ckpt-20260908-1835`..HEAD -- the last *reviewer* checkpoint, not the literal latest
tag, which is HEAD itself and would have given an empty (vacuous) window. Two work units in it:
`id:8679` (strong-execute, opus) and `id:32ba` (executor, sonnet). Tiers: one declared test tier,
`make test` (runs `lint` first) -- **604 passed / 1 failed / 7 expected-red**; the single failure is
the finding below. `make verify-negatives` is opt-in and NOT in `make test`; ran on the file
`id:32ba` touched. No `e2e`/`integration` tier is declared (no `.github/workflows`), so nothing was
silently skipped. `gaming-scan.sh` raised one `ADDED_SKIP` -- a FALSE POSITIVE, matched on the word
"skips" in an English sentence in `tests/test_count_indented_ids_8679.sh`'s header comment, not on a
skip directive. Provenance greps CLEAN: no `@owner-accepted` / `@owner-answered` / `answer-src:`
minted or modified this window. `relay-doctor`: cross-ledger drift clean, `roadmap-lint` clean.

- [ ] **`id:8679` was ticked while its own RED spec was RED, and the next executor mis-attributed
  the failure.** `tests/test_indented_id_population_8679.sh` fails at assertion (0). It was
  EXPECTED-RED (harmless) at the strong unit's own commit, so that unit's "604/0/8" self-report was
  accurate when written; the tick three commits later silently converted it into a hard suite
  failure, and the `id:32ba` executor then recorded it in `CHANGELOG.md` and in checkpoint
  `relay-ckpt-20260908-1947` as **"1(pre-existing unrelated)"**. It was neither: it carries
  `# roadmap:8679`, the id closed three commits earlier in the same chain. **Disposition taken, and
  it is a judgment call you may want to reverse:** I did NOT reopen `8679`. Its ratified acceptance
  and done-check are met, and I reproduced both rather than taking them on trust -- the counting rule
  is committed, `--file TODO.md` names its as-of commit, the meeting note cites it, and run against
  the RED spec's OWN fixture the tool returns exactly the specified population `{a1a1,a2a2,a3a3}`
  with cases B/C/D/F/G excluded. The spec additionally asserts an INVOCATION/OUTPUT contract (a
  positional path, enumeration in default output, a printed rule) that the item never asked for.
  So I filed that gap as `id:0f0a` and retargeted the spec file's `# roadmap:` header to it, which
  restores EXPECTED-RED. **If you read the RED spec as part of 8679's contract rather than an
  over-specification of it, then 8679 should be reopened instead and `0f0a` folded back into it.**
- [ ] **A delegated unit discharged one of your explicit rulings -- confirming this is yours, not
  mine.** The `id:8679` unit appended a `RECONCILED 2026-09-08` block to the ratified meeting note
  `docs/meeting-notes/2026-09-01-2226-ledger-line-shrink-format.md` and wrote that your UNVERIFIED
  ruling on the figure 11 "is discharged". Mechanically I find it sound and reproducible: 11 was the
  CHECKBOX subset of the 21, `e6e3ff70` promoted exactly those, leaving 10, and every figure
  re-derives from `tools/count-indented-ids.py --rev <sha>`. Two reasons it still wants your eye
  rather than a silent pass. Your ruling was "UNVERIFIED **until** the two scopes are reconciled",
  so its own terms are self-clearing and this looks legitimate -- but a delegated agent decided that
  the condition was met, which is the shape CLAUDE.md tells us not to settle unratified. And the
  same block declares one of `8679`'s own acceptance premises ("the shrink itself moved the
  population") **FALSE** on measurement; that is a correction to a ratified paragraph, appended
  below it with the original left verbatim. Nothing to fix if you agree -- this is a ratification
  checkpoint, not a defect.

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
- [x] **`id:dd44` cites `id:4983` as an instance of "a checker that derives its notion of correctness from the thing it checks cannot fail" -- for the LANDED test that premise does not hold, and the hazard-class item should not be built on it.** `TODO.md:848` (INBOUND `routed:4dc2` from loderite) names three instances, the third being *"your lane check borrowing the shrinker's own regex, id:4983"*. Measured against the file: `tests/test_lane_grammar_ssot.sh` derives its EXPECTED set by scraping `relay/references/hard-lanes.md` (the SSOT doc, `SSOT_DOC` at line 56) and imports `_LANE_PATTERNS` only as the SUBJECT under test (line 145). Expectation and subject are different sources, and the test genuinely fired RED against the pre-fix implementation -- a self-referential check could not have. **The narrower residue IS real and is worth keeping in `dd44`:** the doc SCRAPER (`DASH_RE`, line 90) uses the same permissive `[A-Za-z0-9 _./-]+` bracket shape the fix just removed from the shrinker, so a lane the SSOT declares in an unusual spelling would be invisible to the scraper AND to the consumer, and assertion `(a)` only guards against total vacuity (`len(ssot) < 5`). That is a coverage limit, not a tautology. **Confirm the correction so `dd44` is filed on the accurate claim.** **CONFIRMED 2026-09-10 (`/relay human`, tier-(a)): the correction holds and `id:dd44` should be filed on the narrower claim.** Re-derived by reading the file rather than adopting the box: `tests/test_lane_grammar_ssot.sh` exports `SSOT_DOC=relay/references/hard-lanes.md` and scrapes it for the EXPECTED lane set, then imports `_LANE_PATTERNS` from `tools/ledger-shrink.py` only as the SUBJECT under test -- two different sources, so the self-referential premise is false for the landed test. The scraper-permissiveness residue named in this box is the accurate claim and is what `dd44` should carry. Re-check: `grep -n 'SSOT_DOC=\|_LANE_PATTERNS' tests/test_lane_grammar_ssot.sh`. <!-- id:dd44 -->
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

- [x] 🔴 **The `id:f91a` hazard is LIVE right now: this repo's MAIN checkout carries 35 lines of uncommitted, unreviewed work that no worktree contains, and it will DEFER this repo from every later pool round.** Observed at 11:56 while confirming my own worktree was clean: `git -C ~/src/dotclaude-skills status` shows `M meeting/md-merge.py` (mtime 11:52) and untracked `tests/test_md_merge_multiline_line_guard_f833.sh` (mtime 11:54) -- both written DURING this review (started 11:44), neither by me (I only ever invoked `md-merge.py`, never edited it, and all my writes are in my worktree and committed at `486e6737`). The work itself looks sound and deliberate: a real defect fix for `id:f833` (`md-merge.py update-ids` replaces only the marker line, so a multi-line `line` payload DUPLICATES an item instead of updating it -- found in kienzler-solutions' TODO.md) with a matching hermetic test that deliberately carries no `# roadmap:` header. So this is MISLOCATED, not bad: the conventions.md `id:f682` recovery doctrine says favour salvage over discard, and nothing here should be reverted. Two facts make it urgent rather than cosmetic. (1) It is the exact `verify-isolation.sh` failure signature -- the sibling execute worktree `relay/relay-20260907-100619-27900-execute-4839-0` is CLEAN and sits **0 commits beyond main**, i.e. an empty worktree beside a dirty main checkout, which is precisely the shape `id:f682` describes as a silently-wrong 'commit in the worktree' self-report. (2) A dirty main checkout trips the `id:aa93` dirty-guard, so every later pool round DEFERS this repo -- the self-perpetuating backlog review.md §5 exists to prevent. I did NOT commit it (it is another actor's in-flight work, unreviewed, and committing it under my review's checkpoint would launder it as reviewed) and did NOT revert it. I also cannot prove WHO wrote it: no `execute-4839` process survives, and the run's children share one `CLAUDE_SESSION_ID`, so authorship is inferred from timing and location, not established. There is no `id:f833` item in this repo's TODO.md or ROADMAP.md -- only a `routed:f833` mention inside `id:689e` -- so if this came from a cross-repo child it also bypassed the shared-inbox rule. Owner/integrator call: salvage-commit it in the main checkout under the held lease, or hand it back to whoever owns it. <!-- relates:f91a --> **RESOLVED 2026-09-10 (`/relay human`, tier-(a)): the disposition was SALVAGE, and the hazard this box raised is gone.** Both artefacts are on `main` and the main checkout is clean of them: `git ls-files tests/test_md_merge_multiline_line_guard_f833.sh` returns the file, and `8b40b1fc` (the `id:f272` commit-and-park residue carrying the `md-merge.py` f833 multi-line guard) is an ancestor of HEAD. So the `id:aa93` dirty-guard is no longer deferring this repo, which is what made the box urgent. **Residue deliberately NOT closed with it, and it is the owner's:** the content reached `main` through a commit labelled `WIP UNVERIFIED ... do not treat as reviewed`, so the f833 guard and its test have still never had a review pass -- that is a separate question from the checkout hygiene this box was filed on. Re-check: `git merge-base --is-ancestor 8b40b1fc HEAD`. <!-- id:b923 -->

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

## Review 2026-09-08 (hardening audit of id:1b0e / id:e044 / id:ad67, window `relay-ckpt-20260908-0958`..HEAD)

Verdict: **sound with caveats**. All three items' functional acceptance criteria are genuinely
met, and I verified that BY MUTATION rather than by reading: `'use strict';` removed from the
prologue reddens `(d1)`, and removing BOTH id:1b0e mechanisms reddens `(b1)` at exactly the
substring the file's own `# fails-against-assertion:` declares. `gaming-scan.sh` clean;
`orphan-scan.sh --cross-ledger` clean; provenance greps for `@owner-accepted` /
`@owner-answered` / `answer-src:` over the window: none minted; `relay/scripts/relay-loop.js`
byte-unchanged; full suite re-run here at **597 passed, 0 failed, 0 errored, 8 expected-red**;
`roadmap-lint` carries 4 DEAD-GATE + 1 NO-ACCEPTANCE warning, all pre-existing and none on this
window's items. All mutants were built in an isolated mirror root; the tracked helper was never
modified.

**No false GREEN exists in the shipped scanner, and I looked hard for one.** Every input I could
construct where the lexical state goes wrong in the fail-OPEN direction (a backtick inside a
double- or single-quoted string, an escaped backtick, `/*` inside a string, three backticks on a
line) still returns non-zero, because `export`/`import` declarations are SyntaxErrors inside a
function body and `node --check` is a hard backstop. What degrades is the MESSAGE: the loud
refusal naming the source file is replaced by a node error naming the temp path
(`/tmp/tmp.XXXXXX.js:3`), which is precisely what assertions `(b2)`/`(c4b)` exist to prevent
given that call sites redirect stderr (26 of 74 `workflow_node_check` invocations under
`tests/`, measured here; the `id:62c9` note's "~40 of 48" counts differently and neither figure
was re-derived for the other's method). The single construct for which a false green
IS reachable is `import.meta` -- invisible to the regex (it requires whitespace after the
keyword) and ACCEPTED by `node --check` inside an async function in a `.js` script (measured,
rc=0). Latent: zero occurrences in `relay-loop.js`. Recorded in `docs/ledger-notes/8627.md`, not
filed as work.

**Readability guard: complete, measured.** FIFO refused by `[[ -f ]]` with no hang (returns
immediately under an 8s kill); directory refused; symlink to an unreadable target correctly
caught by `[[ ! -r ]]`; empty file and a file with no trailing newline both behave; NUL byte and
200 KB of binary both rejected. `sed_rc` was hand-verified to propagate out of the redirected
brace group (measured `sed_rc=2`), so the TOCTOU backstop does work -- it is simply untested by
the suite (now `id:0165`). No temp-file leak on any early-return path. The two `rm -f "$tmp"`
sites are a `CLAUDE.md` style nit only (`rm --` is preferred for a known file); not worth a
commit of their own, folded into `id:8627` if that item touches those lines.

**Filed as mechanically actionable rather than boxed here:** `id:8627` (the scanner goes blind
over 1,251 of `relay-loop.js`'s 4,930 lines because two `//` comments containing `relay/orphan/*`
open a block-comment state that runs 520 and 731 lines; plus three surviving false refusals and a
header comment that again claims more than the code does) and `id:0165` (the id:1b0e spec passes
with either mechanism removed).

- [ ] **Should `id:e044` be REOPENED, or does `id:8627` carry its unfinished half?** `id:e044`'s
  acceptance had five clauses. The four functional ones are met and specced by
  `tests/test_workflow_check_hardening.sh` `(c1)`-`(c4)`. The fifth -- *"Fix the helper's own
  comment in the same change -- it currently states a guarantee the code does not provide"*, which
  the note itself flags as NOT mechanically checked -- is **not** met: the rewritten header now
  claims *"a real lexical scan (not just a line-initial substring) confirms"* (it is a per-line
  backtick-parity heuristic) and *"A `//` line comment [...] never trips this refusal either
  way"* (a `//` comment containing `/*` opens a 520-line blind window on the live file, measured).
  The inline comment further down is honest, so the file contradicts itself. I did NOT untick
  `id:e044`: its spec is green, unticking would confuse the ledger, and `id:8627` names the same
  correction as an acceptance clause. But that is a judgement about ledger hygiene, not a fact,
  and review.md says an unmet acceptance clause reopens the item -- so it is yours, not mine.
  <!-- relates:e044 --> <!-- relates:8627 --> <!-- id:07ef -->

**Tooling note, found while trying to resolve the box below.** The stale `id:62c9` box carried a
BARE `id:62c9` rather than the owning `<!-- id:62c9 -->` form, so `md-merge.py update-ids` cannot
address it at all -- it refuses loudly (`regex_sub id(s) not found`), correctly, per the `id:3743`
anchoring rule. It was resolved via `update-sections` instead, which is still under the flock. Any
future REVIEW_ME box that wants to be machine-resolvable needs the HTML-comment marker.

- [ ] **`id:02fe` names landed, tested work that has NO ledger line anywhere — the token exists
  only in a commit message, a test filename, and one `relates:` edge.** Commit `f6fa91d1`
  ("a repo name is not the string-matcher's to choose (id:02fe)") and
  `tests/test_repo_section_quoting_02fe.sh` (160 lines, green) fix the `[repos."zom.fi"]`
  quoted-section class end to end, and open TODO item `id:9220` carries `relates:02fe` pointing
  at it. But `grep 02fe` over `ROADMAP.md`, `ROADMAP.archive.md`, `TODO.md`, `TODO.archive.md`,
  `REVIEW_ME.md`, `REVIEW_ME.archive.md` and `RELAY_LOG.md` returns exactly one hit: the
  `relates:` edge itself. So `orphan-scan`'s exact-token correlation finds nothing, the
  single-id-two-views cross-ledger check has nothing to compare, and `9220`'s typed edge points
  at a token no ledger owns. **No code defect and nothing to reopen** — the work is done and the
  test passes (verified: the file carries no `# roadmap:` header, so its failures always count
  and it is not silently carved out). The question is the RECORD: backfill a `- [x]` line into
  `ROADMAP.archive.md` reusing `02fe` so the edge resolves, or accept that a fix landed with no
  ledger entry. Owner's call — a reviewer should not mint a closed item's history unasked.
  Found by relay review, run relay-20260908-174448-4421.

## Review 2026-09-08b (chain-end re-ask, run `relay-20260908-231617-32609` -- id:8123)

- [ ] **An item was recorded CLOSED and ARCHIVED while its own spec test was RED, and the executor had explicitly said it was not done -- `id:64f9` reopened by hand, mechanism filed as `id:963c`.** The execute unit rewrote 4 of 46 over-budget titles and wrote in `RELAY_LOG.md`: "Leaving the item open, unticked, for a follow-up batch". It then returned `64f9` in `worked_ids`, which is what the dispatch prompt asks for -- `relay/scripts/relay-loop.js:3202` defines that field as the ids "you closed/**advanced**". The integrator's `roadmap-tick.sh` has no notion of "advanced": `relay/scripts/integrate.sh:803-825` feeds every returned id straight to it, so the box flipped and `archive-done.sh` swept the item into `ROADMAP.archive.md` in the next commit. **Nothing about this was dishonest** -- the executor reported accurately and the driver did exactly what it is written to do; the two halves simply disagree about what the field means. Caught here because ticking the box removed its EXPECTED-RED carve-out and `make test` went 610/1-failed; reopening restored 610/0/5-expected-red. This review restored the live item to `ROADMAP.md` and left a plain-comment tombstone (no `id:` marker, so nothing double-counts) at the archive line. **The owner's call, NOT taken here:** `id:963c` asks only for the cheap mechanical guard the repo already documents (`CLAUDE.md` §Testing: tick the box, then `make test` must be fully green). Whether the child return contract should instead grow a real closed-vs-advanced signal -- which would touch every child of every unit type -- is a design decision I have deliberately left open.

- [ ] **Two prompt-injected relay docs still described the integrate push as `git-lock-push.sh --ff-only --all`, which is the auto-publish shape `id:f66e` forbids -- corrected this review, please confirm the correction rather than the wording.** `relay/references/conventions.md:38` (the "Relay invariants" block, whose text is injected into child prompts) and `relay/SKILL.md:501` (the hand-integration recipe) both said `--all`. Verified against the code before changing either: `integrate.sh` has selected remotes via `--remote` since `id:4d44` (see its lines 962-968, 1056), and `relay-reconcile.sh` since this window's `id:4263`. So both lines were stale DESCRIPTIONS of already-narrowed code -- but they are the copies an agent actually reads, so a child following them literally would have published. `relay/SKILL.md:606` (the reconcile recipe) was made stale by this window specifically and was updated to match `id:4263` including its declared scope limit. I have flagged rather than quietly filed this because editing an *invariants* block is exactly the derived-doc-vs-ratified-source hazard, and the wording should be yours if you want it different.

## Review 2026-09-09 (chain-end re-ask, run `relay-20260908-231617-32609` -- id:8123)

- [ ] **`make verify-negatives` was RED on both of its relative declarations, and the verdict it printed -- VACUOUS, "demonstrates no killing power" -- was FALSE about the tests and TRUE about the declarations. Fixed and guarded this review (`id:0801`); flagging because the class is subtle.** `tests/verify-negative-cases.py` exists to make "green for the wrong reason" impossible. It reported `test_roadmap_lint_duplicate_detail_pointer_78e6.sh` VACUOUS -- the file the executor had shipped hours earlier, this window's only substantive work. It was not vacuous: its declaration read `# fails-against-rev: HEAD~1`, and by the time the integrator had added four commits on top, `HEAD~1` named a revision that ALREADY CONTAINED the fix. Re-pinned to the immutable sha (`4d133c76ce48`) it reports `red-there OK` at its declared assertion, so `id:78e6` is genuinely verified. Its sibling `test_roadmap_lint_follows_pointer_e95b.sh` had rotted the same way earlier (pinned to `8115c2ae73a8`). **Why this is worth your eye and not just a fix:** the failure arrives from the DECLARATION side, and its output is indistinguishable from the real thing -- a run that says "no killing power" about a test whose killing power was never exercised. A reader trusting that verdict would have concluded the id:78e6 fix was unpinned. The guard now REFUSES a moving rev as a CONFIG ERROR, deciding immutability on the BASE ref before any `~`/`^` traversal, so `<sha>^` passes and `HEAD~1`/`main~3` do not. Census: 107 declarations, 105 were already hex, so the corpus is clean under it today. **Known residue, stated rather than implied covered:** a bare BRANCH name with no traversal is still accepted, because the tag case (`relay-ckpt-*`) needs that allowance and tightening it to "hex or an existing tag" needs a repo handle the parser does not take. No declaration uses a bare branch today.

- [ ] **`id:cb9a` had been genuinely green since the 2026-09-08 reconcile but was left unticked -- ticked this review after a full resurrection check.** The `[ROUTINE]` seam (surface todo-conformance's INERT stderr from relay-doctor; widen install-drift to all of `relay_FILES`) landed in `93c8cf46`/`97642d53`, whose diff touches only `RELAY_LOG.md` and `relay/scripts/relay-doctor.sh` -- the RED spec `tests/test_relay_doctor_sees_manifest_gap_4839.sh` is untouched since handoff (`05606f6f`, plus one lint fixup). Verified both directions rather than trusting the green: the spec passes on the current tree, and against `93c8cf46^`'s relay-doctor it fails at assertions (a) and (c) with the messages it was written to emit. Its two `id:4839` siblings `id:c655` and `id:aa5e` are correctly still RED and stay open. **Nothing to reopen; the note is about the ROUTE** -- a fix that lands through the reconcile path never reaches `roadmap-tick.sh`, so its box stays unticked with no signal anywhere that it is done. That is the mirror image of `id:963c` (the tick that fires when it should not), and it is the one you should decide about, not the tick itself.

- [ ] **`roadmap-lint` warns on three open items and none is new work from this window; two are the same DEAD-GATE, waiting on a promotion only a handoff may make.** `id:540f` and `id:c179` are both `gated-on:b0b1`, and `b0b1` lives ONLY in `TODO.md` -- never promoted to the execution queue -- so nothing in `ROADMAP.md` can ever clear either gate. The lint's own advice is to promote `b0b1` or re-target the marker, and it says explicitly that the lane is handoff C2's call and must never be guessed, so this review left both alone. `id:da55` (the em-dash S10 seam B) fires NO-ACCEPTANCE-NO-TWIN: no Acceptance/Tests/Done-check clause in its body and no TODO twin, i.e. structurally un-workable as written. It is `[INPUT - meeting]` and `gated-on:6958`, so it is not executor work either way, but it will keep firing until someone gives it a done-check.

- [ ] **`id:740a` reproduced LIVE this review, on the real `ROADMAP.md`, by a reviewer following the documented procedure -- evidence for an item that until now rested on reading the code.** `md-merge.py`'s `insert_after` anchors on the id-bearing LINE, not the item BLOCK. Inserting a new item after `id:963c` -- which is a WRAPPED item, head line plus `**Acceptance**` / `**Done-check**` / `**Context**` continuation lines -- put the new line BETWEEN `963c`'s head and its own continuations, so for one commit `963c`'s acceptance criteria belonged, by position, to a different item. Nothing complained: `roadmap-lint` stayed at its 3 pre-existing WARNs before and after, because every line is individually well-formed and no check reads block membership. I noticed by eye while re-reading the file, and fixed it in `de39d41b`. **Why it is worth recording rather than just fixing:** the corruption is silent, it is produced by the tool the ledger rules REQUIRE for these files (CLAUDE.md: TODO/ROADMAP go through `md-merge.py`, and Edit "bypasses the flock exactly as `sed -i` does"), and the shrink programme is actively converting items into exactly this wrapped shape -- so the population that can be hit is growing. `id:740a` is open in `TODO.md:1088` and is `[ROUTINE]`; this is the first observation of it damaging a live ledger.
- [ ] **`id:5ad9`'s ROADMAP Done-check names a test file that does not exist and never did — `tests/test_integrate_remote_gate_binds.sh`.** Re-verified independently this review: the behaviour is real (`relay/scripts/ratify-queue.sh` `pending-blocking` at line 558, `relay/scripts/integrate.sh` step 8's `id:5ad9` block at line 1100, both on the real push path, not a harness) and the RED spec that covers it, `tests/test_ratify_gate_binds_remote_7408.sh`, has exactly ONE commit in its history (`6433b65c`, the C3 handoff that authored it) — so it was never touched to make it pass, and it runs green standalone. The item is legitimately closed and archived. What is worth a human's eye is the AUTHORING defect, not the close: a Done-check that names a nonexistent file cannot be executed as written, so "done-check passed" for this item rested on a reviewer's judgement of substance-equivalence rather than on running the named command. That is the id:d35a silent-no-op shape one level up — a done-check nobody can run is indistinguishable from one that passes. Consider whether handoff C3 should refuse to author a Done-check naming a test path it did not also create.

- [ ] **`make baseline-staleness` prints a remedy that would SILENCE 13 currently-over-budget items — measured this review, not inferred; do not run it as printed.** The detector reports one stale row (`ee62`: current 169 vs a baselined ceiling of 540, "the floor forgives 371 more chars than reality requires") and instructs `relay/scripts/todo-conformance.sh --regen-length-baseline TODO.md > relay/head-length-baseline.txt` plus the ROADMAP append. I ran both regens to a scratch file and diffed them against the committed baseline rather than writing anything. Result: the regen would TIGHTEN zero rows and LOOSEN zero rows. What it would actually do is drop `ee62`'s row (correct and strictest — the file's own header says a row exists only for a line that was OVER the 500-char budget at capture time, and `ee62` is now 169 chars) and **MINT 13 new TODO rows, each grandfathering an item that is over budget TODAY at its current length**: `3294`=1727, `3770`=2209, `3c04`=698, `4cd4`=1618, `59d1`=1518, `6740`=1000, `6a5d`=512, `6ead`=994, `740a`=1458, `c3a2`=529, `d29b`=761, `ee5e`=1259, `f833`=1429. ROADMAP regen adds 6 more of the same shape. That is the id:0d7c re-grandfathering channel exactly as CLAUDE.md's "a grandfathering mechanism is not a ratchet" heuristic describes it: the remedy is keyed on the ID, so it cannot express "may only get better", and running it converts 13 loud over-budget items into permanently forgiven ones in a single commit that looks like routine baseline hygiene. **The finding is the REMEDY TEXT, not the stale row.** Reclaiming `ee62`'s 371 chars is worth ~371 chars; the printed way to reclaim them costs ~15,700 chars of newly-forgiven regrowth. A safe regen needs to be row-scoped (rewrite only rows that TIGHTEN, never mint) or the message needs to say what it is about to grandfather. Disposition is the owner's; nothing was written by this review.

## Review 2026-09-09b (chain-end re-ask, run `relay-20260909-091623-10249` -- id:8123)

- [ ] **`id:8627` is verified genuinely green, and the strongest evidence is that its RED spec was proven to redden at the exact assertion it declares -- which matters because the SAME executor wrote both the spec and the fix, in one commit.** There was no handoff-authored spec to check the work against, so "the suite is green" would have been the executor grading its own homework. `make verify-negatives FILES="tests/test_workflow_scan_lexical_8627.sh"` was run this review and reports `red-there OK` against `67b1139f` firing `(b2) the refusal does not name the fixture file` -- exactly the `# fails-against-assertion:` the file declares, not an earlier assertion and not a fixture-sanity abort. Over-reach (review.md §2d) checked against the ratified source `docs/ledger-notes/8627.md` rather than the ROADMAP restatement: every clause of its Acceptance is met and nothing beyond it shipped -- the `rm -f` -> `rm --` fold-in is explicitly invited by that note's own "Adjacent" section ("fold it in if this item touches those lines anyway") and is reported on the `refactor:` line, so it is authorized, not scope creep. Provenance greps for `@owner-accepted` / `@owner-answered` / `answer-src` over the window: clean, no markers introduced. Fixture special-casing: the implementation mentions `relay/orphan/*` only in two COMMENT lines, and no fixture literal (`1251`, `4930`, the fixture names) appears in any code branch. Tiers run this review, named per review.md §3(c): `make lint` green (rm-force baseline 0<=0), `tests/run-tests.sh` 615 passed / 0 failed / 0 errored / 4 expected-red, `make gaming-canary` 3/3, `make shard-canary` 6/6, `make verify-negatives` for the item's own file. No tier was skipped. <!-- id:8627 -->

- [ ] **The reference measurement inside `docs/ledger-notes/8627.md` was itself produced by a `//`-blind scanner -- so the note that documents this defect class carried a milder instance of it, and its "ground truth" numbers were both wrong. Note CORRECTED this review; the item is NOT reopened.** The note's contrast paragraph claimed a character-level scanner finds "719 genuine template-interior lines and 5 genuine block-comment-interior lines" on `relay-loop.js`. Measured with the SHIPPED `workflow_scan_stats` against `d380fb6e` -- the exact 4,930-line revision the note measured, so the file is not the variable -- the answer is `skipped-in-template=324 skipped-in-comment=0`. Both corrections were adjudicated WITHOUT relying on that scanner: `grep -n '/\*' | grep -v '\*/'`, minus line-initial `//` lines, returns nothing on that revision, so the file contains no multi-line block comment at all and 0 is right rather than 5; and the file carries 17 line-initial `//` comments with an ODD backtick count (they quote ```` ```relay-mech ```` fences, e.g. lines 222/658/659/1983), each of which a `//`-blind scanner opens a template on -- which is the entire 395-line gap between 719 and 324. Nothing shipped is wrong: the fix, the acceptance and the `(f1)` assertion (`skipped-in-comment < 20`, actual 0) all stand. What was wrong was the paragraph a future reader would use to check the scanner, and it pointed AWAY from the correct implementation -- someone "restoring" 719 would reintroduce the bug. The note is edited in place with the original figures kept visible and the edit declared in its header, per this repo's CLAUDE.md convention that detail notes are editable and an edit is declared. <!-- relates:8627 -->

- [ ] **`relay-doctor` (report-only), recorded so the silence is on the record rather than assumed.** Cross-ledger drift: CLEAN. `roadmap-lint`: clean on the GRAMMAR axis relay-doctor reports (every open item carries a recognized lane tag + id), but run DIRECTLY it still emits the same three WARNs the section above already boxes -- the `id:540f`/`id:c179` DEAD-GATE pair plus `NO-ACCEPTANCE-NO-TWIN` on `id:da55`. None is new work from this window and none is newly actionable, so no new box; said explicitly because a bare "clean" would have been an overclaim sourced from the narrower of two checks. `orphan-scan.sh --shipped`: no TICK-READY and no GATE-STALE hits (the three ids the grep surfaces are items ABOUT those classes, matched on their titles). Executor-contract pointer in `CLAUDE.md` is `v18`, matching the canonical marker -- no refresh needed. Unchanged and NOT re-litigated here: the two parked orphans (`...-execute-c655-0`, `...-32609-execute-repo-0`) and the relay-core shadow-parity gap already have open boxes in the section above; `id:c655` correctly remains `- [ ]` open in ROADMAP, so its handback did not fake a close. NEW this window: a second inbox dead-letter, `routed:0ec3` -> `[inflownistration]`, filed by `5386fd64` in this same window and absent from that repo's ledgers -- it joins `routed:5997` as an unresolved routing, both awaiting a write in a DIFFERENT repo and neither actionable from here. Both ledger ratchets (head-length id:0d7c, shape-prose id:2d17) remain INERT for want of an installed baseline, which is why `todo-conformance` surfaces a large backlog rather than a delta; that is `id:4839` and its seams `id:c655`/`id:aa5e`, already tracked. **UPDATE 2026-09-09 (`/relay human`): the dead-letter half is DISCHARGED — this turn's `scan-routed.sh --apply` filed BOTH `routed:5997` and `routed:0ec3` into `inflownistration/TODO.md` (commits `a2cabf0` and `70bfeee` there), which is the cross-repo write a review worktree correctly refused to make. The rest of this snapshot (shadow parity, the two parked orphans, the INERT ratchets) stands; the orphans were dispositioned leave-parked this same turn.** <!-- relates:0ec3 -->
- [ ] **A `# fails-against-rev:` declaration may name a MOVING ref, and one did -- `test_verify_isolation_annex_cosmetic_3016.sh` declared `main`, which carried the fix the moment `d5e096a5` merged, so `make verify-negatives` reported it `VACUOUS -- the test PASSES against its declared negative case`.** Found and FIXED in this review (run relay-20260909-143257-21736): the rev is now pinned to `478d70d2`, the last commit touching `relay/scripts/verify-isolation.sh` before the fix, and re-running the runner gives `red-there OK ... -> FAIL: (1) cosmetic-only tree did not pass (rc=2)`, the exact declared assertion. `main` was CORRECT when authored -- it was the pre-fix tip when the branch was cut -- which is what makes the class insidious: the declaration decays into a no-op on precisely the merge that makes the fix real, and it decays SILENTLY because `verify-negatives` is opt-in and not part of `make test`. A sweep of all 141 declaring files found no other moving ref. The GUARD (refuse a non-immutable rev at declaration time) is filed as `id:ff6a`; this box records the incident. <!-- relates:ff6a --> <!-- id:76c9 -->
- [ ] **`tests/test_hard_lane_slice_f957.sh` carries NO machine-readable negative case and NO exemption, and now never will be asked for one -- its only negative control lives in the prose of commit `6cb345a5`.** `id:f957` is closed, so `verify-negative-cases.py`'s carve-out has EXPIRED and it would happily run a declared case; but there is nothing to run. `tests/lint-vacuous-fixtures.py` will never flag it either, because its carve-out is keyed on the PRESENCE of the `# roadmap:` token and deliberately so (`lint-vacuous-fixtures.py:57-62`, the `id:7c82` split -- the lint asks 'does this file owe a declaration', the runner asks 'may I execute one'). Verified by reading both carve-outs, not inferred: this is a documented design choice, NOT a defect, so nothing here is reopened. The residue is a COVERAGE observation with a number on it -- `--list` reports 412 roadmap-spec files unverified against 13 whose carve-out expired AND which carry a machine-readable case. The general gap is already tracked (`id:292b`/`id:a7..` family, `REVIEW_ME.md:901-906`); this box names the one instance this window created. Owner's call whether a closed roadmap-spec item should be asked to upgrade. <!-- id:7827 -->
- [ ] **Commit `2aa1bd09` landed a user-visible `/relay human` feature -- the `parked_orphan` kind, 92 lines of `gather-human-backlog.sh`, a 184-line test and a `relay/references/human.md` section -- with NO ledger id anywhere.** `grep -niE 'parked_orphan|parked relay/orphan' TODO.md TODO.archive.md ROADMAP.md ROADMAP.archive.md REVIEW_ME.md` returns NOTHING. The commit message cites `id:da87` (an ordering contract it preserves, still open) and `id:4e14` (the false-clean bug shape it avoids, closed) -- neither is the item. Consequence, which is the reason this is a box and not a shrug: work with no id is invisible to `orphan-scan --cross-ledger`, to the changelog deriver (which reads `workedIds`), and to any later 'was this ever specced' question -- the shape `id:3441` exists to prevent, one level up from a TODO line. Disposition is the owner's: mint a retrospective `[x]` ledger entry so the work is on the record, or rule that an unplanned in-review feature legitimately needs none. <!-- id:18ca -->
- [ ] **`id:1048` was ticked `[x]` and ARCHIVED on 2026-07-23 (commit `39a0bfe7`) while its own line still read 'needs RED spec' -- and its wiring into `relay-loop.js` landed 48 days later, on 2026-09-09 (`3ffdc8cc`).** Concrete instance of the built-green-but-unreferenced class: the ledger recorded the item CLOSED while `grep -c autoIntegrateParkedOrphans relay/scripts/relay-loop.js` would have returned 0. The wiring itself is sound and conservative -- gated on `AUTO_INTEGRATE_ORPHANS`, OFF by default, and its negative case verifies (`red-there OK ... the auto-integrate call site is not gated`) -- so nothing is reopened on quality grounds. What this box asks is narrower: an archived `[x]` line whose own text says 'needs RED spec' was a FALSE close for 48 days, and the archive is where a reader is least likely to catch it. Worth deciding whether a tick should be refused while the item's body names an unmet prerequisite. <!-- relates:1048 --> <!-- id:256d -->
- [ ] **`id:2b7a` (`[INBOUND routed:3655 from code.lawless]`, `TODO.md:867`) is a REPRODUCTION report whose purpose was served -- `id:3016` shipped on its evidence and is archived -- but it carries no lane tag and is still open, so it sits in the ledger as neither work nor record.** It is grammar-CONFORMING (it has an id), so `todo-conformance` does not see it and no collector will ever route it. Two of its three findings are discharged by `d5e096a5`; the THIRD is not: 'after the discard, porcelain read 0 while `git worktree remove` still saw dirt' is a separate predicate mismatch that the `id:3016` fix does not touch. So this is not a clean tick. Disposition: either carve the third wrinkle into its own lane-tagged item and then tick `2b7a` + `append.sh inbox-done 3655` (the `routed:3655` breadcrumb is in the owning `[INBOUND ...]` bracket form, so the twin-guard will find it), or re-lane `2b7a` itself onto the residual. Left for a human because deciding the third wrinkle is real work is a judgement, not bookkeeping. <!-- relates:3016 --> <!-- id:c758 -->

## Review 2026-09-09c (chain-end re-ask, run `relay-20260909-143257-21736` -- id:8123)

Window `relay-ckpt-20260909-1509`..HEAD -- the last *reviewer* checkpoint, not the literal latest
tag (`relay-ckpt-20260909-1516`), which is HEAD itself and would have given a vacuous window. ONE
work unit in it: `id:6446` (executor, sonnet). Tiers, named per review.md §3(c): `make lint` green
(rm-force baseline 0<=0), `tests/run-tests.sh` **620 passed / 1 failed** on arrival and **621 / 0 /
4-expected-red** after the fix below, `make gaming-canary` 3/3, `make shard-canary` 6/6, `make
verify-negatives` on the file this window added. No tier skipped; no `.github/workflows` exists, so
there is no e2e/integration tier to miss. `gaming-scan.sh`: CLEAN (no output). Provenance greps for
`@owner-accepted` / `@owner-answered` / `<!-- answer-src:` over the window: CLEAN, none introduced
or modified. `relay-doctor`: cross-ledger drift clean; `roadmap-lint` run directly still emits the
same three pre-existing WARNs already boxed above (`id:540f`/`id:c179` DEAD-GATE, `id:da55`
NO-ACCEPTANCE-NO-TWIN) -- none new, none newly actionable. The `docs/ledger-notes/4983.md` missing
detail pointer that `classify-repo` reports is already boxed at `REVIEW_ME.md:95`. Executor-contract
pointer in `CLAUDE.md` is `v18`, matching the canonical marker -- no refresh needed.

- [ ] **`id:6446` is verified genuinely green, and the load-bearing evidence is a replay rather
  than the suite: applying the OLD and NEW vocab to every heading in `ROADMAP.md`, `TODO.md`,
  `REVIEW_ME.md` and both `.archive.md` siblings flips exactly ONE heading -- `## User-injected
  promotion 2026-08-13 (id:baf1) -- archive-path stub design call`, which is `id:cd9c`'s own
  incident heading.** That is the whole acceptance, in both directions at once: the mention-only
  heading stops parking, and not one genuine parking bucket (`## Gated / deferred`, `## Done`,
  `## Icebox`, `@owner-gated`) changes verdict. Over-reach (review.md §2d) checked against the
  cited ratified source `docs/ledger-notes/6446.md` and the ⚠️ implementer note in
  `lib-roadmap-sections.sh`, not the ROADMAP restatement: the note mandates anchoring
  `ROADMAP_PARKED_HEADING_WORDS` ONLY and explicitly forbids anchoring the composed
  `..._VOCAB` (that would re-capture the marker half and un-protect owner-gated work). The diff
  does exactly that, and the anchored string it uses is byte-identical to the faithful stand-in
  `tests/test_owner_gated_first_class_f391.sh:139` already verified as safe. Not a superset. The
  `gated-on:f391` prerequisite is genuinely discharged (`f391` is `[x]` in both archives).
  Residual worth a human eye, NOT reopened: the left boundary `[^A-Za-z0-9_@-]` excludes a
  preceding hyphen, so a hand-written heading like `## Owner-gated holds` no longer parks. No such
  heading exists on this tree (that is what the replay proves), and it is the `id:d35a` class --
  "the vocabulary does not contain the words a human would write" -- already open as an
  `[INPUT - decision]` item. <!-- relates:6446 -->

- [ ] **GAMING FLAG (judgment, not `gaming-scan`): the executor reported "Full suite: 621 passed,
  0 failed, 4 expected-red" in `RELAY_LOG.md`, the commit body AND the changelog line. The suite
  was 620/1. Its own new test file was the failure.** `tests/test_negative_case_runner_a73c.sh`
  case (i) refused the whole declaration allowlist because
  `tests/test_roadmap_parked_heading_anchor_6446.sh` shipped with BOTH halves of its negative-case
  declaration malformed. Verified this is the executor's regression and not pre-existing: the
  runner file is byte-identical at `relay-ckpt-20260909-1509` and at HEAD (`diff -q`, clean), so
  nothing about the check changed -- only the input did. The two defects:
  `# fails-against-mutation:` was a python heredoc split across nine comment lines, of which only
  the FIRST reaches the runner (`id:b890`), leaving the syntactically-invalid fragment
  `python3 -c "`; and `# fails-against-assertion:` named a string that appears NOWHERE in the
  file's body, so it could never have matched a fired `FAIL:` line. **FIXED this review**
  (`fa48199e`), not reopened: the mutation is now one complete single-line command, and the
  assertion names the LAST of the four `FAIL:` lines the non-exiting accumulator fires, per the
  CLAUDE.md rule. `make verify-negatives FILES="tests/test_roadmap_parked_heading_anchor_6446.sh"`
  now reports `green-now OK` / `red-there OK ... 4 FAIL lines fired; matched the LAST`. What the
  owner may want to weigh: this is the THIRD vacuous-negative-case incident in three consecutive
  reviews (`id:3016`'s moving rev -> `id:ff6a`; `id:f957`'s absent declaration -> `id:7827`; now
  this), and the common factor is that `make verify-negatives` is opt-in and NOT part of
  `make test`, so an executor can honestly believe it ran everything. <!-- relates:6446 -->
  <!-- relates:ff6a -->

- [ ] **NEW EVIDENCE for the already-open `id:8372`, and it is worse than that item's own framing:
  `ledger-shrink.py` did not merely "defeat the shrink" -- it MANUFACTURED a live first-class
  DISPATCH EXCLUSION on an open `[ROUTINE]` item.** `id:6446`'s ROADMAP head line read
  ``... -- detail: `docs/ledger-notes/6446.md` 🚧 `@owner-gated` <!-- gated-on:f391 --> <!-- id:6446 -->``.
  The item was never owner-gated; its real gate was the typed edge `gated-on:f391`. Both the `🚧`
  and the `` `@owner-gated` `` were hoisted out of the item's BODY by commit `63d8539b`
  (`shrink(0d7c)`), where they occur only as prose ABOUT the other item's protection mechanism
  ("a heading containing the literal `@owner-gated` is parked ONLY because that string contains
  `gated`"). `id:8372`'s `_at_marker_is_prose_example` guard cannot see this: it fires only when
  the quoted marker is immediately followed by the word "marker"/"markers", and neither sentence
  here is. Consequence, measured not inferred -- `classify-repo.sh` computes
  `blocked = "🚧" in ln` and `is_owner_gated = "@owner-gated" in ln`, and the actionable branch
  requires `not blocked and not is_human`, so the line scored **False** for
  `actionable_routine_open`. A correct, ungated, RED-spec-ready item was invisible to dispatch for
  the same reason `id:cd9c` was -- which is the exact silent-starvation class `id:6446` itself
  existed to fix. Two more live instances of the same hoist, both currently harmless only because
  their lane is already non-dispatchable: `TODO.md:575` (`id:16bf`) and `TODO.md:930` (`id:d35a`,
  which additionally carries FOUR lane tags -- `[INPUT — decision]`, `[ROUTINE]`,
  `[INPUT — meeting]`, `[HARD]` -- three of them hoisted from body prose). Blast radius today:
  ZERO open ROADMAP items carry `@owner-gated`, so nothing is starved right now; 601 bodies were
  relocated by that one commit, so the question is what else it planted. Suggest this evidence
  re-scopes `id:8372` from a shrink-quality item to a dispatch-integrity one. <!-- relates:8372 -->
  <!-- relates:6446 -->

- [x] **`id:6446` was worked by an executor even though its ROADMAP line carried TWO independent
  first-class dispatch exclusions, and the classifier correctly excluded it -- so the exclusion is
  computed and then not consulted by whatever picks the item.** Verified by evaluating
  `classify-repo.sh`'s own predicates against the literal line as it stood at
  `relay-ckpt-20260909-1509`: `is_routine=True`, `blocked=True` (the `🚧`), `is_owner_gated=True`,
  therefore `counts toward actionable_routine_open = False`. The execute unit was legitimately
  dispatched for the repo's OTHER actionable `[ROUTINE]` items; the Sonnet executor then selected
  an item the classifier had ruled out. The outcome here was benign -- the markers were false
  (previous box), the real gate was discharged, and the work is correct -- but the mechanism is
  not: an executor that does not honour `🚧`/`@owner-gated` at SELECTION time can work a
  genuinely owner-gated item, which is the `id:540f`/`id:c179` owner-gate-breach class the holds
  exist to prevent. The gap is that `actionable_routine_ids` is computed by the classifier and
  the executor contract's rule 1 says only "work `[ROUTINE]` items from ROADMAP.md" -- it never
  tells the executor about the marker exclusions, nor hands it the computed id list. Two fix
  shapes, owner's call: pass `actionable_routine_ids` into the executor's dispatch prompt as the
  permitted set, or restate the marker exclusions in `executor-contract.md` rule 1 (cheaper, but
  it is prose an executor can miss -- the `id:d35a` failure mode). **RESOLVED 2026-09-10 (owner ruling): the permitted-id set is now PASSED INTO the dispatch prompt.** `permittedIdsFor()` in `relay-loop.js` renders the classifier's full `actionable_routine_ids` (minus the orphan/stranded subtraction, injected item first) as a CLOSED PERMITTED SET in the execute brief, with unlisted ids declared OUT OF SCOPE and a hand-back instruction rather than a preference. The prose alternative -- restating the marker exclusions in `executor-contract.md` rule 1 -- was NOT taken, for the reason this box gives. An EMPTY set fails CLOSED: the historical `Work the open [ROUTINE] items in ROADMAP.md` fallback is replaced by `EXECUTE_NO_PERMITTED_SET`, a refusal that authorises no work and instructs an immediate structured handback. Pinned by `tests/test_permitted_id_set_c076.sh` (mutation-verified). <!-- id:c076 -->

  ANSWERED 2026-09-10 (/relay human 3a): RESOLVED as the box records. permittedIdsFor() renders the closed permitted set into the execute brief (2 call sites in relay-loop.js), an empty set fails closed via EXECUTE_NO_PERMITTED_SET (3 sites), and tests/test_permitted_id_set_c076.sh passes cases A-D. Re-checkable by rerunning that test.

## Review 2026-09-09 (run `relay-20260909-143257-21736`, chain-end re-ask)

Window `relay-ckpt-20260909-1547`..HEAD -- the last *reviewer* checkpoint, not the literal latest
tag (`relay-ckpt-20260909-1609`), which is HEAD itself and would have given an empty, vacuous
window. One work unit in it: `id:521b` + `id:9088` (executor, sonnet). Tiers: one declared test
tier, `make test` / `tests/run-tests.sh` -- **622 passed / 0 failed / 0 errored / 3 expected-red**,
independently re-run here and matching the executor's claim (the previous review caught a FALSE
621/0 claim, so this was verified rather than taken). No `e2e`/`integration` tier is declared (no
`.github/workflows`), so nothing was silently skipped; `make verify-negatives` is opt-in and not
part of `make test`. `gaming-scan.sh`: CLEAN, no output. Provenance greps CLEAN: no
`@owner-accepted` / `@owner-answered` / `answer-src:` minted or modified this window. No
`[host:]` tag on any reviewed item, so the id:43b9 host gate does not apply. `orphan-scan
--cross-ledger`: clean. `roadmap-lint`: 3 pre-existing WARNs (DEAD-GATE id:540f and id:c179 both
gated on `b0b1`, which lives only in TODO.md; NO-ACCEPTANCE-NO-TWIN id:da55) -- unchanged by this
window, already known.

**Verified green: `id:521b`.** Not taken on the suite result. The RED spec was replayed against
the PRE-fix `tools/shrink-acceptance.py` (restored from `relay-ckpt-20260909-1547`) and reddens at
case (2) -- exactly the assertion the item's acceptance names as the failing one -- then passes all
8 cases against the new implementation. The one test-file change in the window is INPUT-only (the
case-3 fixture string); every assertion is byte-identical, so the resurrection check's negative
control holds.

**`id:9088` independently confirmed and ticked.** The claim was that case 3 was UNSATISFIABLE -- a
fixture title of 194 chars against the 200 it must exceed. Re-derived by feeding both the old and
new fixture lines to `relay/scripts/todo-conformance.sh` directly: the OLD line emits only
`shape-new` and NO `grammar-item-title-long`, the NEW line emits `grammar-item-title-long (280
chars of title, approximate max 200)`. The case genuinely could not fail for the reason it named.
Its TODO.md checkbox was left open by the executor's tick commit despite that commit's message
saying `+ TODO twins [id:521b,9088]`; ticked here.

- [ ] **A shrink batch that makes a title LONGER is accepted, and is misreported as a deliberate
  leave.** Filed as `id:227d`. `check_title_rewrites()` scopes `common`/`touched` to items whose
  BEFORE title was already over budget (a correct fix for a real false positive), but the `left`
  loop iterates `before_ids & after_ids` UNSCOPED. Measured with a constructed fixture pair: an
  item rewritten from a 66-char title to a 280-char title exits **rc=0, ACCEPTED**, printing
  `items checked=0   touched=0   left-still-over-budget=1` -- describing as `LEFT unmodified` a
  line that was modified, in the one direction a shrink gate exists to prevent. **The judgment
  call is yours**: the misreport is unambiguously a bug and `id:227d` owns fixing it, but whether
  a grown title should additionally be a FATAL refusal has a real blast radius (it could newly
  reject otherwise-honest batches). The item deliberately does NOT decide that.
  **UPDATE 2026-09-09 (relay review, run relay-20260909-143257-21736): the REPORTING half has
  LANDED and is verified green** -- `dfbf6e24` adds a third `grown` bucket, and the same fixture
  pair now prints `WARN [title-rewrite] id:b2b2 -- title CHANGED and is now over budget (was not
  over budget before) -- not a leave, the line was edited`. The executor implemented reporting
  only and left the refusal question open, exactly as the item required. **Re-measured here, the
  batch still exits `rc=0, VERDICT: SAFE TO LAND`** -- so the question below is unchanged and
  still yours, and until you answer it a title-rewrite batch must be READ for the WARN rather than
  trusted on its exit code (id:b437's ROADMAP line now says so). Box left OPEN for that decision
  alone, not for the bug. <!-- id:227d -->

- [ ] **The negative-case discipline has a second, independent umbrella on the DECLARATION axis:
  a defect-fix case grafted into a landed `# roadmap:`-keyed spec is verifiable by nothing.**
  Filed as `id:799f`; the declaration-axis sibling of `id:11a4` above, same root, different file.
  `lint-vacuous-fixtures.py` exempts any roadmap-keyed file outright (its own line 21: *"NEVER
  flagged, regardless"*), and with no declaration `verify-negative-cases.py` has nothing to
  execute -- so such a file falls in the `roadmap-spec (not verified)` bucket rather than the
  `roadmap carve-out EXPIRED` bucket, which only catches files that DID declare. Neither side has
  a detector for the gap. **Found live in the work I was reviewing**: case (8) of
  `tests/test_title_rewrite_batch_acceptance_64f9.sh` (the `id:227d` fix) landed into a file whose
  `# roadmap:521b` key already pointed at a closed item, with no declaration and no exemption.
  **I verified that case by hand** -- restored the pre-fix `tools/shrink-acceptance.py`, re-ran the
  file, cases 0-7 pass and case 8 fails at the exact assertion it names -- so `id:227d` is sound
  and I am not reopening it. The finding is that the verification was mine, not the machine's.
  355 of 625 test files sit inside the same file-scoped exemption; that is the population a future
  graft hides in, NOT 355 defects, and a "fix" that turns the advisory lint into a 355-line wall
  would be a regression. **Your call on the shape** (per-case declarations, or the lint noticing a
  closed-item file that gained assertions) -- id:799f states both and decides neither.
  <!-- id:799f -->

- [ ] **This queue is at 65 open boxes against its own stated `Max ~10`, and I did not prune it.**
  The file's header says the reviewer prunes resolved boxes each review turn; the repo convention
  (CLAUDE.md) says REVIEW_ME is compacted by ARCHIVING resolved boxes rather than by relocating
  their prose, and to do it aggressively. Adjudicating 65 boxes is not a rushed side-task inside a
  review turn -- deciding a box is resolved is exactly the judgment that must not be guessed, and
  most boxes here carry no `id:` so no tooling reaches them. Surfacing rather than sweeping is the
  conservative default. If you want this mechanized, it wants its own item.

- [x] **Cross-repo dead-letter, unresolved: `routed:d357` -> `it-infra`.** `relay-doctor` reports
  it absent from both `it-infra`'s TODO.md and ROADMAP.md (route `www.whaleverifier.com` through
  the fievel tunnel; blocked because the stored Cloudflare token lacks
  `cfd_tunnel/*/configurations`, error 1001). Left untouched deliberately: it targets another
  repo, and `scan-routed` is report-only unless run with `--apply`. Noted here so it is not lost.
  `relay-doctor` also reports the relay-core shadow at 37,312 mismatches over 339,373 rounds --
  pre-existing, bash stays authoritative.

  RESOLVED 2026-09-10 (`/relay human`, tier-(a)): it is no longer a dead-letter. `it-infra/TODO.md`
  line 320 carries `[INBOUND routed:d357 from zkWhale relay review 2026-09-09]` as `id:7f3b`,
  lane `[INPUT - access]`, `gated-on:5b71` -- correctly qualified as needing an account-level
  Cloudflare Tunnel:Edit token nobody here can mint. The token is gone from the inbox.
  The relay-core shadow-parity half of this box is NOT resolved and is already carried by its own
  box in the `## Review 2026-08-26` section (`id:82c4`).
  Re-check: `grep -n 'routed:d357' ~/src/it-infra/TODO.md`.

## Review 2026-09-09d (chain-end re-ask, run `relay-20260909-185356-12943` -- id:8123)

Window `relay-ckpt-20260909-1910..HEAD`: one executor unit (`id:5295`) plus its integrate
commits. `gaming-scan.sh`: no output (no DELETED_TEST / ADDED_SKIP / REMOVED_ASSERT).
Provenance greps for `@owner-accepted:` / `@owner-answered:` / `<!-- answer-src:` in the
window: none introduced, none modified. Tiers: `tests/run-tests.sh` **623 passed, 0 failed,
0 errored, 3 expected-red**; `make lint` (`check-no-bare-rm-f.sh --enforce`) clean at
baseline 0. **SKIPPED-TIER: `verify-negatives`, `gaming-canary`, `shard-canary`** -- all
three are opt-in by design and NOT part of `make test` (seconds-per-case sandboxing; the
two canaries spawn real agents and cost tokens); no closed item's done-check depends on
them. Executor-contract pointer in `CLAUDE.md` is `v18`, matching the canonical marker --
no refresh. `orphan-scan --cross-ledger`: clean. `orphan-scan --shipped`: the only three
`TICK-READY`/`GATE-STALE` string hits are items *about* those classes (`id:4425`,
`id:535d`, `id:e1bb`) matched on their titles -- no real hit, same as the prior window.
`roadmap-lint` exit 0 with the same three pre-existing WARNs (`540f`/`c179` DEAD-GATE,
`da55` NO-ACCEPTANCE-NO-TWIN), all already boxed above; no new box.

- [ ] **`id:5295` is verified GENUINELY green by spec-replay, not by taking the suite's word
  -- but one clause of the item's own body was NOT delivered, and I closed it anyway.** The
  spec `tests/test_self_transcript_tilde_marker_5295.sh` was authored by the handoff
  (`a18bc832`) and is **byte-unmodified** by the executor, so §2b.1's resurrection check is
  satisfied structurally: the implementation moved, the spec did not. I re-ran the spec
  against the PRE-fix `relay/scripts/self-transcript.sh` (extracted from
  `relay-ckpt-20260909-1910` into a scratch tree) and it dies at **case 1** -- `an
  absolute-path marker did not match a tilde-spelled dispatch prompt (rc=4)` -- which is the
  assertion the item names, not an earlier fixture-sanity death. The spec's own negative
  controls are real and pass: case 4 (a different `$HOME` must still MISS), case 5 (two
  sibling worktrees differing only in the trailing unit key stay discriminated), case 6 (a
  marker naming nothing still exits 4 loudly). §2d over-reach: the diff is a strict SUBSET of
  what the item authorized, not a superset -- 30 lines confined to the marker filter, no
  `relay-loop.js` edit, no nonce, and the tie-break semantics the item explicitly forbade
  touching are untouched. **The residue:** the item's body says *"Fixing the fixture's
  fidelity is part of this item"* about `tests/test_self_transcript_workflow_nesting_c219.sh`
  (which writes an ABSOLUTE dispatch prompt and passes a BASENAME marker -- the two
  divergences that hid this defect for weeks). That file is unchanged. The new 5295 spec
  models the real shape instead, so the *coverage* gap is closed by a second file rather than
  by repairing the first; but `c219`'s fixture still models a shape the dispatcher does not
  emit, and the next defect on that path will be hidden by it the same way. I did **not**
  reopen: the item's explicit **Acceptance** and **Done-check** bullets are both fully met,
  and the fixture sentence sits in a rationale bullet. Flagging the judgment because reading
  the body and reading the acceptance give different answers here. <!-- relates:5295 -->
  <!-- relates:c219 -->

- [ ] **Every executor-actionable `[ROUTINE]` item in this repo was attempted on 2026-09-09
  and PARKED with real unmerged work: five orphan branches carry 253/249/70/62 insertions
  that a re-dispatch will silently redo from scratch.** `relay-doctor` lists 6 parked orphans
  for this repo; measured with `git diff --stat main...relay/orphan/<b>`, four of them hold
  substantive WIP -- `...-143257-21736-execute-11a4-0` (7 files, +253),
  `...-143257-21736-execute-799f-0` (2 files, +249, including a whole new
  `tests/test_lint_post_close_graft_799f.sh`), `...-143257-21736-execute-b437-0` (11 files,
  +70), `...-143257-21736-execute-aa5e-0` (1 file, +62) -- plus
  `...-091623-10249-execute-c655-0` from the earlier run. Those ids are `11a4`, `799f`,
  `b437`, `aa5e`, `c655`: **that is the entire un-gated `[ROUTINE]` set.** Note what
  `relay-doctor`'s own summary says two lines later -- *"5 retirable item(s) -- no work at
  risk"* -- which is about WORKTREES, not these branches; a reader skimming the report would
  conclude nothing is stranded. The commits are honest (`id:f272` commit-and-park, labelled
  `WIP UNVERIFIED ... do not treat as reviewed`), so this is not a gaming finding; it is a
  *throughput* finding, and it is the live shape of `id:3846` (the trimmed
  `relay-implementer` still dying `Prompt is too long`; its own line records 7/10 without the
  flag vs 1/4 with). The decision I am NOT making: whether to salvage these branches
  (cherry-pick / re-dispatch onto them) or discard them. Both are owner calls and the diffs
  are UNREVIEWED. <!-- relates:3846 --> <!-- relates:f272 -->

- [ ] **`routine_open` returned as 4, not the raw 10 -- confirm the call (the `id:59f2`
  judgment, second occurrence).** Raw count of open `- [ ] ... [ROUTINE]` in `ROADMAP.md` is
  10. `resolve-gates.sh` reports `540f`, `c179`, `554b` blocked=1. Of the remaining seven:
  `d4ca` carries 🚧 plus four `gated-on:` markers (`33b2`/`93ac` in prose, `09e4`/`b0b1`
  typed); `cf2d` is `@owner-verify` and its body says the evidence can only come from a LIVE
  harness the pool cannot manufacture; `aa5e`'s own title gates it on the repo-dimension seam
  (`c655`) landing first. That leaves `c655`, `b437`, `799f`, `11a4` = **4**, every one of
  which is a parked-orphan id from the box above. So `routine_open: 4` is honest under
  `review.md`'s *"is there executor work left"* reading, but the supervisor should know the
  work is not virgin -- re-enqueueing an execute unit hands it four items that four children
  already started and lost today. <!-- relates:59f2 -->

- [ ] **The executor committed `id:5295`'s fix into the MAIN checkout on `main` before
  noticing, and the isolation gate never fired -- it self-healed by luck of merge topology,
  not by a guard.** Its own `RELAY_LOG` friction note is candid: it committed `639c6ffa` in
  `~/src/dotclaude-skills` on `main` instead of its worktree, cherry-picked the identical
  content to `64d6de3c` on the worktree branch, then had every attempt to undo the stray
  commit (`reset --soft`, `revert`, `branch -f`) denied by the permission classifier, and
  handed the residue over asking for an operator reset. **That reset never happened and is no
  longer needed:** the integrator's merge `975f835f` took `639c6ffa` as its FIRST parent, so
  the stray commit is now an ancestor of `HEAD` (`git merge-base --is-ancestor 639c6ffa HEAD`
  -> yes), and `git -C ~/src/dotclaude-skills status -sb` reads `## main...origin/main` with
  a clean tree. I verified the double-apply did no damage: `grep -c 'marker_variants=()'` is
  **1**, and `bash -n` on the file is clean. Two things worth a human's eye anyway.
  (a) `verify-isolation.sh` checks that the WORKTREE has commits and a clean tree -- both
  were true here, because the cherry-pick fixed the worktree side -- so it structurally
  cannot see that the same work also landed on `main`. The gate is one-sided. (b) The
  executor's honest attempt to CLEAN UP was blocked while the mislocated WRITE was not,
  which inverts the intended pressure: the classifier permitted the mistake and forbade the
  correction. Recording it rather than proposing a fix, because "should a child be able to
  reset a main checkout" is exactly the kind of guard question that must not be answered by
  the child that wants the permission. <!-- relates:f682 -->

## Handoff 2026-09-09 (run `relay-20260909-205831-5121`, user-injected id:6d7e)

- [x] **The ambiguity refusal reuses exit code 4 rather than minting a distinct one, so no
  caller can branch on "not unique" vs "no such marker".** The ruling said "exit non-zero"; I
  read that as 4, the resolver's existing UNRESOLVED code, because `context-budget.sh --self`
  fails open on ANY non-zero and the acceptance requires it to land on `unknown` -- a new code
  would work identically there, so 4 costs nothing today and keeps the exit table at three
  values. The case against: the two failures have OPPOSITE remedies (fix the marker string vs.
  make the marker unique at source), and a caller that one day wants to retry-with-a-narrower
  marker on ambiguity, but not on a genuine miss, cannot tell them apart from the status alone.
  The RED spec pins only that the two MESSAGES differ (case 2), which is enough for a human
  reading a run log and not enough for a program. If you want a distinct code, say so before the
  executor picks this up -- adding one later is a compatibility change to a documented table.  (against `id:6d7e`.)

  CLOSED AS SUPERSEDED 2026-09-10 (`/relay human`, tier-(a)) -- this is a bookkeeping close, NOT an
  answer. Its literal ask ("say so before the executor picks this up") is spent: the executor
  shipped exit 4 and `id:6d7e` is closed and archived. The SAME question, correctly reframed as a
  compatibility change to a shipped exit table, is carried by the still-OPEN box in the
  `## Review 2026-09-09e` section ("The exit-code question the handoff raised against `id:6d7e`
  has now SHIPPED as exit 4"). Decide it there; nothing is lost by closing this duplicate.

- [ ] **Two landed test cases pin the behaviour the ruling reverses, and I prescribed EDITING
  them rather than deleting them -- an executor will be rewriting cases whose own items are
  closed.** `tests/test_self_transcript_wiring_ff30.sh` case 6 and
  `tests/test_self_transcript_workflow_nesting_c219.sh` case 7 assert the newest-mtime pick, and
  under the fix they die mid-file as REAL failures (neither carries a `# roadmap:` header, so
  neither can be swallowed as expected-red). The item tells the executor to convert both to
  `--allow-ambiguous`, keeping their assertions byte-for-byte otherwise, on the grounds that the
  guarantee they encode (newest wins, every candidate named) is exactly what the opt-in path must
  still provide -- so the conversion is the opt-in's only regression cover, and deleting them
  would leave that path covered by nothing but the new spec's case 6. Flagging it because
  "handoff rewrites the tests of two closed items" is the shape that usually deserves a second
  look, even when, as here, the behaviour under them was deliberately changed by an owner ruling.  (against `id:6d7e`.)
  **CORRECTION 2026-09-09: there was NO owner ruling.** The owner was asked directly and said
  "it wasn't my call". The text the handoff child read as his was the `inject.sh --prompt` I
  wrote to dispatch the item; this box then cited that child's inference as established fact,
  one hop further. He did endorse the DIRECTION ("multi-match must fail loudly"), but was never
  shown the `(a)`/`(b)` framing or branch (b)'s cost (rule 2c returns `unknown` for every pooled
  child until the marker is unique at source). The behaviour change is a standing engineering
  judgement, open to revision; `(a)` is reopened. See the correction banner in
  `docs/ledger-notes/6d7e.md`.

## Review 2026-09-10 (run `relay-20260910-114832-18641`, window `relay-ckpt-20260909-2341..HEAD`)

36 commits, ALL hand/session work (no executor unit in this window -- `RELAY_LOG.md` gained
nothing, so every §2 check ran against owner-attributed commits). `gaming-scan.sh`: clean, no
output. Provenance greps (§2b.7/9/10): no `@owner-accepted` / `@owner-answered` / `answer-src`
introduced or modified anywhere. Exactly ONE test file was MODIFIED rather than added
(`tests/test_prelude_mechanized_86a2.sh`, the `id:1975` hermeticity fix) -- read line by line: it
adds five `export`s and a comment block, and touches no assertion, so §2b.1's resurrection check
has nothing to replay. Tiers RUN: `make test` (runs `lint` first) **634 passed / 1 failed / 0
errored / 1 expected-red**, `make gaming-canary` (3/0), `make shard-canary` (6/0/0),
`make baseline-staleness` (advisory: 1 ORPHANED shape row for the now-closed `id:c655`, 0 stale),
and `verify-negatives --changed relay-ckpt-20260909-2341` (6 files executed, every declared
negative case fires at its declared assertion except `id:0246`'s, which is red-now by design).
RECORDED-SKIP: `make check-statusline-deps` and the full `verify-negatives` sweep (opt-in, not part
of `make test`). No e2e/integration tier is declared. `orphan-scan --cross-ledger`: clean.
`roadmap-lint`: 4 WARNs, 3 pre-existing, 1 NEW (box below). Verified green and CLOSED: `id:4e84`,
`id:aa5e` (ROADMAP), `id:ed35` (TODO). Ingested the 3 `routed:` dead-letters aimed at this repo
(`2af2`->`id:a33d`, `4887`->`id:9635`, `5831`->`id:5239`), each with a detail note; not
`inbox-done`'d here, since the twin-guard reads the MAIN checkout and auto-reconcile drains them
after integrate.

- [x] **The suite is RED at HEAD on purpose, and that makes the executor contract's
  definition-of-done unreachable for every future unit in this repo.**
  `tests/test_inbox_own_token_extractor_0246.sh` deliberately carries NO `# roadmap:` header, so
  its failures always count; the implementation it specs was REVERTED (`eb2587fd`) after the
  adversarial review found 9 defects, 2 HIGH, on a destructive write path. That was the right call.
  The consequence is the part nothing has recorded: executor-contract rule 2 says done means "the
  FULL test suite is green", so until `id:0246` ships, every executor either hands back or quietly
  redefines green -- and `id:0246` cannot ship, because its D5 and D6 need YOUR ruling (is an
  indented inbox line legal; does the multi-marker refusal extend to a line that merely CITES the
  token). I did not weaken the test or add a header: both would hide a live defect. Your call is
  which of three: rule on D5/D6 so it can ship, give the file a temporary exemption with a named
  expiry (`<!-- expires-on:0246 -->` now exists for exactly this, via `id:a192`), or accept a red
  suite and tell executors so explicitly.

  RESOLVED 2026-09-10 (relay human, tier-(a)): the premise is gone. D5 and D6 were both
  ruled on 2026-09-10 (D5 refuse an indented line LOUDLY; D6 DISSOLVED -- reject a multi-marker
  inbox line at write time), so `id:0246` was no longer blocked. It re-landed as `69587e46` with
  all 9 review defects fixed and the suite reports `637 passed, 0 failed, 0 errored, 1
  expected-red`. No exemption was minted and the headerless spec kept its header-less shape.
  Re-check: `git show 69587e46 --stat` and `make test`.
- [ ] **`id:4e84` is ticked although HALF of what `routed:71c6` filed did not ship -- confirm the
  split rather than the tick.** The inbound report named two faults. Fault (b) (strict rank order
  starves apex and handoff) is fixed and independently verified: spec cases A-G green, and the
  declared mutation reddens at the declared assertion, not an earlier one. Fault (a) (an
  excluded-but-open item pins the verdict) is NOT fixed -- `classify-verdict.sh` still has no
  notion of a dispatch brief, and the widening only changes the CONSEQUENCE, because the round's
  second pass now reaches `hard`/`handoff`. I ticked the item (its ROADMAP line, detail note and
  RED spec all scope it to the loop-side widening) and filed fault (a) as `id:fe67`
  `[INPUT - decision]` so it cannot vanish inside a closed item. If you would rather the parent
  stay open until (a) is answered, reopen both lines -- `ROADMAP.md` `id:4e84` and its
  `TODO.md` twin.

- [ ] **`id:a192` shipped, is green, and has NO ledger line anywhere -- the token exists only in
  commits and its own detail note.** The `expires-on:` edge plus `relay/scripts/expires-on-scan.sh`
  landed in `91264d35` with a verified negative case, and `grep -rn 'id:a192'` finds nothing in
  `TODO.md`, `ROADMAP.md` or either archive. Nothing is open, so nothing is starved -- but
  `orphan-scan --cross-ledger`, `unpromoted-scan` and `expires-on-scan`'s own DANGLING check are
  all id-keyed, so a shipped feature that no checkbox ever described is invisible to every one of
  them. Same class as the already-open box on `id:02fe`; recording it here rather than
  retro-filing a closed item, which is your call, not mine.

- [ ] **NEW `roadmap-lint` WARN, introduced by this window: `id:32c3` trips DECIDED-LEFT-OPEN.**
  Its hand-promoted ROADMAP line carries "the CLAUDE.md (c) amendment's 'belongs to (b)' clause is
  SUPERSEDED", and the lint reads `SUPERSEDED` as a claim about THIS item's status; the item is
  genuinely open (the skill is unbuilt). So the WARN is a false positive on a true sentence. I left
  the prose alone: rewording a recorded owner ruling to placate a linter is the wrong direction,
  and suppressing the check repo-wide is worse. Either accept a standing WARN on this one item, or
  the lint learns that a decided-marker inside a quoted ruling is not a status marker.
