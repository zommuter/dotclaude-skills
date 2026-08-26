# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

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

- [x] **Cross-ledger drift `id:5bef` — `[x]` in ROADMAP (archived) but `[ ]` in TODO.md — reconciled
  this review.** TODO.md:333 twin ticked; `orphan-scan --cross-ledger` now clean for 5bef.

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

- [x] **Handoff-readiness: `id:f26d` is an open non-gated `[ROUTINE]` with NO RED spec** —
  `grep -rl 'roadmap:f26d' tests/` returns nothing, yet the classifier ranks it `actionable_routine`
  (non-gated `[ROUTINE]`), so an execute chain would pick it with no failing test to satisfy (executor
  definition-of-done). Needs a handoff pass to author the red spec (or re-lane — it is `md-merge.py`
  insert-relative-to-id + a TOCTOU-free in-lock line transform, arguably design-weight) before it is
  genuinely dispatchable.
  **UPDATE — review relay-ckpt-20260819-1614 chain (chain-end re-ask of the `id:f875` executor chain):**
  the sibling `id:f875` this box also named is now CLOSED and green — the executor hardened
  `test_run_tests_parallel.sh` itself (its deliverable IS the test, so it needed no separate RED spec);
  the change replaces the racy live-marker point-sample with a flock-ordered start/stop event stream +
  interval-stabbing peak, verified honest (gaming-scan clean, assertions intact, `maxc==1` serial /
  `maxc>1` parallel checks unchanged). `id:dd7d` — the item this box cited as the only spec'd one of the
  trio — is also closed+green (`tests/test_redispatch_stranded_branch_dd7d.sh` passes) and its TODO twin
  was reconciled [x] this review. Only `id:f26d` remains from the original trio.
  — ✅ **STALE — the last of the trio closed too. Box closed 2026-08-20 (`/relay human --all`) after
  verification, with a correction.** Both halves of the hazard are now false: **(1)** `id:f26d` is
  `- [x]` on `ROADMAP.md:1608` (the `md-merge.py` insert-relative-to-id + in-lock line transform
  shipped, INBOUND `routed:f88b` from loderite); **(2)** the missing RED spec EXISTS —
  `tests/test_md_merge_insert_and_transform_f26d.sh` (authored 2026-08-19 16:26), and it PASSES
  (`tests/run-tests.sh` → `1 passed, 0 failed, 0 expected-red`). So the dispatch hazard this box
  described — a non-gated `[ROUTINE]` an execute chain would pick with no failing test to satisfy —
  cannot occur: there is nothing left to pick.
  **Recorded because it changed a decision:** the owner was asked (on this box's stale framing) and
  chose \"route to `/relay handoff` to author the RED spec\". **That routing was NOT performed**, because
  the spec it would have commissioned already exists and the item it would have prepared is already
  done — dispatching it would have produced a duplicate spec for shipped work. Verified before acting
  rather than after. This is the third stale REVIEW_ME box found in this pass (with helferli `id:4137`
  and loderite `id:8b7c`'s misattributed blocker); the common shape is a box asserting a CODE state
  that the code has since moved past, which is exactly the doc-vs-code drift the global rule names.

## Review 2026-08-14 (chain-end re-ask, chain `relay-ckpt-20260813-2332` — id:8123)

Window carried no executor code work (ledger/human batches + inbox ingests only); `gaming-scan.sh`
clean. §5b reverse-handoff: authored the missing RED spec for `id:1b13` (re-laned to `[ROUTINE]`
this window). One handoff-readiness gap surfaced:

- [x] **`id:f91a` (@container, ROADMAP.md:1509) is an open `[ROUTINE]` with NO RED spec — not
  executor-ready.** `grep -rl 'roadmap:f91a' tests/` returns nothing, so an executor that picks it
  has no failing test to satisfy (the executor-contract definition-of-done). It is NOT new this
  window (predates `relay-ckpt-20260813-2332`), so it is outside the §5b mini-handoff, but it needs
  a handoff pass to author a red spec before it can be dispatched. Either author the spec at the
  next handoff or re-lane it if @container is a design task rather than executor work. (The other
  dispatchable `[ROUTINE]` items — `id:1b13`, `id:cd9c`, `id:ec3c` — all have specs.)
  **RESOLVED 2026-08-14 (`/relay human .` batch 4): the "re-lane if @container is a design task"
  branch was taken — `id:f91a` is now `[INPUT — meeting] @container` at ROADMAP.md:1509, so it is
  no longer an open `[ROUTINE]` and needs no RED spec. No longer dispatchable pool work.**

### Re-ask 2026-08-14 (window `relay-ckpt-20260814-1102`..HEAD — 2 human ledger commits, no code)

Chain-end review re-ask (same chain id:8123) fired after the `/relay human` batch-4 commit +
the false-DEAD-GATE fix on `id:f91a`. Window carried **no executor code work** — only ledger/human
decisions. `gaming-scan.sh` clean; `orphan-scan --cross-ledger` clean; `check-install-drift`/refs
clean; no MECHANICAL orphans; 0 parked orphans; contract pointer `v12` == canonical. Full suite
green (422 pass, expected-red for the open `[ROUTINE]` specs). `roadmap-lint` exit 0 (only the
pre-existing DEAD-GATE/DEP-PROSE WARNs already boxed below — none introduced this window).

**§5b reverse-handoff:** the batch added two genuinely-new items to `TODO.md`. `id:f346`
(deterministic premise-checker) is `[HARD]` → left for the reviewer, not mini-handoff material.
`id:cc7e` (md-merge `update-ids` own-id resolved by FIRST id-comment instead of LAST) is
execution-ready `[ROUTINE]` → **mini-handoff done**: promoted to ROADMAP.md (Review-derived
promotion section) reusing `id:cc7e`, with RED spec `tests/test_md_merge_own_id_last.sh`
(`# roadmap:cc7e`). Verified RED against the unmodified tree and non-vacuous (green only when
both `md-merge.py:263` own-id resolution AND `_validate_replacement`'s marker check use the LAST
`<!-- id:XXXX -->`; `lib-typed-edges.sh:22` `head -1` is the third consistency site named in the
item). Actionable `[ROUTINE]` queue now: `id:cd9c` + `id:cc7e` (2); the other 4 open `[ROUTINE]`
items (`d4ca`/`540f`/`c179`/`554b`) all carry live gates.

- [x] **Inbox dead-letter `routed:c8d7 → [dotclaude-skills]` is unrouted into this repo's ledgers.**
  `relay-doctor` (`scan-routed.sh`) reports an inbound `/meeting --triaged` design item destined for
  dotclaude-skills but absent from `TODO.md`/`ROADMAP.md`. It is a **design-judgment** item (new
  `/meeting` switch with a schema-definition sub-task, gate-verification semantics, and a cross-repo
  edge-ownership question) — a `/meeting` candidate, NOT auto-promotable to ROADMAP. Human: ingest it
  into `TODO.md` as a meeting candidate or discard the inbox line. Surfaced report-only per review.md §4b.
  **RESOLVED 2026-08-14 (`/relay human .`, tier-a auto-answer) — the item IS ingested; the dead-letter
  is cleared.** It landed as `TODO.md:672`, an open `[INBOUND routed:c8d7 from escapement]` line carrying
  a fresh `id:948c` and the full design text — the `/meeting --triaged` switch with all five recorded
  constraints (a)–(e), including the schema-definition sub-task (c) and the cartulary edge-ownership
  boundary this box named. It is filed as a **meeting candidate in TODO, NOT promoted to ROADMAP**,
  which is exactly the disposition this box asked for. Ingest happened in the 2026-08-14 inbox drain
  recorded at REVIEW_ME:628 (15 auto-filed by `scan-routed.sh --apply`). Evidence, re-checkable:
  `scan-routed.sh` reports `0 dead-letter/unresolved`; `inbox-scan-repo.sh dotclaude-skills` exits 0
  with nothing surfaced; `grep -n 'routed:c8d7' TODO.md` matches the anchored `[INBOUND routed:c8d7 …]`
  ingest marker (not a bare-token prose mention — the [[inbox-twin-check-bare-token-false-resolve]]
  hazard was checked for explicitly and this is a genuine ingest, verified by reading the line body
  against this box's own description of the item).

## Review 2026-08-13e (window last-reviewer-ckpt `relay-ckpt-20260813-2213`..HEAD `-2222` — id:259f execute)

Trust-but-verify over the `id:259f` executor (sonnet) unit. HEAD `-2222` is the executor's OWN
checkpoint, so `$LAST..HEAD` is empty; audited the real window `-2213` (last **reviewer** ckpt) →
HEAD instead. `gaming-scan.sh` clean; full suite **420 passed / 0 failed / 1 expected-red**;
contract pointer v12 == canonical v12.

**`id:259f` VERIFIED genuine-green (not gamed, not over-reach).** One-line fix to
`meeting/classify.sh` gate detector: `gated?|gate:` → `\bgated?\b|\bgate:` (word-boundary anchor).
The RED spec `test_classify_gate_word_boundary_259f.sh` was authored at handoff (`60a9208`),
UNMODIFIED by the executor (resurrection check trivially passes), and went RED→GREEN by the
implementation change alone. §2d over-reach: NONE — the diff matches the TODO item's OWN stated
remedy (`\bgated?\b`, "check the other alternatives similarly"); the untouched multi-word
alternatives (`reopen (gate|trigger)`, `condition-triggered`, `blocked on`) have no substring-FP
hazard, so leaving them is correct, not under-reach. Closed + archived (`ROADMAP.archive.md`);
TODO twin ticked. The archive commit `a4d1aed` moved ONLY `id:259f` (verified `[x]`) — no un-done
item swept. Resolves the `id:259f` owner-call box from 13c (approach A shipped).

`routine_open` = **0** — no ungated, non-`@container` open `[ROUTINE]` remains (13d's sole
candidate `id:d119`'s ROADMAP twin has since closed+archived). The 5 open `[ROUTINE]` items
(`1255`/`1380`/`c179`/`1397`/`f91a`) are all `🚧 GATED` (owner/technical) or `@container`;
`classify-repo.sh --emit` agrees (`actionable_routine_open=0`). Nothing reopened.

Re-derivation edit: added `@container` to `id:ae08` (was DECOMPOSED into seams `02b2`/`99e5`/`5b12`
but still wore an `[INPUT — decision]` lane → roadmap-lint DECOMPOSED-CONTAINER; not ticked
because seams `02b2`/`99e5` remain open, `5b12` closed).

- [x] **`id:d119` cross-ledger drift — SAME id reused for two different scopes; ROADMAP half shipped, TODO half genuinely still open.** `id:d119` is `[x]` CLOSED in `ROADMAP.archive.md:4015` (scoped "roadmap-lint *recognizes* an OWNER-HOLD marker & suppresses its false DEAD-GATE — linter only") but `[ ]` OPEN in `TODO.md:732` (broader: *apply* the owner-hold marker onto `id:540f`/`id:c179` in place of their dead `gated-on:b0b1` + the marker grammar). The remaining TODO work is genuinely incomplete — **evidence:** `roadmap-lint` STILL emits false DEAD-GATE for `540f`/`c179` this pass, i.e. the owner-hold marker was never written onto them. So do NOT auto-tick the TODO twin (would mark undone work done). `orphan-scan --cross-ledger` missed this (archive blind spot — already tracked as inbox dead-letters routed:42c9/8b21). **Owner/handoff call:** either mint a fresh id for the "apply-the-marker + grammar" remainder and re-scope the TODO d119 line, or confirm the remainder is intended and leave it — not a review auto-fix. **OWNER-DECIDED 2026-08-14 (`/relay human .`): MINT a fresh id for the apply-the-marker remainder.** `id:d119` is re-scoped in `TODO.md` to the SHIPPED slice only (roadmap-lint *recognizes* `<!-- owner-hold:REASON -->` and suppresses its false DEAD-GATE — linter-only), matching the archived ROADMAP half, so the two views agree. The genuinely-open remainder — (a) migrate `id:540f`/`id:c179` off their dead `gated-on:e62c,b0b1` onto the confirmed `owner-hold:` marker AND (b) teach `classify-repo.sh`'s dispatch gate to honour it, **as one atomic change** — is filed as **`id:b8e8`**. The marker spelling was confirmed in the same pass (see the id:d119 grammar box below). Note the false DEAD-GATE for 540f/c179 is EXPECTED to persist until `id:b8e8` lands — the linter recognizes the marker, but nothing has written it onto those two lines yet.
- [x] **Install-drift: `relay/scripts/roadmap-tick.sh` is in the repo + declared in `relay_FILES`, but its `~/.claude/skills/relay/scripts/` symlink is MISSING** (relay-doctor install-drift, id:1102). This is the v12 tick-ownership script the serialized integrator uses to tick ROADMAP checkboxes from `worked_ids`. Report-only, but if the live integrator resolves scripts through the installed skill path it can't tick — run **`make install-relay`** (or `make install`) on zomni to regenerate the symlink. Install-state, not repo content, so not fixable in this worktree. **RESOLVED 2026-08-14 (`/relay human .`, owner-approved) — `make install-relay` RUN on zomni.** Evidence: `ls -l ~/.claude/skills/relay/scripts/roadmap-tick.sh` now resolves to `/home/tobias/src/dotclaude-skills/relay/scripts/roadmap-tick.sh`, and `check-install-drift.sh --canonical <repo>/relay --installed ~/.claude/skills/relay` reports `OK — fully mirrored (scripts + source targets)`. Re-checkable by re-running either command. The RECURRENCE gate is a separate owner decision — see `TODO.md` id:83c3, decided this pass.

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

## Review 2026-08-13c (window `relay-ckpt-20260813-1850`..HEAD — 5 commits)

Clean verification pass over the `id:3bf3` `/meeting` C1 inline close (disposition-routing
surface). `gaming-scan.sh` clean; full suite **414 passed / 0 failed / 1 expected-red**.
Test-integrity VERIFIED not gamed: the new `tests/test_classify_disposition_contract_3bf3.sh`
is a genuine BEHAVIOURAL test — it runs `meeting/classify.sh` against a fixture `TODO.md` and
asserts on the emitted TSV columns (STATE/GATE axis, 5-column arity+order contract, the
`{C1,C2,C3}` pickable vs `{RELAY,POOL,EXEC,MECH,HANDS,HUMAN}` skip partition), not a source
grep; RELAY_LOG records mutation-verification against 3 independent `classify.sh` mutations.
Over-reach (§2d): none — the diff adds only a test, no `classify.sh` behaviour change, and the
executor UNDER-reached honestly (found the LANE axis already covered by
`test_classify_hard_lanes.sh` and scoped only the complement). `id:3bf3` ticked + archived
correctly (zero ROADMAP refs, so single-id-two-views needs no second write).
`actionable_routine_open` = **0** — unchanged from 13b (the 4 real open `[ROUTINE]` items stay
`🚧 GATED`, `id:f91a` is an `@container`). Nothing reopened. One box below for the newly-filed
`id:259f`.

- [x] **`id:259f` (classify.sh gate detector substring false-positive) — owner call on WHETHER/HOW to tighten.** ✅ RESOLVED via **approach A**: promoted to ROADMAP with a word-boundary RED spec (handoff `-2142`), executed at `-2222` (`\bgated?\b|\bgate:`, `meeting/classify.sh`), and VERIFIED genuine-green this review (2026-08-13e) — `test_classify_gate_word_boundary_259f.sh` passes, no gaming, not a superset (the fix matches the TODO item's own stated remedy). Closed + archived in ROADMAP; TODO twin ticked. If you prefer approach B, the change is a trivial one-line revert. Original box: the executor filed this as a `[ROUTINE]` item after discovering `classify.sh`'s gate pattern matched the bare substring `gate`, so *investigate*/*mitigate*/*aggregate*/*delegate*/*navigate* all rendered `[GATED]` in every `/meeting` bucket summary.

## Review 2026-08-13b (window `relay-ckpt-20260813-1618`..HEAD — 21 commits, all owner-authored)

Clean verification pass over the FIX-and-bookkeeping response to the 16:18 review's findings
(plus a `/meeting` amendment and a `/relay human` pass). No executor units. `gaming-scan.sh`
clean; suite **411 passed / 0 failed / 1 expected-red** (`roadmap:6217`, an open decision-gated
item — legitimate). Test-integrity VERIFIED not gamed: the load-bearing
`test_reconcile_stranded_liveness_b99f.sh` was run side-by-side and FAILS against the pre-fix
`relay-reconcile.sh` (whole-line `grep -qxF` against a bare runId — gate could never fire),
PASSES against the jq `.runId` fix; genuinely non-vacuous. Cross-ledger clean; contract pointer
v11 == canonical. `actionable_routine_open` = **0** (all 5 open `[ROUTINE]` items gated or
`@container`). Nothing reopened. One advisory box below.

- [x] **GATE-STALE (`orphan-scan --shipped`): `id:6c6e` "Better sudo-elevation mechanism than plain `ssh-askpass`" — its gating clause is now 23 days old (>=14d threshold); re-check whether the gate has lapsed.** `[INPUT — meeting]` design item, so this is a human re-read, not executor work — surfaced per review.md §5(b3ee), advisory only.

  **RESOLVED 2026-08-14 (`/relay human .`) — the gate was re-read and the item RE-SCOPED, so the staleness is discharged.** The 24-day-old clause reflected that no design session had happened, not that the problem had gone away. The owner ruled: carve out failure mode (1) — an anonymous askpass popup gives no session/agent/command attribution, so elevation cannot be judged — as buildable NOW, and re-laned `id:6c6e` from `[INPUT — meeting]` to `[ROUTINE]` with an explicit Acceptance clause. Whether a `/meeting` is still warranted for the remainder is deliberately deferred until the attribution half ships and is used: `id:18ce`, gated on `id:6c6e`. Re-checkable: `id:6c6e` is no longer `[INPUT — meeting]` and no longer appears in the `hard_meeting` bucket.

## Review 2026-08-13 (window `relay-ckpt-20260812-1417`..HEAD — 13 commits)

Window is ledger-heavy: one `/meeting --fabled` session (`id:55f6`), two relay-script fixes
(`ef43739`, `82643ab`), one `meeting/append.sh` fix (`89f6e1c`), and gate/handback bookkeeping.
Suite 400 passed / 0 failed / 1 expected-red (`roadmap:6217`, still open — the red test is the
spec). `gaming-scan.sh` clean. Cross-ledger drift clean. `actionable_routine_open` stays **0**
after re-derivation — the gate re-target did NOT make `id:d4ca`/`id:e405` actionable
(`resolve-gates.sh` reports `d4ca 1 ⟨empty⟩`, `e405 1 ⟨empty⟩`: block=1, zero dangling).

Boxes for the human:

- [x] **Dispose the now-fully-SUPERSEDED stranded branch `relay/relay-20260812-122721-23819-review-repo-0` — DONE 2026-08-13 (owner-confirmed).** Verified before disposing rather than on the salvage claim: the test file is byte-identical in main; 9 of its 10 `REVIEW_ME` lines are present in main; the 10th (a relay-doctor install-drift box) was NOT salvaged, but its finding was STALE (`mech-currency.sh` was symlinked at 12. Aug 17:14 and `check-install-drift.sh` reports the relay tree fully mirrored) and its live standing question was rescued as `id:83c3`; the dropped `ROADMAP.md` hunk belongs to `id:ed3f`, `[x]` and archived. Retired force-free via `worktree-retire.sh` (the worktree was still on disk — it had never actually been parked), which parked the unmerged ref, then discarded under `RELAY_DISCARD_CONFIRM=1`. Three further merged-but-unretired worktrees from the same run were found and retired in the same pass — filed as `id:8132`, since nothing surfaces them. Doc incoherence found en route: `id:331a`.
  - **DEFERRED 2026-08-13 (owner): do not dispose yet — re-verify the classification once `id:b99f` lands.** `relay-reconcile.sh:222` matches liveness with `grep -qxF` against a bare runId while `heartbeat.sh live-runs` emits JSON lines, so the liveness gate CANNOT fire and **every** unmerged branch is currently labelled STRANDED regardless of whether its owning run is alive (verified 2026-08-13 against live output). Disposing on the strength of a classifier that is known to be stuck-on is exactly the hazard `id:b99f` describes — the recommended next step for a STRANDED branch is `--discard`. The byte-identical salvage evidence above still stands on its own; what is deferred is trusting the STRANDED label. Re-run reconcile after the fix, confirm this branch still classifies as disposable, then dispose. `id:e53a` compounds it: a parked orphan currently hides the stranded section entirely.
- [x] **`edbc462`'s salvage correctly dropped the `id:ed3f` ROADMAP hunk — no action needed; noted only for the over-reach it concealed.** My first pass called this a possible gap because I grepped only `ROADMAP.md`; **that was wrong** — `id:ed3f` is `- [x]` at `ROADMAP.archive.md:3999`, so the item was legitimately closed and archived and re-adding an open hunk would have been the error. The salvaged test passes, and by genuine implementation (`5c425fc` really did teach the linter `dispatchGuarded`; the test was not weakened — verified byte-identical to the branch copy). The one residue worth your eye: the salvaged spec prose contains the clause that `id:3d78` now flags — the ratified text says `agentGuarded`/`safeAgent` *"do not exist — do not invent matchers for them"* while the shipped linter matches both. The spec came back without a live item, so nothing was positioned to notice the contradiction; `id:3d78` is now that item. Also stale-but-harmless: the test's header still says "EXPECTED-RED until id:ed3f is ticked in ROADMAP.md" — `run-tests.sh` greps `ROADMAP.md`, where `ed3f` no longer appears, so a future regression counts as a REAL failure rather than being masked. <!-- id:3d78 -->

## Review 2026-08-12 (chain-end re-ask, window `relay-ckpt-20260812-0915`..HEAD — id:8123)

Window carries **no executor code/test work**: 9 mechanical inbox ingests (`id:678e`, cross-project routed items appended to `TODO.md`), one `meeting/personas.md` Ada extension (`e601f79`, from escapement id:4982 — a non-destructive in-place persona edit, not gaming), and the archive move of the three already-verified provisioning-cluster closes (`76d2`/`9834`/`3222`, PASS'd by the prior review `e3ff3ec`). `gaming-scan.sh` clean; cross-ledger `orphan-scan` clean; contract pointer v11 == canonical v11; full `tests/run-tests.sh` **394 passed, 0 failed, 2 expected-red**. Nothing to reopen.

Actions taken this pass:
- **`id:ed3f` qualified (was NO-ACCEPTANCE-NO-TWIN per roadmap-lint; it is the single `actionable_routine_open`).** Added a BDD Acceptance + Tests + Done-check + Context clause (reusing the id) and authored the RED spec `tests/test_mech_model_lint_dispatchguarded_ed3f.sh` (`# roadmap:ed3f`, EXPECTED-RED — proven genuinely red: the linter passes a fence-carrying `dispatchGuarded('…', model:'bash')` sample it should flag). Scope corrected in-place: the Fix prose named `agentGuarded`/`safeAgent`, which **do not exist** — `dispatchGuarded` is the only guard wrapper in the tree. The re-enqueued execute now has a workable spec.
  - **SUPERSEDED-IN-PART 2026-08-12 (apex salvage turn).** This review branch never merged — it hit a ROADMAP.md conflict against the execute unit that was shipping `id:ed3f` **concurrently** (integrate `relay-ckpt-20260812-1240`). `id:ed3f` is now `[x]` in `ROADMAP.archive.md:3999` and the fix is live (`lint-mech-model.mjs:59`, `AGENT_CALL_IDENTIFIERS = {agent, dispatchGuarded, agentGuarded, safeAgent}`). So the branch's **ROADMAP hunk was deliberately DROPPED** — re-adding planning prose for shipped, archived work is exactly the stale-restatement drift CLAUDE.md warns about. Its **test file was KEPT and is now GREEN** (6/6). That is worth more than it looks: the spec was written by the reviewer WITHOUT sight of the executor's implementation, so it is genuine independent verification of `id:ed3f` rather than the same agent grading its own work ([[feedback-verify-delegated-work-independently]]). Note the reviewer's scope correction was right about the tree at the time and the shipped code went WIDER (it also matches the two wrapper names the reviewer correctly said do not exist — harmless, but they match nothing).

Boxes for the human:

- [x] **9 freshly-routed INBOUND `TODO.md` items (12:27 ingest) triaged, NOT promoted — owner/next-handoff call.** Reverse-handoff (§5b): these arrived via the mechanical inbox daemon and every one concerns the relay's OWN in-flight dispatch machinery, so I did not unilaterally author RED specs / promote them (CLAUDE.md: don't reshape a shared plan mid-flight; owner is domain expert). Triage:
  - **Execution-ready-but-clustered** (cheap `classify-*`/splitter fixes, but siblings that want joint design — two of them explicitly cross-reference each other as over- vs under-report duals): `id:4d6b` (dispatch REASON string counts raw not gate-resolved `[ROUTINE]`), `id:b724` (`classify-repo.sh` `blocked` is an UNANCHORED substring — incidental prose re-imposes a gate), `id:7756` (`id:3801` splitter mints seam ids by lifting a token out of the seam's own subject text instead of `append.sh new-id`). A handoff turn should promote these with RED specs; `4d6b`+`b724` are the classify over/under-report pair, do them together.
  - **Design/owner-gated — `/meeting` candidates, leave as TODO**: `id:795d` (classify-verdict `[HARD]`-starvation ordering — "owner decision / meeting, not a snap flip"), `id:cd9c` (roadmap-archive stub-per-item — "DESIGN CALL REQUIRED, do not guess"), `id:2419` (`/meeting` same-turn-AskUserQuestion protocol regressing on Opus — investigation), `id:f916` (no-NIH mechanical detector — CLAUDE.md rule change), `id:6d01` (mechanical-proxy restart kills in-flight agents — proxy behaviour/logging), `id:bf54` (`id:8df5` escalation trigger fired a 3rd time, n=3 — evidence for the deferred per-decision Fable pass; feeds `id:8df5`, still unfiled).
- [x] **relay-doctor install-drift: `relay/scripts/mech-currency.sh` is declared in the Makefile `relay_FILES` but not symlinked into `~/.claude/skills/relay/`.** Same invisible-`make install`-drift class the 2026-08-11 apex review left for a human (5 scripts then). Host-side, not a worktree defect — resolve with `make install-relay`. Worth the standing decision that review left open: gate `make install` after a manifest touch, or promote relay-doctor's install-check to `--strict` in some path.
  - **RESOLVED 2026-08-12 (apex salvage turn)** — ran `make install-relay`; `ls -l ~/.claude/skills/relay/scripts/mech-currency.sh` now resolves to the repo file. **The standing decision this box raises is NOT resolved and got a live confirmation the same hour**: this turn added `relay/scripts/lib-roadmap-sections.sh` (id:4b8f) and, between the source edit and `make install`, the INSTALLED `gather-repo-state.sh` — a symlink, so already live — sourced a lib that did not exist at the installed path and died with `No such file or directory` on every call. A source-only edit can therefore BREAK the running fleet for the window before someone remembers to install, and nothing warns. `tests/test_relay_install_manifest.sh` caught the missing Makefile entry (good), but it is a *test*, not an install gate. Owner's call on the mechanism (install gate vs relay-doctor `--strict` in the pool's own preflight).
- [x] **Inbox dead-letter `routed:7b8f` → `[dotclaude-skills]` (id:8df5 escalation, `--fabled` 6-forced-findings firing) is absent from `TODO.md`/`ROADMAP.md`.** `id:8df5` (the per-decision Fable-pass / multi-pass design item) has never been filed as a workable item; `routed:8552`/`id:bf54` (ingested this window) is a SECOND breadcrumb for the same id (the n=3 firing). Route via `scan-routed.sh --apply` or file `id:8df5` — owner's call on the design, not build work.

- [x] **id:7681 — coverage grep-SCOPING for the arg-guard's `--coverage` mode (handoff 2026-07-21).** — **CONFIRMED 2026-07-23 (relay human): the as-built scoping is right, with one follow-up.** Verified against `relay/scripts/validate-flags.sh:105-155`: /relay scopes to the `Invocation:` fence MINUS the `/relay inject|stop` lines (their `--item`/`--verdict`/`--prompt`/`--now` are subcommand-owned args, not top-level guard flags) PLUS the `## Configuration knobs` table's FIRST column only (the Effect prose column mentions `--exclude` etc. in passing and is correctly excluded) — neither missing a real switch nor bloating the manifest, exactly the recommendation this box made. **Follow-up filed → TODO id:cdcf**: the /meeting branch scopes via a single `grep -i "skill argument"` on SKILL.md, so one reworded sentence silently empties the scoped region and `--coverage` passes VACUOUSLY (a drift guard that cannot fail is worse than none) — give /meeting a real anchored marker/fence and assert the scoped region is non-empty. `tests/test_unknown_switch_guard.sh` (`# roadmap:7681`) drives `validate-flags.sh <skill> --coverage <SKILL.md>` and asserts exit 0 = every INVOCATION flag documented in a SKILL.md is in that skill's manifest. The judgment call the RED spec deliberately does NOT pin: **which `--flag` tokens in a SKILL.md count as invocation flags.** Both SKILL.md files mention many helper-script flags in prose that are NOT `/meeting`·`/relay` switches — `meeting/SKILL.md` has `--mode`, `--apply`, `--commit`, `--show-toplevel`, `--query`, `--reverse`, `--root`, `--run`, …; `relay/SKILL.md`'s top block alone has `--item`, `--verdict`, `--prompt`, `--now`, plus git's `--no-ff`/`--ff-only` and script sub-flags. A naive `grep -oE '\-\-[a-z]+'` over the whole file would demand ALL of these in the manifest (unsatisfiable) OR force the manifest to bloat with non-invocation flags (defeats the guard). The executor must scope the coverage grep to real invocation flags (my recommendation: the invocation code-fence + the `## Configuration knobs` table rows for /relay; the invocation line + `--fabled`/`--cross` for /meeting) and single-source that scoping inside `--coverage`. **CONFIRM**: is the scoping right — neither missing a real switch (guard would false-warn on it) nor pulling in helper-script prose flags (manifest bloat)? Re-check on the next `/relay review`. Related: id:7e87 (gated-on 7681), id:0e56.

- [x] **id:a286 — `make test` is RED: id:34c2's integration (febb0c3) introduced a bare `rm -f`
  in `meeting/append.sh:384` that trips the repo's own `check-no-bare-rm-f.sh --enforce` lint
  (baseline 0), so the `lint` tier of `make test` now FAILS for every consumer** (review
  2026-07-17). The unit test tier is fully green (256 passed, 0 failed) — this is purely the
  new lint violation. The line is `rm -f -- "$tmp_check"` where `tmp_check` is a known-present
  `mktemp` file, so the CLAUDE.md destructive-op-hygiene fix is a one-liner: `rm -- "$tmp_check"`
  (or annotate `# force-ok: <reason>`). Filed as ROADMAP `[ROUTINE]` id:a286 (this pass could
  not fix it — the review's safety constraint bars touching `meeting/*.sh`). Root cause is a
  spec/lint gap in the id:34c2 handoff: the RED spec did not gate on the lint tier passing.
  **RESOLVED 2026-07-19 (relay human, verified):** the bare `rm -f` is gone from `meeting/append.sh` (grep clean), `tools/check-no-bare-rm-f.sh --enforce` = 0 violations within baseline, full suite 262/0/3-xred green. The root-cause lesson (a RED spec not gating on the lint tier) is exactly what the freshly-prepared **id:66d4** tier-coverage checkpoint gate enforces.

- [x] **relay-doctor findings (review 2026-07-17, report-only, non-blocking).** Four are the
  cross-ledger drift this review RESOLVED in-pass by ticking the TODO twins of the integrated
  items (id:34c2, id:de36, id:1735, id:1102 — ROADMAP `[x]`, TODO was `[ ]`). Remaining, for a
  human's call: (1) **one parked orphan branch** `relay/orphan/blind-e02a-spec` in the loderite
  repo (a blind RED spec, `2c03545`) — cross-repo, not this repo's disposition; (2) **one inbox
  report-only finding** — a `[lodelore]` ORIGIN-MYTH item (`orphan 132`) whose `routed:` marker
  is a literal `$ID` placeholder, so it is not routable; a cross-project inbox line, not a
  dead-letter here. Neither blocks. relay-doctor otherwise clean (roadmap-lint clean, TODO
  conformance clean, main-checkout residue clean, last_ckpt resolves, no mechanical orphans).
  **RESOLVED 2026-07-24 (relay human, both findings verified GONE).** (1) The parked orphan is
  gone: `relay-reconcile.sh --all` this session reported **0 parked orphans across all own
  repos** (48 repos swept — 54 `own` minus 6 `paused`), and `git -C ~/src/loderite for-each-ref
  refs/heads/relay/orphan/` is empty, so `relay/orphan/blind-e02a-spec` no longer exists.
  (2) The literal `$ID` placeholder is gone from the shared inbox (`grep '$ID'` → no match);
  the one remaining `[lodelore]` line now carries a proper `routed:33db` marker, so it is
  routable. Nothing left for a human here.
- [x] id:6e02 — LIVE-worktree sweep incident (2026-07-01 ~22:56): this review's own
  explicitly-created worktree + branch were deleted ~1 min after creation, mid-test-run,
  WHILE ~/.config/relay/claims/dotclaude-skills.json held a live claim (22:55:01). The
  child recovered (recreated + marker commit so tip≠main). No relay-loop was running
  (events end 20:45); reconcile log shows nothing at 22:5x — most consistent with an
  orchestrator-side cleanup treating a zero-commit branch (tip==main, `branch -d`-able)
  as an integrated leftover. Filed as TODO id:6e02 [HARD — meeting] (sweeps must honor
  claims; child setup should marker-commit first). Orchestrator: please confirm/deny
  running a worktree cleanup at ~22:56 so the finding pins the actual actor.
  ORCHESTRATOR ANSWER 2026-07-01: NOT the orchestrator (this session ran no cleanup at
  22:5x). Actor pinned by the bugfix child: run relay-20260701-225242-28925's dotclaude-skills
  integrator (dispatched 22:52:45, lease-refused handback ~22:56) applied its "tip-is-ancestor
  ⟹ integrated leftover" cleanup to a branch it didn't create, AFTER releasing the lease.
  Cleanup is now scoped to own-runId artifacts only (relay-loop.js, merged 2026-07-01); the
  remaining DESIGN CALL — destructive cleanup under-the-lease vs release-first (id:ebfb
  ordering) — is TODO id:6613 [HARD — meeting]. Box stays open only for that meeting call.
  **CLOSED 2026-07-23 (relay human): the box's own question is fully discharged** — the
  confirm/deny was answered (NOT the orchestrator; actor pinned to run
  relay-20260701-225242-28925's integrator), and the fix (cleanup scoped to own-runId
  artifacts) merged 2026-07-01. The residual design call is already tracked as its own
  open `[INPUT — meeting]` item id:6613 and appears in the meeting backlog, so keeping a
  second box open for it double-counts one decision.
- [x] **RE-TRIAGED + CLOSED 2026-07-28 (relay human, owner chose "re-triage the 13 items").**
  Verified every id the doc cites against its OWN repo's ledgers: **16/16 are OPEN and
  correctly lane-tagged `[INPUT — access]` there** (one, the zkm Signal pilot, lives in the
  `zkm-signal` plugin ledger rather than the parent — tracked, not missing). So the doc holds
  **zero untracked work**: it is a derived cross-repo VIEW whose only added value is the
  unlock-per-minute RANKING, and each target repo's own `/relay human` already surfaces its
  items. Nothing to promote here — and nothing could be, since the fleet enumeration must not
  land in this public file. The ranking is exactly what **TODO id:c3f6** (mechanize the
  keystone-unblock triage as a `/relay human --keystones` gate-graph view) exists to replace;
  until that ships the private doc stands as the hand-maintained ranking. Verification stamps
  recorded in the private doc itself. Box closed — the standing pointer is id:c3f6, not this box.
  Original box text: Human-sprint 80/20 checklist (2026-07-02 Fable consulting session): pre-triaged
  tier-1 (minutes-each) + tier-2 (session-each) [HARD — hands] tasks across the fleet,
  ranked by unlock-per-minute — lanes already decided, context linked per item. Lives in
  the PRIVATE diary repo (fleet enumeration must not land in this public file):
  `~/src/claude-diary/docs/2026-07-02-human-sprint-8020.md`. Next `/relay human` should
  present it as the "you run these" checklist and tick items THERE; close this box when
  that doc is fully worked or superseded.
- [x] **id:b780 — a review child FIXED a flaky test in-flight; confirm that was in scope.**
  `tests/test_isolation_gate_wired.sh` intermittently failed (measured 1/25 idle, 22/40 under
  CPU load) via a >64 KB `printf | grep -q` SIGPIPE race under `pipefail` — grep matched
  (PIPESTATUS=[0]) but printf died 141 and pipefail promoted it to a failure. I fixed it here
  rather than only filing it, because the flake red-lights `make test` — the definition-of-done
  gate every execute unit depends on — and it indicts the id:7612 isolation gate, which is
  exactly the wrong signal. Mutation-tested (3/3 broken-gate variants still caught) so the spec
  is intact. **If you'd rather review children never touch non-ledger code, say so** and this
  becomes a [ROUTINE] item instead; the fix + evidence are in the commit either way.
  **RULED 2026-07-19 (relay human): OUT OF SCOPE.** A review pass returns a verdict; it does not mutate non-ledger code — a verifier that can fix the artifact it verifies can launder its verdict (chidiai `a-relay-review-sub-agent-scoped`; reviewer-read-only, now load-bearing in id:0c86/077d). The already-committed fix STAYS (correct + mutation-tested), but going forward such a fix is a HANDBACK / separate execute unit, not a review action — enforced structurally via id:077d/0c86.
- [x] **id:521f / routed:f1f5 + id:1312 — same defect class, possibly one fix.** Both are
  unanchored token greps over prose-bearing ledger lines (roadmap-lint's first-match `id_re`;
  unpromoted-scan's bare `grep -qF`). `scan-routed.sh` already anchors correctly. This is the
  4th instance of the family (with `inbox-done`'s substring match and md-merge's fail-open
  append, id:1b1a). **Worth one shared anchored-extraction helper + its own test rather than a
  third hand-rolled copy?** That's a design call, not a review verdict — hence a box, not a
  ROADMAP decision. Related: the id:2c94 duplication linter would flag the copies mechanically.
  **DECIDED 2026-07-19 (relay human): BUILD one shared anchored-extraction helper + test** (dedup the 4th instance of the family; route roadmap-lint's first-match `id_re`, unpromoted-scan's `grep -qF`, and the copies through it — model it on `scan-routed.sh`, which already anchors correctly). Filed as `[ROUTINE]` id:3add.
- [x] **Repo-wide: is the `printf "$big" | grep -q` + `pipefail` pattern worth a lint?** id:b780
  was one instance; 23 files pair `pipefail` with an early-exiting reader on a pipe. Only
  payloads >64 KB (the pipe buffer) can bite, so today `relay-loop.js` (91 KB) is plausibly the
  sole live case — I did NOT sweep or "fix" the others, per observe-before-preventing. Recorded
  so the decision is yours: leave it, or add a check to `tools/` if it recurs. Note any such
  lint must run under real `bash` — under `zsh` the race does not reproduce at all.
  **DECIDED 2026-07-23 (relay human): LEAVE IT — no lint.** One instance in one file is not
  evidence of a class; per the CLAUDE.md *observe-before-preventing* heuristic, don't build
  a guard on speculation. Revisit only if a second instance actually bites (the >64 KB
  payload precondition makes that rare — `relay-loop.js` is plausibly the sole live case).
- [x] **id:de31 — `orphan-scan --shipped` says TICK-READY; I verified it and did NOT tick.** — **RESOLVED 2026-07-23 (relay human, owner sign-off "split the unspecced halves into own ids"):** de31's ROADMAP item is already `[x]` (ROADMAP.archive.md), but its two under-verified halves are now carved into their own open TODO ids so nothing reads as done-that-isn't — **id:8cb8** (forced-resolution WRITE at lane-triage; case g/h can never silently no-op) and **id:dda6** (conservative inline lane-triage sub-agent). Each gets its own RED spec on the next `/relay handoff`. Box closed; the generalizable point below (TICK-READY can't see a test's scope is a subset of the item's acceptance) stands as a recorded observation.
  The scan is right that `tests/test_decision_queue.sh` is green with no gating lexeme, but the
  test's own header declares a NARROWER scope than the item: "In scope here: the record format
  + the flock'd add/list/resolve helper." C7 (id:de31) additionally requires *the forced-
  resolution WRITE at the lane-triage point (case g/h can never silently no-op)* and *the
  conservative inline lane-triage sub-agent* — neither is exercised. Ticking on the green test
  would freeze the item's harder half as "done". Recorded so the next review doesn't re-litigate
  the same advisory hit. **The generalizable point**: TICK-READY correlates an item to a linked
  test but cannot see that the test's declared scope is a SUBSET of the item's acceptance — so
  a partially-specced item reads as shippable. That is inherent to the heuristic (it is advisory
  by design, which is why §5 mandates this manual verify), but if this recurs it argues for
  scope-declaring test headers being machine-read, or splitting C7's remaining halves into their
  own ids. Your call — no ledger change made.
- [x] **id:eb46 — promoted [ROUTINE], but its lane may need to flip to [INPUT — user].** The
  handoff promoted the "relay children need a failing askpass (`SUDO_ASKPASS=/bin/false`) so a
  sub-process `sudo` can't pop a GUI prompt" item as `[ROUTINE]` with a built-in BAILOUT GUARD:
  if the ONLY reachable env-injection point turns out to be `~/.claude/settings.json` `env`, the
  executor must STOP and re-lane `[INPUT — user]` rather than edit settings.json from a worktree
  (that file is deliberately relay-untouched). The judgment call for the human/reviewer: is there
  an in-repo/pool-launch injection point at all, or is this really a settings.json change (hence
  `[INPUT — user]`, not executor-pool work)? `relay-loop.js` spawns children via the Workflow
  `agent()` API with no reachable `process.env` inside the sandbox (L1907), so the env is set at
  pool launch OUTSIDE the repo — which makes the settings.json outcome plausible. Recorded so the
  next executor's bailout (or the reviewer's re-lane) isn't re-litigated. No fresh RED test (the
  fix's location, not its logic, is the open question). **RESOLVED 2026-07-19 (relay human): the settings.json path is confirmed and DONE** — `SUDO_ASKPASS: "/bin/false"` is live in `~/.claude/settings.json` `env` (applied by cd4d20a). ROADMAP id:eb46 is already `[x]`; naive-case containment is in place, deeper OS-level containment tracked as id:5937. No lane flip needed. <!-- roadmap:eb46 -->
- [x] **id:ac7f — handoff-authored interface for the `drained` render-alias.** The RED spec pins a NEW `relay/scripts/render-verdict.sh` (stdin classify-verdict JSON → label; `idle`→`drained`, else verbatim) as the D1 render-alias home. D1 mandates "render-alias, no new enum" but names no script — this interface is the handoff author's choice among defensibles (a separate script vs. a flag on an existing renderer vs. a reviewer-prose convention). Confirm the separate-script shape is what you want before the executor builds it. — **CONFIRMED 2026-07-19 (relay human): separate `render-verdict.sh` is the intended shape.** As-built matches; no change. <!-- roadmap:ac7f -->
- [x] **id:66d4 — tier-enumeration + toolchain-marker heuristics chosen by the spec.** `test_review_gate_tier_coverage.sh` exercises ONE declared-tier source (package.json `scripts` keys containing "test") and ONE toolchain-presence marker (populated `<dir>/node_modules`). The item also names Makefile targets / CI config / `~/.cache/ms-playwright` — the executor may add them, but the spec only proves the package.json+node_modules path. Judgment: is that enough coverage for the gate's first cut, or must the RED spec also pin a Makefile-tier fixture? — **RULED 2026-07-19 (relay human): NOT enough — the RED spec MUST also pin a Makefile-tier fixture.** The shipped `review-gate.sh` already enumerates Makefile `test`-named targets, but the test only proves the package.json path, so that code path is unspecced. Follow-up filed → TODO id:050b (add a Makefile-tier fixture to the RED spec). <!-- roadmap:66d4 -->
- [x] **id:78df — consumer-enum is a content-grep listing aid, not import-graph analysis.** `test_consumer_enum.sh` pins `consumer-enum.sh <artifact>` = "every file whose CONTENT references the token, .git excluded, exit 0 always". It does NOT resolve real import/read edges (a false positive on a mention-in-a-comment is accepted — it is a surfacing aid, per D6/id:78df "listing aid, not a gate"). Confirm the plain-grep semantics are the intended aid. — **RULED 2026-07-19 (relay human): NOT the intended endpoint — it should resolve real import/read edges, not text mentions.** The shipped content-grep aid stands as the first cut; the upgrade to import-graph analysis is filed as follow-up → TODO id:494f. <!-- roadmap:78df -->
- [x] **The "promote backlog" is mostly PHANTOM/mis-classified — only id:798d was a real promotion this handoff (run relay-20260719-132549-15264).** `unpromoted-scan.sh` reported 7 `promote` items; on inspection only **id:798d** was clean executor work (promoted with RED spec `tests/test_unpromoted_scan_gated_twin.sh`). The other 6 each carry a lane/scope/identity question a handoff must NOT resolve by guessing (owner-decision territory) — surfaced here, deliberately NOT re-laned or promoted:
  - **id:659c, id:401c — 798d-bug PHANTOMS.** Both already have a ROADMAP twin, but their `<!-- id -->` marker is followed by a trailing gate/DONE note, so the end-of-line-strict twin check (the exact 798d bug) misses them and re-reports the TODO source as `promote`. **Shipping id:798d drains these two automatically** — no separate action.
  - **id:d5e0 — an audit-summary line, not a task.** It is the rolling "Relay: N open ROADMAP items" summary maintained by id:401c's audits; its removal is already owned by **id:1de1** ("drop the count prose once `proj relay`/the id:2840 index is the count authority") and id:4d8e case-(3) explicitly names it as a summary line the classifier should SKIP. It is mis-tagged `[ROUTINE]` → mis-classified `promote`. Do NOT promote; the real fix is the classifier skipping audit lines (id:4d8e) — deliberately retained until id:1de1 ships.
  - **id:2e6d — a mostly-SHIPPED umbrella.** Its core dissolution shipped 2026-07-10 (`tools/memory-index.py` now GENERATES the index; `--check` is the enforcing lint; `hooks/memory-index-sync.py` PostToolUse shipped). Residual = child **id:7d97** (add `user:`-prefix/emphasis invariants to `--check`) + a `[INPUT — user]` settings.json hook install. The umbrella is open+`[ROUTINE]` so it reads `promote`, but there is no fresh executor work in the parent itself — it should be `@container`/closed, a judgment for you.
  - **id:02c7 — OS-ACL access work mis-tagged `[ROUTINE]`.** "Per-directory named POSIX ACLs on `~/.config/relay`" is `setfacl` OS provisioning, part of the os-users design ([[os-users]] — nothing provisioned; needs credential/consent). This is `[INPUT — access]`, not worktree-buildable executor routine. — **RULED 2026-07-23 (relay human): do NOT re-lane to `[INPUT — access]` — KEEP `[ROUTINE]` and apply the author-then-run split (id:e175).** The owner's reading: the `setfacl` calls are *scriptable*, so the authoring half is genuinely worktree-buildable and must not be thrown onto the hands lane wholesale. Split filed → TODO **id:c7c0** (`[ROUTINE]` "author the ACL provisioning script + its RED spec") with the on-device `sudo setfacl` run residue as an `[INPUT — access]` item gated `(DEP: c7c0)`. Only the run residue is hands.
  - **id:3add — a refactor that reopens a recorded decision.** "Shared anchored-extraction helper + test" (relay human 2026-07-19) wants to migrate the 4 hand-rolled extractors onto one helper — but `relay/scripts/lib-anchored-id.sh`'s header (id:521f, lines 14-26) explicitly RECORDS a decision NOT to unify `unpromoted-scan.sh`/`scan-routed.sh` onto it (different problem shape: presence-check vs extract-unknown-id). Promoting 3add requires reconciling with that recorded rationale, and it is a behaviour-preserving refactor (id:108e — unverifiable by a classic RED test; belongs to `/relay refactor`, id:22da). Not a blind `[ROUTINE]` promote. NB: id:798d fixes ONE instance (unpromoted-scan's twin check) of the family 3add would unify — sequence 798d first, then let 3add subsume the pattern.
  - **id:2d20 — targets sandbox-gated `relay-loop.js`.** "Pool busy-loops re-dispatching un-doable HARD units" is a `relay-loop.js` fix; that file runs only in the Workflow sandbox ([[sandbox-2ec4]] — no in-repo mechanical dispatch), so a RED spec cannot be verified from a worktree. Needs the sandbox-testability question answered before it is executor-promotable.
  **Net**: this repo's apparent promote backlog is an artifact of the id:798d bug (2 phantoms) + known classifier gaps (id:4d8e audit-line skip) + three mis-tagged/umbrella items — not undispatched executor work. Ship id:798d; then a human re-lane pass (or id:4d8e's classifier) should stop the pool re-dispatching handoffs here. No ledger re-lanes made (owner's call). <!-- handoff:relay-20260719-132549-15264 -->
  **PARTIAL RESOLUTION 2026-07-23 (relay human).** (1) **id:798d has SHIPPED** — verified `[x]` at `ROADMAP.md:212`, so the two phantoms **id:659c and id:401c are drained automatically**, exactly as predicted; no action. (2) **id:02c7 ruled** — keep `[ROUTINE]`, author-then-run split → id:c7c0 (see above). Box stays OPEN for the three still-unruled dispositions: **id:d5e0** (audit-summary line — retained until id:1de1 ships), **id:2e6d** (mostly-shipped umbrella — close/`@container` is a judgment), **id:2d20** (targets sandbox-gated `relay-loop.js` — needs the sandbox-testability question answered first). **id:3add** is separately superseded: `ROADMAP.md:94` id:3743 already migrates the hand-rolled extractors onto `lib-anchored-id.sh` and is `[x]`.
  **CLOSED 2026-07-24 (relay human): all three remaining dispositions have landed since this box
  was written — verified in the ledgers, no promote is warranted for any of them.**
  (1) **id:d5e0** — archived `[x]` at `TODO.archive.md:456`, marked `[STALE — archived 2026-07-21
  drain run-2: snapshot of since-shipped ids, superseded]`; the audit-summary line the box asked
  about no longer exists, so the "retain until id:1de1 ships" holding pattern is discharged.
  (2) **id:2e6d** — archived `[x] [ROUTINE] @container` at `TODO.archive.md:452` (DONE 2026-07-21
  drain run-2, child id:7d97 shipped); the umbrella got exactly the `@container`-close the box
  called a judgment for the owner. (3) **id:2d20** — now correctly lane-tagged `[INPUT — meeting]`
  at `TODO.md:146`, i.e. sitting in the meeting backlog rather than reading as a `[ROUTINE]`
  promote candidate; ROADMAP records the same disposition ("2d20 (decision-gated, meeting
  id:719e)"). The sandbox-testability question the box wanted answered first is owned there.
  The box's own question — "should any of these 6 be promoted?" — is now answered NO for all six.

## Relay execute→review — scope-change ratification (2026-07-20)

- [x] **id:be0e — scope substitution RATIFIED by owner 2026-07-20.** The executor fixed the *live* false-positive (the `**[ROUTINE]` markdown-bold wrapper tripping `TAG-NOT-FIRST`, anchored by stripping leading `*`/`_`; RED test `tests/test_roadmap_lint_head_anchor.sh`, merged `relay-ckpt-20260720-1404`) instead of the item's literally-cited "multiple lane brackets" ERROR, which was already fixed (id:1781/ad8a). **Owner ratified the substitution as shipped and did NOT request a separate multi-bracket fixture.** be0e's ledger description updated to match what shipped. (Calibration anchor: chidiai case `2026-07-20-relay-opus-review-agent-returned-ship`, the balanced-brief correction.)

## Relay review — mech-proxy probe + service (2026-07-23, since relay-ckpt-20260723-1301)

- [x] **RESOLVED 2026-07-23 (owner-approved fix): `base_url="${ANTHROPIC_BASE_URL:-}"` — unset now yields `mode-a` (verified `env -u ANTHROPIC_BASE_URL … discriminate` → `mode-a`, exit 0; test still green). id:99a4 — `probe-mech-proxy.sh` ABORTED ("unbound variable", exit 1, empty stdout) when `ANTHROPIC_BASE_URL` is UNSET (not merely empty).** Verified: `env -u ANTHROPIC_BASE_URL bash relay/scripts/probe-mech-proxy.sh discriminate` → `line 56: ANTHROPIC_BASE_URL: unbound variable`, exit 1. This is a direct consequence of `set -u` + the spec-mandated plain `base_url="$ANTHROPIC_BASE_URL"` (line 56). The probe's own documented mode-a contract says *"ANTHROPIC_BASE_URL empty, OR set but not loopback"* → an UNSET var is semantically identical to empty (session wasn't launched through the proxy) and SHOULD yield `mode-a`, but instead it crashes. **The current sole caller `tools/claude-relay.sh` is unaffected** — it always calls the probe with `ANTHROPIC_BASE_URL="$url"` set — so nothing shipped is broken today. But any *other* caller (e.g. the relay-loop Haiku-fallback wiring the item names as its downstream consumer) invoking the probe in an environment where the var is unset gets a crash+empty-output instead of `mode-a`. **Judgment for the owner:** the ROADMAP spec explicitly directed *"plain `"$ANTHROPIC_BASE_URL"` (never `${VAR:-}`, per repo convention)"* — but that convention (CLAUDE.md Gotchas) is about `${VAR:-}` tripping a permission prompt *in a Claude Bash tool call*, which does NOT apply inside an executed `.sh` file. So `base_url="${ANTHROPIC_BASE_URL:-}"` would be safe here and would make unset behave as empty→mode-a, honoring the mode-a contract. Should the probe tolerate an unset var (recommend: yes, `${ANTHROPIC_BASE_URL:-}`), or is the crash-on-unset acceptable because every real launch path sets it? The RED test only covers empty/set cases, never unset. No code change made (the spec pinned the current form). <!-- roadmap:99a4 -->

- [x] **FILED 2026-07-23 as ROADMAP id:4044 (watchdog seam, owner-directed) — the WatchdogSec+sd_notify half is now queued for build; the TCP-connect-liveness-vs-round-trip point (2) is captured in that item's context as a within-spec note. id:69f6 — `mechanical-proxy.service` has `Restart=always` but no `WatchdogSec`, and the probe's "healthy" liveness is a bare TCP-connect (not a functional round-trip).** Two defensible-but-arguable choices, surfaced for the owner: (1) The unit relies on `Restart=always`/`RestartSec=5` to recover from crashes, but a *hung* (accepting-connections-but-wedged) daemon would not be restarted — a `WatchdogSec=` + `sd_notify` heartbeat would catch that. Adding it requires the Python daemon to implement `sd_notify`, which it does not today, so leaving it off is reasonable for a v1. Want a watchdog seam filed? (2) `probe-mech-proxy.sh` classifies `healthy` on a successful `/dev/tcp` connect to the port only — it does not verify the listener is actually the mech-proxy or that a `model:"bash"` round-trip returns. The ROADMAP item itself named "TCP-connect the port, OR a trivial model:bash echo whose stdout must come back" as alternatives and the executor took the simpler TCP-connect, which is *within spec* — flagging only so the owner confirms liveness≠correctness is acceptable for the launcher's health gate. No change made. <!-- roadmap:69f6 -->
- [x] **RESOLVED 2026-07-23 (relay human, verified): already integrated — this box was stale.** `git merge-base --is-ancestor 18df6c0 HEAD` = YES (the id:ce50 work is in `main`), `git for-each-ref refs/heads/relay/orphan/` is empty, and `relay-reconcile.sh .` reports "no parked orphans". Nothing to integrate or discard. **BUT the integration was only half-effective**: `relay/scripts/inbox-scan-repo.sh` shipped to `main` without a `~/.claude/skills/relay/scripts/` symlink, so every caller of the installed path got exit 127 — this run's own human.md §2 inbox scan silently failed. Fixed by `make install`; the recurrence guard is filed as TODO id:ba27. Original box text: auto-reconcile parked orphan `relay/orphan/relay-20260723-110229-15341-execute` (18df6c0) — non-ledger (code) diff in 4 file(s) (e.g. Makefile) — needs strong-turn review; --auto never auto-merges code. Subject: relay: per-repo filtered inbox scan for repo-scoped runs (id:ce50). Surfaced 2026-07-23 14:20 by `relay-reconcile.sh --auto` (id:7809); integrate or discard manually: `relay-reconcile.sh --integrate relay/orphan/relay-20260723-110229-15341-execute` / `--discard relay/orphan/relay-20260723-110229-15341-execute`.

## Relay review — id:8913 + id:5533 audit (2026-07-24, since relay-ckpt-20260723-2034)

- [x] **CONFIRMED + SHIPPED 2026-07-28 (relay human, verified empirically): boundary-anchoring is the right fix, and the as-built goes one step further than the box proposed — it is deliberately NOT a plain `\b`.** A bare `\b` would still fire inside `fail-CLOSED` (a hyphen is a non-word char), so it would NOT have fixed the live false positive this box reported. `relay/scripts/lib-state-claim.sh:48` instead uses `(^|[^A-Za-z0-9_-])(RESOLVED|SUPERSEDED|DONE|CLOSED|DEFERRED)($|[^A-Za-z0-9_-])` — hyphen excluded from the boundary class on both sides — so a hyphen-joined compound never counts as a standalone terminal-word assertion. Verified live via `state_claim_violation`: `fail-CLOSED is the key property` → no violation, `this is disclosed info` → no violation, `undone work` → no violation, `item is CLOSED` → still fires. No allowlist of compound exceptions is needed (that alternative would have required enumerating `disclosed`/`enclosed`/`undone`/… indefinitely; the boundary rule is closed-form). Original box text: **id:78e1 filed — id:5533's state-claim predicate lacks word boundaries → live false positive on this repo's own ROADMAP.** VERIFIED: `state_claim_violation` on the id:6b35 line returns `i` because `STATE_CLAIM_TERMINAL_RE`'s bare `CLOSED` alternative matches inside the visible prose "fail-**CLOSED** is the key property". Same class would fire on `disclosed`/`enclosed`/`undone`. This is a precision regression id:5533 introduced by expanding the DECIDED-LEFT-OPEN word list (the old rule had only `DEFERRED`/`SUPERSEDED`/`decided <date>`, none of which collide with in-repo prose). id:5533's acceptance contract (self-vs-scoped + cross-linter invariant) is genuinely met and its tests pass — this is an UNSPECIFIED edge case, not test-gaming, so id:5533 stays closed. Fix is a two-line regex tightening, filed as **ROADMAP id:78e1** with a RED spec. **CONFIRM**: word-boundary anchoring is the right fix (vs. an allowlist of compound exceptions).
- [x] **RESOLVED 2026-07-29 (relay human, owner call): option (a) — id:659c TICKED + CLOSED, residual re-filed as id:75db.** The item as titled is dead: its 2026-07-14 build authorization was retracted 2026-07-28 on a false premise, so "build the relay consumer" was never pending work, and leaving it open misrepresented a retracted authorization as a live build. The genuinely-live /meeting question (extend the project_manager index to emit checkbox-state + counts, vs. keep `orphan-scan --cross-ledger` and drop the count prose per id:1de1) is now its own `[INPUT — meeting]` item, id:75db. Both ledger twins closed identically via the flock'd `md-merge.py` (single-id-two-views). This also removes the permanent DECIDED-LEFT-OPEN WARN at its source rather than suppressing it. Original box text: **id:659c now trips DECIDED-LEFT-OPEN under id:5533's expanded predicate — it is inline-gated, not heading-gated, so the lint still fires.** The item's visible text says "DECISION **RESOLVED** + BUILD AUTHORIZED 2026-07-14" while it stays open (correctly — its premise turned out false and it is `🚧 GATED (route:decision-gate)` awaiting a /meeting). Under the old word list (no `RESOLVED`) it was silent; id:5533 added `RESOLVED`, so roadmap-lint now WARNs on it. This is a *true* decided-left-open in the letter of the rule, but the item is deliberately parked with an inline gate annotation. **DECIDE**: either (a) tick+close id:659c and re-file the residual /meeting question as a fresh item (the gate note already says the premise is false), or (b) accept the standing WARN as harmless (non-strict, advisory). No change made this pass.
- [x] **RESOLVED 2026-07-28 (relay human, verified): the symlink now exists — `make install` was run 2026-07-24 21:22.** `ls -l ~/.claude/skills/relay/scripts/lib-state-claim.sh` → symlink to `/home/tobias/src/dotclaude-skills/relay/scripts/lib-state-claim.sh`; the installed `roadmap-lint.sh`/`todo-conformance.sh` `source` it successfully (this run's own lint invocation used the installed path and returned real output, not exit 127). The recurrence-guard class stays open as TODO id:ba27/id:5bbb. Original box text: **`relay/scripts/lib-state-claim.sh` (new this window) is not yet symlinked into `~/.claude/skills/relay/scripts/` — run `make install`.** relay-doctor reports 1 declared relay script missing from the install tree; it is `lib-state-claim.sh`. Until `make install` runs, any invocation of the INSTALLED `roadmap-lint.sh`/`todo-conformance.sh` (which now `source` the sibling lib) works from the repo checkout but the installed symlink tree is one file short. Mechanical, host-agnostic; the recurrence-guard class is TODO id:ba27/id:5bbb.

## Relay review — id:61fa handback-followup window (2026-07-28, since relay-ckpt-20260728-1518)

- [x] **RESOLVED 2026-07-29 (relay handoff run `relay-20260729-100152-27550`, verified): `make install-relay` was run and the symlink now exists** — `ls -l ~/.claude/skills/relay/scripts/fable-config.sh` → symlink to `/home/tobias/src/dotclaude-skills/relay/scripts/fable-config.sh` (mtime 2026-07-29 09:57), so the `meeting` SKILL.md step 0f `--fabled` availability check no longer exits 127. **The recurrence-guard class stays OPEN as TODO id:ba27** — and this instance sharpened it: this very box detected the drift on 2026-07-28 and the symlink stayed missing anyway until a live `exit 127` on 2026-07-29, so the gap is not detection but that nothing ACTS on it (the duplicate TODO id:18ed was folded into id:ba27 and deleted in the same pass). Original box text: **Install-tree drift (recurrence of the id:ba27/id:5bbb class): `relay/scripts/fable-config.sh` is committed to the repo (9695c5b, 2026-07-28 13:44) but has NO symlink in `~/.claude/skills/relay/scripts/` — run `make install` (or `make install-relay`).** relay-doctor's install-drift check (id:1102) reports it as the one declared `relay_FILES` entry missing from the install tree. Standing gap, not new this window (the file predates the checkpoint). Every caller of the INSTALLED path gets exit 127 until re-install; editing/committing from the repo checkout works, but the symlink tree is one file short. This is the SAME class the just-resolved `lib-state-claim.sh` box hit on 2026-07-24 — the durable recurrence-guard is already filed as TODO id:ba27/id:5bbb (auto-`make install` after a new relay script lands). Mechanical, host-agnostic; no code change made this pass (install is a `~/.claude` action outside the review worktree).

- [x] **RESOLVED 2026-07-29 (relay review, run `relay-20260729-142725-13077`, verified): fixed by option (b), landed in commit `bd794a0` (2026-07-29 14:20, before ckpt-1437).** `tests/run-tests.sh` now exports `GIT_CONFIG_COUNT=1 / KEY_0=core.hooksPath / VALUE_0=/dev/null`, neutralizing the global hook for every fixture git invocation via env-override (never mutating the developer's real global config). The box's "silently disables the privacy gate too" concern was addressed: `test_privacy_gate_prepush.sh` case (6) re-overrides it for its own case. Verified live in the review worktree: the global `~/.config/git/hooks/pre-commit → pre-commit-lane-vocab.sh` symlink is STILL installed, yet both formerly-failing tests pass and the full suite is GREEN — **324 passed / 0 failed / 9 expected-red**. Original box text: **SUITE IS RED FOR A REASON UNRELATED TO ANY OPEN ITEM: installing the lane-vocab pre-commit ratchet today broke two hermetic tests** (handoff 2026-07-29, run `relay-20260729-133054-23284`). Baseline at the 12:55 review was **323 passed / 0 failed / 4 expected-red**; the global `core.hooksPath` `pre-commit` symlink → `hooks/pre-commit-lane-vocab.sh` was installed at **13:24** (the id:ad7c activation); the suite is now **321 / 2 / 10** (the +6 expected-red are this handoff's new RED specs, which is the intended state). The two failures — `tests/test_backtest_fidelity.sh` and `tests/test_lane_vocab_ratchet_hook.sh` — both `git commit` fixture ledger lines that deliberately carry OLD-vocab tags (`[HARD — pool] Recurring audit item`, `[HARD — meeting] legacy item`) inside their own `mktemp -d` repos. `core.hooksPath` is a **global** git config, so it applies to those throwaway fixture repos too, and the HARD-DENY ratchet refuses the fixture commit. Verified on the MAIN checkout with none of this handoff's changes applied — pre-existing, not caused by the promotions or the new specs. The irony is load-bearing: `test_lane_vocab_ratchet_hook.sh` is the ratchet's OWN test, and it fails because the ratchet is installed. **DECIDE the fix shape** — no change was made here, because it touches shipped tests and this handoff's scope is C2+C3 only: (a) neutralize the inherited hook path inside each hermetic fixture (`git -c core.hooksPath=/dev/null commit …`, or `git config core.hooksPath ""` right after `git init`) — narrow, but every future fixture-committing test must remember it; (b) have `run-tests.sh` neutralize the hooks path for the whole suite — one place, but it silently disables ALL global hooks for tests, including the privacy gate; (c) investigate why the hook's own own-repo-set no-op path does not cover these fixtures (`test_lane_vocab_ratchet_hook.sh` DOES print `repo '/tmp/…' is not in the relay own-repo set — no-op` for one case and still blocks another) — this is the most informative of the three and may show the guard is scoped wrongly. **A red suite hides real failures**, so this is worth the owner's five minutes before the next executor round.

## Relay review — user-injected unit (2026-07-29, run relay-20260729-142725-13077, since relay-ckpt-20260729-1437)

- [x] **roadmap-lint DECIDED-LEFT-OPEN false-positive on id:5f31 — the id:bf19(b) class, no action needed here.** `roadmap-lint.sh` WARNs that open `[INPUT — meeting]` item id:5f31 "carries a decided/deferred/superseded marker but is still open". It does NOT — the item asserts nothing terminal about ITSELF; the trigger is prose *scoped to another id* ("**id:a225 CLOSED**", "UN-GATED", "struck", "stale") describing why 5f31 became un-gated. This is exactly the false-positive class already tracked as **id:bf19(b)** (the scoped-assertion strip in `lib-state-claim.sh:73` requires a literal " is " and misses `id:a225 CLOSED`). This review DROPPED the now-discharged `<!-- gated-on:a225 -->` marker (a225 is `[x]`), which is correct hygiene but does NOT clear the WARN — the prose does. Deliberately NOT mangling the accurate provenance prose to satisfy a known lint FP (drift-toward-the-tool anti-pattern). Resolution belongs to id:bf19, not this line. **No decision needed** — informational; the WARN is advisory (non-strict).
  - **AUTO-ANSWERED (relay human, 2026-07-31, claude-opus-5).** The box asks for no decision, and its disposition claim is verified: `id:bf19` is OPEN and tracked in BOTH ledgers under the same id — `TODO.md:372` and `ROADMAP.md:2122`, both `[ROUTINE]` — so the resolution genuinely has a home and this line is not it. Ticking as informational; the lint WARN stays until bf19 lands, by design. Re-check: `grep -n 'id:bf19' TODO.md ROADMAP.md`.

- [x] **relay-core shadow parity has REGRESSED since the TODO id:82c4 "zero mismatches / flip-gate MET" claim — surface for the owner before any flip.** `relay-doctor` reports the live shadow at **88436 rounds / 253 mismatches** (`~/.claude/logs/relay-core-shadow.jsonl`), and flags "MISMATCHES present — bash stays authoritative; investigate before the flip". TODO id:82c4's body still records "**2895 match** — ZERO mismatches, ZERO INVALID-JSON … far exceeds the N=5 clean-consecutive-rounds bar" as of 2026-07-10 (~3000 rounds). At 88436 rounds there are now 253 mismatches, so the flip-gate (100% parity) is **no longer met** and 82c4's "SHADOW-ROUND half of the flip gate is MET" wording is stale. Not fixed here: the Lean substrate lives in a separate repo (`~/src/relay-core`) and the flip is gated on the island-2 go/no-go meeting (id:ebdb). **Owner: the 253 mismatches need triage before any flip is considered — the shadow is doing exactly its job (bash stays authoritative).** Report-only.
  - **OWNER-DECIDED 2026-07-31 (relay human): correct id:82c4's stale wording AND file the triage.** Re-measured at decision time with `relay-doctor.sh .` — **95663 rounds / 281 mismatches (~0.29%)**, up from the 88436/253 recorded above, so this is an ACCRUING regression, not a frozen historical gap. Two actions taken: (1) id:82c4's "flip-gate MET / ZERO mismatches" body is amended to the current numbers, because as written it reads as settled current state and is not; (2) the mismatch triage is filed as **id:d5bd**. The flip decision itself is untouched and stays with the owner at the island-2 go/no-go (id:ebdb). Re-check: `~/.claude/skills/relay/scripts/relay-doctor.sh . | grep -A2 shadow`.

## Relay handoff C2/C3 — id:1f4f children promoted after the relay-loop.js directive lift (2026-07-30)

- [x] **id:cc90 — the three pre-registered rechain semantics are MY defaults, not the owner's ruling. Ratify or overrule.** Meeting 2026-07-26-1922 amendment A2 (`--fabled` F1) requires (a) review scope under chaining, (b) reject-unwind semantics at depth K, (c) whether a chained member re-enters the disjoint greenlight — to be PRE-REGISTERED before implementing. The promoted ROADMAP item pre-registers all three as the **status-quo-preserving** choice: (a) per-chain deferred review (no mid-chain review), (b) NO unwind of already-integrated units on a depth-3 reject, (c) a chained execute never enters the greenlight (it is dependent by construction; admitting it turns the wave into a DAG). Each is the option that changes nothing beyond the chaining itself, which is why a handoff can defensibly set it — but (b) in particular is a real commitment: it means a bad execute at depth 1 can be pushed to main before the reject at depth 3 is known. **If any answer should differ, that is a `/meeting`, not an executor's call.**
  - **OWNER-RATIFIED 2026-07-31 (relay human): all three stand as pre-registered — (a) per-chain deferred review, (b) NO unwind of already-integrated units on a depth-K reject, (c) a chained execute never re-enters the disjoint greenlight.** This is now the owner's ruling, not a handoff default; amendment A2's pre-registration requirement is DISCHARGED. The (b) exposure is accepted knowingly: a depth-1 execute may reach main before a depth-3 reject is known. The `DO-NOT-START` gate on id:cc90 is LIFTED.

- [x] **id:923b — the unit-key shape is UNDEFINED for id-less units, and I did not resolve it.** The ratified key is **itemId × attempt**, but only `execute` units carry an item id (`actionable_routine_ids[0]`, id:b09e); `review`, `handoff`, `hard` and injected units have none. The ROADMAP item records a PROVISIONAL fallback — `${verdict}-${itemId || 'repo'}-${attempt}` — which preserves today's one-unit-per-repo-per-verdict behaviour for the id-less verdicts, and instructs the executor to HAND BACK rather than invent something else if it proves insufficient. This gap is not mentioned in the meeting note; it may need a design answer before id:ae08's fan-out relies on the key.
  - **OWNER-RATIFIED 2026-07-31 (relay human): the provisional fallback is the real key.** `${verdict}-${itemId || 'repo'}-${attempt}` is no longer provisional — it is the ratified unit-key shape for id-less verdicts (`review`/`handoff`/`hard`/injected). It preserves today's one-unit-per-repo-per-verdict behaviour, and the HAND-BACK-rather-than-invent instruction stays in force as the escape hatch if id:ae08's fan-out proves it insufficient. No `/meeting` needed; ae08 is not blocked on this.

- [x] **Premise correction for the record: id:ae08 and id:a955 were NOT untagged in TODO.md** — both carried a genuine head lane tag `[HARD — pool]` at offset 0. That is OLD venue-keyed vocabulary, which is why the scanners read them as unlaned. This handoff converted both TODO lines to the canonical `[HARD]` per `relay/scripts/lane-convert.sh`'s mapping and promoted them as `[HARD]`. **No lane was guessed.** Flagging it because the handoff brief asserted they were untagged; the disposition would have been the same either way, but the reasoning differs.
  - **AUTO-ANSWERED (relay human, 2026-07-31, claude-opus-5).** Verified on disk: `TODO.md:66` (id:ae08) and `TODO.md:67` (id:a955) both now carry the canonical head lane tag `[HARD]` — no venue suffix, no guessed lane — matching `lane-convert.sh`'s `[HARD — pool]` → `[HARD]` mapping. The correction is accurate and needs no decision. Re-check: `grep -nE '^- \[.\].*id:(ae08|a955)' TODO.md`.

- [x] **id:a955 is promoted but GATED on id:87f5, which is not promoted and not done.** Meeting D4a gates both a955 and 3ca7 on the pre-registered per-phase burn measurement (id:87f5) that ORDERS them. a955 now appears in the execution queue with a `<!-- gated-on:87f5 -->` marker and a leading DO-NOT-START line, so it is visible but not pickable. **Owner: id:87f5 is an `[INPUT — access]`-class item in TODO with no home in the queue — a955 stays parked until you run it or lift the gate.**
  - **OWNER-DECIDED 2026-07-31 (relay human): give id:87f5 a home in the queue; the gate on a955 STANDS.** The gate is not weakened — D4a's pre-registered per-phase burn measurement still orders a955 and 3ca7, and a955 keeps its `<!-- gated-on:87f5 -->` marker and DO-NOT-START line. What changes is that 87f5 stops being stranded in TODO: it is promoted into `ROADMAP.md` as an `[INPUT — access]` item so the blocker is visible and trackable in the execution queue rather than invisible to it. The owner runs it when convenient; a955 unblocks then.

## Relay handoff C2/C3 — execute→review cadence starvation (2026-07-31, branch relay/handoff-cadence-20260731)

- [x] **id:6217 — "exactly ONE definition" may be UNREACHABLE under the Workflow sandbox constraint. Ratify the contract or re-scope it.** The meeting's D4/A3 contract is *"exactly one definition of each remains"* for `isDryRound`/`isBlockedRound`/`workCreated`. But the inline copies exist for a REASON that has not gone away: `relay-loop.js` is Workflow-sandbox JS and **cannot `import`** — `drain.mjs:20-22` says so in as many words (*"relay-loop.js (the Workflow sandbox cannot `import`) carries BYTE-IDENTICAL inline copies of these bodies"*). So "one definition" across `drain.mjs` AND `relay-loop.js` needs a MECHANISM nobody has specified: a generation/inlining build step, a lint that proves byte-equality, or the loop ceasing to need its own copy. The RED spec `tests/test_dryround_single_definition_6217.sh` asserts the contract **as ratified** and instructs the executor to hand back rather than weaken the test — but if the intended reading was only *"one definition INSIDE `relay-loop.js`"* (which is already true today, so the item would be near-empty), that is a scope question only the owner should settle. **Decide: (a) the cross-file single definition stands and someone builds the mechanism; (b) re-scope to a tested byte-equality lint over the two copies; (c) re-scope to loop-internal only and say what the deliverable then is.**
  - **RULED 2026-07-31 (owner, `/relay human`): the cross-file contract STANDS — build the generation mechanism.** Option (a). Both weaker readings were considered and rejected: a byte-equality lint over two hand-maintained copies, and re-scoping to loop-internal-only (already true today, which would empty the item). The deliverable is a generation/inlining step emitting `relay-loop.js`'s copy from the single source, so the duplication is derived, not maintained. Flowed to `ROADMAP.md` id:6217, which also notes the change must update `CLAUDE.md`'s "There is no build step" line or the architecture doc contradicts the code.

- [x] **id:c500 part (1) — a reconcile checkpoint's model attribution is genuinely undecided, and the item says so.** A reconcile-integrate can be run by a human, by an apex session, or by `--auto`. The three candidate answers (caller passes the model id / read it from the environment / a reconcile checkpoint deliberately does NOT count as strong) have materially different consequences for `id:8123`'s watermark-advance reset, which depends on the watermark being trustworthy. Part (2) — making `ckpt-tag.sh` LOUD on a model-less label — is unconditional and specced behaviourally, so the executor can land it regardless. **Owner: if you already know which of the three you want, saying so now saves a `decision-gate` handback round-trip.**
  - **RULED 2026-07-31 (owner, `/relay human`): a reconcile checkpoint deliberately does NOT count as strong.** Caller-passes and read-from-environment both rejected — either would advance `last_strong_ckpt` on a reconcile, making merged orphan work read as audited when nobody audited it. This ratifies today's de-facto behaviour and makes it deliberate; part (1) becomes documentation at `relay-reconcile.sh:278`, not attribution plumbing. Part (2) (LOUD on a model-less label) is unconditional and unchanged — it is what distinguishes "deliberately not strong" from "forgot the model id". Flowed to `ROADMAP.md` id:c500.

- [x] **id:8123 — the RED spec accepts four field spellings for the "chain ended" fact; the classifier's input contract is the owner's to name.** `tests/test_chain_end_reask_8123.sh` probes `chain_ended` / `chainEnded` / `chain_end` / `chain_end_reason` so it constrains BEHAVIOUR rather than vocabulary. That is deliberate — but `classify-verdict.sh`'s input object is a contract surface consumed by `classify-repo.sh`, `discover-sig.sh` (which must hash any new signal, id:c3a6) and `gather-repo-state`, so the field name is not purely an implementation detail. **If you want a specific name, say it and the spec will be narrowed.** Related: whichever name is chosen MUST be added to `discover-sig.sh`'s hashed blob, or a chain-end verdict can be served stale from the signature cache — the same trap `id:907e` clause (i) exists to close.
  - **RULED 2026-07-31 (owner, `/relay human`): the spec stays PERMISSIVE** — the implementer picks from the four spellings; behaviour is what is constrained. **With a hard requirement attached**: whichever name is chosen MUST be added to `discover-sig.sh`'s hashed blob, or a chain-end verdict serves stale from the `id:c3a6` signature cache and the forced review silently never fires — the same trap `id:907e` clause (i) closes on the other side. Flowed to `ROADMAP.md` id:8123 with an acceptance criterion.

- [x] **id:da87 was NOT promoted — confirm that is right.** `unpromoted-scan.sh` labels it `promote`, but its fix is merged (`78a4463`) and its stated premise was refuted (`85ca751` — the collector never under-reported; the caller's `| head -80` truncated the last 9 rows). The only residue is a line the TODO itself marks *"Not done, deferred to the owner: emitting `review_me` **first** per repo… a mitigation with a row-order behaviour change, so it was surfaced rather than taken."* That is an owner decision, not executor work, so promoting it as `[ROUTINE]` would hand an executor a call the owner reserved. **Owner: either rule on the row-order change (and it gets promoted), or the TODO line should be closed with the residue re-filed as `[INPUT — decision]` so the scanner stops labelling it `promote`.**

  - **RULED 2026-07-31 (owner, `/relay human`): emit `review_me` FIRST per repo — the skip is confirmed and the residue is now ordinary executor work.** The row-order change is approved, so it gets promoted rather than re-filed as `[INPUT — decision]`. Supporting evidence accumulated the same day: output was truncated TWICE in one session — the collector via `| head -80` (the original `id:da87` false alarm) and then the test suite via `| tail -3` — so making the highest-value tier survive an accidental truncation is demonstrated need, not hypothesis.
---

## Review 2026-07-31 (relay review, window `relay-ckpt-20260730-2018..HEAD`, 46 commits)

- [x] **`id:ad7c` was closed on an owner ratification that leaves NO greppable trace — stamp it or reopen.** — **RESOLVED 2026-08-01 (relay human, tier-b owner decision): the ratification is GENUINE; the marker is now stamped.** The owner confirmed directly that the fleet-wide `core.hooksPath` pre-commit HARD-DENY is intended, and `@owner-accepted:2026-07-31` was appended to the `id:ad7c` line in `TODO.archive.md` (re-checkable: `grep '@owner-accepted:2026-07-31' TODO.archive.md`). The tick stands; nothing reopened. The recorded consequence is UNCHANGED and still open — `routed:d349` / `id:8b77` (the `id:3801` auto-gate still emits old venue-keyed vocab, so the ratified hook blocks the pool from committing its own output). The item's own text set its release condition as *"confirm the fleet-wide HARD-DENY is intended, then tick"*, and `RELAY_LOG.md:3947` recorded *"the work is DONE; what remains is an owner tick, not executor work."* Commit `7bdfa45` ticked it, asserting *"The owner confirmed on 2026-07-31"* — but there is **no `@owner-accepted:2026-07-31` marker anywhere in the window** (`git log -p relay-ckpt-20260730-2018..HEAD | grep @owner-accepted` → empty), so the ratification of a **global `core.hooksPath` pre-commit that BLOCKS commits fleet-wide** rests entirely on the prose of a commit written by the same session that closed the item. This is the exact shape review.md §5c fail-closes on. Mitigating evidence that it IS genuine: the same commit records *"Not ticked, deliberately: 2da8, 75b3 (owner declined the 4th tranche)"* — a fabricating session does not invent a declined tranche. **NOT reopened by this review** (§5c's gate is scoped to the version-bump set, and this repo has no version), but the owner should either add `@owner-accepted:2026-07-31` to the `id:ad7c` line or say the tick was premature. **Consequence already recorded on the line and worth acting on:** ratifying hard-deny makes `routed:d349` / `id:8b77` urgent — the pool's own `id:3801` auto-gate still emits old venue-keyed vocab, so the ratified hook now blocks the pool from committing its own output.

- [x] **Six shared-inbox dead-letters are addressed to this repo and were never ingested** — **AUTO-ANSWERED 2026-08-01 (relay human, tier-a): the claim is no longer true — all six ARE ingested and the inbox is drained of them.** Re-checkable evidence: `grep -l 'routed:<tok>' TODO.md` returns `TODO.md` for every one of `caf8 aa3e b333 c2ba 5996 46ec`; `grep -E 'routed:(caf8|aa3e|b333|c2ba|5996|46ec)' ~/.claude/projects/todo-inbox.md` returns EMPTY; and a fresh `scan-routed.sh` now reports 2 findings, both targeting `loderite` (`routed:813f`, `routed:6ebf`) and zero targeting this repo. The routing this box asked for happened between the review and this triage. **Ingestion is not the fix, though** — `routed:caf8` (`id:e44e`) was ingested UNLANED and unpromoted, so no pool could pick it up; it has now been promoted to `ROADMAP.md` as `[ROUTINE]` on owner decision (see the `id:e44e` line). The other five stay as ingested TODO backlog for the next handoff C2 to lane. (`relay-doctor` → `scan-routed`, 8 dead-letters total, 6 targeting `dotclaude-skills`). The window contains 8 `chore(inbox): ingest routed:…` commits, so these arrived after that pass and are a genuine un-routed backlog, not a skipped set. Surfaced only, per `id:678e`'s report-only gate — routing them is the owner's/next handoff's call. **`routed:caf8` is operationally urgent and fleet-wide:** the `id:b8fa` CHANGELOG rollout leaves a `.changelog.lock` that is NOT in the gitignore stanza the bootstrap writes, so `classify-repo.sh` reports `verdict:blocked / "Dirty main working tree"` and the pool stops with `stopReason: blocked-pending-human` while actionable `[ROUTINE]` work remains (observed live on mathematical-writing 2026-07-31, 3 items stranded). Every b8fa-rolled repo is exposed. The other five: `routed:aa3e` (reconcile false-clean on unparked orphan branches), `routed:b333` (`RELAY_STATUS.md`'s "REVIEW_ME open items" is scoped to boxes opened *this run* but labelled as the repo backlog — false-clean at exactly the moment a human reads it), `routed:c2ba` (`orphan-scan --cross-ledger` reports author-then-run splits as drift, and the obvious fix buries the residue), `routed:5996` (relay worktrees break `lake exe cache get` for Lean repos), `routed:46ec` (Fable escalation trigger fired again — owner said FILE, do not build).

## Handoff 2026-08-01 (C2/C3, owner-scoped 5-item promotion)

- [x] **`id:f91a` was promoted as an `@container` epic, NOT as a dispatchable `[ROUTINE]` unit — and its 2026-07-30 "NOTHING IS QUEUED" hold was AMENDED for `id:34b7`. Both are my calls, not yours; confirm or correct.** The handoff scope named `id:f91a` as `[ROUTINE]`, but the item's own text carries **no fix of its own** — only the problem statement plus two candidate directions (`id:34b7`, queued; `id:d464`, owner-barred). Promoting it as a dispatchable unit alongside its own child would double-count against that child, which is the exact anti-pattern `handoff.md`'s id:8504 rule names. So it is `@container` (non-dispatchable via `classify-repo.sh`'s `is_human`, id:0cf5) and carries no RED test; `tests/test_parent_creates_worktree_34b7.sh` is the spec for the queued half. **Separately**: `TODO.md` id:f91a still carried the owner directive *"Both children are filed for discussion only … do not promote either to ROADMAP"* (2026-07-30). I read the owner-scoped 2026-08-01 handoff as superseding that hold **for `id:34b7` only** and amended the TODO line in place saying so; **`id:d464`'s "DISCUSSION ONLY / DO NOT BUILD" stands unamended and is absent from ROADMAP.** If the 34b7 promotion was not intended, untick/remove the two ROADMAP entries and revert the TODO amendment — nothing else depends on them. **Also worth your call, deliberately NOT minted as new work:** the item's "Amplification" residue — a main-checkout leak surfaces as an *unattributed* "main checkout dirty" in a later, innocent run — is owned by NEITHER child. It is currently unassigned.

- [x] **`id:ecce` part 4 — "make `/relay review` LOUDLY refuse when its audit window is EMPTY" — is specced in ROADMAP but NOT covered by the RED test. Confirm the shape, or accept the gap.** `tests/test_integrate_label_not_strong_ecce.sh` covers parts 1-3 behaviourally (label semantics in `ckpt-tag.sh`, the second consumer in `gather-repo-state.sh`, the `SKILL.md` prescription) but asserts nothing about part 4, because **"refuse" has two defensible meanings and picking one silently would be the handoff making your call**: (a) a non-zero exit that aborts the review unit, or (b) a loud surfaced no-op that still returns cleanly. They differ materially under `--afk`: (a) turns a vacuous review into a handback the pool records and stops re-dispatching; (b) keeps the round moving but relies on a human reading `RELAY_STATUS.md`. The ROADMAP item instructs the executor to STATE which it chose and why in the commit message, so the choice is at least recorded — but it is unspecced, so nothing tests it. **Say which you want and the spec gets a case; or accept that part 4 lands on the executor's judgement.**

## Review 2026-08-10 (relay review, window `relay-ckpt-20260801-2135..HEAD`, 12 commits)

- [x] **Four open ROADMAP items sit behind gates that can never open — `roadmap-lint` DEAD-GATE (id:49e0), 4 hits.** Two are gated on a **RETIRED** id: `id:2b49` (visible-half-is-primary handoff discipline) is `gated-on:ac7f`, and `id:1f8e` (add `worktree-retire.sh` to `ALLOWED_RELAY_SCRIPTS` — itself flagged HIGH PRIORITY and "ticked but INERT at runtime") is `gated-on:5bbb`; both gate ids are archived `[x]` in `TODO.archive.md` and are not ROADMAP items, so nothing can ever clear them. Two more — `id:540f` and `id:c179`, the `mech-preflight`/`relay-loop` refusal pair — are `gated-on:e62c,b0b1` where **`b0b1` lives only in `TODO.md` and was never promoted**, so no ROADMAP transition can clear that half either. **The `540f`/`c179` case is NOT a mistake to auto-fix**: both carry an explicit *owner gate* ("does NOT land until the owner explicitly says so", 2026-07-31) because the refusal makes the pool unrunnable in any `/remote-control` session — the dead `b0b1` marker is arguably the correct encoding of "waiting on the owner", and re-targeting it would quietly convert an owner hold into a technical one. **Decide per pair:** (a) `2b49`/`1f8e` — drop or re-target the retired marker (mechanical, low risk; `1f8e` unblocking matters because the ticked-but-inert `4df8` is a live runtime gap); (b) `540f`/`c179` — either promote `b0b1` so the gate is real, or replace the marker with an explicit owner-hold annotation that lint understands. Owner's call on (b). — **CORRECTION 2026-08-10, same day: half (a) of this box was WRONG and must NOT be actioned as written.** It accepted `roadmap-lint`'s DEAD-GATE diagnosis at face value. Verified since: `resolve-gates.sh:36` resolves gate tokens over `ROADMAP.md ∪ TODO.md ∪ TODO.archive.md`, so an archived **ticked** gate id is SATISFIED, not unreachable — `ac7f` is `- [x]` at `TODO.archive.md:428`, meaning `id:2b49`'s gate is **already open** and it is a ready-to-run `[HARD — meeting]`, not a blocked item. Dropping its marker as this box recommended would have deleted a correct, satisfied dependency edge. `id:1f8e` is moot here — a parallel session established it had been done since `d8bfbba` (2026-07-31) and ticked it in both ledgers after re-running its done-check. The lint defect itself is now filed as **`id:8de9`** (make `roadmap-lint` share `resolve-gates.sh`'s resolution span and distinguish satisfied / open / unresolvable instead of conflating them). Half (b) — `540f`/`c179` on the never-promoted `b0b1` — is a genuinely different case and **still stands** as written; it is not covered by `id:8de9` and still needs the owner's call.

- [x] **Two parked orphan branches in this repo have outlived their runs and nobody has disposed of them.** `relay/orphan/relay-20260731-174550-21952-review` (`27c7fd7`, a completed roadmap re-derivation carrying verified-green notes for `id:5bbb`/`id:8c6f` plus cross-ledger reconcile work) and `relay/orphan/relay-20260801-213927-29875-execute` (`6c20004`, explicitly a **WIP UNVERIFIED residue auto-commit** from the `id:f272` commit-and-park path, labelled "do not treat as reviewed"). These are opposite dispositions and must not be batched: the review branch looks integrable and its content may already be duplicated by later ledger work, while the execute branch is unreviewed residue from the very run that died on `Prompt is too long` (`id:93cc`) and is a `--discard` candidate at best. Dispose via `/relay reconcile` per branch — `--integrate` re-runs the full serialized-integrator recipe, and `--discard` needs `RELAY_DISCARD_CONFIRM=1`. Not done in this review: integrating a stale review branch over 9 days of newer ledger edits is a merge-judgment call, and discarding unreviewed work is the owner's.

- [x] **`relay-core` shadow has 350 mismatches over 106,536 rounds and the flip gate (100% parity + N=5 clean rounds) is not met — confirm this is still an active track and not abandoned scaffolding.** Reported by `relay-doctor` (id:82c4); bash remains authoritative so nothing is broken today. Surfacing it because a long-running shadow with a stable nonzero mismatch rate is either (a) real evidence the port has a defect worth investigating before more is built on it, or (b) an instrument nobody reads any more, in which case the honest move is to retire it rather than let `relay-doctor` report a gate that will never be evaluated. Not a blocker for this review.

## Pool run 2026-08-10 (`relay-20260810-103858-20326`, 1 round, `blocked-pending-human`)

- [x] **`id:ef9e`'s implementation exists, complete-looking and UNVERIFIED, on a parked orphan branch — decide integrate vs discard.** — **RESOLVED 2026-08-10: recovered, COMPLETED, reviewed, integrated.** The orphan was merged, the missing `relay_FILES` manifest entry added, and — the part that mattered — a **coverage hole in its central guarantee** was found and fixed: the recovered linter classified the *motivating incident's own shape* (`# lib-state-claim.sh's …` inside `python3 -c '…'`, re-balanced by a later apostrophe so the file stays `bash -n` clean) as `UNCHECKED` → exit 0 → "clean". The adversarial review re-derived that independently rather than trusting the executor: it ran the pre-fix linter against both a hand-built fixture and a copy of the LIVE `discover-repo.sh` with the original apostrophe re-injected — both printed clean before, both are REJECTED after with the incident's own `IndentationError` signature. No false positives (live tree: 78 checked clean, the same 5 `UNCHECKED` bodies as before). **Note the lesson**, since it nearly cost the catch: my earlier verification passed this work at 9/9 by running *its own test* — the test shared the code's blind spot because the same child wrote both, which is exactly what `review.md` §2d exists to catch. Remaining, filed separately: the linter has no caller outside its own test (test 5 does run it against the live tree every `make test`, so it is not dead — but no hook or integrate step invokes it; wiring it is an owner call). The `execute` child for this repo was dispatched on `id:1f8e` but worked `id:ef9e` instead — **not a malfunction**: a parallel session established (2026-08-10) that `1f8e` had silently been done since `d8bfbba`, and `executeNamedInstruction` (`relay-loop.js:1950`) explicitly authorises taking the next classifier-actionable candidate when the named item "turns out to be already done". The child followed the contract. What is missing is any record of the substitution — `relay-events.jsonl` still says `1f8e` while the orphan branch contains `ef9e` work, which is why this looked inexplicable; filed by that session as `id:eb63`. So for `id:ef9e` (lint the quoting hazard in embedded foreign-language literals) the child wrote `relay/scripts/lint-embedded-literals.mjs` (414 lines) + `tests/test_embedded_literal_lint_ef9e.sh` (152 lines), then died on `Prompt is too long` before reporting. `worktree-retire.sh` parked the work as `relay/orphan/relay-20260810-103858-20326-execute` (`bdc04a3`, 1 commit ahead of main; the worktree directory is gone, the ref is reachable). Its own commit message says **"WIP UNVERIFIED residue … do not treat as reviewed"** — the suite was never run against it, the item is still `- [ ]` in both ledgers, and nothing checked whether the linter actually catches the apostrophe-in-`python3 -c '…'` case it targets. **This is NOT the same disposition as the other two parked orphans** already listed above: those are a stale review branch and a genuinely empty residue commit; this one is a full, plausible implementation of an open `[ROUTINE]` item, so discarding it throws away real work while integrating it un-reviewed merges 566 unverified lines. **Recommended**: verify before deciding — run the parked test against the parked branch in a scratch worktree; if green, `/relay reconcile --integrate relay/orphan/relay-20260810-103858-20326-execute` (which re-runs the full serialized-integrator recipe); if red or thin, leave it and let a fresh execute unit redo the item. Not done here: integrating unreviewed work is the owner's call, and an `--afk` run takes the surface-don't-act default. — **VERIFIED 2026-08-10 (scratch worktree off the parked ref, then removed): the work is real but INCOMPLETE — do not integrate as-is.** Its own targeted test is **9/9 ALL PASS** and the assertions are substantive, not decorative: apostrophe-truncated embedded python → nonzero naming file:line and language; valid python → zero; corrupted embedded awk → nonzero; a glued `-F` flag value does not desync recognition of the real awk program; and an un-isolable interpolated body is reported `UNCHECKED` rather than silently skipped. It also lints the live `relay/scripts` tree clean. **But the full suite is `354 passed, 1 failed, 10 expected-red` — `test_relay_install_manifest.sh` FAILS**, because the branch adds `relay/scripts/lint-embedded-literals.mjs` without adding it to the Makefile's `relay_FILES` manifest (the same install-drift class as `prompt-size-gate.mjs` earlier this day). That is a one-line completion, not a design problem. **Recommendation**: add the manifest entry, re-run the suite, and if green integrate via `/relay reconcile --integrate`; the alternative — discarding and re-dispatching `id:ef9e` — would pay for 566 lines twice to avoid a one-line fix. Still the owner's call to authorise.

## Review 2026-08-10b (fix chain, window `relay-ckpt-20260810-1152..HEAD` — id:798b, id:ef9e, id:8c85)

All three units verified genuinely green under an adversarial pass: each item's RED spec was authored at handoff and is untouched (798b, 8c85) or additive-only (ef9e, +49/-0), and running each **unmodified** spec against its **pre-fix** implementation reproduces the original defect — 9 BAD for 798b's lock, 8 BAD for 8c85's four vanished classes, and for ef9e the literal `linter reported CLEAN on the motivating incident's own shape`. Zero gaming flags. All three over-reach candidates judged **justified** against the ratified ROADMAP text, not its restatement. Follow-ups filed as `id:d525`, `id:340f`, `id:b3a3`, `id:5b21`. One open judgement box remains:

- [x] **The `lint-embedded-literals.mjs` linter (`id:ef9e`) has no caller outside its own test — decide whether to wire it, and where.** `tests/test_embedded_literal_lint_ef9e.sh` case (5) runs it against the live `relay/scripts` tree on every `make test`, so it is genuinely exercised and is **not** the `[[relay-builtgreen-but-unreferenced]]` class. But nothing in `relay-loop.js`, no git hook, and no integrate step invokes it — so it catches a quoting corruption only when someone runs the suite, not when someone *writes* one. The bug it exists for (an apostrophe silently truncating an embedded `python3 -c '…'` body while `bash -n` still passes) is introduced at authoring time and can ship green if the author does not run `make test`. **Candidates**: the shared git-hook framework (`id:7a05`/`id:077d`) as a pre-commit plugin — the reconcile-before-greenfield home, but that framework is not ready; a relay integrate step alongside the other lints; or leave it suite-only and accept the window. Not decided here — it is a real coverage question, not a defect, and the hook-framework dependency makes it an owner call rather than an executor one.

## Review 2026-08-10c (tracker pilot, window `relay-ckpt-20260810-2019`..HEAD — id:2bb1, id:8066)

Both units verified adversarially: every new test was mutation-probed and each one goes RED when its target is broken (fixture drift removed → drift spec red; `control-board.sh` given a deliberate `git tag` write and a deliberate untracked-file write → purity assertion red naming the drift; `control-board.sh` removed from `relay_FILES` → the pre-existing `test_relay_install_manifest.sh` red). `gaming-scan.sh` clean, no test weakened or deleted, `refactor:` self-reports present for both units, no executor-introduced `@owner-accepted`. Three OWNER calls the children correctly declined to settle:

- [x] **`--allow-homonyms` has NO basis in the ratified meeting note — ratify the knob, or remove it.** The note (`docs/meeting-notes/2026-08-10-0906-tracker-substrate-replacing-markdown-ledgers.md` D2, as amended by finding 6) says only: *"composite key `(repo, id)`; cross-repo 4-hex collisions **fail loudly at import**"*, and its action-item contract says *"a synthetic cross-repo id collision exits non-zero"*. There is no clause anywhere in the note about strict-vs-lenient modes, an escape hatch, or a class-A/class-B split — every defaults-flavoured sentence in it points one way ("fail loudly", "never a silent skip", "exits non-zero"). `id:2bb1` shipped an opt-in `--allow-homonyms` that downgrades class-A homonyms to warnings; `tracker/SCHEMA.md` openly concedes the gap. **Nothing is broken today** — the default is strict, class B (an ambiguous cross-repo `routed:` edge) is never downgradable, and `tests/test_tracker_id_collision_loud.sh:57-67` proves both halves. The question is whether a ratified fail-loud should be flag-downgradable at all. **My assessment on the substantive question the child raised (default-strict at ~60 repos over a 4-hex space):** default-strict is right *and* the knob will be needed. 4 hex = 65536; with ~4000 live ids across the fleet the birthday probability of at least one cross-repo homonym is effectively 1 — so a strict fleet import (id:94ce) will refuse on day one, for a collision the composite key already disambiguates correctly. Strict-by-default is still correct because it forces the collision to be *seen*; the knob is what makes the fleet importer runnable afterwards. What is missing is a policy for WHERE the flag lives — if id:94ce's timer just passes `--allow-homonyms` unconditionally, the loud failure is dead on arrival and we are back to a silent laundering. **Recommendation (owner decides):** keep the knob, but require id:94ce to pass it with an explicit allow-LIST of already-adjudicated tokens rather than a blanket flag, so a NEW homonym still fails loudly. **DECIDED 2026-08-10 (owner): replace the boolean with an explicit ALLOW-LIST.** The knob stays (default-strict is preserved), but it takes adjudicated tokens rather than a blanket downgrade — a token on the list passes, a NEW homonym still fails loudly, and `id:94ce`'s timer therefore cannot switch class A off wholesale. This keeps the ratified "fail loudly at import" operative for everything not yet seen by a human, which was the whole objection. Build filed as `id:ca24`. Class B stays always-fatal, unchanged.

- [x] **`tracker/` as a new top-level directory — confirm or relocate.** The child flagged it. It does not collide with the repo's "no `SOP/`/`adr/` directory" convention (id:a6e1) — that rule bars parallel *decision-record* trees, and `tracker/` is code + schema + fixtures, not decision records. It is documented in `CLAUDE.md`'s Layout table in the same commit (`ee9c64e`), which is the repo's actual convention for a new directory, and both lint guards (`tools/check-no-bare-rm-f.sh`, `tools/check-no-silent-swallow.sh`) were extended to scan it. The alternative homes are worse: under `relay/` it would imply relay ownership of a substrate the meeting explicitly kept at arm's length (D4: "zero relay scripts write to the tracker"), and under `tools/` it would bury a multi-file contract surface in a flat script drawer. **Recommendation: keep it.** Owner's call because a new top-level directory is a durable repo-shape commitment. **CONFIRMED 2026-08-10 (owner): `tracker/` STAYS top-level.**

- [x] **`derived_status` is a stored single status shipped under a "never a collapsed single status" clause — confirm the field, given the producer-side enforcement now added.** The meeting's D2 amendment names only the per-view pair and the `drift` flag; it neither authorizes nor forbids an extra derived convenience field. `id:2bb1` shipped one, and made it REQUIRED in the JSON schema alongside the three authoritative fields. As integrated, `validate` checked only enum membership plus the single drift⇒not-done case, so a hand-edited or adapter-round-tripped document could carry a `derived_status` that flatly contradicted its per-view fields and still validate OK (reproduced: mutating a `roadmap_status: open` item's `derived_status` from `queued` to `backlog` validated clean, exit 0). **Fixed in this review** — `validate` now RE-DERIVES the field and fails loudly with the offending uid and both values, per this repo's enforce-don't-document rule; spec is `tests/test_tracker_ledger_map_robustness.sh`. The residual is the CONSUMER side, filed as `id:857d`. Surfacing the field itself because it is an addition the ratified source does not contain (review.md §2d), not because it is wrong — it is defensible and the values (`backlog`/`queued`/`needs-decision`) are lifted verbatim from the note's own mapping table. **DECIDED 2026-08-10 (owner): KEEP the field, and make `id:857d` BINDING on `id:90f2`.** The producer-side enforcement added in this review stands; the consumer side is now a gate, not a suggestion — `id:90f2`'s acceptance must require each adapter to carry the per-view pair (or a visible drift marker) into the target, so `derived_status` cannot become the only status a board shows. Rationale: adapters need ONE column or Plane and Vikunja would each invent their own collapse and disagree about the same item, which would wreck the pilot's comparison — the risk was never the field, it was laundering one layer down.

## Review 2026-08-11 (chain-end re-ask, window `relay-ckpt-20260811-1719`..HEAD — id:069b)

id:069b (personas.md dedup + `personas-conformance.sh` + `append.sh -t personas` extend-path) verified GENUINELY GREEN and non-gamed: `gaming-scan.sh` clean; the sole test edit (`test_personas_no_duplicate_names_069b.sh`) touched only the input-seeding line (a `printf` leading-dash shell bug — `printf '- 🔧…'` parsed as an option flag), not the assertion (§2b.1 negative-control exemption); the original test's assertions 1-5 all PASS against the new implementation; real registry `grep -oE '\*\*[A-Za-z]+\*\*' | sort | uniq -d` is EMPTY; conformance exit 0; `append.sh` extend-path is general (no fixture special-casing); no executor-introduced `@owner-accepted`; `refactor: none needed` self-report matches an additive diff. Cross-ledger drift reconciled: id:069b was `[x]` in ROADMAP.archive but left `[ ]` in TODO.md — ticked (single-id-two-views D2; orphan-scan `--cross-ledger` misses it because the item is archived out of ROADMAP.md, same as the id:d808 case). Resolved the DECOMPOSED-CONTAINER lint on id:c7dc (this session's earlier handback-followup split it into seams 258d/37f2/e87d but left the parent open without the marker) by adding `@container`.

- [x] **Two wave-model items are `orphan-scan --shipped` TICK-READY but NOT ticked here — verify wiring before ticking.** `id:cc90` (green `tests/test_rechain_depth_cc90.sh`, gate LIFTED 2026-07-31) and `id:923b` (green `tests/test_unit_identity_key_923b.sh`) both report TICK-READY with no gate. NOT ticked in this pass: they are outside this review's id:069b window, and this id-family (id:5367/2062, `[[relay-builtgreen-but-unreferenced]]`) is the exact class where a green test does not prove the code is REFERENCED from `relay-loop.js` — `id:ae08` is the wiring child. Before ticking, `grep -c` the relevant call sites in `relay-loop.js` to confirm the behaviour is actually reachable, not just unit-green.
- [x] **`tests/test_git_lock_push_slash_branch.sh` flakes under the full parallel suite — known class, non-blocking.** Full `make test` this pass: `378 passed, 1 failed, 5 expected-red`, the one failure being this test; run in isolation it PASSES. Its own header documents the flakiness (SSH-agent state / parallel suite run, id:05e8 lineage — same class as `test_resource_claim_pid.sh`/id:ab5c). Unrelated to id:069b (which touched only `meeting/`). Re-run before trusting a red full-suite result; a durable de-flake (hermetic ssh-agent isolation) would be its own item.

## Review 2026-08-11b (chain-end re-ask, window `relay-ckpt-20260811-1809`..HEAD — id:6217 gate verification)

Window is a SINGLE commit (`dc1fb21`, the id:3801 durable handback-followup that gated id:6217 to `[INPUT — decision]`); zero code/test delta, `gaming-scan.sh` clean. **The decision-gate is WARRANTED — verified against the RED spec directly.** Surfacing the box below because the gate's inline `gate_reason` names only ONE of the item's TWO independent, confirmed blockers, and the `/meeting` that eventually addresses id:6217 needs both. Also cleaned up two malformed placeholder deps this same window: id:37f2/id:e87d carried literal `(after id:(seam 1's id))`/`(after id:(seam 2's id))` — the id:3801 auto-split never substituted the seam ids; corrected in ROADMAP to `(after id:258d — seam 1, DONE)` / `(after id:37f2 — seam 2)` from the unambiguous RELAY_LOG mapping (258d/37f2/e87d = seams 1/2/3), and the substitution defect filed as `id:0eb0`.

- [x] **`id:6217` decision-gate has TWO independent spec blockers, not one — the eventual `/meeting` must reconcile BOTH, and the ROADMAP `gate_reason` records only the second.** Verified in this review against `tests/test_dryround_single_definition_6217.sh` and the live `relay/scripts/relay-loop.js`:
  - **(A) Assertion 4 is an UNSCOPED-grep bug that contradicts the spec's own assertion 5** (this is the executor's committed BLOCKED finding, 2026-08-11 17:46, RELAY_LOG — NOT captured in the gate line). Assertion 4 does `grep -q 'keep byte-equivalent' "$JS"` over the WHOLE of `relay-loop.js` and requires it absent. That literal substring appears in FIVE comments — 998 (id:1432), 1065 (id:1735), 1087 (id:dc5b), **1185 (id:4ca8 — THIS item's actual target: drain.mjs's isBlockedRound/isDryRound inline copy)**, 2090 (id:4f9b) — four of which are unrelated predicates. So assertion 4 can never pass unless all five are rewritten, which is exactly the blanket sweep assertion 5 exists to catch (`this item's scope is isDryRound/isBlockedRound/workCreated only`). Confirmed pre-existing (3 of the 4 collisions predate the spec's 2026-07-31 authoring per `git blame`). Fix is to LINE-SCOPE assertion 4 to id:4ca8's line 1185 (as assertion 5 already line-ranges drain.mjs), OR an owner call on whether the other four inline-copy comments are in scope.
  - **(B) Assertions 1-2 (`exactly one` `function isDryRound(r)`/`isBlockedRound(r)` across BOTH files) are structurally unreachable under the owner-ratified mechanism** (this IS the recorded gate_reason). The 2026-07-31 owner ratification says: build a GENERATION step that EMITS relay-loop.js's copy from drain.mjs's single source. But a generated/emitted copy still leaves a literal `function isDryRound(r)` in relay-loop.js → `defs_of` counts 2 → assertion fails. The only ways to reach count==1 are `import` (impossible — Workflow sandbox) or an unverified `eval`/`Function`-constructor escape-hatch. So either the assertion must be relaxed to verify the generation mechanism (source→emitted-copy byte-equality + an id-marker) rather than a literal single-declaration count, OR the owner must confirm a sandbox posture that permits the escape-hatch.
  - **Both are owner/design calls, not build work** — decision-gate is the right route. The `/meeting` should resolve (A) and (B) together: relaxing assertion 1-2 to a generation-verification shape (B) would also naturally re-scope assertion 4 (A) to the emitted block. Do NOT let a partial fix of one blocker re-dispatch the item while the other still blocks it.
  - **RESOLVED 2026-08-14 (`/relay human .`, tier-a auto-answer) — the gate_reason now records BOTH.**
    This box's ask was a *bookkeeping* one: get blocker (A) into the ROADMAP gate line so the eventual
    `/meeting` cannot address only (B). That landed. `ROADMAP.md:1475` now opens its `gate_reason` with
    "**TWO independent blockers — the /meeting must reconcile BOTH (gate_reason previously recorded only
    (B); corrected 2026-08-13 by `/relay human`)**" and carries both (A) — the unscoped `grep -q 'keep
    byte-equivalent'` hitting five comments (998/1065/1087/1185/2090) with the line-scope-to-1185 remedy
    — and (B) — the structurally-unreachable one-declaration count under the no-import sandbox — plus the
    "do NOT let a partial fix re-dispatch the item" clause verbatim. **The DESIGN question is untouched
    and still open**: `id:6217` remains `[ ] [INPUT — decision]` 🚧 GATED awaiting its `/meeting`; only
    the record-keeping defect this box tracked is closed. Re-checkable: `grep -n 'id:6217' ROADMAP.md`
    — if the gate line ever loses either blocker, reopen this box.

## Review 2026-08-11c (chain-end re-ask, window `relay-ckpt-20260811-1838`..HEAD — two executor units, id:8123)

Chain of TWO execute units verified GENUINELY GREEN and non-gamed (window base is the last reviewer checkpoint `ecd3f48`/1838; the chain's own executor checkpoints 1923/1934 are the units under review):

- **id:34b7** (DISSOLUTION half of id:f91a — the PARENT creates + provisions the child's worktree before dispatch): `relay-loop.js` gains a `provisionWorktree()` mechanical hop (MECH_MODEL/`relay-mech` fence) dispatched from `runUnit()` BEFORE the child `agent()` call, reusing `worktreePathFor()`/`branchFor()`; a provisioning failure hands back instead of dispatching a child into nothing. New `relay/scripts/provision-worktree.sh` (single-target `git worktree add` + best-effort `node_modules`/`.venv` symlinks). Both prompt sites (`unitPrompt`/`resumePrompt`) drop `main checkout: ${unit.path}` and the "Create your worktree first" instruction (part 3, correctly gated behind parts 1+2). Script registered in `mechanical-proxy.py` `ALLOWED_RELAY_SCRIPTS` (id:5bbb completeness) and the Makefile `relay_FILES`/`relay_EXEC`/`relay_ALLOW` manifest. RED spec `tests/test_parent_creates_worktree_34b7.sh` 8/8 green; honest source-shape coverage caveat stated in-file (relay-loop.js has no hermetic runner).
- **id:37f2** (seam 1 of id:c7dc — `discover-repo.sh` carries `verdict`/`priority_rank` on the no-unit paths): blocked/AMBIGUOUS surfaced + idle skipped entries now carry `{verdict, priority_rank, reason}`; the substitutive repo-level-block path emits an honest `verdict:""` (reconcile never classifies) rather than omitting the field. Test additions to `tests/test_discover_repo.sh` are purely ADDITIVE new assertions (cases 2/3/4 field checks + a source-shape check for the dormant AMBIGUOUS branch), no existing assertion weakened.

Verification: `gaming-scan.sh` clean (no deleted test / added skip / removed assert); no test weakened or rewritten (§2b.1 — the id:37f2 test diff strengthens, the id:34b7 test is new); `refactor: none needed` self-reports present for BOTH units and consistent with additive/new-code diffs; no executor-introduced `@owner-accepted` in the window; §2d over-reach — both diffs match their cited sources (id:34b7 stays DISSOLUTION-only, does not touch the owner-barred enforcement child id:d464; id:37f2 additive fields per id:c7dc D-seams). Full `make test`: **381 passed, 0 failed, 3 expected-red** (unrelated open items). Cross-ledger drift reconciled: `id:34b7` was `[x]` in `ROADMAP.archive.md` but still `[ ]` in `TODO.md` line 436 — ticked (single-id-two-views D2; `orphan-scan --cross-ledger` misses it because the item is archived out of `ROADMAP.md`). `id:f91a` correctly stays OPEN — its close condition (34b7 done AND owner rules on d464) is unmet.

Re-derivation: after this chain, seam 2 **`id:e87d`** is now UNGATED (its blocker id:37f2 landed) and executor-ready → `routine_open` reflects it. relay-doctor + roadmap-lint findings (DEAD-GATE 2b49/540f/c179, parked orphans, relay-core shadow, f91a/34b7 promotion) are ALL already boxed above — no duplicate boxes added. NOTE for the human: relay-doctor reports **4 inbox dead-letters targeting this repo** (routed:4728/b7d8/c2b9/a808, all from today's 2026-08-11 escapement-scoping session — onboard escapement into relay.toml, re-scope cb1c, two Fable-protocol discussion items, and the --fabled 7-forced-findings evidence for id:8df5). They live durably in the git-tracked inbox and are surfaced by `/relay human`; route them via inbox-reconcile (`scan-routed.sh --apply`) or file into TODO — not re-recorded here to avoid a third parallel copy.

## Review of relay-ckpt-20260811-2019..HEAD (2026-08-11, apex reviewer, claude-opus-5)

Window deliberately anchored on the last **reviewer** checkpoint (`relay-ckpt-20260811-2019`), not the latest tag: the four checkpoints after it (2032/2052/2123/2137) are all `strong-execute`, which is *work*, not audit. Anchoring on the latest tag would have made this a 2-commit window and skipped the id:33b2 security-boundary change entirely — the id:da95 watermark defect, seen live.

- [x] **id:93ac — command-fence precedence in the id:33b2 stdin channel** (filed as a new `[HARD]` ROADMAP item, gates id:d4ca + id:e405). A `` ```relay-mech `` fence embedded in a stdin PAYLOAD overrides the loop's own command, because `_extract_mechanical_command()` takes the first fence in the whole text and nothing orders the two fences. Reproduced in-process; dispatch returned the payload's argument, not the loop's. Bounded by both existing gates (allowlisted script + `STDIN_ALLOWED_SCRIPTS`) and **not live today** — no hop uses the channel yet. **Human judgment wanted on the gate**: I have blocked d4ca/e405 on it. If you would rather ship d4ca first and accept argument-level redirection of `relay-status-publish.sh` from ledger prose, that is your call to make, not mine — say so and I will lift the gate.
- [x] **Run 71's "the two fences are disjoint by construction" is too strong** (`ROADMAP.md` audit note + `docs/meeting-notes/2026-08-11-2145-strong-model-audit.md`). The *regexes* are disjoint at the opener (verified true); *extraction* is not. Corrected inline in the id:93ac item rather than by editing the historical audit note. Worth noting that a 3-pass adversarial audit reached "CLEAN" on this diff — the miss was a generalization from the property actually tested, which is the failure mode `--fabled` exists to catch.
- [x] **5 declared relay scripts were missing from the install tree** — FIXED 2026-08-11 by `make install-relay`; re-ran `relay-doctor.sh`, zero `MISSING:` lines. The full set was `status-accounting.mjs`, `lint-embedded-literals.mjs`, `provision-worktree.sh`, `declared-path-extractor.sh`, `control-board.sh` — all present in the repo, none symlinked into `~/.claude/skills/relay/`. **`provision-worktree.sh` was the live one**: `relay/scripts/relay-loop.js:2746` dispatches it as `~/.claude/skills/relay/scripts/provision-worktree.sh`, the exact path that did not exist, on every unit dispatch since id:34b7 landed mid-run at 19:23. The [[relay-builtgreen-but-unreferenced]] class — built, tested, green, and not reachable. **Left for a human**: `make install` drift is invisible between relay-doctor runs and there is no gate that fires when a `relay_FILES` entry lands without an install; worth deciding whether the executor contract should require `make install` after touching the manifest, or whether relay-doctor's check should be promoted to `--strict` in some path.
- [x] **New parked orphan from run relay-20260811-144639-28608**: `relay/orphan/relay-20260811-144639-28608-execute` (WIP residue from the execute unit that died with "Prompt is too long"). 6 parked orphans across all own repos now. Dispose via `/relay reconcile`.

**Verification performed**: `gaming-scan.sh` clean (no deleted test, no added skip, no removed assert). `make test` **383 passed, 0 failed, 1 expected-red** — the repo declares exactly one tier (`make test` → `tests/run-tests.sh`); no e2e/integration tier exists to skip. §2b test-integrity: `test_mech_stdin_channel_33b2.sh` covers all five contract clauses and was strengthened, not weakened; no `@owner-accepted` introduced. §2d over-reach on id:33b2: the diff converted NO hop and widened NO allowlist — it matches the ratified id:a05c option-B acceptance clause-for-clause, so **id:33b2 is not reopened**; id:93ac is a gap in the acceptance itself, not executor infidelity. Cross-ledger drift: clean. roadmap-lint: clean.

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

## Handoff C2/C3 2026-08-13 (promotion judgment calls)

Two interpretations baked into the RED specs of the items promoted this handoff (id:292b,
id:f657, id:d119). f657 carries no judgment call (its contract is fully specified in TODO).

- [x] **id:292b — `# fails-against:` header scope: ALL headerless tests, or a marked defect-fix
  subset only?** The RED spec (`tests/test_vacuous_fixture_lint_292b.sh`) requires the header on
  every `tests/test_*.sh` that lacks a `# roadmap:` header, treating "no roadmap header" as the
  definition of "defect-fix test" (CLAUDE.md §Testing). But some headerless tests are harness /
  structure tests (e.g. a pure-shape lint test), not defect-fix regressions, and requiring
  `# fails-against:` on those may be noise. **Confirm**: is the requirement over ALL headerless
  tests correct, or should the lint key on an explicit opt-in marker (e.g. `# defect-fix:`) so
  only genuine defect-fix tests are held to it? Also note the item ships mechanism (1) ONLY — the
  CI runner that actually executes the declared negative case, plus mechanisms (2)/(3), are
  deliberately out of scope (follow-ups).
  **OWNER-DECIDED 2026-08-14 (`/relay human .`): keep ALL headerless tests in scope, PLUS an
  allowlist file for known shape/harness tests.** The opt-in-marker alternative (`# defect-fix:`)
  was REJECTED: opt-in means a genuine defect-fix test that forgets the marker escapes the lint
  entirely, so the blind spot grows silently — the fail-closed direction was chosen deliberately.
  Exemptions go in ONE reviewable allowlist file rather than scattered `# fails-against: n/a`
  comments, so what has been excused is auditable in one place. Implementation note for the
  executor: this changes the RED spec's exemption MECHANISM, not its scope predicate.

- [x] **id:d119 — owner-hold marker grammar + the deliberate roadmap-lint-only scope.** The RED
  spec proposes the spelling `<!-- owner-hold:REASON -->`; confirm or rename it before it is
  built (it becomes a grammar other tools may later read). AND confirm the scoping decision: this
  handoff scoped id:d119 to the REPORT-ONLY linter's recognition of the marker, and left OUT (a)
  migrating `id:540f`/`id:c179`'s real `gated-on:e62c,b0b1` to the new marker and (b) teaching
  `classify-repo.sh`'s dispatch gate to honour owner-hold — because removing `gated-on:b0b1`
  before the dispatch gate also honours the marker would make those owner-held items dispatchable,
  which the 2026-07-31 owner gate forbids. Confirm that (a)+(b) should indeed be a separate,
  coordinated step and not folded into id:d119.
  **OWNER-DECIDED 2026-08-14 (`/relay human .`), both halves:**
  1. **Marker spelling CONFIRMED as proposed: `<!-- owner-hold:REASON -->`.** Chosen over
     `<!-- owner-gate:REASON -->` and over overloading `<!-- gated-on:owner -->` (which would put a
     non-4-hex token into a space that today holds only ids). It joins the existing typed-edge
     family (`gated-on:`, `children-of:`) in shape; `REASON` is free prose after the colon.
  2. **(a)+(b) CONFIRMED as a separate, coordinated step — they must land TOGETHER, never split.**
     Ratifies the handoff's reasoning verbatim: migrating id:540f/id:c179's `gated-on:e62c,b0b1`
     to the new marker BEFORE `classify-repo.sh`'s dispatch gate honours it would make those
     owner-held items dispatchable in the gap — exactly what the 2026-07-31 owner gate forbids.
     Filed as its own item `id:b8e8` (see `TODO.md`), NOT folded into d119.

## review 2026-08-13 (relay-20260813-203957-8486, reviewer opus) — surfaced, not acted

- [x] **id:292b — intentional two-views scope divergence (expect a `--cross-ledger` flag).**
  This review closed the ROADMAP slice `id:292b` (mechanism (1) linter shipped, verified green)
  but LEFT the TODO twin `id:292b` OPEN because the TODO bundles the broader design (mechanism
  (2) reached-fixture, (3) ledger-token-shape, and the CI-runner negative-case check) that the
  ROADMAP item explicitly carved out of scope. So `orphan-scan.sh --cross-ledger` will report
  `292b` as "closed in ROADMAP, open in TODO" — that is EXPECTED here, not drift. Owner call: is
  keeping the follow-ups under the SAME id acceptable, or should they be re-minted as a distinct
  successor id so cross-ledger stays clean? (The `xledger-ok`-style suppression marker convention
  is routed:42c9 — not built here.)
  **OWNER-DECIDED 2026-08-14 (`/relay human .`): RE-MINT a successor id for the remaining
  mechanisms.** `id:292b` closes in BOTH views (the mechanism-(1) linter that shipped); the leftover
  scope — mechanism (2) reached-fixture, mechanism (3) ledger-token-shape, and the CI runner that
  executes the declared negative case — is re-filed as **`id:a73c`** (see `TODO.md`), together with
  the allowlist-file exemption mechanism decided in the box above. Cross-ledger stays clean with no
  suppression marker, so this does NOT wait on routed:42c9. The cost is accepted explicitly: the
  one-id-spans-the-design-thread property is broken here, and `id:a73c` carries a back-pointer to
  `id:292b` so the thread is still followable.

- [x] **inbox dead-letter backlog: 12 routed items unrouted (relay-doctor scan-routed, report-only).**
  `scan-routed.sh` reports 12 dead-letters (11 → dotclaude-skills, 1 → escapement) absent from
  their target TODO/ROADMAP. This is pre-existing backlog, NOT from this diff window; surfaced for
  a `/relay human` or `/meeting` routing pass (respecting `--exclude`/paused repos). Two are
  directly relevant to this session's fixes: **routed:f833 / routed:7a88** (roadmap-archive
  stub-leaving) — the destructive MECHANISM is now guarded by commit 12e9825 (`roadmap-archive.sh`
  stub-guard, test green), but f833's open (a)/(b) DESIGN call (teach the generic script to leave
  stubs vs delegate to a per-repo archiver) is UNRESOLVED and remains the owner's; and the
  **archive-blindness cluster** (routed:8b21 unpromoted-scan, routed:42c9/675b cross-ledger
  archive blind spot) — the `scan_ids` half is now fixed by id:3262 (commit 347866e), but the
  orphan-scan/unpromoted-scan halves are still open.

  **RESOLVED 2026-08-14 (`/relay human .`, tier-a auto-answer) — the inbox is DRAINED.** All 18 items targeting this repo were routed in this session's inbox pass: 15 auto-filed as INBOUND stubs by `scan-routed.sh --apply`, and 3 (`routed:057f`/`8b21`/`42c9`) recovered by hand from `git show HEAD:todo-inbox.md` after `--apply` deleted them on FALSE twin matches — a bare-token twin check satisfied by a prose mention inside a sibling item (defect filed `id:c97c`). Evidence: `scan-routed.sh` reports 0 dead-letters; `inbox-scan-repo.sh dotclaude-skills` reports 0 open lines; every one of the 18 tokens verified present exactly once by an ANCHORED grep (`<!-- routed:X -->|INBOUND routed:X`), never a bare-token grep. Re-checkable by re-running those three commands. NOTE: one NEW dead-letter is expected and correct — `routed:5018`, routed OUT to cartulary this session and not yet ingested there.

- [x] **roadmap-lint pre-existing warnings (none introduced this window).** `roadmap-lint.sh`
  WARNs (exit 0, non-blocking): DEAD-GATE on id:d4ca/id:e405/id:540f/id:c179 (all TODO-only,
  deliberately owner-held/gated — the false-positive DEAD-GATE these throw is exactly what the
  open [ROUTINE] id:d119 owner-hold-marker item is built to suppress); DEP-PROSE-UNTYPED on
  id:d4ca/id:e405; DECOMPOSED-CONTAINER on id:ae08 (already carries a route:hard-split annotation
  into seams id:02b2/99e5/5b12); NO-ACCEPTANCE-NO-TWIN on id:1b13 (an [INPUT — decision] item,
  structurally a /meeting question not executor work). No action taken — surfaced for the human's
  lane-assignment-at-source discipline (id:78ff).
  **CLOSED 2026-08-14 (`/relay human .`, OWNER-DECIDED) — every WARN is owned at source; the standing
  box is duplicate signal.** Owner's call, verbatim option: "Close it — id:b8e8 owns the fix". Re-ran
  `roadmap-lint.sh .` this pass: the same set, none new — DEAD-GATE ×6 rows (id:2b49, id:d4ca, id:e405,
  id:540f ×2, id:c179 ×2) and DEP-PROSE-UNTYPED ×2 (id:d4ca, id:e405). Ownership at source: the
  540f/c179 DEAD-GATEs are the EXPECTED false positive `id:b8e8` (`TODO.md:749`) exists to remove — its
  own acceptance clause requires `roadmap-lint` to emit no DEAD-GATE for them while `classify-repo.sh`
  still refuses to dispatch, asserted together; `id:d119` (`TODO.md:740`) ships the `<!-- owner-hold:REASON -->`
  grammar it depends on; DEP-PROSE-UNTYPED is `id:3f7e`. **Reopen condition** (this is what a closed box
  costs, stated so it is re-checkable): a lint WARN appears that no open item covers. The two currently
  in that position — DECOMPOSED-CONTAINER on `id:ae08` and NO-ACCEPTANCE-NO-TWIN on `id:1b13` — were
  inspected and are **benign by construction, not unowned**: ae08 already carries its `route:hard-split`
  annotation into seams id:02b2/99e5/5b12, and 1b13 is an `[INPUT — decision]` item, which has no
  executor twin to have. Neither is a defect the lint should stay open over. Note the lint exits 0
  throughout — these have never blocked anything.

- [x] **2 parked orphan branches (relay-reconcile --all).** `relay/orphan/relay-20260813-180303-4214-review-repo-0`
  carried the STRANDED close of id:292b — this review has now reconciled that (ticked id:292b in
  ROADMAP + annotated the TODO twin), so that orphan is superseded and safe to drop. The other,
  `relay/orphan/relay-20260813-180303-4214-execute-repo-0` (session log for id:f657/id:d119), is a
  parked orphan for the human's reconcile call.
  **RESOLVED 2026-08-14 (`/relay human .`, tier-a auto-answer) — both branches are GONE.**
  Evidence: `relay/scripts/relay-reconcile.sh /home/tobias/src/dotclaude-skills` prints
  `no parked orphans` (run this pass). Disposal is recorded independently in `TODO.md`
  id:8132, which states all four leftover worktrees from the 2026-08-12 run were retired by
  hand on 2026-08-13 via `worktree-retire.sh` (three clean `git branch -d`, one
  park-then-`--discard`). Re-checkable: re-run `relay-reconcile.sh <repo>` — a non-empty
  parked list reopens this box.

- [x] **id:cd9c was silently un-dispatchable — parked-vocab substring FP on its section heading (FIXED this window; hardening filed id:6446).** The owner-ruled (a), ungated `[ROUTINE]` `id:cd9c` (roadmap-archive stub-on-move, RED spec `tests/test_roadmap_archive_leaves_stub.sh` landed EXPECTED-RED) was excluded from dispatch — `classify-repo.sh` reported `actionable_routine_open:0` — because its section heading `## … — archive-path stub design call` contains `archive`, which `lib-roadmap-sections.sh`'s parked-vocab `(gated|deferred|done|icebox|archive|parked)` matches as a bare substring, parking the whole section. Renamed the heading `archive-path` → `stub-on-move` this review, which restores `actionable_routine_open:1 [cd9c]`; a guard comment now sits above the heading. **Root-cause hardening is id:6446** (make the vocab match intentional, not any-substring). Owner: confirm the heading rename is acceptable and greenlight id:6446's anchor fix so future `archive`/`done`-mentioning headings don't re-park live work.
  **OWNER-DECIDED 2026-08-14 (`/relay human .`) — BOTH confirmed: rename accepted, `id:6446` greenlit and PROMOTED.**
  Owner's call, verbatim option: "Confirm rename + promote id:6446". (1) The `archive-path` → `stub-on-move`
  heading rename stands as the immediate unblock — re-verified this pass that the live heading no longer
  carries a parked-vocab word. (2) `id:6446` is promoted from `TODO.md:761` to `ROADMAP.md` as an
  executor-ready `[ROUTINE]` item under the **same id** (single-id-two-views, D2 — no duplicate token
  minted); its acceptance and done-check were already written at TODO-authoring time and are carried
  across verbatim, so the pool can pick it up without a further handoff. Re-checkable: `grep -n 'id:6446'
  ROADMAP.md TODO.md` shows one open line in each, same token. **The rename is a workaround, not the fix**
  — it holds only until someone writes another heading that happens to mention `archive`/`done`/`gated`;
  `id:6446` is the durable one, which is why it was promoted rather than left as backlog.

- [x] **id:ec3c — cross-ledger drift with a SCOPE MISMATCH; do NOT auto-tick the TODO twin (review 2026-08-18).** `orphan-scan --cross-ledger` flags `id:ec3c` as `TODO:[ ] ROADMAP:[x]`. The ROADMAP twin (`ROADMAP.archive.md`, "statusline-command.sh hardcodes its four /tmp usage-state paths — make them env-overridable", reverse-handoff, REUSED the id) is genuinely done+verified: `statusline/statusline-command.sh:63-66` now read `${CLAUDE_USAGE_*:-/tmp/…}` overrides and `tests/test_statusline_path_overrides_ec3c.sh` is green. BUT the TODO twin (`TODO.md:651`) frames a **CLASS** — "Parallel-suite flakes are a CLASS" — of THREE flake instances: (1) statusline /tmp paths [FIXED here], (2) `test_git_lock_push_slash_branch.sh` ssh-agent state [spun out to an OPEN item `TODO.md:783`], (3) `test_relay_loop_intensive_emit.sh` [**NOT tracked anywhere**]. Ticking `id:ec3c` on the statusline closure over-closes the class and drops instance (3). This review LEFT `id:ec3c` OPEN and reverted a provisional tick. Owner's call: either (a) split instance (3) into its own `[ROUTINE]` item and close `id:ec3c` as the class-container, or (b) re-scope `id:ec3c` to the remaining instances. `cd9c` and `d119` (same-scope twins) WERE reconciled/ticked this pass. **RESOLVED 2026-08-18 (`/relay human .`, owner-decided).** Option (a) taken: instance (3) `test_relay_loop_intensive_emit.sh` split out as its own `[ROUTINE]` item `id:7a3d` (`children-of:ec3c`), and `id:ec3c` then ticked as the class-container — so the class closes with all three instances individually tracked and nothing dropped. Re-verified before ticking, not taken on trust: `statusline-command.sh:63-66` do carry the `${CLAUDE_USAGE_*:-…}` overrides and `tests/test_statusline_path_overrides_ec3c.sh` exits 0; instance (2) is open at `TODO.md:781`; and `grep -rn test_relay_loop_intensive_emit` across both ledgers + both archives confirmed instance (3) appeared ONLY as the test artifact of closed items, never as an open flake item. (This box's own line references had drifted — the class item is at `TODO.md:650`, not 651, and instance (2) at 781, not 783; located by content instead.)

## Review 2026-08-19 (chain-end re-ask, chain `relay-ckpt-20260818-1506` — id:8123)

`gaming-scan.sh` clean (no deleted tests / added skips / removed asserts). One closed item
this window (`id:f69b`, parallelise the suite); the rest were ledger/meeting/human batches.
Trust-but-verify found the suite is NOT deterministically green under load — the finding below.

- [x] **`id:f69b` LANDED the 5.4x speedup but the parallel suite is INTERMITTENTLY red under
  concurrent load — the "442/0/3, verified" green claim is a single-quiet-run claim, not a
  deterministic one.** Running the FULL suite in a loop on a loaded box (a relay pool running is
  the normal case), I saw distinct intermittent failures across ~20 runs: `test_run_tests_parallel.sh`
  (`-j 1 overrides JOBS=4: expected '1', got '2'`), `test_statusline_tokens.sh` (blank output), and
  once `test_no_silent_swallow.sh`; every one passes standalone. This is NOT test-gaming (scan clean,
  no weakened tests) and the speedup is real, so `id:f69b` was LEFT TICKED rather than reopened —
  reopening would re-dispatch the whole done parallelisation. Instead the residue is split into a
  targeted follow-up **`id:f875`** ([ROUTINE], filed this review) to make `test_run_tests_parallel.sh`'s
  seriality observation load-robust, and one instance was fixed inline (next box). **Owner call**: is
  the split disposition right, or do you want `id:f69b` reopened until the suite is deterministically
  green? Re-checkable: `for i in $(seq 20); do tests/run-tests.sh 2>&1 | grep '^failed:'; done` under load.
  **UPDATE 2026-08-19 (chain-end re-ask review):** the split follow-up `id:f875` has now LANDED —
  `test_run_tests_parallel.sh`'s seriality observation is load-robust (flock-ordered event stream,
  no point-in-time sample), so THAT specific flake instance is closed. The broader owner call stands:
  the suite is still not deterministically green under heavy load. Fresh evidence this review — running
  the full suite at load-avg ~15 flaked `test_mechanical_tag.sh` ONCE (446/1/2), which then passed
  standalone 3x and passed on the immediate suite re-run (447/0/2); no timing/concurrency in that test,
  so it is a fork/resource-exhaustion flake under contention, not a `test_run_tests_parallel.sh`-class
  sampling race. `id:f69b` still LEFT TICKED (speedup real, no gaming). Owner call unchanged.
  — ✅ **OWNER CALL MADE 2026-08-20 (`/relay human --all`): the split disposition is RIGHT — `id:f69b`
  stays TICKED, not reopened — and the residue gets ONE ITEM PER FLAKY TEST.** Reopening f69b would
  re-dispatch a completed parallelisation to chase a test-hygiene residue, which is the wrong unit of
  work; per-test items let each be reproduced and fixed independently. **Checked each of the three
  before filing anything, and only ONE was untracked:** `test_run_tests_parallel.sh` → `id:f875`,
  CLOSED green; `test_statusline_tokens.sh` → fixed under `id:ec3c` (`- [x]`, `TODO.archive.md:645`;
  the fix made `statusline-command.sh`'s four hardcoded `/tmp` usage-state paths env-overridable);
  `test_no_silent_swallow.sh` → **nowhere**, now filed as **`id:a4d2`**. Its done-check is explicitly
  repeat-under-load, because \"442/0/3, verified\" being a single quiet run is the exact weakness this
  box was opened to name. **Deliberately NOT merged in:** `tests/test_git_lock_push_slash_branch.sh`
  (`TODO.md:450`) stays a do-not-fix-yet n=1 observation, and `test_mechanical_tag.sh` above is a
  one-off fork/resource-exhaustion flake with no timing logic — neither has the evidence to justify an
  item yet, and inflating the class with singletons would make it unfalsifiable.

- [x] **`id:ec3c` instance (1) was closed as DONE but its ORIGINAL flaky test was never made
  hermetic — FIXED inline this review.** The id:ec3c fix made `statusline-command.sh` usage-state
  paths overridable (`CLAUDE_USAGE_{CACHE,HISTORY,BACKOFF,LOCK}`) and added a NEW test
  (`test_statusline_path_overrides_ec3c.sh`), but `tests/test_statusline_tokens.sh` — the test that
  MOTIVATED the class — still set only `HOME` and left the usage paths at their hardcoded `/tmp`
  defaults, so it kept racing the developer's live-session statusline and flaking in-suite. Completed
  id:ec3c's own stated shape ("have the test point them into its mktemp -d"): the four `CLAUDE_USAGE_*`
  paths now point into the test's `mktemp -d`. Verified still green standalone. No owner action — the
  ratified id:ec3c design authorized exactly this; recorded for visibility.

- [x] **relay-doctor surfaced 5 inbox DEAD-LETTERS whose target is THIS repo but which are in
  neither `TODO.md` nor `ROADMAP.md`** (report-only, not routed by this review — several are
  design-weight and belong to `/relay human` / `/meeting`, not a review turn): `routed:9ff0` (URGENT —
  pool DOUBLE-DISPATCHES: in-flight de-dup keyed on dispatch-time slot, not the item the child works),
  `routed:30c0` (URGENT/owner-ruling — a HARD lane silently dispatches to Sonnet when it also carries
  the wire marker), `routed:96de` (RELAY_STATUS.md last-writer-wins across concurrent `--afk` pools),
  `routed:236d` (`id:34b7` pre-dispatch worktree provisioning failed, emitted twice), `routed:f0bb`
  (hard-split must re-point dependants when it containerises an item). Route via `/relay human .` /
  `/meeting`, respecting paused repos. Re-checkable: `relay/scripts/relay-doctor.sh "$(pwd)"`.
  — ✅ **RESOLVED 2026-08-20 (`/relay human --all`, tier-(a) auto-answer).** All five are now filed
  in this repo's `TODO.md`, so the box's stated condition ("in neither TODO.md nor ROADMAP.md") is
  false. The `--all` inbox auto-filer (`scan-routed.sh --apply --exclude truncocraft`, SKILL.md
  invariant 1) ran at the top of this turn and wrote a committed INBOUND stub per item — it filed 11
  dead-letters overall and drained 1 twinned item. **Re-checkable, verified per id:** `routed:f0bb` →
  `TODO.md:701`, `routed:236d` → `:702`, `routed:30c0` → `:703`, `routed:96de` → `:704`, `routed:9ff0`
  → `:705` (one occurrence each; commits `99c29c6`, `44a4760`, `262cf19`, `2b83c03`, `bbf56b7`).
  Filing is ROUTING, not triage: the two URGENT ones (`routed:30c0` HARD-lane-dispatches-to-Sonnet,
  `routed:9ff0` pool double-dispatch) are now tracked items awaiting a lane + disposition, not
  resolved defects.

- [x] **`roadmap-lint` reports 5 pre-existing DEAD-GATE / DEP-PROSE-UNTYPED warnings on gated,
  owner-held items** (`id:2b49`, `id:d4ca`, `id:e405`, `id:540f`, `id:c179`) — gates pointing at
  RETIRED ids or at TODO-only ids never promoted, so they can never open. All predate this window and
  sit under owner-gates (the id:6b35 haiku-hop cluster + the visible-half item), so a review turn does
  NOT re-target them (guessing a lane/gate is handoff/owner work). Surfaced for the owner to drop or
  re-target the markers. Re-checkable: `relay/scripts/roadmap-lint.sh "$(pwd)"`.
  — ✅ **RESOLVED 2026-08-20 (owner, `/relay human --all`) — and the five were TWO different problems,
  which only resolving each target revealed.** **Class 1, FIXED this pass (mechanical, no judgment):**
  `ac7f`, `e62c` and `33b2` are each `- [x]` in `ROADMAP.archive.md`, so gates on them were
  **DISCHARGED, not dead** — the lint called them dead only because the archived items lost their live
  ROADMAP stub (the same stub-loss class loderite's `id:2ab3` names, and the same reason loderite's
  `id:4027` gate cleared). Markers replaced with an explicit discharge note rather than silently
  deleted, so the provenance survives: `id:2b49` (was `gated-on:ac7f`) is now **fully unblocked**, and
  `id:540f` / `id:c179` lost their `e62c` half. **Class 2, SURFACED not fixed:** `id:b0b1`
  (`[HARD — meeting]`) and `id:09e4` (`[ROUTINE]`) live only in `TODO.md` and were never promoted, so
  gates on them genuinely cannot open — `id:540f` and `id:c179` remain blocked on `b0b1`, `id:d4ca` and
  `id:e405` on `09e4`. Fixing that means either promoting the targets (assigning a lane, which
  `hard-lanes.md` says must be read from the item, not guessed — handoff C2's call) or re-targeting the
  markers (an owner decision about what those items truly depend on). A review turn may do neither, so
  it is now tracked as **`id:ae11`** rather than left in this queue. **Measured before and after:**
  `roadmap-lint.sh` reported 7 DEAD-GATE lines; it now reports exactly 4, all class 2.

- [x] **id:cc7e — OWNER CALL PENDING: spec conflicts with the shipped id:6059 design; RE-LANED [ROUTINE]→[INPUT — decision] by review relay-ckpt-20260819-1449.** The executor (relay-ckpt-20260819-1449 chain) correctly BLOCKED cc7e instead of gaming it: `meeting/md-merge.py` already implements id:6059 (it RAISES `AmbiguousOwnId` / refuses any line carrying multiple anchored `<!-- id:XXXX -->` markers, rather than resolving own-id as first-vs-last), so cc7e's RED test case (A) — an `update-ids` write aimed at the trailing OWN id must APPLY — can never pass against the intended behaviour. Two honest resolutions, both need your sign-off: (1) CLOSE cc7e in favour of id:6059 and retire `tests/test_md_merge_own_id_last.sh`; or (2) REDEFINE cc7e to assert the id:6059 refusal and author a fresh RED spec. Until then the item is parked as [INPUT — decision] (not executor-dispatchable) and its test stays EXPECTED-RED. Evidence: RELAY_LOG 2026-08-19 BLOCKED note; `grep -n id:6059 meeting/md-merge.py`. — ✅ **OWNER DECIDED 2026-08-20 (`/relay human --all`): option (2) REDEFINE, not close.** Rationale recorded with the decision: the `AmbiguousOwnId` refusal is currently pinned only by `md-merge.py`'s own code, with no spec asserting it is *deliberate* rather than incidental — closing cc7e would have left it untested. cc7e now owns that assertion and is re-laned [INPUT — decision] → **[ROUTINE]** (ordinary executor work once the direction is fixed). New contract on the ROADMAP twin (`ROADMAP.md`, `<!-- id:cc7e -->`): a fresh RED spec asserting `update-ids` RAISES `AmbiguousOwnId` and writes nothing for a line bearing >1 anchored marker, while a single-marker line still applies; `tests/test_md_merge_own_id_last.sh` is retired/replaced, since its assertions encode the retired spec. **NOTE — the TODO twin (`TODO.md:784`) could NOT receive this flow-back:** `md-merge.py` refused it with `AMBIGUOUS own id — line carries 5 anchored id markers (2f81, 7756, aaaa, bbbb, cc7e)`, because that item quotes marker literals as its own evidence. The guard fired correctly, on the very item that documents it; the ROADMAP twin carries the decision and both twins remain `- [ ]`, so there is no checkbox drift.

- [x] **id:293f is now GATE-READY — its `gated-on:2bc6` blocker landed this chain.** The mechanical detector (id:2bc6, `relay/scripts/hooks-path-shadow-scan.sh`) is built, tested, wired into `relay-doctor.sh`, and its live sanity run against the real `~/.config/relay/relay.toml` reproduces the exact finding the sweep was filed for: 7 EMPTY-SHADOW own repos (incl. `dotclaude-skills` itself, and `loderite` whose `core.hooksPath` points at `truncocraft/.git/hooks` — a rename residue) + 2 DELIBERATE. id:293f ([INPUT — access], owner-decided "build the detector first, then sweep") is now actionable: run `git config --local --unset core.hooksPath` on the 7 EMPTY-SHADOW repos (owner call — a security-relevant config change; the two DELIBERATE repos, zkWhale/toesnail, are a separate call to merge the global hooks in). Re-checkable: `relay/scripts/hooks-path-shadow-scan.sh` or `relay/scripts/relay-doctor.sh "$(pwd)" --only hooks-path-shadow`. — ✅ **SWEEP AUTHORISED + EXECUTED + VERIFIED 2026-08-20 (`/relay human --all`).** Owner chose "unset the 7 EMPTY-SHADOW, leave the 2 DELIBERATE as a separate call". `git config --local --unset core.hooksPath` ran on all 7 (dotclaude-skills, isochrone, trAIdBTC, zkm-stt, project_manager, mathematical-writing, loderite), each rc=0 and re-reading as unset. **Re-verified after:** the scan reports `52 own repo(s) scanned, 0 EMPTY-SHADOW, 2 DELIBERATE` (was 7/2), and in this repo `git config --get core.hooksPath` → `~/.config/git/hooks` with `pre-push` resolving to `hooks/pre-push-privacy-gate.sh`. **This box is closed; `id:293f` itself stays `- [ ]` on purpose** — its own recorded fix has FOUR steps and only three are discharged. Step 4 (push a throwaway branch carrying a KNOWN fixture pattern with `PRIVACY_GATE_LOG` pointed at a scratch file, confirm a line lands, never commit the fixture) proves the gate *fires*, not merely that it *resolves* — an outward-facing push the human runs. It is on the `/relay human` "you run these" checklist. zkWhale/toesnail remain a separate owner call.
- [x] auto-reconcile parked orphan `relay/orphan/relay-20260819-134717-30389-execute-repo-0` (0ceacbc) — non-ledger (code) diff in 4 file(s) (e.g. Makefile) — needs strong-turn review; --auto never auto-merges code. Subject: chore(relay): WIP UNVERIFIED residue auto-commit for worktree relay-20260819-134717-30389-execute-repo-0 (id:f272 commit-and-park; do not treat as reviewed). Surfaced 2026-08-19 16:48 by `relay-reconcile.sh --auto` (id:7809); integrate or discard manually: `relay-reconcile.sh --integrate relay/orphan/relay-20260819-134717-30389-execute-repo-0` / `--discard relay/orphan/relay-20260819-134717-30389-execute-repo-0`. — **REVIEWED + DISCARDED 2026-08-20** (`/relay reconcile --all`, owner-ratified). Verdict: SUPERSEDED, nothing unique. Re-checkable evidence: the branch was the earlier WIP park (tip `0ceacbc`, 2026-08-19 15:16) of the SAME item `id:dd7d` whose reviewed landing is `b966ea8` on main 25 min later (15:41); all four touched files are already on main in later form — `Makefile` (3 refs to `stranded-branch-scan.sh`), `mechanical-proxy.py` allowlist (1 ref), `relay-loop.js` (5 refs: both the pre-dispatch check and the `1c.` integrate sibling-comparison), and the script itself; a comment-stripped diff of `stranded-branch-scan.sh` shows identical flag surface (`--base --count --format --git-dir --item --verdict --verify`) and identical algorithm, with main's version STRICTLY more robust (validates the base ref resolves, defaults to `origin/main` when present, POSIX-hardened arg parsing). `id:dd7d` is `[x]` in `ROADMAP.md:1589` + `TODO.md:844` with `tests/test_redispatch_stranded_branch_dd7d.sh` present. Integrating would have REGRESSED the script, so the real choice was discard-vs-leave; owner chose discard. Ref deleted via `RELAY_DISCARD_CONFIRM=1 relay-reconcile.sh --discard`.

## Review 2026-08-21 (window `relay-ckpt-20260820-2044`..HEAD — 82 commits, ~18 closes)

NOTE: appended at the file's END, not the top — `md-merge.py` (the flock'd write path this
repo mandates) can only replace a `##` section or append an unknown one, and REVIEW_ME.md
carries no HTML id-marker at its head to anchor an `insert_before` against. Read this
section as the NEWEST. (Filing that gap as a tooling nit is the owner's call.)

Scope of THIS pass: ROADMAP re-derivation, the REVIEW_ME contract, cross-ledger, and an
anti-gaming spot-check. Six targeted agent audits (blast-radius, test-integrity/mutation,
evidence, synthesis, control-flow, transform) already covered this window and were
deliberately NOT redone. `make test` re-run standalone: 467 passed, 0 failed, 1
expected-red. `gaming-scan.sh` produced two `ADDED_SKIP` hits — BOTH verified false
positives (the literal word "skip" inside a docstring in `tests/lint-pipefail-sigpipe.py`
and inside a comment in `tests/test_slice_invitation_headroom_7575.sh`); no test file was
deleted and no assertion removed.

- [x] **`id:3a09` is TICKED but the guard it ships protects NOTHING today, and `id:6f62`
  says it cannot be wired as written — is that the close boundary you want?** The item's
  own text is fully honest about this ("INSTALLED BUT NOT WIRED — activation is the
  owner's"; a test asserts it is unregistered), and I independently confirmed
  `destructive-git-guard.py` has ZERO occurrences in `~/.claude/settings.json`. So this is
  NOT gaming — it is a scope question. But the sequence matters: the guard was ticked, and
  then `id:6f62` was filed recording that the hook misreads the discovery-producer daemon
  as an unattended run, so wiring it would hard-deny every INTERACTIVE session. A reader
  scanning tick-states sees "destructive-git guard: done". **Your call:** (a) leave ticked
  and rely on `id:6f62` carrying the wiring, (b) untick until `6f62` lands and the owner
  wires it, or (c) re-title it "…— hook AUTHORED (activation gated on id:6f62)".
  — ✅ **RESOLVED 2026-08-22 (`/relay human`) — tier (a): BOTH halves of the premise are now false,
  so option (a) "leave ticked" is simply CORRECT and the tick reads true.**
  **(1)** The guard IS wired — `destructive-git-guard.py` is registered in `~/.claude/settings.json`
  (line 909), and `tests/test_destructive_git_guard_3a09.sh` check (6) now asserts *it IS wired* and
  PASSES. The assertion this box cited (a test asserting it UNregistered) was INVERTED when the owner
  wired it; the file's own header records that both original claims "are now wrong".
  **(2)** `id:6f62` — the blocker this box named ("cannot be wired as written") — is `- [x]` at
  `ROADMAP.md:1627`. It fixed exactly that: the heartbeat probe now requires a marker to name a real
  POOL run via the shared `lib-pool-runs.py::is_pool_run`, so the `discovery-producer` daemon no
  longer reads as an unattended run and interactive sessions are not hard-denied on a false reason.
  Re-checkable in two commands: `grep -n destructive-git-guard ~/.claude/settings.json` and
  `tests/run-tests.sh tests/test_destructive_git_guard_3a09.sh`.

- [x] **A GREEN test sitting under an UNTICKED item is silently disarmed — `id:ebd0` is in
  that state right now (the `id:087b` shape, but standing).** `tests/run-tests.sh` reports
  a failing test as EXPECTED-RED while its `# roadmap:` item is unticked. That is correct
  for a RED spec, but it also means a test that is ALREADY GREEN under an open item has no
  teeth: if it regresses, the suite stays green-with-an-expected-red and nobody is told.
  `tests/test_privacy_gate_prepush.sh` passes standalone today while `id:ebd0`
  (`ROADMAP.md:1252`, `[INPUT — access]`) is open — the warn+log half shipped, the
  access half did not. I swept every `# roadmap:`-headed test in `tests/` and this is the
  only unambiguous instance. **Question:** should a partially-shipped item's green half be
  re-homed to a separate ticked item (so its test is armed), or is the disarm acceptable?
  A general fix — arm a test the moment it first goes green regardless of checkbox — is a
  runner change, not a review edit, so it is not made here.
  — ✅ **DECIDED 2026-08-22 (`/relay human`, tier (b) — owner): fix the CLASS in the runner, not this
  one instance.** `tests/run-tests.sh` will ARM a test the moment it first goes green, regardless of
  its `# roadmap:` item's checkbox, so a green test can never again silently regress under an open
  item. Because this changes a documented `CLAUDE.md` §Testing convention (expected-red semantics),
  it is filed as its own item rather than edited inline: **`id:86ca`** in `TODO.md`. `id:ebd0`'s
  green half is deliberately NOT re-homed — the owner chose the class fix over the one-off remedy,
  and the runner change subsumes the need.

- [x] **Four DEAD-GATE / two DEP-PROSE-UNTYPED `roadmap-lint` warnings persist (`id:d4ca`,
  `id:e405`, `id:540f`, `id:c179`) — all four are gated on ids that live ONLY in TODO.md.**
  Pre-existing, not introduced this window, and lint exits 0 (WARN, not FAIL). Nothing in
  ROADMAP.md can ever clear `gated-on:09e4` / `gated-on:b0b1`. Resolution is `id:49e0`'s
  choice — promote the gate targets (handoff C2's lane call, never guessed) or re-target
  the markers — and both are owner-gated items, so I did not touch them. Surfaced so the
  four are not read as accidentally-blocked a second time.
  — ✅ **DECIDED 2026-08-22 (`/relay human`, tier (b) — owner): fix the LINT CHECK, not the ledger.**
  The DIAGNOSIS is what is wrong. `resolve-gates.sh:36` already resolves gates against
  `ROADMAP.md ∪ TODO.md ∪ TODO.archive.md`, so a gate target living in `TODO.md` IS resolvable —
  only `roadmap-lint.sh` insists it must be in `ROADMAP.md`, which is why all four WARNs fire. Make
  lint agree with the resolver; that clears all four without touching a single gate marker. The
  alternative (promote `09e4` + `b0b1`) was explicitly REJECTED — `b0b1` is a deliberate OWNER gate
  and promoting it would put it in the execution queue's line of sight.
  **This box's counts VERIFIED correct 2026-08-22:** 4 DEAD-GATE (`d4ca`, `e405`, `540f`, `c179`)
  + 2 DEP-PROSE-UNTYPED (`d4ca`, `e405`), lint exit 0 — plus 2 NEWER `DECOMPOSED-CONTAINER` WARNs
  (`7518`, `372a`) that postdate the box.
  **Routing correction:** the box (and `roadmap-lint.sh`'s own WARN string) sends the reader to
  `id:49e0` — which is `- [x]` CLOSED and archived (`TODO.archive.md:515`,
  `ROADMAP.archive.md:3488`). The live owner is **`id:8de9`** (`TODO.md:494`), which already records
  the sibling inversion bug in the same check; the decision is recorded there, including a note to
  fix the dead `(id:49e0)` pointer in the WARN string itself.

## Review 2026-08-21 (focused, `relay-ckpt-20260821-1515`..HEAD — id:6f62)

One unit, 10 files. **Verified honest + green.** `gaming-scan.sh` clean; no `@owner-accepted` in
the window; no test deleted/skipped/weakened. Reproduction independently re-derived through the
REAL `~/.claude/hooks/` symlink with the REAL live `discovery-producer` marker: empty output,
exit 0 (DEFERS). Real pool marker still `deny`. `stop-request.sh` matrix re-run: 0 pools → exit 3
+ writes nothing; producer-only → exit 3 + writes nothing; 1 pool → exit 0 + targeted sentinel;
2 pools + producer → exit 4, lists both, writes nothing. Missing / corrupt / attribute-less lib
all fail SAFE (deny) in a scratch copy. Latency 22 ms/call, no subprocess. Boxes below are for
wiring readiness — none blocks the merge.

- [x] **The guard CRASHES (exit 1, traceback) on four malformed-payload shapes, and a crashing
  PreToolUse hook fails OPEN.** Reproduced: top-level JSON array or string (`payload.get` on a
  non-dict → `AttributeError`), `tool_input` a string (`.get` on `str`), and `command` a non-string
  (`"git" not in 123` → `TypeError`; a list reaches `shlex.split` and raises). Exit 1 is a
  *non-blocking* hook error — Claude Code surfaces stderr and RUNS the command — so the one input
  class that should never be trusted is exactly the class that bypasses the guard. Today's harness
  always sends a well-formed payload, so likelihood is low; impact is the "worst outcome" the
  wiring question named. **Recommendation:** `if not isinstance(payload, dict): return` plus
  `isinstance(command, str)`, and wrap `find_violation` so an unexpected exception routes to the
  conservative regex scan rather than to an uncaught traceback. <!-- id:3866 -->
  — ✅ **RESOLVED 2026-08-21 (executor). Promoted to `ROADMAP.md` under the SAME id and ticked.** Every branch of `main()` now exits 0 and `find_violation` never raises; the tokenised analysis routing to the conservative regex scan on an unexpected exception is the same safe side a `shlex` error already took. **Disposition for an unreadable payload (acceptance clause 2): DEFER — exit 0, EMPTY stdout, plus a one-line stderr note.** A payload that will not parse carries no command, so there is nothing destructive to block; blocking would make any future hook-protocol change a fleet-wide outage in front of every Bash call. The stderr note keeps it observable rather than a silent hole. Six shapes pinned (the four reported verbatim + empty stdin + invalid JSON), each asserted exit 0 / empty stdout / non-empty stderr, in `tests/test_destructive_git_guard_malformed_3866.sh`. Fail-safe branches re-verified: breaking `lib-pool-runs.py` three ways × (heartbeat dir present / absent) still denies naming `heartbeat probe ERRORED`. `settings.json` NOT written.

- [x] **A live marker whose `runId` is empty or non-string is SILENTLY IGNORED rather than treated
  as a probe error.** `is_pool_run("")`/`is_pool_run(None)` → `False`, and `_heartbeat_signal`
  `continue`s on a `False` — so an unclassifiable-but-FRESH marker contributes no signal and an
  interactive session DEFERS. That is right for `stop-request.sh` (an unnamed run cannot be
  addressed) but inverts the guard's own stated doctrine, where "cannot tell whether a pool is
  live" is ambiguity and must BLOCK. Narrow: `heartbeat.sh beat` refuses an empty runId, so no
  sanctioned writer produces one. **Recommendation:** in the guard only, distinguish "marker parsed,
  runId unusable" → `error` from "marker parsed, runId is a known non-pool" → skip. Keep
  `lib-pool-runs.py` as-is; the split belongs in the caller. <!-- id:8987 -->
  — ✅ **RESOLVED 2026-08-21 (executor). Promoted to `ROADMAP.md` under the SAME id and ticked.** Implemented exactly as recommended — the split is in the CALLER, `lib-pool-runs.py` is unchanged. A FRESH marker whose `runId` is empty, whitespace, or not a string now returns `error` ⇒ ambiguous ⇒ BLOCK (a non-object marker likewise); a fresh marker naming a known non-pool run still contributes nothing. Staleness is still evaluated BEFORE the runId, so a stale empty-runId marker remains no signal. Pinned in `tests/test_destructive_git_guard_malformed_3866.sh`.

- [x] **id:6f62 shared the runId predicate but left the LIVENESS predicate re-derived — the same
  drift shape, one level up.** The guard reimplements `heartbeat.sh`'s `is_alive` (ts + TTL) and
  its `3600` default instead of consuming `heartbeat.sh live-runs`. A divergence already exists:
  `hb_ts()` falls back to the file's MTIME when `heartbeat_ts` is missing or garbled and can call
  such a marker ALIVE, while the guard reads a missing field as `ts=0` ⇒ stale ⇒ skip. Both err
  safe today and nothing tests the parity. Note the re-derivation is a deliberate latency trade —
  shelling to `heartbeat.sh` would add a bash+`jq` fan-out to every Bash call. **Recommendation:**
  either a parity test pinning the two liveness rules against one fixture set, or an in-file
  comment stating the divergence is intended and why. Owner's call which. <!-- id:5f95 -->
  — ✅ **DECIDED 2026-08-22 (`/relay human`, tier (b) — owner): parity test against ONE fixture set.**
  The latency trade STAYS — the guard keeps its in-process re-derivation, with no bash+`jq` fan-out
  per Bash call — so this is explicitly NOT a one-definition extraction. What changes is that the
  divergence becomes MEASURED rather than assumed: one fixture set (valid ts, missing field, garbled
  field, expired ts, fresh ts) exercised through BOTH `heartbeat.sh`'s `is_alive`/`hb_ts` and the
  guard's ts+TTL rule, asserting the intended agreements AND pinning the intended MTIME-fallback
  difference, so a later change to either side fails loudly. The cheaper alternative (an in-file
  comment stating intent) was REJECTED — a comment rots, a test does not. Filed in `TODO.md`
  reusing **`id:5f95`**.

- [x] **The no-drift assertion prevents ONE SPELLING, not the rule.** The test greps both callers
  for `!= "discovery-producer"`. A reintroduced inline copy written as `== "discovery-producer":
  continue`, `not in ("discovery-producer",)`, or `startswith("discovery")` passes it untouched.
  A strictly stronger assertion is available and already true: both callers mention
  `discovery-producer` ONLY in comments (verified — guard lines 51/103/162, stop-request 58/59),
  so the test can assert ZERO non-comment occurrences of the literal in either file.
  **Recommendation:** tighten to the non-comment-occurrence form. <!-- id:4c14 -->
  — ✅ **RESOLVED 2026-08-21 (executor). Promoted to `ROADMAP.md` under the SAME id and ticked.** Tightened to the non-comment-occurrence form in `tests/test_destructive_git_guard_pool_signal_6f62.sh`: the guard is checked with `tokenize` (COMMENT tokens and triple-quoted docstrings exempt, plain string literals NOT — so `== "discovery-producer"` still counts) and `stop-request.sh` by stripping `#` lines. Negative control run before trusting it: an injected `== "discovery-producer": continue` mutant is MISSED by the old spelling grep and CAUGHT by the new assertion. The old assertion is retained beside it, so the change is strictly additive.

- [x] **Pre-existing (id:3a09 scope, NOT introduced here), surfaced because wiring is next:
  `eval 'git reset --hard'` and `bash -c 'git reset --hard'` are ALLOWED.** Not the
  command-substitution path — these tokenise cleanly, and `_split_git_commands` only starts a
  command at a bare `git` token, so the quoted string is one opaque argument. Also allowed:
  `git $(echo reset) --hard` (the raw-pattern fallback does not match). Correctly blocked:
  `git -C /tmp reset --hard`, `cd sub && git checkout -- .`, `git clean -fdx`, `git stash drop`.
  The guard is an accident-prevention lever, not an adversarial one, so this may be an accepted
  boundary — but an executor that hits the refusal could reach for `bash -c` as its next move,
  which is the routed-around-into-the-tree-wide-form failure the guard's own header warns about.
  **Recommendation:** owner's call — either accept and say so in `hooks/README.md`, or scan
  `eval`/`bash -c`/`sh -c` string arguments with the existing `_RAW_PATTERNS`. <!-- id:fb2c -->
  — ✅ **DECIDED 2026-08-22 (`/relay human`, tier (b) — owner): scan the `eval` / `bash -c` / `sh -c`
  string argument with the existing `_RAW_PATTERNS`.** Now load-bearing rather than theoretical:
  since the owner's 2026-08-22 ruling the five tree-wide forms are an UNCONDITIONAL deny, so an
  agent that hits the wall has a live incentive to reach for a wrapper — precisely the
  routed-around-into-the-tree-wide-form failure the guard's own header warns about.
  **Scope stays BOUNDED by explicit owner choice:** the command-substitution form remains an
  ACCEPTED, documented boundary. The fuller "close every wrapper form" option was declined — the
  guard is accident-prevention, not adversarial, and chasing substitution adds false-positive
  surface. Done-check pins the boundary as well as the fix, so it is deliberate rather than merely
  unimplemented. Filed in `TODO.md` reusing **`id:fb2c`**.
  **Observed while filing this, 2026-08-22:** the guard fired on a Bash call whose only offence was
  QUOTING a destructive form inside a heredoc — the `id:9979` false-positive class, live and now
  twice-confirmed, and it forced this very write-back onto a different tool path.

## Review 2026-08-23 (apex `--afk` hard gate — `id:7986` + `ref:da51`)

Window `eb582156~1`..`75e8f18e` (handoff + execute). **Verified honest + green** — `gaming-scan.sh`
clean, no `@owner-accepted` in the window, suite re-run independently: **493 passed / 0 failed /
1 expected-red** (`test_dryround_single_definition_6217.sh`, unrelated). `node --check` and
`lint-workflow-templates.mjs` both pass. The three sibling tests the executor rewrote were each
re-audited BEFORE-vs-AFTER: all three are strictly STRONGER (each replaced its old positive
assertion with an equivalent one plus a new ABSENCE assertion banning the superseded literal);
nothing was skipped, emptied, or loosened. The RED spec was verified non-tautological (12/12 red
against `eb582156`) and mutation-verified independently against five mutants — all five caught.
**No RELAY_LOG.md self-report exists for this window** (the executor died with "Prompt is too long"
at its commit step); the `refactor:` forcing-function line is therefore absent — noted, no cruft
visible in the diff.

- [x] **`--intensive` no longer implies `--afk` in practice, so `/relay --intensive` silently
  withholds every `hard` unit.** `relay/SKILL.md`'s `--intensive` flags-table row states
  "**`--intensive` IMPLIES `--afk`** (id:052c — a user need not pass both)" but documents only
  `Sets args.allowIntensive = true`; `relay-loop.js` derives `const AFK = !!A.afk` and never falls
  back to `ALLOW_INTENSIVE`. Before `id:7986` this was inert (`afk` had zero consumers). Now it is
  load-bearing: an `--intensive` run gets `AFK=false`, so `enforceApexGate` defers every `hard` unit
  with `HARD-execute at apex requires --afk` — on a run the docs call an away-run. **This does NOT
  violate the three owner rulings** (they say `hard` requires `--afk`, which the code does); it is a
  front-door contract self-contradiction. **Owner's call**, two clean options: (a) make the
  implication real — the front door sets `args.afk = true` for `--intensive` too (and the row says
  so), or (b) drop the "implies `--afk`" sentence and require both flags. Do not pick silently.
  <!-- id:84c5 -->
  - **OWNER-DECIDED 2026-08-23: make the implication REAL (option (a)), and enforce it in CODE, not only in the front door.** `relay-loop.js`'s `AFK` is now `!!A.afk || ALLOW_INTENSIVE`, so `/relay --intensive` permits `hard` dispatch as the docs have always promised. **Deliberate deviation from the option as worded** (it said "the front door sets `args.afk = true`"): the front door is PROSE in `SKILL.md` executed by an LLM session, and resting an apex-spend gate on prose alone is precisely the `id:7986` defect — an owner rule that was correct, documented, and unenforced for months. The front door DOES now also pass `args.afk` for `--intensive` (SKILL.md `:282`, `:856`), so the two agree; the code clause is the structural floor that holds when the prose is misread. Pinned by a new assertion group **(B7)** in `tests/test_apex_afk_hard_gate_7986.sh`, mutation-verified in a temp tree: reverting `AFK` to the bare `!!A.afk` fails B7 and ONLY B7 (`RED: 1 assertion group`).

- [x] **`relay/scripts/apex-gate.mjs` is declared in the Makefile's `relay_FILES` but is NOT in the
  live install tree** — `relay-doctor.sh` install-drift check: `MISSING: relay/scripts/apex-gate.mjs
  is declared in relay_FILES but not installed under ~/.claude/skills/relay`. Harmless to the pool
  today (relay-loop.js carries the byte-equivalent inline copy, and the test reads the repo tree),
  but this repo's convention is "the live install IS the published version", so the gap is real.
  Fix is one command, deliberately NOT run by this review because it writes outside the repo into
  `~/.claude/`: `make install-relay`. <!-- id:bfc9 -->
  - **RESOLVED 2026-08-23 (owner-approved, verified): `make install-relay` was run.** `ls -l ~/.claude/skills/relay/scripts/apex-gate.mjs` → symlink to the repo path; `check-install-drift.sh --canonical relay --installed ~/.claude/skills/relay` → `OK — relay fully mirrored (scripts + source targets)`, rc=0. This is another instance of the recurrence class already filed as `id:ba27` (auto-`make install` after a new relay script lands) — detection worked again, and again nothing acted on it until a human did.

**Observed, NOT filed as a defect (out of this unit's ratified scope):** the same model-id-coupling
class `id:da51` removed from the apex gate still exists on the Fable side — `relay-loop.js:240`,
`:2369`, `:2535` compare `STRONG_MODEL === 'claude-fable-5'` rather than asking `STRONG_TIER`.
Bumping the Fable pin would reproduce the da51 trap on the `-d` defer path. Pre-existing, untouched
by this window, and `id:f6a1` already owns the adjacent pin question.
