# ROADMAP archive
- [x] [ROUTINE] Refactor `relay/scripts/reconcile-repo.sh` into a pure PLANNER + thin APPLIER — add `--dry-run` that emits the plan JSON with ZERO side effects (parity oracle for relay-core ebdb-b) <!-- id:77ce -->
  - **Why** (TODO id:77ce, INBOUND routed:2f0c from relay-core): `reconcile-repo.sh` is currently apply-then-log — it *destroys* worktrees/branches at `:135-136`/`:139-140`, records the action at `:137`/`:141`, and only emits the JSON summary at `:177-200`. Because the side effect happens BEFORE the JSON exists, there is NO plan to shadow-compare against an alternate substrate and NO parity oracle. relay-core's ebdb-b (the Lean/substrate port) needs a pure `state → action-list` planner it can re-implement and diff byte-for-byte against this bash reference. This is the hard prerequisite for that port; it is substrate-neutral and buildable entirely in a worktree.
  - **How / Design**: split the script into two phases that share ONE decision core:
    1. **PLAN** — a pure function of observed repo state (upstream ahead/behind, porcelain, worktree listing, orphan refs) that produces the `actions`/`surfaced` lists WITHOUT any mutating git call. All the branching now inline in the SYNC/LOCK/WORKTREE/ORPHAN blocks moves here; the *observations* (`git rev-list --count`, `status --porcelain`, `ls` the worktree dir, `for-each-ref`) are read-only and stay, but the *mutations* (`merge --ff-only`, `add`/`commit`, `worktree remove`, `branch -D`/`-m`) are deferred.
    2. **APPLY** — a thin executor that walks the planned action list and performs the mutation for each `kind` (`ff-merge`, `lock-commit`, `reap`, `park`). `diverged-surface`/`suppress` are plan-only (no mutation).
    Add a `--dry-run` flag: when set, run PLAN and emit the SAME JSON, then STOP before APPLY — no git write happens. When absent, PLAN → APPLY → emit (identical observable behavior to today; every existing `test_reconcile_repo.sh` case stays green). The emitted `actions`/`surfaced` for a given input state MUST be identical with and without `--dry-run` (that identity IS the parity oracle: `--dry-run` JSON == the plan a live run acted on). Keep the CPython `json.dumps` sink at `:177-200` as the single canonical serializer (relay-core's Amendment F2 `jq -S -c` compare applies unchanged). **LiveClaims as an explicit tri-state (id:e3ad):** replace the `live_claims_provided` bool + `live_claims` string pair with one explicit representation of the three cases — flag-absent (Unknown → fail-closed, refuse reap/park), flag-present-empty (Known-empty → nothing live), flag-present-nonempty (Known set). Bash has no sum type; model it as a single sentinel-bearing variable (e.g. `live_claims="__UNSET__"` default vs `""` vs `"repoA,repoB"`) so the three states are one value, not two coupled flags — the current pair is what "modelling Option as a bool default costs" (id:e3ad). The fail-closed guard (id:e3ad) semantics must NOT change: Unknown still refuses every destructive op and surfaces. Add **git-free unit tests** for the PLAN function where feasible (feed it a synthesised observation record → assert the action list) IN ADDITION to the existing git-fixture behavioral tests — the planner's purity is exactly what makes it unit-testable without a real repo.
  - **Acceptance**: `tests/test_reconcile_planner.sh` (`# roadmap:77ce`) green — for each of the mutating states (behind-only→ff-merge, uv.lock-only→lock-commit, stale-empty-worktree→reap, commit-bearing-worktree→park), `--dry-run` emits the action in the plan JSON BUT leaves the repo byte-identical (HEAD unchanged, tree still dirty, worktree dir still present, branch still named `relay/<bn>`); AND the `--dry-run` action-kind list equals the live-run action-kind list for the same seeded state (parity). The existing `tests/test_reconcile_repo.sh` (live behavior, id:5987) must stay fully green (no regression). `--dry-run` unknown-arg no longer errors.
  - **Done-check**: `tests/run-tests.sh tests/test_reconcile_planner.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/reconcile-repo.sh` (the whole script — mutations at `:70`/`:93-94`/`:135-136`/`:139-140`, JSON sink `:177-200`, the `live_claims_provided` guard `:28`/`:102-116`), `tests/test_reconcile_repo.sh` (the live-behavior spec that must not regress), TODO id:77ce, relay-core routed:2f0c / ebdb-b.

<!-- 2026-07-10 review §5b reverse-handoff (run relay-20260710-171033-12826): promoted the
     manually-filed [ROUTINE] data-loss bug id:411d from TODO.md. Single-id-two-views (D2):
     REUSES its open TODO.md twin. RED spec tests/test_inbox_done_anchor.sh (# roadmap:411d)
     ships red; the fix (anchor the predicate on the item's OWN routed marker) turns it green. -->
- [x] [ROUTINE] `append.sh inbox-done XXXX` must delete ONLY the item whose OWN `routed:XXXX` marker matches — a prose cross-reference to that token in a sibling item is not the same item <!-- id:411d -->
  - **Why** (TODO id:411d, found 2026-07-10 routing two chidiAI cases): `meeting/append.sh`'s inbox-done predicate is `needle in l and l.lstrip().startswith("- [")` with `needle = f"routed:{token}"` — a SUBSTRING test, not an anchor. An inbox item whose *prose* legitimately cites a sibling's token (e.g. "the contrast with `routed:4fa9` is the signal") is a checkbox line containing that needle, so resolving the sibling **silently deletes the citing item too**. inbox-done is destructive by design (vanish-on-resolve) and the inbox is local-only / never committed, so a wrongly-deleted item is **unrecoverable** — no git twin to restore from.
  - **How / Design**: change the deletion predicate so it targets the line whose OWN routed marker is `routed:<token>`, not any line that merely mentions the token. Anchor on the marker form the inbox contract guarantees — CLAUDE.md specifies every inbox entry ends `<!-- routed:XXXX -->` — e.g. match a trailing `<!-- routed:{token} -->` (allowing optional whitespace), NOT a bare substring. A prose mention like `routed:4fa9` inside another item's text must NOT match. Keep the `- [` checkbox guard and the flock. Do NOT change the vanish-on-resolve semantics (the matched line is still DELETED, not marked `[x]`) — only tighten WHICH line matches. Preserve the `RELAY_INBOX` injection point (hermetic tests depend on it).
  - **Acceptance**: `tests/test_inbox_done_anchor.sh` (`# roadmap:411d`) green — a two-item fixture inbox where item A (own marker `routed:1234`) cites `routed:4fa9` in its prose and item B (own marker `routed:4fa9`) is the target; `inbox-done 4fa9` deletes B and PRESERVES A.
  - **Done-check**: `tests/run-tests.sh tests/test_inbox_done_anchor.sh` then full `make test` after ticking (RED until then).
  - **Context**: `meeting/append.sh:24-52` (the inbox-done block + Python predicate), CLAUDE.md §Cross-project TODO inbox (the `<!-- routed:XXXX -->` line contract), TODO id:411d.

<!-- 2026-07-08 handoff C2 (run relay-20260708-162516-22523, second pass): promoted the 3
     `promote`-disposition TODO items (unpromoted-scan: 3 promote / 154 surface). Single-id-two-
     views (D2): every id below REUSES its open TODO.md twin. 7725/aec5 = [ROUTINE] with RED specs
     (C3 below); f599 = [HARD — pool] measure-then-decide (pool-executed, no red spec). Surface
     items are the mechanical `human`-verdict filer's job, NOT promoted here (handoff.md §surface). -->
- [x] [ROUTINE] `heartbeat.sh reap-run <runId>` — reap a KNOWN-DEAD run's marker on OBSERVED failure, not just TTL expiry (id:7725) <!-- id:7725 -->
  - **Why** (TODO id:7725, observed 2026-07-07): the outage watchdog (id:98f0) correctly notified that the `-c`-crash run (relay-...-174626) died, but ~1h LATE and REDUNDANTLY — the session had already detected the Workflow failure immediately (task-notification), relaunched, and reconciled the orphans within minutes. The dead heartbeat marker lingered because at relaunch it was only ~25 min stale (UNDER the ~3600s TTL), so auto-reconcile-on-restart's stale-only `heartbeat.sh reap --prefix 'relay-*'` (id:7809, `relay-loop.js:1977`) skipped it; it aged past the TTL ~1h later and tripped the watchdog for a crash already resolved. The existing `reap` archives only PRESENT-but-STALE markers — there is no way to archive a marker known-dead by DIRECT OBSERVATION while it is still fresh.
  - **How / Design**: add a `reap-run <runId>` subcommand to `relay/scripts/heartbeat.sh` that archives THAT SPECIFIC run's marker (`heartbeats/<safekey>.json` → `heartbeats.done/`, flock'd, mirroring `stop`/`reap`) REGARDLESS of staleness — the run is known dead, so we must not wait for the conservative TTL. Idempotent (exit 0 when the marker is already absent, like `stop`). Log a DISTINCT line (`reap-run run=<id> reason=observed-dead`) so it is separable from a clean `stop`. Add it to the subcommand dispatch `case`, the `*)` usage list, and the `--help` header block. Then WIRE it into the two OBSERVED-failure sites so a promptly-handled crash stops re-alarming: (1) the front-door/observer path that catches a `relay-loop.js` Workflow reject (it holds `state.runId`), and (2) the auto-reconcile-on-restart handler in `relay-loop.js` (~line 1962-1981) — after `relay-reconcile.sh --all --auto` disposes a dead run's orphans, `reap-run` that run's marker immediately rather than leaning only on the stale-only `reap` backstop. KEEP the TTL `reap` path as the backstop for a truly-unobserved death (session killed, no observer — the case the watchdog exists for). Do NOT change staleness semantics of `status`/`dead-runs`/`reap`.
  - **Acceptance**: `tests/test_heartbeat_reap_run.sh` (`# roadmap:7725`) green — `reap-run` archives a FRESH (within-TTL) marker so it drops out of `status`/`dead-runs`; it is scoped to the named run (a sibling healthy run stays alive); it is idempotent on an absent marker. The JS wiring is guarded by `node --check` + `lint-workflow-templates.mjs` (no hermetic unit test for the Workflow-sandbox path — note this in the done-note).
  - **Done-check**: `tests/run-tests.sh tests/test_heartbeat_reap_run.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/heartbeat.sh` (`stop`/`reap` subcommands to mirror), `relay/scripts/relay-loop.js:1962-1981` (auto-reconcile-on-restart, the id:7809 handler), `relay/scripts/relay-reconcile.sh` (`--auto` disposes orphans; does not reap markers), TODO id:7725.
- [x] [ROUTINE] Generalize the discovery-only exec-smoke guard to ALL relay-loop.js prompt-builder templates (id:aec5) <!-- id:aec5 -->
  - **Why** (TODO id:aec5, 2026-07-07 follow-up to the id:5bac/efaf backtick crash): `tests/test_relay_loop_discovery_exec.sh` EXECUTES only the *discovery* dispatch, so an unescaped-backtick (or any other synchronous runtime fault) in the OTHER inline prompt templates (integrate, execute-child, review-child, handoff-child, quota, inject-take, auto-reconcile) still ships GREEN — `node --check` + grep miss a runtime throw. The id:71f2 static lexer lint (`lint-workflow-templates.mjs`) already covers the BACKTICK sub-case across ALL templates; this item adds the EXECUTABLE belt that also catches non-backtick runtime faults (a bad `${...}` reference, a mis-shaped tagged template) in the builders the discovery-only harness never evaluates. **Regression-guard, not a red-of-a-live-bug (handoff.md D1):** relay-loop.js has no such fault today, so once the harness exists this guard PASSES — it guards the NEXT such fault. Ships GREEN; the RED below is purely the missing harness/coverage.
  - **How / Design**: author `tests/fixtures/loop-round-exec-harness.mjs` mirroring `discovery-exec-harness.mjs`'s stub-globals technique (async-IIFE wrap; stubbed `log`/`phase`/`budget`/`parallel`/`pipeline`/`agent`), but feed the loop NON-EMPTY units of EACH verdict (`execute`/`hard`/`handoff`/`review`) plus an injected unit and a quota check, so EVERY prompt-building branch is entered and its template literal actually evaluated. The stub `agent()` records which builder labels it was called with and returns schema-appropriate stubs so the round drains; the stub `parallel()` records any thunk throw and the harness exits non-zero on it (reuse the existing harness's `thunkThrew` pattern). Print a `BUILT: <builder>` line per builder reached. Prefer extending coverage via richer stubs over a second harness only if it keeps the discovery-only test untouched (that test guards a shipped fix — do not weaken it). Keep the whole thing hermetic (no network/`~`/real git).
  - **Acceptance**: `tests/test_relay_loop_all_builders_exec.sh` (`# roadmap:aec5`) green — the harness runs clean (no synchronous throw in any thunk) AND emits `BUILT: <b>` for each of `execute-child`/`integrate`/`review-child`/`handoff-child`/`quota`/`inject-take`/`auto-reconcile`. (The exact builder-label strings are the executor's to reconcile with relay-loop.js's actual `agent()` `label`s — adjust the test's loop list to match the real labels if they differ, but every non-discovery builder must be exercised.)
  - **Done-check**: `tests/run-tests.sh tests/test_relay_loop_all_builders_exec.sh` then full `make test` after ticking (RED until then).
  - **Context**: `tests/test_relay_loop_discovery_exec.sh` + `tests/fixtures/discovery-exec-harness.mjs` (the pattern to generalize), `relay/scripts/relay-loop.js` (the prompt builders — search each `agent(` call's `label`), `relay/scripts/lint-workflow-templates.mjs` (the id:71f2 static belt this complements), TODO id:aec5.
- [x] [ROUTINE] `classify-repo.sh` — exempt whole gated/deferred ROADMAP sections from `actionable_routine_open` (align with `roadmap-lint.sh` `is_exempt_heading`) (routed:dfc1) <!-- id:356f -->
  - **Why** (TODO id:356f, routed:dfc1 from llm-from-scratch review 2026-07-02): `classify-repo.sh`'s routine-counting loop (`relay/scripts/classify-repo.sh:88-132`) walks each open `- [ ] ` line independently and excludes only LINE-SCOPED gates (`🚧` / `BLOCKED on` / `blocked on`, line 125). It has NO section-level gating. So a `[ROUTINE]` item parked under a `## Gated / deferred` (or `icebox`/`archive`/`parked`/`done`) heading — WITHOUT an inline marker — still counts toward `actionable_routine_open`, which gates the `execute` verdict (`classify-verdict.sh:91`). `roadmap-lint.sh` already treats such an item as EXEMPT (whole-section gating via `is_exempt_heading`, `roadmap-lint.sh:158-167` + the `in_exempt_section` tracker at `:172-211`). The two derivations disagree → a gated-section `[ROUTINE]` item mis-fires an execute dispatch (empty-handback no-op, the id:4da4 failure class). **Live-confirmed this handoff**: a `[ROUTINE]` item under a `## Gated / deferred` heading yields `actionable_routine_open=1` (must be 0).
  - **How / Design**: give the routine-counting loop in `classify-repo.sh` the SAME whole-section gating `roadmap-lint.sh` has. Track an `in_exempt_section` flag as the loop encounters `##`/`###` headings; a heading whose text matches (case-insensitive) `gated|deferred|done|icebox|archive|parked` opens an exempt section (any other `##`/`###` heading closes it) — mirror `roadmap-lint.sh:158-167` EXACTLY (same regex, same buckets) so the two never drift. While `in_exempt_section` is true, an open `[ROUTINE]` line must NOT increment `actionable_routine_open` (and, by the same section-gating, must not increment `roadmap_actionable_open` / `open_mechanical` — parked = parked for all lanes). Keep the existing per-line `@manual`/`🚧`/`BLOCKED`/primary-lane logic unchanged; this ADDS section-gating on top. Do NOT change `hasRoutine` semantics gratuitously beyond what the section-gate implies (a gated-only repo should read as having no ACTIONABLE routine work — assert on `actionable_routine_open`, the field the bug names). Factor the heading test to match roadmap-lint's phrasing so a future reader sees they are twins (a shared comment citing `roadmap-lint.sh is_exempt_heading` suffices; extracting a shared helper is OUT of scope — the two scripts are bash + python respectively).
  - **Acceptance**: `tests/test_classify_repo_gated_section.sh` (`# roadmap:356f`) green — a `[ROUTINE]` item under each of `gated`/`deferred`/`icebox`/`archive`/`parked` headings yields `actionable_routine_open == 0`; the SAME item text under a normal `## Items` heading yields `actionable_routine_open == 1` (proves the gate is section-scoped, not a blanket suppression); a line-scoped-marker case (`🚧`) still counts 0 under a normal heading (regression guard for the existing behavior). Hermetic mktemp repo, `--emit unit`, no `~/.config` touch (idiom: `test_classify_repo_standin_gate.sh`).
  - **Done-check**: `tests/run-tests.sh tests/test_classify_repo_gated_section.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/classify-repo.sh:88-132` (the loop to gate), `relay/scripts/roadmap-lint.sh:158-211` (the `is_exempt_heading` + `in_exempt_section` pattern to mirror), `relay/scripts/classify-verdict.sh:~91` (the `execute ⟹ actionable_routine_open>0` gate that mis-fires), TODO id:356f.

<!-- 2026-07-07 handoff (relay, Fable-tier): RED specs for the two genuinely executor-ready
     open TODO items (unpromoted-scan promote-set minus f599, which is [HARD — pool]
     measure-then-decide and deliberately NOT promoted here). Single-id-two-views: both ids
     reuse their open TODO.md twins. -->
- [x] [ROUTINE] purity-test-as-contract: shared `tests/lib/assert-repo-unchanged.sh` helper + documented convention (id:758e) <!-- id:758e -->
  - **Why** (TODO id:758e, 2026-07-07 near-miss): `test_discovery_producer_readonly.sh` proved the pattern — a component *labeled* read-only must carry a test that PLANTS a repo (commit + dirty file + live worktree), runs the component, and asserts the repo state is byte-identical after (no commits/fetch/worktree changes, HEAD/reflog unchanged). Generalize that inline pattern into a SHARED helper so every future read-only/snapshot/pure label ships a purity test cheaply, and document the convention so it can't stay tribal knowledge. See [[feedback-enforce-not-document-contracts]].
  - **How / Design**: new sourceable bash library `tests/lib/assert-repo-unchanged.sh` (`set -euo pipefail`-compatible; sourcing has NO side effects) defining exactly two functions: `repo_state_snapshot <repo-dir>` → deterministic state blob on stdout capturing at least HEAD sha, all refs (`git for-each-ref`), HEAD reflog, `git status --porcelain`, `git worktree list --porcelain`, and the stash list — and itself read-only; `assert_repo_unchanged <repo-dir> <saved-snapshot-file>` → exit 0 iff the current snapshot is byte-identical, else NONZERO with a loud stderr diff/description (no-silent-swallow, id:4347). Blob format is the executor's choice — the test asserts behavior (detects commit / untracked-file / worktree-add drift; passes on pure reads; snapshot is deterministic across back-to-back calls), not format. Then add a short `### Purity-test-as-contract` note to `relay/references/executor-contract.md` (the phrase `purity-test` must appear) stating the rule: any component documented as read-only/snapshot/pure MUST ship a purity test built on this helper. Do NOT bump the contract version marker (v6) — this is an additive test-authoring convention, not a rule change an in-flight executor must know; the no-bump call is recorded in REVIEW_ME.md for the reviewer to overrule. Optional follow-up refactor of `test_discovery_producer_readonly.sh` onto the helper is OUT of scope (don't touch that test — it guards a shipped data-loss fix, and a parallel executor is working in adjacent files).
  - **Acceptance**: `tests/test_purity_helper.sh` (`# roadmap:758e`) green — helper exists, sources cleanly, both functions behave per the drift/no-drift cases above, drift diagnostics are on stderr, and executor-contract.md documents the convention.
  - **Done-check**: `tests/run-tests.sh tests/test_purity_helper.sh` then full `make test` after ticking (RED until then).
  - **Context**: pattern source `tests/test_discovery_producer_readonly.sh`; convention target `relay/references/executor-contract.md` §Maintenance (version-bump rule); `tests/lib/` does not exist yet — create it.
- [x] [ROUTINE] `relay-gap-sample` hardening: hermetic test green + `make install-gap-sample`/`uninstall-gap-sample` + SKILL.md doc line (id:bf7a) <!-- id:bf7a -->
  - **Why** (TODO id:bf7a): the between-runs churn evidence logger (`tools/relay-gap-sample.sh` + `.service`/`.timer`, shipped+enabled 2026-07-02, commit 79df6fc) landed test-less and without install plumbing while the pool held this repo's claim.
  - **How / Design**: the hermetic behavior spec ALREADY EXISTS as the first half of `tests/test_gap_sample_install.sh` (stubbed `RELAY_SCRIPTS` island; change-line on first tick, tick-only on unchanged second run, loud ERROR verdict + `classify_errors` count on classify failure — all passing today, i.e. that half is a regression guard). What's missing (the RED half): (1) Makefile `install-gap-sample` / `status-gap-sample` / `uninstall-gap-sample` targets mirroring `install-quota-timer` EXACTLY (symlink `tools/relay-gap-sample.{service,timer}` into `$(SYSTEMD_USER)`, `daemon-reload`, `enable --now`; uninstall disables + removes symlinks; add all to `.PHONY` and the `help` text; status target optional but matches the sibling pattern); (2) one `relay-gap-sample` doc line in `relay/SKILL.md` §Shared resources (what it logs, where the JSONL lands, the make target, id:bf7a). The timer is ALREADY enabled live from the 2026-07-02 hand-install — the install target must be idempotent over that (ln -sf semantics already are).
  - **Acceptance**: `tests/test_gap_sample_install.sh` (`# roadmap:bf7a`) green — behavior spec sections still pass, `make -n install-gap-sample`/`uninstall-gap-sample` succeed and reference both unit files, `relay/SKILL.md` mentions relay-gap-sample. The test never runs real `systemctl` (asserts via `make -n` only) — keep it that way.
  - **Done-check**: `tests/run-tests.sh tests/test_gap_sample_install.sh` then full `make test` after ticking (RED until then).
  - **Context**: `Makefile:245-266` (install/status/uninstall-quota-timer, the pattern to mirror), `relay/SKILL.md:492` (§Shared resources), `tools/relay-gap-sample.{sh,service,timer}`.

<!-- 2026-07-02 handoff C2 (run relay-20260701-234115-26818): promoted from the open TODO backlog.
     unpromoted-scan reported 9 promote / 71 surface; 4 of the 9 (33c2/a505/7b23/b8ae) were
     prose-substring MISLABELS of untagged items (the id:fb7f bug class, live evidence recorded
     in that item) — they were lane-tagged in TODO.md instead (33c2/a505/7b23 → [HARD — meeting],
     b8ae → [HARD — hands]) so they become honest `surface` items for the mechanical filer.
     Single-id-two-views (D2): every id below reuses its open TODO.md twin. -->

<!-- 2026-07-03 handoff (relay): RED spec for shadow-log RED-row persistence + sig-fidelity fix (id:e833),
     the harden-forward that closes id:3134's instrument gap (3 disputed RED cases were un-adjudicable). -->
- [x] [ROUTINE] `shadow-log.jsonl` per-repo RED-row persistence + close the sig-fidelity gap that manufactures FALSE RED (id:e833) <!-- id:e833 -->
  - **Why** (TODO id:e833, resolving id:3134 2026-07-03): the a0b6 classifier-flip tripwire (`backtest-verdict.py` → `~/.config/relay/shadow-log.jsonl`) showed `red>0` in several snapshots, but the entries store only the AGGREGATE count (`{"red":3,...}`) — so the 3 disputed RED cases (leAIrn2learn/yinyang-puzzle/zkm-threema) were **un-adjudicable post-hoc** and had to be hand-reconstructed from `relay-events.jsonl`. Root cause of those false REDs = a **sig-fidelity gap**: `discover-sig.sh` hashes HEAD/ckpt-tags/porcelain/upstream/worktrees/orphans/roadmap/dq but NOT the post-execute unaudited-commit flip (the `substantive_unaudited` axis / the audit-ckpt-tag's TARGET commit). So a legitimate `execute→review` advance leaves the discover-sig UNCHANGED, and the RED bucketer (fires when `dispatch_sig == cur_sig` but verdicts differ) mislabels that documented `substantive_unaudited→review` policy-delta as RED. Both halves make `red>0` finally mean "a real classifier defect", not noise.
  - **How / Design** (two parts, one item):
    1. **Persist per-repo RED rows.** `backtest-verdict.py` already computes per-repo `rows` (repo, live `verdict`, `last_mode`, `note`) and threads each RED's `dispatch_sig`/`cur_sig` through the e8ea bucketer. Add each RED row to the `--append-log` shadow-log entry as `red_rows`: a list of `{"repo","dispatch_verdict","classifier_verdict","sig"}` (dispatch_verdict = the last-dispatch mode; classifier_verdict = the live classify verdict; sig = the shared dispatch/current sig), with `len(red_rows) == entry["red"]`. Do NOT drop the aggregate `red` count — this is additive. (Rows for non-RED buckets are out of scope; keep the entry lean.)
    2. **Close the sig-fidelity gap — executor's choice, note which:** EITHER (2a) add the `substantive_unaudited` / unaudited-commit signal (equivalently the audit-checkpoint anchor's target) to `discover-sig.sh`'s hashed blob — over-invalidation is SAFE per the CLAUDE.md sig-cache note (under-invalidation is the only hazard), so err toward changing the sig; OR (2b) teach `backtest-verdict.py`'s RED bucketer to reclassify a same-sig `execute→review` advance as EXPECTED (mirroring `backtest-historical.py`'s `match_policy_delta` `substantive→review` rule). Prefer 2a: it fixes the fidelity at the SOURCE so every sig consumer benefits and no second policy-list has to be maintained; 2b only patches the one report. If 2a, add the new signal to `discover-sig.sh`'s blob ONLY (do not touch its fail-open contract), and remember the sig-cache superset rule.
  - **Acceptance**: `tests/test_backtest_red_row_persist.sh` (`# roadmap:e833`) green — one `backtest-verdict.py --json --append-log` run over two fixture repos asserts BOTH: (1) the shadow-log entry carries `red_rows` (a list of `{repo,dispatch_verdict,classifier_verdict,sig}`, `len==red`) with the genuine RED repo attributable (dispatch review / classifier execute / its sig), and the execute→review repo ABSENT from `red_rows`; (2) the `execute→review`-at-same-sig repo buckets EXPECTED, not RED (assertion is on the OUTCOME "not counted RED", satisfiable via EITHER 2a or 2b). Full `make test` green after ticking this item's checkbox (RED until then).

<!-- 2026-07-03 handoff (relay): RED spec for backstop-fire instrumentation (id:854c) — b50e GO-criterion (a). -->
- [x] [ROUTINE] instrument that the three JS-side dispatch backstops FIRE — persist each fire durably to the `relay-events.jsonl` history so fire-frequency is measurable over a window of runs (id:854c) <!-- id:854c -->
  - **Why** (TODO id:854c, b50e GO-criterion (a) 2026-07-03): the three deterministic dispatch backstops in `relay-loop.js` — id:000d finished-repo demote (~line 919), id:9973 HARD-pool demote (~line 951), id:ad74 INTENSIVE promote (~line 992) — each `log()` when they fire, but that log goes ONLY to Workflow-sandbox stdout; **nothing persists it**, so there is no measure of how often they actually fire. b50e (delete the backstops) is NO-GO partly for lack of this fire-frequency data — its GO condition needs "a window of NON-drained forward runs with 000d/9973/ad74 firing 0 times", which is unobtainable while fires vanish to stdout.
  - **Sink (chosen — REUSE, do NOT invent)**: the append-only `relay-events.jsonl` history substrate, via the SAME pipeline `dispatch`/`integrate`/`handback` events already use to persist durably from inside the no-fs/no-net/no-shell Workflow sandbox: `pushEvent(kind, fields)` → `pendingEvents` → `snapshotState()` drains via `splice` into the `RELAY_STATUS` heredoc after the `===RELAY-EVENTS===` sentinel → `relay-status-publish.sh` → `relay-state-write.sh event-append` → `~/.config/relay/relay-events.jsonl`. A backstop fire is an EVENT (a thing that happened), so the append-only event log is the right sink — NOT `relay.toml` (`toml-set`) or `RELAY_STATUS.md` (`status-write`), both rewritten each round and unable to accumulate a fire count. `pushEvent` is the ONLY durable side channel available inside the sandbox.
  - **How / Design**: inside each of the three backstop blocks, emit a `backstop`-kind event through `pushEvent` (directly, or via one small helper — e.g. `emitBackstopFire(id, units, action)` — reused by all three) carrying WHICH backstop (`000d`/`9973`/`ad74`), the `repo`/unit it acted on, and the `verdict` it demoted/promoted (i.e. the record `{ts, runId, kind:'backstop', backstop, repo, verdict}`). Keep the existing `log()` lines (human-readable trace); the `pushEvent` is the durable counterpart. Emit one event per affected unit so a fire on a batch attributes each repo. Add an `id:854c` marker. Do NOT change any demote/promote LOGIC — this is instrumentation only. Respect the template-literal linter (`lint-workflow-templates.mjs`) and the no-fs/net/shell sandbox constraint (no `Date.now()`/`new Date()` — `pushEvent` already stamps `state.ts`).
  - **Acceptance**: `tests/test_backstop_fire_log.sh` (`# roadmap:854c`) green — (A) source-shape: each of the three backstops (id:000d/9973/ad74) emits a durable `backstop`-kind event through `pushEvent` carrying repo + verdict; `node --check` + template lint stay clean; (B) outcome: a synthetic backstop event round-trips through the real `relay-status-publish.sh` → `relay-state-write.sh event-append` pipeline and lands in `relay-events.jsonl` with `kind`+`backstop`+`repo`+`verdict` (part B already passes — it validates the SINK; the RED is entirely the missing part-A wiring). Full `make test` green after ticking this item's checkbox (RED until then).

<!-- 2026-07-03 handoff (relay): RED spec for the tag-first-among-trailing-tags lint (id:ad8a). -->
- [x] [ROUTINE] `roadmap-lint.sh` tag-first rule — flag an open item whose genuine lane tag is NOT the first recognized lane-tag (a prose/backtick'd lane bracket precedes it) (id:ad8a) <!-- id:ad8a -->
  - **Why** (TODO id:ad8a, the "A" floor of the d259 A→C decision): the id:4da4/id:0d58 PRIMARY-LANE anchoring both `classify-repo.sh` and `gather-repo-state.sh` rely on assumes the genuine capability lane is the FIRST recognized lane-tag on the line — but `classify-repo.sh` anchors on the RAW first-position tag (`min()` over `LANE_TAGS`, NO backtick strip) while `gather-repo-state.sh::roadmap_primary_lane` anchors on the first tag AFTER stripping backtick-quoted spans (id:1bbd). When a prose/history lane bracket (typically a backtick'd mention) sits BEFORE the item's own bare tag, the two readers split-brain — `classify-repo` mis-anchors on the prose one. This is the c3f5/leAIrn2learn hazard the anchoring was built to survive; `roadmap-lint.sh` has no rule enforcing the invariant, so a violating line slips past the grammar (the sibling parser fix landed as id:fb7f; this is the lint counterpart).
  - **How / Design**: add a check to `roadmap-lint.sh` reusing the case-c (id:09a3) detection idiom + severity convention. For each open `- [ ]` item compute `raw_first` = first recognized lane-tag WITHOUT stripping backticks (classify-repo's `min()` view) and `genuine_first` = first recognized lane-tag AFTER stripping backtick spans (gather's `roadmap_primary_lane`, id:1bbd); FLAG when `genuine_first` exists but `raw_first != genuine_first`. Match the lane-tag SET exactly to `LANE_TAGS`/`roadmap_primary_lane` so the lint agrees with the classifier. A legitimately-first lane with a LATER prose bracket is compliant (`raw_first == genuine_first`) — do NOT over-flag. The diagnostic must name the ORDERING/anchoring (first/precede/anchor), distinct from case-c's "conflict/multiple lane brackets" wording, so the two rules are separable. To keep the c3f5 compliant shape fully clean, prefer also making case-c's lane-count backtick-aware (strip backtick spans before counting, mirroring id:1bbd) — otherwise it still false-positives that shape as a two-lane conflict.
  - **Severity**: default to a report-only **WARN** per "observe before preventing" (the dual-vocab migration window churns lane tags); the current ROADMAP.md/TODO.md are clean of THIS violation, so a hard ERROR (nonzero exit) is also safe if preferred. Wire whichever; the RED test is severity-agnostic (asserts the diagnostic is/ isn't SURFACED, not an exit code). Do NOT edit `roadmap-lint.sh`'s existing case-c severity contract beyond the backtick-awareness note above.
  - **Acceptance**: `tests/test_roadmap_lint_tag_first.sh` (`# roadmap:ad8a`) green — (a) an open item with a backtick'd/prose lane bracket BEFORE its genuine lane tag is flagged with a tag-first/ordering diagnostic; (b) a plain tag-first item is NOT flagged; (c) the id:0d58/fb7f/c3f5 shape (`[HARD — pool]` genuine-first, a backtick'd `[ROUTINE]` quoted LATER) is NOT flagged by the tag-first rule. Full suite green after ticking (RED until then).
  - **DONE 2026-07-03 (executor)**: tag-first WARN rule shipped (report-only, exit 0) — `first_lane_tag()` mirrors `roadmap_primary_lane`'s backtick-strip (strip=1) alongside a raw no-strip scan (strip=0, mirrors `classify-repo.sh`'s `min()`); flags when they diverge. **Case-c backtick-awareness NOT applied** — verified regression: stripping backticks before counting collapses `test_roadmap_lint_tagprose.sh`'s own case-c fixture (`[HARD — decision gate] … actually re-laned to `[HARD — pool]`…`) to a single bracket, silencing the genuine tag/prose ERROR that test requires. Both that fixture and the c3f5-compliant shape are structurally identical (genuine tag first, a different tag later in backticks) — only their PROSE semantics differ ("actually re-laned to" vs "quotes … as the rejected verdict"), which a bracket-counting grammar can't distinguish. Per the reviewer's explicit escape hatch, left case-c's existing (non-backtick-aware) counting untouched rather than weaken/break the tagprose test; the c3f5 shape still trips case-c's OLD "conflict" message as a known, pre-existing false-positive (harmless — a different message string, doesn't collide with the new tag-first diagnostic, and outside this test's assertions). Flagging for a follow-up id if the false-positive itself needs resolving later (likely needs a semantic cue beyond bracket-counting, or folds into the id:7df1/d259-C structural-reorder migration that deletes this anchoring reimplementation entirely).
- [x] [ROUTINE] `git-lock-push.sh` — id:aa93 dirty-guard: tolerate untracked-only churn + drop the "concurrent edit" causal guess <!-- id:dff8 --> done 2026-07-02 (executor): legacy/manifest pull-path refusal now classifies porcelain — untracked-only (`?? ` only) proceeds with the autostash-rebase, any tracked entry still refuses; refusal message states facts ("uncommitted tracked changes"), no more "(a concurrent edit?)" guess; `tests/test_git_lock_push_dirty_guard.sh` 1/1 green
  - **Why** (TODO id:dff8, recurring on `~/.claude`, user-confirmed 2026-06-30): the guard (`git-diary-workflow/git-lock-push.sh:128`) refuses the `pull --rebase --autostash` path on ANY `git status --porcelain` output. `~/.claude` is perpetually dirty with harness runtime churn — untracked `plans/`, `session-env/`, `sessions/`, `tasks/` — so every push needs the manual fallback, and the warning asserts an unverified cause ("a concurrent edit?"), actively misleading the operator. `--autostash` only stashes TRACKED changes; untracked paths carry no stash-reapply data-loss risk (a rebase that would overwrite an untracked file aborts loudly on its own, which is safe-and-loud).
  - **Acceptance**:
    1. Before refusing, classify the porcelain: **untracked-only** (every line `?? `) → PROCEED with the autostash-rebase (both legacy and manifest mode); ANY tracked modification/staged/renamed entry → keep refusing (the id:aa93 data-loss guard is untouched for tracked dirt).
    2. Reword the refusal per TODO option (c): state facts only — e.g. "working tree has uncommitted tracked changes; not autostash-rebasing (id:aa93)" — no "(a concurrent edit?)" causal guess.
    3. Out of scope: the TRACKED runtime churn half (`.last-cleanup`, `history.jsonl` are tracked in the `~/.claude` worktree and will still refuse) — that is claude-diary's gitignore decision (TODO id:dff8 option (a)). REVIEW_ME box records this judgment split.
  - **Tests**: `tests/test_git_lock_push_dirty_guard.sh` (`# roadmap:dff8`) — hermetic bare-remote + clone fixtures (idiom: `test_git_lock_push_ff_only.sh`): (a) legacy-mode push with residual untracked-only churn proceeds (new commit reaches the remote); (b) tracked modified file still refuses (exit 0, commit stays local-only, remote unchanged); (c) the refusal warning no longer contains "concurrent edit". RED until the fix lands.
- [x] [ROUTINE] STOP-sentinel check/countdown/consume → one deterministic script call + timestamped consume log (id:482d) <!-- id:482d --> done 2026-07-02 (executor): `relay/scripts/stop-sentinel.sh check --path <file>` implements the check/countdown/consume semantics atomically (absent→false; positive-int countdown→decrement; else→consume+timestamped log line); prelude step 8 delegates to it verbatim; registered in Makefile relay_FILES/EXEC/ALLOW; `tests/test_stop_sentinel_consume.sh` 8/8 green
  - **Why** (TODO id:482d, observed 2026-07-01 ~23:27): a fired user-stop left `~/.config/relay/STOP` present minutes AFTER the workflow returned (gone unaided by 23:41) — consumption happened but DELAYED. The check/countdown/consume logic lives as prose instruction 8 of the discover-prelude prompt (`relay-loop.js:732`), so the `rm` lands at whatever point the agent reaches it; the hazard window is a next pool launched during the lag being false-stopped. Mechanize-first: collapsing the whole step into ONE atomic script call structurally dissolves the timing-variance class, and the timestamped consume log is the observe-instrumentation the item's OBSERVE downgrade asked for (both halves in one bounded change).
  - **Acceptance**:
    1. New `relay/scripts/stop-sentinel.sh check [--path <file>]` implementing prelude step 8 semantics VERBATIM: file absent → `{"stopRequested":false}`; trimmed content a positive integer N≥1 → write N-1 back, `{"stopRequested":false}`; anything else (empty / non-numeric / "0" / negative) → `rm -f` the file and `{"stopRequested":true}`. On consume, append ONE ISO-timestamped line to a log (env-overridable path, default `~/.claude/logs/relay-stop-sentinel.log`) so any future delayed-consumption report has a real timeline. Registered in Makefile relay_FILES/EXEC/ALLOW.
    2. `relay-loop.js` prelude step 8 rewritten to run the script and return its JSON verbatim (still the only actor, once per round; countdown write-back semantics unchanged). ENGINE-EDIT CAUTION: prompt-string change only — `node --check` + `lint-workflow-templates.mjs` + the existing structure tests must pass (the a0b6 template-literal-lint hazard class); do this edit early-session, not tail-of-session.
  - **Tests**: `tests/test_stop_sentinel_consume.sh` (`# roadmap:482d`) — hermetic tmpdir: absent / countdown-decrement (3→2, file kept) / plain-stop consume (file GONE + log line ISO-timestamped) / stale-"0" consume; plus a structure assertion that the prelude step 8 text references `stop-sentinel.sh` (sibling of `test_relay_loop_structure.sh`). RED until landed.
- [x] [ROUTINE] lane-anchor the remaining two parsers: `gather-repo-state.sh` `open_hard_pool` + `unpromoted-scan.sh` `primary_lane` (id:fb7f) <!-- id:fb7f --> done 2026-07-02 (executor): `gather-repo-state.sh`'s `open_hard_pool` now anchors on `roadmap_primary_lane` (leftmost-tag-after-backtick-strip, mirroring classify-repo.sh:85 + gather-human-backlog.sh's id:1bbd backtick-strip) and excludes 🚧/BLOCKED-on pool items (mirrors classify-repo.sh:98); `unpromoted-scan.sh`'s `primary_lane` now requires a bold-titled TODO item's tag to sit immediately after the title's closing `**` — a bold item with no title-adjacent tag returns no lane (surface) even if its prose bare/backtick-quotes a lane tag elsewhere. `tests/test_gather_pool_count_anchor.sh` 6/6 green; full suite 163/163 green.
  - **Why** (TODO id:fb7f; it-infra phantom `hard` 2026-06-30): `gather-repo-state.sh:341-355` counts `open_hard_pool` by whole-line substring — an open item whose PROSE quotes `[HARD — pool]` (re-lane criteria) counts as pool work → phantom `hard` verdict → doomed Opus dispatch each intensive/opus round. Sibling fixes already shipped for `gather-human-backlog.sh` (id:1bbd, backtick-strip) and `classify-repo.sh` (id:4da4, first-tag position); this closes the remaining two spots. **LIVE EVIDENCE from THIS handoff (2026-07-02)**: `unpromoted-scan.sh::primary_lane` (leftmost recognized tag, no position bound) mislabeled 4 of 9 `promote` items — 33c2/a505/7b23/b8ae carry NO genuine lane tag, so a prose `[ROUTINE]` became leftmost and set disposition=promote (backtick'd in three of them; BARE in b8ae's "open [ROUTINE] count" — so backtick-strip ALONE is insufficient here).
  - **Acceptance**:
    1. `open_hard_pool` counts an open `- [ ]` item ONLY when its PRIMARY lane (id:4da4 first-tag parse, mirroring `classify-repo.sh:85`) is `[HARD — pool]`; keep the recurring-audit exemption unchanged. Also mirror the conservative gate exclusion (`classify-repo.sh:98`): an open pool item carrying `🚧` or `BLOCKED on` does not count (under-dispatch-safe; unblocks promoting dep-gated pool items without doomed dispatches).
    2. `unpromoted-scan.sh::primary_lane` must yield NO lane (→ disposition `surface`) for an item whose only lane-tag occurrences are prose — including a BARE un-backtick'd mention deep in the body. Candidate mechanism: the tag must sit immediately after the item's bold-title close (`**` + optional whitespace), with first-tag as the fallback for non-bold items — but the FIXTURES below are the contract; the mechanism is the executor's choice (REVIEW_ME box records the judgment).
    3. `classify-repo.sh` consumes the scan TSV downstream — verify `unpromoted.promote/surface` counts shift accordingly (no code change expected there). Cross-ref id:cb9b (label-SEMANTICS contract): this item fixes lane PARSE; cb9b pins label MEANING.
  - **Tests**: `tests/test_gather_pool_count_anchor.sh` (`# roadmap:fb7f`) — hermetic fixtures: (a) ROADMAP whose only `[HARD — pool]` occurrences are inside a hands/meeting item's prose → `open_hard_pool==0`; (b) genuine pool item → 1; (c) `🚧 GATED` pool item → 0; (d) TODO item with backtick'd prose `[ROUTINE]` and no genuine tag → `surface`; (e) TODO item with a BARE prose `[ROUTINE]` mid-body and no genuine tag → `surface`; (f) genuinely tagged `- [ ] **title** [ROUTINE] …` → `promote`. RED until landed.
- [x] [HARD — pool] `/relay next` routes 1/2a — "effectively-drained" predicate aligned with the shipped classifier semantics (id:9014) <!-- id:9014 --> done 2026-07-02 (handoff C5): SKILL.md route 1 now keys on executor-ACTIONABLE `[ROUTINE]` (the `actionable_routine_open` predicate, classify-repo.sh cited as the single source); route 2a fires on "no executor-actionable open item" incl. the @manual/human-lane-only effectively-drained case; anti-guess wording retained; drift-guard tests/test_next_actionable_predicate.sh 4/4 green (behavior itself already locked by test_classify_verdict_humanlane.sh — loop half had shipped via id:4da4/5eb3, verified in-source this handoff)
  - **Why** (TODO id:9014, user 2026-06-30 "something's fishy… was there no work left in truncocraft?"): a ROADMAP whose only open items are `@manual`/human-lane is not ZERO-open, so `/relay next` route 2a never fires the unpromoted-scan/handoff path — truncocraft's 35-item TODO backlog read as "needs human / idle". The LOOP half is ALREADY SHIPPED + test-locked (verified this handoff 2026-07-02): `classify-repo.sh:89-105` derives `actionable_routine_open`/`roadmap_actionable_open` with `@manual`/human-lane/blocked exclusions, and `classify-verdict.sh:91,112-123` gates execute on the actionable count and fires `handoff` on promote>0 regardless of open human-lane boxes (`tests/test_classify_verdict_humanlane.sh` green). Remaining: the `/relay next` doc predicate (`relay/SKILL.md:378-395`) still keys route 1 on bare "Open `[ROUTINE]` items" and route 2a on "no open `- [ ]` items".
  - **Acceptance**:
    1. SKILL.md route 1 keys on executor-ACTIONABLE open `[ROUTINE]` items (primary-lane, not `@manual`/human-gated, not `🚧`/`BLOCKED on`) — the `actionable_routine_open` semantics.
    2. Route 2a's trigger becomes "no executor-actionable open item" (zero open boxes OR only `@manual`/human-lane/blocked boxes remain = effectively drained) → run unpromoted-scan and route per its findings; keep the anti-guess wording (never auto-promote an untagged item with a guessed lane).
    3. Align-by-reference: NAME `classify-repo.sh` / `actionable_routine_open` as the predicate authority instead of re-defining it in prose (single-source, cf. id:415b).
    4. Drift-guard test asserting the route-1/2a text carries the actionable-predicate markers (weak wording test — acceptable as a drift guard; the behavior itself is locked by `test_classify_verdict_humanlane.sh`).
  - **Tests**: `tests/test_next_actionable_predicate.sh` (`# roadmap:9014`).
- [x] [HARD — pool] Front-door first-class single-repo scope — `/relay <repo|.>` short-circuits discovery (routed:bc24) <!-- id:7633 --> done 2026-07-06 (HARD-pool): `/relay <repo>` / `/relay .` / `--only <repo>` → `args.onlyRepo`; relay-loop.js resolves it against the canonical relay.toml own set (honoring `# path:`, via pool-args.mjs::resolveScopeRepo) and narrows the exclude-filter + sig-cache + discover fan-out to that ONE repo — the 40-repo universe classification is bypassed while `discover-repo.sh`'s per-repo path is REUSED (never forked). Unconfirmed name = LOUD reject (surfaced, no dispatch, no ~/src guess). `--exclude` still validates against the FULL canonical set (acceptance #3 verified). ACCEPTANCE #4: bare `.` does NOT route to `/relay next` semantics — kept distinct (`.` = autonomous single-repo pool; `next` = interactive human-or-not router). tests/test_relay_single_repo_scope.sh 10/10 + node --check + template-lint + test_relay_loop_structure.sh + full `make test` green.
  - **Why** (TODO id:7633, inbound from truncocraft/loderite, observed 2026-06-29): a single-repo invocation (`/relay --afk . --quota-7d 90`) still enumerates + fully classifies the entire own-repo universe (40+ repos incl. `# path:` plugins), computing gating reasons that are all discarded to dispatch ONE repo; the workaround (hand-built 24-name `excludeRepos`) was incomplete because it missed `# path:`-relocated repos. Slow, overkill, and error-prone scoping.
  - **Acceptance**:
    1. A first-class single-repo scope (bare repo positional / `.` for cwd / `--only <repo>`): discovery classifies ONLY that repo — skip the own-repo enumeration + discover fan-out, but still run the SAME per-repo path (`discover-repo.sh` reconcile→classify→route; reuse, never fork the logic).
    2. The repo resolves against `relay.toml` (THE canonical own-repo set, honoring `# path:` — never a `~/src` glob); a repo not confirmed there is a LOUD reject, not a guess ([[feedback-use-existing-tools-not-improvise]]).
    3. `--exclude` filters the SAME canonical list BEFORE any classification work (verify, add a check if absent).
    4. `relay/SKILL.md` front-door documents the scope arg; decide in-item whether a bare `.` with open actionable `[ROUTINE]` work should route to `/relay next` semantics — record the decision in the done note.
    5. ENGINE-EDIT CAUTION: `pool-args.mjs` + `relay-loop.js` — `node --check` + `lint-workflow-templates.mjs` + structure tests green.
  - **Tests**: args-parse cases in the `pool-args.mjs` test surface + a structure test that the single-repo path bypasses the universe enumeration (same idiom as `test_relay_loop_structure.sh`). RED or structure-asserted per feasibility.
- [x] [ROUTINE] `classify-repo.sh` — gate the `standin` flag on `fable_rechecked` (perpetual Fable-recheck re-dispatch) (routed:f3d0) <!-- id:a42e --> done 2026-07-02 (executor): `standin` now requires `not fable_rechecked` — a checkpoint annotation that merely mentions "fable-standin" no longer re-elevates once the id:e030 watermark shows the recheck was already consumed; `tests/test_classify_repo_standin_gate.sh` 2/2 green
  - **Why** (inbound from the zkm relay review 2026-07-02; verified in-source this handoff): `classify-repo.sh` derives `standin = "fable-standin" in ckpt_msg` — a naive substring — so a GENUINE Fable recheck tag whose annotation merely MENTIONS the standin review it audited (zkm `relay-ckpt-20260701-2315`) re-triggers `standin`; `relay-loop.js` then ORs `u.standin || u.strongRecheckPending`, so an already-rechecked repo (`fable_rechecked` set ⇒ `strongRecheckPending=false`) re-elevates idle→review on EVERY Fable pool round. Observed: redundant zkm dispatch in run relay-20260701-234115 (empty window; the recheck was already consumed 2026-07-01).
  - **Acceptance**:
    1. The `standin` derivation becomes `("fable-standin" in ckpt_msg) and not fable_rechecked` — the durable id:e030 watermark is the gate. A genuinely NEW standin checkpoint still elevates, because writing `last_strong_ckpt` resets `fable_rechecked = false` (id:e030 shape); an already-consumed recheck never re-fires.
    2. No change to `strongRecheckPending` (already watermark-gated) or to the elevation OR itself.
  - **Tests**: `tests/test_classify_repo_standin_gate.sh` (`# roadmap:a42e`) — hermetic: (i) latest relay-ckpt annotation mentions `fable-standin` ∧ toml block has `fable_rechecked` set → `--emit unit` `standin==false`; (ii) same tag, `fable_rechecked` absent → `standin==true` (regression guard). RED until landed.
- [x] [ROUTINE] `relay-loop.js` — Fable-produced strong HANDOFF must not queue a bogus self-recheck; recheck reason must not hardcode "Opus stood in" (id:6856) <!-- id:6856 --> done 2026-07-02 (executor): `isFableRecheck` now drops the `verdict === 'review'` conjunct (any strong unit produced on a real-Fable session marks `fable_rechecked` with a dated watermark instead of `false`); elevation reason no longer hardcodes "Opus stood in for Fable" (neutral "strong checkpoint pending independent Fable audit" wording); `tests/test_fable_recheck_write_side.sh` 4/4 green, `node --check` + `lint-workflow-templates.mjs` + `test_fable_standin_marker.sh`/`test_relay_loop_structure.sh` all green
  - **Why** (found by the 2026-07-02 Fable recheck of relay-ckpt-20260702-0119 — which was itself the bogus dispatch): the integrator prompt gates the id:e030 consume side on `isFableRecheck = SESSION_IS_FABLE && unit.verdict === 'review'` (`relay-loop.js:1393`), so a strong checkpoint produced by REAL Fable via a **handoff** (or hard) unit falls to the else branch and records `fable_rechecked = false` — queuing a Fable-rechecks-Fable review the next pool round (this run: empty diff window, `strong_model = "claude-fable-5"`). The elevation reason (`relay-loop.js:~1046`) also hardcodes "Opus stood in for Fable" regardless of the recorded `strong_model`, so the dispatch reason was factually wrong (the [[feedback-ping-threshold-anomalies]] misconfiguration-smell class). Write-side sibling of id:a42e (read-side standin gate) — same perpetual/wasted-re-dispatch family, third mechanism (a42e substring, 25aa tag anchor, 6856 verdict conjunct).
  - **Acceptance**:
    1. `isFableRecheck` is true for ANY strong unit when the session's strong tier is real Fable (drop the `verdict === 'review'` conjunct) — a self-produced strong checkpoint has nothing pending, so it records a dated `fable_rechecked`, never `false`. The non-Fable (Opus-standin) branch keeps recording `false` (queue side unchanged).
    2. The strongRecheckPending elevation reason stops hardcoding "Opus stood in for Fable" — derive the wording from the recorded `strong_model` (or neutral "strong checkpoint pending independent Fable audit" phrasing). No behavior change to the elevation predicate itself (that is a42e/read-side territory).
    3. ENGINE-EDIT CAUTION: prompt-string edits — `node --check` + `lint-workflow-templates.mjs` + existing structure tests (`test_fable_standin_marker.sh`, `test_relay_loop_structure.sh`) stay green.
  - **Tests**: `tests/test_fable_recheck_write_side.sh` (`# roadmap:6856`) — static-grep structure spec (house idiom): (1) no `verdict === 'review'` conjunct on `isFableRecheck`; (2) no hardcoded "Opus stood in for Fable" literal; (3)+(4) regression guards: dated-watermark consume instruction + `fable_rechecked = false` queue instruction both survive. RED until landed (2 red / 2 green at promotion).
- [x] [ROUTINE] `classify-repo.sh` — `strongRecheckPending` must be model-aware: a Fable-produced strong checkpoint never queues a Fable-rechecks-Fable review (routed:1c2b) <!-- id:5884 --> done 2026-07-06 (executor): strong_model fable-substring gate added, tests/test_classify_repo_fable_model_gate.sh 3/3 PASS
  - **Why** (inbound from the chidiai relay review 2026-07-02, promoted by the 2026-07-02 review): `strong_recheck_pending = last_strong_ckpt set ∧ ¬fable_rechecked` (`classify-repo.sh:160`) is model-BLIND — a relay.toml entry whose `strong_model` is ALREADY a Fable model (e.g. chidiai `relay-ckpt-20260702-0048`, `strong_model = "claude-fable-5"`, `fable_rechecked = false`) elevates a same-tier second-opinion recheck (low value, wasted strong dispatch). The write-side fix (id:6856, shipped 2026-07-02) stops NEW Fable strong checkpoints from recording `false`, but pre-existing entries (and any written by non-pool paths, cf. id:0a3b) still carry the bogus-pending shape — the read side needs its own gate. Fourth mechanism in the perpetual/wasted-re-dispatch family (a42e substring, 25aa tag anchor, 6856 verdict conjunct, 5884 model-blind read).
  - **Acceptance**:
    1. `strong_recheck_pending` additionally requires the recorded `strong_model` NOT be a Fable model (case-insensitive `fable` substring on the parsed `strong_model` value): `last_strong_ckpt` set ∧ ¬`fable_rechecked` ∧ ¬fable-model → pending. A Fable-authored entry with a stale `fable_rechecked = false` is treated as ALREADY satisfied (nothing pending).
    2. Conservative default preserved: `strong_model` ABSENT/empty (legacy entry) keeps today's behavior (pending → optional recheck; the elevation is non-gating and cheap, so unknown-model errs toward the recheck).
    3. No change to the `standin` derivation (id:a42e territory) or to relay-loop.js's elevation OR.
  - **Tests**: `tests/test_classify_repo_fable_model_gate.sh` (`# roadmap:5884`) — hermetic (idiom: `test_classify_repo_standin_gate.sh`): (i) toml block `strong_model = "claude-fable-5"` + `fable_rechecked = false` → `--emit unit` `strongRecheckPending==false`; (ii) `strong_model = "claude-opus-4-8"` + `fable_rechecked = false` → `true` (regression guard); (iii) `strong_model` absent + `fable_rechecked = false` → `true` (legacy conservative default). RED until landed.
- [x] [ROUTINE] `relay-state-write.sh` `toml-set` must emit VALID TOML for a bare string value (smart-quote) — a hyphenated `status = handed-off` currently produces invalid TOML that breaks the pool's relay.toml read (routed:dc81) <!-- id:abbd -->
  - **Why** (TODO id:abbd, routed:dc81 from loderite /relay handoff 2026-07-04): `toml-set <repo> <key> <value>` writes the value VERBATIM (`relay-state-write.sh` awk `print key " = " val`), so `toml-set demo status handed-off` produced `status = handed-off` — an invalid TOML bareword (the hyphen) that broke the pool's relay.toml read; the handoff had to be re-run with explicit quotes. Deterministic: any bare hyphenated/special string value from any caller misfires the same way. The existing "caller supplies quotes" contract is error-prone (proven by the loderite incident); smart-quoting fixes the class.
  - **Acceptance**: `toml-set` smart-quotes the value in bash BEFORE the awk write, idempotently: value already wrapped in `"..."` → verbatim; `true`/`false` → verbatim (bare bool); `^-?[0-9]+(\.[0-9]+)?$` → verbatim (bare number); otherwise wrap in double quotes (bare string, incl. hyphenated — this makes dates strings, matching the `confirmed = "YYYY-MM-DD"` schema). Backward-compatible: every existing caller (pre-quoted strings, bare bools/ints) is unaffected. Update the script header's "value written VERBATIM — caller supplies quotes" note to the smart-quote contract. Do NOT touch `status-write` / `event-append`.
  - **Tests**: `tests/test_relay_state_write_toml_quote.sh` (`# roadmap:abbd`) — hermetic (`FABLES_CONFIG`=mktemp, log=/dev/null), validates real TOML via python `tomllib`: (a) `status handed-off` → `status = "handed-off"` + file parses; (b) a pre-quoted value is NOT double-quoted; (c) a bare bool stays a bool; (d) a bare int stays an int. RED until landed.
- [x] [HARD — pool] Integrator `-c` anchor: tag the MERGED tip when a review/recheck branch carries commits (routed:37f0; second occurrence routed:20b2 = TODO id:962d) <!-- id:25aa --> done 2026-07-06 (HARD-pool): integrate() step 2/3 prompt now decides `-c` by case — zero-commit → `-c <reviewedTip>` (id:8e3e, unchanged); branch WITH commits → NO `-c` so the tag lands on the POST-MERGE tip containing the run's own merged commits (was silently generalizing the id:8e3e "never tag main HEAD" rule → merged commits stranded outside the audited window → perpetual "substantive unaudited commits" re-dispatch). tests/test_integrate_ckpt_merged_tip.sh (structure + hermetic behavioral fixture) PASS; node --check + template-lint + test_relay_loop_structure.sh green. Folds TODO id:962d (llm-from-scratch signature covered). Optional ckpt-tag.sh defensive assert SKIPPED (would add a new CLI param for no marginal safety over the computation fix — no gold-plating).
  - **Why** (inbound from the zkm-photo relay review 2026-07-02): the 2026-07-01 23:55 zkm-photo Fable-recheck checkpoint was anchored on the child's BASE commit although the branch had a merged commit (REVIEW_ME prune) plus its own RELAY_LOG commit — so the run's OWN commits sit permanently outside the audited window and classify-repo re-dispatches a "substantive unaudited commits" review forever (self-heals only when a later ckpt tags past the residue). Sibling of routed:f3d0/id:a42e (different mechanism, same perpetual-re-dispatch symptom); the carries-commits COMPLEMENT of shipped id:8e3e (zero-commit branch → tag the reviewed tip). **Second independent occurrence** (llm-from-scratch review 2026-07-02, routed:20b2/TODO id:962d): `relay-ckpt-20260702-0038` annotated with the Fable-recheck summary but pointing at the PREVIOUS checkpoint commit `64aa14d` instead of its own `27c53d7` — same fail-safe over-inclusion (next window double-audits already-checkpointed commits).
  - **Acceptance**: the integrate() `-c` computation in `relay-loop.js` picks: zero-commit branch → the reviewed tip (id:8e3e rule, unchanged); branch WITH commits → the POST-MERGE tip on main (the audited boundary must include the run's own merged commits). ENGINE-EDIT CAUTION (template-literal-lint hazard): `node --check` + `lint-workflow-templates.mjs` + structure tests green. OPTIONAL defensive half (from id:962d — executor's judgment on cost): a `ckpt-tag.sh` assert that when `-c` is given alongside a known integrated-branch tip, the tag target CONTAINS that tip (loud reject otherwise); and/or note a candidate relay-doctor invariant (latest ckpt tag anchored strictly behind commits its own annotation claims to audit) for the id:4da4 detector family — do NOT gold-plate, the `-c` computation fix is the deliverable. **Closing this item: also tick TODO id:962d** (folded second occurrence) and verify the fix against the llm-from-scratch signature.
  - **Tests**: structure test naming the merged-tip rule (idiom: `test_ckpt_tag_commit_target.sh`); hermetic behavioral fixture if feasible (branch with commits → tag lands on the post-merge tip, not the base).
- [x] [ROUTINE] `scan-routed.sh --apply` — INBOUND stubs must land in an ACTIVE TODO section, never under `## Done` (found by the 2026-07-02 review) <!-- id:14d0 --> done 2026-07-06 (executor): md-merge.py update-ids anchors new (not-found) ids before the first archive-class heading (Done/Archive/Icebox); tests/test_scan_routed_stub_placement.sh 3/3 PASS
  - **Why** (TODO id:14d0): the stub write path (`scan-routed.sh:280` → `md-merge.py update-ids`) appends new lines at EOF; this repo's `TODO.md` ends with the `## Done` section, so BOTH 2026-07-02 ingests (routed:1c2b → id:5884, routed:20b2 → id:962d) were misfiled as open `- [ ]` items under `## Done` — open work hidden in a done section (wrong for archive semantics, section-aware scanners, and human reading). Deterministic and recurring: every future `--apply` against a Done-terminated TODO misfiles the same way. The 2026-07-02 review relocated the two lines by hand; this item fixes the tool.
  - **Acceptance**:
    1. A newly-written INBOUND stub lands BEFORE the first `## Done` / archive-class heading (Done/Archive/Icebox), or in a dedicated inbound/active section — EOF append remains ONLY the fallback when no such heading exists. Mechanism is the executor's choice (an insertion anchor in `md-merge.py update-ids` for new ids, or scan-routed pre-computing an anchor line) — keep the flock'd atomic write path, never a raw append.
    2. Idempotency + existing behavior preserved: `test_scan_routed_apply.sh` and `test_md_merge*`/existing md-merge specs stay green; updating an EXISTING id keeps its line position (only NEW-id insertion moves).
  - **Tests**: `tests/test_scan_routed_stub_placement.sh` (`# roadmap:14d0`) — hermetic (idiom: `test_scan_routed_apply.sh`): target repo TODO.md ends with a `## Done` section → after `--apply`, the stub line appears BEFORE the `## Done` heading (and not after it); a TODO with no Done heading still gets the stub (EOF fallback). RED until landed.
- [x] [HARD — pool] `review.md` step 3 — run-or-record-skip MANDATORY for every declared test tier (routed:49a0) <!-- id:f032 -->
  - **Why** (inbound from the isochrone Fable recheck 2026-07-02): isochrone's e2e tier was RED for 13 days (2026-06-17..30) across 5 reviews logging "suites green" — the worktrees lacked node_modules, playwright was silently absent, and the reviews ran only the unit tiers while claiming green for the suite. A green claim derived from a subset of tiers is the same class as C3's "a skipped or uncompiled test is NOT a pass".
  - **Acceptance**: `review.md` step 3 requires the reviewer to (a) ENUMERATE the repo's declared test tiers (package.json scripts / Makefile targets / CI config); (b) run each, or RECORD-THE-SKIP with the reason in RELAY_LOG + the returned summary; (c) NAME the tiers actually run in any green claim — "suites green" from a subset is banned wording. Keep it aligned with handoff C3's `unverified` doctrine (same file family, cite it).
  - **Tests**: a wording drift-guard over `review.md` step 3 (enumerate/record-skip/name-tiers markers) — weak but cheap; the behavioral enforcement is the Opus reviewer following its contract.
- [x] [ROUTINE] `reconcile-repo.sh` — bounded side-effecting git reconciliation, split out of the LLM shard (flip step b, id:a0b6; meeting 2026-07-01-1904) <!-- id:5987 --> done 2026-07-01 (executor): implemented + registered in Makefile, tests/test_reconcile_repo.sh 7/7 PASS
  - **Why** (meeting `docs/meeting-notes/2026-07-01-1904-a0b6-step-b-engine-swap.md`, A1): the flip swaps the LLM discovery shard for the side-effect-free `classify-verdict`, but the shard ALSO does side-effecting git the classifier can never hold. `relay-loop.js` is a Workflow script (no subprocess) so this must be a script an agent runs. The dangerous op (orphan reap-vs-park `merge-base --is-ancestor` → force `worktree remove`) is exactly what needs a hermetic RED test — testability, not reuse, justifies the split.
  - **Acceptance**:
    1. `relay/scripts/reconcile-repo.sh --repo <name> --path <abs>` performs ONLY the bounded side-effecting git ops transcribed from `relay-loop.js:854-870`: behind-origin `merge --ff-only` (then leave state for a fresh gather), DIVERGED → no-op surface (never commit), stale-worktree reap (`worktree remove --force` + `branch -D`) when HEAD is an ancestor of main, orphan-park (`branch -m … relay/orphan/*` + `worktree remove --force`) when it carries unmerged commits, and the id:bae5 in-place `uv.lock` commit when `dirty_lock_only`. No verdict/classification logic (that stays `classify-repo.sh`). Registered in Makefile relay_FILES/EXEC/ALLOW.
    2. Emits a small JSON summary of what it reconciled (for the runner to fold into `surfaced`); deterministic reap-vs-park decision; no `find`/broad-tree hunting (id:612f).
    3. Runner contract: an agent runs `reconcile-repo.sh` THEN `classify-repo.sh` per repo — the two stay separate so `classify-repo.sh` remains hermetically testable in isolation.
  - **Tests**: `tests/test_reconcile_repo.sh` (`# roadmap:5987`) — hermetic mktemp git fixtures seeded from the REAL id:689c/3ac8/1f53/c3f7/bae5 states (behind-only ff, diverged block, stale-reap, orphan-park, uv.lock-only dirty). RED until it lands.
- [x] [ROUTINE] full-unit assembler — `classify-repo.sh --emit unit` (flip step b sub-component, id:a0b6; discovered 2026-07-01) done 2026-07-01 (executor): --emit unit merges gather passthrough + toml/ckpt-msg derivations + classify-verdict output into full DISCOVER_SCHEMA unit; default mode byte-unchanged <!-- id:3d61 -->
  - **Why**: the mechanical runner (a0b6) needs a COMPLETE `DISCOVER_SCHEMA` unit per repo (`relay-loop.js:351-435`: path/repo/verdict/reason + lastCkpt/income/hasRoutine/openHard/standin/is_finished/top_intensive/substantive_unaudited/work_sig/open_hard_pool/strongRecheckPending/intensive). The LLM shard assembled those from the gather JSON + relay.toml; `classify-repo.sh` today emits ONLY classify-verdict's `{verdict,reason,evidence,ambiguous}`. Without a deterministic assembler the runner would have to improvise the field mapping (the exact non-determinism the flip removes). Surfaced while mapping the a0b6 contract 2026-07-01.
  - **Acceptance**:
    1. `classify-repo.sh --emit unit --repo <name> --path <abs>` emits ONE full-unit JSON with EVERY DISCOVER_SCHEMA unit field. WITHOUT `--emit unit` the output is UNCHANGED (`{verdict,reason,evidence,ambiguous}` — `test_classify_repo.sh` stays green).
    2. Deterministic derivations (from the old shard prose `relay-loop.js:876-887`): `income` ⟵ relay.toml block `income = true`; `standin` ⟵ gather `latest_ckpt_msg` contains `fable-standin`; `strongRecheckPending` ⟵ block `last_strong_ckpt` set ∧ `fable_rechecked` false/absent; `lastCkpt` ⟵ gather `latest_ckpt`; `openHard`/`open_hard_pool`/`is_finished`/`top_intensive`/`substantive_unaudited`/`work_sig` verbatim from gather; `verdict`/`reason`/`intensive` from classify-verdict. SIDE-EFFECT-FREE.
  - **Tests**: `tests/test_classify_repo_unit.sh` (`# roadmap:3d61`) — hermetic fixtures assert the full field set, the derivations, income/standin/strongRecheckPending defaults, verdict parity with default mode, and the unchanged-default regression guard. RED until `--emit unit` lands.
- [x] [ROUTINE] `discover-repo.sh` — per-repo composition (reconcile → classify → route) (flip step b sub-component, id:a0b6; 2026-07-01) <!-- id:64b4 --> done 2026-07-01 (executor): implemented, composes reconcile-repo.sh + classify-repo.sh --emit unit, all 5 routing scenarios green
  - **Why**: to keep the `relay-loop.js` edit thin (agent runs ONE script per repo, pure transport), the per-repo reconcile+classify+ROUTE logic is itself a deterministic, testable script. It composes `reconcile-repo.sh` (id:5987) + `classify-repo.sh --emit unit` (id:3d61) and emits `{units,surfaced,skipped}` for one repo. Doing the routing in a script (not the agent prompt) keeps the mechanized path fully tested.
  - **Acceptance**:
    1. `discover-repo.sh --repo <name> --path <abs> [--runid <id>] [--live-claims <csv>] [--main-branch <name>]` emits ONE JSON `{units:[≤1],surfaced:[],skipped:[]}`. ROUTING: run reconcile-repo.sh; **if it surfaced anything → return those surfaced, no classify, no unit** (reconcile surfaces EXACTLY the don't-work cases: diverged/parked/in-flight — never double-surface). Else run `classify-repo.sh --emit unit` and route by verdict: `blocked`→surfaced(no unit); `AMBIGUOUS`→surfaced with a LOUD reason(no unit — dormant hook, NO LLM prompt resurrected); `idle`→unit + skipped rollup; else→unit.
    2. Only reconcile's bounded git ops mutate; the routing + classify are read-only.
  - **Tests**: `tests/test_discover_repo.sh` (`# roadmap:64b4`) — hermetic fixtures for all 5 routing branches (execute / diverged-surface-once / idle+skipped / dirty-blocked / uv.lock-relock→execute). RED until `discover-repo.sh` lands.
- [x] [HARD — pool] a0b6 remainder — the confined `relay-loop.js` verdict-source swap (flip step b; meeting 2026-07-01-1904) <!-- id:a0b6 --> done 2026-07-01 (supervised): shardPrompt (74-line LLM classifier) DELETED, replaced by a mechanical runner calling discover-repo.sh per repo; node --check + template-lint clean; nested-uv.lock fidelity + id:1f53 suppress-redispatch reimplemented in reconcile-repo.sh (found via failing structure tests); 11 structure tests repointed to the new script homes; suite 151/0. The LLM discovery shard is GONE — discovery is now fully deterministic (reconcile+classify+route), LLM confined to the dormant AMBIGUOUS surface.
  - **GATED on id:5987 (done ✓) + id:3d61 (done ✓) + id:64b4 green** (the runner invokes `discover-repo.sh`, which composes reconcile + classify --emit unit). Careful supervised engine work — the engine crashed the pool 3× on the template-literal-lint hazard; NOT a tail-of-session edit.
  - **Why** (same meeting, A3): DP1 (2026-06-30-1523) ratified Replace — classifier primary, LLM shard fires only on AMBIGUOUS. Step (a) reached verdict parity (id:e424); this is the engine edit that makes `classify-verdict` the primary verdict source.
  - **Acceptance**:
    1. Replace the `shardPrompt` builder + the `agent(shardPrompt(chunk), …)` call (`relay-loop.js:820-900`) with a runner-agent prompt: for EACH repo in the chunk run `discover-repo.sh --repo <repo> --path <path> --runid <runId> --live-claims <csv> --main-branch main` and CONCATENATE each repo's `{units,surfaced,skipped}`; run NOTHING else (id:612f NO-FILESYSTEM-HUNTING guard verbatim). Return the SAME `SHARD_SCHEMA` shape. (LLM judgment is confined to the dormant `AMBIGUOUS` path, which `discover-repo.sh` surfaces loudly — classify-verdict never emits it today, so the big shard prompt is DELETED, not kept.)
    2. HARD swap — old `shardPrompt` DELETED (not commented). Edit confined to `:820-900`; the downstream merge/backstop code (`:906-1063`) and `SHARD_SCHEMA` UNCHANGED. The four JS-side backstops (id:000d/9973/ad74/365b) stay (A2). Rollback = `git revert` of this commit; NO runtime fallback flag.
    3. NESTED-uv.lock fidelity (folded in from 5987 review): before the flip, reconcile-repo.sh's LOCK guard must commit a nested `plugins/*/uv.lock` too (currently a literal root-`uv.lock` porcelain match) — key it on gather's nested-aware `dirty_lock_only`, or the zkm cascade stays dirty-but-dispatched. Add a nested-lock fixture to `test_reconcile_repo.sh`.
    4. `tests/test_workflow_template_lint.sh` extended for the new prompt + a new `tests/test_relay_runner_swap.sh` structure test (runner call feeds the same schema the merge code reads) both green; `make test` fully green with THIS box ticked; one `/relay --once` smoke run on the drained portfolio (0 crashes, byte-compatible discovery, verdicts match the historical backtest) as the acceptance gate.
  - **Out of scope**: b444 lane-triage broker, inotify (id:0ee6), continuous dispatch (id:80b8), unpromoted-scan promote/surface semantics, and deleting any backstop (id:b50e).
- [x] [HARD — decision gate] Delete the id:000d/9973/ad74 JS-side backstops once the LLM-RUNNER-transport-infidelity residual is proven constrained (flip follow-on; meeting 2026-07-01-1904) <!-- id:b50e --> — RESOLVED 2026-07-06 NO-GO (gate (c) failed with data; guards proven load-bearing). Forward path → id:c79e.
  - **REFRAMED 2026-07-03 (evidence-gate analysis): NO-GO, keep all three.** The original "AMBIGUOUS→LLM path" framing was imprecise: `classify-verdict.sh` can't emit AMBIGUOUS (hardcoded false) and the dormant `discover-repo.sh` hook is explicitly "NO LLM call" — so that literal path is unreachable, not merely constrained. What 000d/9973/ad74 ACTUALLY guard post-flip is an **unfaithful haiku discovery runner** (`relay-loop.js:862`, still an LLM relaying `discover-repo.sh` JSON) emitting a bogus execute/hard/handoff. That residual is NOT proven constrained: (1) **no fire-frequency data exists** — the guards only `log()` to sandbox stdout (id:854c files the instrumentation to fix this); (2) shadow-log shows RED>0 in 3/10 snapshots and is idle-dominated (drained portfolio barely exercises the acted-on states); (3) **open revert dispute id:3134** ("REVERT 0c9bcf9 NOW", still open) — deleting the classifier's safety nets while the classifier's correctness is under active challenge is backwards. The guards are ~30 cheap demote/promote-only lines. **GO criteria:** (a) id:854c instrumentation live, (b) id:3134 resolved (revert declined + 3 RED cases triaged non-defect, OR classifier hardened), (c) a window of NON-drained forward runs with 000d/9973/ad74 firing 0 times. DEP: id:854c, id:3134.
  - **RE-CHECK 2026-07-04 (b50e evidence gate, background agent): still NO-GO, but the gate has narrowed to (c) alone.** (a) MET-in-code: id:854c instrumentation landed (commit `9b355ad`, archived) — `emitBackstopFire()` (`relay-loop.js:66`) persists durable `kind:"backstop"` events to `~/.config/relay/relay-events.jsonl` via the existing `pushEvent` sink; all three fire sites wired (:926/:959/:993). (b) SUBSTANTIVELY MET: id:3134 resolved DECLINE-REVERT-AND-HARDEN, 3 RED cases triaged 0-defect, harden-forward id:e833 shipped (commit `a68454d`, archived) — only the 3134 checkbox tick is outstanding. (c) UNMET DECISIVELY: `grep '"kind":"backstop"' ~/.config/relay/relay-events.jsonl` → **0 events, because no relay round has run since the instrumentation landed** (last forward event 2026-07-02T17:02, 854c landed 2026-07-03T18:58). The 0 is zero-data, not an observed 0-fire window. **CLOSE (c):** run the pool forward across a window that reaches the acted-on states (execute / hard-pool / INTENSIVE), confirm each of 000d/9973/ad74 fires 0× while dispatch events are demonstrably non-idle; then flip GO. id:365b stays regardless.
  - **CLOSE 2026-07-06 (b50e decision resolved with data): NO-GO — keep all three guards.** Gate (c) tested on the first non-drained forward window after the 854c instrumentation landed: run `relay-20260704-173233-19787` (8 rounds / 416 agents / demonstrably non-idle — substantive execute+review+hard dispatches across ~20 repos). `grep '"kind":"backstop"' ~/.config/relay/relay-events.jsonl` → **000d ×9, ad74 ×3, 9973 ×0.** Gate (c) requires **0×** on a non-idle window → it **FAILS** for 000d + ad74, which are thereby proven **load-bearing** (not vestigial). 9973's 0-fire in this single window is NOT grounds to delete it alone (cheap guard for a rare condition; one window ≠ characterized). The b50e *decision* ("delete now?") is answered **NO** and this item ticks closed. The **forward path** (make the guards vestigial by porting their per-round logic into the mechanical classifier so they fire 0× natively → then deletion becomes safe) moves to **id:c79e**. Root cause of the fires: zelegator carries **0 open ROADMAP items** (finished; re-proposed each round, 000d re-parks it → handoff), and isochrone's freshly re-laned `[INTENSIVE — r5-jvm]` (id:11c3) isn't read natively so `classify-verdict.sh` emits plain `execute` and ad74 promotes it. `id:365b` (cross-round spin) stays in JS regardless.
  - 🚧 GATED — not dispatchable now. After the flip (id:a0b6), 000d finished-demote / 9973 hard-pool-demote / ad74 INTENSIVE-promote only guard the residual `AMBIGUOUS`→LLM surface. When that surface is proven constrained (or itself removed), the three become vestigial and should be deleted (constraint-archaeology). **id:365b circuit breaker STAYS** — it is cross-round loop state the per-repo classifier cannot implement. Do NOT start before a0b6 ships + the AMBIGUOUS path is characterized.
- [x] [HARD — pool] Port the 000d/ad74 per-round backstop logic into `classify-verdict.sh` so the guards fire 0× natively (re-opens id:b50e deletion) <!-- id:c79e --> — DONE 2026-07-07 (executor): both fixture conditions (finished-repo authority / INTENSIVE native promote) now caught deterministically in `classify-verdict.sh`; `tests/test_classify_verdict_backstop.sh` green; JS backstops kept unchanged per b50e's NO-GO. `make test` 188/188.
  - **Why** (b50e forward path, evidence 2026-07-06): the first non-drained forward window after the 854c instrumentation (run `relay-20260704-173233-19787`) shows 000d firing **9×** and ad74 **3×**, each on the *same repo every round* — 000d re-parks **zelegator** (0 open ROADMAP items → finished, yet re-proposed) to `handoff`; ad74 promotes **isochrone** (re-laned to `[INTENSIVE — r5-jvm]`, id:11c3) that `classify-verdict.sh` still verdicts plain `execute`. Both are **deterministic per-round tests the mechanical classifier could own**, currently patched by a JS backstop. Mechanize-first doctrine: fold that loud-failure resolution back into the mechanical layer so the guards become vestigial → then b50e's deletion is finally safe. This is the constructive inverse of b50e (which just closed NO-GO because the guards are load-bearing).
  - **How / spec**: (a) `classify-verdict.sh` emits an `idle`/`handoff` verdict for a confirmed repo with **0 open dispatchable items** (folds 000d's finished-repo test — a repo with nothing to execute should never reach the JS demote); (b) it reads the `[INTENSIVE — <res>]` primary lane tag and sets the intensive flag **natively** (folds ad74; relate id:5ac6 "INTENSIVE = flag+invariant+fail-closed assertion, NOT a verdict value", and slice-A id:e407/id:68dc). RED specs under `tests/` (`test_classify_finished_repo_idle.sh`, `test_classify_intensive_tag_native.sh` or equivalent). **Verify** via a forward window where 000d/ad74 fire **0×** on demonstrably non-idle dispatch, then b50e is re-openable. Do NOT touch id:365b (cross-round spin state — the per-repo classifier cannot hold it). Dispatch: `/relay handoff` (strong-model authors RED) → Sonnet executor.
  - **Relate**: id:b50e (this re-opens its deletion), id:365b, id:a0b6, id:5ac6, id:e407/id:68dc.

<!-- id:4da4 part-2 invalid-state detector — meeting 2026-07-01-2142-relay-state-machine-invalid-state-detector.md.
     Model (artifact×actor×transition matrix + invariants I1–I9) lives in that note. C5 ratified report-only:
     every check below surfaces LOUDLY but NEVER auto-blocks a round; honor relay-doctor's existing --strict
     (id:a883) as an explicit opt-in only. C1–C3 land in parallel (no cross-dep). -->
- [x] [ROUTINE] relay-doctor check 9 — main-checkout residue detector (I1/I7) (id:4da4 pt2; meeting 2026-07-01-2142) <!-- id:8018 --> done 2026-07-01 (opus): check 9 reuses clean-tree-gate.sh, counts non-lock uncommitted entries as residue, lock-only=benign; report-only + --strict; test_relay_doctor_residue.sh 4/4
  - **Why**: seed invalid-state (i) — a gate-detection/handback path can strand an uncommitted ledger edit on the main checkout (loderite id:3801 residue). `clean-tree-gate.sh` enforces clean-or-lock-only only AT integrate, per-repo; there is no standing sweep. Report-only detection is the regression guard.
  - **Acceptance**: a new `check_repo` check in `relay-doctor.sh` (matching checks 1/2/6/7) that reuses `clean-tree-gate.sh` (id:9bec no-reimplement rule) to classify each own repo's main checkout; a non-lock-only dirty tracked file counts into `repo_issues`/`issues_total`; prints "clean" or the findings; report-only (nonzero only under the existing `--strict`). NO new auto-block.
  - **Tests**: `tests/test_relay_doctor_residue.sh` (`# roadmap:8018`) — hermetic: own repo with a foreign-dirty tracked ledger edit → reported; lock-only dirty → clean; `--strict` exits nonzero on a residue. RED until landed.
- [x] [ROUTINE] relay-doctor check 10 — verdict-invariant replay detector (I2/I4) (id:4da4 pt2; meeting 2026-07-01-2142) <!-- id:188c --> done 2026-07-01 (opus): classify-repo.sh --emit unit now exposes actionable_routine_open; check 10 asserts I2 (execute⟹aro>0) + I4 (intensive⟹verdict∈{execute,hard}) with honest coverage note; RELAY_DOCTOR_CLASSIFY_REPO override for the stub; test_relay_doctor_verdict_invariant.sh 4/4
  - **Why**: seed invalid-state (ii) — `execute` on a repo with no executor-actionable work. Part-1 PREVENTS it at source (`classify-verdict.sh:91` gates on `actionable_routine_open`); this is the standing regression guard that prevention lacks. Self-replay cross-checks the derived count (`classify-repo.sh`) against the verdict (`classify-verdict.sh`) — different scripts, so it catches the part-1 gate-wiring bug class.
  - **Acceptance**: a new check that runs `classify-repo.sh --emit unit` (side-effect-free) per own repo and asserts `verdict==execute ⟹ actionable_routine_open>0` AND `intensive!="" ⟹ verdict∈{execute,hard}` (id:5ac6). A violation is a LOUD issue. Print an HONEST coverage note: this guards verdict↔derivation CONSISTENCY, not derivation CORRECTNESS (a bug shared by derivation+gate is out of reach — the `relay-events.jsonl` real-dispatched-verdict read is the noted future upgrade). Report-only; honor `--strict`.
  - **Tests**: `tests/test_relay_doctor_verdict_invariant.sh` (`# roadmap:188c`) — hermetic: `@manual`-only `[ROUTINE]` repo (verdict≠execute → clean); a synthetic unit with `intensive!=""` ∧ verdict=review → flagged; `execute` ∧ `actionable_routine_open==0` → flagged. RED until landed.
- [x] [ROUTINE] relay-doctor check 11 — last_ckpt tag existence detector (I8) (id:4da4 pt2; meeting 2026-07-01-2142) <!-- id:333c --> done 2026-07-01 (opus): check 11 rev-parse --verify's each own repo's relay.toml last_ckpt (empty=clean, dangling=flagged); coverage-gap block now names I5 (id:e149) + I9 (id:b444); test_relay_doctor_last_ckpt.sh 4/4
  - **Why**: the integrator writes each own repo's `last_ckpt` (`relay-loop.js:1426`); a failed push / aborted tag can desync it from the actual tag set. A dangling `last_ckpt` is an invalid state a `rev-parse --verify` catches deterministically.
  - **Acceptance**: a new check that, for each own repo, parses `last_ckpt` from its relay.toml block (reuse the doctor's tomllib reader) and runs `git -C <path> rev-parse --verify refs/tags/<tag>`; a missing tag counts as an issue. Empty/absent `last_ckpt` is NOT an issue (a not-yet-checkpointed repo). Report-only; honor `--strict`. Also add I5 (gated id:e149 heartbeat) + I9 (gated id:b444 decision-queue schema) to the doctor's coverage-gap "checks NOT yet wired" honesty block (no build) so the report never looks falsely green.
  - **Tests**: `tests/test_relay_doctor_last_ckpt.sh` (`# roadmap:333c`) — hermetic: toml `last_ckpt` naming a non-existent tag → flagged; naming a real tag → clean; empty `last_ckpt` → clean; assert the coverage-gap block names I5/I9. RED until landed.
- [x] [HARD — pool] atomic main-write fix for id:3801 handback follow-up (seed invalid-state i) (id:4da4 pt2; meeting 2026-07-01-2142) <!-- id:e5e9 --> done 2026-07-01 (opus): handback-followup.py now passes --commit to md-merge (id:148b atomic write+commit under one flock), then legacy-mode git-lock-push of the already-committed HEAD — the write→commit stranding window is gone; HANDBACK_GIT_LOCK_PUSH override; death-sim test_handback_atomic_commit.sh 3/3 (dying push → clean tree). reconcile-repo.sh out of scope
  - **Why**: `handback-followup.py:173` runs `md-merge.py update-ids` WRITE-ONLY (no `--commit`) then `:194` runs `git-lock-push.sh` as a SEPARATE step — a death between them strands `ROADMAP.md` dirty on the main checkout (the exact loderite id:3801 residue that motivated id:4da4). The structural fix is to make the write+commit ONE flock'd op.
  - **Acceptance**: route `handback-followup.py`'s ROADMAP write+commit through the id:148b atomic path — pass `--commit "<msg>"` to the existing `md-merge.py` call so write+commit happen under the one flock (the subsequent `git-lock-push` becomes push-only of an already-committed change), OR fold the write through `commit-ledger.sh`. NO functional change to what gets written; the ONLY change is closing the write→commit window. `reconcile-repo.sh:86` (un-serialized but commits, never strands) is OUT of scope (meeting D-C4-scope; observe-first). Cross-ref id:148b, id:2147.
  - **Tests**: extend `tests/` with a hermetic case (`# roadmap:e5e9`) that simulates a death BETWEEN the md-merge write and the push (e.g. run the write step, then assert the tree is NOT left with an uncommitted ROADMAP.md — the write must already be committed under the flock). RED until the atomic path lands.

<!-- 2026-07-01 fable catch-up review findings (relay-machinery, evidence in relay-events.jsonl + git timestamps; TODO.md carries the full narrative under the same ids — single-id-two-views) -->
- [x] [HARD — pool] Integrator: distinguish a ZERO-COMMIT review branch from a duplicate dispatch — checkpoint the reviewed tip, never handback (found 2026-07-01, run relay-20260701-202806-14640; done 2026-07-01: relay-loop.js "Already up to date" ⇒ ckpt-tag `-c <reviewed-tip>`, destructive cleanup scoped to own artifacts; tests test_ckpt_tag_commit_target.sh + suite 158 green) <!-- id:8e3e -->
  - **Why**: a review child with nothing to write (clean window, ledger no-op) returns a branch whose tip == its base; if main advanced meanwhile (interactive commits), `merge --no-ff` says "Already up to date" and the integrator hands back "Duplicate dispatch" with NO checkpoint — the audited window never closes, so the next discovery re-dispatches a strong review of the same commits (unbounded strong-tier waste in an unattended pool). Verified 2026-07-01 20:36: child based on the TRUE then-HEAD 33169ee, zero commits; main moved to 65ce4ea (20:34:53) before integration.
  - **Acceptance**:
    1. The integrate() prompt (relay-loop.js:1415-1430 area) branches on `tip == base of the review branch ∧ tip is ancestor of main`: this is a CLEAN EMPTY REVIEW → run ckpt-tag.sh at the BRANCH TIP (the audited boundary — NOT current main HEAD, whose newer commits the review never saw and must not be marked audited), update relay.toml per step 6, remove worktree + branch; only a branch already merged by an earlier integrator of the SAME run is "duplicate dispatch".
    2. Careful supervised engine work (template-literal-lint hazard, same class as a0b6); node --check + template-lint green.
  - **Tests**: a structure test asserting the integrate prompt names the zero-commit/ckpt-at-tip rule (same idiom as test_workflow_template_lint.sh); hermetic behavioral fixture if feasible (zero-commit branch + advanced main → tag lands on branch tip, no handback).
- [x] [ROUTINE] `ckpt-tag.sh`: sync `[repos.<name>]` `last_ckpt` (+ `last_strong_ckpt`/`strong_model` when strong) in relay.toml via `relay-state-write.sh toml-set` (found 2026-07-01: tags 1948/2019/2110 minted by supervised sessions while relay.toml stayed at 1635; done 2026-07-01: flock'd sync at the choke-point, spec test_ckpt_tag_toml.sh GREEN) <!-- id:0a3b -->
  - **Why**: only the pool integrator writes relay.toml (relay-loop.js:1426); supervised/manual checkpoints via ckpt-tag.sh leave `last_ckpt`/`last_strong_ckpt` stale. Discovery is NOT mis-driven (gather-repo-state.sh:156 reads `git tag -l` — tags are the source of truth) but the id:e030 Fable-recheck queue misses strong checkpoints made outside the pool and relay-doctor check 11 validates a stale value.
  - **Acceptance**:
    1. After a successful tag, `ckpt-tag.sh` sets `last_ckpt = "<tag>"` for `[repos.<name>]` through the flock'd `relay-state-write.sh toml-set` single-writer — IFF the repo has a `[repos.<name>]` block (silently skip unmanaged repos; never create a block). When the annotation label records a strong model (`claude-opus-*` / Fable), also set `last_strong_ckpt`/`strong_model` per the id:e030 shape (do NOT touch `fable_rechecked` — the integrator owns its consume-side).
    2. Honor the existing `FABLES_CONFIG` env override (relay-state-write.sh's hermetic-test path) so tests never touch `~/.config/relay`; a missing/unreadable relay.toml is a logged no-op, never a failure of the tagging itself.
  - **Tests**: `tests/test_ckpt_tag_toml.sh` (`# roadmap:0a3b`) — hermetic: managed-repo fixture → last_ckpt updated under flock; strong-label fixture → last_strong_ckpt+strong_model set; unmanaged repo → toml untouched; toml absent → tag still succeeds. RED until landed.
- [x] [HARD — pool] `classify-verdict.sh` case-b split → `human` + mechanical surface-filer (meeting 2026-06-30-2238) <!-- id:5eb3 -->
  - **Why** (meeting `docs/meeting-notes/2026-06-30-2238-classifier-flip-prereqs-intensive-casebt.md`): `classify-verdict.sh:100` fires `handoff` on `promote>0 OR surface>0`. id:47f1 already broke the case-g loop (surface items file to the decision-queue once, then drop out), so this is a COST-TIER fix, not a correctness fix: a `promote==0 ∧ surface>0` repo has nothing an Opus `handoff` can promote — its only action is mechanical `decision-queue.sh add` per surface item. Burning the apex turn on filing-only is the over-tier the mechanize-first heuristic dissolves.
  - **Acceptance**:
    1. `classify-verdict.sh` splits the old case-b three ways: `promote>0 → handoff`; `promote==0 ∧ surface>0 → human` (priority_rank 5); `promote==0 ∧ surface==0 → idle` (unchanged). The `human` verdict must NOT outrank execute/review/hard (D3 order intact).
    2. The surface→decision-queue filing RELOCATES out of the Opus handoff handler (`handoff.md` case-g) into a FORCED, LOGGED, idempotent mechanical step wired where the loop consumes the `human` verdict (new `relay/scripts/file-surface-decisions.sh <repo>` or fold into `unpromoted-scan.sh --apply`; reuse `decision-queue.sh add --source-id <token>` + the id:47f1 exclusion). Anti-gaming invariant preserved: surface backlog is LOUD-surfaced and N decision-queue records are ACTUALLY written (a silent no-op here is the exact relay-2026-06-30 anti-pattern — must NOT recur). Update `handoff.md` so the handoff handler no longer files (the loop does).
    3. **RECONCILE**: the existing `tests/test_classify_verdict.sh:41` case (b) (roadmap:85df, TICKED) asserts surface-only → `handoff`; flip it to `human`. Full suite green requires it.
  - **Tests**: `tests/test_classify_verdict_humanlane.sh` (`# roadmap:5eb3`) — verdict-level three-way split (RED until landed) + a new hermetic filer test asserting N decision-queue records are written for a surface-only repo (no silent no-op). Plus the flipped case (b) in `test_classify_verdict.sh`.
- [x] [HARD — pool] INTENSIVE verdict-layer fail-safe: `intensive` flag + invariant + fail-closed dispatch assertion (SAFETY; meeting 2026-06-30-2238) <!-- id:5ac6 -->
  - **Why** (same meeting; SAFETY): `classify-verdict.sh` reads no intensive field, so `[HARD — pool] [INTENSIVE]` classifies as plain `hard` and `[ROUTINE] [INTENSIVE]` as plain `execute` — indistinguishable. The ONLY dispatch guard is loop-level `relay-loop.js` `ALLOW_INTENSIVE`, a single point of failure: a regression spawns an executor/apex child on resource-heavy work → stall or the [[oom-local-model-session-kills]] OOM-crash (Gemma-26B killed all 6 sessions).
  - **Acceptance**:
    1. `classify-verdict.sh` copies gather's `top_intensive` VERBATIM to an `intensive:"<resource>"` field beside an UNCHANGED `verdict` (a FLAG, never a new verdict value — `[INTENSIVE]` is an orthogonal resource axis operative only on dispatchable lanes; human-gated exclusion is inherited free because `top_intensive` is "" for human-gated items, id:a707). The field is always present (string, "" when none).
    2. Invariant `intensive != "" ⇒ verdict ∈ {execute, hard}` holds across the state space (test-locked).
    3. Add a FAIL-CLOSED pre-dispatch assertion in `relay-loop.js`: never spawn an executor/apex child on a unit with `intensive` set unless `ALLOW_INTENSIVE` — skip + surface loudly, never OOM-dispatch (third defense-in-depth layer; keep the existing partition + `resource:` claim).
  - **Tests**: `tests/test_classify_verdict_intensive.sh` (`# roadmap:5ac6`) — flag presence + verbatim copy + the verdict-coupling invariant (RED until landed). Extend `tests/test_relay_loop_intensive_emit.sh` (or a sibling) for the JS-side fail-closed assertion.
- [x] [ROUTINE] roadmap-lint case (d): realign INTENSIVE to operative-only-on-dispatchable-lanes (meeting 2026-06-30-2238) <!-- id:9062 -->
  - **Why** (same meeting; resolves the LIVE it-infra id:9321 false-positive surfaced by a parallel `/relay human` session): `roadmap-lint.sh:80` (comment "orthogonal, may co-occur") contradicts `:170` case (d) ("INTENSIVE valid ONLY on `[HARD — pool]`"), which also wrongly rejects `[ROUTINE] [INTENSIVE]`. gather's `top_intensive` is the operative source of truth (ROUTINE + HARD — pool; human-gated excluded).
  - **Acceptance**:
    1. `roadmap-lint.sh` case (d): ACCEPT `[INTENSIVE]` on `[ROUTINE]` or `[HARD — pool]` (operative); ACCEPT on human lanes (`hands`/`meeting`/`decision gate`/`@manual`) as advisory — NO violation; REJECT only `[INTENSIVE]` with no recognised lane (lane-less / underivable).
    2. Fix the contradictory `:80` comment + the db39 doc; restate the operative-only-on-dispatchable-lanes doctrine in `references/hard-lanes.md` (`[INTENSIVE]` operative on dispatchable lanes, advisory-inert on human lanes — NOT "amplification of HARD"; routine-intensive is operative).
    3. **RECONCILE**: this SUPERSEDES id:297b's case-d "pool-only" rule. `tests/test_roadmap_lint_tagprose.sh` (`# roadmap:297b`, TICKED) case (d) asserts `[HARD — meeting] [INTENSIVE]` must ERROR — flip it to the new rule (advisory-accept), or repoint that example at a genuinely lane-less item. Full suite green requires it. it-infra id:9321 keeps both tags — NO it-infra edit.
  - **Tests**: `tests/test_roadmap_lint_intensive_lanes.sh` (`# roadmap:9062`) — accept/reject matrix over operative + advisory + lane-less (RED until landed). Plus the reconciled case (d) in `test_roadmap_lint_tagprose.sh`.
- [x] [ROUTINE] `backtest-historical.py` — historical replay of past dispatch events against reconstructed ledger state (id:4d8e backtest cluster) <!-- id:0e57 --> done 2026-06-30 (executor): `relay/scripts/backtest-historical.py` [--since YYYY-MM-DD] [--limit N] [--json] [--append-log]; iterates `relay-events.jsonl` dispatch events, resolves each repo/timestamp to a historical commit via `git rev-list --before` (read-only), reconstructs `hasRoutine`/`roadmap_actionable_open`/`open_hard_pool`/`unpromoted`/`substantive_unaudited`/`is_finished` from `git show C:<file>` content, and pipes the reconstructed JSON to `classify-verdict.sh` → V'. Compares V' to event's `mode` (V): agree/diverge/new/crashes + per-mode agreement rates. Documented partial-fidelity boundary: `dirty=false`/`diverged=false` assumed (self-consistent: dispatch events were demonstrably not blocked); uv.lock and recurring-audit exemptions omitted. Historical diverges labelled "diverge" (CANDIDATE, not confirmed RED). Makefile relay_FILES/EXEC/ALLOW updated. `tests/test_backtest_historical.sh` (`# roadmap:0e57`) green; `relay/scripts/roadmap-lint.sh` exit 0; full suite green. FIDELITY PASS done 2026-06-30 (executor): (1) per-row `classifier_reason`+`classifier_evidence[]`+`reconstructed` input fields in every row; (2) tag-time filter applied (ckpt tags created after event ts excluded — fixes false-sub_unaudited-false for past events); (3) id:9973 recurring-audit gate applied (recurring-audit [HARD — pool] items excluded when sub_unaudited=false); (4) legacy-lane-vocab reconstruction gap (pre-id:78ff `[HARD — strong model]` etc. not counted as open_hard_pool, rows flagged `reconstruction-gap:legacy-lane-vocab`); (5) all-fields-empty reconstruction gap (commit-timestamp-boundary gap where ckpt commit at dispatch time is missed by strict `--before` filter); (6) 3-bucket diverge categorization (`candidate-classifier-worse` / `reconstruction-gap` / `classifier-better`); (7) output leads with `candidate-classifier-worse` count (quality signal, target 0) not agree%. `tests/test_backtest_fidelity.sh` (`# roadmap:0e57`) green. GUARDRAIL: agreement-with-shard is NOT a quality target; classifier-better divergences (shard was wrong) must be preserved, not erased. Over 767 real events: 0 crashes, 93 candidate-classifier-worse (surface for human review), 205 reconstruction-gap (legacy-lane-vocab:137, all-fields-empty:73, 9973:6), 66 classifier-better, 403 matches-shard.
  - **Why** (meeting 2026-06-30-1523 DP7, id:4d8e / id:9d2b): the live `backtest-verdict.py` (id:5f93) compares CURRENT-state classification to LAST-DISPATCHED-state, producing structural divergence because dispatching changes state. The historical mode reconstructs the ledger at the EXACT EVENT TIMESTAMP from git history, giving a meaningful (if partial-fidelity) agreement signal over the full dispatch corpus. Together with id:5f93 (live) and id:9d2b (forward-shadow), forms the three-layer pre-flip validation gate.
  - **Acceptance**:
    1. `relay/scripts/backtest-historical.py` reads each `kind=dispatch` event from `relay-events.jsonl`, resolves the repo path from `relay.toml` (honoring `# path:`), finds the commit as-of `ts` via `git rev-list -1 --first-parent --before=<ts> HEAD`, reconstructs the classifier input from `git show C:<file>` (ROADMAP.md + TODO.md), and calls `classify-verdict.sh` for V'.
    2. Non-own or missing repos: surfaced on stderr, counted in `skipped`, never silently swallowed (id:4e14).
    3. Repo younger than event (no commit before ts): counted as `new`, never crashes.
    4. `--json` emits `{summary: {events,crashes,agree,diverge,new,skipped,mode:"historical",per_mode_agreement,distribution_verdict,distribution_event_mode}, rows:[...]}`. Report-only, exit 0.
    5. NEVER uses `git checkout`, `git switch`, `git worktree add`, or any write op on a target repo. Only: `git -C <path> show`, `rev-list`, `tag`, `log`, `merge-base --is-ancestor`.
    6. Makefile: `backtest-historical.py` in relay_FILES, relay_EXEC, relay_ALLOW.
  - **Tests**: `tests/test_backtest_historical.sh` (`# roadmap:0e57`) — 3-commit temp repo + ckpt tags + fixture relay.toml/events; asserts: (a) agree=2/diverge=1 on known fixture events, 0 crashes; (b) `git worktree list` = 1 entry + branch set unchanged after run (read-only guard); (c) exit 0, plain mode works; bonus --since filter. Hermetic.
- [x] [ROUTINE] `gather-human-backlog.sh` — anchor the HARD-lane parse to the item's OWN bracket tag, ignoring a pool-lane token mentioned only in body prose <!-- id:1bbd --> done 2026-06-30 (executor): `emit_hard_lanes()` in `gather-human-backlog.sh` now strips backtick-quoted strings from the line before lane detection, so a prose mention like `` `[HARD — pool]` `` cannot shadow the item OWN bracket tag. `tests/test_gather_lane_anchor.sh` (roadmap:1bbd) green; `test_hard_lane_buckets.sh` unregressed; suite 135 green.
  - **Why** (inbox routed:6645 from it-infra relay HARD child relay-20260630-131714-19334): `emit_hard_lanes()` reads the lane by whole-line substring match with the **pool branch checked FIRST** (`gather-human-backlog.sh:197`), so any `[HARD — hands]`/`[HARD — meeting]` item whose body prose quotes the literal `` `[HARD — pool]` `` (e.g. a re-lane-criterion sentence) mis-buckets as `hard_pool`. Caused it-infra `open_hard_pool=2` false-positive → a wasted Opus HARD dispatch (it-infra ids 9321/c5e9 are genuinely `[HARD — hands]`). Confirmed reproduced this review.
  - **Acceptance**:
    1. The lane is read from the item's OWN bracket tag (the `[HARD — <lane>]` immediately after the title), not from a `[HARD — pool]` string anywhere on the line. Fix per the report: anchor the lane regex to the tag after the title, OR test hands/meeting before pool, OR strip prose past the title's lane tag.
    2. A `[HARD — hands]` item whose prose contains `` `[HARD — pool]` `` buckets as `hard_hands`; a `[HARD — meeting]` item with the same prose buckets as `hard_meeting`. A genuine `[HARD — pool]` item still buckets as `hard_pool` (no regression).
    3. `tests/test_hard_lane_buckets.sh` stays green (no regression to the existing lane-vocabulary contract).
  - **Tests**: `tests/test_gather_lane_anchor.sh` (`# roadmap:1bbd`) — a `[HARD — hands]` item with a `[HARD — pool]` prose mention must bucket as `hard_hands`; genuine pool item unaffected. RED until the fix lands.
- [x] [ROUTINE] `classify-verdict.sh` verdict-PARITY — `blocked` for dirty/diverged (flip step a, id:a0b6) <!-- id:e424 --> done 2026-06-30 (strong turn): added a rank-0 `blocked` verdict so the classifier reaches the shard's dispatch-or-not parity — DIVERGED (has_upstream ∧ ahead>0 ∧ behind>0) and DIRTY non-lock-only → `blocked` (surface, never dispatch), outranking every D3 verdict. NOT blocked: uv.lock-only dirty (id:bae5 exemption) and behind-only (shard ff-merges first). classify-verdict-ONLY change (classify-repo already passes the full gather JSON through). `tests/test_classify_verdict_parity.sh` (`# roadmap:e424`) green; existing classifier tests unregressed; suite 134 green. Remaining for the flip: the relay-loop.js swap (step b) — keeps the side-effecting reconciliation guards shard-side.
- [x] [ROUTINE] case-g loop-breaker — wire surface-item lane-triage to the decision-queue so `handoff` can never silently no-op (4d8e child g) <!-- id:47f1 --> done 2026-06-30 (strong turn): the live `/relay --afk` run surfaced the defect — the classifier CORRECTLY emits `handoff` on surface-only backlog (DoD case b), but the resolution silently no-op'd, so `unpromoted-scan` re-counted surface items every round → `handoff` re-fired forever (30-handoff cluster = this loop, NOT a classifier miscount). Fix (NOT the classifier): (1) `decision-queue.sh add --source-id <token>` records the originating TODO id; (2) `unpromoted-scan.sh` excludes a token with an OPEN decision-queue record → a filed surface item drops out of fresh backlog and `handoff` stops re-firing; a RESOLVED record re-surfaces it for promotion; (3) `handoff.md` C2 now documents the FILE-each-surface-item-to-the-queue step (the missing "below") with the load-bearing `--source-id`, and declares a handoff that leaves surface items neither promoted nor filed INCOMPLETE. `tests/test_unpromoted_decision_queue_exclusion.sh` (`# roadmap:47f1`) green; case-b/h classifier tests unregressed; suite 136 green. Remaining loud-failure surface (de31/b444): the conservative inline lane-triage sub-agent (confidence → enqueue) is the decision-queue's own scope, not this loop-breaker.
- [x] [ROUTINE] `decision-queue.sh` — durable file-backed human-decision-request queue (C7, DP4) <!-- id:de31 --> done 2026-06-30 (executor): implemented `relay/scripts/decision-queue.sh` with add/list/resolve subcommands; flock'd on `<queue>.lock`; JSON built via python3; `RELAY_DECISION_QUEUE` env-overridable; registered in Makefile relay_FILES/EXEC/ALLOW.
  - **Why** (meeting 2026-06-30-1523 DP4): when the loop hits a resolution it can't mechanically close (a forced lane-triage of N surface items, a "close 244b or drain?" call), it must APPEND a decision request to a durable store and keep working — never silently no-op (cases g/h). This is the "one home" (the substrate); the transport (broker vs FIFO vs file-tail) is the deferred sibling id:b444.
  - **Acceptance**:
    1. `relay/scripts/decision-queue.sh add --repo <r> --kind <k> --question <q> [--option <o>]… [--evidence <e>]` mints a decision id, appends ONE JSON record `{id,repo,kind,question,options[],evidence,requested_at,status:"open"}` to `$RELAY_DECISION_QUEUE` (default `~/.config/relay/decision-queue.jsonl`), and prints the id. Append-only; flock'd (mirror `append.sh`/`commit-ledger.sh`).
    2. `decision-queue.sh list [--repo <r>]` prints the OPEN records (default open-only); `--all` includes resolved.
    3. `decision-queue.sh resolve <id> --answer <a>` sets `status:"resolved"`, `answer`, `resolved_at` on that record (rewrite under flock); resolved records drop out of the default `list`.
    4. Side-effect-free beyond the queue file; the queue path is env-overridable (hermetic tests).
  - **Tests**: `tests/test_decision_queue.sh` (`# roadmap:de31`) — add → list → second add (append) → resolve → open-list excludes resolved. RED until the helper lands.
- [x] [ROUTINE] `backtest-verdict.py` — pre-flip validation gate (replay classify-repo vs last-dispatch verdicts) <!-- id:5f93 --> done 2026-06-30 (strong turn): productized the dogfood prototype into `relay/scripts/backtest-verdict.py` (report-only, exit 0 like relay-doctor; `--json`); calls `classify-repo.sh` per own repo, compares to the most-recent `relay-events.jsonl` dispatch verdict. Gate run: **0 crashes / 49 repos** (the hard gate); diverged=40 but all explainable (state evolved since last dispatch — repos dispatched execute/review now show review from the resulting unaudited commits, or handoff once drained-with-backlog: the case-b/h fix). FIDELITY: live-state comparison, not full git-reconstruction — the classifier's input depends on ephemeral state (substantive_unaudited / worktrees / claims) that is NOT git-recoverable (the meeting's own partial-fidelity flag), so live + forward-shadow (id:9d2b) are the practical gate. `tests/test_backtest_verdict.sh` (`# roadmap:5f93`) green.
- [x] [ROUTINE] Record discover-sig on dispatch event (f896) <!-- id:f896 --> done 2026-06-30 (executor): two additive lines in `relay-loop.js` — (1) unit cache loop stamps `u.sig = sigByRepo[u.repo] || ''` on every fresh unit; (2) `pushEvent('dispatch', …)` now includes `sig: unit.sig || ''`. Purely additive; no verdict authority / shard / reconciliation changes. Template-literal lint stays clean. `tests/test_dispatch_event_sig.sh` (`# roadmap:f896`) green; suite 139 green.
  - **Why** (id:9d2b / id:4d8e): `relay-events.jsonl` dispatch records carried only `{repo,mode,tier,round}` — no input hash — so `backtest-verdict.py` compared current-state classification to a STALE last-dispatch verdict, producing structural divergence (agree=5/50 even on a clean tree). Recording the discover-sig at dispatch lets the backtest replay on the exact input the shard saw, making divergence bucketing (id:e8ea) sound.
  - **Acceptance**:
    1. `relay-loop.js` unit cache loop sets `u.sig = sigByRepo[u.repo] || ''` on every freshly classified unit.
    2. `pushEvent('dispatch', …)` includes `sig: unit.sig || ''` — fail-open (absent/empty sig → empty string sentinel).
    3. Purely additive: no change to verdict authority, shard, or reconciliation (id:a0b6 scope).
    4. `tests/test_workflow_template_lint.sh` stays green (template-literal hazard guard).
  - **Tests**: `tests/test_dispatch_event_sig.sh` (`# roadmap:f896`) — static source-shape assertions on relay-loop.js (grep + linter). RED until the edit lands.
- [x] [ROUTINE] Auto-bucket backtest divergences: state-drift vs true-disagreement (e8ea) <!-- id:e8ea --> done 2026-06-30 (executor): `backtest-verdict.py` now reads the `sig` field from each dispatch event; for each diverged row, recomputes the current discover-sig via `discover-sig.sh` and buckets: same-dispatch-sig AND same-current-sig → `RED` (real disagreement); absent/changed sig → `EXPECTED` (state-drift/pre-f896 event). RED and EXPECTED counts added to summary and `--json` output. Fail-open: empty current-sig → EXPECTED, never crash. Summary line now reads `agree=N diverged=N red=N expected=N`. `tests/test_backtest_bucketing.sh` (`# roadmap:e8ea`) green; suite 139 green.
  - **Why** (id:9d2b / id:4d8e): with f896's captured sig, diverged rows can be labelled mechanically — shrinking the human triage from ~43 rows/run to the handful of RED rows. Turns the id:9d2b gate from manual eyeballing into a mechanical pass/fail.
  - **Acceptance**:
    1. `backtest-verdict.py`: for each diverged row, reads `sig` from the dispatch event; calls `discover-sig.sh` for the current sig; same-sig-different-verdict → `RED`; changed/absent-sig → `EXPECTED`. Agree rows stay `agree`.
    2. `--json` summary includes `red` and `expected` counts. Plain output summary line shows both.
    3. Fail-open: if current-sig computation fails → EXPECTED, exit 0 (never crash).
    4. Pre-f896 events (no sig field) → EXPECTED (backward compatible).
  - **Tests**: `tests/test_backtest_bucketing.sh` (`# roadmap:e8ea`) — four cases: same-sig→RED, different-sig→EXPECTED, no-sig→EXPECTED, agree→agree. Hermetic fixture with real discover-sig.sh call.
- [x] [ROUTINE] Persist + auto-run the shadow accumulation log (1324) <!-- id:1324 --> done 2026-06-30 (executor): `backtest-verdict.py --append-log [<path>]` (env `RELAY_SHADOW_LOG`, default `~/.config/relay/shadow-log.jsonl`) appends one JSON line `{agree,diverged,red,expected,new,crashes,distribution,timestamp}` per run. Wired in `relay/SKILL.md` step 4: the front door runs `backtest-verdict.py --append-log` post-drain so id:9d2b accrues mechanically. `tests/test_backtest_append_log.sh` (`# roadmap:1324`) green; suite 139 green.
  - **Why** (id:9d2b): `backtest-verdict.py` was stdout-only — no place for the gate to accrue. The front door runs it automatically at end of every `/relay` run so the accumulation gate fills without human remembering.
  - **Acceptance**:
    1. `--append-log [<path>]`: appends ONE JSON line with keys `{agree,diverged,red,expected,new,crashes,distribution,timestamp}` to the log path; report-only, exit 0.
    2. `RELAY_SHADOW_LOG` env override controls the default path (hermetic tests).
    3. `relay/SKILL.md` step 4 (Exit summary) documents the front door running `backtest-verdict.py --append-log` post-drain.
  - **Tests**: `tests/test_backtest_append_log.sh` (`# roadmap:1324`) — append writes parseable JSON with expected keys; two appends yield two lines; explicit path argument; combined with `--json`. Hermetic.
- [x] [ROUTINE] `gather-repo-state.sh` — fix the env-var `execve` overflow on a >128KB ROADMAP <!-- id:07be -->
  - **Why** (found 2026-06-30 dogfooding id:3f0f): `emit()` hands large field values (the ROADMAP content + porcelain/toml/worktrees) to `python3` via ENV VARS; a single env string over `MAX_ARG_STRLEN` (128KB) breaks `execve` ("Argument list too long"). Real repos survive today because the emitted `roadmap` field is a ~94KB subset — but dotclaude-skills is already at 94KB and growing, and crossing 128KB crashes gather AND the whole `classify-repo.sh` chain. Same class as the id:3f0f wrapper fix (which used temp files).
  - **Acceptance**:
    1. `gather-repo-state.sh` no longer passes large field values to `python3` via env/argv — use a temp file or stdin so no single string can exceed `MAX_ARG_STRLEN`. The wrapper/caller path then works on a repo with a >128KB ROADMAP.
    2. Output is **byte-identical** to today on all existing inputs (the field set, ordering, and encoding are unchanged). Every existing gather/discovery test stays green (`test_discover_sig.sh`, `test_relay_discovery_guards.sh`, `test_relay_discover_shard.sh`, `test_classify_repo*.sh`, …).
    3. The temp file (if used) is cleaned up; gather stays side-effect-free outside its own scratch.
  - **Tests**: `tests/test_gather_repo_state_large.sh` (`# roadmap:07be`) — a fixture repo with a >128KB ROADMAP; gather must emit valid JSON (not crash). RED until the fix lands.
- [x] [ROUTINE] `classify-repo.sh` — DP1 assembly wrapper: gather → derive → fold unpromoted-scan → classify-verdict, end-to-end per repo <!-- id:3f0f -->
  - **Why** (dogfood finding 2026-06-30, id:4d8e / id:5f93): `classify-verdict.sh` (id:85df) is a pure function with NO producer for its full input — the live dogfood proved `gather-repo-state.sh` does not emit `hasRoutine`/`roadmap_actionable_open` and there is no wrapper folding in `unpromoted-scan`. This wrapper is what makes the classifier usable end-to-end and is the prerequisite for the real backtest (id:5f93) and the cutover. Productizes the throwaway prototype `scratchpad/backtest_dogfood.py`.
  - **Acceptance**:
    1. `relay/scripts/classify-repo.sh --repo <name> --path <abs>` emits ONE `{verdict,reason,evidence,ambiguous}` JSON on stdout, assembling: `gather-repo-state.sh` + DERIVED `hasRoutine`/`roadmap_open`/`roadmap_actionable_open` from `<path>/ROADMAP.md` (actionable = open `[ROUTINE]`/`[HARD — pool]` and NOT human-gated `[HARD — hands|meeting|decision gate]`/`@manual`) + FOLDED `unpromoted-scan.sh` `{promote,surface}` counts → piped to `classify-verdict.sh`.
    2. SIDE-EFFECT-FREE: runs the read-only helpers, mutates nothing (no commit, no ledger write, no tag). Registered in the Makefile `relay_FILES`/`_EXEC`/`_ALLOW`.
    3. End-to-end verdicts correct: open `[ROUTINE]` → `execute`; drained-`@manual`-only ROADMAP + untagged TODO backlog (surface) with HEAD audited → `handoff` (the case-b/h fix); finished ROADMAP + nothing unpromoted → `idle`.
  - **Tests**: `tests/test_classify_repo.sh` (`# roadmap:3f0f`) — hermetic mktemp git-repo fixtures run through the whole chain (integration tier, DP3). RED until the wrapper lands.
- [x] [ROUTINE] `classify-verdict.sh` — deterministic verdict classifier, the PRIMARY discovery verdict source (replaces the LLM shard) <!-- id:85df -->
  - **Why** (meeting 2026-06-30-1523 `docs/meeting-notes/2026-06-30-1523-relay-loop-mechanical-classifier.md`, umbrella id:4d8e DP1): relay discovery currently lets an LLM `discover-shard` own the primary verdict by trusting tag/gate/lane states that don't match the ledger — one `/relay --afk` run surfaced 8 false verdicts, all "the shard trusted a state the deterministic layer would have caught." `gather-repo-state.sh` (id:11ad) already computes the deciding fields and `relay-loop.js:397–429` already has JS backstops; this item consolidates that into ONE tested pure function so the common path is mechanical (DP1 "Replace": the shard fires ONLY on `AMBIGUOUS`).
  - **Acceptance**:
    1. `relay/scripts/classify-verdict.sh` reads a gather-repo-state JSON object on stdin (with an `unpromoted` summary `{promote,surface}` folded in) and emits ONE JSON object `{verdict, reason, evidence[], ambiguous}` on stdout. `verdict ∈ {execute, review, hard, handoff, human, idle, AMBIGUOUS}`; `evidence` is a list of `{field,value,source}` pointers; `ambiguous` is a bool (`AMBIGUOUS` is the ONLY verdict that routes to the LLM — DP2).
    2. PURE FUNCTION + SIDE-EFFECT-FREE: a function of its JSON input only (no git, no fs writes, no ledger mutation, no lease/dispatch). Orchestration (gather→scan→classify) stays in the caller. A picker may call it many times per round.
    3. Verdict logic gets the corpus right — at minimum cases (a) `open_hard_pool=0` ≠ `hard`; (b) drained-`@manual`-only ROADMAP + unpromoted backlog → `handoff` (not idle/human); (h) `is_finished` BUT unpromoted `promote`/`surface` → `handoff` (the finished guard consults the scan). D3 verdict-class order holds (execute → review → hard → handoff).
    4. Emits the D3 priority-class rank alongside the verdict (so a streaming refill picker — id:80b8 — orders units without recomputing).
  - **Tests**: `tests/test_classify_verdict.sh` (`# roadmap:85df`) — pure JSON-in/verdict-out fixtures seeded from the real 2026-06-30 failures (a/b/h) + the output contract. RED until the script lands. (The full two-tier RED harness incl. integration fixtures + cases e/f/g is umbrella child id:ccd9 / follow-ons; this item is the foundation the others build on.)
- [x] [ROUTINE] `roadmap-lint.sh` — loud-ERROR on a tag/prose lane disagreement (case c) and a free-typed `[INTENSIVE]` (case d) <!-- id:297b -->
  - **Why** (meeting 2026-06-30-1523, id:4d8e DP2/DP3 cases c/d): (c) ai-codebench id:244b carried `[HARD — decision gate]` while its own prose said "re-laned to pool, runs under --intensive" — the disagreement was read as a silent gate, the item never ran, and the empty run was misread as "done." The TAG is authority; a tag/prose disagreement must fail LOUD. (d) it-infra c5e9/fd30 had `[INTENSIVE — local-llm]` free-typed onto a disk `rm` / a `/meeting` decision item — INTENSIVE must be derivable, not free-typed.
  - **Acceptance**:
    1. `roadmap-lint.sh` exits NONZERO with a stderr ERROR naming the violation when an open item's lane bracket disagrees with a lane claimed in its own prose (case c).
    2. It exits NONZERO with a stderr ERROR when `[INTENSIVE — <resource>]` is free-typed onto an item whose resource is not derivable (case d).
    3. No false positives: a conforming ROADMAP (plain `[ROUTINE]`/`[HARD — pool]` items) stays a clean zero-exit no-op. These are loud-fail checks (exit-code + stderr), NOT verdicts.
  - **Tests**: `tests/test_roadmap_lint_tagprose.sh` (`# roadmap:297b`) — asserts exit-code + stderr for cases c/d and a clean pass for a conforming ROADMAP. RED until both checks land.
- [x] [ROUTINE] `ckpt-tag.sh` must degrade gracefully when `.gitattributes` is unaddable — a repo that can't track the `merge=union` attr must still get its checkpoint <!-- id:a7a3 -->
  - **Why** (observed 2026-06-30 reviewing `kienzler-homepage`; reverse-handoff of TODO id:a7a3): the repo's `.gitignore` carried a `.*` dotfile catch-all that swallowed `.gitattributes`, so ckpt-tag's `git add -- RELAY_LOG.md .gitattributes` (`relay/scripts/ckpt-tag.sh:55`) exited non-zero and — under `set -euo pipefail` — aborted the WHOLE checkpoint inside the flock: no commit, no tag, and `RELAY_LOG.md` left STAGED as dirty residue. The `RELAY_LOG.md merge=union` attribute is a nicety (it only matters for parallel-relay merge conflicts), NOT essential to a checkpoint; a repo that cannot add it must still get its `RELAY_LOG.md` entry + tag. Manual workaround used that day: `git commit RELAY_LOG.md` + `git tag -a`, plus a `!.gitattributes` negation in kienzler's `.gitignore` — but ckpt-tag itself must not hard-fail.
  - **Acceptance**:
    1. When `.gitattributes` cannot be staged (ignored by `.gitignore`, or any `git add -- .gitattributes` failure), ckpt-tag.sh WARNs to stderr and PROCEEDS — it still commits `RELAY_LOG.md` and produces the annotated `relay-ckpt-*` tag. It exits 0.
    2. The normal path (where `.gitattributes` IS addable) is unchanged: the attr file is created/updated and committed alongside `RELAY_LOG.md` exactly as today.
    3. No `RELAY_LOG.md` staged-but-uncommitted residue is ever left behind, in EITHER path. The commit must stage `RELAY_LOG.md` (and `.gitattributes` only if it staged cleanly) — never abort mid-flock with the log staged.
    4. The flock, the same-minute `-2`/`-3` tag-collision suffixing, and the stdout tag-name contract are all preserved.
  - **Tests**: `tests/test_ckpt_gitattributes_degrade.sh` (`# roadmap:a7a3`) — sets up a repo whose `.gitignore` `.*` catch-all swallows `.gitattributes`, runs ckpt-tag.sh, and asserts exit 0 + a `relay-ckpt-*` tag + the `RELAY_LOG.md` entry committed + no staged residue. RED until the script tolerates the unaddable attr.
  - **Done-check**: `tests/run-tests.sh tests/test_ckpt_gitattributes_degrade.sh`, then tick this checkbox AND the TODO id:a7a3 line, and `make test` must be fully green.
  - **Context**: `relay/scripts/ckpt-tag.sh` (the `git add -- RELAY_LOG.md .gitattributes` at :55 and the `if ! git diff --cached --quiet` commit at :56–59). Likely shape: stage `.gitattributes` in its OWN tolerant `git add` (`|| warn`), then `git add -- RELAY_LOG.md`, then commit whatever is staged. Single-id-two-views: REUSE `<!-- id:a7a3 -->` (already in TODO.md); tick both ledgers when it closes.
- [x] [ROUTINE] Gate `claim.sh` `is_live` worktree-anchor on the run heartbeat — a dead-but-committed run must stop holding its claim forever <!-- id:33d3 --> done: heartbeat_alive_for_run gate in is_live; worktree clause only extends past mtime-TTL when heartbeat.sh status <runId>==alive; dead/absent → mtime-TTL fallback; fail-safe on heartbeat.sh error
  - **Why** (meeting 2026-06-29, `docs/meeting-notes/2026-06-29-1750-dead-but-live-claim-heartbeat-gate.md`; the id:9000 remainder after id:672b): `is_live` (`relay/scripts/claim.sh:124`) currently keeps a claim live when its mtime is fresh **OR** (id:7570) its `--worktree` has commits beyond main **OR** (id:1b11) its `--pid` is alive. The id:7570 `worktree_working` clause (`:89`) is a "has unmerged work" signal, NOT a liveness signal — committed git objects persist after the owning process dies, so a relay child that commits then dies before integration holds its claim **forever** (the truncocraft second-instance class). A parallel `/meeting` or pool then sees a held claim for abandoned work. `heartbeat.sh` (id:e149) already exists as the PURE ts+TTL run-liveness oracle built for exactly this — its header literally documents that the worktree clause "is exactly WRONG for detecting a dead LOOP." `is_live` just doesn't consult it yet. Fix: gate the worktree clause on the run heartbeat so the worktree anchor only EXTENDS liveness past mtime-TTL when a FRESH heartbeat backs it.
  - **Acceptance**:
    1. `is_live`'s `worktree_working` contribution is GATED on the claim's run heartbeat: the worktree clause keeps a claim live ONLY when `heartbeat.sh status <runId>` (the claim's recorded `.runId`) prints `alive`. (D1)
    2. NO-HEARTBEAT (`status` = `absent`) OR `dead` → the worktree clause does NOT extend liveness; the claim falls back to the ORDINARY mtime-TTL (live iff mtime fresh OR `pid_alive`). Net: the id:7570 worktree anchor only extends past mtime-TTL when a fresh heartbeat backs it. (D2)
    3. Reuse `heartbeat.sh`'s own TTL constant — introduce NO new knob/threshold in `claim.sh`. (D2)
    4. `claim.sh` MUST NOT touch the worktree — reclaim/reap free only the RESERVATION; the orphan worktree with its commits is disposed by the existing reconcile (id:a4e9 park / id:7809), never by `claim.sh`. (D3)
    5. Scope = ONLY this `is_live` clause-gate + the heartbeat consult. OUT: bilateral coordination channel (rest of id:9000), auto-integrating orphans, pid-reuse hardening for id:1b11, any new TTL knob. (D4)
    6. A meeting claim (no worktree) and a standalone `--pid` job (no worktree) are unaffected — they never enter the worktree clause. Single-id-two-views: REUSE `<!-- id:33d3 -->` (already in TODO.md); keep both ledgers' checkbox consistent when it closes.
  - **Tests**: `tests/test_relay_claim_liveness.sh` (`# roadmap:7570`, extended) — keep its existing cases; new DETERMINISTIC (stubbed-heartbeat-ts, never wall-clock-compared, per id:16e9) cases assert: (a) worktree-with-commits + FRESH heartbeat for the claim's run → claim LIVE (not stolen); (b) worktree-with-commits + STALE/dead heartbeat → claim RECLAIMABLE (another run's acquire succeeds / reap moves it); (c) worktree-with-commits + ABSENT heartbeat + stale mtime → reclaimable (mtime-TTL fallback); (d) mtime-fresh → live regardless of heartbeat. Fresh = `heartbeat.sh beat <runId>`; stale = write/age `heartbeats/<runId>.json` `ts` deterministically. These new cases are RED until `claim.sh` consults the heartbeat.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_claim_liveness.sh`, then tick this checkbox and `make test` must be fully green.
  - **Context**: `relay/scripts/claim.sh` (`is_live` :124, `worktree_working` :89, `pid_alive` :116, `is_fresh` :74; records `.runId`), `relay/scripts/heartbeat.sh` (`status <runId>` → alive|dead|absent, its own `HEARTBEAT_TTL`). Relates id:e149 (heartbeat oracle), id:7570 (worktree anchor being gated), id:1b11 (`--pid` clause, unaffected), id:a4e9/7809 (orphan reconcile that disposes the worktree), id:9000 (parent; this is its cheapest half), id:672b (the prior shipped half). NOTE: this handoff makes NO edit to `claim.sh` — that is the executor's job.
- [x] [ROUTINE] Structured executor size-out signal — a sized-out `[ROUTINE]` item must hand back so the integrator gates it (stop the re-dispatch spin) <!-- id:08c0 -->
  - **Why** (observed truncocraft, relay-ckpt-20260629-1325 — routed:9a50; manually hard-split there into 9039/d9c1/5f6c): a cheap executor that sizes out a `[ROUTINE]` item as too-large-to-land-green has no handback→gate path. It only has the SOFT notes — a `friction:` commit line (contract rule 4) / a `BLOCKED:` RELAY_LOG line (rule 3). The integrator's durable handback follow-up (`handback-followup.py`, id:3801) reads ONLY the STRUCTURED return fields (`contract_met`/`handback_item`/`route`/`proposed_split`) — it never parses the soft notes. So the sized-out item stays a plain open `[ROUTINE]`; the executor commits a checkpoint with `contract_met=true`, the repo signature changes (defeating the discover cache), and the next discovery round re-dispatches the SAME un-doable item to another executor. The HARD-execute child already has this discipline (relay-loop.js line ~1277, id:8b1f); the `[ROUTINE]` execute child does not.
  - **The integrator GATE already exists and works** — `handback-followup.py`'s `gate_line` re-tags a `[ROUTINE]` parent to the classifier-excluded `[HARD — decision gate]` (`TIER_RE` matches `[ROUTINE]`; proven green by `tests/test_handback_followup.sh` "decision-gate re-tags a [ROUTINE] parent"), and `relay-loop.js` (`handbackFollowup`, ~line 1490) calls it for ANY handback regardless of verdict. The missing half is purely UPSTREAM: the executor must be TOLD to EMIT the structured size-out handback for a `[ROUTINE]` item.
  - **Design (decided in this handoff — NOT a meeting): reuse the existing gate, invent NO new tag.** The routed item floated `[ROUTINE — oversized, needs handoff split]`, but that tag would NOT stop the spin: the dispatch matcher `^- \[ \].*\[ROUTINE\]` (relay-loop.js openRoutine count + gather-repo-state.sh) and the HARD-lane exclude filter `\[HARD — (hands|meeting|decision gate)\]` would BOTH still let a `[ROUTINE — …]` line through. Re-tagging to `[HARD — decision gate]` via the existing id:3801 path is the only thing that actually excludes it from re-dispatch AND surfaces it for a handoff decomposition.
  - **Acceptance**:
    1. `relay/references/executor-contract.md` gains a SIZE-OUT rule: when an executor determines a `[ROUTINE]` item is too large to land green in one session AND cannot be partially advanced toward its green checkbox, it MUST NOT silently leave the item open — it returns the STRUCTURED handback: `contract_met=false`, `handback_item=<id>`, `route=hard-split` (with `proposed_split` seams) or `decision-gate`/`human`, plus a one-line `gate_reason`.
    2. That rule states explicitly that the soft `friction:`/`BLOCKED:` notes are NOT sufficient for this (the integrator's durable follow-up reads only the structured fields), names the re-dispatch spin it prevents, and points at the id:3801 gate so the executor trusts the integrator will durably re-tag the item to `[HARD — decision gate]` + append seams.
    3. The `relay-loop.js` EXECUTE-verdict child prompt (the `unit.verdict === 'execute'` segment, today just "never start an item you cannot finish") wires the size-out → structured-handback path for `[ROUTINE]` items, mirroring the HARD-execute child's id:8b1f discipline (size-out = CLEAN worktree, NO commit, rationale only in the returned `handback`/classification fields).
    4. The contract version is bumped `v5 → v6` (an in-flight executor must learn the new return obligation — contract maintenance rule), and the `## Relay contract <!-- relay-executor contract vN -->` pointer in `CLAUDE.md` is refreshed to match (the SKILL.md note auto-refreshes it, but verify).
    5. No new ROADMAP tag is introduced; the gate stays the existing `[HARD — decision gate]` path.
  - **Tests**: `tests/test_executor_sizeout_signal.sh` (`# roadmap:08c0`) — currently RED. Asserts (a) executor-contract.md documents the structured signal (size-out rule, `contract_met=false`, `handback_item`+route, soft-notes-insufficient rationale, id:3801 pointer), (b) contract version ≥ v6, (c) the relay-loop.js execute-verdict segment covers ROUTINE size-out → handback.
  - **Done-check**: `tests/run-tests.sh tests/test_executor_sizeout_signal.sh`, then tick this checkbox and `make test` must be fully green.
  - **Context**: `relay/references/executor-contract.md` (the lean Sonnet executor contract — the actual doc to edit); `relay/scripts/relay-loop.js` (execute-verdict prompt ~1276, HARD model at ~1277, `handbackFollowup` ~1490, return schema ~1285); `relay/scripts/handback-followup.py` + `tests/test_handback_followup.sh` (the gate, already green — do NOT change it); `CLAUDE.md` §"Relay contract" pointer. Relates id:3801 (durable handback gate), id:8b1f (HARD size-out clean-worktree discipline), id:365b (redispatch circuit breaker — a coarse backstop this makes precise), id:e107 (non-actionable ROUTINE exclusion). Source: shared-inbox routed:9a50 (from truncocraft).
- [x] [ROUTINE] `/meeting` setup-time advisory claim — acquire ONE claim at SETUP for relay-managed repos; release on every exit; inform-and-proceed on an existing claim <!-- id:672b -->
  - **Why** (decided 2026-06-24 meeting D3, `docs/meeting-notes/2026-06-24-1308-meeting-relay-classification-claim-compat.md`; reconciled 2026-06-29 with the just-shipped id:c144): `/meeting` closes the one-sided-lease asymmetry ([[meeting-pool-claim-asymmetry-incident]]) — today the pool claims at dispatch but `/meeting` takes no claim, so a live pool can re-derive off a stale base while a meeting edits the same ledgers. Fix: `/meeting` acquires ONE advisory repo claim at SETUP (the pool already honors claims via `claim.sh peek` → skips the repo for the meeting's duration), released at end. **c144 reconciliation:** id:c144 (shipped 2026-06-29) already REMOVED the old step-2a per-write-back acquire/DEFER and made ledger write-backs peek-and-warn-and-proceed under flock + atomic commit (id:148b `md-merge.py --commit`). So `/meeting` now holds exactly ONE claim (setup→end) and the 2b/2e write-backs happen UNDER that held claim + flock — do NOT re-introduce a second acquire at 2a.
  - **Acceptance**:
    1. In a relay-managed repo (`<root>/ROADMAP.md` exists), `/meeting` acquires an advisory claim at SETUP — `claim.sh acquire <root-basename> --run meeting-<captured session id> --mode meeting` — early in setup (after root resolution, near the existing 2a-replay area), BEFORE the design/decide phase.
    2. The claim is released at the END of the meeting on ALL exit paths (`claim.sh release <root-basename> --run meeting-<captured session id>`), with the claim mtime+TTL as the backstop if a path is missed.
    3. This setup claim REPLACES (does not duplicate) any per-write-back acquire: there is NO second `claim.sh acquire` at step 2a — the 2b/2e write-backs run under the ONE held claim + flock + atomic commit (id:c144/148b).
    4. On an EXISTING claim at setup (a live pool / another session already holds the repo): `/meeting` INFORMS the user and PROCEEDS as a NON-CONFLICTING session — the decide/design phase needs no claim so it proceeds; the ledger WRITE-BACK proceeds via peek-and-warn + flock + atomic commit (per c144/148b). It does NOT abort, and it is NOT worktree-per-meeting (rejected af04).
    5. The id:2c42 deferred-writeback is the flock-TIMEOUT FALLBACK only — NOT the default on a contended claim (this supersedes id:672b's original "write-back deferred+replayed" wording for the normal case, per c144).
    6. Non-relay repos (no `<root>/ROADMAP.md`) behave exactly as before: NO claim is acquired or released.
    7. Single-id-two-views: this item REUSES `<!-- id:672b -->` (already in TODO.md, the design ledger); keep the checkbox consistent across BOTH ledgers when it closes.
  - **Tests**: `tests/test_meeting_setup_claim.sh` (`# roadmap:672b`) — GREEN. Content-assertion against `meeting/SKILL.md`: (a) a setup-time advisory `claim.sh acquire … --mode meeting` gated on `ROADMAP.md`; (b) a release at end-of-meeting on all exit paths; (c) the existing-claim non-conflicting path (inform user + proceed; NOT abort, NOT worktree-per-meeting); (d) the c144 reconciliation (write-back proceeds under flock/peek-and-warn; id:2c42 = flock-timeout fallback); (e) non-relay repos unaffected.
  - **Done-check**: `tests/run-tests.sh tests/test_meeting_setup_claim.sh`, then tick this checkbox and `make test` must be fully green.
  - **Done 2026-06-29** (executor, Sonnet): added `2-setup-claim` step to `meeting/SKILL.md` Setup section documenting the advisory claim acquisition at setup, release on all exit paths, existing-claim non-conflicting path, TTL backstop, c144 reconciliation, and non-relay-repo no-op. Full suite green (122 passed, 0 failed). Ticked id:672b in ROADMAP.md + TODO.md (single-id-two-views).
  - **Context**: `meeting/SKILL.md` (Setup steps; the 2a peek-and-warn block, the 2a-replay block ~line 124, and the 2b/2e write-backs) — the executor edits SKILL.md; `relay/scripts/claim.sh` (acquire/release/peek interface, `--mode meeting`); relates id:c144 (peek-and-warn write-back, supersedes the d748 DEFER), id:148b (atomic scoped commit), id:2c42 (deferred-writeback = flock-timeout fallback), id:d748 (the removed lease hold), id:9000 (this is its cheapest half; richer notify-channel deferred), id:3536 (surface the claim in the cockpit, gated on this). NOTE: this handoff makes NO edit to SKILL.md — that is the executor's job.
- [x] [ROUTINE] Relay host-awareness — host-bound verification gate for multi-host config monorepos <!-- id:43b9 -->
  - **Why** (zomni meeting 2026-06-26, `consolidate-device-repos-monorepo` D7): the planned `it-infra` monorepo (`hosts/<hostname>/` + `shared/`) holds work items whose definition-of-done is HOST-BOUND — you cannot validate fievel's apt path or zomni's touchscreen udev rule on the wrong machine. *Editing* a config file is host-agnostic (any host writes it); only the `make install`/test VERIFICATION is host-bound. The relay had no notion of "this item belongs to host X", so an executor/reviewer on the wrong host would either run install/tests against a foreign config or falsely credit a green it never ran.
  - **Acceptance**:
    1. A ROADMAP item carries an OPTIONAL `[host:<name>]` tag (`[host:zomni]`/`[host:fievel]`/`[host:any]`); untagged ⇒ `host:any` ⇒ host-agnostic (verify anywhere).
    2. `relay/scripts/host-gate.sh '<item line>'` parses the tag vs the current `hostname` (override `RELAY_HOSTNAME`): exit 0 PROCEED (tag absent / `any` / matches), exit 3 DEFER (names a different host; prints `defer: needs host:<X> (current: <Y>)`), exit 2 misuse. Case-insensitive; reads text from `$1` or stdin.
    3. Editing stays host-agnostic; ONLY the verification step gates. On mismatch the conservative default is DEFER with a `needs host:<X>` note — NOT ssh-to-host execution (documented future option only).
    4. Enforced (not just documented): executor done-check (contract rule 2) and reviewer re-derivation (review §2c) consult the gate before verifying; SKILL.md `executor` section documents it; script registered in the Makefile manifest.
  - **Spec / test**: `tests/test_host_gate.sh` (`# roadmap:43b9`) — matching/mismatched/any/untagged/case-insensitive/stdin/misuse. Green.
  - **Done 2026-06-26** (strong turn, free-implemented — design fully decided by the meeting, bounded, no executor in loop): added `relay/scripts/host-gate.sh` + test (green); wired the gate into `references/executor-contract.md` rule 2 (DEFER on exit 3, leave checkbox unticked, append `DEFERRED: <id> needs host:<X>` to RELAY_LOG) + the item-format reference; `references/review.md` §2c (treat host-bound tests as unverified on a mismatched host, keep item open, never `contract_met` on unrun verification); `SKILL.md` executor section; bumped the executor contract v4→v5 (rule 2 gained a clause) across executor-contract.md / conventions.md / this repo's CLAUDE.md pointer (external managed repos auto-refresh on their next review §4); registered `host-gate.sh` in `relay_FILES`/`_EXEC`/`_ALLOW`/`_LOCAL`. The actual it-infra migration + ssh-to-host verification are out of scope (separate gated sessions). Resolves inbox `routed:ffe4`.
- [x] [ROUTINE] TODO/inbox conformance grammar — flag (and safely auto-fix) every non-conforming ledger entry so nothing slips through relay routing <!-- id:3441 -->
  - **Why** (user directive 2026-06-25, escalated twice): `/relay` is only reliable if NO work hides in a malformed ledger line. `roadmap-lint.sh` already enforces a positive grammar on open ROADMAP items, but `TODO.md` has NO grammar lint — a scan of THIS repo found a bare `placeholder` line (252) and a checkbox-less pointer bullet (185) that no tool sees; the shared inbox has ~12 token-less prose blocks. **At least one of handoff/review/human MUST notify of every non-conforming entry** (everything that is not a header, an HTML comment, or a well-formed `- [ ]/[x]` list item + id tag), and **auto-fix where applicable, NEVER block work that shouldn't be blocked** (user: "autofix instead if applicable … never block work that shouldn't be blocked").
  - **Acceptance**:
    1. `relay/scripts/todo-conformance.sh [--fix] [--inbox] [<path>]` — a POSITIVE grammar (mirrors `roadmap-lint.sh`). TODO mode (default): a top-level (non-indented) non-blank line is CONFORMING iff it is a markdown header, an HTML-comment-only line, OR a well-formed `- [ ]/[x]` item; an OPEN `- [ ]` item must additionally carry `<!-- id:XXXX -->` (4-hex). Indented continuation lines are NEVER linted (like roadmap-lint). EXEMPT: a line bearing `<!-- lint-ok: <reason> -->` or an intentional pointer `<!-- ref:XXXX -->`. Output `<class>\t<lineno>\t<text>` (`missing-id` = auto-fixable; `orphan` = surface-only). `--inbox` swaps in the inbox grammar (checkbox + `[target]` + `routed:XXXX`). Report-only (exit 0 with findings); `--strict` → nonzero. LOUD on unreadable path, no silent `2>/dev/null` swallow (id:415b/4e14).
    2. `--fix` AUTO-FIXES only the unambiguously-safe class: an open `- [ ]` item that is well-formed but missing an id → mint via `append.sh new-id` and append `<!-- id:XXXX -->` (flock'd, in place). It MUST NOT touch `orphan` lines (bare prose / checkbox-less bullets — intent unknowable; converting them would fabricate tasks). Prints what it fixed + what it surfaced.
    3. Wired into `relay-doctor.sh`, `/relay review` (→ REVIEW_ME box, never a hard block), `/relay human` (triage list), and handoff C2. **Never blocks** a routine/review/handoff turn — surfaces + auto-fixes, exit stays 0 (the `--strict` gate is opt-in only).
  - **Spec / red test**: `tests/test_todo_conformance.sh` (`# roadmap:3441`) — hermetic fixtures: (a) a clean TODO (headers + well-formed id'd items) → no findings; (b) an open item missing an id → `missing-id`, and `--fix` appends a minted id (re-lint clean); (c) a bare prose line + a checkbox-less bullet → `orphan`, and `--fix` leaves them UNTOUCHED (surfaced, never fabricated); (d) a `<!-- lint-ok -->` / `<!-- ref:XXXX -->` line → exempt; (e) `--inbox` flags a token-less inbox prose block but passes a conforming routed line. RED until the script + wiring land.
  - **Done-check**: tick + `make test` green; dogfood on this repo's TODO (auto-fix any missing-id; resolve the `placeholder`/pointer lines); relay-doctor shows the new check.
  - **Context**: `relay/scripts/roadmap-lint.sh` (the ROADMAP-side sibling — same positive-grammar pattern), `relay/scripts/unpromoted-scan.sh` (id:2dea — overlaps on the missing-id class), `meeting/append.sh new-id` (the mint path for --fix). Inbox AUTO-RECONCILE on cross-repo activity is the sibling id:678e. Deps: none.
- [x] [ROUTINE] Inbox auto-reconcile SLICE-2 auto-write — `scan-routed.sh --apply` (class-A idempotent INBOUND stub keyed on routed:XXXX/id-twin; resolve-by-EXISTENCE not relay.toml membership; claim.sh-peek skip; own commit-ledger.sh commit; mandatory --dry-run) on cross-repo sweeps (respect --exclude); folds id:3947; slice-1 detection SHIPPED <!-- id:678e -->
  - **Why** (user directive 2026-06-25): the shared cross-project inbox (`~/.claude/todo-inbox.md`) strands work — routed items whose target repo never ingested them + token-less prose entries no tool resolves (live: 12 + ~12 for this repo alone). User wants this handled **"more or less automatically on any cross-repo `/relay` or `/meeting` activity, but respecting relay's `--exclude` switch"** — i.e. not a passive surface but an active reconcile pass folded into the cross-repo sweeps, auto-fixing where applicable and surfacing the rest, never blocking.
  - **Why [HARD — meeting]**: genuine design judgment + irreversible auto-mutation of MULTIPLE PRIVATE repos. Open Qs: (a) what is unambiguously auto-fixable (a `routed:XXXX` with a clear `[target]` → append an `[INBOUND routed:XXXX]` stub into the target's TODO via flock'd `md-merge.py`; vs a token-less `<repo>:` prose block → mint a routed id only if the target parses, else surface); (b) the exact integration points (the autonomous pool / `/relay --all` / `/relay human --all` / `/meeting --cross`) and how each honors `--exclude`/`relay.toml paused`; (c) public/private coupling — the PUBLIC dotclaude-skills scripts must take the inbox path by injection, never hardcode the local file; (d) idempotency + the parallel-session claim (don't auto-file into a repo a pool worktree holds — cf. claim.sh / [[meeting-pool-claim-asymmetry-incident]]). Builds on id:3441's `--inbox` grammar (detection) and the id:3947 `scan-routed.sh` dead-letter proposal. Surfacing is cheap and ships with id:3441; the AUTO-FILE/auto-migrate mutation is the [HARD] part gated here.
  - **DECIDED 2026-06-25** (`docs/meeting-notes/2026-06-25-2335-inbox-auto-reconcile-cross-repo.md`): **detection-first, two slices.** SLICE 1 (build now) = `relay/scripts/scan-routed.sh`: report-only dead-letter detector (a conforming `routed:` item absent from its `[target]` repo's TODO+ROADMAP) + inbox-conformance (reuse `todo-conformance.sh --inbox`), printing the READY-TO-RUN file command; `RELAY_INBOX` default `~/.claude/todo-inbox.md`; once-per-sweep; honor `paused`/`--exclude`; wired into relay-doctor + /relay human + /meeting --cross + pool prelude. SLICE 2 (this item stays open for it) = auto-file the reversible additive INBOUND stub for **class A** (conforming token + resolvable target, incl. polyrepo `# path:`), gated on `claim.sh peek` skip + `routed:` idempotency. **Class B** (token-less prose / unresolvable target) = forever surface-only, never guessed. Reverses id:b30b's "no auto-write" ONLY at the slice-2 additive-stub boundary (re-justified: surface-only failed — 12 stranded items; the stub is additive/idempotent/reversible/claim-guarded, not a silent clobber).
  - **DECIDED 2026-06-29** (`docs/meeting-notes/2026-06-29-1116-inbox-reconcile-slice2-gate-open.md`): **slice-2 gate OPENED → re-tagged `[ROUTINE]`.** The slice-1 dogfood this session (4 class-A dead-letters hand-routed via scan-routed's emitted commands, zero resolution error) satisfies the "proven target-resolution" precondition. Slice-2 = `scan-routed.sh --apply`: class-A reversible INBOUND stub only, idempotent on `routed:XXXX` (grep target TODO for the routed token OR its minted `id:` twin before writing — survives promotion), `claim.sh peek` skip for relay-managed targets, own `commit-ledger.sh` commit (clean tree, never `git add -A`), **mandatory `--dry-run`/diff**. **Resolution axis revised (user): repo-EXISTENCE, not relay.toml membership** — TODO *routing* ≠ relay *management*; resolve `[target]` to a repo path (discover-repos.sh `own` + relay.toml `# path:` polyrepo central-ledger, b257; an own repo with no relay.toml block still resolves) and write into ITS TODO with NO onboarding; only a target matching no repo on disk is UNRESOLVED→class-B surface. The open Qs (a)-(d) above are resolved. **Out of scope:** auto-onboarding any repo; class-B auto-parse; the emit-time per-routed stub (id:3947 proposal-1, separate future item). Red-test cases: polyrepo→central TODO, non-relay-own→its TODO, nonexistent→UNRESOLVED, idempotent re-run=no-op, `--dry-run`=no write+diff.
  - **Spec / red test**: `tests/test_scan_routed.sh` (`# roadmap:678e`) covers slice 1 (dead-letter / clean-twin / token-less-prose / `--exclude` / misuse). Slice-2 auto-write spec follows once slice 1 + target-resolution land.
  - **Direction (user 2026-06-25)**: global `CLAUDE.md` now documents the inbox lifecycle
    (write via `append.sh -t inbox`, resolve via `inbox-done`, lint via `todo-conformance.sh
    --inbox`, reconcile on cross-repo activity respecting `--exclude`) — the doc half is DONE.
    The mechanized half MECHANIZES by extending the EXISTING small tools — `append.sh` inbox
    subcommands + `todo-conformance.sh --inbox` (detection, shipped) + a new `scan-routed.sh`
    dead-letter pass — NOT by adapting `claim.sh` (that is a repo *lease* / mutual-exclusion
    primitive, not a dead-letter router; the only claim relevance is the idempotency guard in
    open-Q (d): don't auto-file into a repo a pool worktree currently holds).
  - **Context**: id:3947 (this absorbs it), id:3441 (detection substrate), `relay/scripts/discover-repos.sh` + the `--exclude`/`paused` plumbing, `meeting/append.sh -t inbox`, [[meeting-relay-classification-claim-compat-2026-06-24]] (manual pool↔meeting coordination = `--exclude meeting-repo`).
  - **Why** (LIVE evidence 2026-06-25, truncocraft): `/relay next`/`review`/handoff decide "is there work?" from OPEN ROADMAP items + unaudited commits ONLY. truncocraft's ROADMAP was fully `[x]`-closed while `TODO.md` held FIVE open executable items (`b1e4` removal ghost, `a7d2`/`c3f7` HARD-pool, `a03c` HARD-meeting, plus the favicon redo) — so every prior `/relay` run read the repo as DRAINED and the apex turn even reported "handoff would be a no-op." The whole job of handoff C2 is to PROMOTE TODO→ROADMAP, but nothing detects the un-promoted backlog, so it sat idle for days. This is the **second instance** (id:78ff was the first: a `[HARD — pool]` filed TODO-only the pool couldn't see).
  - **Gap vs the existing d9b0 promotion-tracking note** (ROADMAP.md line ~142, under the *closed* `d9b0`): that check only flags a TODO item *already carrying* an executable lane (`[ROUTINE]`/`[HARD — pool]`) whose `id:` lacks a ROADMAP twin. truncocraft's stranded items carried **NO lane tag at all** in TODO (raw backlog prose) → they slip past that check entirely. d9b0 was ticked `[x]` but this sub-point never actually shipped as a routing-visible signal. Re-open it here with the broader, evidenced scope.
  - **Acceptance**:
    1. A mechanical check (extend `meeting/orphan-scan.sh` or a new `relay/scripts/unpromoted-scan.sh`) that lists every OPEN `TODO.md` `- [ ]` item whose `<!-- id:XXXX -->` has NO twin line in that repo's `ROADMAP.md` — **regardless of whether the TODO line carries a lane tag** (the gap that bit truncocraft). Output: `<repo>\t<id>\t<title>` TSV, report-only. Honor `# path:` overrides; LOUD on unreadable repo (no silent `2>/dev/null` swallow, per id:415b).
    2. Wire the count into `/relay next` + the `/relay review` + `relay-doctor.sh` (id:9bec) report so a closed-ROADMAP-but-open-TODO repo surfaces "N un-promoted TODO items — needs a handoff pass" INSTEAD of "drained / nothing to do." `/relay next`'s route-1/2/3 ladder gains a pre-check: open un-promoted TODO ids ⇒ route to **handoff** (promotion), not "human/idle."
    3. Distinguish genuinely-not-yet-actionable backlog (meeting topics, blocked-on-dep) from promotable executable work — when the lane is ambiguous (untagged), SURFACE for the strong turn to triage (handoff C2), never auto-promote with a guessed lane.
  - **Spec / red test**: `tests/test_unpromoted_scan.sh` (`# roadmap:2dea`) — hermetic: a fixture repo with (a) a closed ROADMAP + an open untagged TODO id with no twin → reported; (b) an open TODO id WITH a ROADMAP twin → clean; (c) a meeting-lane/blocked TODO → reported as "surface, not auto-promote". RED until the scanner + wiring land.
  - **Done-check**: tick + `make test` green; dogfood `relay-doctor.sh --all` shows the new line; a `/relay next` on a closed-ROADMAP/open-TODO repo routes to handoff.
  - **Context**: `meeting/orphan-scan.sh` (cross-ledger sibling), `relay/scripts/relay-doctor.sh` (id:9bec), `relay/SKILL.md` `## Next mode` (the route ladder), the d9b0 design note (ROADMAP ~142.1). Relates to id:2840 (derived ledger index models one-id-two-scope-rows natively — the eventual durable home) + id:3947 (cross-repo dead-letter routing, sibling class). Deps: none to start. **Filed as a ROADMAP item, not TODO-only — that IS the lesson.**
- [x] [ROUTINE] `relay-doctor.sh` — report-only relay-machinery health aggregator (cheap-first-slice of id:0907) <!-- id:9bec -->
  - **Why**: aggregates the already-built mechanical checks into one report so latent relay-plumbing defects don't depend on a human noticing (the 2026-06-23 six-defect session). Decided 2026-06-24 (`docs/meeting-notes/2026-06-24-1631-relay-doctor-scope.md`); its gate (id:09a3/69ef/000d) is met.
  - **Acceptance**: `relay/scripts/relay-doctor.sh` CALLS (never reimplements) orphan-scan.sh --cross-ledger, roadmap-lint.sh, the id:69ef refs-install check, relay-reconcile.sh --all; scope = cwd-default / `<dir>` / `--all` (relay.toml own); REPORT-ONLY (exit 0 with findings, only misuse exits nonzero); LISTS not-yet-wired checks (id:e149 claim-staleness, id:c3a6 discover-sig) for honest coverage (D4). `tests/test_relay_demote_guard_hard_pool.sh`… → `tests/test_relay_doctor.sh` (`# roadmap:9bec`) green; full suite green. (Dogfood: on first run it caught a real id:9973 TODO↔ROADMAP drift, now fixed.)
- [x] [ROUTINE] relay-doctor front-door wiring — `/relay health` mode + a `/relay review` sub-step surfacing findings to REVIEW_ME (never a hard block); child of id:0907 (D1), DEP id:9bec <!-- id:3eb5 -->
- [x] [ROUTINE] relay-doctor `--strict` (opt-in nonzero gate) + quota-config sanity check (RELAY_QUOTA_DECAY_7D direction, threshold bounds); child of id:0907 (D3/D4), DEP id:9bec <!-- id:a883 -->
- [x] [ROUTINE] Fix `orphan-scan.sh --cross-ledger` false-positive — it must correlate ONLY the line bearing `<!-- id:XXXX -->` (exact token), not a prose/substring match <!-- id:9221 -->
  - **Why**: dogfooding `relay-doctor.sh --all` (id:9bec) surfaced `id:f4a7 — TODO:[x] ROADMAP:[ ]` in isochrone, but f4a7's token line is `- [ ]` in BOTH ledgers (id also appears in prose on 3 `f4a7-A/B/C` child lines, all `[ ]`); `id:601e` in the same repo is reported correctly. So the cross-ledger check mis-attributes a checkbox to an id whose own token line agrees. This is the interim drift backstop id:2840 relies on + a relay-doctor input — phantom drift erodes trust in both.
  - **Acceptance**: hermetic test — (a) id whose `<!-- id:XXXX -->` lines AGREE but whose id is mentioned in prose on other (differently-checkboxed or same) lines → reported CLEAN; (b) genuine token-line disagreement → reported DRIFT. orphan-scan keys strictly on the token-bearing line.
  - **Done-check**: tick + `make test` green.
- [x] [HARD — pool] Workflow-script template-literal lint — catch unescaped backticks inside template literals before they reach the live Workflow parser (and fix any existing) (done 2026-06-24, relay HARD child id:da26) <!-- id:71f2 -->
  - **Why** (observed 2026-06-24): the id:9973 demote-guard edit added backtick-wrapped `` `hard` `` twice inside `relay-loop.js`'s `shardPrompt` template literal WITHOUT escaping the backticks (lines 763, 822). `node --check` AND `make test` both TOLERATED it, but the Workflow tool's stricter template-literal parser rejected the entire script (`Unexpected token (763:1527)`), so `/relay --afk` could not launch the pool at all (fixed ad-hoc in commit 178b8db). The lesson: `node --check` is NOT a sufficient gate — the live engine crashed on a script `node` accepts. [HARD — pool] because a robust check is parser/lexer-aware (a naive `grep` for backticks false-positives on `//` comments and the already-escaped `` \` `` cases), and it guards the relay engine's own CI surface.
  - **Acceptance**:
    1. A check (`relay/scripts/lint-workflow-templates.{sh,mjs}`) that, for every workflow JS script (`relay/scripts/relay-loop.js` plus any script containing `export const meta` / future `*.workflow.js`), detects a backtick INSIDE a template literal that is neither escaped (`` \` ``) nor the literal's own delimiter — via a real lexer pass that distinguishes template-literal context from `//` + `/* */` comments and ordinary `'`/`"` strings (NOT a line grep). It FAILS loudly (nonzero exit + offending `file:line`) on a violation.
    2. Wired into `make test` via `tests/test_workflow_template_lint.sh` so the suite goes RED on any reintroduction.
    3. Run against the current tree; fix any existing violation (none expected post-178b8db — verify). The cosmetic `` \`hard\` `` the ad-hoc fix left in a `//` comment at `relay-loop.js:419` is exempt (comments are not template literals) — the linter must NOT flag it.
  - **Spec / red test**: `tests/test_workflow_template_lint.sh` (`# roadmap:71f2`) — hermetic: a fixture script with an unescaped backtick inside a template literal → linter exits nonzero naming the line; a fixture with only escaped backticks + backticks inside comments/strings → exits zero. RED until the linter lands.
  - **Done 2026-06-24** (relay HARD child, id:da26): new `relay/scripts/lint-workflow-templates.mjs` — a single-pass CHARACTER LEXER (stdlib node, no deps) that tracks JS context (code / line-comment / block-comment / `'…'` / `"…"` / `` `…` `` template with `${…}` substitution nesting, AND regex literals `/…/` so a `/'/g` quote can't desync the string lexer) and flags ONLY an unescaped backtick that, in template-literal content, is immediately followed by an identifier char (`[A-Za-z0-9_$]`) — the `` `hard`` desync signature. Escaped `` \` ``, backticks in comments/strings, and `${…}` interpolation are all in the wrong lexer state and never reach the rule (the false-positive class a line grep can't avoid). Reproduced the original defect: ran against commit 178b8db^'s relay-loop.js → flags exactly lines 763 + 822 (`node --check` passed on that same file); current tree lints CLEAN. Targets `relay-loop.js` + any `relay/scripts/*.{js,mjs}` containing `export const meta` or named `*.workflow.js`; usage `lint-workflow-templates.mjs [file|repo-root …]`, exit 0 clean / 1 violation (`file:line:col`) / 2 misuse. Added to `relay_FILES`/`relay_EXEC`/`relay_ALLOW`/`relay_LOCAL` (id:69ef install-completeness). Spec `tests/test_workflow_template_lint.sh` (`# roadmap:71f2`) green; full suite green. The cosmetic `` \`hard\` `` in the `relay-loop.js:419` comment is correctly NOT flagged (comment state). Follow-up (not blocking): the linter is not yet wired into `make test` as a standalone target nor into `relay-doctor.sh` — the test invokes it directly; a `/relay review` wiring step can fold it into the health aggregator (id:0907 family).
- [x] [HARD — pool] `/relay stop` — first-class graceful (patient) operator wind-down for a running pool (no orphaning) <!-- id:c012 -->
  - **Why**: the self-feeding loop ended only on quota cap / 2 dry discoveries / `MAX_ROUNDS`, or a hard `TaskStop` that kills in-flight children + parks worktrees as `relay/orphan/*`. No VOLUNTARY "finish the current batch, don't re-discover, stop clean" signal existed (observed 2026-06-22 + 2026-06-24). Merged former id:3b1e (patient stop / `--once`) into this id. [HARD — pool] because it edits `relay-loop.js`'s live Workflow engine — the class the pool crashed on 3× (id:e37b).
  - **Acceptance**: (1) STOP sentinel at `STOP_PATH` (`~/.config/relay/STOP`, override `args.STOP_PATH`/`RELAY_STOP_PATH`) checked by the `discover-prelude` (the only actor with shell/FS each round) — content = integer "rounds remaining before stop" (empty/≤0 = stop now; `--after N` = N), prelude decrements N→N-1 and **consumes (rm)** on fire, returning `stopRequested` (added to `PRELUDE_SCHEMA`). (2) `runRound` short-circuits on `prelude.stopRequested === true` (strict, fail-safe — a dead prelude never stops): sets `stopReason='user-stop'`, returns a `userStop` marker WITHOUT dispatching a new wave (prior wave + integration debt already drained). (3) Outer loop breaks on `r.userStop` AND on the launch-time round cap `STOP_AFTER_ROUNDS` (`--once` = 1, `--after N` = N), both → `stopReason='user-stop'`. (4) `buildStopReasonLine` glosses `user-stop`. (5) SKILL.md `## Stop mode` documents `/relay stop`, `/relay stop --after N`, `/relay stop --now` (hard `TaskStop` path), `--once`, and the knobs table rows.
  - **Spec / red test**: `tests/test_relay_graceful_stop.sh` (`# roadmap:c012`) — static-structural over `relay-loop.js` + `SKILL.md` (the pool can't exercise the live Workflow), plus `node --check` and the Workflow-forbidden-API guard. Green.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] First-class per-run `--priority` / `--exclude` pool args — no relay.toml mutation, no `inject.sh` abuse <!-- id:d530 -->
  - **Acceptance**: `relay-loop.js` reads `args.excludeRepos` / `args.priorityRepos`. EXCLUDE drops those repos from the own-repo list BEFORE sharding (no unit emitted) + adds each to the `skipped` rollup `excluded for this run (--exclude)`; no relay.toml write. PRIORITY is a per-run ORDERING bump in the unit sort comparators — ahead of non-priority units WITHIN the same verdict class, above `income`, below injected-unit precedence + the D3 verdict-class order (never a verdict override, never a created/injected unit → can't double-dispatch, the id:d530 finding). Unknown/unconfirmed repo names are a LOUD reject (surfaced), never silent. Logic factored into the PURE helper `relay/scripts/pool-args.mjs` (byte-equivalent inline copies in `relay-loop.js`, pinned by a structural test, per the `redispatch-guard.mjs` precedent). SKILL.md front door documents both flags (run-scoped, never write relay.toml) + maps the natural-language forms onto `args.priorityRepos`/`args.excludeRepos`. `tests/test_relay_pool_args.sh` (`# roadmap:d530`) green; full suite green.
- [x] [ROUTINE] Deterministic `is_finished` guard — stop the classifier false-dispatching handoff/hard on finished repos <!-- id:000d -->
  - **Why** (incident 2026-06-23, run relay-20260623-083216): with the quota false-stop fixed (id:1d64) the pool ran longer and reached the lowest-priority `handoff` tier, where the LLM shard emitted `handoff`/`hard` verdicts for FINISHED repos (recurheb/echoAI/collaib — ROADMAP all `[x]`, 0 open items, clean tree, no unaudited commits). Children correctly no-op + auto-reap, but each burns a strong/opus dispatch; left unchecked it churns across rounds. **CONFIRMED not a discover-sig bug** (it hashes full ROADMAP content — checkbox flips invalidate correctly) and not a gather-state bug (it strips done `[x]` blocks). The shard over-applies `handoff` (whose definition requires "untracked new work exists") to a repo that should classify `idle`. Mechanize the judgment (id:415b: guard arguable LLM judgment with a deterministic check).
  - **Acceptance**:
    1. `relay/scripts/gather-repo-state.sh` emits a new bool field **`is_finished`** = `roadmap` is present/non-empty AND has ZERO open `- [ ]` items (after the existing open-item trim) AND `commits_since_ckpt` is empty AND `dirty` is false (the existing `dirty_lock_only` exemption still counts as not-finished-blocking → treat lock-only dirty as clean for this flag). A repo with NO roadmap stays `is_finished=false` (genuine first `handoff`). Add it through the existing `emit()` positional→env→JSON path.
    2. `relay/scripts/relay-loop.js` classifier consumes it as a **demote-only guard**: when `is_finished` is true, the repo is NEVER a `units` entry of verdict execute/hard/handoff — it goes to `surfaced` with reason `finished repo (0 open items, clean, no unaudited commits) — not dispatched (anti-false-handoff guard id:000d)`. The guard may only DEMOTE to idle/surfaced, never invent work; `review` is unaffected (review requires commits_since_ckpt, which makes is_finished false anyway).
  - **Spec / red test**: `tests/test_gather_is_finished.sh` (`# roadmap:000d`) — hermetic, reuses the shard-canary fixtures: idle→is_finished true; review/dirty/hard-gated/non-git→false. RED until gather emits the field. Also add a structural assertion to `tests/test_relay_loop_structure.sh` that the is_finished demote-guard is present in relay-loop.js.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] Deterministic HARD-pool demote-guard — stop the shard false-dispatching `hard` on a repo with NO open `[HARD — pool]` item <!-- id:9973 -->
  - **Why** (observed 2026-06-24): the discover-shard's `hard` verdict is an LLM judgment of whether an executable `[HARD — pool]` item exists, but only `[HARD — pool]` items are pool-dispatchable (`relay/references/hard-lanes.md`) — `[HARD — meeting]`/`[HARD — decision gate]`/`[HARD — hands]` are NOT. The judgment is non-deterministic: two repos whose only open HARD item was `[HARD — decision gate]` were wrongly classified `hard` and handed back as pre-start size-outs (burning Opus), though an earlier run that session correctly surfaced them as gated. Mechanize the judgment (id:415b) with a deterministic check, mirroring the id:000d `is_finished` guard.
  - **Acceptance**:
    1. `relay/scripts/gather-repo-state.sh` emits a new number field **`open_hard_pool`** = the count of open `- [ ]` ROADMAP items whose lane tag is exactly `[HARD — pool]`, EXCLUDING a `<!-- relay:recurring-audit -->`-marked item that has nothing to audit this round (reuse the id:365b `substantive_unaudited` logic — a vacuous recurring audit is not an executable pool item). Added through the existing `emit()` positional→env→JSON path. A repo with no roadmap / no pool-lane item stays `open_hard_pool=0`.
    2. `relay/scripts/relay-loop.js` consumes it as a **demote-only guard** (after the shard merge, alongside the id:000d guard): when a unit's verdict is `hard` and that repo's `open_hard_pool == 0`, DEMOTE it — remove from `units`, push to `surfaced` with reason `HARD backlog is gated — no open [HARD — pool] item (only meeting/hands/decision-gate lanes); not dispatched (deterministic demote-guard id:9973)`. DEMOTE-ONLY (only toward surfaced); injected units (`unit.injected`) are EXEMPT; `review`/`execute`/`handoff` untouched. The value reaches the unit via the DISCOVER_SCHEMA field + a shard-prompt copy-verbatim instruction (same wiring discipline as id:401c's is_finished fix).
  - **Workflow-sandbox constraint**: the JS guard is pure logic over already-gathered data — no `Date`/`process`/`require`/`fs`/`Math.random` (they crash the pool); `node --check` + `tests/test_relay_no_date_api.sh` stay green.
  - **Spec / red test**: `tests/test_relay_demote_guard_hard_pool.sh` (`# roadmap:9973`) — hermetic, static-structural: (a) gather emits `open_hard_pool` counting ONLY open `[HARD — pool]` items (decision-gate+hands→0; one pool→1; done [x]→0; vacuous recurring-audit→0); (b) relay-loop.js has the demote-guard wiring (hard + open_hard_pool==0 → surfaced, injected-exempt, demote-only). RED until both halves land.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] Relay: decouple --afk from intensive — --afk stays non-intensive, --intensive opts in (implies --afk) [ROUTINE] <!-- id:052c -->
  - **Why** (user 2026-06-23): auto-running OOM-risky `[INTENSIVE]` work *because* the user stepped away is backwards ([[oom-local-model-session-kills]]). `--afk` = unattended but SAFE; `--intensive` (synonym `--allow-intensive`) is the explicit opt-in and IMPLIES `--afk`.
  - **Acceptance**: `relay-loop.js` `ALLOW_INTENSIVE = !!A.allowIntensive` (no longer `|| A.afk`); the front door sets `args.allowIntensive` ONLY for `--intensive`/`--allow-intensive`, never a bare `--afk`; SKILL.md splits the two knob rows; skip messages say "needs --intensive"; `tests/test_relay_intensive.sh` asserts the decoupling. Suite green.
- [x] Relay intensive-emit human-gate carve-out — don't auto-dispatch a human-gated [INTENSIVE] item [ROUTINE] <!-- id:a707 -->
  - **Why** (incident 2026-06-23): with `--afk`, the id:ad74 INTENSIVE-EMIT-GUARD force-emitted a zomni `[HARD — hands] [INTENSIVE — local-llm]` GGUF-cleanup unit; it was dispatched but un-doable (needs live GPU/sudo) — [INTENSIVE] is an orthogonal resource axis (id:78ff), not an executor-eligibility override.
  - **Acceptance**: `gather-repo-state.sh` `top_intensive` is the resource of the top open [INTENSIVE] item that is NOT human-gated (`[HARD — hands]`/`[HARD — meeting]`/`[HARD — decision gate]`/`@manual`), "" when the only open [INTENSIVE] items are human-gated; the shard INTENSIVE-EMIT-GUARD prose carries the carve-out; `tests/test_intensive_human_gate.sh` green.
- [x] Relay anti-spin: recurring-audit gate + re-dispatch circuit breaker [ROUTINE] <!-- id:365b -->
  - **Why** (incident 2026-06-23, run relay-20260623-172446): the recurring strong-model audit (id:401c) never closes by design; once dotclaude-skills drained all other work it became the only open pool-dispatchable item, so the `hard` verdict re-selected it EVERY round, auditing only its own prior `relay: checkpoint` commit ("clean by vacuity") — ~13 vacuous rounds drove the 5h quota 98%→41% for zero output (the checkpoint churn also defeated the discover-sig cache). See TODO id:365b.
  - **Acceptance**: (1) `gather-repo-state.sh` emits `substantive_unaudited` (bool, FAIL-OPEN true — false iff every commit since the audit ref `last_strong_ckpt`/latest ckpt is a `relay:/fable: checkpoint` or uv.lock-only) and `work_sig` (string, stable across the pool's own checkpoint churn, changes when an item closes or a substantive commit lands). (2) Mechanism 1: id:401c carries a `<!-- relay:recurring-audit -->` marker; the discover-shard EXECUTABLE-HARD test excludes a marked item from `hard`/`openHard` when `substantive_unaudited` is false, surfacing "recurring audit idle …". (3) Mechanism 2: a deterministic JS circuit breaker (`redispatchGuard` + the pure helper `redispatch-guard.mjs`) suppresses any non-injected (repo,verdict) unit dispatched >3× in one run with an unchanged `work_sig`; injected units exempt; resets on a work_sig change.
  - **Spec / red tests**: `tests/test_recurring_audit_gate.sh` + `tests/test_redispatch_circuit_breaker.sh` (both `# roadmap:365b`). RED until implemented.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] Margin-aware quota-stop staleness — stop false-stopping a healthy pool when the cache is stale + unrefreshable <!-- id:1d64 --> (done 2026-06-23, executor)
  - **Why** (incident 2026-06-23, run relay-20260623-070136): the pool stopped with `stopReason=quota-stale-cache` at five_hour=**7%** / seven_day=**38%** / seven_day_sonnet=**25%** vs a 90% threshold — huge headroom. `quota-stop.sh`'s staleness fail-safe is MARGIN-BLIND: when the cache is older than `STALE_SECS` and the self-refresh fails (the `/api/oauth/usage` endpoint 429s aggressively — documented statusline gotcha; nothing keeps the cache fresh during an unattended `--afk` run), it does an UNCONDITIONAL `exit 2` (stop) regardless of the last-known reading. A stale reading is only dangerous if we might have CROSSED the threshold since it was taken. Same false-stop family the SKILL warns about for `RELAY_QUOTA_DECAY_7D`.
  - **Acceptance**: in the stale-path of `relay/scripts/quota-stop.sh`, replace the post-refresh-failure unconditional `exit 2` (~L82) with a margin check: if EVERY checked bucket for the tier has last-known util < (its `bucket_threshold`×100 − MARGIN), log `proceeding on stale-but-safe cache` and fall through to the normal `check_key` loop (→ exit 0); if any checked bucket is within MARGIN of its threshold OR missing, keep `exit 2`. `MARGIN = RELAY_QUOTA_STALE_MARGIN` points, **default 30**. A genuinely MISSING cache file still exits 2 (blind). No change to the seatbelt, the fresh-cache path, or the self-refresh attempt itself.
  - **Spec / red test**: `tests/test_quota_stop_stale_margin.sh` (`# roadmap:1d64`) — hermetic (temp cache aged past STALE_SECS + tokenless creds so refresh is skipped): stale+low-util → exit 0; stale+near-threshold bucket → exit 2; missing cache → exit 2; fresh+low-util → exit 0. RED until implemented.
  - **Done-check**: tick this checkbox, then `make test` fully green.
  - **Secondary (optional, NOT this item):** `quota-stop` should respect the existing `/tmp/claude-usage-backoff` instead of re-hitting the 429'd endpoint, and reuse the statusline's cache rather than competing for the token's ~5-req budget. Split to a follow-up if pursued.
- [x] [ROUTINE] Cheap quota PRE-GATE before the per-round discovery fan-out — don't spend N shards on a round that immediately quota-stops <!-- id:5c00 -->
  - **Why** (observed 2026-06-25, run relay-20260625-225111, `/relay --afk . --quota-7d 50`): round 1 ran the **DISCOVER_SHARDS fan-out (5 agents, ~94k tokens)** and only THEN hit the quota gate → `stopReason=quota-stale-cache`, 0 units dispatched. The stop itself was CORRECT (id:1d64 margin-aware fail-safe: 44% 7d-used vs a 50% cap = 6pt headroom < 30pt MARGIN under a stale cache), but the **ordering wasted the whole discovery wave** — the gate runs after the tokens are already spent. User: "what's the point of discover/shards before the quota check killing those discoveries?"
  - **Acceptance**: in `relay/scripts/relay-loop.js`, run the `quota-stop.sh` gate (or a cheap inline last-known-cache margin check) at the TOP of `runRound()` — BEFORE the `discover-prelude` + the DISCOVER_SHARDS fan-out — so a round that will stop returns immediately with the correct `stopReason` and **zero discovery agents**. The once-only prelude global work (runId, inject.take) and the per-round shard fan-out both move *after* the pre-gate. Keep the existing post-discovery/ pre-dispatch gate too (quota can cross mid-round); this just adds an early-exit. Round 1's pre-gate uses the existing cache (no extra refresh).
  - **Spec / red test**: `tests/test_relay_loop_structure.sh` (extend, `# roadmap:5c00`) — assert the round body calls the quota gate before the discovery fan-out (grep ordering in `runRound`), and a mocked over-threshold gate yields `rounds:0`-style early return with no shard dispatch.
  - **Done-check**: tick + `make test` green; a dry-run with a forced over-threshold cache dispatches 0 discovery shards.
  - **Context**: `relay/scripts/relay-loop.js` (`runRound`, the discover-prelude + shard fan-out ordering), `relay/scripts/quota-stop.sh`. Relates id:1d64 (the stale-cache margin fix — correct, but fires too late in the round). Deps: none.
- [x] [ROUTINE] Sync relay-loop.js classifier to the canonical `[HARD — pool]` lane token (close the id:78ff drift) <!-- id:3c0f -->
  - **Why** (audit 2026-06-23): id:78ff made `[HARD — pool]` the single canonical lane token (`hard-lanes.md`, `gather-human-backlog.sh`, project_manager `scan.py`) and back-filled this repo's only pool-executable HARD item (id:401c) to `[HARD — pool]` — but left `relay/scripts/relay-loop.js` keyed on the OLD bare `[HARD — strong model]`. Consequence: a `[HARD — pool]` item is HIDDEN from `/relay human` ("the pool runs it") yet the loop's EXECUTABLE-HARD test / `openHard` count / hard-child dispatch prompt look for a DIFFERENT literal, so the pool can compute `openHard=0` and never emit a `hard` verdict → the item falls in the crack between loop and human = **drained pool despite open work**. Latent landmine: `gather` LOUD-rejects `[HARD — strong model]` as untagged, so any own-repo using the loop's token would break `/relay human`.
  - **Acceptance**: in `relay-loop.js`, replace every operative `[HARD — strong model]` with the canonical `[HARD — pool]` (the verdict definition ~L623, the EXECUTABLE-HARD test ~L626, the `openHard` definition ~L661, the hard-child dispatch prompt ~L913, and the comment ~L304-305). The progress-meta title (L8) is already `[HARD — pool]` — leave it. NO behavioural change beyond the token; do not touch the EXECUTABLE-HARD gate logic.
  - **Spec / red test**: `tests/test_relay_loop_hard_token.sh` (`# roadmap:3c0f`) — static: asserts relay-loop.js carries NO `HARD — strong model` token, DOES reference `[HARD — pool]`, and that token is defined in `hard-lanes.md` (consumers cannot drift again). RED until synced.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] Add `references/hard-lanes.md` to the Makefile install manifest + guard every reference doc <!-- id:69ef -->
  - **Why** (audit 2026-06-23): `relay_FILES` in the Makefile is an EXPLICIT list, not a glob; `relay/references/hard-lanes.md` (added by id:78ff) was never added, so `make install-relay` does NOT symlink it into `~/.claude/skills/relay/references/` — it 404s at the install path while `gather-human-backlog.sh` error messages + `human.md` point readers to it. Generalize: a new reference doc must never be silently left un-installed.
  - **Acceptance**: add `references/hard-lanes.md` to `relay_FILES`; then `make install-relay` (the human/strong turn re-runs the live install once it lands). The test below guards that EVERY `relay/references/*.md` is in the manifest.
  - **Spec / red test**: `tests/test_relay_refs_install_complete.sh` (`# roadmap:69ef`) — static: asserts every `relay/references/*.md` appears in `relay_FILES`. RED until the Makefile line is added.
  - **Done-check**: tick this checkbox, then `make test` fully green.
  - **Note**: this item is itself `[HARD — pool]`, so the pool can only DISPATCH it once id:3c0f lands (the loop must recognize `[HARD — pool]`). id:3c0f is `[ROUTINE]` and pool-executable now → it self-bootstraps this one. Until then, build it via `/relay human` (hard_pool surface) or a manual strong turn.
- [x] [HARD — pool] `roadmap-lint.sh` — a GRAMMAR validator that LOUD-rejects any open ROADMAP item not matching the proper syntax; wire into `review` + `human` (done 2026-06-23, relay HARD child) <!-- id:09a3 -->
  - **Done 2026-06-23** (relay HARD child, id:da26): new `relay/scripts/roadmap-lint.sh [roadmap|repo-root]` (`set -euo pipefail`; defaults to cwd-repo ROADMAP.md; short stdout, details to `~/.claude/logs/relay-roadmap-lint.log`). POSITIVE grammar: an open top-level `- [ ]` item under an ACTIVE section must carry (1) a recognized class/lane tag — `[ROUTINE]` OR a `hard-lanes.md` lane (`[HARD — pool|meeting|hands|decision gate]`, optionally `[INTENSIVE — …]`) — AND (2) a 4-hex `id:` token; reports EVERY violation generically (offending line + id + which clause failed) and exits nonzero; a conforming ROADMAP is a clean zero-exit no-op. Lane vocabulary is READ from `hard-lanes.md` (single source — no second copy; fail-safe fallback if the doc is unreadable). Closed `[x]`, indented continuation lines, and gated/deferred/done/icebox/archive/parked sections are EXEMPT. Does NOT auto-rewrite — surfaces for the strong/human turn (id:78ff precedent). Wired into `references/review.md` §5 (runs on cwd repo, surfaces in return report) and `references/human.md` §2 (runs across own repos alongside gather). Added to `relay_FILES`/`relay_EXEC`/`relay_ALLOW` in the Makefile (id:69ef install-completeness precedent). Spec `tests/test_roadmap_lint.sh` (roadmap:09a3) green; live ROADMAP lints clean.
  - **Why** (audit 2026-06-23, user directive): instead of detecting a fixed list of SPECIFIC known issues, the relay should reject ANYTHING that doesn't match the proper open-item syntax (a positive grammar — extends 415b grammar-tightening-with-loud-rejection). `gather` already LOUD-rejects an untagged `[HARD]`, but is blind to (a) an open `- [ ]` item with NO class tag at all (e.g. meeting-rpg id:0951, a `[SEVERE]` item with no relay lane — invisible to BOTH the loop AND `/relay human`) and (b) a malformed/unknown lane outside the `[HARD]` family (e.g. truncocraft id:9a98 `[HARD — epic, post-MVP]`). A grammar catches every deviation, not just the ones we thought to look for.
  - **The grammar** (an open `- [ ]` item under an ACTIVE section must match ALL of): (1) a recognized class/lane tag — `[ROUTINE]` OR a `hard-lanes.md` lane (`[HARD — pool|meeting|hands|decision gate]`), optionally combined with `[INTENSIVE — <resource>]`; (2) an `id:XXXX` (4-hex) token. Items under a GATED / DEFERRED / DONE / ICEBOX / ARCHIVE heading are EXEMPT (explicitly parked). Closed `- [x]` items are never linted. Read the recognized lane set from `hard-lanes.md` (single source of truth — no second copy of the vocabulary).
  - **Acceptance**: new `relay/scripts/roadmap-lint.sh [roadmap-path | repo-root]` (`set -euo pipefail`; defaults to the cwd repo's `ROADMAP.md`; short stdout, details to `~/.claude/logs/`). Reports EVERY non-conforming active open item GENERICALLY (the offending line + id if present + which grammar clause failed) and exits nonzero when any are found; a fully conforming ROADMAP is a clean zero-exit no-op. Then wire it in: `references/review.md` §5 (re-derive ROADMAP) runs it on the cwd repo and surfaces violations in the return report; `references/human.md` §2 (collect) runs it across own repos alongside `gather`. Do NOT auto-rewrite items — surface for the strong/human turn to assign the lane (mirrors id:78ff's "back-fill belongs to each repo's next handoff/review/human" precedent).
  - **Spec / red test**: `tests/test_roadmap_lint.sh` (`# roadmap:09a3`) — hermetic fixture with one conforming item per class, a missing-class item, an unrecognized-lane item, a missing-id item, a gated-section exempt item, and a done item; asserts the three active violations are each reported, the conforming/exempt/done items are NOT, and a clean fixture exits zero. RED until the script exists + is wired in.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] Discover-shard must treat an open `[INTENSIVE — <res>]` item as WORK, never classify the repo idle <!-- id:ad74 -->
  - **Why** (observed 2026-06-23, run relay-20260623-112409, `/relay --afk`): ai-codebench had an open `[INTENSIVE — local-llm]` item (id:244b, ~15 model runs pending) and the run set `allowIntensive=true`, yet the discover-shard classified the repo `idle — in sync, no open work` and never emitted an intensive-tagged unit, so `relay-loop.js`'s INTENSIVE partition (~L877, `ALLOW_INTENSIVE ? intensiveUnits : intensiveDeferred`) never received a unit → the user's overnight ai-codebench drain (id:244b/8bea) was blocked. **Not a gather bug** (`gather-repo-state.sh --repo ai-codebench` correctly emits `is_finished=false` + the open `[INTENSIVE]` box + id:244b — verified this session). **Root cause = shard JUDGMENT**: the shard never sees the `--afk`/`allowIntensive` flag (it is a JS-level dispatch decision), and the repo's own ROADMAP convention prose ("a session finding only `[INTENSIVE]` items open reports 'no executor-eligible work' and stops" — written for generic/remote executors with no GPU) is read literally and reported as idle, short-circuiting the intended design (always emit an intensive unit; let the loop decide dispatch by `ALLOW_INTENSIVE`). This is the symmetric PROMOTE counterpart to the id:000d is_finished DEMOTE guard, and uses the same mechanize-the-judgment + JS-side-backstop pattern (id:415b).
  - **Acceptance**:
    1. **Shard-prompt instruction** (`relay/scripts/relay-loop.js`, the precedence/intensive block ~L644-679): add an explicit rule that an open `- [ ]` item carrying an `[INTENSIVE — <resource>]` modifier is ALWAYS executor-eligible WORK — the repo MUST emit a `units` entry with `intensive` set (parse the resource per the existing id:8d52 rule ~L674), and MUST NOT be classified `idle`/`skipped` on the strength of any repo-local "reports no executor-eligible work" convention prose. The auto-run-vs-defer decision stays with `relay-loop.js` (the existing INTENSIVE partition already surfaces deferred units as skipped when `!ALLOW_INTENSIVE`). The same `--afk`-blind reasoning as id:000d applies: a repo-local convention must not override the shard's emit.
    2. **JS-side backstop** (mirror the id:000d demote guard ~L722): after shard results are merged, a repo whose gathered state shows an open `[INTENSIVE — <res>]` item (carry the resource through `gather-repo-state.sh` / the DISCOVER_SCHEMA the same way `is_finished` is carried — a new `top_intensive` STRING field, empty when none) MUST NOT remain in `idle`/`skipped` with no unit; if the shard idled it, PROMOTE it to a `units` entry with `intensive` set (a PROMOTE-only guard — it may only move a repo toward a dispatch verdict for the intensive resource, never demote). This makes a shard that ignores instruction 1 self-correcting, exactly as id:000d's JS backstop corrects an over-classifying shard.
  - **Spec / red test**: `tests/test_relay_loop_intensive_emit.sh` (`# roadmap:ad74`) — static, hermetic: asserts (a) the shard prompt in `relay-loop.js` instructs that an open `[INTENSIVE]` item is never idle (a grep for the new rule marker, e.g. `id:ad74`), (b) the DISCOVER_SCHEMA declares the carried intensive field (`top_intensive: { type: 'string' }`), (c) a JS-side `[INTENSIVE] promote` backstop block referencing `id:ad74` is present, and (d) `gather-repo-state.sh` emits `top_intensive` (the resource of the top open `[INTENSIVE — <res>]` item, "" when none). Model on `tests/test_relay_loop_structure.sh` §id:000d/401c. RED until both halves land.
  - **Done-check**: tick this checkbox, then `make test` fully green.
  - **Note**: add an INTENSIVE-only fixture to the shard-canary corpus (`tests/shard-canary/intensive-only/` → expected a `units` intensive verdict, NOT idle) when the corpus is next exercised — non-blocking for this item (the canary harness is token-gated, not in the default sweep). Distinct from id:000d (the inverse: false-DISPATCH on FINISHED repos); a natural check to fold into the relay-health report id:0907.
- [x] [ROUTINE] relay-loop progress buckets — split the crowded `Dispatch` /workflows group into per-verdict phases (Execute/Review/Hard/Handoff) + a `Support` bucket for non-work agents (quota gate, lease release, inject-take) (done 2026-06-22, user request; display-only, zero behavioural change; `tests/test_relay_loop_structure.sh` locks the routing) <!-- id:7d1e -->
- [x] [ROUTINE] Relay ROADMAP archiver — `relay/scripts/roadmap-archive.sh` moves done `[x]` items out of the live ROADMAP <!-- id:6b67 -->
  - **Why**: a large ROADMAP overflows the executor-contract prompt → "Prompt is too long" blocks ALL execute/INTENSIVE dispatch on that repo (id:93cc, hit live 2026-06-22 on ai-codebench's ~400-line ROADMAP). Keep the live ROADMAP to OPEN items by archiving completed ones, mirroring how `todo-update/archive-done.sh` keeps TODO.md small.
  - **Acceptance**:
    - New `relay/scripts/roadmap-archive.sh [repo-root]` (defaults to `git rev-parse --show-toplevel`); `set -euo pipefail`; short stdout, details to `~/.claude/logs/`.
    - Moves each fully-done item — a top-level `- [x] …` line PLUS all its indented continuation lines (the block up to the next top-level `- [ ]`/`- [x]` or `## ` heading) — from `ROADMAP.md` into `ROADMAP.archive.md` (created if absent, appended newest-last), preserving the `<!-- id:XXXX -->` token and original text verbatim.
    - NEVER touches open `- [ ]` items, `## ` section headers, or the file preamble/conventions block. Headers that become empty are LEFT (no pruning — ROADMAP headers are structural, UNLIKE archive-done.sh).
    - Conservative gate (mirror archive-done.sh): only archive items done in a PRIOR commit (not the working tree) OR carrying a trailing "done YYYY-MM-DD" ≥30 days old — never archive a just-ticked item (so a same-run checkpoint isn't archived before review sees it). Gate must be explicit + tested.
    - Idempotent; flock-guarded on a `*.lock` (fd pattern per `append.sh`/`diary-append.sh`); re-running with nothing to archive is a clean no-op.
  - **Tests**: add `tests/test_roadmap_archive.sh` (`# roadmap:6b67`), hermetic (mktemp; no `~/.claude`/network): multi-line item-block capture, open-item + header preservation, the prior-commit/≥30d gate (NEGATIVE: a working-tree-ticked item is NOT archived), idempotent no-op, token preservation. Tick the checkbox so `make test` is green = done.
  - **Context**: model on `todo-update/archive-done.sh` (date/section logic) but ROADMAP-specific (no section pruning; multi-line blocks). This is fix-direction (b) of id:93cc; the separate (a) "executor contract passes only OPEN items to the child" stays in id:93cc.
- [x] [HARD — hands] Heartbeat liveness on the relay claim/lease — FOUNDATION for id:7809 + id:98f0; build FIRST. Extend the existing id:0902 claim/lease to write `runId` + `heartbeat_ts` + a TTL, with a single staleness-check helper (`heartbeat older than TTL ⇒ prior run died`) consumed by BOTH the auto-reconcile (id:7809) and the watchdog (id:98f0) — one source of truth, no separate `.relayactive` file. Acceptance: a test asserts a stale heartbeat reads "dead", a fresh one "alive". Files: `relay/scripts/claim.sh` (+ `heartbeat.sh` or equivalent) + a test. Design: **TODO id:e149** + `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`. <!-- id:e149 -->
- [x] [HARD — hands] Auto-reconcile-on-restart for the relay loop — DESIGN RESOLVED 2026-06-22 (`docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`): `/relay reconcile --auto` (one code path with the human reconcile) loop-invoked at startup on a STALE heartbeat (id:e149 foundation, extends id:0902 — no new `.relayactive` file); SAFE auto-integrate = clean tree + mechanical `gaming-scan.sh` + full-suite-green + ledger-only/trivial diff; everything else (BLOCKED/partial/red/conflicting/needs-strong-judgment) → parked + surfaced via REVIEW_ME / `/relay human`; conservative classifier defaults to JUDGMENT, never a weaker bar than a human `/relay review`. Design + rationale: **TODO id:7809** (single-id-two-views). Build AFTER id:e149. <!-- id:7809 -->
- [x] [HARD — hands] Outage-resilient LOCAL relay loop — DESIGN RESOLVED 2026-06-22 (`docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`): observe-first. Build a watchdog systemd `--user` timer (modelled on `quota-sample.timer`) that detects a dead loop via the SHARED heartbeat (id:e149) and NOTIFIES for one-tap restart (PushNotification→`notify-send` fallback) — NOT a headless `claude -p`, so it sidesteps the permission wall entirely; its outage-death log is the EVIDENCE GATE to re-open the deferred heavy build (curated allowlist / dedicated-OS-user scoped allowlist = id:2d01). Deferred-out-of-scope until evidence warrants: any `--dangerously-skip-permissions` use, the allowlist treadmill, the OS-user repo-access bridge. Cheap fixes split out: nudge id:bde8, upstream report id:0994. Design + rationale: **TODO id:98f0**. Build AFTER id:e149. (Billing note 2026-06-22: the deferred *heavy* path's headless `claude -p` would-bill-separately overhang is relieved — that Agent-SDK/`claude -p`→dedicated-credit cutover is deferred with advance notice, see memory `anthropic-agent-sdk-billing-deferred` / TODO id:00a5 — but the heavy path stays gated on the permission wall + evidence regardless.) <!-- id:98f0 -->
- [x] [ROUTINE] Fix the misleading `loop-hint.sh`/step-0a "unattended resilience" nudge — correct it to state `/loop`/cron dies WITH the session (resilient only to relay's own early-exit — quota/seatbelt — within a live session, NOT to a session/process kill). Pairs with id:888a/id:8602. Files: `relay/scripts/loop-hint.sh` + SKILL.md step 0a. Design: **TODO id:bde8** + `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`. <!-- id:bde8 -->
- [x] [HARD — hands] File `CronCreate durable:true` no-op upstream — FILED 2026-06-29 → https://github.com/anthropics/claude-code/issues/72238 (reproduced on Claude Code 2.1.195: `{durable:true,recurring:true}` returns `[session-only]`, writes no `~/.claude/scheduled_tasks.json`; the tool description now claims persistence → description↔behavior mismatch). Draft: `docs/upstream-reports/2026-06-29-croncreate-durable-noop.md`. Design: **TODO id:0994** + `docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md`. <!-- id:0994 -->
- [x] [HARD — hands] Fleet-quiescence drain — wind the pool down when all remaining work is gated/finished instead of spinning to MAX_ROUNDS re-confirming an already-drained fleet. SHIPPED 2026-06-29: pure `relay/scripts/drain.mjs` (`unitIsSubstantive` — a confirming-only review that reopened/added nothing is NOT progress; `classifyDrainBacklog` — buckets blocked repos finished/gated/circuit-broken/dirty + names the gated ones with a `/relay human`·`/meeting` pointer), byte-identical inline copies in `relay-loop.js` (dry-detector flips `produced→substantive`; wind-down logs the backlog summary). Subsumes the cwd self-review footgun (a no-op re-review no longer resets `dry`). `tests/test_relay_drain.sh` (`# roadmap:d58f`) — 15 assertions green; full suite green. Design + rationale: **TODO id:d58f**. <!-- id:d58f -->
- [x] [ROUTINE] Finer-grained `/workflows` phase buckets — SHIPPED 2026-06-29: split the two overloaded catch-alls so per-phase counts are meaningful. `meta.phases` + the `agent()` `phase:` opts in `relay-loop.js` now route `discover-shard`→**Classify** (split from the prelude's Discover), `write-relay-status`→**Status** (was flooding Integrate), `gaming-log`/`handback-followup`→**Logging**, `quota`→**Quota**, `release`→**Leases**; Integrate holds only the merge; Support keeps just injection/heartbeat/auto-reconcile. Purely display, zero behavioural change (id:7d1e precedent). `tests/test_relay_phase_buckets.sh` (`# roadmap:7c10`) green; full suite green. Design: **TODO id:7c10** (relates id:7d1e, id:de69). <!-- id:7c10 -->
- [x] [ROUTINE] Surface the ROADMAP/TODO `id:` a relay unit is/was working on — SHIPPED 2026-06-29. (a) dispatch-time label enrichment: a known-at-dispatch item id (injected `--item` or a hard unit's bounded item) is appended to the `/workflows` agent label → `execute:zkm-stt id:09a3`. (b) durable record: `REPORT_SCHEMA` gains `worked_ids` (children return the item id(s) they closed/created/promoted; review falls back to verified-green∪reopened), and the integrator propagates them into the ckpt-tag checkpoint message (`… [id:a,b]`), the RELAY_STATUS "Completed this run" line (`ids=…`), and the `relay-events.jsonl` integrate event — so plain execute/review units (which pick the item INSIDE the child) are traceable post-run. `tests/test_relay_worked_ids.sh` (`# roadmap:de69`) green; full suite green. Design: **TODO id:de69** (relates id:c8b6 events, id:7c10/7d1e display). <!-- id:de69 -->
- [x] [ROUTINE] `/meeting` deferred ledger write-back — breadcrumb + replay-on-next-invocation + log (done 2026-06-22, executor) <!-- id:2c42 -->
  - **Design + rationale: TODO id:2c42** (single-id-two-views) + meeting `docs/meeting-notes/2026-06-22-2139-meeting-worktree-writeback.md` (af04). The 2026-06-22 meeting REJECTED worktree-per-`/meeting` (D2 — inherits id:ca87's non-unionable-checkbox merge problem, contradicts `/meeting`=same-dir→flock + worktrees-are-code-only) and ruled step 2a's deferral is **working as designed** (D1 — no data loss). The only gap: a deferred write-back never auto-completes (it lags the note until the next `--cross-ledger` scan / manual `/todo-update`). Build the self-heal.
  - **Acceptance** (matches the meeting test contract):
    - On a **refused** step-2a claim (deferral), `meeting/SKILL.md` step 2a persists a **generic** `{target_file, helper, payload}` JSON breadcrumb to a gitignored drop path `<root>/.meeting-deferred-writeback.json` AND appends an event to `~/.claude/logs/meeting-deferred-writeback.log`. Payload format generic so it extends if another defer site appears, but WIRED IN only at step 2a (the sole site that defers today — `~/.claude` shared files are flock-safe, no pool there).
    - A **setup-phase replay check** in BOTH `/meeting` setup AND `/todo-update`: applies any pending payload via the named helper (`md-merge.py`/`append.sh`) under a **fresh** `claim.sh acquire`, then clears the drop file. Nothing is applied while the pool still holds the claim (replay re-defers on refusal).
    - Add `.meeting-deferred-writeback.json` to `.gitignore`.
    - **Also (bookkeeping):** add the af04 motivation as a cross-link note on id:3558 (no new structural build — id:3558 covers concurrent CODE writers, orthogonal to the foreground meeting's ledger tick) and record that the literal worktree-per-meeting option was REJECTED by this meeting.
  - **Spec / red test**: `tests/test_meeting_deferred_writeback.sh` (`# roadmap:2c42`) — static-structural (mirrors `test_meeting_claim_hold.sh`): asserts the breadcrumb+log on deferral, the generic payload shape, the replay check (fresh claim, clears drop file) in `/meeting` + `/todo-update`, the still-holds guard, and the gitignore entry. RED until implemented.
  - **Done-check**: tick this checkbox, then `tests/run-tests.sh tests/test_meeting_deferred_writeback.sh` and full `make test` green. Tick the TODO id:2c42 line too (single-id-two-views).
- [x] [ROUTINE] Harden the flaky `test_relay_claim_liveness.sh` (hermeticity under parallel run) (done 2026-06-21, executor) <!-- id:6b91 -->
  - **Bug (observed 2026-06-21, /relay human):** `tests/test_relay_claim_liveness.sh` (roadmap:7570) flakes ~1/run under the **parallel** `tests/run-tests.sh` (1 fail), but passes on re-run and is green in isolation. It claims hermetic (`CLAIM_BASE` in a tmpdir) yet shows cross-test interference under concurrency. The feature (worktree-anchored claim liveness) is genuinely green — this is a TEST hermeticity defect, not a regression. Decision: harden, don't accept-as-known-flaky (a flaky test erodes the suite's signal).
  - **Fix:** identify the actual shared surface first (a default `claim.sh` registry path? a fixed `/tmp` lock the tmpdir `CLAIM_BASE` doesn't cover?), then give the test a fully private claim root per test process and/or serialize the claim tests if they share state the runner can't isolate.
  - **Acceptance:** `test_relay_claim_liveness.sh` passes across ≥20 consecutive full **parallel** `tests/run-tests.sh` runs (no intermittent fail); the leaking shared surface is documented in the fix commit.
- [x] [ROUTINE] Mechanize the TODO↔ROADMAP seam (promotion-tracking + derived count) (done 2026-06-21, executor; residual count-line derive-or-drop split to TODO id:1de1, gated on id:2840, 2026-06-22) <!-- id:d9b0 -->
  - **Design + rationale: TODO id:d9b0** (single-id-two-views). The split stays (TODO=why, ROADMAP=now); mechanize the hand-done SYNC. Three gaps that bit 2026-06-21:
    1. **Promotion-tracking:** add a check (extend `meeting/orphan-scan.sh` or `todo-update/`) that flags a TODO item carrying an executable lane (`[ROUTINE]`/`[HARD — pool]`) whose `id:` has NO twin in that repo's ROADMAP → "un-promoted, pool-invisible" (id:78ff was filed TODO-only and the pool couldn't see it).
    2. **Derived count:** the `Relay: N open ROADMAP items` TODO summary (id:d5e0 here, id:d1dc in project_manager) is hand-maintained prose the id:401c audit keeps re-fixing — `proj`/`scan.py` already compute it. Derive it (a generator/check) or drop the prose line and point at `proj relay`.
    3. **Scope-split false-positives in `--cross-ledger`** (measured `/relay review --all` 2026-06-21): `orphan-scan --cross-ledger` flags ANY checkbox disagreement as drift, but a reused `id:` legitimately spans a *closed ROADMAP decision* + an *open TODO action* with genuinely different states — re-flagged every review forever → alarm fatigue, the very seam pain this item must measure. 3 concrete instances this sweep: `zelegator 6c63` (eval closed / swap deferred), `yinyang-puzzle a202` (defer-decision closed / paid filing pending), `yinyang-puzzle cf89` (ROUTINE cross-link closed / broader TODO scope). The guard needs a way to mark a divergence INTENTIONAL (proposed: an inline `<!-- xledger-ok: <reason> -->` annotation on the open side, honored like `# swallow-ok:` in id:4347; empty reason still flags). Open design Q (→ which item owns it): a per-line annotation is the point-solution; 2840's derived index models it natively (one id → two scope rows, each its own state) — so this may be EVIDENCE FOR 2840 rather than more d9b0 scope.
  - **Acceptance:** `tests/test_ledger_seam.sh` (`# roadmap:d9b0`): a fixture repo with an executable-lane TODO item absent from ROADMAP is FLAGGED; a present one is not; the count line is derived (or its removal is asserted); and an `xledger-ok`-annotated scope-split is NOT flagged while an un-annotated divergence still is. Builds on `orphan-scan.sh --cross-ledger`. Relates id:962a/69f4/415b; the scope-split half is partly dissolved by the deferred id:2840 (derived-index vision).
- [x] [ROUTINE] Add `--all` to relay-reconcile.sh so `/relay reconcile --all` is a tested code path (done 2026-06-21, executor) <!-- id:4e14 -->
  - **Bug (observed 2026-06-21):** `relay-reconcile.sh` only operates on ONE repo (cwd or arg). `/relay reconcile --all` has no script support, so the strong turn improvised a cross-repo sweep with `git for-each-ref … 2>/dev/null`. Run in the sandbox (where `git -C <repo outside cwd>` fails), the `2>/dev/null` swallowed every error and the run reported "0 parked orphans / clean" — a FALSE negative — while `proj relay` correctly showed parked `relay/orphan/*` branches in isochrone, project_manager, and zkm-pdf. Swallowing git stderr + a directory-exists check that still passed = silent miscount as "no orphans". Root lesson: a cross-repo sweep belongs in a deterministic script, not improvised per-turn.
  - **Fix:** add a first-class `--all` flag to `relay-reconcile.sh` that enumerates relay.toml `classification = "own"` repos (honoring the `# path:` override + `RELAY_TOML`/`SRC_DIR`, exactly as `gather-human-backlog.sh`'s `own_repos()` does — reuse/copy that parser, do not re-roll it) and runs the LIST action across all of them, aggregating output. It must **NEVER** silently swallow a git read failure: an unreadable/missing repo path is SURFACED on stderr (a NOTE/ERROR line), never counted as "no orphans". `--all` is list-only (multi-repo); `--integrate`/`--discard` stay per-branch single-repo (a combination like `--all --integrate` should be rejected, not guessed).
  - **Also:** the relay SKILL.md reconcile section should document that `reconcile --all` is the cross-repo list (one canonical command), so no future turn hand-rolls a sweep. Note the relay.toml path discrepancy to verify while here: `gather-human-backlog.sh` defaults `RELAY_TOML` to `~/.config/relay/relay.toml` but the live file is `~/.config/relay/relay.toml` — resolve to whatever the rest of the relay scripts actually use (don't break the existing default; just make `--all` read the same file the pool reads).
  - **Acceptance:** `tests/test_relay_reconcile_all.sh` (`# roadmap:4e14`) — temp RELAY_TOML + temp git repos; asserts `--all` lists a parked orphan and names its repo, skips non-own repos, does NOT spuriously attribute an orphan to a clean repo, and (the core guard) SURFACES an unreadable repo path instead of swallowing it. RED until implemented.
- [x] [HARD — strong model] Integrator can DESTROY uncommitted edits in a repo's main checkout (data loss) (done 2026-06-18, strong-execute) <!-- id:aa93 -->
  - **Bug (observed 3× on 2026-06-18):** while the pool was integrating dotclaude-skills, a human/parallel-session's uncommitted edit to `relay/scripts/relay-loop.js` (tracked, unstaged) **vanished** — reflog showed `reset: moving to HEAD`, `git stash list` was EMPTY (i.e. real loss, not a recoverable autostash). The integrate step's "verify clean tree, abort if dirty" (relay-loop.js ~line 990) is an **LLM-agent prompt, not a deterministic gate** — the most likely mechanism is the integrator agent "cleaning" a foreign-dirty tree (`git stash`+drop / `git checkout -- <f>` / `reset --hard`) to proceed with its `--no-ff` merge, discarding changes it did not create. `git-lock-push.sh`'s non-ff path (`git pull --rebase --autostash`, line 116) is a second exposure: it autostash-resets a foreign-dirty tree outside any lock the editor respects (the flock serializes only the push, NOT working-tree safety).
  - **Impact:** silent, unrecoverable loss of a concurrent editor's work. Forced a `TaskStop` of the pool just to land an edit safely. This is the acute, fileable slice of the id:3558 shared-checkout hazard.
  - **Fix directions:** (1) make the clean-tree gate DETERMINISTIC + FAIL-SAFE in a non-agent wrapper: `git status --porcelain` before any merge/push; if the tree carries changes the run did not create → DEFER the repo and surface it, never force-clean. (2) The integrator must NEVER run `git stash` / `git checkout --` / `git reset --hard` / `git clean` on a main checkout to make room. (3) `git-lock-push.sh`: STRONGLY CONSIDER dropping `--autostash` from the non-ff path (line 116) entirely — under commit-first discipline the tree is clean at push time, so `--autostash` is a no-op EXCEPT when the tree is unexpectedly dirty, i.e. a foreign session's uncommitted work; its only real effect is to silently sweep that work into a rebase autostash (user call 2026-06-18: "autostash bad maybe?"). Replace with the SAME fail-loud/defer the `--ff-only` path already uses on divergence (warn, keep work committed locally, `exit 0` non-fatal) — never silently mutate a dirty tree. (4) Structural fix remains id:3558 (worktree-per-session merge), but (1)+(2)+(3) are the cheap interim guard. Acceptance must include a `git-lock-push` case: a foreign-dirty tree is DEFERRED (warned, not stashed/lost), tree unchanged.
  - **Acceptance:** `tests/test_integrator_foreign_dirty.sh` (`# roadmap:aa93`) — seed a tracked-file edit in a fake main checkout, run the integrate/clean-tree gate, assert the edit SURVIVES and the repo is deferred (not merged). RED until implemented.
  - **DONE 2026-06-18 (strong-execute, fixes (1)+(2)+(3); structural fix (4)=id:3558 stays open):**
    - New deterministic gate `relay/scripts/clean-tree-gate.sh` (modeled on sync-origin.sh): observes ONLY (`git status --porcelain`), NEVER stash/checkout/reset/clean. Clean (or all entries `--accept`-ed) → `clean`/exit 0; foreign-dirty → `dirty <N>` + offending porcelain lines/exit 2 (caller DEFERS). `--accept <path>` whitelists a declared-acceptable path (e.g. a relay.toml-commented build artifact).
    - relay-loop.js integrate **step 1** now runs `clean-tree-gate.sh ${unit.path}` and ABORTS (merged=false) on non-zero — replacing the LLM-only "verify clean tree" prompt — with an explicit NEVER-`git stash`/`checkout --`/`reset --hard`/`git clean` prohibition on the main checkout (id:aa93 marker in-file).
    - `git-diary-workflow/git-lock-push.sh`: the `--rebase --autostash` (non-ff) path now refuses a foreign-dirty tree (`git status --porcelain` guard) instead of autostash-resetting it — leaves work committed-locally-not-pushed (non-fatal, same as a flock timeout).
    - Makefile registers `clean-tree-gate.sh` in relay_FILES/_EXEC/_ALLOW. `tests/test_integrator_foreign_dirty.sh` green; full `make test` green.
- [x] [HARD — pool] Gate-detection (id:3801) must commit its main-checkout ROADMAP edits atomically — uncommitted residue is a self-blocking dirty backlog (done 2026-06-24, relay HARD child id:da26) <!-- id:2147 -->
  - **Why** (observed 2026-06-24, 5 repos at once): the relay's gate-detection (id:3801) — run by `/relay review`/`/relay human` per-repo, which write ROADMAP gate annotations + lane migrations + seam decompositions in the **main checkout** (id:15d5, NOT a worktree) — leaves those edits **uncommitted** when the run ends/dies before a commit (mid-run API error, session kill, or simply no per-edit commit step). The residue then trips the dirty-guard (id:aa93): every subsequent pool run DEFERS the repo to avoid data loss, so the residue can never be cleared by the very `review` that would commit it — a self-perpetuating backlog. Found `M ROADMAP.md`-only residue in trAIdBTC (id:b123 +seams 00cb/c666), zkm-ner (7b4e), proton-moresync (5cc5), puzzle-pwa (6bef), and a mixed ROADMAP+code residue in zkm-pdf (9475 +seams cd59/8aa4 + the cd59 impl). Memory [[relay-onboarding-vs-confirmation]] recorded the symptom ("commit the residue") 2026-06-21; this is the structural fix. Complement to id:aa93 (which stops the integrator DESTROYING foreign-dirty trees — this stops gate-detection CREATING the residue). Sibling of id:148b (atomic write+commit in `/meeting`'s md-merge.py).
  - **Acceptance**: identify every relay step that writes ROADMAP/TODO/REVIEW_ME in the **main checkout** (gate-detection id:3801 in `review.md`/`human.md`, the re-derive-roadmap step, lane back-fill) and make each write commit **atomically per-repo** — scoped `git commit <ledger-file>` under the flock'd `meeting/md-merge.py` path (the id:148b precedent), so an interruption can NEVER leave a modified-but-uncommitted ledger in main. After any gate-detection edit there is no dirty ledger left behind. Add a test that simulates a gate write + abort and asserts the tree is either clean-committed or untouched (never dirty-uncommitted). Relates id:aa93/148b/3558/15d5/415b(4); back-fill note: a `/relay review` of the 5 just-committed repos will adjudicate the freshly-committed seams' checkbox + versioning.
  - **Done 2026-06-24** (relay HARD child, id:da26): new deterministic `relay/scripts/commit-ledger.sh <repo-root> -m <msg> <ledger-path>…` — the reusable "commit your main-checkout ledger edit atomically" primitive. It flock-serializes on the repo's `.git-lock-push.lock`, stages ONLY the named ledger paths (`git add -- <path>`, NEVER `git add -A` — id:debf) and commits them with a scoped `git commit -- <path>`, so a concurrent edit to an UNRELATED file is left alone. It NEVER stashes/resets/cleans/`checkout --` a foreign-dirty tree (id:aa93 — only ADD+COMMIT). COMMIT-ONLY (never pushes — relay children don't push; a local commit alone clears the dirty-guard, which is the whole fix); a named file with no change is a clean no-op (idempotent). Rejects out-of-repo paths + loud-fails on missing `-m`. The AUTOMATED gate path (`handback-followup.py`, id:3801) already committed atomically via `git-lock-push --ff-only` + single-file manifest — the residue came from the **LLM-prose** steps, so wired commit-ledger.sh into `references/review.md` §5 (after the ROADMAP/TODO re-derivation + gate annotations) and `references/human.md` §5 (after each repo's `md-merge.py` flow-back — md-merge writes but does NOT commit, the exact gap). Registered in `relay_FILES`/`relay_EXEC`/`relay_ALLOW`/`relay_LOCAL` (id:69ef install-completeness). Spec `tests/test_relay_commit_ledger.sh` (`# roadmap:2147`) green (scoped-commit-leaves-foreign-dirty-alone, no-stash, multi-file, clean-no-op, abs-path, misuse, path-traversal-reject, prose+manifest wiring); full suite green (101). Note: this provides the helper + wiring; a future `/relay review` can additionally fold a `commit-ledger`/dirty-residue check into `relay-doctor.sh` (id:0907 family) for detection alongside this prevention.
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [HARD — pool] Standalone GPU/intensive background jobs must acquire a relay `resource:<name>` claim so `--intensive` can serialize against them (done 2026-06-25, relay HARD child id:da26) <!-- id:a643 -->
  - **Why** (observed 2026-06-24): `~/.claude/logs/ai-codebench-drain.sh` (the id:244b matrix drain) ran a local `llama-server -ngl 99` on the GPU for ~2h, fully detached (PPID 1) and OUTSIDE the relay. It holds **no** relay claim, so a concurrent `/relay --intensive` pool is **blind** to it: the relay's intensive child does `claim.sh acquire resource:<name>` and correctly stops if busy (relay-loop.js ~L1200), but nothing told it the GPU was already taken → had the pool dispatched an ai-codebench `[INTENSIVE — local-llm]`/GPU unit it would have spun up a SECOND llama-server concurrently = GPU OOM ([[oom-local-model-session-kills]], the Gemma-26B 6-session kill). The relay side already HONORS a held `resource:<name>` claim; the only missing half is the standalone job ACQUIRING it. Neighbour of id:2147 (both about state the relay can't see); resource axis is id:8d52.
  - **Acceptance**: (1) document a shared `resource:<name>` vocabulary (e.g. `resource:gpu` or the same `<resource>` token an `[INTENSIVE — <resource>]` lane tag uses) so a standalone job's claim and the relay's intensive-unit claim collide on the SAME key. (2) wrap `ai-codebench-drain.sh` (and provide a small reusable helper for future standalone intensive jobs) to `claim.sh acquire resource:<name> --run drain-<pid> --mode intensive` for its lifetime and `release` on exit, with the claim's mtime-TTL/PID-liveness covering a crash (a dead drain's claim auto-expires, never wedges the relay). (3) verify the relay's intensive `acquire` collides with the drain's claim (a test or documented manual check: drain holds `resource:gpu`, relay intensive `acquire resource:gpu` → busy → handback, not a second model load). Don't build a new lock — compose existing `claim.sh` (id:ebfb). Relates id:8d52/2147/244b; [[oom-local-model-session-kills]].
  - **Done-check**: tick this checkbox, then `make test` fully green.
  - **Done 2026-06-25** (relay HARD child, id:da26): composed the EXISTING `claim.sh` (id:ebfb) — built NO new lock. (1) `relay/references/resource-claims.md` — the shared `resource:<name>` vocabulary doc (single source both sides read): the resource token MUST be byte-identical to the item's `[INTENSIVE — <resource>]` tag (id:8d52) so the relay's intensive-child `claim.sh acquire resource:<res>` (relay-loop.js ~L1200) and a standalone job's claim COLLIDE on one key; table of `local-llm`/`gpu` tokens; crash-safety via claim.sh mtime-TTL+PID reap. (2) `relay/scripts/acquire-resource.sh <resource> [--run R] [-- ] <cmd…>` — the reusable wrapper for future standalone intensive jobs: acquires `resource:<res>` (mode=intensive), runs the command, and ALWAYS releases on exit (trap EXIT/INT/TERM); bare `--acquire`/`--release` forms for a job that manages its own lifetime; REFUSES (exit 1, no command run) when the resource is busy — exactly the relay-blind second-GPU-load the item exists to prevent. Registered in `relay_FILES`/`relay_EXEC`/`relay_ALLOW`/`relay_LOCAL` + the doc in `relay_FILES` (id:69ef install-completeness). Spec `tests/test_resource_claim.sh` (`# roadmap:a643`) green — incl. the core collision test: standalone holds `resource:gpu` → a relay `acquire resource:gpu` is REFUSED; release → relay acquire succeeds; full suite green. **Residual (NOT this worktree's scope):** the actual one-line wrap of `~/.claude/logs/ai-codebench-drain.sh` lives OUTSIDE this repo (a local un-versioned operator script a relay child cannot commit) — prefix its run with `acquire-resource.sh local-llm --run drain-$$ --` where that file lives. This repo ships the primitive + vocabulary + collision test (acceptance parts 1 + 3 + the reusable-helper half of 2); the per-job wrap is the operator's one-liner.
- [x] [HARD — pool] PID-anchored claim liveness for standalone long jobs + `--pid` adopt for an already-running drain (done 2026-06-25, strong turn) <!-- id:1b11 -->
  - **Why** (observed 2026-06-25, while wiring the a643 drain): a STANDALONE intensive job has NO worktree, so `claim.sh` liveness fell back to mtime-TTL ALONE (1800s/30min) — a multi-hour `ai-codebench-drain.sh` would go stale and be reaped mid-run, so a later `/relay --intensive` would no longer see the held `resource:local-llm` claim and could spin up a second GPU load (the exact a643 hazard, just delayed 30min). And a drain that is ALREADY running can't be wrapped retroactively — there was no way to adopt a running PID into a claim.
  - **Done 2026-06-25** (strong turn): added a THIRD liveness signal to `claim.sh` keyed on a DEDICATED `live_pid` field (NOT the incidental `.pid` = claim.sh's own `$$`): `pid_alive()` (`kill -0`) joins `is_fresh`/`worktree_working` in `is_live`, so a claim with an explicit `--pid` stays live while that process lives (past the TTL) and auto-expires the instant it dies. `acquire` gained `--pid PID`; the field is preserved on re-entrant heartbeat-refresh. `acquire-resource.sh` gained `--pid PID` (adopt an already-running job) and now defaults the wrapped (`cmd`) form's anchor to its OWN `$$` (alive for the command's lifetime under the trap), so wrapped long jobs are durable with no heartbeat. Backward-safe: no `--pid` → empty `live_pid` → zero behaviour change (no PID-reuse exposure on the default path). The running `ai-codebench-drain.sh` (PID 23282) was adopted live: `acquire-resource.sh local-llm --acquire --pid 23282 --run drain-23282`. Spec `tests/test_resource_claim_pid.sh` (`# roadmap:1b11`) green (live-pid survives TTL/steal-refused, peek+reap keep it, dead-pid reapable, no-pid legacy unchanged, acquire-resource adopt); full suite green (103).
  - **Done-check**: tick this checkbox, then `make test` fully green.
- [x] [ROUTINE] Stop discovery shards flailing on the filesystem (no-hunting guard) (done 2026-06-18, reviewer) <!-- id:612f -->
  - **Bug (observed live 2026-06-18):** in a running pool, discovery (a barrier over 6 parallel Sonnet shards) stalled >5 min. One shard hitting a repo with parked `orphan_refs` (dotclaude-skills, 2 refs) improvised instead of using the gather JSON: ran `find /home/tobias -name relay.toml` across ALL of $HOME, cat-ed session transcripts, hand-parsed ROADMAPs — **36 tool calls vs ~9** for a lean shard. Since the round can't proceed until the slowest shard merges, one flailer paced the whole round (and burned extra Sonnet, compounding the discover-on-Sonnet cost, id:c3a6).
  - **Fix (applied directly this turn):** added a NO-FILESYSTEM-HUNTING GUARD to the shard prompt — everything is already in the gather JSON (`toml_block` = the repo's relay.toml block, `roadmap` = its ROADMAP.md, `orphan_refs` = parked refs); the shard must NEVER `find` over $HOME, cat transcripts, or re-derive JSON-provided state; parse the orphan cost-hint runId from the ref basename; surface (don't hunt) on a genuinely-missing field. `node -c` clean; `tests/test_relay_loop_structure.sh` + `test_relay_discovery_guards.sh` + `test_relay_discover_shard.sh` green.
  - **Follow-up (not done):** hoist the per-shard orphan→ROADMAP binding (the `git show --stat` + checkbox resolve, lines ~610–613) into the once-only prelude so shards never touch orphan state at all — bigger refactor, deferred. Add a shard-canary corpus case asserting zero `find`/`cat`-transcript calls.
- [x] [ROUTINE] Normalize nested quota-threshold args in relay-loop.js so a per-bucket override isn't silently dropped <!-- id:b841 -->
  - **Bug (observed 2026-06-18):** the front door / caller passed quota caps as a nested `args.quotaThresholds = {SEVEN_DAY: 0.70, SEVEN_DAY_SONNET: 0.70}` object, but `relay-loop.js` only forwards FLAT keys (`A['RELAY_QUOTA_THRESHOLD_SEVEN_DAY']`, `..._SONNET`) into the gate env (lines ~901–904). The nested object was never read, so a user directive "raise 7d cap to 70%" silently had ZERO effect across two runs — the standing `RELAY_QUOTA_DECAY_7D` cap governed instead.
  - **Fix:** in the args-normalization block (near `const A =`, the same place `fableDown` is normalized), accept a nested `quotaThresholds` map and fold each entry into the corresponding flat `RELAY_QUOTA_THRESHOLD_<BUCKET>` key (flat key still wins if both present). Explicit per-bucket threshold beats the decay (quota-stop.sh §117), so this restores the user's ability to override.
  - **Also:** the SKILL.md front door should translate a "7d cap = X%" phrase into BOTH flat keys (`RELAY_QUOTA_THRESHOLD_SEVEN_DAY` + `_SONNET`), since executor/review children run on the Sonnet bucket. Document the arg shape in the config-knobs table.
  - **Acceptance:** a `tests/test_relay_quota_args.sh` (`# roadmap:b841`) asserting a nested `quotaThresholds` arg produces the same forwarded env as the flat keys. RED until implemented.
- [x] [ROUTINE] Fix relay quota stop-reason bucket attribution (`quota-exhausted:unknown` mislabel) <!-- id:2425 -->
  - **Bug (observed 2026-06-18):** when the gate stops, `relay-loop.js` (~line 936) names the culprit with a hardcoded `(v.buckets||[]).find(b => b.pctRemaining <= 10)` — the old 90%-cap assumption. A stop triggered by a *decayed* or *overridden* threshold below 90% utilization (e.g. `seven_day_sonnet=34% >= 0.3353`) matches no bucket → falls through to `quota-exhausted:unknown`, making real stops look mysterious.
  - **Fix:** have the quota agent / `quota-stop.sh` return the bucket that actually crossed its (possibly decayed/overridden) threshold plus the threshold value, and use THAT for `stopReason` (`quota-exhausted:<bucket>`), instead of the ≤10%-remaining heuristic. Keep the heuristic only as a last-resort fallback.
  - **Acceptance:** a `tests/test_relay_stop_reason.sh` (`# roadmap:2425`) feeding a below-90% decayed-threshold crossing and asserting `stopReason` names the crossed bucket, not `unknown`. RED until implemented.
- [x] ⭐ HIGH PRIORITY: cut relay status/overhead cost (~35% of spend, low-concurrency, on the critical path) [HARD — strong model] <!-- id:c3a6 -->
  - **DONE 2026-06-17** (Opus `/meeting`, `docs/meeting-notes/2026-06-17-0721-relay-status-overhead-cost.md`). Two changes, both in `relay/scripts/relay-loop.js` + new `relay/scripts/discover-sig.sh`; `make test` green (62), TDD `tests/test_discover_sig.sh` + `tests/test_discover_cache.sh`.
    - **D1** — pinned `discover-shard` (line 593) to `model:'sonnet'` (was inheriting the Opus session model; sibling prelude already sonnet). Sonnet not haiku: the shard prompt is logic-dense (EXECUTABLE-HARD test, orphan-park precedence) and Haiku is known to misclassify such tasks (`d6-builder-tier-decision`).
    - **D2 (tier audit — SATURATED)**: every other agent is already correctly tiered — work-units (1059–1060) pin execute→sonnet / review+handoff+hard→STRONG_MODEL; prelude+integrator are sonnet (logic-dense, Haiku-fail risk); status/quota/release/gaming are haiku. **No further safe tier downgrade exists.** Do NOT re-open this item to haiku-ify the integrator — that path was rejected with rationale.
    - **D3 (re-discovery redundancy)**: content-addressed discovery cache — `discover-sig.sh` hashes a SUPERSET of every classifier input (HEAD, ckpt tags + latest message, porcelain, upstream ahead/behind, worktree dirs, orphan refs, relay.toml block, ROADMAP hash, in-liveClaims flag); `runRound` reuses last round's verdict for unchanged repos, so an LLM shard fires only on churn. Fail-open (empty/sentinel sig → re-classify).
  - **Forward — D1 attribution RESOLVED (code read, no live data yet)**: `discover-shard`/`discover-prelude` agents carry `phase: 'Discover'` (relay-loop.js:537,627); `profile-run.sh` heuristic (line 140) maps that to `"discover"`; `relay-econ.py` `PHASE_CAT` (line 36) maps `"discover"` → **`"scaffold"`** bucket — NOT `"status"`. The pre-fix Opus spend on shards would show up in the `scaffold` column. Post-fix verification command: `python3 relay/scripts/relay-econ.py --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print("scaffold $",d["cost"]["scaffold"],"| cost_by_model:",d["cost_by_model"])'` then diff scaffold $ and opus share vs prior run. No post-fix pool-run data exists yet — live confirmation still pending. <!-- id:9cb1 -->
  - **Forward — integrator frequency** (NOT tier): CLOSED 2026-06-17 (id:c563) — both levers exhausted: (1) 'skip no-op' lever does not exist (integrate() early-returns before Sonnet agent for null/contract_met=false — all 119 spawned integrators had genuine merges); (2) batching infeasible — per-repo integrations are one-per-round (each branch descends from prior ckpt, median ~100 min span), never co-ready; cross-repo batching reverses line-465 parallel design and worsens recovery for rounding-error sonnet token saving vs Opus-dominated spend. Re-open trigger: same-repo co-ready units in one wave. See meeting note docs/meeting-notes/2026-06-17-0812-relay-integrator-batching-close.md. <!-- id:c563 -->
  - **Evidence** (`relay-econ.py`, 2026-06-16, 5 runs / $633): `status` category = **$220.90 (34.9%)** of cost at only **2.2× mean concurrency** (serial-ish, on the critical path); `work` is $384.84 (60.7%). Model split: opus **78.2%**, sonnet 17%, haiku 4.5%. So a third of spend is overhead, not repo work.
  - **Prime suspect (quick win):** `discover-shard` agents in `relay/scripts/relay-loop.js:593` **omit `model:`**, so they inherit the *session* model — **Opus** when the pool is launched from an Opus session — and discovery **re-runs every round** (DISCOVER_SHARDS=6 × up to MAX_ROUNDS=30). The sibling `discover-prelude` (line 526) doing the same classification IS pinned to `model:'sonnet'`. Pin the shards to sonnet (or haiku) → likely large saving for zero quality loss. Verify the category mapping first (shards are phase `Discover`, not necessarily the econ `status` bucket — re-profile to attribute).
  - **Other leads:** per-repo integrator is a Sonnet agent ~1–2 min each, serialized per-repo (109 integrations on 2026-06-16) — see `relay-loop.js:455`; `RELAY_STATUS` writes + quota gates already run on Haiku off the critical path (line 245, NOT the target — leave them).
  - **Goal:** reduce overhead $ without losing work throughput. Measure before/after with `relay-econ.py`. Quick-win (shard model pin) is executor-sized; the broader "what else can downgrade safely" needs judgment → kept [HARD].
  - **Note:** `relay-burn.sh report` currently has **no samples** (`quota-samples.jsonl` empty) — the $/h-to-reset projection is blind until quota-gate sampling accumulates ≥2 points during a run; worth checking the sampler is actually firing (id:219b).
- [x] [ROUTINE] Surface the REAL quota-stop reason in RELAY_STATUS + workflow log (visual feedback) (done 2026-06-15) <!-- id:8c35 -->
  - **Context**: 2026-06-15 — the relaunched pool (run relay-20260615-155151) reported
    `quotaStopped:true` and a big queued-not-dispatched backlog, but it had NOT hit any quota
    bucket (5h 43% / 7d 55% / Sonnet 81% remaining, all far from the 90%-used threshold). The
    real cause, only found by grepping the workflow log, was `quota-stop: cache stale (1404s >
    600s limit) and self-refresh unavailable/failed` — the conservative stale-cache-can't-refresh
    seatbelt (the `/api/oauth/usage` endpoint 429s aggressively). A refresh-failure stop and a
    real-exhaustion stop are reported IDENTICALLY ("quotaStopped"), making the stop opaque.
  - **Why**: user directive 2026-06-15 — "really needs more visual feedback". An operator should
    see WHY the pool stopped without grepping transcripts.
  - **Acceptance**: relay-loop.js's quotaGate captures the quota-stop verdict CATEGORY and detail
    (real exhaustion: which bucket + headroom%, vs stale-cache/refresh-failure vs seatbelt/budget)
    and (a) `log()`s it as the drain reason, and (b) writes it into RELAY_STATUS.md (e.g. a
    `## Stop reason` line or annotating the existing `## Quota remaining` section). The returned
    run result distinguishes `stopReason: "quota-exhausted:<bucket>" | "quota-stale-cache" |
    "budget" | "drained" | "max-rounds"`. quota-stop.sh already returns exit 2 for
    uncertain/stale vs exit 1 for at/above-threshold — surface that distinction instead of
    collapsing both to "quotaStopped". Hermetic test asserting the stale-cache path yields the
    stale-cache reason, not a bucket-exhaustion reason.
  - **Spec / red test**: `tests/test_relay_quota_stop_reason.sh` (`# roadmap:8c35`) — static-structural
    (matching `test_relay_loop_structure.sh`): asserts quotaGate branches on quota-stop.sh exit 2
    (stale-cache) vs exit 1 (exhaustion) instead of collapsing both to `quotaStopped`; a `stopReason`
    field is captured in the run result with the category vocabulary (`quota-stale-cache`,
    `quota-exhausted:<bucket>`); the drain-reason `log()` names the category; and RELAY_STATUS
    surfaces the stop reason alongside the existing `## Quota remaining` section. RED until implemented.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_quota_stop_reason.sh` then full `make test`
    after ticking.
- [x] [ROUTINE] Harden relay-state-write.sh toml-set against awk -v / regex-key input (F1/F2) (done 2026-06-15) <!-- id:c8db -->
  - **Source**: id:401c strong-model audit 2026-06-15 (`docs/meeting-notes/2026-06-15-1520-strong-model-audit.md`),
    findings F1 + F2. Re-filed after the audit's own commit was discarded (stale base) — see that note's provenance header.
  - **F1**: `toml-set` passes the value via `awk -v val="$value"`, and awk's `-v` processes
    C-style backslash escapes — a value containing `\` would be silently mangled before it hits
    the file. **F2**: `key` is spliced into an awk *regex* (`kre="^" key "[ \t]*="`); a key with
    regex metacharacters would match/replace the wrong line.
  - **Risk today: zero** — every caller (relay-loop.js integrate step 6) passes only checkpoint
    tags, ISO dates, and bare tokens (`false`/`"active"`/`"handed-off"`); keys are fixed TOML
    identifiers. This is forward-robustness so a future caller passing an arbitrary value/key
    can't be corrupted. Low priority.
  - **Acceptance**: `toml-set` writes the value without awk `-v` escape processing (e.g. pass via
    env/ARGV or a literal-safe mechanism) and matches the key by literal compare (not regex);
    a test feeds a value with a backslash and a key-shaped edge and asserts a faithful round-trip.
- [x] [ROUTINE] Resolver pushes unblocked work to the pool via inject.sh (low-latency REVIEW_ME pickup) (done 2026-06-15) <!-- id:fb75 -->
  - **Context**: 2026-06-15 user observation — a parallel `/relay human` session resolved most
    REVIEW_ME boxes, but the running pool only reacts at its next discovery **round boundary**
    (after the current wave integrates), so a resolution that unblocks pool work waits minutes.
    The inject path already exists (id:baf1: `inject.sh add/take`, `inject.d/` inbox, injected
    units outrank every verdict class + skip the quota gate). Push beats watch here: the resolver
    knows *exactly* what it unblocked, so it should hand that item to the pool directly rather
    than have the pool (or an inotify watcher) re-derive it. (inotify rejected — the pool is a
    deterministic Workflow that can't consume an inotify event mid-run; a watcher→inject bridge
    is strictly more than calling inject.sh at resolution time, and fires on every blind tick.)
  - **Spec / red test**: `tests/test_relay_resolution_inject.sh` (`# roadmap:fb75`). It asserts
    `references/human.md` §5 write-back: (1) calls `inject.sh add`, (2) conditioned on the
    resolution UNBLOCKING pool work (not every tick), (3) passes `--item <id>` (targets the
    unblocked item, not a blind repo re-classify), (4) REUSES the existing id (single-id-two-views,
    no duplicate mint).
  - **Acceptance**: edit `references/human.md` §5 (and note the same step for the `/meeting`
    REVIEW_ME write-back, id:15d5) so that after a clean lease-held write-back that ticks a box
    unblocking a gated/blocked ROADMAP item, the resolver runs
    `~/.claude/skills/relay/scripts/inject.sh add <repo> --item <id> --verdict execute` (only when
    it unblocks work). Then `make test` green (fb75 ticked). No relay-loop.js change — this is the
    resolver contract only; the within-round-latency lever is id:6e9d.
- [x] [HARD — strong model] Freed lane pulls injections mid-round (free-slot immediacy, no round-boundary wait) (done 2026-06-15) <!-- id:6e9d -->
  - **Context (corrected 2026-06-15)**: the dispatch core is ALREADY a free-slot worker pool —
    `parallel()` spawns POOL_WIDTH lanes each looping `queue.shift()`, and there is precedent for
    pushing onto the LIVE queue mid-round (the review→execute re-enqueue at ~L782). The real gap:
    injections enter the queue ONLY at round-start discovery (`inject.sh take` runs inside the
    discovery agent). A lane that empties `queue` then EXITS (its `while (queue.length)` condition),
    so a freed slot idles until the round ends — and the round ends only when the SLOWEST current
    unit finishes. So a mid-round injection waits for unrelated long units (user report 2026-06-15:
    "injection should trigger when a slot is free, not wait for irrelevant tasks").
  - **Key constraint**: the Workflow script CANNOT run shell itself — `inject.sh take` only runs
    inside an `agent()`. So a lane cannot poll `inject.d` directly; it must spawn a tiny take-agent.
  - **Design (poll-once-on-drain, the cheap Pareto fix)**: when a lane finds `queue` empty (would
    otherwise exit), it spawns a small `inject.sh take` agent (resolves repo path via relay.toml
    `# path:`, returns injected unit objects). If it yields units → push onto the live `queue` +
    continue (the freed lane runs them immediately). If empty → the lane exits as today. So an
    injection is caught the moment the NEXT lane frees with the queue drained — for a cycling
    multi-unit pool that is ~one short-unit latency, vs. today's "wait for the whole round + integ
    drain + re-discovery". It does NOT preempt a running agent (impossible).
  - **Known residual (explicitly out of scope, by design)**: if ALL lanes are simultaneously busy
    on long units (e.g. end-of-backlog lone long tail), freed lanes have already exited, so the
    injection is caught only when that tail unit finishes → the round ends → the outer loop
    re-discovers (sub-second) and `take`s it. Fully closing that needs a poll-WHILE-busy lane, which
    taxes EVERY round's tail with repeated take-agents whether or not an injection ever arrives — a
    bad default (most rounds have no injection). Not taken; the poll-once fix is a strict
    Pareto-improvement (never worse than today, usually much better) without that standing cost.
  - **Races handled**: two lanes draining together both spawn take-agents — `inject.sh take` is
    atomic/flock'd, so each shard goes to exactly one lane (the other gets empty → exits; no loss).
    No busy-spin: a lane spawns the take-agent only when it would otherwise EXIT (queue empty), not
    every iteration. MAX_UNITS/quota gates still bound dispatch.
  - **Spec / red test**: `tests/test_relay_midround_inject.sh` (`# roadmap:6e9d`). Static-structural
    (matching test_relay_loop_structure.sh): assert relay-loop.js has a mid-round injection pickup
    (a take-agent spawned from the lane drain path, carrying `id:6e9d`), distinct from the
    discovery-time take. RED until implemented.
  - **No longer deferred**: user directive 2026-06-15 — free-slot immediacy is the wanted behavior,
    not a measure-first nicety. Complements id:fb75 (resolver pushes) — fb75 enqueues the unblocked
    item, 6e9d makes a free slot pull it without round-boundary latency.
- [x] relay-loop.js must auto-reap stale worktrees from dead runs (not treat them as in-flight) (done 2026-06-15) <!-- id:3ac8 -->
  - **Context**: observed 2026-06-15 — two crashed morning runs (`relay-…-1104-hard`,
    `relay-…-1152-hard`) left 17 worktrees on disk under `~/.cache/fables-turn/worktrees/`
    with NO live `claim.sh` shard. Discovery's worktree-aware guard (id:c3f7) treats a
    worktree directory's mere existence as "in-flight elsewhere — claimed by another relay
    run", so a later pool falsely SKIPPED 14 repos (all the HARD-eligible ones) and starved
    itself. `claim.sh` explicitly defers this case: "handback nuance for stale-with-live-worktree
    is the relay-loop's job, not this." The loop isn't doing it.
  - **Why HARD**: must distinguish a *dead-run* stale worktree (no live claim + claim/worktree
    mtime past TTL) from a genuinely live foreign-runId worktree, AND must NOT blind-prune — a
    worktree can hold an unmerged handback commit (RELAY_LOG/REVIEW_ME notes; 2 of the 17 did).
    Reconcile-then-reap: integrate any commits ahead of main (ff/union path) before removing.
  - **Acceptance**: relay-loop.js discovery, before classifying a repo "in-flight elsewhere",
    checks for a FRESH `claim.sh` shard; if none and the worktree branch is `--is-ancestor` of
    main (empty), prunes it + deletes the branch; if it carries commits ahead, surfaces it as a
    HANDBACK needing integration (never silently dropped). Hermetic test in `tests/` with a
    seeded stale worktree + empty claim registry asserting the repo is freed, not skipped.
  - **Manual cleanup already done 2026-06-15** (this is the durable fix): the 17 worktrees were
    hand-reaped, the 2 handback commits (rawrora id:9029 REVIEW_ME box, zkm-notmuch id:f103 log)
    ff-merged to main and pushed first.
- [x] Interactive relay modes (handoff/review/human) are claim-aware (done 2026-06-15) <!-- id:0902 -->
  - **Context**: post-cluster gap — the autonomous pool (id:ebfb), `/relay executor` (contract v4),
    and `/meeting` (id:d748) took the cross-session lease, but the INTERACTIVE orchestrator modes
    (`/relay handoff|review|human`) were claim-blind, so `/relay human --all` (or two `/relay review`s)
    could still collide with a live pool on shared ledgers / main checkouts.
  - **Done 2026-06-15**: SKILL orchestrator invariant 4 acquires `claim.sh acquire <repo> --run
    relay-<mode>-$CLAUDE_SESSION_ID` before fanning out each handoff/review child (refused → skip +
    surface, never spawn a colliding child); invariant 5 releases it run-scoped at integration.
    `references/human.md` §5 acquires the lease before each per-repo REVIEW_ME/ledger write-back and
    DEFERS on refusal (mirrors `/meeting` id:d748), releasing after. `tests/test_relay_interactive_claim.sh`.
    Every relay actor — pool, executor, meeting, and the interactive modes — now respects one lease.
  - **Concurrent-pool fix (same commit)**: the discovery runId was minute-granular
    (`relay-YYYYMMDD-HHMM`) — two no-args/`--all` pools started in the same minute shared a runId, so
    the lease's same-run re-entrancy AND the worktree-aware guard both false-passed → double-work. runId
    is now per-run unique (`relay-$(date +%Y%m%d-%H%M%S)-$RANDOM`), so two concurrent pools never collide.
- [x] Relay must sync local↔origin before working a repo (stale-clone / divergence guard) (done 2026-06-15) <!-- id:c3f7 -->
  - **Done 2026-06-15**: discovery SYNC-WITH-ORIGIN guard (fetch + ahead/behind; diverged→surface,
    behind-only→ff) in relay-loop.js; `relay/scripts/sync-origin.sh` testable helper (exit 0 ok/ff/
    no-upstream, 2 behind, 3 diverged) with a hermetic functional 2-clone test
    `tests/test_relay_sync_origin.sh`; integrator belt-and-suspenders calls sync-origin.sh and aborts
    on a diverged base (`tests/test_relay_discovery_guards.sh`). The ai-codebench incident cannot recur.
  - **Context**: 2026-06-15 near-catastrophe. The pool worked ai-codebench on a LOCAL clone that
    had been ~1 month behind origin (stale since 2026-05-13, missing 106 commits incl. the live
    GPU session done on zomni). Discovery classifies purely from LOCAL git state and never fetches,
    so for DAYS the pool built a doomed parallel relay timeline (9+ checkpoints) on the stale base
    that could never push (`--ff-only` correctly refused) — wasted work + divergence. A force-push
    "fix" would have destroyed the 106 origin commits. Fixed manually (reset local→origin, purged
    9 dangling stale-timeline tags, corrected relay.toml last_ckpt).
  - **Acceptance**: discovery (or a pre-dispatch step) runs `git -C <path> fetch origin` and compares
    local main to `origin/main`: (a) up-to-date → proceed; (b) behind & clean & no local-unique
    commits → fast-forward, then classify; (c) DIVERGED (local-unique AND origin-unique commits) →
    do NOT work it — surface in RELAY_STATUS "Blocked: <repo> diverged from origin (local N / origin M)
    — needs manual reconcile", never commit on top. Dirty tree still blocks as today. The integrator
    must also never create a checkpoint/commit on a base behind origin. Hermetic test with two scratch
    clones (behind→ff; diverged→surface).
  - **Pairs with**: server-side hardening — **APPLIED 2026-06-15**: `git config --global
    receive.denyNonFastForwards true` + `receive.denyDeletes true` on fievel, so any force/purge push is
    now server-rejected. A controlled-override path (for the user's occasional legitimate force-push) is
    tracked as TODO id:de51 (gerrit is overkill for a Pi).
- [x] Relay claim-registry + cross-session safety (cluster steps 1–4 + executor + single-writer) (done 2026-06-15) <!-- id:ebfb -->
  - ROADMAP execution view of TODO id:ebfb (single-id-two-views). Ratified design:
    `docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md`.
  - **Shipped 2026-06-15**: (1) discovery WORKTREE-AWARE (skip a foreign-runId worktree → surfaced) +
    SYNC-WITH-ORIGIN guard (id:c3f7) in relay-loop.js — `tests/test_relay_discovery_guards.sh`;
    (2) `relay/scripts/claim.sh` — per-shard flock'd registry (`acquire`/`release`/`peek`/`reap`,
    mtime+TTL, resource-key safe; **same-run re-entrant**, **run-scoped release**) —
    `tests/test_relay_claim.sh`, registered in the Makefile;
    (3) **claim wired into the dispatch path (step 4)** — work children `claim.sh acquire <repo> --run
    <runId>` FIRST (refused → stop + "claimed by another relay run" handback); the integrator
    `claim.sh release <repo> --run <runId>` run-scoped; `writeRelayStatus` projects live claims via
    `claim.sh peek` into a `## Claims (live)` section — `tests/test_relay_claim_wiring.sh`.
  - **Also done 2026-06-15**: (4) `/relay executor` honors the lease — executor-contract **v4** rule 0
    (`claim.sh acquire/release`, markers synced across executor-contract.md / CLAUDE.md / conventions.md,
    `tests/test_relay_executor.sh`). Sibling cluster items `[INTENSIVE]` (id:8d52) + `/meeting` hold
    (id:d748) shipped.
  - **Also done 2026-06-15**: (5) cluster **step 2 — flock'd single-writer state**: `relay/scripts/
    relay-state-write.sh` (`toml-set <repo> <key> <value>` field-scoped + `status-write <abs-path>`,
    both flock'd + atomic temp-mv; `tests/test_relay_state_write.sh`). The integrator writes every
    relay.toml field via `toml-set`; `writeRelayStatus` writes via `status-write` — concurrent runs
    serialize on one lock, no torn/clobbered writes. (Per-runId RELAY_STATUS *display* sections were not
    needed — flock'd-atomic single-writer + the claim lease serializing per-repo work cover the cases.)
    All cluster steps 1–6 + executor-honoring + single-writer now shipped.

<!-- DESIGN CLUSTER: "safe concurrent + resource-aware relay dispatch" — RATIFIED 2026-06-15
     (meeting docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md). The claim
     primitive + per-repo lease REUSE existing TODO id:ebfb (claim/reservation umbrella: worktree-
     aware discovery + single-writer relay.toml/RELAY_STATUS + per-shard claim registry) and id:3558
     (flock'd-merge = repo-lease enforcement). id:7b7a & id:8ac5 RETIRED as duplicates. Kept new:
     id:8d52 ([INTENSIVE], rescoped to claim-on-resource + run-alone), id:d748 (/meeting hold),
     id:baf1 (on-demand task injection). Build cheapest-first; dry-stall deferred+observe. -->
- [x] Task-claim primitive — RETIRED 2026-06-15: duplicate of TODO id:ebfb. The PM-board "claim" framing + per-shard registry (`~/.config/fables-turn/claims/<key>.json`) + item-keyed/repo-enforced design is ratified in `docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md` and tracked under id:ebfb (claim/reservation) + id:3558 (flock'd-merge = repo-lease). <!-- id:8ac5 -->
- [x] Cross-session relay dispatch safety — RETIRED 2026-06-15: duplicate of TODO id:ebfb + id:3558. Worktree-aware discovery, single-writer relay.toml/RELAY_STATUS, claim registry → id:ebfb; per-repo lease enforcement → id:3558. Ratified design: `docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md`. <!-- id:7b7a -->
- [x] `[INTENSIVE — <resource>]` tag: gate local-LLM/heavy work behind explicit permission (done 2026-06-15) <!-- id:8d52 -->
  - **Done 2026-06-15**: mechanism (discovery parse + never-auto-dispatch gate + `--allow-intensive`/
    `--afk` + serial run-alone + exclusive `resource:<name>` claim — `tests/test_relay_intensive.sh`)
    AND the tagging-criteria doc in `references/conventions.md` (when strong children tag
    `[INTENSIVE — local-llm]`, citing the OOM + TTFT — `tests/test_relay_intensive_criteria.sh`).
    Operational note: seed the coarse per-repo `intensive = "local-llm"` default into ai-codebench /
    zkm relay.toml blocks when convenient (skipped here — relay.toml was under concurrent write; the
    mechanism reads the flag if present, item-level tags override).
  - **Context**: 2026-06-15 user request. Local-LLM tasks (ai-codebench benchmarks, zkm embedding
    index) hammer GPU/RAM — memory `oom-local-model-session-kills`: Gemma 26B killed all 6 sessions;
    ~57s cold TTFT (cf id:642f). Run-1 already handed these back ad hoc ("hardware-gated for an
    unattended relay turn… never an unattended relay child" — zelegator id:462c, linguistic-unversals
    id:3071). This makes it a first-class, deterministic tag instead of per-child judgment.
  - **Shape**: a resource modifier ORTHOGONAL to the verdict axis (NOT a replacement for
    `[ROUTINE]`/`[HARD]`), two-part like the HARD tags so the gate knows which resource:
    `[ROUTINE] [INTENSIVE — local-llm]`, `[HARD — strong model] [INTENSIVE — local-llm]`.
  - **Acceptance**: (1) discovery parses the modifier; an `[INTENSIVE]` unit is NEVER auto-dispatched
    by the default unattended pool — surfaced in RELAY_STATUS "Queued — needs explicit permission"
    (extends `feedback-relay-unattended-default`: never run resource-doomed work unasked). (2) Global
    resource semaphore `~/.cache/relay/resources/<resource>.lock` — at most one local-llm task
    at a time; conservative default = it RUNS ALONE (pool pauses new dispatch / forces POOL_WIDTH=1
    while held) — this is the actual OOM fix. (3) Opt-in to run them: `/relay --allow-intensive`
    (flag) and an **AFK mode** `/relay --afk [duration]` ("I'm away, do something useful" — drains
    light work, then chews intensive items one-at-a-time within a time/quota budget, reports back).
    (4) Tagging: strong children tag per criteria in `conventions.md` (cite OOM + TTFT), PLUS a coarse
    per-repo default `[repos.ai-codebench] intensive = true` / `[repos.zkm] intensive = true` as a
    safety net; item-level tags override.
  - **RATIFIED 2026-06-15** (meeting 2026-06-15-1216): `[INTENSIVE — <resource>]` is a **claim on a
    resource key** (`~/.config/relay/claims/resource:local-llm.json`), exclusive; while held
    collapse `POOL_WIDTH→1` (RUN ALONE — the OOM fix); never auto-dispatched without `--allow-intensive`
    / `--afk`. Reuses the id:ebfb claim machinery — NOT a separate `resources/*.lock` semaphore (the
    earlier acceptance text above is superseded by this). Build step 5 of the cluster sequence.
  - **Shipped 2026-06-15 (mechanism)**: relay-loop.js — discovery reports `intensive` (resource
    string) from the `[INTENSIVE — <resource>]` item modifier OR a relay.toml `intensive` flag;
    `--allow-intensive`/`--afk` gate (`args.allowIntensive`, SKILL.md knobs); intensive units are
    PARTITIONED out of the parallel wave (never auto-run — surfaced "needs --allow-intensive") and,
    when allowed, run in a SERIAL run-alone phase after the wave, each holding an exclusive
    `resource:<name>` claim (acquire in unitPrompt, release in integrator). `tests/test_relay_intensive.sh`.
  - **Remaining (item stays open)**: the tagging *criteria* doc — `references/conventions.md` /
    handoff.md guidance for strong children on WHEN to tag an item `[INTENSIVE — local-llm]`
    (cite the OOM + ~57s TTFT facts) — plus seeding the coarse per-repo `intensive` defaults in
    relay.toml for ai-codebench / zkm.
- [x] `/meeting` ↔ relay-loop mutual hold (holdable meeting while a pool is live) (done 2026-06-15) <!-- id:d748 -->
  - **Shipped 2026-06-15**: `meeting/SKILL.md` step 2a "Relay-pool claim hold" — before the 2b/2e
    shared-ledger write-back (relay-managed repos only), `/meeting` acquires the repo claim
    (`claim.sh acquire <repo> --run meeting-<session> --mode meeting`), does the write + releases;
    on refusal (a live pool holds it) it DEFERS the write-back (the meeting note already records the
    decisions) and never forces a write under a live pool claim. Read/think + the note are never
    blocked. `tests/test_meeting_claim_hold.sh` (`# roadmap:d748`). Reuses the id:ebfb claim registry.
  - **Context**: 2026-06-15 user request. `/meeting` writes the shared ledgers (TODO/ROADMAP/REVIEW_ME)
    in the MAIN checkout while the relay pool merges worktree branches into the same files (D2
    single-id-two-views; CLAUDE.md already notes md-merge.py + `orphan-scan.sh --cross-ledger` for
    residual drift). A meeting started mid-pool can collide at integration. Need a mutual-hold so the
    two actors don't write the shared ledgers concurrently.
  - **Acceptance (design)**: decide the yield direction — (a) `/meeting` detects a live pool (lease/
    runlock from id:7b7a) and HOLDS/queues its ledger writes until a safe point, or (b) the pool
    yields a short window to an interactive meeting, or (c) both coordinate via the same per-repo lease
    keyed on dotclaude-skills. Likely reuses id:7b7a's lease + single-writer helper rather than a
    separate mechanism. Must keep meeting's read/think phase unblocked (only the WRITE-BACK holds).
  - **RATIFIED 2026-06-15** (meeting 2026-06-15-1216): `/meeting` is a **consumer of the id:ebfb claim
    registry** — it holds (or takes) the dotclaude-skills claim for its ledger WRITE-BACK only; read/think
    phase stays unblocked. Build step 6 (last). Reuses the claim machinery; no parallel lock.
- [x] Relay integrator bottleneck — per-repo serialization, cross-repo concurrency (done 2026-06-15, reviewer) <!-- id:bc9d -->
  - **Context**: 2026-06-15 — investigating "the pool only runs ~1-wide". Work agents
    (review/execute/hard) DO run concurrently (harness cap `min(16, cores-2)`; I/O-bound API
    calls, no mutual block). The apparent serialism was the **single global integrator**
    (`integrationChain` promise chain, relay-loop.js): every repo's integration ran one-at-a-time,
    and each is a full Sonnet agent running 4 deterministic commands (merge --no-ff → ckpt-tag.sh
    → git-lock-push.sh → worktree prune), ~1–2 min each. Checkpoints are stamped at integration,
    so tags landed ~1–2 min apart no matter how wide dispatch was — that even spacing is what
    *looked* like a 1-wide pool. (The per-unit quota-agent throttle in 82a2dda was a separate,
    minor win, NOT this.)
  - **Fix shipped**: replaced the single `integrationChain` with a per-repo chain map
    (`integrationChains: Map<repo, tailPromise>`, `enqueueIntegration(repo, fn)`). Same-repo
    integrations still serialize (preserving review→execute re-chain ordering into one main
    checkout); DISTINCT repos integrate concurrently — distinct remotes don't conflict, and
    git-lock-push.sh still flocks per-repo for the residual same-remote case. This restates the
    D5/D6 invariant from "one concurrent integration per POOL" to "one per REMOTE", which is the
    only thing safety actually requires. Checkpoint throughput now scales with dispatch width.
  - **Tests**: `tests/test_relay_integrator_per_repo.sh` (`# roadmap:bc9d`) — no global
    integrationChain; enqueueIntegration keyed by repo; per-repo map get/set; drain awaits all
    chains; integration still not wrapped in parallel(). `test_relay_loop_structure.sh` (3)
    updated to the per-repo assertion.
  - **Follow-up (deferred, not blocking)**: integration agent could be Haiku and/or BATCH several
    repos per call to further cut the ~1–2 min/repo agent overhead — left for a later pass; the
    per-repo concurrency above is the primary throughput lever.
- [x] On-demand high-priority executor-task injection into the running pool [ROUTINE] (done 2026-06-15) <!-- id:baf1 -->
  - **Shipped 2026-06-15**: `relay/scripts/inject.sh` (`add`/`peek`/`take`, flock'd per-shard
    inbox `~/.config/relay/inject.d/`, consumed → `inject.done/`). relay-loop.js discovery
    runs `inject.sh take`; injected units carry `injected:true` + `inject_token`/`inject_item`/
    `inject_prompt`, sort AHEAD of every verdict class (both the normal and `--fable-down`
    schedulers), and SKIP the quota gate (explicit user request). Makefile + allowlist registered
    (id:5f09 lesson). `tests/test_relay_inject.sh` (`# roadmap:baf1`) green. Usage:
    `inject.sh add <repo> [--item <id>] [--verdict execute] [--prompt "…"]` — picked up next round.
  - **Deferred follow-ups (not blocking)**: RELAY_STATUS `peek` projection of pending injections;
    within-round latency (a lane re-checking `inject.d` between units — MVP is next-round-boundary).
  - **Context**: 2026-06-15 user request — "inject this executor task next with highest priority."
    A live control-plane: drop a task and the running pool picks it up ahead of its normal
    verdict-class schedule (execute→review→hard→handoff, id:da26) on the next round.
  - **Design (rides the cluster registry pattern, id:ebfb)**: an **injection inbox** the pool
    polls at each round's discovery — per-shard files `~/.config/relay/inject.d/<token>.json`,
    each one unit spec `{repo, item_id?, verdict (default execute/sonnet), prompt?, requested_at}`.
    A flock'd allowlisted helper `inject.sh <repo> [--item id] [--verdict execute] [--prompt ...]`
    writes the shard (so a human/other session enqueues without hand-editing JSON). Discovery reads
    inject.d at round start, converts each to a unit, and the scheduler places injected units at the
    FRONT of the queue (ahead of the class order). **Consume-once**: dispatched → shard moved to
    `inject.done/` (reuse the claim machinery so it isn't re-injected every round). Surface injected
    units in RELAY_STATUS.
  - **Open (minor, decide at build)**: latency = next round-boundary (MVP) vs within-round (a lane
    re-checks inject.d between units); injectable verdicts (execute-only vs any); always-top vs a
    priority field. Does NOT need a full /meeting — it's a contained extension of the ratified
    registry pattern (`docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md`).
  - **Why ROUTINE-with-care**: additive, but it touches the dispatch/PRIORITY ordering — reviewer
    should confirm an injected unit never starves the D3 review-after-execute invariant.
  - **Tests**: `tests/test_relay_inject.sh` — inject.sh writes a valid shard; discovery prepends it;
    consumed shard moves to inject.done and isn't re-dispatched. Hermetic.
- [x] Contract tests for relay install-completeness + quota-stop invocation (done 2026-06-15) <!-- id:5f09 -->
  - **Done 2026-06-15**: `tests/test_relay_install_manifest.sh` — (1) every `relay/scripts/*` is in
    the Makefile `relay_FILES` (and every `.sh` in `_EXEC`/`_ALLOW`), so a new helper can't ship
    un-symlinked; (2) relay-loop.js invokes `quota-stop.sh` with only its accepted flags
    (`--tier`/`--agents`/`--wall`, no bare positionals). Both 2026-06-15 contract gaps are now gated.
  - **Context**: On 2026-06-15 the default `/relay` autonomous pool was non-functional and
    the full suite was green. Two contract bugs shipped undetected: (1) the Makefile
    `relay_FILES`/`_EXEC`/`_ALLOW` lists omitted `scripts/quota-stop.sh` and
    `scripts/relay-loop.js`, so `make install` never symlinked the Workflow engine or the
    quota helper agents invoke by installed path; (2) `relay-loop.js`'s `quotaGate()` called
    `quota-stop.sh --tier T <agents> 0` with bare positionals, but the script only accepts
    `--tier/--agents/--wall` and exits 2 on anything else — tripping the fail-safe STOP on
    every gate check. Fixed in 5481502; tests did not catch either.
  - **Acceptance**: (1) a test asserts every `relay/scripts/*` file appears in the Makefile's
    `relay_FILES` (and every executable `.sh` in `relay_EXEC`/`relay_ALLOW`), so a new helper
    can't ship un-symlinked; (2) a test asserts the `quota-stop.sh` invocation string embedded
    in `relay-loop.js` uses only flags `quota-stop.sh` actually parses (`--tier/--agents/--wall`)
    — ideally by extracting the command and dry-running it, else by static flag-set match.
  - **Tests**: extend `tests/test_relay_loop_structure.sh` (quota-stop invocation) and add a
    Makefile-manifest check (new `tests/test_relay_install_manifest.sh` or fold into an existing
    install test); header `# roadmap:5f09`.
  - **Done-check**: tick this box, then full `make test` green.
- [x] De-fable checkpoint tags + durable model-tracked Fable-bonus-recheck queue [HARD — strong model] (done 2026-06-15, reviewer; merges id:e030) <!-- id:96a8 -->
  - **Acceptance**: `relay/scripts/ckpt-tag.sh` emits `relay-ckpt-YYYYMMDD-HHMM` annotated
    tags (not `fable-ckpt-*`); the RELAY_LOG.md append + the model+role annotation label are
    unchanged; existing `fable-ckpt-*` tags are never rewritten. `relay/scripts/relay-loop.js`
    finds the latest checkpoint / commit range / standin by matching BOTH prefixes
    (`git tag -l 'fable-ckpt-*' 'relay-ckpt-*' | sort | tail -1`), so a repo whose `last_ckpt`
    is still `fable-ckpt-*` keeps working across the boundary. `integrate()` writes a durable,
    model-tracked Fable-bonus-recheck queue into relay.toml on a STRONG (review/handoff/hard)
    checkpoint — `last_strong_ckpt`, `strong_model`, `fable_rechecked` — which an executor
    (sonnet) checkpoint never clears (masking fix, id:e030); the id:9821 elevation consults
    `strongRecheckPending` (un-rechecked strong ckpt) as an OPTIONAL, non-gating recheck
    candidate. The three relay.toml fields are documented in `relay/SKILL.md` (State) and
    `relay/references/conventions.md`.
  - **Tests**: `tests/test_relay_tag_scheme.sh` (`# roadmap:96a8`) — ckpt-tag.sh emits a
    `relay-ckpt-*` tag (hermetic run), label/RELAY_LOG unchanged; relay-loop.js dual-prefix
    matching + the three relay.toml fields + the strongRecheckPending consume wiring; docs
    mention the fields.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_tag_scheme.sh` then full `make test`.
- [x] `/fables-turn human` mode — cross-repo human-backlog triage (the human as 3rd actor) [ROUTINE] (done 2026-06-15, reviewer) <!-- id:2892 -->
  - **Acceptance**: `fables-turn/SKILL.md` documents a `human` mode — the invocation
    block carries `/fables-turn human [repo-list | --all]`, a `## Human mode` section
    describes the 3-tier triage and points at `references/human.md`, frames Opus as apex,
    and notes it generalizes the planned `review_me`. `references/human.md` exists and
    specifies the 3 tiers (AUTO-ANSWERABLE / BATCH-DECIDABLE / CHEWY), the
    `@manual`-never-auto-tick rule, and the tier-C → `/meeting --cross` routing.
    `scripts/gather-human-backlog.sh` is a read-only helper (`set -euo pipefail`, optional
    repo args, hermetic via `SRC_DIR`/`RELAY_TOML` overrides) that scans relay.toml `own`
    repos' `REVIEW_ME.md` for open `- [ ]` boxes and emits a TSV
    (`repo path kind box_summary`, `kind=review_me|manual`), flagging `@manual` boxes
    (REVIEW_ME and ROADMAP) as `kind=manual`; closed `- [x]` boxes are never emitted. The
    helper joins the Makefile `fables-turn` FILES/EXEC/ALLOW.
  - **Tests**: `tests/test_fables_human.sh` (`# roadmap:2892`) — SKILL.md documents the
    mode + invocation; references/human.md exists and specifies the 3 tiers +
    @manual-never-auto-tick + tier-C→/meeting --cross; gather-human-backlog.sh emits the
    TSV and flags @manual (hermetic fixture).
  - **Done-check**: `tests/run-tests.sh tests/test_fables_human.sh` then full `make test`
    after ticking.
  - **Context**: TODO id:72cc — codifies a hand-run procedure. Interactive strong-turn
    PROCEDURE (uses AskUserQuestion, so NOT a Workflow); mirrors handoff.md/review.md as
    reference-doc procedures. Per-repo commit in the main checkout (the /meeting REVIEW_ME
    write-back path, id:15d5), not a worktree merge. Opus is apex; an auto-answer is a
    CLAIM the next review re-checks (anti-gaming, downgrade a→b when unsure).
- [x] HARD-execute verdict + tested Fable-probe cache helper for the autonomous pool [HARD — strong model] (done 2026-06-15, reviewer) <!-- id:da26 -->
  - **Why HARD**: touches the dispatch contract in relay-loop.js (a new verdict class
    with an apex-only gate that must never leak HARD work onto the Sonnet execute tier),
    and the steady-state scheduling invariant. Wrong gating dispatches a doomed strong
    unit on Fable, or — worse — runs unbounded HARD work on Sonnet.
  - **Acceptance**: relay-loop.js gains a `hard` verdict (in DISCOVER_SCHEMA's enum +
    an `openHard` count). The classifier emits `hard` when a repo has NO unaudited
    commits, NO open `[ROUTINE]`, but ≥1 open `[HARD` item (precedence
    review > execute > hard > handoff > idle). `PRIORITY = { execute:0, review:1, hard:2,
    handoff:3 }`. A `hard` unit is DISPATCHED only when `STRONG_MODEL === 'claude-opus-4-8'`
    (apex); on Fable / the `-d` defer path it is left for Fable handoff-C5/review-step6 and
    surfaced in RELAY_STATUS Queued. NEVER on the Sonnet execute tier. The hard child works
    ONE bounded `[HARD]` item under handoff-C5 "only-if-small-enough" discipline, ticks the
    box only if genuinely green, and returns the standard report. Integration uses a
    `strong-execute (<model>, fable-standin, relay-loop)` checkpoint label. `scripts/probe-fable.sh`
    manages the front door's 2 h Fable-probe cache (`check` → fresh-available/fresh-unavailable/
    stale/absent; `set <true|false> [ts]`), hermetically testable (PROBE_CACHE override, no model).
    SKILL.md documents the `hard` verdict + references the helper in step 0.
  - **Tests**: `tests/test_relay_loop_structure.sh` (`# roadmap:83c9` + da26 §18 checks:
    enum, PRIORITY order, opus-only gate, Sonnet-never-HARD, strong-execute label, refDoc),
    `tests/test_probe_fable.sh` (`# roadmap:da26`) — fresh-available/unavailable, stale (>2h),
    absent, malformed, set-persistence, bad-arg.
  - **Done-check**: `tests/run-tests.sh tests/test_probe_fable.sh tests/test_relay_loop_structure.sh`
    then full `make test` after ticking.
  - **Context**: TODO id:da26 (c) — ratified 2026-06-15 (user): accept Opus doing `[HARD]`
    work while Fable is out. Built on the Opus-apex pivot (f64c28b). Reuses handoff.md C5,
    `worktreePathFor`/`branchFor`, and the existing `standInSuffix` logic.
- [x] Add a batched `say` subcommand to broker-curl.sh and route broker-mode.md through it [ROUTINE] <!-- id:3b02 -->
  - **Acceptance**: `broker-curl.sh <port> <session> say` reads plain-text lines from
    stdin and POSTs **one `/event` per line** (per-line painting in the renderer must
    be preserved — never collapse lines into a single event). A `--opener` first-line
    flag marks the first stdin line with `"kind":"opener"` for TTFL logging. Text with
    apostrophes/quotes/backslashes survives intact (JSON built with `jq -n --arg`
    internally). stdout stays quiet on success (HTTP responses discarded); curl/HTTP
    failures still reach stderr and exit non-zero. Empty stdin lines are skipped.
    `meeting/broker-mode.md` §Discussion is updated so the per-persona-line example
    uses ONE `say` call per agenda item instead of one Bash call per line (this is
    the actual ctx win: ~25–35 tool-call records/meeting → ≤10). Existing endpoints
    (`status events event question await response`) are unchanged.
  - **Tests**: `tests/test_broker_say.sh` (`# roadmap:3b02`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_broker_say.sh` then full `make test` after ticking
  - **Context**: `meeting/broker-curl.sh` (case-arm dispatch; keep the existing
    brace-default and quoting gotchas documented in CLAUDE.md §Gotchas),
    `meeting/broker-mode.md` (only the Discussion example block needs rewording —
    keep the "never batch into one event" semantics explicit). Mock broker fixture:
    `tests/fixtures/mock-broker.py`. TODO id:3b02 is the origin item — option (b)
    batching was chosen; do not also implement (a)/(c).
- [x] Add the Fable-class caveat to the γ-branch reference table in broker-mode.md [ROUTINE] <!-- id:44ba -->
  - **Acceptance**: in `meeting/broker-mode.md`, the `## γ-branch reference` section
    contains a visible Fable note attached to the table — either a `> **Fable note:**`
    blockquote directly under the table or a footnote marker on the three
    `AskUserQuestion` fallback rows (`MEETING_LIVE=0`, `subscribers=0`,
    `Broker unavailable`). The note must say that on Fable-class harnesses
    `AskUserQuestion` is replaced by inline-prose numbered prompts and point to
    `format.md §Interactive mode §Harness-class gate`. The `subscribers>0` row needs
    no caveat (broker routing makes the rendering limit irrelevant). Table content
    itself stays otherwise unchanged.
  - **Tests**: `tests/test_fable_caveat.sh` (`# roadmap:44ba`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_fable_caveat.sh` then full `make test` after ticking
  - **Context**: TODO.md "broker-mode.md γ-branch table missing Fable caveat" item;
    `docs/meeting-notes/2026-06-12-0749-fable-harness-interactive-mode-fix.md`.
    Prose cross-refs already exist elsewhere in the file — the fix is specifically
    AT the table, which is what gets skimmed.
- [x] Cover fables-turn and projects skills in the Makefile installer [ROUTINE] <!-- id:1ec1 -->
  - **Acceptance**: `make install-fables-turn` and `make install-projects` exist and
    symlink the skills into `$(DEST_DIR)` (override-able, default `~/.claude/skills`).
    fables-turn installs `SKILL.md`, `references/{handoff,review,conventions,templates}.md`,
    and `scripts/{discover-repos,ckpt-tag}.sh` (scripts chmod +x), creating the
    nested `references/` and `scripts/` directories under the destination —
    extend the `SKILL_RULES` template with a `mkdir -p` of each file's dirname
    rather than flattening paths. projects installs `SKILL.md` only. Both skills are
    in `SKILLS` so `make install`, `make status`, `make uninstall` cover them, and
    `make help` lists them. fables-turn's two scripts join the allowlist generation
    (`fables-turn_ALLOW`). Neither skill has LOCAL files. `make status-fables-turn`
    reports nested files correctly.
  - **Tests**: `tests/test_makefile_skills.sh` (`# roadmap:1ec1`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_makefile_skills.sh` then full `make test` after ticking
  - **Context**: `Makefile` (per-skill variable convention at top + `SKILL_RULES`
    define). The skill was hand-symlinked on 2026-06-12; the Makefile is the
    canonical installer and must not lag. Test with `DEST_DIR=$(mktemp -d)` —
    never the real `~/.claude`.
- [x] Add tools/ctx-budget.sh — per-skill SKILL.md token-budget audit [ROUTINE] <!-- id:32d6 -->
  - **Acceptance**: `tools/ctx-budget.sh [root]` (default: git toplevel) scans every
    `*/SKILL.md` in the repo and prints one TSV line per file:
    `<relpath>\t<est_tokens>\t<gate>\t<OK|WARN>`, where `est_tokens = bytes/4`
    (the repo's established chars/4 convention, same as cost-of.sh SIZE_KB/4) and
    `gate` is 2000 tokens by default, override via `CTX_BUDGET_GATE` env var.
    Files over gate get `WARN`; exit code is 0 either way (advisory logger, not a
    blocker — "observe before preventing"). A `--summary` flag prints only the WARN
    lines plus a final `total: N files, M over gate` line. Executable, `set -euo
    pipefail`, no dependencies beyond coreutils.
  - **Tests**: `tests/test_ctx_budget.sh` (`# roadmap:32d6`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_ctx_budget.sh` then full `make test` after ticking
  - **Context**: TODO.md "git-diary-workflow SKILL.md size audit" item and the
    global "per-prompt ctx multipliers" heuristic — mandatory-after-every-prompt
    skills multiply their size by prompt count, so their SKILL.md size needs a
    cheap recurring check. ARCHITECTURE.md §9 for the advisory-only philosophy.
- [x] Show the session token total in the statusline context segment [ROUTINE] <!-- id:2520 -->
  - **Acceptance**: `statusline/statusline-command.sh` line 1 displays the context
    segment as `<pct>%(<tokens>)` where `<tokens>` is `TOTAL_TOKENS` (input+output,
    already computed) humanized: `<1000` → as-is, `≥1000` → `N.Nk` with one decimal
    truncated to `Nk` when ≥10k (e.g. `115000` → `115k`, `9500` → `9.5k`, `730` →
    `730`). Same color as the existing context percentage. No new network calls, no
    layout change elsewhere on the line. Script must still produce output when run
    with `HOME` pointing at an empty temp dir (no credentials → fetch skipped).
  - **Tests**: `tests/test_statusline_tokens.sh` (`# roadmap:2520`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_statusline_tokens.sh` then full `make test` after ticking
  - **Context**: `statusline/statusline-command.sh` (CONTEXT_* block around line
    251–258; final echo at the bottom). Fixture stdin JSON:
    `tests/fixtures/statusline-input.json`. Origin: TODO.md "Statusbar: other
    cost-saving indicators" (this implements the first candidate; cache-read ratio
    is out of scope — it needs transcript parsing).
- [x] Extend the id-token ecosystem to ROADMAP.md (scan-ids, orphan-scan union, classify relay line) [HARD — strong model] <!-- id:de9c -->
  - **Why HARD**: cross-script invariant — three scripts must agree on what counts
    as the id-bearing ledger, and the wrong call silently reintroduces token
    collisions or orphan-scan false positives; also requires deciding how the
    classifier should treat relay-managed lines (judgment, not mechanics).
  - **Acceptance**: (1) `append.sh` gains a `scan-ids [<root>]` subcommand printing
    every existing `id:XXXX` token (one per line, sorted unique) from the ledger
    file set, which now includes `ROADMAP.md`; `new-id`/`new-ids` use the same scan
    so freshly minted tokens can never collide with roadmap ids. (2)
    `orphan-scan.sh` includes `ROADMAP.md` in the TODO-union read (forward and
    reverse modes): a meeting-note item whose token lives in ROADMAP.md is not an
    orphan. (3) `classify.sh` emits class `RELAY` for the TODO.md relay mirror line
    (`Relay: N open ROADMAP items`) so `/meeting` no-arg dispatch never proposes a
    meeting on it. Resolves TODO id:62f5 part (a).
  - **Tests**: `tests/test_id_ecosystem.sh` (`# roadmap:de9c`)
  - **Done-check**: `tests/run-tests.sh tests/test_id_ecosystem.sh`
  - **Context**: executed by the reviewer in this handoff turn (C5). See
    ARCHITECTURE.md §3.
- [x] Create the `fables-executor` skill: versioned SKILL.md + Makefile registration + test [ROUTINE] <!-- id:7691 -->
  - **Acceptance**: `fables-executor/SKILL.md` exists with `name`/`description` frontmatter
    and a `## Executor contract <!-- fables-executor contract v1 -->` heading carrying the
    5 rules verbatim + ROADMAP item format recap + RELAY_LOG conventions + Maintenance
    bump-rule note. `fables-executor` is in `Makefile` `SKILLS` with `_FILES := SKILL.md`
    and empty `_EXEC/_ALLOW/_LOCAL`. `dotclaude-skills/CLAUDE.md` `## Relay contract`
    section is the thin pointer (`<!-- fables-executor contract v1 -->`). Version-consistency
    grep: the `vN` in `fables-executor/SKILL.md` equals the `vN` in `CLAUDE.md`'s pointer.
    `fables-turn/references/conventions.md` no longer contains the fenced 5-rule block.
    `handoff.md` C1 and `review.md` step 4 reference the pointer, not the block.
  - **Tests**: `tests/test_fables_executor.sh` (`# roadmap:7691`)
  - **Done-check**: `tests/run-tests.sh tests/test_fables_executor.sh` then full `make test` after ticking
  - **Context**: meeting note `docs/meeting-notes/2026-06-12-1404-fables-executor-skill.md`;
    TODO id:fba6. The skill body + all reference-file edits may already exist from the
    review turn that wrote this item — verify before re-implementing.
- [x] Autonomous relay front-door: `/fables-turn` no-keyword default mode [HARD — strong model] (done 2026-06-12, reviewer) <!-- id:230f -->
  - **Why HARD**: redesigns the fables-turn SKILL.md trigger surface and dispatch logic; requires
    judgment on the unattended-safe confirmation contract and how the skill hands off to the Workflow engine;
    wrong front-door behaviour silently skips repos or blocks the unattended run.
  - **Acceptance**: invoking `/fables-turn` with no keyword (no `handoff`/`review` argument) starts the
    autonomous pool loop. Non-interactive by default: operates only on relay.toml `classification=own`
    confirmed repos; surfaces (never asks about) new/dirty/needs_review repos in `RELAY_STATUS.md`.
    `--interactive` flag re-enables `AskUserQuestion` confirmations. Front door invokes the
    `relay-loop.js` Workflow script (id:83c9) and exits after the Workflow completes, printing the
    RELAY_STATUS.md path and HANDBACK count. Existing `handoff` and `review` keyword modes are
    unchanged and fully compatible. SKILL.md updated to document the new default mode and the knobs
    (`STRONG_TIER`, `--interactive`, quota-threshold env var).
  - **Tests**: `tests/test_fables_front_door.sh` (`# roadmap:230f`) — verify (1) no-keyword invocation
    without relay.toml confirmed repos surfaces a message + exits cleanly; (2) `--interactive` flag is
    passed through to Workflow args; (3) existing keyword modes remain functional (dry-run check).
  - **Done-check**: `tests/run-tests.sh tests/test_fables_front_door.sh` then full `make test` after ticking
  - **Context**: meeting note `docs/meeting-notes/2026-06-12-2045-fables-relay-autonomous-pool.md` D1/D2.
    fables-turn/SKILL.md and relay-loop.js (id:83c9) must coexist. Workflows are opt-in by design (user
    invoking the command counts as explicit opt-in per harness rules — no extra gate needed).
- [x] Workflow script `relay-loop.js` — priority-mixed 5-wide autonomous pool [HARD — strong model] (done 2026-06-12, reviewer) <!-- id:83c9 -->
  - **Why HARD**: complex Workflow JS orchestrating pool concurrency, the serialized integrator, quota
    guards, and graceful drain — all interacting. Wrong sequencing causes concurrent pushes (the
    double-decrement bug from prior executor runs); wrong quota gate causes runaway or premature stop;
    wrong graceful-drain loses in-flight worktrees.
  - **Acceptance**: `fables-turn/scripts/relay-loop.js` is a valid Workflow script with `export const meta`.
    Scheduler: per-repo classifier maps confirmed repos to {execute(Sonnet)/review(strong)/handoff(strong)/idle};
    pool fills up to 5 execute slots first; backfills idle slots with review (unreviewed-executor-work priority
    > fresh handoff). SERIALIZED integrator: after each agent completes, ONE coordinator agent runs
    `--no-ff` merge → `ckpt-tag.sh` → `git-lock-push.sh --ff-only` — never two repos integrating concurrently
    (one-push-per-repo-per-turn invariant). Quota-stop: calls the id:9934 quota helper; on threshold crossed,
    stops dispatching new units and lets in-flight agents + ALL integration debt finish before `return`.
    `STRONG_TIER` env var (default `fable`, `opus` pilotable) sets `model:` on review/handoff agents.
    `log()` emits phase transitions; `RELAY_STATUS.md` rewritten on each integration.
    **Income preference (user directive 2026-06-12):** within a verdict class, repos flagged
    `income = true` in relay.toml are dispatched first; the class ordering itself is unchanged.
  - **Tests**: `tests/test_relay_loop_structure.sh` (`# roadmap:83c9`) — static checks: (1) `meta` block
    present with required fields; (2) no `AskUserQuestion` call in the script; (3) integration block
    serialized (no bare `parallel()` over the integration step); (4) `STRONG_TIER` variable referenced.
    Integration-behaviour tests deferred to the A6 pilot (live integration is too expensive for unit tests).
  - **Done-check**: `tests/run-tests.sh tests/test_relay_loop_structure.sh` then full `make test` after ticking
  - **Context**: meeting note D2/D3/D5. Gil's constraint: Workflow JS can't run git; the integrator MUST
    be an agent that calls the bash scripts. Petra's fallback (not default): if the in-script integrator
    proves unwieldy, the integrator agent returns branch names and the front-door turn integrates — but
    don't build the fallback pre-emptively. Reuses `scripts/ckpt-tag.sh`, `scripts/discover-repos.sh`,
    and `git-diary-workflow/git-lock-push.sh --ff-only`. See also id:9934 (quota helper) and id:aeaf (STRONG_TIER).
- [x] Tier-aware quota-stop helper for relay-loop.js [ROUTINE] <!-- id:9934 -->
  - **Acceptance**: `fables-turn/scripts/quota-stop.sh [--tier sonnet|strong]` (or a JS helper inline in
    relay-loop.js) reads `/tmp/claude-usage-cache.json` and exits 0 (below threshold) or 1 (at/above).
    Sonnet tier: stop if `seven_day_sonnet`, `five_hour`, OR `seven_day` utilization ≥ threshold
    (env `RELAY_QUOTA_THRESHOLD`, default 0.90 = 90%). Strong tier: stop if `five_hour` OR `seven_day`
    ≥ threshold. **Scale (review fix 2026-06-12):** the live cache stores `.utilization` as a
    0–100 percent (e.g. `37.0`), while `RELAY_QUOTA_THRESHOLD` is a 0–1 fraction — the script
    converts internally (`val >= threshold*100`). Tests must use percent-scale fixtures. Stale cache (mtime > 10 min) or missing file → print a warning to stderr and exit 2
    (caller treats as "stop, uncertain"); missing-key in JSON → same. Threshold 0.90 is the default;
    override via env for piloting. Seatbelt: if agent-count arg `N` ≥ 200 or wall-clock arg `S` seconds ≥ 7200,
    also exit 1 regardless of cache.
  - **Tests**: `tests/test_quota_stop.sh` (`# roadmap:9934`) — synthetic cache JSONs at 0.85/0.90/0.95
    utilization for each relevant bucket; stale/missing file; seatbelt cap triggers.
  - **Done-check**: `tests/run-tests.sh tests/test_quota_stop.sh` then full `make test` after ticking
  - **Context**: meeting note D5. `/tmp/claude-usage-cache.json` format is maintained by
    `statusline/statusline-command.sh` (keys: `five_hour`, `seven_day`, `seven_day_sonnet`, each with
    a `percent_used` or similar field — verify the exact key names from the statusline script before coding).
    NEVER call `/api/oauth/usage` directly (429s after ~5 requests total).
- [x] `STRONG_TIER` config knob in relay-loop.js and front-door SKILL.md [ROUTINE] <!-- id:aeaf -->
  - **Acceptance**: relay-loop.js reads `STRONG_TIER` env var (values: `fable` | `opus`, default `fable`);
    passes it as `model:` override to all review and handoff agent() calls. Front-door SKILL.md documents
    the knob: `STRONG_TIER=opus /fables-turn` or `--strong-tier opus` flag. Sonnet execute agents never
    receive the STRONG_TIER override. If `STRONG_TIER` is unset or empty, defaults to `fable`.
  - **Tests**: `tests/test_strong_tier_knob.sh` (`# roadmap:aeaf`) — verify the JS script references
    `STRONG_TIER` and the SKILL.md documents it (grep-based static check).
  - **Done-check**: `tests/run-tests.sh tests/test_strong_tier_knob.sh` then full `make test` after ticking
  - **Context**: meeting note D4. Opus model ID: `claude-opus-4-8`. fable-class model match: `claude-fable-5`.
    Workflow agent() `model:` override is a first-class field — no wrapper needed.
- [x] `RELAY_STATUS.md` cross-repo rollup writer [ROUTINE] <!-- id:80e2 -->
  - **Acceptance**: relay-loop.js writes/rewrites `~/.config/relay/RELAY_STATUS.md` (or a path
    configurable via `RELAY_STATUS_PATH` env var) on every integration and every phase transition.
    Template sections: `## In-flight` (repo, mode, agent-id), `## Completed this run` (repo, mode,
    ckpt-tag, push status), `## Queued` (repo, classifier verdict), `## Blocked / HANDBACKs` (repo,
    reason, worktree path), `## Quota remaining` (all three buckets with % remaining and reset time if
    available), `## REVIEW_ME open items` (per-repo count + path). Header: `# RELAY_STATUS — last updated
    <ISO timestamp>  run: <runId>`. File is overwritten each time (not appended). Also printed to `log()`
    as a condensed one-liner on each rewrite (so /workflows live view shows progress without the full file).
  - **Tests**: `tests/test_relay_status.sh` (`# roadmap:80e2`) — verify template sections present and
    non-empty for a synthetic completed-run payload; verify `log()` line appears in the condensed form.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_status.sh` then full `make test` after ticking
  - **Context**: meeting note "Surfacing (settled, no vote)". Per-repo REVIEW_ME.md stays the judgment-call
    channel (written by handoff/review children as before). RELAY_STATUS.md is read-only for humans —
    never edited by executor sessions.
- [x] Pilot autonomous pool on 1–2 income repos [HARD — strong model] (done 2026-06-12, run relay-20260612-2304: 6 integrated, 3 HANDBACKs recovered, quota drain verified; retrospective in RELAY_LOG.md 23:50 entry; Opus-handoff pilot NOT run — no handoff units classified; follow-ups id:bae5/59ea/1dff) <!-- id:1ad7 -->
  - **Why HARD**: first-contact with the real relay loop; templates and the executor contract will need
    revision after seeing actual unattended behaviour; judgment required on HANDBACK handling, REVIEW_ME
    quality, and whether priority-mixed scheduling converges as designed. Also the natural window to pilot
    `STRONG_TIER=opus` on handoff/review and compare output quality.
  - **Acceptance**: at least one complete unattended run on zkWhale or trAIdBTC (income repos) without
    manual intervention. `RELAY_STATUS.md` is produced **with all six template sections populated
    correctly — this is the behavioral check of the id:80e2 writer (its unit test is static-grep
    only; rescoped here by 2026-06-12 review)**. Any HANDBACKs are documented with root-cause.
    A short retrospective paragraph is appended to RELAY_LOG.md in this (dotclaude-skills) repo noting
    what needed revision and whether the Opus-handoff pilot was run.
  - **Tests**: none (pilot output is the deliverable; follow-on fixes get their own tests/items)
  - **Done-check**: `RELAY_STATUS.md` exists post-run; retrospective paragraph committed to RELAY_LOG.md here.
  - **Context**: meeting note A6 / D3 / D6. Gate: id:230f (front door) + id:83c9 (relay-loop.js) + id:9934
    (quota helper) must all be implemented first. Do not run fleet-wide until at least one income-repo
    pilot validates the design. This item is the verification gate before `--all` runs.
- [x] `--fable-down` / `-d` flag for executor-only relay runs (Fable inaccessible) [HARD — strong model] (done 2026-06-13, reviewer) <!-- id:3737 -->
  - **Why HARD**: touches the dispatch contract in relay-loop.js (pool partitioning, zero-execute edge,
    deferred-unit surfacing) plus the SKILL.md front-door (Opus self-guard, Workflow args pass-through,
    invocation block, knobs table). Wrong placement would silently skip the Opus guard or fail to
    surface deferred units, masking the outage.
  - **Acceptance**: `--fable-down`/`-d` flag parsed by the front door and passed as `args.fableDown`
    into `relay-loop.js`. When set: (1) review and handoff units are partitioned out of the dispatch
    queue and surface in RELAY_STATUS Queued with reason `deferred: --fable-down, strong model skipped`;
    (2) execute (Sonnet) units proceed normally; (3) zero-execute edge exits cleanly with a log line;
    (4) integrator, quota gate, and drain logic are untouched. Opus self-guard in SKILL.md Default-mode
    step 0: if the session model is `claude-opus-*` and `-d` is not set, print a warning + `sleep 10`
    before launching the Workflow; suppressed when `-d` is set. Auto-probe deferred (forward-compatible:
    a future probe sets `args.fableDown = true` identically).
  - **Tests**: `tests/test_fable_down_flag.sh` (`# roadmap:3737`) — 11 static-grep checks
  - **Done-check**: `tests/run-tests.sh tests/test_fable_down_flag.sh` then full `make test` ✓
  - **Context**: meeting note `docs/meeting-notes/2026-06-13-0825-fable-down-detection.md`;
    https://www.anthropic.com/news/fable-mythos-access (access pull announced).
- [x] Separate Fable-availability from fallback policy (two-switch: `-d` × `STRONG_TIER`) [ROUTINE] <!-- id:5902 -->
  - **Acceptance**: `--fable-down`/`-d` asserts ONE axis only — "the Fable strong tier is
    unavailable this run" — and composes with `STRONG_TIER` (which chooses WHICH strong
    model review/handoff agents use). The FABLE_DOWN defer/demote block in `relay-loop.js`
    is gated on `FABLE_DOWN && STRONG_MODEL === 'claude-fable-5'`: (1) `-d` alone (STRONG_TIER
    `fable`) → defer strong work, executor-only (prior id:3737 behaviour, preserved exactly);
    (2) `-d` + `STRONG_TIER=opus` (STRONG_MODEL `claude-opus-4-8`) → SUBSTITUTE Opus, skip the
    defer block, dispatch review/handoff normally on Opus (already marked `fable-standin` by
    `standInSuffix`). Startup `log()` and explanatory comment describe both axes. SKILL.md
    knobs row documents defer-vs-substitute; a `/fables-turn -d --strong-tier opus` usage
    example is added near the STRONG_TIER examples.
  - **Tests**: `tests/test_fable_down_strong_tier.sh` (`# roadmap:5902`) — static-grep that the
    defer block is gated on `STRONG_MODEL === 'claude-fable-5'`, that no ungated `if (FABLE_DOWN) {`
    remains, and that SKILL.md documents the substitute combo + usage example.
  - **Done-check**: `tests/run-tests.sh tests/test_fable_down_strong_tier.sh` then full `make test` ✓
  - **Context**: follow-up to id:3737. The `-d` flag conflated "Fable unavailable" with "defer
    all strong work"; STRONG_TIER already chose the strong model, so the two compose. Opus
    model ID `claude-opus-4-8`; Fable-class match `claude-fable-5`.
- [x] [ROUTINE] `gaming-scan.sh` — mechanical gaming detector extracted from `review.md` §2 (done 2026-06-15) <!-- id:fa05 -->
  - **Source**: id:2909 meeting 2026-06-15 (`docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md`), Piece 1 / D2-D3.
  - **Spec**: `relay/scripts/gaming-scan.sh`, `set -euo pipefail`, args `<repo-root> <since-tag>`. Emits one parseable flag line per mechanical detection:
    - deleted test file: `git diff "$since"..HEAD --diff-filter=D --name-only -- '<test-dirs>'`
    - added `skip`/`xfail`/`.only`/`@pytest.mark.skip` in test files
    - removed `assert`/expectation lines without an equivalent addition in test files
  - **Acceptance**: `tests/test_gaming_scan.sh` (roadmap:fa05) — crafted minimal git repos/diffs: (a) deleted test file → flag emitted; (b) added `@pytest.mark.skip` → flag; (c) removed `assert` line → flag; (d) clean diff (e.g. implementation file only changed) → SILENT. At least one negative control (a legitimate green diff that must NOT flag, modelled on the id:3b02 resurrection case from RELAY_LOG: only input line changed, assertions intact). `make test` green.
- [x] [ROUTINE] `review.md` §2 delegate rewrite — single source of truth (done 2026-06-15) <!-- id:dfaf -->
  - **Source**: id:2909 meeting 2026-06-15 (`docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md`), Piece 2 / D3. **Depends on id:fa05 shipping first** (script must exist before prose delegates to it).
  - **Spec**: rewrite `relay/references/review.md` §2 so it: (a) invokes `gaming-scan.sh <repo-root> $LAST` as the mechanical pass and surfaces its output; (b) retains prose ONLY for the judgment-residue checks (resurrection-check + fixture-special-casing); (c) removes the inlined `--diff-filter=D` / `skip`/`xfail` grep one-liners from prose (they now live in the script). Single source of truth: script owns mechanical, prose owns judgment.
  - **Acceptance**: static-grep test (`tests/test_gaming_scan.sh` or a sibling) asserts `review.md` references `gaming-scan.sh` and does NOT contain the old literal one-liners (`--diff-filter=D`, `xfail`, `skip` inline in §2). `make test` green.
- [x] [ROUTINE] Supervisor flag-rate logger in `relay-loop.js` `integrate()` (done 2026-06-15) <!-- id:3826 -->
  - **Source**: id:2909 meeting 2026-06-15 (`docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md`), Piece 4 / D1-D3.
  - **Spec**: in `relay-loop.js` `integrate()`, after the `gaming_flags` / `verified_green` / `reopened` fields are available in the review `report`, append a line to `~/.claude/logs/relay-gaming-flags.log` with JSON fields: `{repo, runId, ts, closed_ids, gaming_flags, reopened, verified_green}`. Create the log file if absent. Also add a comment block at the append site: `// DEFERRED-FLEET SEAM: to escalate, spawn parallel() refuters over gaming_flags[] or verified_green[] here; see id:2909 meeting 2026-06-15 D1 for the evidence gate.`
  - **Acceptance**: `tests/test_gaming_logger.sh` (roadmap:3826) — construct a synthetic `report` object with non-empty `gaming_flags` and call the relevant integrate path (or extract the logger into a standalone function that can be called from a test harness); assert the log file receives a line containing the expected repo name, runId, and flag id. `make test` green.
- [x] [HARD — strong model] Tier B model canary harness for gaming-detection judgment checks (done 2026-06-16) <!-- id:414a -->
  - **Done 2026-06-16** (relay HARD child): `tests/gaming-canary/` ships three crafted
    fixtures — `resurrection-rewrite/` (executor rewrote the test ASSERTION to match buggy
    `str(a)+str(b)` output; expects FLAG), `fixture-special-casing/` (impl branches on the
    exact test-input literals 6/28/12 instead of computing the divisor sum; expects FLAG),
    and the `negative-control-input-only/` (real id:3b02 shape — only the test INPUT changed,
    assertion structure + a genuine impl fix intact; expects EMPTY). Each fixture's diff is
    ≤20 lines. `tests/gaming-canary/run.sh` feeds each fixture + a compact review.md §2b
    judgment prompt to one review-style agent (`claude -p --output-format json` by default,
    `CANARY_AGENT` override for token-free plumbing tests; unwraps the claude JSON envelope;
    SKIPs—never false-passes—when no agent is present) and asserts the `gaming_flags`
    contract. `make gaming-canary` invokes it; it is excluded from `run-tests.sh` (globs
    `tests/test_*.sh`) so `make test` stays zero-token. The harness PLUMBING is
    regression-guarded token-free by `tests/test_gaming_canary.sh` (Tier A, in the default
    sweep) using stub agents — pins the FLAG/EMPTY/envelope/no-agent/determinism contract.
  - **Source**: id:2909 meeting 2026-06-15 (`docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md`), Piece 3 / D2. **NOT in `run-tests.sh` default sweep** — zero-token; invoked manually via `make gaming-canary`.
  - **Why HARD**: fixtures are prepared mini git repos containing *intentionally crafted gamed diffs* for the judgment checks (resurrection-check, fixture-special-casing) that gaming-scan.sh deliberately does NOT cover mechanically. The harness spawns one review-style agent per fixture and asserts the `gaming_flags` contract — the design of convincing-but-detectable fixtures requires strong-model craft.
  - **Spec**: `tests/gaming-canary/` directory: (a) at least one resurrection-rewrite fixture (an executor rewrote a test's `assert` to match whatever the code returns); (b) at least one fixture-special-casing fixture (code branches on exact test-input literals); (c) at least one **negative control** (a legitimate green resurrection where only the test INPUT changed and assertions stayed intact — must NOT flag). `tests/gaming-canary/run.sh` feeds each fixture diff to a compact review-procedure prompt and checks `gaming_flags`/absence. `Makefile` target `gaming-canary` invokes `run.sh`.
  - **Acceptance**: `make gaming-canary` executes: positive fixtures yield non-empty `gaming_flags`; negative control yields empty `gaming_flags`. The harness itself must not be flaky on identical inputs. Keep each fixture minimal (≤20 lines of diff) so the judgment is unambiguous.
  - **Gate CLEARED 2026-06-15** (audit run 4): id:fa05 (gaming-scan.sh) and id:dfaf (review.md §2 delegate) both shipped — `review.md` now references `gaming-scan.sh` (3×) and the script exists, so the review procedure this harness invokes already delegates mechanical checks. The item is dispatchable; it is HARD because crafting convincing-but-detectable fixtures needs strong-model judgment, not because of an unmet dependency.
- [x] [ROUTINE] memory-index lint: add `user:`-prefix + emphasis-preservation invariants to `--check` <!-- id:7d97 -->
  - **Why now**: `tools/memory-index.py --check` currently proves only that the index is
    *derivable* from the memory files. It does NOT compare hook TEXT against the previous
    committed state, so a bulk rewrite can preserve every `id:`/`routed:` token,
    `[[wiki-link]]`, status lexeme, link target and entry count — and still silently change
    meaning. That is not hypothetical: on 2026-07-10 an Opus compaction agent passed exactly
    that invariant set while stripping the `user:` prefix from 14 of 15 `feedback-*` hooks
    (`user: don't improvise` → `don't improvise`) and flattening emphasis in 62 more. The
    prefix marks a hook as a directive from the user rather than an observation.
  - **The before-state is free**: the memory dir lives in the `~/.claude/projects` git repo
    with hourly auto-commits, so the check diffs the worktree against `git show HEAD:<path>`
    — no snapshot plumbing.
  - **Contract a test would verify**: `--check` exits non-zero and names the entry when (a) a
    hook that began `user:` in HEAD no longer does; (b) a hook loses a `**bold**` / `ALL-CAPS`
    emphasis token present in HEAD; (c) an unchanged index is a clean no-op; (d) a brand-new
    memory (absent from HEAD) is NOT flagged. Keep it a diff-vs-HEAD check, not a style rule.
  - **Out of scope**: the semantic-drift residual a lint cannot decide (a hook rewritten with
    every token intact and different meaning). That stays an LLM-review job, fires only on
    entries whose hook changed, and must fail loudly. Do NOT try to mechanize it.
  - Parent `id:2e6d` (TODO). Not the settings.json wiring — that is the user's call, `[INPUT]`.
- [x] Rename relay state dirs `~/.{config,cache}/fables-turn` → relay naming [HARD — strong model] (done 2026-06-17; code-rename only — the data migration was left half-done, see id:bbd2 for the proper completion) <!-- id:10c0 -->
- [x] Complete the id:10c0 state-dir migration properly + fix the split-brain regression [HARD — strong model] (done 2026-06-17, TDD) <!-- id:bbd2 -->
  - **What broke**: code defaulted to `~/.config/relay` but `relay.toml` was still at `~/.config/fables-turn` and both dirs were real (no symlink) → `gather-human-backlog.sh` silently returned an empty `/relay human` backlog. `migrate-state-dirs.sh` existed but was buggy (skip-on-collision → never symlinked) and never installed/run.
  - **Fix**: rewrote `migrate-state-dirs.sh` to reconcile collisions (merge `*.jsonl` union, union dirs, newest-mtime snapshot, drop `*.lock`), env-overridable for hermetic tests, exit 3 on idle-guard refusal. Spec'd by `tests/test_migrate_state_dirs.sh` (9 cases). Ran for real: old dirs → symlinks→`relay`, events merged 347+12→358 (no loss), gather returns 48 on default path. `make install-relay` linked it. Suite 66/66.
  - **Why HARD**: not the mechanical sed (33 `fables-turn` refs across 13 executable
    files + ~25 docs) but the LIVE-migration / back-compat design call. These are live
    dirs an in-flight pool reads/writes (relay.toml registry, RELAY_STATUS.md,
    relay-events.jsonl, quota-samples.jsonl, fable-probe.json, worktrees/) — needs a
    one-time `mv` + back-compat (symlink-old→new or fallback-read) so a running pool /
    cross-session lease isn't broken mid-migration.
  - **Back-compat design call — RESOLVED 2026-06-17 (Opus apex, via `/relay human`):**
    **symlink-old→new + run-when-idle, symlink kept permanently as the safety net.**
    Migration script `relay/scripts/migrate-state-dirs.sh` does, in order: (1) PRECONDITION
    — refuse unless no relay pool is active (no fresh `RELAY_STATUS.md` touch within
    `RELAY_ACTIVE_SECS`, and `claim.sh` registry shows no live holder); (2) `mkdir -p
    ~/.config/relay ~/.cache/relay`; (3) `mv` the contents over; (4) replace each old dir
    with a symlink `~/.config/fables-turn → ~/.config/relay`, `~/.cache/fables-turn →
    ~/.cache/relay`. The symlink is the load-bearing back-compat net: any straggler
    process, cross-session lease, un-updated ref, or older checkout still resolves the old
    path correctly, so there is NO window where old-path access fails (the only
    non-atomic gap is between mv and symlink — sub-second, and the idle precondition
    covers it). Rejected alternatives: dual-read fallback in code (churns every accessor,
    no upside over a symlink) and hard cutover with no net (re-introduces the
    in-flight-breakage risk the symlink eliminates). Keep the symlink indefinitely — it is
    cheap and is the only thing protecting a pool that started before the migration.
  - **Acceptance** (now UNGATED — bounded hard-execute): (1) `migrate-state-dirs.sh` exists
    with the idle-precondition guard and is idempotent (re-run is a no-op once symlinks
    exist); (2) the 33 `fables-turn` refs across the 13 executable files are updated to the
    new canonical `relay` path in the same change (the symlink covers anything missed, but
    new code reads the new name); (3) git tags `fable-ckpt-*` are NOT touched (constraint
    a — scope is the cache/config DIRECTORIES only; the dual-prefix reader already handles
    tag history); (4) `make test` green; (5) a test asserts the migration's idle-guard
    refuses while a pool looks active. Run only when no pool is active (the script's own
    precondition enforces this). HARD retained for the live-migration care, but the design
    call is made — dispatchable as an Opus hard-execute unit.
  - **Done 2026-06-17** (Opus hard-execute): `relay/scripts/migrate-state-dirs.sh` ships —
    idle-precondition guard (refuses while RELAY_STATUS.md is fresh within
    `RELAY_ACTIVE_SECS` OR `claim.sh peek` shows a live holder), then `mkdir -p
    ~/.config/relay ~/.cache/relay` → `mv` contents (skip-existing for resumability) →
    replace each old dir with a permanent `old→new` symlink (the back-compat net).
    Idempotent: once old is a symlink, a re-run is a no-op. The env-var defaults in the 11
    accessor scripts + `relay-loop.js`'s `RELAY_STATUS_PATH`/`RELAY_EVENTS_PATH` constants,
    `worktreePathFor`, and its prompt-text `~/.cache/relay/worktrees` /
    `~/.config/relay/relay.toml` references now read the canonical `relay` path; the
    fables-turn symlink covers any straggler. Git tags untouched (constraint a). Test:
    `tests/test_relay_migrate_state_dirs.sh` (roadmap:10c0) — guard-refuses (forced +
    fresh-status), migrate-moves-and-symlinks, idempotent re-run, and a no-legacy-default
    grep over the 11 scripts. `test_relay_status.sh` / `test_relay_discovery_guards.sh`
    path assertions updated to the new name. `make test` green.
- [x] A1 — `[MECHANICAL]` capability tag + `mechanical` verdict [ROUTINE] <!-- id:7616 -->
  - **Why** (meeting 2026-07-02-1924 decision 1; TODO id:7616): the taxonomy needs a
    fourth capability tier for pure-compute work no LLM or human runs — local-LLM
    benchmarks, pytorch, pilots — dispatched to a host daemon (A3, gated) while an LLM
    session reviews the artifact. This item adds ONLY the tag + verdict plumbing so the
    tier is recognized additively; it does NOT build the daemon consumer.
  - **Acceptance**:
    1. `relay/scripts/roadmap-lint.sh` ACCEPTS `[MECHANICAL]` as a recognized class tag —
       standalone (`- [ ] title [MECHANICAL] <!-- id -->`) and composed with the orthogonal
       resource modifier (`[MECHANICAL] [INTENSIVE — local-llm]`). A `[MECHANICAL]`+`[INTENSIVE]`
       item is grammar-clean; a `[MECHANICAL]`+`[HARD — pool]` item is a tag/prose lane
       conflict (case c) exactly as two hard lanes would be (MECHANICAL is a capability lane,
       INTENSIVE is not).
    2. `relay/scripts/gather-human-backlog.sh` keeps a `[MECHANICAL]` item OUT of every human
       lane bucket — a repo whose only open item is `[MECHANICAL]` (no `[HARD]`) emits NO
       hard_pool/hard_meeting/hard_hands/manual/review_me line and does NOT trip the untagged
       LOUD-reject (exit 0, empty).
    3. `relay/scripts/classify-verdict.sh` emits a NEW `mechanical` verdict for a
       MECHANICAL-only repo: given gather JSON with `open_mechanical >= 1` and nothing
       higher-priority (no actionable routine / unaudited / hard-pool / promote / surface),
       `verdict == "mechanical"`. It is POOL-INERT — never `execute`/`hard`; the `intensive`
       field stays `""` on it (the id:5ac6 invariant `intensive!="" ⇒ verdict∈{execute,hard}`
       holds unchanged). A higher-priority class (open `[ROUTINE]`, etc.) still outranks it.
    4. Document the `[MECHANICAL]` capability + `mechanical` verdict in
       `relay/references/hard-lanes.md` (as an additive capability tier alongside the resource
       axis, noting the slice-B rename is where it folds into the two-axis vocabulary).
  - **Tests**: `tests/test_mechanical_tag.sh` (`# roadmap:7616`) — hermetic fixtures: (a)
    roadmap-lint accepts `[MECHANICAL]` standalone + `[MECHANICAL] [INTENSIVE — local-llm]`,
    rejects `[MECHANICAL] [HARD — pool]` conflict; (b) gather-human-backlog emits nothing for
    a MECHANICAL-only repo; (c) classify-verdict emits `verdict==mechanical` (intensive="") for
    `open_mechanical>=1` and `execute` still wins when a routine item co-exists; (d) hard-lanes.md
    names `[MECHANICAL]`. RED until landed.
  - **Context**: `roadmap-lint.sh` class_re + case-c lane count; `gather-human-backlog.sh`
    emit_hard_lanes (only touches `[HARD` lines); `classify-verdict.sh` priority cascade + the
    `open_mechanical` field it must read; the minimal `open_mechanical` wiring in gather is
    part of this item. Do NOT build A3's daemon. Cross-ref B1/B2 (rename, gated).
- [x] A2 — recipe manifest schema + drop-dir contract + `recipe-validate.sh` [ROUTINE] <!-- id:64d3 -->
  - **Why** (meeting 2026-07-02-1924 decision 3; TODO id:64d3): the mechanical-run daemon
    (A3, gated) consumes relay-authored recipes from a drop-dir. This item pins the recipe
    JSON schema, the `{pending,running,done}/` lifecycle-dir contract, and a LOUD validator
    so a malformed recipe never reaches the daemon. WHITELISTED — recipes are relay-authored
    only, NEVER auto-scanned from ROADMAP (the registry is the gate, not a tag; devil's-
    advocate Riku's constraint).
  - **Acceptance**:
    1. A reference doc (`relay/references/recipe-manifest.md`) specifies: the drop-dir
       `~/.config/relay/recipes/{pending,running,done}/` lifecycle (relay authors into
       `pending/`; daemon moves `pending → running → done`); and the recipe JSON schema
       `{id, repo, cmd, host, est_wall, resource, acceptance_artifact}` with each field's type
       (`id`/`repo`/`cmd`/`host`/`resource`/`acceptance_artifact` strings, `est_wall` a
       positive integer seconds). States explicitly: whitelisted / relay-authored / never
       auto-scanned from ROADMAP.
    2. `relay/scripts/recipe-validate.sh <recipe.json>` validates one recipe against the
       schema: exit 0 + silent on a well-formed recipe; exit NONZERO with a LOUD `ERROR:`
       stderr line naming the FIRST offending field on ANY missing key, wrong type, or
       empty/ non-positive `est_wall`. No silent coercion.
    3. Config-dir path is env-overridable (`RELAY_RECIPE_DIR`, default
       `~/.config/relay/recipes`) for hermetic testing.
    4. `recipe-validate.sh` registered in the Makefile `relay_FILES`/`relay_EXEC`/`relay_ALLOW`
       (3×) and the doc in `relay_FILES` (id:69ef install-completeness).
  - **Tests**: `tests/test_recipe_manifest.sh` (`# roadmap:64d3`) — hermetic tmpdir: a
    complete valid recipe passes (exit 0); each of the 7 fields removed in turn → nonzero +
    `ERROR:` naming that field; a non-integer / zero / negative `est_wall` → nonzero; the doc
    exists and names the drop-dir + all 7 fields + "whitelisted"/"never auto-scanned"; Makefile
    registers the script 3× and the doc. RED until landed.
  - **Context**: mirror `acquire-resource.sh`/`resource-claims.md` for the script+doc+Makefile
    idiom (`tests/test_resource_claim.sh` steps 6–7). Schema fields come from the meeting note
    decision 3. Do NOT build the daemon (A3) or wire `inject.sh`.
- [x] A4 — `permitted-intensity.json` + `relay-intensity.sh` graded-window CLI [ROUTINE] <!-- id:e407 -->
  - **Why** (meeting 2026-07-02-1924 decision 4; TODO id:e407): the binary `ALLOW_INTENSIVE`
    gate is all-or-nothing. Replace it (conceptually) with a GRADED, time-boxed permit — "tea"
    (15m/light) vs "lunch" (2h/heavy) — so a human can authorize a bounded intensive window
    that auto-expires. The relay-loop.js engine wiring is RISKY (crash-prone template-literal
    lint, the a0b6 hazard class) and is a FOLLOW-UP note below, NOT required for this item's
    green — the executor-buildable slice is the config file + CLI + predicate with a hermetic
    test.
  - **Acceptance**:
    1. `~/.config/relay/permitted-intensity.json = {max_wall_seconds, resource_ceiling,
       expires_at}` is the on-disk permit; path env-overridable via `RELAY_INTENSITY_FILE`.
    2. `relay/scripts/relay-intensity.sh` CLI writes/reads it:
       - `--for 15m --light` (tea) and `--for 2h --heavy` (lunch) write a permit with the
         parsed wall-seconds + tier + an `expires_at` = now + the `--for` duration;
       - `--afk` writes the CONSERVATIVE default (a minimal short window that does NOT permit a
         heavy resource — bare `--afk` is NOT full intensive, preserving the old binary
         semantics);
       - `--clear` removes the permit; `--status` prints the current permit (or "none").
    3. `relay-intensity.sh permits <est_wall> <resource>` is the predicate: exit 0 IFF
       `est_wall <= max_wall_seconds` AND the resource fits the ceiling AND `now < expires_at`;
       exit nonzero otherwise (no permit / expired / over-window / over-ceiling). Absent or
       expired permit → nonzero (conservative — deny by default).
    4. Back-compat: a `--intensive` flag writes a permissive window (superseding binary
       `ALLOW_INTENSIVE`); bare `--afk` stays conservative (§2). Document the supersession.
    5. FOLLOW-UP (NOT required for green, note only): `relay-loop.js` reading the permit in
       place of the binary `ALLOW_INTENSIVE` gate is a separate engine edit (`node --check` +
       `lint-workflow-templates.mjs` + structure tests) — do it early-session if attempted,
       else leave as a tracked follow-up.
  - **Tests**: `tests/test_permitted_intensity.sh` (`# roadmap:e407`) — hermetic
    `RELAY_INTENSITY_FILE` override: no permit → `permits 60 cpu` nonzero; `--for 2h --heavy`
    → `permits 3600 local-llm` exit 0; over-window (`permits 9000 local-llm`) nonzero; a
    `--light`/`--for 15m` window does NOT permit a heavy resource (`permits 60 local-llm`
    nonzero) but permits a light one within window; an expired `expires_at` (write then
    hand-edit / `--for 0`) → nonzero; `--clear` → nonzero; `--status` prints the window; bare
    `--afk` refuses a heavy job. RED until landed.
  - **Context**: the resource→tier mapping (which resource names count "heavy") is the
    executor's judgment — the test pins only the monotonic property (a heavy resource passes
    a `--heavy` window and fails a `--light` one); REVIEW_ME records the mapping call. Parse
    `--for` as `<N>m`/`<N>h`/`<N>s`. Do NOT touch relay-loop.js for green (§5).
- [x] A5 — `resource-probe.sh` check-and-defer arbitration [ROUTINE] <!-- id:68dc -->
  - **Why** (meeting 2026-07-02-1924 decision 4; TODO id:68dc): auto-launch of an intensive
    mechanical run needs a LIVE-availability probe on top of the permit window (A4) — measured
    VRAM/RAM/load AND no competing `resource:<res>` claim. **Check-and-defer, NEVER preempt**
    (Riku: suspending an in-flight embed-rebuild can corrupt the index; active-suspend is a
    gated cross-repo enhancement, routed:f506, out of scope here).
  - **Acceptance**:
    1. `relay/scripts/resource-probe.sh <resource>` probes availability of a named resource:
       `gpu` via nvidia-smi when present, else a GRACEFUL "unavailable" with a stated reason
       (never a crash / non-zero from a missing binary being fatal); `ram` via `/proc/meminfo`;
       `cpu` via loadavg (`/proc/loadavg`); `local-llm` = claim-only (no hardware metric —
       availability is purely "no competing claim").
    2. It ALSO reads `claim.sh peek` (sharing `CLAIM_BASE`) and reports NOT available when a
       LIVE `resource:<res>` claim is held — check-and-defer, never preempt.
    3. Thresholds are env-overridable (e.g. `RESOURCE_PROBE_RAM_MIN_MB`,
       `RESOURCE_PROBE_LOAD_MAX`); the nvidia-smi binary is env-overridable
       (`RESOURCE_PROBE_NVIDIA_SMI`, default `nvidia-smi`) so the probe is testable without a
       real GPU.
    4. Emits ONE JSON object `{resource, available, reason, ...metrics}` on stdout and an exit
       code: 0 when available, nonzero when not.
  - **Tests**: `tests/test_resource_probe.sh` (`# roadmap:68dc`) — hermetic `CLAIM_BASE`
    (mktemp): `cpu` with a generous `RESOURCE_PROBE_LOAD_MAX` and no claim → `available:true`,
    exit 0; then `claim.sh acquire resource:cpu` → probe reports `available:false` + nonzero
    (check-and-defer); `gpu` with `RESOURCE_PROBE_NVIDIA_SMI` pointed at a nonexistent binary →
    graceful `available:false` with a reason, no crash; `ram` output is valid JSON with an
    `available` boolean; a low RAM threshold override flips availability deterministically. RED
    until landed.
  - **Context**: compose `claim.sh peek` (reads `CLAIM_BASE`, safekey `resource_<res>`, JSON
    `.key=="resource:<res>"`) — do NOT add a second lock/registry. Never preempt/kill a holder.
    Register in Makefile 3×. Pairs with A4 (permit window) as the two launch conditions.
- [x] M1 — handoff.md C2 PRODUCES the MECHANICAL tag + authors the recipe [ROUTINE] <!-- id:9c88 -->
  - **Why** (meeting amendment 2026-07-02, M1; TODO id:9c88): the missing PRODUCER link. A1
    taught the classifier to recognize `[MECHANICAL]`→`mechanical`, but `handoff.md` C2 still
    only ever tags `[ROUTINE]`/`[HARD — *]` — so the tag is routed but never produced and
    nothing feeds the daemon (A3). Teach C2 to recognize compute-only / no-LLM /
    benchmark-or-pilot work (leAIrn2learn, pytorch, model-probe-style batteries) and (i) TAG
    it `[MECHANICAL]` (composing `[INTENSIVE — <res>]` when heavy) and (ii) AUTHOR the A2
    recipe (the `relay/references/recipe-manifest.md` schema, id:64d3 —
    `{id,repo,cmd,host,est_wall,resource,acceptance_artifact}`) into
    `~/.config/relay/recipes/pending/`. This is a CONTRACT-PROSE change to `handoff.md`; no
    script logic changes.
  - **Acceptance**:
    1. `handoff.md`'s C2 checkpoint documents recognizing compute-only / no-LLM /
       benchmark-or-pilot work as `[MECHANICAL]` (alongside the existing `[ROUTINE]` /
       `[HARD — *]` tagging), naming the concept.
    2. C2 documents AUTHORING an A2 recipe into `~/.config/relay/recipes/pending/` for such an
       item, referencing the `recipe-manifest.md` schema (id:64d3) — the producer link to the
       A3 daemon.
  - **Tests**: `tests/test_handoff_produces_mechanical.sh` (`# roadmap:9c88`) — a STRUCTURAL
    grep-style test (like `tests/test_hard_lane_buckets.sh`) asserting `handoff.md` C2 carries
    the `[MECHANICAL]`-tagging instruction AND the recipe-authoring instruction (the pending/
    drop-dir + recipe-manifest reference). RED until the prose lands.
  - **Context**: prose only, in `relay/references/handoff.md` §C2 (roadmap checkpoint, the
    tagging paragraph ~L60–73). Pairs with A3 (the daemon that consumes the authored recipe).
    Do NOT touch any script.
- [x] M2 — re-lane DOCTRINE routes compute-only work to MECHANICAL (fix the wrong-to-hands producer sites) [HARD — pool] <!-- id:2313 -->
  - **Why** (meeting amendment 2026-07-02, M2; TODO id:2313): three CONTRACT doc sites still
    route scriptable / no-human / no-LLM "run X" work to `[HARD — hands]` (the human), even
    though `[MECHANICAL]` now exists and a daemon (A3) can run it. `gather-human-backlog.sh`
    already excludes `[MECHANICAL]` from human buckets in CODE (slice-A A1); M2 is the
    DOC/doctrine layer that TEACHES the strong turn to produce `[MECHANICAL]` instead of
    mis-laning to hands. ORTHOGONAL to B2 (the vocabulary rename) — a routing change that must
    survive B2.
  - **Acceptance** (all three doc sites carry the new routing):
    1. `hard-lanes.md` 5-criterion re-lane policy (~L88–101) gains a "needs an LLM?" branch:
       compute-only + passes a–e ⇒ `[MECHANICAL]` (daemon); LLM + passes a–e ⇒
       `[ROUTINE]`/`[HARD — pool]`; fails a–e (needs a human) ⇒ `[HARD — hands]`.
    2. `handoff.md` author-then-run split (~L93–106) routes the daemon-runnable "run X" residue
       to `[MECHANICAL]`, keeping only genuinely-human runs (device/sudo/physical/credential)
       as `[HARD — hands]`.
    3. `human.md` (the "you run these" checklist, ~L158–168/194/287) EXCLUDES `[MECHANICAL]`
       from the human "you run these" list — it is daemon-run, not human-run.
  - **Tests**: `tests/test_mechanical_relane_doctrine.sh` (`# roadmap:2313`) — a STRUCTURAL
    grep test asserting all THREE doc sites (`hard-lanes.md`, `handoff.md`, `human.md`) name
    `[MECHANICAL]` in their re-lane / author-then-run / you-run-these routing. RED until the
    prose lands.
  - **Context**: prose only, across `relay/references/{hard-lanes.md,handoff.md,human.md}`.
    Do NOT rename any existing lane (that is B2). The CODE-layer exclusion already exists
    (`gather-human-backlog.sh` only inspects `[HARD` lines) — this is the doctrine that keeps
    producers from emitting `[HARD — hands]` for daemon-runnable work in the first place.
- [x] A3 — mechanical-run daemon [HARD — pool] <!-- id:b3d0 -->
  - **Why** (meeting 2026-07-02-1924 decision 3; TODO id:b3d0): the host `--user` `.path`-unit
    that runs pending recipes → artifact → `inject.sh` review, OUTSIDE the Workflow (pure
    mechanical → no permission wall; sidesteps the babysitter/outage problem). Model-probe
    topology (`tools/quota-sample.*` + `tools/relay-watchdog.*` are the existing instances of
    the systemd-`--user` → mechanical-script → git-JSONL/notify pattern). UN-GATED: deps
    64d3 + e407 + 68dc all landed.
  - **Acceptance**:
    1. `relay/scripts/mechanical-daemon.sh` performs ONE processing tick (a subcommand, e.g.
       `run`/`tick`) over the recipe drop-dir: for each recipe in `pending/`, VALIDATE it
       (`recipe-validate.sh`); check the launch gate — `relay-intensity.sh permits <est_wall>
       <resource>` AND `resource-probe.sh <resource>` both succeed; if permitted, move
       `pending → running`, run `cmd` (which writes the `acceptance_artifact`), move
       `running → done`, and drop a review-request via `inject.sh add`. If NOT permitted
       (resource claimed OR est_wall over the window OR resource unavailable) the recipe is
       DEFERRED — left in `pending/`, NOT run, no artifact, no inject (check-and-defer, never
       preempt).
    2. Dirs are env-overridable for hermeticity: `RELAY_RECIPE_DIR` (default
       `~/.config/relay/recipes`, holds `pending/running/done`), `RELAY_INTENSITY_FILE`,
       `CLAIM_BASE`, `INJECT_BASE` — all threaded to the sibling scripts.
    3. A systemd `--user` `.path` unit watches `~/.config/relay/recipes/pending/` and triggers
       a oneshot service that runs the tick (`tools/` topology, alongside quota-sample /
       relay-watchdog units). `make install-mechanical-daemon` installs+enables them.
    4. `mechanical-daemon.sh` registered in the Makefile `relay_FILES`/`relay_EXEC`/`relay_ALLOW`
       (id:69ef install-completeness).
  - **Tests**: `tests/test_mechanical_daemon.sh` (`# roadmap:b3d0`) — REAL hermetic tests
    (mktemp `RELAY_RECIPE_DIR`/`CLAIM_BASE`/`INJECT_BASE`/`RELAY_INTENSITY_FILE`): (1) a valid
    recipe whose gate PERMITS runs — recipe moves `pending→running→done`, its
    `acceptance_artifact` is written, and an inject unit appears; (2) a recipe whose resource
    is CLAIMED is DEFERRED — stays in `pending/`, no artifact, no inject; (3) a recipe whose
    `est_wall` EXCEEDS the permit window is DEFERRED likewise. RED until the daemon lands.
  - **Context**: reads all three slice-A helpers at launch (`recipe-validate.sh`,
    `relay-intensity.sh permits`, `resource-probe.sh`); shares the ONE `claim.sh` registry via
    `CLAIM_BASE` (no second lock). Check-and-defer ONLY — never suspend/kill a claim holder
    (active-suspend is routed:f506, out of scope).
- [x] B1 — target taxonomy → `hard-lanes.md` north star + `lane-convert.sh` converter + dual-vocab lint window [HARD — pool] <!-- id:4f02 -->
  - **Why** (meeting 2026-07-02-1924 decision 2; TODO id:4f02): the SAFETY-NET-FIRST half of
    the rename. Before any reader flips (B2), ship (i) the north-star vocabulary in
    `hard-lanes.md` as a BOTH-VOCAB table, (ii) a `roadmap-lint.sh` that DUAL-ACCEPTS old and
    new vocab (neither an ERROR during the window), and (iii) a DETERMINISTIC converter that
    performs the unambiguous renames and FLAGS (never auto-converts) the one ambiguous case
    (`[HARD — hands]`→`[MECHANICAL]` candidate). This item OPENS the dual-vocab window; the
    eventual old-vocab→ERROR FLIP that CLOSES it is deliberately NOT here (it is the tail of
    B2, after every reader + this repo's ledgers are migrated).
  - **Acceptance**:
    1. **North-star write** — `relay/references/hard-lanes.md` documents the ratified two-axis
       taxonomy as the north star, with a BOTH-VOCAB mapping table (old `[HARD — *]` spelling →
       new capability tag). The three unambiguous rows are 1:1 (`[HARD — pool]`→`[HARD]`,
       `[HARD — meeting]`→`[INPUT — meeting]`, `[HARD — decision gate]`→`[INPUT — decision]`); the
       `[HARD — hands]` row shows its FOUR candidate destinations `{[MECHANICAL] | [INPUT — access]
       | [INPUT — decision] | [INPUT — meeting]}` (per-item human judgment, NOT a single target).
       State explicitly that the dual-vocab window is OPEN (both spellings accepted ERROR-free) and
       that the old→ERROR flip lands at the end of B2. Keep the existing `[MECHANICAL]` +
       `[INTENSIVE]` sections coherent with the new axes.
    2. **`roadmap-lint.sh` DUAL-ACCEPTS** — extend the recognized `class_re` so BOTH the old
       lanes (`[HARD — pool|meeting|hands|decision gate]`) AND the new vocab (bare `[HARD]`,
       `[INPUT — meeting]`, `[INPUT — decision]`, `[INPUT — access]`; `[MECHANICAL]` already
       accepted) are ERROR-free class tags. Neither vocabulary is a violation during the window.
       The lane set is READ from `hard-lanes.md` (single source) — extend the extraction to pick
       up the new `[HARD]`/`[INPUT — …]` forms, do NOT hardcode a second copy. GOTCHA: bare
       `[HARD]` is NOT a substring of `[HARD — pool]` (the em-dash + space intervene), so a
       naive `[HARD]` match will not false-fire on old-vocab items — but the case-c two-lane
       conflict counter must not double-count an item that (correctly) carries exactly one new
       OR one old lane. An item carrying an old lane AND its new rename simultaneously (e.g.
       `[HARD — pool]` + `[HARD]`) SHOULD still be a case-c conflict (never both).
    3. **`relay/scripts/lane-convert.sh <ledger-file>`** — a deterministic TEXT transform (not a
       lane-parser) over a ROADMAP/TODO file. AUTO-APPLY the THREE UNAMBIGUOUS 1:1 renames on the
       exact bracket strings ONLY: `[HARD — pool]`→`[HARD]`, `[HARD — meeting]`→`[INPUT — meeting]`,
       `[HARD — decision gate]`→`[INPUT — decision]`. **`[HARD — hands]` is NEVER auto-converted**
       (it fragments four ways — see the section intro): LEAVE the line UNCHANGED and SURFACE it on
       STDERR as a needs-judgment flag naming its FOUR candidate destinations (`[MECHANICAL]`,
       `[INPUT — access]`, `[INPUT — decision]`, `[INPUT — meeting]`) + the item's file:line + id,
       deferring the decision to M3 (id:3ef7) / human. The converter emits NO default for hands.
       `[ROUTINE]` / `[MECHANICAL]` / `[INTENSIVE — <res>]` and the `🚧 route:*` auto-gate aliases
       pass through UNCHANGED. IDEMPOTENT — re-running on already-converted output is a no-op (a
       still-present `[HARD — hands]` re-flags but is not rewritten, so the text is stable). Default
       is stdout (or `--in-place`); the test fixture is the contract.
    4. **Makefile registration** — `lane-convert.sh` in `relay_FILES`/`relay_EXEC`/`relay_ALLOW`
       (3×, id:69ef install-completeness).
    5. Do NOT flip any reader (that is B2) and do NOT run the converter on this repo's ledgers
       yet (also B2). B1 is the additive safety net ONLY.
  - **Tests**: `tests/test_lane_convert.sh` (`# roadmap:4f02`) — hermetic tmp fixtures:
    (a) `roadmap-lint.sh` exits 0 on a ROADMAP whose items use the NEW vocab (bare `[HARD]`,
    `[INPUT — meeting|decision|access]`) AND on one using the OLD vocab (dual-accept); an item
    with two lanes (old + its new rename on one line) still exits nonzero (case-c conflict);
    (b) `lane-convert.sh` on a fixture AUTO-APPLIES the three unambiguous renames exactly
    (`[HARD — pool]`→`[HARD]`, `[HARD — meeting]`→`[INPUT — meeting]`,
    `[HARD — decision gate]`→`[INPUT — decision]`); (c) EVERY `[HARD — hands]` item (plain AND
    `[INTENSIVE]`-composed) is LEFT UNCHANGED in stdout and SURFACED on STDERR naming all four
    candidate destinations — never auto-`[INPUT — kind]` and never auto-`[MECHANICAL]`; (d)
    `[ROUTINE]` / `[MECHANICAL]` / `[INTENSIVE — res]` lines are untouched, and a second pass is a
    no-op (idempotent). RED until B1 lands.
  - **Context**: `roadmap-lint.sh` class_re + hard-lanes-extraction (L54–86) + case-c counter
    (L165–176); the new-vocab north-star lives in `hard-lanes.md`. The converter is a NEW
    sibling script — mirror the `host-gate.sh`/`recipe-validate.sh` script+Makefile idiom. The
    `[HARD — hands]` fan-out is inherently a per-item JUDGMENT (four destinations) — the converter
    only SURFACES it (detector-surfaces/human-decides, M3 id:3ef7); the fixtures pin the
    never-auto-default + four-candidate-flag invariant.
- [x] Tag-first reorder tool + tag-first lint (WARN) — the C-endgame capability, built ahead of 7df1's run [ROUTINE] <!-- id:4b37 -->
  - **Why** (meeting 2026-07-06-0959, d259 RATIFIED endgame = (C) tag-truly-first bracketed position): the reorder tool + lint are PURE tooling with no cross-repo dependency, so they build now (ungated), decoupled from 7df1's gated *execution*. Building them here shrinks id:7df1 to "run the built tool + flip the lints to ERROR". (A)'s parser-hardening floor already shipped (id:0d58); the tag-first WARN *split-brain* floor shipped as id:ad8a — this is a DISTINCT check (below).
  - **How / spec** (D2 — ISOLATED, separately-tested; do NOT bolt onto lane-convert.sh's 1:1-rename flow):
    1. **Reorder mode** — `lane-convert.sh --reorder` (or a sibling `lane-reorder.sh`) that, on a `- [ ]`/`- [x]` line ONLY, moves the anchored primary lane token PLUS any adjacent orthogonal `[INTENSIVE — <res>]` (order preserved) to immediately after the checkbox, strips it from the old position, and leaves body brackets + the trailing `<!-- id:XXXX -->` untouched. IDEMPOTENT (already-first ⇒ no-op). Invoked in the SAME `--in-place` pass as the rename when 7df1 runs (touch-once), but its logic is a separate unit.
    2. **Tag-first lint (WARN)** — `roadmap-lint.sh` gains a "the lane tag is the FIRST non-whitespace token after the checkbox" check, emitted as WARN (report-only, exit 0) during the dual-vocab window. This is distinct from ad8a's raw-vs-backtick-stripped split-brain detector. It flips to ERROR only in 7df1's final window-close step (a hard ERROR now would false-fire on every not-yet-reordered old-vocab line).
  - **Tests**: `tests/test_lane_reorder.sh` (`# roadmap:4b37`) — hermetic tmp fixtures, ADVERSARIAL: (a) `- [ ] **title** [ROUTINE] <!-- id -->` → `- [ ] [ROUTINE] **title** <!-- id -->`; (b) multi-tag `[MECHANICAL] [INTENSIVE — r5-jvm]` moves BOTH, order preserved; (c) a Why-body / non-checkbox line that merely mentions a backtick'd `[HARD — pool]` is UNCHANGED (not a checkbox line); (d) already-first line is a no-op (idempotent); (e) a prose `[bracket]` in an item's body is untouched. Plus a `roadmap-lint.sh` WARN-not-ERROR assertion for a tag-not-first line during the window. RED until built.
  - **Context**: `relay/scripts/lane-convert.sh` (B1's converter, id:4f02) + `relay/scripts/roadmap-lint.sh` (ad8a WARN floor at the `first_lane_tag` helper). Makefile registration (relay_FILES/EXEC/ALLOW, id:69ef) if a sibling script. Dispatch: background relay handoff (RED) → Sonnet executor (anti-gaming split, per d259 decision 4). Feeds id:7df1 (which then only RUNS the tool + flips lints). Meeting: `docs/meeting-notes/2026-07-06-0959-machine-tag-format-endgame.md`.
- [x] B2 — lane-READERS + references + engine (relay-loop.js) dual-accept the new vocabulary [HARD] <!-- id:8111 -->
  - **RE-SCOPED + verified 2026-07-02 (relay review, wave-2b).** The shipped B2a (parsers+refs)
    + B2b (relay-loop.js engine) dual-accept slice is genuinely DONE and verified both directions
    (old-vocab still buckets/dispatches everywhere; new vocab buckets/classifies correctly; no
    test gamed; suite green). The remaining B2c work — CONVERT this repo's own ledgers, MIGRATE
    the ~30 lane-asserting tests, and CLOSE the dual-vocab window (old-vocab → lint ERROR) — was
    split out to id:7df1 (GATED), because the window cannot close while M3 (id:3ef7) and the
    cross-repo `[HARD — hands]`/scan.py (id:b466) surfaces are still on old vocab. This item is
    the reader+reference+engine dual-accept migration ONLY.
  - **Why** (meeting 2026-07-02-1924 decision 2; TODO id:8111): with B1's converter + dual-vocab
    window in place, flip every lane-READER and reference to EMIT/EXPECT the new vocabulary
    (still ACCEPTING old via B1's window). `[HARD — hands]` items are only FLAGGED, never
    auto-converted (the FOUR-candidate fan-out is per-item judgment, deferred to M3/7df1).
  - **Acceptance (shipped — B2a + B2b):**
    - **B2a — readers + references.** Flip the tag-PARSERS and prose to the new vocab (dual-accept):
      1. `gather-human-backlog.sh::emit_hard_lanes` buckets new vocab: bare `[HARD]`→`hard_pool`,
         `[INPUT — meeting]`/`[INPUT — decision]`→`hard_meeting`, `[INPUT — access]`→`hard_hands`;
         old spellings still accepted during the window. (Today an `[INPUT — …]` line is silently
         skipped — it does not even match `/\[HARD/`.)
      2. `classify-repo.sh` `LANE_TAGS`/`HUMAN_GATES` + primary-lane parse + `gather-repo-state.sh`
         `open_hard_pool` anchor recognize the new vocab (bare `[HARD]` counts as pool; `[INPUT — …]`
         are human-gates, excluded from actionable/pool counts).
      3. References `human.md`, `review.md`, `conventions.md`, `handoff.md` re-worded to the new
         vocabulary (old spellings noted as recognized aliases during the window).
    - **B2b — `relay-loop.js` (the crash-prone engine).** Update the verdict-schema enum comments
      and any HARD-string regexes (`unitIsSubstantive` reason regex `/\[HARD —|no open \[HARD — pool\]/`,
      the row-detail strings) to also match the new vocab. The numeric `open_hard_pool` demote-guard
      is tag-agnostic (unaffected). **ENGINE-EDIT CAUTION:** `node --check` + `lint-workflow-templates.mjs`
      + `test_relay_loop_structure.sh` must pass (the a0b6 template-literal-lint hazard crashed the
      pool 3×) — do this early-session, NOT tail-of-session.
    - **B2c — this-repo ledgers + tests + window close.** ➡️ SPLIT OUT to id:7df1 (GATED) — NOT
      part of this item's done-state. See the finalizer item below.
  - **Done-check (met 2026-07-02)**: `node --check relay/scripts/relay-loop.js` +
    `lint-workflow-templates.mjs` clean; `test_relay_loop_structure.sh` green;
    `tests/test_lane_vocab_migration.sh` green; full suite `tests/run-tests.sh` 0 failed;
    dual-accept proven both directions for `gather-human-backlog.sh` / `classify-repo.sh` /
    `gather-repo-state.sh` / `relay-loop.js`.
  - **Tests**: `tests/test_lane_vocab_migration.sh` (`# roadmap:8111`) — the verifiable slice:
    `gather-human-backlog.sh` buckets a repo whose ROADMAP uses the NEW vocab (bare `[HARD]`→a
    `hard_pool` line; `[INPUT — meeting]`→a `hard_meeting` line; `[INPUT — access]`→a `hard_hands`
    line). GREEN as of B2a. The relay-loop.js regex + classify-repo parse flips are verified by
    review spot-checks + the ~30 old-vocab tests still passing (dual-accept).
- [x] classify-repo.sh open_mechanical must be LANE-ANCHORED, not a bare substring [ROUTINE] <!-- id:0d58 -->
  - **Why** (TODO id:0d58): `classify-repo.sh` has two disagreeing tag readers on an open
    `- [ ]` ROADMAP line. The primary-lane derivation (~line 102, id:4da4) is positionally
    ANCHORED — the FIRST recognized `LANE_TAGS` token wins; backtick/prose mentions further
    right are ignored. But the `open_mechanical` counter (~line 93, `if "[MECHANICAL]" in ln`)
    is a BARE SUBSTRING test outside that anchoring — `[MECHANICAL]` is not in `LANE_TAGS`. So an
    open item whose REAL lane is `[HARD — pool]`/`[ROUTINE]` but that merely mentions a
    backtick'd `` `[MECHANICAL]` `` on the same line falsely increments `open_mechanical`, which
    drives the priority-6 `mechanical` verdict (classify-verdict.sh:146, `open_mechanical >= 1`)
    and can mis-fire it on a repo that has no genuine mechanical work.
  - **How**: make the `open_mechanical` count LANE-ANCHORED the same way the primary-lane parse
    is — only a line whose PRIMARY lane is `[MECHANICAL]` counts (e.g. add `[MECHANICAL]` to
    `LANE_TAGS` and gate the increment on `primary == "[MECHANICAL]"`). Do NOT touch
    classify-verdict.sh's priority cascade; the false positive is purely the count.
  - **Acceptance**: `tests/test_mechanical_lane_anchor.sh` (`# roadmap:0d58`, RED until fixed)
    goes GREEN: (1) a `[ROUTINE] @manual` / `[HARD — pool]` open item mentioning a backtick'd
    `` `[MECHANICAL]` `` does NOT count in `open_mechanical` (via `--emit unit`) and does NOT
    yield the `mechanical` verdict; (2) a GENUINE `[MECHANICAL]`-primary item STILL counts and
    STILL classifies `mechanical` (no over-correction to zero). `make test` fully green.
- [x] `[MECHANICAL]` recipes must write an EXPLICIT success/failure marker into the acceptance_artifact [ROUTINE] <!-- id:fd37 -->
  - **Why** (TODO id:fd37, pilot finding — mechanical-daemon's first real firing on zkWhale
    id:0a7b, 2026-07-03): a recipe whose `cmd` is e.g. `pnpm -s typecheck` writes an EMPTY
    `acceptance_artifact` on success (tsc is silent-on-clean). An empty artifact is an
    ambiguous acceptance signal — indistinguishable from "never ran / redirect failed". The
    daemon's own success/fail branch is ALREADY correct (exit-code driven: it writes a
    `.error` sibling only when the cmd exits non-zero), so this is purely about the ARTIFACT
    a reviewer inspects.
  - **How**: `[MECHANICAL]` recipe `cmd`s must append an explicit terminal success/failure
    marker to the acceptance_artifact AND preserve the real exit code so the daemon's branch
    still fires. Canonical safe pattern (document verbatim as the reference):
    `cd <repo> && { <realcmd> > "$ART" 2>&1; rc=$?; echo "MARKER exit=$rc finished=$(date -Is)" >> "$ART"; exit $rc; }`.
    Two enforcement surfaces: (1) DOC — `references/recipe-manifest.md` documents the
    explicit-marker + exit-preservation requirement in its schema/acceptance section, and the
    M1 producer site (`handoff.md` C2 / `executor-contract.md`) instructs the recipe author to
    include the marker. (2) OPTIONAL CODE — `recipe-validate.sh` emits a NON-FATAL advisory
    (stderr WARNING, still exit 0) when a `cmd` redirects into the acceptance_artifact but
    carries no explicit marker / exit-preservation. Keep validate's existing 7-field schema
    hard-fail UNCHANGED — the marker check is advisory only (validate can't fully parse
    arbitrary shell, so keep it a heuristic that won't over-flag a correct recipe).
  - **Acceptance**: `tests/test_recipe_success_marker.sh` (`# roadmap:fd37`, RED until fixed)
    goes GREEN: (a) `recipe-manifest.md` documents the explicit-marker + exit-preservation
    doctrine; (b) `recipe-validate.sh` WARNs on stderr (exit still 0) for a redirect-without-
    marker cmd; (c) NO warning for a cmd carrying the canonical `exit=$rc` marker (no false
    positive). `make test` fully green.
- [x] `roadmap-lint.sh` case-c must count only BARE (non-backtick'd) lane tags [ROUTINE] <!-- id:9078 -->
  - **Why** (TODO id:9078, owner-signed-off option a): case-c (id:09a3) counts ALL lane
    brackets on an open `- [ ]` line, including backtick-QUOTED ones (`echo "$line" | grep -qF`
    on the raw line, ~lines 229-244). That FALSE-POSITIVES the compliant id:0d58/fb7f/c3f5
    shape — a genuine primary lane tag followed by a LATER backtick'd lane MENTION
    (prose/history), e.g. `[HARD — pool] … see the old note `` `[ROUTINE]` `` …` — because the
    quoted bracket is counted as a second lane and the item is loud-rejected as a "tag/prose
    lane conflict". This is a real dispatch-blocking false positive on conforming items.
  - **How**: narrow case-c to count only lane tags OUTSIDE backticks — before the lane count,
    strip backtick-quoted spans, then flag the conflict IFF ≥2 BARE lane tags survive. REUSE
    the existing backtick-strip helper already in this file: `first_lane_tag`'s `strip=1`
    branch (id:1bbd/ad8a) does exactly `search="$(printf '%s' "$line" | sed -E 's/`[^`]*`//g')"`.
    Apply the same strip to the case-c line before the `grep -qF` lane counting (or count bare
    tags via a stripped copy of `$line`). Do NOT change the id:ad8a tag-first WARN, case-d, or
    the grammar clauses. This deliberately RETIRES case-c's unreliable "prose disagrees with
    tag" intent (id:244b) — mechanically undetectable, and its harmful sub-case (a prose bracket
    BEFORE the genuine tag) is already covered by the id:ad8a tag-first rule.
  - **Acceptance**: `tests/test_roadmap_lint_casec_backtick.sh` (`# roadmap:9078`, RED until
    fixed) goes GREEN: (a) the compliant c3f5 shape (genuine bare tag + LATER backtick'd
    mention) PASSES lint (exit 0, no case-c conflict diagnostic); (b) a genuine TWO-BARE-tag
    conflict (`[HARD — pool] [ROUTINE]`, both un-backtick'd) is STILL loud-rejected. The
    repointed `tests/test_roadmap_lint_tagprose.sh` case-c fixture (now a genuine two-bare
    conflict) STILL passes. `make test` fully green.
- [x] Make the 'mechanical' verdict REPRESENTABLE + SURFACED (never DISPATCHABLE), mirroring 'human' [ROUTINE] <!-- id:d310 -->
  - **Why** (findings verified 2026-07-10 against live code + a running pool): `classify-verdict.sh`
    emits `verdict=mechanical` (priority_rank 6) for a repo whose only remaining backlog is open
    `[MECHANICAL]` items, but `relay-loop.js` OMITTED 'mechanical' from its shard verdict enum and
    from `PRIORITY`. So the first repo whose only backlog was `[MECHANICAL]` produced a verdict its
    own runner's structured output could not validate — and it sorted as `NaN`, silently dropped.
    CRITICAL INVARIANT (classify-verdict.sh:180): mechanical work is POOL-INERT — a host daemon
    dispatches it (A3, gated), NEVER the LLM pool. It must become REPRESENTABLE + SURFACED, never
    DISPATCHABLE — exactly how 'human' is handled (present in enum + PRIORITY rank 5, absent from
    `PHASE_BY_VERDICT`, never spawns an executor child).
  - **Done** (2026-07-10): (1) added `'mechanical'` to the DISCOVER_SCHEMA verdict enum (reused by
    SHARD_SCHEMA) so the shard output validates; (2) added `mechanical: 6` to `PRIORITY` (matches
    classify-verdict's priority_rank) + a mechanical-surface partition that pulls mechanical units
    out of `actionable` before dispatch and spreads them into `state.queued` (RELAY_STATUS Queued)
    with a pool-inert / host-daemon reason — no agent is ever spawned (contrast 'human's file-surface
    agent); (3) repaired the three `## [LANE] … (relay handoff 2026-07-03)` heading-as-item
    roadmap-lint violations (dropped the lane tag from the section headers whose child items are
    already `[x]`-tagged — the two `[MECHANICAL]` ones named in id:baf1 plus the sibling `[ROUTINE]`
    one from the same batch, needed for lint to reach exit 0); (4) `tests/test_relay_mechanical_verdict.sh`
    (`# roadmap:d310`) asserts the full round-trip: classify-verdict emits it, it validates against
    the shard enum, ranks 6, is surfaced, and is NEVER dispatched (absent from `PHASE_BY_VERDICT`,
    pulled from `actionable`, no agent). Updated `test_relay_loop_structure.sh`'s pinned enum +
    PRIORITY assertions. NOT in scope: the verdict→recipe bridge (A3, deliberately gated → /meeting).
    `make test` fully green; `roadmap-lint.sh` clean.
- [x] [ROUTINE] D1 — park unmerged orphans on discovery (done 2026-06-16) <!-- id:689c -->
  - **Source**: `docs/meeting-notes/2026-06-16-0938-relay-orphan-reconcile.md` D1; TODO id:689c.
  - **Context**: today the commits-ahead branch of discovery (`relay/scripts/relay-loop.js`
    ~:569, the id:3ac8 path tested by `test_relay_stale_worktree_reap.sh`) only SURFACES a
    commit-bearing stale worktree as "needs manual integration" and leaves the directory in
    place, so the `ls worktrees/` scan re-surfaces it every round forever.
  - **Spec**: change that path to PARK the orphan instead of re-surfacing: `git worktree remove
    --force <dir>` (stops the re-surface) then `git branch -m relay/<runId>-<v>
    relay/orphan/<runId>-<v>` (the stranded commit stays reachable on the canonical
    `relay/orphan/*` ref — NOT deleted, NOT auto-integrated). Emit ONE summary line, not a
    per-round handback. No `--no-ff` merge in this path (parking is not integration).
  - **Acceptance**: `tests/test_relay_orphan_park.sh` (roadmap:689c, RED until implemented) —
    asserts the discovery prompt carries the `id:689c` marker, parks into `relay/orphan/*` via
    `git branch -m`, removes the worktree dir, and describes parking (not the old surface-only
    handback). Behaviourally: a seeded stale worktree + 1 commit → dir gone, `relay/orphan/<…>`
    ref present carrying the commit, one summary line, idempotent across two discoveries.
  - **Done-check**: tick this box, then `tests/run-tests.sh tests/test_relay_orphan_park.sh`,
    then full `make test` green.
- [x] [ROUTINE] D2 — scripted `/relay reconcile` mode (human-invoked) (done 2026-06-16) <!-- id:3313 -->
  - **Source**: meeting 2026-06-16-0938 D2; TODO id:3313. **Sequence: after D1 (id:689c).**
  - **Spec**: a human-invoked reconcile path (script `relay/scripts/relay-reconcile.sh` or a
    documented mode in the relay skill) that enumerates `relay/orphan/*` across managed repos and,
    per branch, offers {integrate | discard | leave}. Integrate MUST reuse the existing
    verify-clean-main → `git merge --no-ff` → `ckpt-tag.sh` → `git-lock-push.sh --ff-only` path
    (no CAS plumbing — `--no-ff` preserves 3-way conflict surfacing; reusing ckpt-tag + --ff-only
    stops a human skipping the checkpoint tag or racing the live pool's push). Discard is
    `git branch -D`. NEVER auto-triggered by the pool.
  - **Acceptance**: `tests/test_relay_reconcile_mode.sh` (roadmap:3313, RED until implemented) —
    the reconcile entrypoint carries `id:3313`, enumerates `relay/orphan/*`, integrates via
    `merge --no-ff` + `ckpt-tag` + `--ff-only`, and offers a discard path. Behaviourally:
    integrate → `relay-ckpt-*` tag + pushed `--no-ff` merge; discard → ref gone; conflicting
    orphan → left + surfaced, never half-merged.
  - **Done-check**: tick this box, then `tests/run-tests.sh tests/test_relay_reconcile_mode.sh`,
    then full `make test` green.
- [x] [ROUTINE] D3 — suppress-redispatch of items with parked partial work (done 2026-06-16) <!-- id:1f53 -->
  - **Source**: meeting 2026-06-16-0938 D3; TODO id:1f53. **Sequence: after D1 (id:689c).**
  - **Spec**: at discovery, bind each `relay/orphan/*` branch back to its ROADMAP item via
    `git show --stat` on the parked commit; if that item is still OPEN, suppress a fresh dispatch
    (don't repeat the expensive session in vain) and surface ONE line carrying a best-effort
    `relay-burn.sh --run <runId>` cost hint. A CLOSED-item orphan does NOT suppress. Ambiguous
    binding → default to suppress. No new manifest — the `relay/orphan/*` refs ARE the registry.
  - **Acceptance**: `tests/test_relay_orphan_suppress_redispatch.sh` (roadmap:1f53, RED until
    implemented) — discovery carries `id:1f53`, binds via `git show --stat`, suppresses
    re-dispatch of still-open items, and surfaces a `relay-burn` cost hint. Behaviourally:
    open-item orphan NOT dispatched + IS surfaced; closed-item orphan does not suppress.
  - **Done-check**: tick this box, then
    `tests/run-tests.sh tests/test_relay_orphan_suppress_redispatch.sh`, then full `make test` green.
- [x] Build `tools/model-probe.sh` + `tools/model-probe.battery.jsonl` + log schema [ROUTINE] (done 2026-06-17) <!-- id:c345 -->
  - **Acceptance**: `tools/model-probe.sh grade`, `battery-version`, and the JSONL log all
    work offline (no model call). `model-probe.sh grade <regex> <output>` exits 0 on match,
    1 on mismatch. `model-probe.sh battery-version` prints the battery's `version` field.
    In mock mode (`PROBE_MOCK_RESPONSE` set), a run over a tiny battery writes a complete,
    valid-JSON log line with all D2+D1 fields. Real mode (`claude -p` as probe OS user with
    empty `~/.claude`) is wired but gated on the probe OS user (id:d0c0) — seeding is id:23e9.
  - **Tests**: `tests/test_model_probe.sh` (`# roadmap:040a` — 040a tests the 040a contract,
    which covers c345's offline surface) (currently RED until 040a is ticked).
  - **Done-check**: `tests/run-tests.sh tests/test_model_probe.sh` then full `make test` after
    ticking both id:c345 and id:040a.
  - **Context**: D2 log schema fields: `{ts, battery_version, model, item_id, pass, latency_s,
    out_tokens, tok_per_s, model_id_str, fingerprint, cli_version, quota_tier, os_user,
    config_hash}`. Invocation: shape A = `claude -p` as dedicated probe OS user (id:d0c0);
    shape B = `claude --bare -p` + `ANTHROPIC_API_KEY` (latent fallback). Scope guards: no
    LLM-judge, no dashboard, no scheduler; no seeding (id:23e9); no `useradd` (id:d0c0).
- [x] Write `tests/test_model_probe.sh` — hermetic offline contract tests [ROUTINE] (done 2026-06-17) <!-- id:040a -->
  - **Acceptance**: hermetic, `mktemp -d`, no network, no `~/.claude` touch. Covers:
    (1) `grade` subcommand pass/fail; (2) log format — all D2+D1 fields present in mock-mode
    run; (3) battery-version propagated from fixture battery into log line; (4) empty-config
    assertion — `PROBE_HOME` pointing to a dir with a `CLAUDE.md` causes non-zero exit.
  - **Tests**: `tests/test_model_probe.sh` (`# roadmap:040a`) (currently RED).
  - **Done-check**: `tests/run-tests.sh tests/test_model_probe.sh` then full `make test` after
    ticking both id:040a and id:c345.
  - **Context**: resolves id:6ffe (the placeholder for adding `# roadmap:` linkage once the
    ROADMAP item is open). Both c345 and 040a must be ticked together — the test covers both.

<!-- Direction: autonomous relay orchestration vision -->

- [x] [ROUTINE] **`make test` is RED — bare `rm -f` in `meeting/append.sh:384` trips `check-no-bare-rm-f.sh --enforce`** — REVIEW FINDING 2026-07-17 (review of window `relay-ckpt-20260716-1526`..HEAD). Commit `febb0c3` (integrate id:34c2) added `rm -f -- "$tmp_check"` where `tmp_check` is a known-present `mktemp` file; the repo's own lint (baseline 0 non-recursive force-flag rm) now FAILS, so `make test` aborts at the `lint` tier before the unit suite runs. Unit tier itself is fully green (256 passed). **Fix (one line, per CLAUDE.md destructive-op hygiene):** `rm -- "$tmp_check"` (file is known-present from `mktemp`), or annotate `# force-ok: <reason>`. **Done-check:** `make test` green (lint tier + unit tier). No new spec needed — `check-no-bare-rm-f.sh --enforce` IS the failing spec. <!-- id:a286 -->

- [x] [ROUTINE] **relay classifier spends no-op Opus reviews on metadata-only diffs — broaden the audit-exemption to source/test churn only** — SHIPPED 2026-07-17 (owner-directed, this session). The `review` verdict fired on the mere existence of unaudited commits; `gather-repo-state.sh`'s `substantive_unaudited` only exempted uv.lock-only (id:bae5) and contract-pointer-only (id:fbbf) commits, so a version bump (zkm v0.21.0), a `TODO.md +1` (toesnail), docs/cases (chidiai), and ledger+meeting-note windows (mathematical-writing/zkWhale) each burned a strong review turn for zero audit surface. **Fix:** a commit is substantive only if it touches an auditable path (not lockfile/ledger/`docs/**`/root-doc) whose content is more than a manifest `version` bump or the executor-contract pointer; content check is scoped to the auditable files so a docs-heavy commit can't defeat its own exemption. FAIL-OPEN preserved (unmatched path = auditable; unresolved audit_ref stays substantive). Spec: `tests/test_gather_substantive_nonauditable_exempt.sh` (6 cases incl. 2 controls). Relates id:0f1e (ledger-only), id:cd6e (scheduling side). <!-- id:2630 -->

<!-- 2026-07-16 (interactive apex session, owner-directed). Both items below were VERIFIED
     bugs found while reading run relay-20260716-125514-23493's event log, and both were
     implemented in the same session under a RED-first spec. The owner explicitly ratified
     "shape A" for id:f980 (move the breaker after all verdict mutations) over the narrower
     "skip idle in the guard", accepting that on Fable sessions this STARTS counting elevated
     review units — that is the intended behaviour, not a regression. Recorded here as the
     execution twin of the TODO ids (single-id-two-views D2). -->

- [x] [ROUTINE] id:365b circuit breaker must count only what actually dispatches <!-- id:f980 -->
  - **Why**: the breaker ran BEFORE the `verdict !== 'idle'` filter, keying `${repo}:${verdict}`
    over ALL units — so it counted `${repo}:idle` for units that never dispatch. Run
    relay-20260716-125514-23493 dispatched 21 units across 12 repos, yet 7 repos with **zero**
    `kind:"dispatch"` events were surfaced as circuit-breaker-blocked: 38 phantom entries that
    buried 2 real handbacks. It also ran BEFORE the id:9821/e030 Fable elevation, whose
    `units.length=0` splice could delete an idle unit the elevation still needed — silently
    dropping the optional Fable recheck after 3 rounds (a third bug, dissolved structurally here).
  - **Design (shape A, owner-ratified)**: the breaker is the LAST gate before dispatch. It now runs
    after every verdict mutation (id:000d demote, id:ad74 INTENSIVE promote, id:9821/e030 Fable
    elevation) and over the idle-filtered `dispatchable` set, so what it counts is exactly what
    dispatches, under the verdict key it dispatches as. **Filtering before the guard** — rather
    than special-casing `verdict==='idle'` inside it — is what keeps the inline copy
    logic-equivalent to `redispatch-guard.mjs`: the helper's semantics are untouched, only the
    set it is handed changes.
  - **Acceptance**: `tests/test_redispatch_circuit_breaker.sh` (`# roadmap:365b`) green, including
    the new structural ordering assertions (breaker line > Fable-elevation line; breaker line >
    idle-filter line) and the regression guard (execute AND review units repeated >3× with an
    unchanged work_sig are STILL suppressed — the breaker's real job survives the move).
  - **Done-check**: `tests/run-tests.sh tests/test_redispatch_circuit_breaker.sh` green, then full
    `tests/run-tests.sh` green. Verified 2026-07-16: 250 passed, 0 failed, 1 expected-red
    (roadmap:521f, pre-existing/unrelated).
  - **Context**: `relay/scripts/relay-loop.js` (breaker moved to just above the dispatch sort),
    `relay/scripts/redispatch-guard.mjs` (pure helper, UNCHANGED). Relates id:365b (the breaker),
    id:9821/id:e030 (the Fable elevation that made "idle is non-dispatchable" false), id:1432 (the
    sibling no-work guard), id:a921 (the runId fix landed alongside).
  - **Honest coverage limit**: the ORDER of the inline pipeline is asserted STRUCTURALLY (by line
    position), not by execution — relay-loop.js is a Workflow module that cannot be imported or run
    in-harness. The pure-helper tests cover the breaker's LOGIC; the greps cover only its
    placement. The third bug (Fable recheck no longer droppable) is therefore pinned by the
    ordering assertion — that the breaker can no longer splice a unit before the elevation reads
    it — NOT by an end-to-end Fable-session run, which the harness cannot stage.

- [x] [ROUTINE] Cost hints must cite the canonical state.runId, not the per-round prelude mint <!-- id:a921 -->
  - **Why**: both inline suppression call sites interpolated `prelude.runId`, which is re-minted
    EVERY round, while the events log, RELAY_STATUS header, heartbeat and burn sampler all write
    `state.runId` (the id:c5ba front-door mint). The emitted hint therefore named a run nothing
    ever wrote: `relay-burn.sh --run relay-20260716-143126-21466` → "have 0 samples", while the
    real id returned 7.
  - **Design**: canonicalize `state.runId` ONCE at the prelude — the earliest point it exists and
    before any consumer cites it — and read `state.runId` at both call sites. **Non-obvious**: the
    general-path assignment previously sat BELOW the dispatch sort (the `state.runId = state.runId
    || prelude.runId` at ~L884 is inside the user-stop early-return branch, NOT the normal path),
    so naively reading `state.runId` at the breaker would have printed an EMPTY run id — worse
    than the phantom. Hoisting to the prelude fixes both sites and makes the two later assignments
    redundant (removed).
  - **Scope**: covers BOTH the id:365b breaker hint AND the id:1432 no-work suppression call site
    (a sibling with the identical defect, found during this fix and folded in by owner ruling).
    Both pure helpers (`redispatch-guard.mjs`, `handback-guard.mjs`) already took `runId` as a
    param and are correct — signatures unchanged.
  - **Acceptance**: `tests/test_redispatch_circuit_breaker.sh` asserts the helper honours the
    caller-supplied runId, that the inline breaker hint reads `state.runId`, and that the id:1432
    call site no longer passes `prelude.runId`.
  - **Done-check**: `tests/run-tests.sh tests/test_redispatch_circuit_breaker.sh` green, then full
    `tests/run-tests.sh` green. Verified 2026-07-16 (same run as id:f980 above).
  - **Context**: `relay/scripts/relay-loop.js` L~876 (the single canonicalization), L~1214 (id:1432
    call site), the id:365b breaker hint. Relates id:c5ba (front-door mint), id:e149 (the heartbeat
    whose comment already warned prelude.runId is per-round).
  - **Not fixed (deliberate, out of scope)**: the discover/reconcile shard prompts still pass
    `--runid ${prelude.runId}` to `discover-repo.sh`/`reconcile-repo.sh`. Those hand a per-round
    discovery identifier to a script rather than naming a run for the burn sampler, and on round 1
    the two ids are identical. Changing them was not in the ruling and may be intentional — flagged
    for the owner, not touched.

<!-- 2026-07-16 handoff C2/C3 (interactive apex session, owner-directed): promoted TODO
     id:7612 REUSING its TODO twin (single-id-two-views D2). Owner ratified the
     main-HEAD-discriminator option over "wire for execute/hard only" and over routing to
     /meeting. C3 RED spec written + verified red before dispatch. Scope note: this item
     exists because id:f682's acceptance criteria tested only the SCRIPT's behaviour and
     never asserted a CALL SITE — so the gate shipped, ticked green, and was never wired.
     The acceptance below therefore asserts the wiring itself, not just the logic. -->

- [x] [ROUTINE] Wire the isolation gate into the integrator + make its signal unambiguous (main-HEAD discriminator) <!-- id:7612 -->
  - **Why**: `verify-isolation.sh` (id:f682) exists, is tested, is installed, is allowlisted —
    and `relay-loop.js` has **never called it** (`grep -c verify-isolation relay/scripts/relay-loop.js`
    → **0**, verified 2026-07-16). Invariant 5 + `references/conventions.md` document it as the
    pre-merge gate, so enforcement currently rests on an LLM following prose — the
    mechanize-first anti-pattern. It guards a failure that has already happened twice: loderite
    2026-07-14 (child ran `worktree add` then wrote every edit to the target's MAIN checkout)
    and jobAI 2026-06-30 (id:c6c8, child committed straight to `main`).
    `clean-tree-gate.sh` (step 1) catches only the UNCOMMITTED-to-main variant — it leaves main
    clean-and-committed undetected, which is the exact loderite/jobAI shape.
  - **BLOCKER this item must solve (verified 2026-07-16, do NOT skip)**: wiring the gate AS BUILT
    would **regress id:8e3e**. The gate exits 2 on an empty worktree ("NO commits beyond base"),
    but relay-loop.js step 2 explicitly treats a ZERO-COMMIT branch as a **legitimate completed
    unit** — a review child that audited its window and correctly found nothing to change. A
    handback there leaves the audited window unclosed and the pool re-dispatches the same review
    every round (observed 3× on 2026-07-01). **"Worktree empty" is an AMBIGUOUS signal**: it is
    the signature of BOTH a legitimate no-op review AND an isolation breach.
  - **How / Design** (the discriminator needs NO new plumbing — do not thread state through the pool):
    The breach signature is not "worktree empty" but "**worktree empty AND main advanced with
    non-integrator commits**". Both facts are derivable from the repo + worktree the gate is
    already handed, because the worktree branch was cut from main's HEAD at dispatch:
    - `base = git merge-base <worktree-HEAD> <main-ref>` — this IS the dispatch-time main HEAD.
    - `empty      := <worktree-HEAD> == base`   (branch carries no commits of its own)
    - `main_moved := <main-ref-HEAD> != base`   (main advanced since dispatch)
    Then:
    - `empty && !main_moved` → **exit 0** (legitimate id:8e3e no-op review; today this wrongly exits 2).
    - `empty &&  main_moved` → **exit 2** ONLY if the commits in `base..<main-ref>` include at
      least one **non-merge** commit (a `--no-ff` integrator merge, or merges from another unit,
      are NOT a breach). Name the offending commit(s) in the failure output.
    - `!empty` → existing behaviour unchanged (clean tree → exit 0; dirty → exit 2).
    **Known false-positive, accept + document (do NOT over-engineer):** a legitimate no-op review
    that races a concurrent SUPERVISED direct-to-main commit (id:15d5) will read as `empty &&
    main_moved` and exit 2. That is the CONSERVATIVE direction — it defers a no-op unit rather
    than merging a possible breach — and it costs only a re-dispatch. Add a sentence to the
    script header saying so. Do NOT add author/timestamp heuristics to chase it.
    **Wiring**: add the call to the relay-loop.js integrator recipe as a new step between the
    existing step 1 (clean-tree-gate) and step 1b (sync-origin), mirroring step 1's shape
    EXACTLY: absolute `~/.claude/skills/relay/scripts/verify-isolation.sh` path (NEVER the
    repo-relative form — it only resolves when cwd is dotclaude-skills), explicit "on non-zero
    exit, ABORT: return merged=false with reason …". Keep `${report.worktree}` as the argument.
  - **Also fix the docs** (they are the reason this was never caught): `relay/SKILL.md`
    invariant 5 and `relay/references/conventions.md` both write the invocation repo-relative
    (`relay/scripts/verify-isolation.sh`). Change both to the absolute `~/.claude/skills/...`
    form used by every other integrator gate.
  - **Acceptance**: `tests/test_isolation_gate_wired.sh` (`# roadmap:7612`, written RED by this
    handoff) goes green. It asserts BOTH halves:
    (a) **WIRING** — `relay/scripts/relay-loop.js` contains a `verify-isolation.sh` call using the
        absolute `~/.claude/skills/` path, and the surrounding recipe text carries an ABORT
        instruction. This is the assertion id:f682 lacked; without it the gate regresses to prose.
    (b) **DISCRIMINATOR** (real temp repos + worktrees, hermetic): empty + main unmoved → exit 0;
        empty + main advanced by a NON-MERGE commit → exit 2 naming the commit; empty + main
        advanced only by a MERGE commit → exit 0; non-empty + clean → exit 0; non-empty + dirty
        → exit 2.
    (c) **No regression** — `tests/test_verify_isolation.sh` (id:f682's own suite) still passes,
        EXCEPT its now-obsolete "empty → exit 2" case, which this item's design deliberately
        supersedes: update that case to construct `empty && main_moved` so it still asserts a
        breach. Do NOT delete the case.
  - **Done-check**: `tests/run-tests.sh tests/test_isolation_gate_wired.sh` green after ticking,
    then full `make test` green.
  - **Context**: model the wiring on step 1's `clean-tree-gate.sh` text in
    `relay/scripts/relay-loop.js` (~line 1707). The gate script is
    `relay/scripts/verify-isolation.sh`. Relates id:f682 (the gate), id:8e3e (the zero-commit
    legitimacy this must not regress), id:c6c8 + the loderite 2026-07-14 incident (the failures
    it guards), id:15d5 (the supervised-write false-positive above), id:c5ed (install drift).

<!-- 2026-07-15 handoff C2 (run relay-20260715-121544-12169): promoted the single
     `promote`-disposition TODO item (unpromoted-scan @ dotclaude-skills: 1 promote / 28
     laned; the 159 surface items are the mechanical `human`-verdict filer's job, NOT this
     handoff's). id:f682 REUSES its open TODO.md twin (single-id-two-views D2). Scoped the
     [ROUTINE] deliverable to the load-bearing mechanized integrator gate
     `scripts/verify-isolation.sh` (recommended-fix part 2) with a functional RED spec;
     parts 1 (child-spawn prompt boilerplate) + 3 (recovery doctrine) fold in as in-scope
     doc edits. TODO.md summary line refreshed. C3 RED test written + verified red. -->

- [x] [ROUTINE] Relay pre-integrate isolation gate — `scripts/verify-isolation.sh <worktree>` so a child that wrote to the target's MAIN checkout instead of its worktree fails loud before merge <!-- id:f682 -->
  - **Why** (observed 2026-07-14, loderite R2 consumer handoff): a spawned child correctly
    ran `git worktree add …` but then wrote every edit to the target's MAIN checkout
    (`~/src/loderite`, repo-root-relative paths / never `cd`-ing into the worktree). Its
    worktree stayed EMPTY (0 commits ahead of base), so its "commit in worktree" was a no-op
    and its self-report was wrong; the whole handoff's RED specs landed loose in the main
    checkout, mixed with an unrelated in-flight edit, and had to be reconciled by hand.
    DISTINCT from the c6c8 `isolation:worktree`-param hazard (there the worktree was never
    created; here it was created but bypassed).
  - **How / Design** (part 2 is the load-bearing mechanized fix; do all three):
    (1) **PROMPT** — the child-spawn boilerplate (relay invariant-4 child instructions) must
    force the worktree as working dir (absolute worktree path in every Read/Write/Edit, or
    make it cwd) and explicitly forbid touching the main checkout. Fold this sentence into the
    invariant-4 boilerplate text wherever the relay skill emits child prompts.
    (2) **INTEGRATOR GATE (mechanize)** — new `relay/scripts/verify-isolation.sh <worktree>`
    the integrator (invariant 5) runs BEFORE merging, mirroring `clean-tree-gate.sh` style
    (`set -euo pipefail`, log to `~/.claude/logs/`, exit 0 = safe / exit 2 = isolation
    failed, observe-only never mutate). It asserts the worktree branch has commits beyond its
    base (`git -C <worktree> log --oneline <base>..HEAD` non-empty) AND `git -C <worktree>
    status --porcelain` is clean; if the worktree is EMPTY it FAILS LOUD (exit 2, print the
    reason) — do not merge an empty branch. Not-a-git-worktree / missing path → exit 2 with a
    stderr message. Accept the base ref via `--base <ref>` (default `origin/main`, resolve to
    the current default branch if origin/main is absent).
    (3) **RECOVERY doctrine** — add a short paragraph to `relay/references/conventions.md` (or
    the integrator step it documents): when isolation fails the work is usually sound but
    mislocated — finish/commit it in the MAIN checkout under the held lease (the id:15d5
    pattern); salvage beats discard+re-run.
  - **Acceptance**: `tests/test_verify_isolation.sh` (`# roadmap:f682`, written RED by this
    handoff) goes green — using real temp git repos + worktrees: (a) worktree with a commit
    beyond base + clean tree → prints ok, exit 0; (b) EMPTY worktree (no commits beyond base)
    → exit 2, stderr/stdout names the isolation failure; (c) worktree with commits but a dirty
    tree → exit 2; (d) non-existent / non-git path → exit 2. Script never runs stash / reset /
    checkout -- / clean (grep-assert it mutates nothing).
  - **Done-check**: `tests/run-tests.sh tests/test_verify_isolation.sh` green after ticking,
    then full `make test`.
  - **Context**: model `relay/scripts/clean-tree-gate.sh` (same fail-safe/observe-only shape).
    Relates c6c8 (sibling isolation hazard), 15d5 (main-checkout-under-lease recovery), d2cd
    (lock/hazard umbrella), the invariant-4 worktree spawn step + invariant-5 integrate step.

<!-- 2026-07-15 review mini-handoff (run relay-20260715-121544-12169): relay-doctor
     surfaced two INBOUND inbox dead-letters (routed:2365 + routed:8653) reporting a real
     crash in the shipped id:1750 offline @needs-auth lister. Reproduced + root-caused:
     an executor-ready [ROUTINE] one-liner with a RED spec. Fresh id b8c2 (genuinely new
     follow-up work, not tracked in TODO); both routed: tokens carried on the line below so
     scan-routed --apply drains both inbox entries once this lands. -->

- [x] [ROUTINE] `gather-human-backlog.sh --needs-auth <repo>` crashes `path: unbound variable` — split the `local` in `list_needs_auth_repo` <!-- routed:2365 --> <!-- routed:8653 --> <!-- id:b8c2 -->
  - **Why** (INBOUND routed:2365 + routed:8653; relay-doctor 2026-07-15): the offline lister's
    named-arg branch (`run_needs_auth_lister`, `for name in "$@"` → `list_needs_auth_repo "$name"
    "${PATH_OF[$name]:-$SRC_DIR/$name}"`) dies under `set -u` on EVERY explicit repo-name
    invocation: `relay/scripts/gather-human-backlog.sh: line 362: path: unbound variable`. Root
    cause: `list_needs_auth_repo` opens `local name="$1" path="$2" file="$path/REVIEW_ME.md"` —
    bash expands all RHS words of one `local` command BEFORE any assignment takes effect, so
    `$path` in the `file=` word resolves against the CALLER's scope. The default no-arg branch
    survives by accident (its `while read … path` loop leaks a `path` into scope); the named-arg
    branch (`for name in "$@"`) has no `path` in scope, so it crashes. Only the no-arg all-repos
    form works today; `--needs-auth <repo>` (the per-repo view a human would reach for) is 100%
    broken. routed:2365 additionally notes the plugin-path own-repos (e.g. zkm-signal at
    `~/src/zkm/plugins/`) whose name isn't at `$SRC_DIR/<name>` — same crash, same fix.
  - **How / Design**: split the single-line `local` so `path` is assigned before it is
    referenced — e.g. `local name="$1" path="$2"` then a separate `local file="$path/REVIEW_ME.md"`.
    That is the whole fix; do NOT touch the no-arg branch or the awk block. Verify the plugin-path
    own-repos resolve via the `PATH_OF[$name]` lookup (from `own_repos`) rather than the
    `$SRC_DIR/$name` fallback, so a repo whose name isn't a child of `$SRC_DIR` still lists.
  - **Acceptance**: `tests/test_needs_auth_lister_named_repo.sh` (`# roadmap:b8c2`, written RED by
    this review) goes green — `--needs-auth repoNA` (explicit repo-name arg) exits 0, prints the
    repo's @needs-auth box with all four field values, and stderr carries no `unbound variable`.
    Existing `tests/test_needs_auth_lister.sh` (id:1750, no-arg form) MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_needs_auth_lister_named_repo.sh tests/test_needs_auth_lister.sh`
    then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/gather-human-backlog.sh` (`list_needs_auth_repo` ~L361-362,
    `run_needs_auth_lister` named-arg branch ~L417-420). Sibling: shipped id:1750 (the lister).
    INBOUND routed:2365 + routed:8653.

<!-- 2026-07-14 handoff C2 (run relay-20260714-123104-912): promoted the two `promote`-
     disposition TODO items (unpromoted-scan @ dotclaude-skills: 2 promote / 1 surface / 16
     laned). Both are the `@needs-auth` co-meet cluster RESOLVED + re-laned `[INPUT — meeting]`
     →`[HARD — pool]` by /meeting 2026-07-14-1135 (docs/meeting-notes/2026-07-14-1135-human-
     manual-task-handling.md, D1–D4). Single-id-two-views (D2): id:a505, id:1750 REUSE their
     open TODO.md twins. Both are `[HARD]` (strong-model: a505 is a VERSIONED executor-contract
     change; 1750 is judgment-laden convention wiring) — left specced for the pool `hard`
     verdict, NOT executed in C5 (contract-surface edits + cross-repo retro-tags exceed a safe
     single-turn C5). a505 is the prerequisite (defines the convention 1750 consumes) so 1750
     carries (DEP: a505). The 1 surface item (id:625a, INBOUND routed:a6be, gated on
     project_manager id:0fc7) is the mechanical `human`-verdict filer's job, NOT promoted here. -->

- [x] [HARD] `@needs-auth` convention + executor-contract rule (D1/D2/D3) <!-- id:a505 -->
  - **Done 2026-07-14** (relay HARD child, id:da26): shipped all of D1/D2/D3 in THIS repo.
    (1) **Convention doc** — new `## The @needs-auth marker` section in
    `relay/references/hard-lanes.md`: broad definition (any human-held secret / interactive
    auth), orthogonal to `@manual`, carrier = a per-repo `REVIEW_ME.md` box (D2, explicitly NO
    global auth-queue file — id:9fdb hazard), FOUR mandatory fields (what-secret · where-it-goes
    · exact-command · why). (2) **Versioned contract rule (D3)** — added rule 6 (record-and-
    continue, default clean-handback when separability uncertain) to
    `relay/references/executor-contract.md` and BUMPED the marker v6→v7; updated the
    `CLAUDE.md` `## Relay contract` pointer AND the §Versioning contract-surface table
    ("currently v7") in the same commit (no version skew). (3) **Recognition wiring** —
    `roadmap-lint.sh` + `gather-human-backlog.sh` document `@needs-auth` as a KNOWN marker
    (never flagged unknown/untagged); the AI-free lister/filter is the co-meet item id:1750
    (NOT built here). Acceptance test `tests/test_needs_auth_convention.sh` (roadmap:a505)
    green; updated `tests/test_relay_executor.sh` v6→v7 version-consistency assertion in
    lockstep. Meeting: `docs/meeting-notes/2026-07-14-1135-human-manual-task-handling.md`.
  - **Why** (TODO id:a505; /meeting 2026-07-14-1135, D1/D2/D3): a relay child that hits an
    interactive-auth / human-held-secret wall today STRANDS the rest of its unit mid-session
    (the a505 filing failure). There is no convention for recording "this needs a human secret"
    and no contract rule telling a child to record-and-continue. The meeting resolved this WITH
    id:1750 as one design: a single `@needs-auth` marker is BOTH the class-(i) hands-lane reason
    and the auth-queue membership predicate.
  - **How / Design** (all in THIS repo — no cross-repo edits):
    1. **Document the `@needs-auth` convention** in a reference doc — extend
       `relay/references/hard-lanes.md` (capability/marker section) and/or
       `relay/references/conventions.md`. Definition is **broad**: any human-held secret OR
       interactive-auth (sudo/askpass, polkit/pamac, ssh/login, gpg/credential, browser-OAuth,
       a decryption passphrase, a private export). It is **orthogonal to `@manual`** (an item
       may carry both — `@needs-auth` = provide a secret; `@manual` = run/verify). The carrier
       is a **per-repo `REVIEW_ME.md` box** (D2 — explicitly NO global `~/.config/relay/auth-
       queue.md` file; that repeats the id:9fdb unversioned-destructive-store hazard). The
       convention **MANDATES four fields** per box: what-secret · where-it-goes · exact-command
       · why.
    2. **Executor-contract rule (D3, VERSIONED):** add a rule to
       `relay/references/executor-contract.md` — a child hitting an interactive-auth/secret wall
       RECORDS a conforming `@needs-auth` REVIEW_ME box instead of failing the unit, then
       clean-continues the separable remainder, **defaulting to clean-handback of the gated
       remainder when separability is uncertain**. BUMP the contract marker
       `<!-- relay-executor contract v6 -->` → v7 in executor-contract.md, AND update the
       `## Relay contract <!-- relay-executor contract v6 -->` pointer in `CLAUDE.md` (line
       ~161) to v7 in the SAME commit (co-located bump discipline, CLAUDE.md §Versioning).
    3. **Recognition wiring:** `relay/scripts/gather-human-backlog.sh` and
       `relay/scripts/roadmap-lint.sh` must RECOGNIZE `@needs-auth` (not flag it as an unknown
       marker). (The lister/filter half is id:1750; here only ensure the marker is a known token.)
  - **Acceptance**: a test (e.g. extend `tests/test_hard_lane_buckets.sh`, `# roadmap:a505`)
    asserts: the `@needs-auth` convention doc lists the four mandatory fields; `roadmap-lint.sh`
    does NOT flag an `@needs-auth`-marked item as unknown/untagged; the executor-contract marker
    is v7 and the `CLAUDE.md` pointer matches v7 (no version skew). The D3 contract rule text is
    present in executor-contract.md. NOTE: this is a `[HARD]` item — write the spec as part of
    execution (no pre-written RED spec from handoff), and keep `make test` green after ticking.
  - **Done-check**: `tests/run-tests.sh tests/test_hard_lane_buckets.sh` then full `make test`
    after ticking; verify no contract-version skew (`grep -rn 'relay-executor contract v' CLAUDE.md relay/references/executor-contract.md` all agree).
  - **Context**: `relay/references/hard-lanes.md`, `relay/references/conventions.md`,
    `relay/references/executor-contract.md` (contract marker + pointer discipline ~L141),
    `CLAUDE.md` (§Relay contract pointer ~L161, §Versioning contract-surface table),
    `relay/scripts/gather-human-backlog.sh`, `relay/scripts/roadmap-lint.sh`. Meeting:
    `docs/meeting-notes/2026-07-14-1135-human-manual-task-handling.md`. Co-meet with id:1750.

- [x] [HARD] Offline `@needs-auth` lister (extend `gather-human-backlog.sh`) + retro-tag the class-(i) backlog (DEP: a505) <!-- id:1750 -->
  - **Done 2026-07-14** (relay HARD child, id:da26): shipped the v1 offline lister in THIS
    repo. `gather-human-backlog.sh --needs-auth [repo...]` now filters every OPEN `@needs-auth`
    REVIEW_ME box across own repos (reusing the existing `own_repos` enumeration + REVIEW_ME
    reader, NOT a new walker) and prints a PLAIN, human-readable (NON-TSV) block per box:
    `repo — title (id)` + the four mandatory fields (what-secret / where-it-goes /
    exact-command / why), a missing field printed `(MISSING)` so a non-conforming box is LOUD.
    The mode is pure bash+awk — AI-free / offline (no `claude -p`, no network), bypassing the
    TSV collector + the HARD-lane untagged-exit path (focused human view, not the classifier
    feed). Default TSV mode is UNCHANGED (a `@needs-auth` box still surfaces as an ordinary
    review_me row per the a505 contract). Acceptance test `tests/test_needs_auth_lister.sh`
    (roadmap:1750) green; existing `test_gather_human_decision.sh` / `test_hard_lane_buckets.sh`
    / `test_needs_auth_convention.sh` / `test_relay_human.sh` all stay green. **Retro-tag
    (step 2) — filed as cross-repo inbox items** (SCOPE BOUNDARY: those five boxes live in
    OTHER repos, unreachable from this worktree): zkm-signal/e588, zkm-threema/7364,
    zkm-chatgpt/ad81, bahnbetAI/c624, zkm/0b37. v2 (interactive step-through + tick-back) stays
    DEFERRED (observe-before-preventing). Meeting: `docs/meeting-notes/2026-07-14-1135-human-manual-task-handling.md`.
  - **Why** (TODO id:1750; /meeting 2026-07-14-1135, D4): `/relay human` surfaces
    human-gated work but costs a Claude session. The one genuine differentiator wanted here is
    an **AI-free, offline** lister of every `@needs-auth` box across own repos — a plain bash
    sweep the human runs with no network and no model. The class-(i) backlog is already real
    (zkm-signal e588, zkm-threema 7364, zkm-chatgpt ad81, bahnbetAI c624, zkm 0b37), so the
    lister earns its keep on day one once those boxes exist.
  - **How / Design** (DEP: a505 — the `@needs-auth` convention + field contract must land first):
    1. **Extend `relay/scripts/gather-human-backlog.sh`** (do NOT fork a new repo-walker —
       reuse its existing own-repo enumeration + REVIEW_ME reader) with a `@needs-auth` filter
       and a **plain, human-readable (non-TSV) output mode**: one line/block per box showing
       repo · what-secret · where · exact-command. It must run **AI-free** (pure bash, no
       `claude -p`, no network).
    2. **Retro-tag the existing class-(i) backlog** with conforming `@needs-auth` REVIEW_ME
       boxes (all four mandatory fields) so the lister has day-one content. **SCOPE BOUNDARY:**
       the five targets (zkm-signal e588, zkm-threema 7364, zkm-chatgpt ad81, bahnbetAI c624,
       zkm 0b37) live in OTHER repos — a relay child works ONE worktree, so those per-repo boxes
       are NOT written from this worktree. File them as cross-repo inbox items
       (`meeting/append.sh -t inbox`, one per target repo) during execution; only the
       `gather-human-backlog.sh` change + a hermetic fixture live in THIS repo.
    3. **v2 (interactive step-through + REVIEW_ME tick-back via flock'd `md-merge.py`) is
       DEFERRED** — gated on v1 lister usage (observe-before-preventing). Do NOT build it now.
  - **Acceptance**: a test (`tests/test_needs_auth_lister.sh`, `# roadmap:1750`) with a hermetic
    fixture repo carrying a `@needs-auth` REVIEW_ME box asserts the lister prints that box with
    ALL FOUR fields (what/where/command/why), runs with no network/AI, and the plain output mode
    is non-TSV human-readable. Existing `gather-human-backlog.sh` tests
    (`tests/test_hard_lane_buckets.sh` and any gather-human-backlog test) MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_needs_auth_lister.sh tests/test_hard_lane_buckets.sh`
    then full `make test` after ticking.
  - **Context**: `relay/scripts/gather-human-backlog.sh` (own-repo enumeration + REVIEW_ME
    reader), `relay/references/human.md` (`/relay human --all` aggregation). Cross-repo retro-tag
    targets (inbox, out of this worktree's scope): zkm-signal/e588, zkm-threema/7364,
    zkm-chatgpt/ad81, bahnbetAI/c624, zkm/0b37. Meeting:
    `docs/meeting-notes/2026-07-14-1135-human-manual-task-handling.md`. DEP: id:a505 (convention).
    v2 tick-back deferred under this id's acceptance.

<!-- 2026-07-13 review 5b mini-handoff: qualified two ledger-neutral TODO items the human
     flow-back added (commit 0d1ac39). Both are execution-ready [ROUTINE] with RED specs,
     reusing their TODO ids (single-id-two-views D2): id:1781, id:7f30. -->

- [x] [ROUTINE] `roadmap-lint.sh`: count only the LEADING contiguous lane-bracket run, ignore lane-bracket mentions in trailing audit-trail prose <!-- id:1781 -->
  - **Why** (TODO id:1781, surfaced by leAIrn2learn id:c3f5): the case-c conflict check (`relay/scripts/roadmap-lint.sh` ~L322-350) counts EVERY non-backticked lane bracket on a line. An item whose HEAD tag is a correct single lane but whose BODY cites a prior `[HARD — …]`/`[ROUTINE]` transition in *non-backticked* audit-trail prose (e.g. "(was [HARD — pool] before, re-laned to [ROUTINE])") false-positives the "multiple lane brackets" LOUD-reject. The existing backtick-strip (~L328) only rescues brackets inside a backtick span, not bare audit prose.
  - **How / Design**: the lane tag(s) are the CONTIGUOUS run of lane brackets at the very START of the item text (immediately after `- [ ] `). A lane bracket appearing AFTER any prose word is trailing audit-trail prose and must NOT count toward the conflict. Keep the genuine-conflict path: two contiguous LEADING lane tags (e.g. `[HARD — pool] [ROUTINE] …`) must still ERROR (do not weaken case-c / `test_roadmap_lint_tagprose.sh`). Preserve the backtick-strip and every other grammar check.
  - **Acceptance**: `tests/test_roadmap_lint_trailing_lane_prose.sh` (`# roadmap:1781`, written RED by this review) goes green — a leading `[ROUTINE]` tag with a lane bracket in trailing prose PASSES; two contiguous leading tags still ERROR; a clean single-tag item still passes. Existing `tests/test_roadmap_lint_tagprose.sh`, `tests/test_roadmap_lint.sh`, `tests/test_roadmap_lint_tag_first.sh` MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_roadmap_lint_trailing_lane_prose.sh tests/test_roadmap_lint_tagprose.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/roadmap-lint.sh` (bare-lane count + case-c conflict ~L322-350, backtick-strip ~L328). TODO id:1781.

- [x] [ROUTINE] `orphan-scan.sh --shipped`: add an `<!-- xgate:TOKEN@repo -->` marker that bypasses UNMARKED-GATE for a cross-repo gate whose blocking token lives in another repo <!-- id:7f30 -->
  - **Why** (TODO id:7f30, resolving REVIEW_ME id:50c4 option a): a deliberately-unmarked CROSS-REPO gate (e.g. id:50c4 gated on 508d@relay-core) has NO local `gated-on:` edge to point at, so it re-fires UNMARKED-GATE on every `--shipped` scan. The generic `<!-- gate-prose-only -->` marker (id:8800) suppresses the re-fire but DISCARDS which external token/repo blocks it. A dedicated `xgate:TOKEN@repo` marker records that cross-repo dependency explicitly (parseable) while still shrinking the detector.
  - **How / Design**: mirror the shipped `gate-prose-only` bypass (`meeting/orphan-scan.sh` ~L252-261, L341): detect an `<!-- xgate:TOKEN@repo -->` sibling comment and have it BYPASS the UNMARKED-GATE backstop the same way (guard on the `grep -qiE '…gated on…'` branch ~L341). Like `gate-prose-only`, it must NOT set `has_typed` and must NOT suppress the typed-predicate branches (GATE-READY/GATE-BLOCKED/UMBRELLA-*) or the EXTERNAL-WAIT / GATE-STALE paths. Parse `TOKEN@repo` shape loosely (4-hex token, `@`, repo name); a malformed marker should not crash the scan. Also add the marker to id:50c4's TODO line as the first real consumer.
  - **Acceptance**: `tests/test_orphan_scan_xgate.sh` (`# roadmap:7f30`, written RED by this review) goes green — an item carrying `<!-- xgate:508d@relay-core -->` plus gate vocabulary does NOT surface as UNMARKED-GATE, while a control item with the same vocabulary and NO marker still does. Existing `tests/test_orphan_scan_gate_prose_only.sh` (id:8800), `tests/test_orphan_scan_unmarked_gate.sh` (id:4245), `tests/test_orphan_scan_shipped.sh` MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_orphan_scan_xgate.sh tests/test_orphan_scan_gate_prose_only.sh tests/test_orphan_scan_unmarked_gate.sh` then full `make test` after ticking (RED until then).
  - **Context**: `meeting/orphan-scan.sh` (`gate_prose_only` ~L252-261, UNMARKED-GATE backstop ~L332-344). TODO id:7f30; consumer TODO id:50c4.

<!-- 2026-07-12 handoff C2 (focused inbox ingestion): promoted two inbox-routed items from
     today's it-infra zomni KVM/dock RCA (it-infra hosts/zomni/system/kvm-dock/INCIDENTS.md
     2026-07-12). Both are executor-ready [ROUTINE] with RED specs and are INBOUND stubs in
     TODO.md (single-id-two-views): id:3273 carries routed:8a55, id:1b18 carries routed:5434.
     Both harden the same git-diary-workflow push/replay machinery the flap starved. -->

- [x] [ROUTINE] `git-lock-push.sh` push path: bound a stalled ESTABLISHED ssh with a hard `timeout` + ServerAliveInterval/CountMax (not just ConnectTimeout) <!-- routed:8a55 --> <!-- id:3273 -->
  - **Why** (INBOUND routed:8a55 from it-infra, zomni KVM/dock RCA 2026-07-12): the push loop runs `GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" git push …` (git-lock-push.sh ~L244/246). `ConnectTimeout` bounds ONLY the TCP connect — an ESTABLISHED ssh whose network dies mid-transfer hangs indefinitely. Observed live: a dock-ethernet flap at 08:55:14 left a `git push` hung 40+ min while it HELD the per-repo flock (`.git-lock-push.lock`), starving every other lock user (quota-sample commits, diary-append) fleet-wide. it-infra's `sessions-backup.sh` was hardened the SAME day (it-infra `~/.claude` commit 9950390f) — mirror that fix here.
  - **How / Design**: two complementary bounds on the push. (a) Add `-o ServerAliveInterval=<N> -o ServerAliveCountMax=<M>` to the push `GIT_SSH_COMMAND` so ssh itself tears down a dead ESTABLISHED connection after ~N·M s of silence (mirror the sessions-backup.sh values). (b) Wrap the `git push` invocation in a hard `timeout` as a belt to ServerAlive's suspenders — read a `GIT_LOCK_PUSH_TIMEOUT` env seam (default a sane production value, e.g. 120) so the timeout is tunable and hermetically testable. On a push that times out, print a LOUD stderr WARNING and follow the script's existing non-fatal contract (work stays committed locally; retries next run — same disposition as the flock-timeout / ff-only-divergence branches), and RELEASE the flock (do not leak fd 8). Apply to BOTH push invocations (existing-branch and `--set-upstream` first-push).
  - **Acceptance**: `tests/test_git_lock_push_stall_timeout.sh` (`# roadmap:3273`, written RED by this handoff) goes green — with a fake ssh that serves upload-pack locally but SLEEPS on receive-pack (an ESTABLISHED-then-dead push), the script SELF-TERMINATES within the `GIT_LOCK_PUSH_TIMEOUT` bound instead of hanging, and the built push ssh command carries `ServerAliveInterval` + `ServerAliveCountMax`. Existing git-lock-push tests (dirty-guard, ff-only, merge-branch, slash-branch) MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_git_lock_push_stall_timeout.sh` then full `make test` after ticking (RED until then).
  - **Context**: `git-diary-workflow/git-lock-push.sh` (the push loop ~L235-248; the flock at ~L115-121; the existing non-fatal WARNING+exit-0 branches to mirror). Cross-repo mirror source: it-infra `sessions-backup.sh` (commit 9950390f wording). INBOUND routed:8a55.

- [x] [ROUTINE] `diary-append.sh`: pull BEFORE replaying quarantined entries so a dirty-tree pull failure can't strand replayed text (deadlock) <!-- routed:5434 --> <!-- id:1b18 -->
  - **Why** (INBOUND routed:5434 from it-infra, zomni RCA 2026-07-12): the replay loop (diary-append.sh ~L153-158) appends every `.diary-pending-*` / `.failed/entry-*` file into DIARY.md and `rm`s it BEFORE `git pull --rebase` (~L166). That append DIRTIES the tree, so the pull refuses ("cannot pull with rebase: You have unstaged changes") and `on_failure` quarantines only the CURRENT entry — the already-appended-and-unlinked replayed text strands as an uncommitted DIARY.md change. The tree stays dirty, so EVERY subsequent run's pull refuses too → deadlock until a human commits by hand. Observed live 2026-07-12 09:51 across two parallel sessions plus a stranded quota-sample line. (Sibling of the shipped id:f8df entry-survival fix — same script, the ordering half.)
  - **How / Design**: reorder so the replay CANNOT dirty the tree before a pull. Preferred: `git pull --rebase origin <branch>` FIRST (on the clean tree), THEN replay the quarantined files + append the current entry into DIARY.md, then a single `git commit` + `git push` — the replayed content rides the same commit. (Acceptable alternative: commit the replayed entries as their OWN commit before the pull.) Preserve BOTH invariants: exactly-once (a replayed entry is appended once and its quarantine file removed only AFTER the commit succeeds) and no-entry-loss (a failure still quarantines to `.failed/` with a loud path — never silent unlink; id:4347 class). Keep the flock + the `DIARY_SKIP_SSH` test seam intact.
  - **Acceptance**: `tests/test_diary_append_replay_before_pull.sh` (`# roadmap:1b18`, written RED by this handoff) goes green — given a pre-existing `.failed/entry-*` quarantine plus fresh entries across two runs, all entries land in COMMITTED+PUSHED history exactly once, the working tree ends CLEAN, and no `.failed/`/`.diary-pending-*` files linger. Existing `tests/test_diary_append_entry_survival.sh` (id:f8df) MUST stay green (the failure-quarantine path is unchanged).
  - **Done-check**: `tests/run-tests.sh tests/test_diary_append_replay_before_pull.sh tests/test_diary_append_entry_survival.sh` then full `make test` after ticking (RED until then).
  - **Context**: `git-diary-workflow/diary-append.sh` (replay loop ~L153-158, the pull ~L166, `on_failure` ~L141-151). Sibling: id:f8df (entry-survival, shipped). INBOUND routed:5434.

<!-- 2026-07-12 review reverse-handoff (run relay-20260712-210033-21590): the two INBOUND
     inbox items ingested this window (routed:1cda id:8800 from zkm; routed:8b23 id:0f7a from
     it-infra) landed in TODO.md ledger-neutral (no lane, no acceptance). Both are concrete,
     testable ROUTINE fixes with a clear observable done-state, so they are mini-handed-off
     here (§5b) — RED spec written, id REUSED (single-id-two-views, D2). -->

- [x] [ROUTINE] `orphan-scan.sh`: add a `<!-- gate-prose-only -->` marker that bypasses the UNMARKED-GATE backstop for confirmed external-prose gates <!-- routed:1cda --> <!-- id:8800 -->
  - **Why** (INBOUND routed:1cda from zkm): the UNMARKED-GATE backstop (meeting/orphan-scan.sh ~L321-333) surfaces any unmarked line bearing structured gate vocabulary (`gated on`, `blocked until/on`, `Gate:`, `🚧 GATED …`). Its intended resolution is "add a typed `gated-on:` edge OR confirm the gate" — but when the gate's blocking condition is an EXTERNAL prose condition (an upstream vendor shipping an API, a human decision) rather than a local TODO-id dependency, there is NO local id to point a `gated-on:` edge at. The item therefore re-fires UNMARKED-GATE on every `--shipped` scan with no non-hacky resolution, re-litigating the same confirmed gate forever.
  - **How / Design**: add a durable `<!-- gate-prose-only -->` marker that records "this prose gate is confirmed; it intentionally has no typed edge". Detect it alongside the typed-edge markers (`children:`/`gated-on:`, the `has_typed` block ~L248-250) and have it BYPASS the UNMARKED-GATE backstop the same way `has_typed` does (`continue` at ~L313-318, or a guard on the `grep -qiE '…gated on…'` branch at ~L330) — so a confirmed prose-only gate SHRINKS the detector instead of re-firing. The marker must NOT suppress the typed-predicate branches (GATE-READY/GATE-BLOCKED) — it only silences the UNMARKED-GATE advisory. Keep the EXTERNAL-WAIT (`wait_re`) and GATE-STALE (`completion_re`) paths unchanged. (Mirror the `has_typed` "marked, not because a regex got smarter" doctrine in the in-file comment.)
  - **Acceptance**: `tests/test_orphan_scan_gate_prose_only.sh` (`# roadmap:8800`, written RED by this review) goes green — an item carrying `<!-- gate-prose-only -->` plus gate vocabulary does NOT surface as UNMARKED-GATE, while a control item with the same vocabulary and NO marker still does. Existing `tests/test_orphan_scan_unmarked_gate.sh` (id:4245) and `tests/test_orphan_scan_shipped.sh` MUST stay green.
  - **Done-check**: `tests/run-tests.sh tests/test_orphan_scan_gate_prose_only.sh tests/test_orphan_scan_unmarked_gate.sh` then full `make test` after ticking (RED until then).
  - **Context**: `meeting/orphan-scan.sh` (`has_typed` ~L248-250, the typed-marker bypass ~L313-318, the UNMARKED-GATE backstop ~L321-333). INBOUND routed:1cda.

- [x] [ROUTINE] `archive-done.sh`: count nested `###` subsection task lines before pruning a `##` section as empty <!-- routed:8b23 --> <!-- id:0f7a -->
  - **Why** (INBOUND routed:8b23 from it-infra): the empty-section pruner (todo-update/archive-done.sh ~L151-180) splits TODO.md into segments on ANY heading of level ≥2 (`##` AND `###`), so a `### subsection` starts its OWN segment. A `## section` whose tasks all live under a following `### subsection` is then left with an empty body and pruned, orphaning the tasks under it. Recurred twice on it-infra's `## Backup & storage strategy` (2026-07-11), each run re-orphaning the items under the preceding section.
  - **How / Design**: a `## section` is NOT empty when a nested subsection belonging to it carries task lines. Preferred: when computing `has_content` for a level-2 section, INCLUDE the content of following deeper (`###`+) headings until the next same-or-higher-level (`##`) heading — i.e. treat subsections as body of their parent for the empty-check, not as independent prunable segments. (Acceptable alternative: only ever treat level-2 `##` as prune-segment boundaries and keep `###`+ as body of their parent.) Preserve the existing invariants: protected labels (`Done`/`Current`) are never pruned, a genuinely empty `##` (no body, no task-bearing subsection) IS still pruned, and the H1/preamble stays untouched. Keep the prior-commit + aged-date archive gates unchanged.
  - **Acceptance**: `tests/test_archive_done_nested_subsection.sh` (`# roadmap:0f7a`, written RED by this review) goes green — a `## section` whose only tasks live under a `### subsection` survives the prune, and the subsection + its tasks survive with it. Existing `tests/test_roadmap_archive.sh`, `tests/test_archive_done_multiline.sh`, `tests/test_archive_closed.sh` MUST stay green (a truly-empty non-protected section is still pruned).
  - **Done-check**: `tests/run-tests.sh tests/test_archive_done_nested_subsection.sh tests/test_archive_done_multiline.sh` then full `make test` after ticking (RED until then).
  - **Context**: `todo-update/archive-done.sh` (segment split ~L151-165, empty-check + prune ~L167-180). INBOUND routed:8b23.

<!-- 2026-07-11 handoff C2 (run relay-20260711-123559-15556): promoted the executor-ready
     `[ROUTINE]` promote-disposition TODO items (unpromoted-scan: 16 promote / 3 laned / 183
     surface). Single-id-two-views (D2): every id below REUSES its open TODO.md twin.
     Promoted the 6 genuinely executor-ready [ROUTINE] items (clear code change + testable
     acceptance). NOT promoted: the `[INPUT — meeting]`/`[INPUT — access]`-tagged "promote"
     rows (77f3/4299/b444/33c2/a505/7b23/b8ae/d0da — a lane a handoff can't decide; surface
     items are the mechanical `human`-verdict filer's job, handoff.md §surface); id:02c7
     (POSIX ACLs) is access-gated on the still-unprovisioned relay-ro/relay-svc OS users
     (id:13ae) so its "relay-ro CANNOT write" test is un-runnable — left for the access lane;
     id:2e6d parent is largely SHIPPED and its child id:7d97 (user:-prefix + emphasis
     invariants) was ALREADY SHIPPED (commit 6bc2817, test12/13 in test_memory_index.sh green)
     — so neither is promoted; 2e6d's only remainder is the [INPUT — user] settings.json
     hook install. -->

<!-- 2026-07-11 handoff (run relay-20260711-123559-15556, 2nd child): the classifier
     RE-fired `handoff` (8 promote) even though the 1637 handoff already promoted the real
     [ROUTINE] work and correctly refused the 8 `[INPUT — meeting|access]` rows. ROOT CAUSE
     found + specced below as id:719a: `unpromoted-scan.sh primary_lane()` doesn't know the
     new-vocab tags, so those 8 human-gated items are false-positive `promote`d and the
     promote count never drops → the loop re-dispatches a no-op handoff every round. This is
     the durable fix that stops the re-dispatch; nothing else was executor-promotable. -->

- [x] [ROUTINE] `unpromoted-scan.sh` `primary_lane()`: recognize the NEW capability-keyed lane vocabulary so `[INPUT — *]` items stop false-positive `promote`ing <!-- id:719a -->
  - **Why** (observed 2026-07-11, run relay-20260711-123559-15556): the dual-vocab window is still OPEN (id:7df1 gated), so live TODO items carry new-vocab tags (`[INPUT — meeting|access|decision]`, bare `[HARD]`, `[MECHANICAL]`). `primary_lane()`'s two tag lists (the bold-anchor branch and the leftmost-tag-anywhere branch) enumerate ONLY old-vocab tags (`[ROUTINE]`, `[HARD — pool|meeting|hands|decision gate]`). A new-vocab-prefixed item — `- [ ] [INPUT — meeting] **title** …` — fails the bold-title anchor (the tag sits BEFORE the `**`, not after it), falls through to the leftmost-scan, which doesn't know `[INPUT — meeting]` and so matches a `[ROUTINE]`/`[HARD — pool]` token appearing DEEP IN THE ITEM'S PROSE → returns it → disposition `promote`. Effect this run: all 8 of this repo's `[INPUT — meeting|access]` items (77f3/4299/b444/33c2/a505/7b23/b8ae/d0da) counted `promote`, so `classify-repo.sh` emitted a spurious `handoff` verdict (should be `human` per the promote==0 ∧ surface>0 case-b split, id:5eb3) and dispatched an Opus handoff child with nothing executor-promotable to do — TWICE (1637 + this run). Same anchoring-failure CLASS as existing test case (i) / id:4da4; new trigger (a new-vocab tag defeats the bold anchor). This is the id:4d8e "pin each observed discovery failure as a RED fixture" discipline.
  - **How / Design**: extend `primary_lane()` (in `relay/scripts/unpromoted-scan.sh`) to (a) add the new-vocab tags — `[INPUT — meeting]`, `[INPUT — access]`, `[INPUT — decision]`, bare `[HARD]`, `[MECHANICAL]` — to BOTH the bold-anchor tag loop and the leftmost-scan tag loop; (b) also anchor a lane tag that sits between `- [ ] ` and a bold `**title**` (the tag-before-bold-title shape `- [ ] [TAG] **title**`), so the tag wins over any prose token regardless of order. Then update the disposition mapping (lines ~258-268): executable lanes (`[ROUTINE]`, `[HARD]`, `[HARD — pool]`) → `promote`; human/compute gates (`[INPUT — *]`, `[HARD — meeting|hands|decision gate]`, `[MECHANICAL]`) → `laned` (verdict-neutral, never auto-promoted, never re-filed). Keep the fb7f bold-anchor + id:ed2e status-summary exemptions intact. NOTE: id:7df1's reader-migration (d259 decision) will eventually DELETE `primary_lane()` in favour of one fixed-offset positional read once the tag-first reorder lands cross-repo; this is the interim fix for the still-open dual-vocab window, not a competing design.
  - **Acceptance**: `tests/test_unpromoted_scan_newvocab.sh` (`# roadmap:719a`, written RED by this handoff) goes green — new-vocab-prefixed items with old-vocab prose tokens report `laned` not `promote` (cases j–n), and a genuine `[ROUTINE]` item still reports `promote` (case o). Existing `tests/test_unpromoted_scan.sh` (cases a–i, id:2dea/ed2e/4da4) MUST stay green (no regression to old-vocab anchoring or the status-summary exemption).
  - **Done-check**: `tests/run-tests.sh tests/test_unpromoted_scan_newvocab.sh tests/test_unpromoted_scan.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/unpromoted-scan.sh` (`primary_lane()` ~L85-107 + disposition mapping ~L258-268). Cross-refs: id:4d8e (mechanical-classifier corpus, this is a new fixture), id:7df1 (dual-vocab window close / eventual primary_lane deletion), id:5eb3 (promote==0∧surface>0 → human case-b), id:2d20 (pool re-dispatches un-doable units — this is one concrete cause).

- [x] [ROUTINE] `diary-append.sh`: keep the `-f` entry temp file until push SUCCEEDS + fix the multi-branch rebase race <!-- id:f8df -->
  - **Why** (TODO id:f8df; observed 2026-07-08): `diary-append.sh -f <entry>` raced a concurrent quota-sampler commit on the diary repo, died with `fatal: Cannot rebase onto multiple branches`, and had ALREADY consumed/deleted the `-f` temp entry file — the entry was silently lost (id:4347 silent-swallow class; recovered only because the invoking session still held the text).
  - **How / Design**: (a) delete the `-f` temp file ONLY AFTER commit+push succeeds — on any error, move it to a `.failed/` quarantine and print a LOUD stderr path (never silent unlink). (b) Find why the pull step hit "multiple branches" under concurrency (likely `git pull --rebase` with a multi-refspec fetch config or a missing explicit `origin <branch>` arg inside the flock) and pin the refspec / use explicit `origin <branch>` args. Keep the existing flock discipline.
  - **Acceptance**: a hermetic test (`tests/test_diary_append_entry_survival.sh`, `# roadmap:f8df`) that simulates a concurrent upstream commit landing between fetch and rebase, asserts the `-f` entry file SURVIVES the failed run (in `.failed/` with a loud path), and that a retry appends the entry EXACTLY once (no duplicate, no loss).
  - **Done-check**: `tests/run-tests.sh tests/test_diary_append_entry_survival.sh` then full `make test` after ticking (RED until then).
  - **Context**: `git-diary-workflow/diary-append.sh` (the `-f` consume path + the pull/rebase step under flock), TODO id:f8df.

- [x] [ROUTINE] Unify `orphan-scan.sh --cross-ledger` on an id-keyed, indent-agnostic twin-check (shared with `archive-closed.sh`) <!-- id:34c7 -->
  - **Why** (TODO id:34c7; meeting 2026-07-11-1239 D1): `--cross-ledger` missed 6 real drift items (ROADMAP `[x]` / TODO `[ ]`) because their TODO twin is an INDENTED sub-item, while `archive-closed.sh`'s id-keyed check caught them — the two use different anchoring.
  - **How / Design**: re-implement `--cross-ledger`'s twin match on an id-keyed, indent-agnostic basis (find the `<!-- id:XXXX -->` token anywhere on a checkbox line regardless of leading whitespace), matching `archive-closed.sh`'s approach so the two agree. Anchor on the id marker, not a column-0 `^- \[ \]` grep.
  - **Acceptance**: `tests/` (`test_orphan_scan_cross_ledger_indent.sh` or extend the cross-ledger test, `# roadmap:34c7`) — a fixture where ROADMAP has an `[x]` item whose TODO twin is an INDENTED `  - [ ]` sub-item IS flagged as cross-ledger drift; a matching non-indented case still flags; an agreeing pair (both `[x]`) is not flagged.
  - **Done-check**: run the test then full `make test` after ticking (RED until then).
  - **Context**: `meeting/orphan-scan.sh` (`--cross-ledger` mode), `todo-update/archive-closed.sh` (the id-keyed check to converge on). COUPLED with id:431f (the col-0 anchor blindspot in `--shipped`) — same script family; coordinate the anchor helper if touching both.

- [x] [ROUTINE] `orphan-scan.sh --shipped`: widen the col-0 anchor so INDENTED sub-items are classified <!-- id:431f -->
  - **Why** (TODO id:431f; found 2026-07-10 by the id:46f6 executor): the `--shipped` driver greps `^- \[ \] ` anchored at column 0, so 14 of 241 open id-bearing TODO items (6%) nested under a parent are never classified — not TICK-READY, not GATE-STALE, not the typed-edge umbrella/gate classes. Concretely inert: `gated-on:` markers on id:3c4c/eb92 and the UNMARKED-GATE expected on id:7df1.
  - **How / Design**: widen the anchor to `^\s*- \[ \] ` so indented `  - [ ]` items enter all `--shipped` classes; keep the col-0 behaviour otherwise unchanged. This is report-only (nothing auto-ticks); the change pulls 14 previously-unclassified items in at once — a measured, advisory burst, acceptable.
  - **Acceptance**: `tests/` (`test_orphan_scan_shipped_indent.sh`, `# roadmap:431f`) — an INDENTED `  - [ ]` item with a `children:` marker whose children are all `[x]` is reported UMBRELLA-READY; a pre-existing col-0 case is unchanged.
  - **Done-check**: run the test then full `make test` after ticking (RED until then).
  - **Context**: `meeting/orphan-scan.sh` (`--shipped` driver / anchor). Relates id:46f6 (typed edges), id:1b1a (md-merge fail-open), id:b3ee (original `--shipped` detector). COUPLED with id:34c7 (same anchor family) and id:4245 (which depends on `--shipped` seeing 7df1).

- [x] [ROUTINE] Surface the two deliberately-unmarked gate edges (`7df1`, `50c4`) as UNMARKED-GATE in `orphan-scan.sh --shipped` <!-- id:4245 -->
  - **Why** (TODO id:4245; meeting 2026-07-10-1430): the typed-edge pass wrote 8 `children:` + 10 `gated-on:` markers, but left `7df1` and `50c4` UNMARKED on purpose — their gate tokens (`b466`, `508d`) live in project_manager / relay-core and do not resolve locally. They must surface as UNMARKED-GATE (resolved via the routed:/inbox machinery, not a local `gated-on:` edge), not silently vanish.
  - **How / Design**: give `orphan-scan.sh --shipped` an UNMARKED-GATE class that flags an open item whose known cross-repo gate token is unresolved-and-unmarked-locally, reporting `7df1` and `50c4`. Keep it report-only. NOTE: `7df1`'s TODO twin is indented, so this likely DEPENDS ON id:431f's anchor widening landing first (else 7df1 is invisible to `--shipped`).
  - **Acceptance**: `tests/` (`test_orphan_scan_unmarked_gate.sh`, `# roadmap:4245`) — a fixture with an open item carrying a cross-repo gate token but NO local `gated-on:` marker is reported UNMARKED-GATE; a locally-marked `gated-on:` item is NOT.
  - **Done-check**: run the test then full `make test` after ticking (RED until then).
  - **Context**: `meeting/orphan-scan.sh` (`--shipped`), `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`. DEP: id:431f (indented-item anchor) — pick 431f first.

- [x] [ROUTINE] `md-merge.py update-ids`: fail LOUD on an unmatched id; gate appends behind `--allow-new` <!-- id:1b1a -->
  - **Why** (TODO id:1b1a, HIGH PRIORITY; found 2026-07-10): `md-merge.py:143-152` APPENDS an id not present in the file. Correct for NEW items, fail-OPEN for UPDATES — a caller intending to edit `id:abcd` who mistypes it gets a silent duplicate line, not an error. The whole point of routing writes through this helper is that it is the SAFE path.
  - **How / Design**: make intent explicit — `update-ids` FAILS LOUDLY (non-zero + the named unmatched tokens on stderr, writing nothing) when an id is not found; appends require an opt-in flag (`--allow-new`, or a separate `add-items` subcommand) that preserves today's behaviour. Then verify the id-comment regex (`<!--\s*id:([0-9a-f]{4})\s*-->`, `md-merge.py:135`) is not the only reader assuming the comment terminates immediately after the hex — the item names ~10 readers; at minimum fix `handback-followup.py:71`'s `$`-anchored regex which already silently no-ops on `id:78ff` (its id comment is followed by an `xledger-ok:` annotation).
  - **Acceptance**: `tests/` (`test_md_merge_update_ids_strict.sh`, `# roadmap:1b1a`) — `update-ids` with an unknown id exits non-zero and writes NOTHING; with `--allow-new` it appends as today; a companion assertion that `handback-followup` appends its note to a line whose id comment is non-terminal (`id:XXXX xledger-ok:…`).
  - **Done-check**: run the test then full `make test` after ticking (RED until then).
  - **Context**: `tools/md-merge.py` (`update-ids`, lines ~135/143-152), `relay/scripts/handback-followup.py:71` (`$`-anchored regex bug). Relates id:46f6 (typed-edge marker), id:ee62 (visible-vs-comment annotations), `docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md`.

- [x] [ROUTINE] Add a 5th capability lane `[INPUT — author]` (human-expert-authored content) to the lane contract (this-repo half) <!-- id:2b0b -->
  - **Why** (TODO id:2b0b; user 2026-07-11, M3 lane-triage): the 4 capability lanes don't cover "a human expert AUTHORS content/prose" (not credential/hardware=access, not design-judgment=meeting, not a discrete decision, not compute=mechanical). Surfaced by toesnail id:e552 and linguistic-unversals id:d58f, which stay `[HARD — hands]` until this lands.
  - **How / Design**: add `[INPUT — author]` to `relay/references/hard-lanes.md` (capability table + canonical marker set), and wire its two IN-REPO consumers — `relay/scripts/gather-human-backlog.sh` (id:78ff; bucket it onto the "you run these"/owner list, NOT a meeting) and `relay/scripts/roadmap-lint.sh` (recognition, so it isn't flagged as an unknown/untagged lane). Extend `tests/test_hard_lane_buckets.sh`'s marker-set cross-check.
  - **Acceptance**: `tests/test_hard_lane_buckets.sh` (extend, `# roadmap:2b0b`) green — an `[INPUT — author]` item is bucketed onto the owner/author list (not meeting), `roadmap-lint.sh` does not flag it as untagged, and the marker set in `hard-lanes.md` includes it.
  - **Done-check**: `tests/run-tests.sh tests/test_hard_lane_buckets.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/references/hard-lanes.md` (capability table + marker set), `relay/scripts/gather-human-backlog.sh`, `relay/scripts/roadmap-lint.sh`, `tests/test_hard_lane_buckets.sh`. CROSS-REPO coupling (out of this worktree's scope): project_manager `scan.py` (id:b466) reads the same `hard-lanes.md` contract and needs the matching lane added there — already tracked in TODO id:2b0b, not a new inbox item.

<!-- 2026-07-11 relay human: filed the impl for two ratified REVIEW_ME decisions —
     id:dfe4 (refine c095 heading-as-item detection) + id:26c2 (mechanical-daemon host-gate).
     Both [ROUTINE] with RED specs; NOT reopening c095/b3d0 (their contracts hold). -->

- [x] [ROUTINE] Refine `roadmap-lint.sh` c095 heading-as-item detection — only flag a `## …[LANE]…` heading as MISSING-id when its children are BARE status markers (no own class tag + id) <!-- id:dfe4 -->
  - **Why** (REVIEW_ME decision, human 2026-07-11; audit Run 70 finding, filed 5dc3): `roadmap-lint.sh`'s c095 "heading-as-item" detector treats ANY `## …[LANE]…` heading as a work-item heading that must carry its own `<!-- id:XXXX -->`. That false-positives on descriptive relay-handoff SECTION headers (`## [MECHANICAL] lane-anchor hotfix …`, `## [MECHANICAL] recipe explicit-success-marker …`, `## [ROUTINE] case-c bare-only lane count …`, ROADMAP ~L2861/2883/2911) whose SINGLE child is an already-`[x]` item carrying its OWN `[ROUTINE]` tag + id (0d58/fd37/9078). Demanding an id on such a heading is wrong: adding one would DUPLICATE the child's id and break single-id-two-views. The genuine c095 shape is a heading that OWNS the lane+id whose child `- [ ]` lines are BARE status markers (no own tag+id) — only that shape should be flagged.
  - **How / Design**: refine the detector so a `## …[LANE]…` heading is treated as a heading-*item* (and thus required to carry an id) ONLY when its child checkbox lines are BARE status markers — i.e. none of its immediate children carry their OWN class tag (`[ROUTINE]`/`[HARD]`/…) + `<!-- id:XXXX -->`. If ANY child carries its own tag+id, the heading is a descriptive SECTION title, not a work-item, and MUST NOT be flagged for a missing id. Keep the existing genuine-c095 detection (heading owns lane+id over bare-marker children) unchanged. Anchor the child-tag/id test on the same markers the rest of the lint uses (do not bare-substring). Report-only today (relay-doctor/roadmap-lint exit 0); the refinement removes 3 false-positives without weakening real detection.
  - **Acceptance**: `tests/test_roadmap_lint_c095.sh` (`# roadmap:dfe4`) green — a fixture ROADMAP where (a) a `## [LANE]` heading whose SOLE child carries its own `[ROUTINE]` tag + `<!-- id:XXXX -->` is NOT flagged, and (b) a `## [LANE]` heading owning a lane+id over BARE-marker children (no own tag/id) IS still flagged MISSING-id.
  - **Done-check**: `tests/run-tests.sh tests/test_roadmap_lint_c095.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/roadmap-lint.sh` (the c095 heading-as-item detector), the 3 in-repo false-positive headers at ROADMAP ~L2861/2883/2911 (children 0d58/fd37/9078), REVIEW_ME.md (this decision), original c095 tension (audit Run 70 / filed 5dc3).

- [x] [ROUTINE] Add a host-gate to `mechanical-daemon.sh` — skip+defer any recipe whose `.host` != `uname -n`, never execute it <!-- id:26c2 -->
  - **Why** (REVIEW_ME decision, human 2026-07-11; wave-2a review finding on id:b3d0): the recipe schema's `host` field is REQUIRED non-empty by `recipe-validate.sh` and documented as binding the recipe to a target host, but `mechanical-daemon.sh` reads `est_wall`/`resource`/`cmd`/`artifact` and NEVER reads `.host` nor compares it to `$(uname -n)` — so it would auto-EXECUTE a shell `cmd` from a recipe bound to a DIFFERENT host. Today the drop-dir is per-host so a mismatch can only arrive by mistaken copy or a future shared-transport (de31/b444) — not a live bug — but the daemon auto-runs shell, the review contract's §2c treats a host mismatch as *unrunnable*, and no comment records "host advisory / drop-dir per-host". Defense-in-depth: gate it. NOT reopening b3d0 (its tested contract + launch-gate hold); this is a follow-on.
  - **How / Design**: add a one-line guard in the per-recipe processing loop, BEFORE the launch-gate / run, that reads the recipe's `.host` and, when it != `$(uname -n)`, SKIPS + DEFERS the recipe (leave it in `pending/`, do NOT move to `running`, do NOT run `cmd`, no artifact, no inject) — mirroring the existing check-and-defer path for a claimed resource. Log a DISTINCT line (e.g. `defer recipe=<name> reason=host-mismatch host=<recipe.host> this=<uname>`) so it is separable from a resource-gate defer. Do not delete or quarantine the recipe (a mistaken copy may be recoverable / re-routed); defer is the conservative disposition. Keep `RELAY_RECIPE_DIR` and the other env overrides intact for hermeticity.
  - **Acceptance**: `tests/test_mechanical_daemon.sh` (extend, `# roadmap:26c2`) green — a valid recipe whose `.host` is a FOREIGN name is DEFERRED (stays in `pending/`, no artifact, no inject unit), while an otherwise-identical recipe whose `.host == $(uname -n)` still runs `pending→running→done` + injects (the existing b3d0 permit case, unbroken).
  - **Done-check**: `tests/run-tests.sh tests/test_mechanical_daemon.sh` then full `make test` after ticking (RED until then).
  - **Context**: `relay/scripts/mechanical-daemon.sh` (per-recipe loop, the check-and-defer path to mirror), `relay/references/recipe-manifest.md:51` (`host` field), `relay/scripts/recipe-validate.sh` (requires `host` non-empty), ROADMAP id:b3d0 (A3, the daemon contract), REVIEW_ME.md (this decision).

<!-- 2026-07-10 handoff C2 (run relay-20260710-171033-12826-handoff): promoted the sole
     `promote`-disposition TODO item (unpromoted-scan: 1 promote / 1 laned / 58 surface).
     Single-id-two-views (D2): id:77ce REUSES its open TODO.md twin ([INBOUND routed:2f0c
     from relay-core]). [ROUTINE] with RED spec tests/test_reconcile_planner.sh (# roadmap:77ce).
     Surface items are the mechanical `human`-verdict filer's job, NOT promoted here
     (handoff.md §surface); the one `laned` item (id:abe7, [HARD — meeting]) is already
     lane-tagged and awaits a /meeting, not a handoff. -->

<!-- 2026-07-16 review §5b reverse-handoff (run relay-20260716-125514-23493-review): the
     window added 4 unqualified TODO items. TWO are execution-ready and promoted here with
     RED spec tests, REUSING their TODO ids (single-id-two-views, D2 — never minted fresh):
     id:1312 (tests/test_unpromoted_scan_anchoring.sh) and id:d515
     (tests/test_scan_routed_apply_header.sh). Both specs verified RED-for-the-right-reason
     with passing controls, not crashing/vacuous.
     The other two are NOT promoted — each turns on owner judgment, so they stay TODO-side
     /meeting candidates per §5b: id:1f60 (what counts as a "delegated verdict"; surface vs
     block) and id:2456 (explicitly bars a skill from authoring the invariant prose). -->

- [x] [ROUTINE] `unpromoted-scan.sh` twin check: ANCHOR to an item's own trailing `<!-- id:XXXX -->` marker instead of a bare `grep -qF "id:$token"` over all of ROADMAP.md — ordinary prose that merely MENTIONS a token ("…tracked as id:2b63") currently registers it as already-twinned, so the item silently drops out of the backlog scan (observed 2026-07-16: `df4e` went `laned` → 0 rows). This is the id:2dea hidden-backlog failure the scan exists to prevent, reachable by prose; same hazard class as the `inbox-done` substring match and md-merge's fail-open append. `scan-routed.sh` already anchors for this reason — mirror it. **Acceptance**: `tests/test_unpromoted_scan_anchoring.sh` green — a prose-only mention does NOT twin an item (still reported), while a genuine own-marker twin IS still suppressed (control) and an absent id is still reported (control). **Done-check**: `make test` fully green with the box ticked. <!-- id:1312 -->

- [x] [ROUTINE] `scan-routed.sh` APPLY-mode header lies about dry-run: line ~199 `APPLY mode${DRY_RUN:+' (DRY-RUN)'}` uses `:+` (expands when NON-EMPTY) against the default `DRY_RUN=0` — a non-empty string — so EVERY apply run, including real writing ones, is labelled `(DRY-RUN)`; the single quotes also print literally (`APPLY mode' (DRY-RUN)' ===`). Write-gating is correct (`-eq 1`), so this is cosmetic-but-backwards for an audit trail (observed 2026-07-16: header said DRY-RUN while the run committed 5 INBOUND stubs). Fix: gate the label on the VALUE, e.g. `$([[ $DRY_RUN -eq 1 ]] && echo ' (DRY-RUN)')`. **Acceptance**: `tests/test_scan_routed_apply_header.sh` green — real `--apply` header omits DRY-RUN (and the run demonstrably wrote, so the assertion isn't vacuous), `--apply --dry-run` still advertises it and writes nothing. **Done-check**: `make test` fully green with the box ticked. <!-- id:d515 -->

<!-- 2026-07-16 review §5b (run relay-20260716-125514-23493-review): id:521f promoted
     [ROUTINE] with a RED spec, REUSING its TODO id (D2 — ingested last round from the
     inbox dead-letter routed:f1f5 and never qualified). Same unanchored-token-grep class
     as the id:1312 just closed; its `routed:f1f5` twin stays on the TODO line so
     `append.sh inbox-done f1f5` can resolve it. -->

- [x] [ROUTINE] `roadmap-lint.sh` id extraction is an UNANCHORED first-match grep: `id_re='id:[0-9a-fA-F]{4}'` (line ~217) used with bash `=~` (lines 270/294/323/434/447) captures the FIRST `id:XXXX` on the line, not the canonical trailing `<!-- id:XXXX -->` marker. Two symptoms, both reproduced hermetically 2026-07-16: (1) MISATTRIBUTION — an item whose prose cites another token (`dep: id:1643`) reports its violation as `[id:1643]`, sending a human to the wrong item (real case: zkWhale ROADMAP id:4148); (2) FALSE-NEGATIVE — clause 2 ("has an id token") is satisfied by ANY id on the line, so an item with NO own marker passes clean whenever its prose cites some other token, and this lint's whole reason for existing (the loud reject) never fires. Same hazard class as id:1312 (just closed) and the `inbox-done` substring match; `scan-routed.sh` and `unpromoted-scan.sh` both anchor already. Fix: anchor extraction to the canonical trailing `<!-- id:XXXX -->` comment (prefer LAST-match / comment-anchored) — and since this makes the THIRD hand-rolled copy of the same anchored extraction, prefer factoring ONE shared helper over a third copy (the TODO twin asks for exactly this). **Acceptance**: `tests/test_roadmap_lint_id_anchoring.sh` green — a violating item citing another id is reported under its OWN id (not the cited one), an item with no own marker is still loud-rejected despite a prose citation, and (control) a conforming item that merely cites another id stays clean (no false positive). **Done-check**: `make test` fully green with the box ticked. <!-- id:521f -->

<!-- 2026-07-17 handoff (interactive apex session): promoted TODO id:1735 (three
     independent defects found on run relay-20260717-100452-13146, loderite) REUSING
     its TODO twin (single-id-two-views D2). (a) below is the same id, reused, scoped
     to the proven handback-summary root only. (b) is filed as id:dc5b — an
     [INPUT — meeting] architecture-commitment RECOMMENDATION (C1-now/C2-fallback,
     owner ratification required — NOT decided, NOT executor work). (c) is a distinct
     stop-classification defect, id:4ca8. (c-adjacent) audit is id:4a46, optional. Ids
     minted via `meeting/append.sh new-ids 3 .`. See
     `docs/meeting-notes` (none yet — full evidence lives in the TODO id:1735 line and
     this handoff's investigation notes) for the falsified-hypothesis finding on (c). -->

- [x] [ROUTINE] **relay-loop: handback summary must be reconciled against the event stream** — `state.blocked` is REASSIGNED wholesale every round (`relay-loop.js:1491`, `state.blocked = discovery.surfaced.map(…)`) while five handback sites (1657, 1668, 1807, 1915, 1999) push into it as a cross-round accumulator. Any handback from round N is destroyed at round N+1, so the returned `handbacks` (line 2206) is empty and the front door prints "0 HANDBACKs" (SKILL.md step 4) while a green, wanted fix sits on a parked ref. REPRODUCED: run `relay-20260717-100452-13146` (loderite) — event log has `kind:"handback"`, summary had `handbacks:[]`. Fix: (1) SPLIT the two roles — keep a persistent `state.handbacks` accumulator that is NEVER reassigned, and let `state.blocked` stay the per-round surfaced view; repoint all five push sites at the accumulator. (2) Derive the returned `handbacks` from the accumulator. (3) ASSERT the invariant before return: every `pushEvent('handback', …)` emitted this run has a corresponding entry in `handbacks[]`; on a trip, FAIL LOUDLY (log an `INVARIANT VIOLATED` line + include the orphaned events in the returned object) — never silently return the smaller list. Note the invariant is one-directional today: lines 1657/1668 push to `state.blocked` WITHOUT a matching `pushEvent('handback')`, so `handbacks[] ⊇ handback-events` is the assertable direction (see id:4a46). RED spec: `tests/test_relay_loop_handback_summary.sh`. Relates id:689c, id:c8b6, id:194e. <!-- children:4ca8 --> <!-- id:1735 -->
  - **Implementation note (2026-07-17, executor session):** built STRICTER than the entry's own
    prose — `state.blocked` is fully RETIRED (not kept as the per-round view under its old name)
    and split into `state.surfaced` (per-round view, reassigned every round — the intentional
    behaviour) and `state.handbacks` (persistent accumulator, only ever pushed to, NEVER
    reassigned). All 5 push sites target `state.handbacks.push(`; the returned `handbacks` is
    `reconcileHandbacks(state.handbacks)`; the invariant is `assertHandbackInvariant` (logs
    `INVARIANT VIOLATED` + returns `handbackInvariantViolations` in the summary object on a
    trip). Pure logic lives in `relay/scripts/handback-summary.mjs`; relay-loop.js carries
    byte-equivalent inline copies (grep-pinned, same pattern as `handback-guard.mjs`/id:1432).
    RELAY_STATUS.md's "Blocked" section now shows `state.surfaced ∪ state.handbacks` (a real
    fix, not just cosmetic — it used to lose outstanding handbacks the same way the final
    summary did, just less often because scheduleStatusWrite usually ran before the next
    round's reassignment).
  - **Honest coverage limit**: `relay-loop.js` is a Workflow module that cannot be imported or
    executed in this harness (id:2ec4), same limit as id:f980/id:365b. The pure-helper tests
    (case 4 in the RED spec) drive `handback-summary.mjs`'s real accumulate/reconcile/invariant
    LOGIC directly through node and are the actual spec. The structural greps (cases 1–3) only
    pin that relay-loop.js WIRES the fixed shape (no `state.blocked` field survives, all 5 push
    sites target the persistent accumulator, the invariant assertion + its return field exist) —
    they do not prove the wiring executes correctly inside a live multi-round pool run, which is
    unreachable from this harness.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_loop_handback_summary.sh` green, then
    full `tests/run-tests.sh` green. Verified 2026-07-17.

- [x] [ROUTINE] **relay-loop: a suppressed/surfaced repo must not count as "backlog drained"** — DISTINCT root from id:1735 (the TODO's "stale discovery snapshot" hypothesis is FALSIFIED — discovery was fresh and correct). Run `relay-20260717-100452-13146`: `reconcile-repo.sh:192` (id:1f53 orphan suppress-redispatch) correctly refused to re-dispatch loderite because 4c02's partial work was parked, and `add_surfaced` surfaced the REPO → `discover-repo.sh` skips classify → `actionable.length === 0` → `runRound` returns `{actionable:0}` → 2 dry rounds → "backlog drained" while 8 open [ROUTINE] items sat there. `classifyDrainBacklog` (line 814) DID see the entry but has no regex arm for `suppressed re-dispatch`, so it logged a bare "1 other"; `stopReason` was never set (RELAY_STATUS §Stop reason: none). Fix: (1) the dry-round predicate must distinguish "no work" from "work exists but is BLOCKED" — a round with ≥1 surfaced/suppressed repo is NOT a dry round for drain purposes; stop with `stopReason: "blocked-pending-human"`, not a silent drain. (2) Add a `suppressed` bucket to `classifyDrainBacklog` and surface it as loudly as `gated` (it already logs a /relay human pointer for gated). (3) Always SET `stopReason` on the drain exit — today it stays `null`, so the category is lost even when correctly derived. RED spec: `tests/test_relay_loop_drain_vs_blocked.sh`. Relates id:1f53, id:689c, id:1735. *Scope note for the executor:* do **not** change `reconcile-repo.sh`'s suppression behaviour — id:1f53 is working as designed. The whole-repo blast radius (one parked orphan stalls the repo's other 7 open items) is a **separate design question**, deliberately NOT specced here; if the owner wants item-granular suppression that is a `/meeting`, not this item. <!-- id:4ca8 -->
  - **Implementation note (2026-07-17, executor session):** built on top of id:1735's
    `state.surfaced`/`state.handbacks` split (this item's runRound() return values and
    classifyDrainBacklog's input both consume `state.surfaced`). Added two pure predicates to
    `relay/scripts/drain.mjs`: `isBlockedRound(r)` (substantive===0 AND surfaced>0 — stop
    IMMEDIATELY with `stopReason='blocked-pending-human'`, no need for a 2nd confirming round
    since the surfaced count already explains why) and `isDryRound(r)` (substantive===0 AND
    surfaced===0 — the existing 2-consecutive-round drain path, now gated on this predicate
    instead of a bare `(r.substantive||0)===0` check). `isBlockedRound` is checked BEFORE
    `isDryRound` in the outer loop, so a surfaced round never reaches the dry-counter at all.
    `classifyDrainBacklog` gained a `suppressed` bucket (verbatim-matches
    `reconcile-repo.sh`'s `"suppressed re-dispatch: …"` reason) with its own `/relay reconcile`
    pointer, parallel to `gated`'s `/relay human`/`/meeting` pointer. The drain exit now always
    sets `stopReason` (`stopReason || 'drained'`), never leaves it null. `reconcile-repo.sh`
    itself is UNTOUCHED — id:1f53's suppression behaviour and its whole-repo blast radius are
    explicitly out of scope here, exactly as this item specified.
  - **Honest coverage limit**: same as id:1735/id:f980/id:365b — `relay-loop.js` cannot be
    imported or executed in this harness (id:2ec4). The pure-helper tests (case 1–2 in the RED
    spec) are the real spec, driving `isBlockedRound`/`isDryRound`/`classifyDrainBacklog`
    directly through node. The structural greps (case 3) only pin that relay-loop.js wires the
    fixed shape and orders the two checks correctly — they do not prove a live multi-round pool
    run actually stops at the right round with the right reason.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_loop_drain_vs_blocked.sh` green, then
    full `tests/run-tests.sh` green. Verified 2026-07-17.

- [x] [INPUT — decision] Opus quality-degradation investigation + standing model-probe deliverable — 🚧 GATED (auto, id:3801; route:human): Closure blocked: id:23e9 seed needs the claude-probe OS user (id:d0c0, useradd/sudo — forbidden for a relay child) + real Opus/Sonnet/Haiku token runs — needs /relay human <!-- id:dba3 --> — **DECIDED 2026-07-13 (relay human): reuse the EXISTING `relay-probe` OS user** (no `useradd`/sudo needed — the id:d0c0 blocker lapses); it only needs a fresh credential copy, which the owner consented to provide. HANDS residue (surface to "you run these"): copy new credentials into the `relay-probe` user's `~/.claude`, then the probe can seed the id:23e9 pre-registered band (5 cold runs/tier across Opus/Sonnet/Haiku). Box stays open until credentials are copied + first seed lands. — **DONE 2026-07-13 (user directive):** marked complete. The standing model-probe (`tools/model-probe.sh` + versioned battery) IS the durable deliverable; the investigation was expected inconclusive by design. Related open items NOT auto-closed here — close separately if you consider them subsumed: id:23e9 (seed+close operational sub-item), id:5fc6 (load/disappointment observational umbrella), id:903a/e3c0/241c (investigation axes).
  - **Meeting held 2026-06-17** (`docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md`). **Investigation expected inconclusive** (n=4 anecdotes, n=1 sessions, no prior baseline — self-anchored prior). Real deliverable = the standing probe. Close this item once id:2d01+c345+040a+23e9 land and the baseline is seeded.
  - **Evidence source:** memory `opus-quality-degradation-20260616.md`; 4 incidents from session `bf9dd9e5` (1213 lines / 2.4M tokens — very long; confound). Key hypotheses: long-context fatigue vs wall-clock duration (idle-gap / KV-cache rot) vs model-serving regression.
  - **Investigation steps (id:903a, e3c0, 241c):** three-axis turn-cluster (`context_depth`, `elapsed_wall_time`, `idle_gap_before_error`) on `bf9dd9e5` + yesterday's last `/relay` session; cold fixed-prompt probe re-posing incidents #2/#3; Anthropic status/version check.
  - **Durable deliverable (id:2d01, c345, 040a, 23e9, 6ffe):** `tools/model-probe.sh` + versioned `tools/model-probe.battery.jsonl` (~15–20 timeless items) + append-only log capturing resolved model-id-str + frontend metadata + tok_per_s; three-tier (Opus + Sonnet + Haiku); pre-registered acceptance band; 2-consecutive-miss alarm. Invocation path GATED on ToS pre-check (id:2d01). Cadence = on-demand seed now, cron deferred.
  - **Billing path REAFFIRMED 2026-06-22:** Anthropic's May plan to move `claude -p` / Agent SDK OFF subscription rate limits onto a dedicated monthly credit is **deferred** (email 2026-06-22 — subscription usage unchanged, advance notice promised before any cutover). Path A's "subscription quota, no per-token billing" rationale (id:2d01) **holds** — no new gate, no decision change; keep path B (API + `--bare`) as the advance-notice hedge. Memory `anthropic-agent-sdk-billing-deferred`; broader evaluation = TODO id:00a5.
  - **Detection rule:** flag only on **2 consecutive** out-of-band runs; tokens/sec is the weak silent-swap hedge (silent same-label swap near-unprovable without baseline; the probe is what makes the NEXT suspicion answerable).

- [x] [INPUT — meeting] DEFERRED (decided 2026-06-17): Distributed relay orchestrator — multi-machine, dynamic membership <!-- id:de4e --> <!-- DEFERRED-CLOSED 2026-07-13 (relay human): ticked to clear the recurring roadmap-lint DECIDED-LEFT-OPEN warn; reopen if multi-machine relay is ever needed. -->
  - **Meeting HELD 2026-06-17 — decided DEFERRED on quota economics (do NOT execute, no
    further `/meeting` owed).** Design-gate originally: choose the coordination substrate
    before any code. Captured 2026-06-16 from a working session; the gate was resolved by
    the 2026-06-17 meeting (see D1 below). Relabel per id:9c92 (review 2026-06-18) — the
    old "DECISION GATE / needs a /meeting" heading contradicted the resolved block below.
  - **Why**: leases (`claim.sh`) + `relay.toml` are flock-on-local-dir → single-host
    only, so concurrent `/relay` on zomni+fievel has NO cross-machine mutual exclusion
    (both fully work the same repo; slower one's `--ff-only` push strands). Also lifts
    the `min(16, cores-2)` per-workflow local-parallelism ceiling by spreading across
    machines.
  - **Seed brief** (start the meeting here): `docs/meeting-notes/2026-06-16-2257-distributed-relay-orchestrator-SEED.md`.
  - **⚠️ MEETING HELD 2026-06-17 — D1 constraints (reframed premise, do NOT build now):**
    - **GitHub-as-control-plane / ref-CAS REJECTED.** Serverless is the point; GitHub
      coordination dependency is a no-go.
    - **If ever built:** peer rendezvous (zomni ↔ fievel try to talk directly); if
      unreachable → degrade-to-solo (each assumes it is alone, no quorum). Rare
      split-brain (low-likelihood if both online but cloudflare tunnel fails) caught
      after the fact by `md-merge.py` line-scoped writes + `--ff-only` reject +
      `orphan-scan --cross-ledger`. Optimistic concurrency + merge backstop, NOT CAS.
    - **Deferred reason:** zomni alone exhausted the 7-day→daily quota share 2026-06-16;
      cross-machine throughput is moot until quota economics change.
    - See `docs/meeting-notes/2026-06-17-0953-k3s-parallelity-coordination-design.md`.
  - **Lead candidate**: ~~git-remote-as-control-plane (CAS ref-locks)~~ **REJECTED** —
    see D1 above. Future candidate: direct peer rendezvous + degrade-to-solo.
  - **Related**: id:ebfb / id:0902 (current single-host claim registry),
    `docs/meeting-notes/2026-06-15-1216-relay-dispatch-safety-cluster.md`.

- [x] [HARD] Close the mechanical-orphan resolution loop so [MECHANICAL] items can't rot (user 2026-07-13: "needs more automation otherwise these things get lost"). relay-doctor check-12 (id:1bd1) already DETECTS a [MECHANICAL] ROADMAP item with no matching recipe in the drop-dir, but resolution is fully manual (an Opus session hand-authors the recipe JSON) so orphans silently accumulate — the loud-detection/silent-no-op anti-pattern. Build the resolution half WITHOUT breaking the whitelist trust boundary (no auto ROADMAP→pending/ execution): (a) a `/relay review` (or discovery) sub-step that per orphan AUTO-DRAFTS a recipe skeleton into a NEW `recipes/drafts/` dir (id/repo prefilled; host from `[host:]`; resource from `[INTENSIVE — <res>]`; cmd/est_wall/acceptance_artifact left as explicit TODO for an Opus reviewer) — a draft is NOT executable (daemon only consumes pending/), so an Opus reviewer still deliberately promotes draft→pending; (b) LOUD-surface every orphan + un-promoted draft in RELAY_STATUS.md + the `/relay human` gather; (c) the resource-probe bespoke-token gap is already fixed alongside (r5-jvm/lean/xvfb-electron, commit e980b07); (d) add a periodic RETRY for check-and-deferred recipes — `mechanical-daemon.path` is `PathModified`-triggered with NO retry timer, so a recipe that defers once (resource busy / host mismatch / intensity at that instant) stalls forever until `pending/` is next modified (observed 2026-07-13: the ac14 recipe deferred at the pre-fix tick and could not self-re-evaluate after the fix landed). Add a low-cadence `mechanical-daemon.timer` (or equivalent) so deferred recipes are retried, closing the "deferred → silently stuck" hole. First real instance: isochrone id:ac14 (recipe hand-authored + dropped 2026-07-13). Acceptance: a fresh [MECHANICAL] orphan produces a surfaced draft within one review pass, and a deferred recipe re-attempts without a manual nudge; no orphan or deferred recipe is ever silent. <!-- id:8a6b -->

- [x] [ROUTINE] BUG: discovery classifier emits a FALSE `execute` verdict ("Open executor-actionable [ROUTINE] ROADMAP items present") for repos with NO open actionable [ROUTINE] item. — FIXED 2026-07-13: root cause was NOT the predicate (correct) but `gather-repo-state.sh`'s `top_intensive` filter under-excluding gated/`[MECHANICAL]` `[INTENSIVE]` lines → `classify-verdict.sh` fold(b) fabricated a phantom `[ROUTINE]`. Fix (line 267): added `[MECHANICAL]|🚧|BLOCKED` to the exclusion. RED spec `tests/test_classify_false_execute_no_routine.sh` green; isochrone→review, it-infra→no-execute; suite 232/0. Re-checkable via the test. Observed 2026-07-13 (run relay-20260713-130624-24135): **isochrone** (zero [ROUTINE] items at all — only [INPUT — meeting] + gated [MECHANICAL]) and **it-infra** (both [ROUTINE] items id:935e/6e27 are `[x]` closed) each got execute-dispatched and immediately handed back "no executor-actionable work" — wasted a worktree + Opus/Sonnet child per false dispatch. The `actionable_routine_open` / `roadmap_actionable_open` predicate (`classify-repo.sh`, also `classify-verdict.sh`) is over-counting: it appears to treat closed `[x]` and/or absent [ROUTINE] as open-actionable. A RED test reproducing BOTH cases is the spec; fix the predicate to require primary-lane [ROUTINE] AND open `[ ]` AND not @manual/🚧/BLOCKED. <!-- id:2ab2 -->

- [x] [HARD] Handbacks must be LOUDLY tracked + stop the re-dispatch loop (user 2026-07-13: "when relay agents hand back, that should be loudly tracked and fixed somehow"). `handback-followup.py` (id:3801) durably gates ITEM-level handbacks (size-out / decision-gate / hard-split), but a WHOLE-DISPATCH handback ("no executor-actionable work / classifier verdict wrong", route=none) just no-ops → the repo is re-dispatched EVERY round (observed: it-infra false-execute in rounds 3,5,6,7,8 of run relay-20260713-130624-24135 — ~5 wasted children on ONE bogus verdict). Add: (a) **dispatch-level suppression** — a repo+verdict that hands back "no work" is NOT re-dispatched again in the same run until its discover-sig changes for a genuine reason (negative-cache / cooldown), so a false/stale verdict can't loop; (b) **loud repeat-tracking** — the exit summary + RELAY_STATUS flag any repo that handed back ≥2× in a run as an ALERT (a repeating handback is a bug signal, not noise) — and feed each into the id:2ab2-style "file + investigate" path rather than evaporating; (c) route=none should leave a durable breadcrumb. Complements id:2ab2 (which fixes the specific false-execute predicate) — this is the defense-in-depth so ANY future false/stale verdict is capped + surfaced, never silently looped. <!-- id:1432 -->

- [x] [ROUTINE] REVIEW_ME.md archiver — extend `archive-closed.sh` to a 3rd ledger <!-- id:85d3 -->
  - **What**: `relay/scripts/archive-closed.sh` today archives closed `- [x]` items from
    TODO.md + ROADMAP.md only. `REVIEW_ME.md` (the human review queue) accumulates closed
    `[x]` items with NO archiver (measured 2026-07-14: 15 closed / ~20 KB in this repo).
    Add REVIEW_ME.md as a third source, draining its closed top-level `- [x]` blocks into a
    `REVIEW_ME.archive.md` sibling.
  - **Spec / how it differs from TODO/ROADMAP**: REVIEW_ME items are NOT cross-ledger
    checkbox twins — a REVIEW_ME line often *references* an `id:` whose real ledger home is
    TODO/ROADMAP, so the twin-safe open-twin protection does NOT apply: archive a REVIEW_ME
    `[x]` block on its own state. Reuse the EXISTING block model (a top-level `- [x]` bullet
    plus every following line until the next top-level bullet or heading — this already
    captures column-0 prose + `>` blockquote correctly). NEVER move/prune the
    `# Human review queue` H1 header or its `<!-- budget: … -->` marker. Idempotent; a
    second run is a clean no-op. `--dry-run` reports the REVIEW_ME count alongside TODO/ROADMAP.
  - **Acceptance**: `tests/test_review_me_archive.sh` (roadmap:85d3) is green — a fixture
    REVIEW_ME.md with a closed `[x]` item (incl. a column-0 prose line + a `>` blockquote in
    its body) and an open `[ ]` item → the closed block (with its prose/blockquote) moves to
    `REVIEW_ME.archive.md`, the open item + the `# Human review queue` header + budget marker
    stay, second run is a no-op.
  - **Done-check**: tick this box, then `make test` fully green.
  - **Note**: the periodic-trigger WIRING (systemd timer / `/relay review` sub-step) is
    id:046a's job — this item only adds the REVIEW_ME *capability* to the archiver, which is
    independently testable. Reuses open TODO twin id:85d3 (single-id-two-views).

- [x] [ROUTINE] ROADMAP archiver: capture column-0 prose/blockquote + move emptied transient headers <!-- id:546b -->
  - **Bug 1 (prose/blockquote orphaning) — `relay/scripts/roadmap-archive.sh` only**: its
    `is_continuation()` treats a `[x]` item's body line as part of the block ONLY if the line
    is blank or indented, so a **column-0 prose paragraph or `>` blockquote** (common in
    ROADMAP item bodies) is left stranded in ROADMAP.md when the `- [x]` header moves to the
    archive — splitting the record across two files. Fix: adopt the SAME block boundary
    `archive-closed.sh` already uses (a block runs until the next top-level `- [` bullet OR
    any heading), so column-0 prose/blockquote is captured. `archive-closed.sh` does NOT have
    this bug — do not regress it.
  - **Bug 2 (emptied transient headers left behind) — BOTH `roadmap-archive.sh` AND
    `archive-closed.sh`**: after every item under a `##`/`###` grouping heading is archived,
    the emptied heading is left in ROADMAP.md as clutter. **DECIDED (user 2026-07-14): move an
    emptied transient grouping header INTO the archive together with its block** (preserving
    grouping context), NOT delete-in-place. **Protected — NEVER moved even when emptied**: the
    H1 title line (`# …`) and the standing buckets whose heading text is exactly one of
    `Items`, `Current`, `Done`, `Backlog` (case-insensitive, ignoring any trailing
    `<!-- … -->`). Only move a header that (a) is non-protected AND (b) had ≥1 item archived
    THIS run AND (c) now has zero remaining top-level items under it. A header that was ALREADY
    empty on arrival (author placeholder) is left untouched. This REVERSES the prior
    "headers structural — no pruning" stance (test T9), by explicit user directive.
  - **Acceptance**: `tests/test_roadmap_archive.sh` updated + green:
    (a) NEW case — a `[x]` item whose body has a column-0 prose line AND a `>` blockquote →
    both move to the archive, nothing stranded in ROADMAP.md;
    (b) new coverage in `tests/test_roadmap_archive_prose_headers.sh` — a non-protected
    transient grouping header (e.g. `## batch 2020-01-01`) whose only item is archived → the
    header moves to `ROADMAP.archive.md` and is gone from ROADMAP.md; a protected `## Items`
    header whose only item is archived → STAYS in ROADMAP.md; an already-empty header on
    arrival is left in place. NOTE: existing T9 in `tests/test_roadmap_archive.sh` asserts the
    protected `## Items` header stays — it REMAINS GREEN under the new behavior (Items is
    protected); only refresh its now-stale "no section pruning" rationale comment, do not delete it;
    (c) same emptied-header-move behavior verified for `archive-closed.sh` (extend
    `tests/test_archive_closed.sh` if present, else add coverage).
  - **Done-check**: tick this box, then `make test` fully green.
  - **Reuses** open TODO twin id:546b (single-id-two-views). Relates id:6b67 (built
    roadmap-archive.sh), id:046a (archive-closed consolidation).

## Inbox write-path integrity (meeting 2026-07-17-1450, id:34c2 / id:de36)
<!-- 2026-07-17 (interactive apex meeting, owner-ratified D1-D4). Filed by the meeting, NOT
     implemented by it: this repo is relay-managed and `routed:6fd5` (filed 6 min before the
     meeting, from the owner's own complaint that day) proposes the orchestrator must not
     implement in the foreground. D4 honors that shape without ratifying the open proposal.
     The two items below have DISJOINT file targets (meeting/append.sh vs meeting/SKILL.md)
     per routed:c28e, so the pool may run them concurrently. -->
- [x] [ROUTINE] append.sh inbox write-path integrity — validate, mint-inside, echo-what-was-written <!-- id:34c2 -->
  - **Why**: `routed:acc7` was minted, reported as filed, and never written. The loderite hand-run ran
    `ID=$(append.sh new-id); append.sh -t inbox -e "… <!-- routed:\$ID -->"; echo "filed routed:$ID"` —
    `$ID` **escaped** in the payload, **unescaped** in the echo. Bash wrote the literal `$ID` to
    `todo-inbox.md:143`; the echo said `acc7`. `loderite/TODO.md:40` (`id:0c54`) then cited a token
    that existed nowhere. Root cause is not the escaping: `append.sh -t inbox` accepts arbitrary text,
    validates nothing, and prints **nothing** on success (`meeting/append.sh:283-287`), so the caller
    invents its own receipt from a variable with no causal link to the bytes on disk. Same defect class
    as id:1735 (self-reported summaries) — and the item being filed was itself *about* that class.
  - **Design (owner-ratified D2 + D3)**: three changes to `meeting/append.sh`, all scoped to `-t inbox`:
    1. **(A) Validate on write.** Reject (non-zero, nothing appended) any `-t inbox` entry not matching
       the conforming form: `^- \[[ x]\] \[[^]]+\] .* <!-- routed:[0-9a-f]{4} -->$`. A literal `$ID`
       fails this. Error message must name the offending line and the expected form.
    2. **(B) Mint inside append.** New form `append.sh -t inbox --route-to <target-repo> -e "<description>"`:
       append.sh mints the token, builds the whole conforming line (`- [ ] [<target>] <description>
       <!-- routed:XXXX -->`), appends it under the existing flock, and prints the token. The caller
       never interpolates a token into a payload. Precedent: `new-children` (`append.sh:206-221`) already
       emits its own marker rather than making the caller build it.
    3. **Echo what was written.** `-t inbox` **always** prints the routed token actually written to disk —
       for `--route-to`, the one it minted; for raw `-e`, the one **parsed back out of the appended line**.
       stdout becomes ground truth, so `filed routed:$(append.sh …)` cannot lie.
    Fold-in (D3): `--route-to`'s mint collision-checks the **routed** namespace — existing inbox
    own-markers plus the target repo's `routed:` citations — not just `scan_ids <root>`'s `id:` tokens.
    `scan_ids` (`append.sh:176-185`) greps `id:[0-9a-f]{4}` over `<root>` only; `routed:acc7` matches
    neither the pattern nor the file set, so routed tokens are currently minted unchecked against the
    namespace they land in. Reuse `resolve_inbox()` (`append.sh:27-45`) and `resolve_target()`
    (`append.sh:47+`) — do NOT re-derive either path.
    **Expose the collision set as a verb**: `append.sh scan-routed-tokens <target>` prints it (bare
    4-hex, one per line, sorted unique — the same output contract as the existing `scan-ids` verb,
    `append.sh:187-192`, which it mirrors). This is not decoration: the mint draws from
    `secrets.token_hex(2)`, so "mint N times and assert it never picks the seeded token" passes
    ~99.995% of the time whether or not the check exists. The verb is what makes the set
    **deterministically assertable**, and the mint must then consult that same function — do not
    compute the set twice.
  - **Acceptance**: `tests/test_inbox_write_integrity.sh` (`# roadmap:34c2`) green — RED spec written by
    the handoff, **not** by you. Do not weaken, skip, or rewrite it.
  - **Done-check**: tick this box, then `tests/run-tests.sh` fully green.
  - **Context**: `meeting/append.sh` (the only source file this item touches; `-t discoveries` /
    `-t personas` paths must be left UNCHANGED — D2 explicitly scopes validation to `inbox`).
    `relay/scripts/todo-conformance.sh` already encodes the conforming form — read it and reuse its
    definition rather than inventing a second regex (CLAUDE.md: prefer existing tooling, no NIH).
    Relates id:de36 (the lint-wiring sibling, disjoint file), id:1735, id:9fdb (inbox relocation),
    id:411d (substring-match hazard — anchor on the trailing marker, never a bare token).
  - **Honest coverage limit**: three gaps, named rather than papered over.
    (1) Validation pins the *form* of a routed line, not its *truth* — a well-formed line naming the
    wrong target repo still passes. The echo contract closes the reported-vs-written gap; it does not
    make the description accurate.
    (2) The collision-check is only tested at the *set* level (`scan-routed-tokens` returns the right
    tokens) plus a 3-mint probe. That the mint CONSULTS the set is pinned by construction — one shared
    function, asserted by the probe — not by an exhaustive proof; a mint that recomputed the set wrongly
    could still pass. Injecting the RNG would close this and is deliberately NOT in scope.
    (3) Nothing here stops a caller from ignoring stdout and echoing its own invented receipt. The echo
    contract makes truth *available*; it cannot make a caller use it. Callers are the residual LLM
    surface (CLAUDE.md mechanize-first: the loud-failure residual, named).

- [x] [ROUTINE] Conformance lint at the /meeting inbox surface <!-- id:de36 -->
  - **Why**: `todo-conformance.sh --inbox` correctly flagged the broken acc7 line as `orphan` — the sole
    non-conformer of 13 — but **nothing routine runs it**. It is reachable only via `scan-routed.sh`
    (report-only, auto-write gated per id:678e) or a manual step in the global CLAUDE.md. The detector
    existed and the defect still shipped: a loud detector whose invocation is optional is not a detector.
    Once id:34c2 lands, the write path is guarded, but legacy entries and other `RELAY_INBOX` writers
    remain unlinted.
  - **Design**: `/meeting` SKILL.md step 7b already greps the inbox for `- [ ] [<repo>]` lines and
    surfaces them. Extend that step to also run
    `relay/scripts/todo-conformance.sh --inbox "$(inbox path)"` and display any non-conforming entries
    under a distinct heading (e.g. `⚠ Inbox — non-conforming entries (todo-conformance.sh --inbox)`),
    alongside the routed items. Surface-only, consistent with step 7b's existing read-only contract —
    do NOT auto-fix, and do NOT block the meeting on a non-conformer.
  - **Acceptance**: `tests/test_meeting_inbox_lint_surface.sh` (`# roadmap:de36`) green — RED spec written
    by the handoff, not by you.
  - **Done-check**: tick this box, then `tests/run-tests.sh` fully green.
  - **Context**: `meeting/SKILL.md` step 7b (the only file this item touches — id:34c2 owns
    `meeting/append.sh`; stay out of it so the two can run concurrently).
    `relay/scripts/todo-conformance.sh` is the detector — invoke it, never reimplement it
    (`scan-routed.sh:19` already records that no-reimplementation decision).
  - **Honest coverage limit**: SKILL.md is prose the model follows, not code the harness executes, so the
    test can only assert the instruction is PRESENT and correctly formed — it cannot prove a live meeting
    obeys it. That is a real gap, not a passing grade; it is the same limit every SKILL.md step carries.

- [x] [ROUTINE] relay-doctor must detect INSTALL DRIFT (manifest -> tree), not just manifest completeness <!-- id:1102 -->
  - **Why**: `roadmap-lint.sh` sources `lib-anchored-id.sh`; the file was added to the repo 2026-07-17
    10:51 AND correctly listed in `relay_FILES`, but `make install` was never re-run — so the live tree
    had **62 of 64** declared scripts and the lint died with `No such file or directory` from the
    installed path. It cost a loderite session a broken lint plus a false "relay-machinery bug"
    diagnosis. `handback-summary.mjs` was the other drop. Already repaired in-session by
    `make install-relay`; this item is the GUARD, not the repair.
  - **The precise gap**: `relay-doctor.sh`'s existing check 4 (`reference-install completeness`,
    id:69ef, ~line 416) verifies repo -> manifest — "is every `relay/references/*.md` DECLARED?".
    It structurally cannot catch this: `lib-anchored-id.sh` WAS declared. The unchecked direction is
    **manifest -> tree** — "is every DECLARED file actually INSTALLED?". id:69ef also covers only
    `references/*.md`, never `scripts/*`. Both halves are this item.
  - **Design**: extend `relay-doctor.sh` with an install-drift check tagged `id:1102`. Reuse the
    existing `awk` manifest-join already in check 4 (do NOT write a second manifest parser — it is
    the same `relay_FILES := …` block, and `tests/test_relay_refs_install_complete.sh` uses the same
    awk; a third copy is exactly the drift this repo bans). For each manifested `scripts/*` and
    `references/*` entry, assert presence under the install root. **The install root MUST be
    injectable** (e.g. `$RELAY_INSTALL_ROOT`, defaulting to `~/.claude/skills`) — a hardcoded
    `~/.claude` is untestable, since CLAUDE.md §Testing forbids a test touching the real install tree.
  - **Mandatory carve-out**: `make status` legitimately reports `meeting-cross: SKILL.md (not
    installed)` — that alias skill is DELIBERATELY uninstalled pending deletion (id:4f5f). A drift
    check that counts it fires a false MISSING on every run and gets ignored. Make the exclusion
    explicit and on-record.
  - **Acceptance**: `tests/test_relay_install_drift_check.sh` (`# roadmap:1102`) green — RED spec
    written by the handoff, NOT by you. Do not weaken, skip, or rewrite it.
  - **Done-check**: tick this box, then `tests/run-tests.sh` fully green.
  - **Context**: `relay/scripts/relay-doctor.sh` is the ONLY source file this item touches.
    `make status` ALREADY detects this per-file (verified: it prints
    `!! scripts/lib-anchored-id.sh (not installed)` against a simulated drop) — so **do not build a
    new detector**; the item is that nothing routine INVOKES one. Same class as id:de36
    (`todo-conformance.sh` flagged the acc7 line correctly; nothing ran it) and the same rule:
    CLAUDE.md mechanize-first — *a loud detector whose invocation is optional is not a detector*.
  - **Honest coverage limit**: this makes drift DETECTABLE on a `/relay health` run; it does not make
    the tree self-heal, and nothing forces `/relay health` to run either — so the class is reduced,
    not closed. An auto-install trigger (a hook or `.path` unit) would dissolve it structurally and is
    deliberately OUT of scope here (CLAUDE.md observe-before-preventing: see whether the doctor check
    actually fires before building self-healing machinery).

<!-- 2026-07-18 handoff (relay-20260718-201041-23915-handoff). Promoted four open TODO.md
     [ROUTINE] items with no ROADMAP twin (unpromoted-scan `promote` disposition). Single-id-
     two-views: each REUSES its existing TODO `<!-- id -->` token. Four other `promote`-flagged
     ids were deliberately NOT promoted (recorded in RELAY_LOG.md 2026-07-18 handoff paragraph):
     2e6d (largely SHIPPED, residual already tracked as id:7d97 + an [INPUT — user] settings.json
     install), 659c (already has an OPEN gated ROADMAP twin above, route:decision-gate), d5e0 (a
     running open-item COUNT summary, not a task — slated for drop per id:1de1), 2d20 (executable
     part shipped; the STILL-OPEN residual is meeting-gated → id:719e with open design forks). -->
