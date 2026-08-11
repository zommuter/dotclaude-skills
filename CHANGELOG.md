# Changelog

<!-- DERIVED at relay integrate from existing relay state (report.summary + worked ids) by
     relay/scripts/changelog-append.sh (id:b8fa). Newest bucket first; never hand-edit or
     reorder past buckets. This repo is DATE-bucketed and carries NO version (git = version
     SSOT — id:8ef3/D3, meeting docs/meeting-notes/2026-07-17-1541-semver-trigger-and-fleet-changelog.md).
     Semver repos across the fleet are release-bucketed instead, gated on the id:e647 bump.
     Started from now — history is NOT backfilled (per-close tags are unrecoverable). -->

## 2026-08-11

- id:3f7e — roadmap-lint.sh + todo-conformance.sh now WARN when an open item's (DEP: id) prose has no matching typed gated-on marker (shared lib-typed-edges.sh engine, twin-consumer agreement, new test, full suite 373/0/10-expected-red green). (id:3f7e)
- id:b099 — built relay/scripts/declared-path-extractor.sh (extract + eval-corpus) feeding disjoint-greenlight.sh, with test_declared_path_extractor_b099.sh; full suite 374/0/10-expected-red green (id:b099)
- review: id:3f7e verified genuinely green (DEP-prose-untyped lint, twin-consumer, 373/0/10-red); ticked TODO twin; inbox batch left for C2 triage (id:3f7e)
- Fixed validate-flags.sh to parse --flag=value for arity-1 flags (id:2047), closing the silent quota-cap-loosening hazard; full suite 375/0/9-expected-red green. (id:2047)
- id:cc90 — bounded execute-execute rechain (K<=3): chainDepth counter replaces the one-shot rechained boolean, generalizes chaining to execute units, records the 3 pre-registered answers in-source; full suite 376/0/8-expected-red (id:cc90)
- review: id:2047 (validate-flags --flag=value parse) verified genuinely green (manifest-driven, no overreach, suite 375/0/9-red); ticked TODO twins id:2047+b099 (archive cross-ledger drift) (id:2047,b099)
- Closed id:e44e (.changelog.lock dirty-tree pool-blocker) as already discharged by id:798b's git-dir-relocated lock — ticked both ROADMAP.md and TODO.md checkboxes, no code change, full suite 376/0/8-expected-red unchanged. (id:e44e)
- id:923b per-unit identity key — re-keyed worktreePathFor/branchFor/inFlight off a new unitKey(verdict,itemId,attempt) helper; full suite 377/0/7-expected-red (id:923b)
- review: id:e44e close verified genuinely valid — 798b git-dir lock structurally dissolves the .changelog.lock dirty-tree defect; suite 376/0/8-red green, no gaming, no overreach (id:e44e)
- id:d808 — gather-repo-state.sh's open_hard_pool now excludes @container epics and matches punctuation-variant BLOCKED markers, closing the phantom hard-verdict loop; full suite 378/0/6-expected-red. (id:d808)
- review: id:d808 close verified genuinely valid — @container/BLOCKED-glob fix faithful to RED spec, suite 378/0/6-red green, no gaming/overreach; reconciled cross-ledger TODO tick (id:d808)
- id:069b — meeting/personas.md deduped (27 redundant entries merged with provenance preserved), personas-conformance.sh added, append.sh now extends instead of duplicating an already-registered persona name; full suite 379/0/5-expected-red. (id:069b)
- id:ecce closed — ckpt-tag.sh/gather-repo-state.sh/SKILL.md now use a distinct `integrate (<model>)` label that never advances the strong-audit watermark; id:6217 investigated and BLOCKED (test assertion 4 unscoped-grep bug conflicts with its own scope statement, logged not weakened); id:34b7 sized past scope for this session (restructures the dispatch mechanism this child itself runs under). (id:ecce)
- review: id:069b close verified genuinely green (personas.md dedup + conformance + append extend-path, no gaming/overreach); reconciled cross-ledger TODO tick, resolved @container lint on c7dc, surfaced TICK-READY wave items + flaky test (id:069b,c7dc)
- classify-repo.sh --emit unit now passes priority_rank+evidence through from classify-verdict.sh (id:258d), first of three id:c7dc seams (id:258d)
- review: id:6217 decision-gate CONFIRMED warranted (2 blockers, gate_reason named 1 — surfaced both); fixed id:c7dc auto-split placeholder deps (id:0eb0); suite 380/0/4-red; routine_open=3 (id:6217,37f2,e87d,0eb0)

## 2026-08-10

- Pool silent-exclusion cluster: changelog lock no longer dirties target repos (id:798b); RELAY_STATUS accounts for every own repo in exactly one section (id:8c85); embedded-literal quoting linter recovered and its coverage hole fixed (id:ef9e) (id:798b,8c85,ef9e)

## 2026-07-31

- id:cbd2 — relay-doctor.sh now resolves REPO_ROOT via readlink -f + walk-to-Makefile, so its install-drift/reference-install checks give the same verdict whether invoked via source path or the installed symlink; unlocatable manifests now WARN loudly instead of silently SKIPping. (id:cbd2)
- commit-ledger.sh now resolves a bare repo NAME via the own-repo registry, matching the human.md §5 documented invocation (id:7142) (id:7142)
- orphan-scan.sh's typed-edge resolution map now includes ROADMAP.md (first-wins TODO/archive/ROADMAP), so a children:/gated-on: token naming a relay seam resolves instead of dangling (id:9be0) (id:9be0)
- review: id:9be0 verified genuinely green (orphan-scan resolves ROADMAP seams); reconciled cross-ledger TODO twins (9be0/cbd2/7142); suite 339/0/11 (id:9be0,cbd2,7142)
- id:c500 part 1 closed — relay-reconcile.sh's checkpoint label now explicitly declares itself non-strong by design (owner-ratified 2026-07-31), with an in-source comment; part 2 (loud ckpt-tag.sh warning) was already landed by a prior session on this branch. (id:c500)
- id:0af4 — md-merge.py update-ids now refuses a malformed replacement (missing own id marker, or non-checkbox payload against a checkbox target) instead of silently wiping the line, and gains an explicit append mode; full suite 341/0/9-expected-red. (id:0af4)
- review: id:c500 verified genuinely green (relay-reconcile non-strong label + ckpt-tag loud note, both parts); ticked TODO twin (cross-ledger sync); suite 340/0/10 (id:c500)
- id:05b0 — gather-human-backlog.sh @manual marker now anchored (standalone token, backtick-mention-safe) via one shared predicate at both call sites; suite 342/0/8-expected-red (id:05b0)
- worktree-retire.sh gains opt-in --commit-residue: commits a dirty relay-owned worktree's residue (WIP/UNVERIFIED) onto its own branch and parks it as relay/orphan/<bn>, instead of stranding it surfaced-and-left; relay-loop.js's context-death caller now passes the flag (id:f272) (id:f272)
- review: id:05b0 verified genuinely green (@manual marker anchored via shared predicate, suite 342/0/8-exp-red, no gaming/over-reach); ticked TODO twins id:05b0+id:0af4 (cross-ledger sync) (id:05b0,0af4)
- id:5648 — gather-human-backlog.sh emit_hard_lanes() now picks the item's own lane by textual leftmost-tag position instead of priority-order bucket checks, fixing the d84f prose-hijack/silent-drop; deliberately skipped the fixed-window approach after it regressed 6 real fleet items, verified with a zero-regression before/after diff. (id:5648)
- id:6b1c — anchored unpromoted-scan.sh's primary_lane path 3 (head or clause-boundary) so a lane tag merely mentioned in prose no longer mislabels an unlaned item promote/laned; full suite 344 passed, 0 failed, 6 expected-red. (id:6b1c)
- review: id:5648 gather-human-backlog lane-anchoring verified genuinely green (leftmost-tag position, suite 343/0/7-exp-red, no gaming/over-reach); reconciled cross-ledger (ticked TODO twin id:f272, dropped discharged gated-on:907e from id:6217) (id:5648,f272,6217)
- Closed id:74e7 — Makefile's RELAY_QUOTA_DECAY_7D default now agrees with relay/SKILL.md's RISING (0.30:0.90) doctrine, with a new hermetic test; full suite green (345 passed, 0 failed, 6 expected-red). (id:74e7)
- Fixed DECIDED-LEFT-OPEN's two false-positive classes (id:bf19): @container exemption + widened other-id-scoped strip, in the shared lib-state-claim.sh engine so roadmap-lint.sh and todo-conformance.sh stay in verdict-agreement; new hermetic test test_state_claim_container_fp_bf19.sh; full suite green (346/0/6 expected-red). (id:bf19)
- review: verified id:74e7 genuinely green (Makefile RELAY_QUOTA_DECAY_7D=0.30:0.90 agrees with SKILL.md RISING doctrine, hermetic test, suite 345/0/6, no gaming, not a superset); reconciled cross-ledger drift by ticking TODO twins id:74e7, id:6b1c (id:74e7,6b1c)
- executor: closed id:8c6f — meeting/SKILL.md step 0f.5 now mandates rendering --fabled closing-pass findings VERBATIM before any decision prompt, with reference-doc test test_meeting_fabled_verbatim_8c6f.sh; full suite 347/0/6-expected-red (id:8c6f)
- id:5bbb closed — new tests/test_mech_fence_allowlist_completeness_5bbb.sh statically resolves all 11 real relay-mech fences in relay-loop.js (incl. 2 via one-level call-site indirection) and asserts each script is in ALLOWED_RELAY_SCRIPTS; verified genuinely RED (worktree-retire.sh gap) then added the allowlist entry and confirmed green; full suite 348/0/6-expected-red. (id:5bbb)
- Shipped relay/scripts/lint-mech-model.mjs — lints every relay-mech fence-carrying agent() call for a hardcoded model literal instead of MECH_MODEL (id:4313), wired into all 3 Makefile allowlist blocks and make test; full suite 350/0/6-expected-red. (id:4313)

## 2026-07-30

- `@container` now excludes a decomposed parent from the relay's DISPATCH collectors, not just the lint/human ones — an `@container` ROADMAP item no longer fires `verdict=execute` (classify-repo.sh), no longer surfaces as `top_intensive` (gather-repo-state.sh), and no longer inflates the SAME-ITEM orphan carve-out (discover-repo.sh). Makes handoff.md/review.md's "collectors exclude that marker" true as written. (id:0cf5)

## 2026-07-29

- id:d6f0 — implemented finalDrainVerdict() in drain.mjs (drained/blocked-pending-human now self-verifying against actionability re-derivation, fail-closed on probe failure); RED spec now green; suite 321/0/6-xred. Live wiring at relay-loop.js's drain exit is NOT included (flagged in RELAY_LOG as needing design work — no test covers it). (id:d6f0)
- id:98ea — fixed test_redispatch_suppression_e3b7.sh's structural extraction (awk terminator never matched relay-loop.js's 4-space return, silently captured 674/2600 lines); brace-depth extraction now; 10/10 standalone + full suite 321/0/6-xred. (id:98ea)
- id:a225 diagram edge-coverage guard: relay-dispatch.mmd edges now carry mechanical enforced-by annotations, checked by new relay/scripts/diagram-edge-coverage.sh; suite 322/0/5-xred (id:a225)
- id:89d6 — claim.sh gains a release --run <runId> sweep verb releasing every claim held by a run; suite 324/0/9-xred (id:89d6)
- id:54be — front-door EXIT-ONLY teardown trap (heartbeat.sh stop + claim.sh release --run sweep) added to relay/SKILL.md + mode-b abort-means-abort prose fix; suite 325/0/8-xred (id:54be)
- review: re-derive since ckpt-1437 (user-injected) — verified 89d6 green + resolved TODO↔ROADMAP drift, dropped discharged a225 gate on 5f31, closed RED-suite box (suite 324/0/9), surfaced 2 boxes (id:89d6,5f31)
- id:b460 — added anchored §2d over-reach review check to relay/references/review.md (catches an honest implementation that is a strict superset of its ratified source, even with a green suite); suite 326/0/7-xred (id:b460)

## 2026-07-28

- review: id:18e2 quota-gate deadlock fix verified GENUINE GREEN (no gaming, resurrection-check clean, suite 309/0); 7142/bf19 reverse-handoff left in TODO; routine_open=0 (id:18e2)
- Closed id:f475 (arg-guard): scope-flag near-miss escalation + drop-the-following-positional fix in validate-flags.sh, suite 309/0 (id:f475)
- Mechanized the release: hop (id:f7d3) — releaseLease() now issues one model:'bash' fence per command (claim/resource/heartbeat) instead of one Haiku call over an &&-bundled prompt that could never pass the mechanical-proxy's single-fence gate; suite 310/0. (id:f7d3)
- Audited handback-followup/gaming-log haiku hops (id:4f10): both verdict (iii), trapped-behind-payload same class as id:d4ca; recorded, not converted; suite 310/0. (id:4f10)
- id:aa26 — retired the Fable-availability probe (probe-fable.sh + fable-probe.json cache), replaced with a plain config-read fable-config.sh; SKILL.md/meeting/SKILL.md/Makefile updated; suite 312/0 (id:aa26)
- executor: id:6f1c — taught executor contract symbol-level exploration (Grep/Glob/LSP + no-redundant-reread rule), contract v10→v11, CLAUDE.md pointer refreshed, fixed a v10-hardcoded test broken by the bump; suite 313/0 (id:6f1c)
- executor: id:213a — roadmap-lint.sh gains NO-ACCEPTANCE-NO-TWIN doctrine rule (WARN/--strict-ERROR) flagging open items with no Acceptance/Tests/Done-check clause and no TODO twin; fixed 5 unrelated test fixtures broken by the new rule's blast radius; suite 314/0 (id:213a)
- id:44a1 — id:3801's seam emitter now requires acceptance/done_check/file per hard-split seam, rendered as Acceptance/Done-check/Context sub-bullets; suite 315/0 (id:44a1)
- Closed id:e3b7 — null-report (context-death) handbacks now stamp the id:1432 noWorkNegCache too, so a dying repo can't re-dispatch straight back into the same death; RED spec added, full suite 317/0 green. (id:e3b7)
- Review clean: window = 1 id:61fa handback-followup ledger commit; gaming-scan clean, suite 317/0/0; reconciled 5 cross-ledger drifts, surfaced fable-config install gap; routine_open=0. (id:1af1,6f1c,77f3,213a,44a1,61fa)

## 2026-07-26

- id:78e1 — word-boundary-anchored lib-state-claim.sh terminal-word regex (hyphen-excluded boundary), fixing the id:6b35 fail-CLOSED false positive; new RED spec + suite 308/0/0 (id:78e1)
- review (claude-opus-4-8): id:78e1 lib-state-claim word-boundary fix GENUINE GREEN (RED spec non-tautological, id:6b35 live false-positive resolved, suite 308/0/0); id:27e3 reverse-handoff qualified (id:78e1,27e3)
- id:7e87 /meeting --fabled opt-in closing Fable-5 pass documented in SKILL.md + structural test; suite 309/0 (id:7e87)
- review: window is meeting/persona/archive/inbox-ingest only - audit clean, no gaming, no ledger deltas, routine_open=0

## 2026-07-24

- id:8913 landed — settles:/decided-in: typed-edge grammar + orphan-scan --settled/--unbackrefed (new RED spec authored, both required must-not-fire fixtures verified against real repo ground truth); suite 304/0/0 (id:8913)
- id:5533 shipped — shared two-directional state-claim contradiction predicate (lib-state-claim.sh) now backs both roadmap-lint.sh's DECIDED-LEFT-OPEN rule and a new todo-conformance.sh check; reverted the id:931c prose reword; suite 305/0/0. (id:5533)
- review: id:8913 + id:5533 verified genuinely green (RED specs real, no gaming); ungated cb3e (dep shipped), filed id:78e1 (state-claim word-boundary FP), 3 REVIEW_ME boxes; suite 305/0/0 (id:8913,5533,cb3e,78e1)

## 2026-07-23

- review: suite 293/0 green; verified 6176/7681/f9cd genuine (no gaming); minted id:ce50 for routed:bdee; routine_open=0 (id:6176,7681,f9cd,ce50)
- handoff: promoted id:ce50 (per-repo filtered inbox scan) + RED spec test_inbox_scan_repo.sh; suite 293/0/1-expected-red (id:ce50)

## 2026-07-20

- relay behaviour: distinct-key meeting↔executor lease (claim.sh WARN-not-refuse, id:0ee1); classifier not-executor-ready 3-class hybrid — @owner-verify exclusion + typed gated-on: via shared id:46f6 engine (blocks only OPEN targets) + SURFACED→handoff, extracted shared lib-typed-edges.sh (id:65f5); user-visible-close bump gate — review.md §5c fail-closed @owner-accepted marker + executor-contract v10 provenance + CLAUDE.md pointer (id:8089); one-unit-per-repo-per-round C2 invariant via round-plan.mjs (id:dc5b, worktree part); inbox-done twin-check anchored on lib-anchored-id.sh (id:3743) (id:0ee1,65f5,8089,dc5b,3743)

## 2026-07-19

- hard: closed ac7f (af48 KEYSTONE) — @wire grammar in hard-lanes.md, classify-repo @wire→actionable_routine_open count, new render-verdict.sh drained render-alias; suite 263/0 (id:ac7f)
- C5 66d4: shipped review-gate.sh tier-coverage checkpoint gate (mechanizes review.md §3), suite 264/0 green (id:66d4)
- C5 78df: shipped consumer-enum.sh spec-completeness listing aid (grep-based artifact-reader enumeration), suite green (id:78df)
- C2-C4: promoted id:798d (unpromoted-scan gated-twin fix) with verified RED spec; triaged 6 phantom/mis-classified promote items to REVIEW_ME (id:798d)
- Fixed unpromoted-scan.sh twin-check end-of-line anchor so auto-GATED ROADMAP items (marker + trailing gate note) are recognized as twins instead of phantom-re-dispatching; id:798d closed, full suite 266/0. (id:798d)
- Verified id:798d (unpromoted-scan gated-twin fix) genuinely green — real red→green, RED spec untouched, suite 266/0; reconciled 5 cross-ledger drift twins (e875/b9b5/ab5c/66d4/78df) (id:798d,e875,b9b5,ab5c,66d4,78df)
- a17a: authored the /relay + /meeting state-machine diagram set (3 Mermaid diagrams) + drift guard-test green; full suite 267/0 (id:a17a)
- handoff (claude-opus-4-8): re-laned id:4a46 [INPUT — decision]→[ROUTINE] (owner-resolved handback-log-completeness gate) + RED spec test_handback_invariant_equality.sh; suite 267/0/1-red (id:4a46)

## 2026-07-18

- Relay integrate now derives a `CHANGELOG.md` entry per close — `changelog-append.sh` folds the integrator's own `report.summary` + worked ids into a date bucket (this repo) or a `## vX.Y.Z` release bucket (semver repos, via `--version`); opt-in per repo, so it never fires where no `CHANGELOG.md` exists (id:b8fa)
- review: 20-commit window since relay-ckpt-20260717-1820 verified green (gaming-scan clean, suite 260/0); ticked shipped id:bbb2; verified e647/b8fa/7d20/fc0f/af5a; routine_open=0 (id:bbb2,e647,b8fa,7d20,fc0f,af5a)
- handoff: promoted 4 ROUTINE items (e875/b9b5/ab5c/eb46) into ROADMAP (8→12 open), 2 red specs, suite 260/0 (id:e875,b9b5,ab5c,eb46)
- Closed id:b9b5 — model-probe.sh grade arm swapped echo for printf so a literal -n/-e/-E/-ne output no longer mismatches; RED spec confirmed red then green; full suite 261/0/1-expected-red. (id:b9b5)
- memory-index.py resolves title:/hook:/description from metadata.* nesting + loud stderr warning (id:e875), full suite 262/0/0 (id:e875)
- Fixed flaky test_resource_claim_pid.sh (id:ab5c) — claim.sh's pid_alive() now retries the jq read 3x before concluding a PID-anchored claim is dead, eliminating the ~50%-flaky false-dead verdict under full-suite process load; full suite green 262/0/0. (id:ab5c)
