# Roadmap <!-- fables-turn roadmap v1 -->

Executor-facing task spec. Each item is sized for ONE Sonnet session. Items are
the single source of truth — TODO.md carries only a summary line. Executors tick
checkboxes; only the reviewer adds, removes, or re-scopes items.

Read `CLAUDE.md` (§Testing, §Gotchas, §Relay contract) before starting any item.
Done-check for every item: tick the item's checkbox below, then `make test` must
be fully green (see CLAUDE.md §Testing for the expected-red semantics).

## Items

## Handoff C2 reconcile (2026-07-20, id:2dea) — un-promoted TODO backlog surfaced

> Attended `/relay handoff` on this repo. dotclaude-skills keeps its DESIGN ledger in
> TODO.md **by intent** (ROADMAP = lean executor queue). So this is a VISIBILITY reconcile,
> not a bulk promote: spec-ready executor bugs are promoted in full; decided-lane HUMAN
> items get concise pointers for `/relay human` gather visibility (TODO.md stays the prose
> SSOT); large mostly-done design entries and ambiguous/untagged backlog stay in TODO,
> never lane-guessed. See the turn summary for what was intentionally left.

### Executor-ready (promoted in full, reusing ids)

- [x] [ROUTINE] **`gather-human-backlog.sh` false-rejects a `[ROUTINE]` item that merely MENTIONS a backtick-quoted lane tag in prose** — the candidate-skip gate (`if (line !~ /\[HARD/ && line !~ /\[INPUT.../) next`) reads the RAW line, but lane-detection runs on the backtick-STRIPPED `clean` (the id:1bbd fix). So a `[ROUTINE]` item whose note contains a backtick-quoted ``[INPUT — decision]`` (e.g. id:4a46's "re-laned ``[INPUT — decision]``→``[ROUTINE]``" note) passes the raw candidate gate, then finds no lane in the stripped text → hits the untagged LOUD-reject + nonzero abort (the id:fa5c "aborts the whole scan on one bad tag" class). **Fix**: strip backticks BEFORE the candidate-skip gate (move the `gsub(/`[^`]*`/,"",clean)` above the `next`, or run the candidate check on `clean`). id:1bbd fixed lane-detection shadowing but left the candidate gate reading raw. **Acceptance**: a fixture `[ROUTINE]` item carrying a backtick-quoted `[INPUT — …]` prose mention is SKIPPED (not emitted, not rejected), and the scan exits 0. Discovered 2026-07-19 (relay human, dotclaude-skills). Relates id:fa5c, id:1bbd. — **DONE 2026-07-20 (execute+Opus-review SHIP, relay-ckpt-20260720-1317):** RED tests fail-on-base/pass-on-branch, no test weakened, suite 273/0. <!-- id:306d -->
- [x] **[ROUTINE] `roadmap-lint.sh` TAG-NOT-FIRST check anchors past leading markdown emphasis (`**`/`_`) so a bold-wrapped head lane tag no longer false-warns** (owner-ratified 2026-07-20: the originally-cited "multiple lane brackets" ERROR was already fixed by id:1781/ad8a; the live false-positive fixed here is the bold-wrapper, anchoring to the first bracket per the item's stated principle — no separate multi-bracket fixture requested) (relay human ruling 2026-07-19, from leAIrn2learn id:c3f5) — the lint false-positives with "multiple lane brackets" whenever an item's audit-trail/decision-history mentions a bracketed lane tag in prose (e.g. `[INPUT — decision]→[ROUTINE]` re-lane notes — which THIS session's own re-lanes now add). The lane-grammar check must anchor to the FIRST bracket after the checkbox (the head lane tag) and ignore later bracket mentions in the body. Owner chose the tool-level fix over de-bracketing individual items, since it protects all future items citing a lane in prose. Add a RED test with a fixture item whose body contains a bracketed lane mention. Clears leAIrn2learn c3f5 (and prevents recurrence on the yinyang id:1357 / zkWhale retag notes this session added). — **DONE 2026-07-20 (execute+Opus-review SHIP):** suite 274/0, test-integrity verified, no REVIEW_ME opened. <!-- id:be0e -->
- [x] **[ROUTINE] Pin a Makefile-tier fixture in `test_review_gate_tier_coverage.sh`** (relay human ruling 2026-07-19, follow-up to id:66d4) — the shipped `relay/scripts/review-gate.sh` already enumerates Makefile `test`-named targets alongside package.json `scripts`, but its RED spec `tests/test_review_gate_tier_coverage.sh` only proves the package.json+node_modules path, leaving the Makefile-tier code path unspecced. Add a fixture case: a repo whose declared tiers come from a `Makefile` (e.g. a `test:` / `test-e2e:` target), asserting the gate refuses when the entry omits a Makefile-declared tier and accepts when it covers it. Keep the existing package.json cases. Owner ruled the first cut needs both tier sources proven, not just one. — **DONE 2026-07-20 (execute+Opus-review SHIP):** suite 274/0, test-integrity verified, no REVIEW_ME opened. <!-- id:050b -->
- [x] [ROUTINE] **Shared anchored-extraction helper + test** (relay human 2026-07-19, resolves REVIEW_ME id:521f/1312) — one anchored id/token extraction helper replacing the 4th-instance family of hand-rolled copies: roadmap-lint's first-match `id_re`, unpromoted-scan's bare `grep -qF`, `inbox-done`'s substring match, md-merge's fail-open append (id:1b1a). `relay/scripts/scan-routed.sh` already anchors correctly — model it. The id:2c94 duplication linter would flag the copies mechanically. — **DONE 2026-07-20 (execute[opus]+review SHIP):** shared shape-B anchored primitives shipped in lib-anchored-id.sh + test_lib_anchored_token.sh (14 assertions), suite 275/0; caller migration deferred to id:3743. <!-- id:3add -->

### Pool-executable [HARD] — decided, needs per-item RED spec (route to handoff)

- [ ] [HARD — pool] `/relay . --parallel N` — 🚧 @container DECOMPOSED 2026-07-20 (handoff relay-20260720-144400-4669) — TRACKING LINE ONLY, work the children: verifiable id:5367 (disjoint-path greenlight) + id:2062 (serial one-writer integrator) below; live-only residue id:7fae. Tick this parent only when all three children are closed. Full context TODO.md. <!-- gated-on:0534 --> <!-- id:ebbe -->
- [ ] [HARD — pool] `/relay . --drain` — 🚧 @container DECOMPOSED 2026-07-20 (handoff relay-20260720-144400-4669) — TRACKING LINE ONLY, work the children: verifiable id:cd7a (driver core) → id:f9d2/838d/dd1e (heartbeat/quota/events wiring) + id:864e (front-door reversal doc); live-only residue id:23ff. Tick this parent only when all six children are closed. Full context TODO.md (guard-parity list). <!-- id:93fe -->

#### id:ebbe/93fe decomposition (2026-07-20 handoff): worktree-verifiable children

- [x] [ROUTINE] **Mechanical disjoint-path greenlight — `relay/scripts/disjoint-greenlight.sh` (D4)** <!-- children-of:ebbe -->— DONE 2026-07-20 (execute[sonnet]+review SHIP): disjoint-greenlight.sh (plan+merge-check) passes test_disjoint_greenlight.sh, suite 279/0. <!-- id:5367 --> — pure fail-closed set logic, no pool needed. `plan`: TSV on stdin (one candidate unit per line, `<id>\t<comma-joined declared paths>`) → prints exactly `concurrent` (≥2 units, every set non-empty, pairwise disjoint) or `serial` (anything else — empty/undeclared set, overlap, or a single unit); malformed input → nonzero + ERROR on stderr. `merge-check --touched <file> --merged <file>`: newline path lists → exit 0 disjoint / exit 1 + the intersecting paths on stdout (the handback evidence; never auto-resolve).
  - **Acceptance / done-check**: tick this box, then `make test` green — `tests/test_disjoint_greenlight.sh` (`# roadmap:5367`) goes EXPECTED-RED→PASS (7 cases incl. fail-closed empty-set and merge-time intersection).
  - **Context**: meeting `docs/meeting-notes/2026-07-19-2035-relay-drain-parallel-contract.md` D4; consumed by id:2062 (merge-time re-enforcement) and the id:7fae live fan-out. TODO parent id:ebbe.
- [x] [HARD — pool] **Off-Workflow drain-driver CORE — `relay/scripts/drain-driver.mjs` loop + stop predicate** <!-- children-of:93fe -->— DONE 2026-07-20 (execute[opus]+review SHIP): drain-driver.mjs core loop+stop contract passes test_drain_driver_stop.sh (live wiring = residue id:23ff). <!-- id:cd7a --> — a HOST node script (NOT Workflow-sandbox JS): `node drain-driver.mjs --repo <dir> [--max-rounds N]`. Once per round it runs the `DRAIN_ROUND_CMD` env seam (default = the real classify→dispatch→integrate round; hermetic tests stub it with scripted `{actionable,produced,substantive,surfaced}` JSON), classifies the result via a DIRECT `import` of `drain.mjs` (guard-parity id:d58f — host node CAN import; never re-derive isDryRound/isBlockedRound), and stops on: 2 consecutive non-substantive rounds all-dry → exit 0 reason=drained; 2 consecutive non-substantive with any blocked → exit 2 reason=blocked (the 2026-07-17 drained-while-blocked guard); `--max-rounds` seatbelt → exit 3. Final stdout line machine-readable: `DRAIN_STOP reason=<r> rounds=<n>`.
  - **Why HARD — pool**: the skeleton fixes the driver architecture the wiring children (id:f9d2/838d/dd1e) hang off; interface judgment beyond a mechanical apply.
  - **Acceptance / done-check**: tick this box, then `make test` green — `tests/test_drain_driver_stop.sh` (`# roadmap:cd7a`) EXPECTED-RED→PASS.
  - **Context**: TODO id:93fe (guard-parity requirement), meeting 2026-07-19-2035 D2 + Amendment, `relay/scripts/drain.mjs`.
- [x] [ROUTINE] **drain-driver run-heartbeat wiring (id:e149 parity)** (BLOCKED on id:cd7a — driver skeleton first) <!-- children-of:93fe --><!-- gated-on:cd7a -->— DONE 2026-07-20 (execute[opus]+review SHIP): drain-driver heartbeat wiring passes test_drain_driver_heartbeat.sh (spec hermeticity gap → id:5eb8). <!-- id:f9d2 --> — the driver mints a runId matching the watchdog namespace glob (`relay-drain-<ts>-<pid>` — MUST match `relay-*`, the `--prefix` the watchdog/reap consumers scope by), calls `heartbeat.sh beat` before round 1 and once per round, `heartbeat.sh stop` on every clean exit; crash detection itself stays heartbeat.sh's already-tested TTL contract.
  - **Acceptance**: `tests/test_drain_driver_heartbeat.sh` (`# roadmap:f9d2`) EXPECTED-RED→PASS (marker live during every round; archived to heartbeats.done on clean exit; runId namespace).
- [x] [ROUTINE] **drain-driver quota gate + agent seatbelt** (BLOCKED on id:cd7a) <!-- children-of:93fe --><!-- gated-on:cd7a -->— DONE 2026-07-20 (execute[opus]+review SHIP): drain-driver quota gate + seatbelt passes test_drain_driver_quota.sh 10/10. <!-- id:838d --> — `DRAIN_QUOTA_CMD` env seam defaulting to `relay/scripts/quota-stop.sh`; the gate runs BEFORE EVERY round (including the first) and a refused round is NEVER dispatched; gate exit 1/2/3 map to driver exit 4 with distinct `DRAIN_STOP` reasons `quota-stop` / `quota-cache-unreadable` / `quota-extrapolated-stop`; the driver feeds cumulative `--agents <total>` (accumulated from the round-result JSON's optional `agents` field) + `--wall <elapsed-s>` so quota-stop.sh's 200-agent/7200-s seatbelt engages on a long drain.
  - **Acceptance**: `tests/test_drain_driver_quota.sh` (`# roadmap:838d`) EXPECTED-RED→PASS.
- [x] [ROUTINE] **drain-driver event-line emission (id:c8b6 parity)** (BLOCKED on id:cd7a) <!-- children-of:93fe --><!-- gated-on:cd7a -->— DONE 2026-07-20 (execute[opus]+review SHIP): drain-driver event-line emission passes test_drain_driver_events.sh (spec hermeticity gap → id:5eb8). <!-- id:dd1e --> — append-only JSONL to `$RELAY_EVENTS_PATH` (never truncate the pool's shared feed): a `round-start` event per round + a final `drain-stop` event carrying the stop reason; every line valid JSON bearing `ts` + `runId` (relay-* namespace).
  - **Acceptance**: `tests/test_drain_driver_events.sh` (`# roadmap:dd1e`) EXPECTED-RED→PASS.
- [x] [HARD — pool] **One-writer-to-main serial integrator — `relay/scripts/drain-integrate.sh` (D5)** (BLOCKED on id:5367 — reuses its merge-check) <!-- children-of:ebbe --><!-- gated-on:5367 -->— DONE 2026-07-20 (execute[opus]+review SHIP): drain-integrate.sh (D5 one-writer serial integrator, exit 0/4/5, no force flags) passes test_drain_serial_integrator.sh 13/13, suite 283/0. <!-- id:2062 --> — the single driver merges each executor branch `--no-ff` SERIALLY into main and ticks checkboxes itself; executors never write main. `drain-integrate.sh --repo <main-checkout> --branch <br> --merged-so-far <file>`: merge-time D4 re-enforcement first (branch touched-paths ∩ merged-so-far → exit 4 handback, NO merge attempted, overlapping paths on stdout, branch left intact); textual merge conflict → `git merge --abort`, exit 5 handback, clean tree; success → exit 0 + the branch's touched paths APPENDED to the merged-so-far file. NO force/destructive git flags anywhere (asserted by the spec).
  - **Acceptance / done-check**: tick this box, then `make test` green — `tests/test_drain_serial_integrator.sh` (`# roadmap:2062`) EXPECTED-RED→PASS (real-git fixture: two disjoint branches land, overlap hands back with main unmoved, conflict aborts clean).
  - **Context**: meeting 2026-07-19-2035 D5 (one-writer-to-main) + D4 (merge-time re-enforcement); sibling pattern id:5a39. TODO parent id:ebbe.
- [x] [ROUTINE] **Front-door reversal doc: bare `/relay .` = the off-Workflow drain** <!-- children-of:93fe -->— DONE 2026-07-20 (execute[sonnet]+review SHIP): SKILL.md documents bare /relay .=off-Workflow drain, passes test_relay_dot_offworkflow_doc.sh. <!-- id:864e --> — `relay/SKILL.md` documents the owner-ratified reversal (2026-07-19 Amendment, supersedes id:7633 acceptance #4): a bare `/relay .` runs the lean off-Workflow drain via drain-driver (no Workflow prelude/discovery agents), and says so where the invocation table resolves `.`; the Phase-1 `--drain` alias rows and `tests/test_relay_drain_flag.sh` stay intact.
  - **Acceptance**: `tests/test_relay_dot_offworkflow_doc.sh` (`# roadmap:864e`) EXPECTED-RED→PASS; `tests/test_relay_drain_flag.sh` stays green.

#### id:ebbe/93fe decomposition: sandbox/live-only residue — NEVER auto-execute from a worktree

- [ ] [HARD — pool] 🚧 sandbox/live-verify-only — **end-to-end off-Workflow drain on a live repo** (id:93fe residue) <!-- children-of:93fe --><!-- gated-on:cd7a --><!-- id:23ff --> — why not worktree-verifiable: the real `DRAIN_ROUND_CMD` dispatches LIVE model agents (auto-spend — forbidden in hermetic tests) against a real repo, real quota cache and real integrator; every hermetic child (cd7a/f9d2/838d/dd1e) stubs that seam BY DESIGN. Verify by ONE supervised live drain run after the children land; record the run in RELAY_LOG.md, then tick.
- [ ] [HARD — pool] 🚧 sandbox/live-verify-only — **parallel fan-out N>1 live behaviour** (id:ebbe residue) <!-- children-of:ebbe --><!-- gated-on:2062 --><!-- id:7fae --> — why not worktree-verifiable: real CONCURRENT executor agents in sibling worktrees (scheduling, contention, lease + heartbeat + watchdog interplay under load) cannot be reproduced hermetically — the tests prove only the plan/merge logic (id:5367/2062). Verify by ONE supervised live `--parallel 2` round on declared-disjoint units after 5367+cd7a+2062 land; record in RELAY_LOG.md, then tick.

### 2026-07-20 promoted (meeting 2026-07-20-1918: lease scope, executor readiness, bump gate; + id:3743)

<!-- 2026-07-20 handoff C2 (run relay-handoff-ebd81aaf, supervised): promoted the three
     owner-ratified 2026-07-20-1918 meeting items — single-id-two-views (D2): 0ee1/65f5/8089
     REUSE their TODO.md twins (routed:4361/1c08a/1c08b) — plus id:3743 (promote-disposition,
     reuses its TODO twin) and re-laned id:dc5b in place (spec authored per its 2026-07-19
     "next handoff specs it" routing). RED specs authored this handoff (C3):
     tests/test_meeting_advisory_claim_scope.sh (0ee1), tests/test_classifier_not_ready.sh
     (65f5), tests/test_owner_accept_bump_gate.sh (8089),
     tests/test_round_plan_one_unit_per_repo.sh (dc5b),
     tests/test_anchored_caller_migration.sh (3743). NOT promoted (promote-disposition,
     documented): 2e6d (@container, shipped; residue = INPUT-user hook install + queued 7d97),
     d5e0 (status-summary prose, folds into id:1de1), 2d20 (decision-gated, meeting id:719e),
     df87 (evidence-gated: its pre-registered warn-mode FP-rate trigger has not fired). -->

- [x] [ROUTINE] **meeting↔executor lease scope fix (branch b): distinct advisory key `meeting:<repo>` + mandatory `--repo`, WARN-and-proceed** (owner-ratified D1 branch b, meeting `docs/meeting-notes/2026-07-20-1918-relay-lease-scope-executor-readiness-bump-gate.md`) <!-- routed:4361 --> <!-- id:0ee1 --> — `claim.sh acquire` is mode-blind, so `/meeting`'s setup claim on the repo key hard-refuses a parallel executor's `acquire <repo> --mode execute`, violating claim.sh's own SCOPE INVARIANT (the hard lease guards code/worktree integration ONLY; a meeting is ledger-only/advisory). Three bounded changes, no new machinery: (1) `meeting/SKILL.md` step 2-setup-claim acquires AND releases on the DISTINCT key `meeting:<root-basename>` and passes `--repo <root-basename>` (without `--repo` the advisory claim is invisible to every repo-field matcher, e.g. `relay-loop.js:909`'s live-repo set — the Fable-found gap); (2) `relay/scripts/claim.sh`: a SUCCESSFUL hard-lease `acquire <key>` while a `meeting:<key>` advisory claim is LIVE prints a WARN to stderr naming the advisory holder and still exits 0 (a manual executor drain WARNs-and-proceeds, never refused); (3) the SCOPE INVARIANT header block records the pool→meeting dispatch-time skip as ASPIRATIONAL — gated on id:9000 (bilateral advisory honor, owner-held observe-first), possibly dissolved by id:5a39 — do NOT build the dispatch-time honor point. The two-real-executors-refuse-each-other invariant is UNCHANGED. — **DONE 2026-07-20 (execute+review SHIP):** `claim.sh acquire` WARNs-and-proceeds (exit 0) on the hard-lease key when a live `meeting:<key>` advisory is held (never refuses); `meeting/SKILL.md` acquires/releases `meeting:<repo>` + `--repo`; two-real-executors-on-`<repo>`-refuse invariant PRESERVED; pool→meeting skip recorded doc-only/aspirational (gated id:9000/5a39, NOT built). `test_meeting_advisory_claim_scope.sh` green, suite 289/0.
  - **Acceptance**: (a) after the meeting-style advisory acquire (distinct key + `--repo`), the repo appears in `claim.sh peek`'s repo-set; (b) a concurrent `acquire <repo> --mode execute` from a different run SUCCEEDS while the meeting advisory claim is live, WARNing on stderr; (c) a second `--mode execute` acquire on the held key is still REFUSED.
  - **Tests**: `tests/test_meeting_advisory_claim_scope.sh` (`# roadmap:0ee1`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_meeting_advisory_claim_scope.sh` then tick + full `make test` green; `tests/test_meeting_setup_claim.sh`, `tests/test_meeting_claim_hold.sh`, `tests/test_relay_claim.sh`, `tests/test_relay_claim_liveness.sh` must stay green (the new recipe still carries `--mode meeting`, so their greps remain satisfied — never weaken their refusal cases).
  - **Context**: `relay/scripts/claim.sh` (SCOPE INVARIANT lines 11–26; acquire 173–227), `meeting/SKILL.md` step 2-setup-claim, TODO twin id:0ee1 (routed:4361). Relates id:9000, id:5a39, id:c144, id:179e.

- [x] [HARD — pool] **Classifier not-executor-ready hybrid — all three classes (`@owner-verify` / typed `gated-on:` via the id:46f6 engine / SURFACED→handoff)** (owner-ratified D2, meeting `docs/meeting-notes/2026-07-20-1918-relay-lease-scope-executor-readiness-bump-gate.md`) <!-- routed:1c08 --> <!-- id:65f5 --> — `classify-repo.sh` over-counts `actionable_routine_open`, so `classify-verdict.sh` routes `execute` for items that are not executor-ready (loderite drain 2026-07-20: owner-on-device-pending, spike-gated, spec-less all leaked through). Mechanize ONLY the structured signals; never a prose substring read (the id:4da4/0d58 trap): (1) **`@owner-verify`** joins the conservative `is_human`-style exclusion in `classify-repo.sh` (excluded from `actionable_routine_open`), and every such exclusion emits a LOUD why-not-ready line on stderr naming the item id + marker — never a silent suppression; (2) **typed `<!-- gated-on:XXXX -->`** (form-C sibling comment, CSV multi-token — the id:46f6 grammar) blocks an item IFF any target id's checkbox is still OPEN, resolved over the repo's `ROADMAP.md` ∪ `TODO.md` (∪ `TODO.archive.md`); a DONE/`[x]` target does NOT block (today's live ROADMAP carries `gated-on:` on done targets — an unconditional read would block forever); a dangling/unresolvable target does NOT block but is LOUD on stderr naming the token. REUSE the id:46f6 typed-edge engine semantics (`meeting/orphan-scan.sh` — factor a shared resolver or mirror its anchored marker regexes verbatim), never re-derive edge resolution ad hoc in the line loop; (3) **`⚠ SURFACED`** status (no RED spec) on an open executor-lane item excludes it from `actionable_routine_open` and routes the repo to verdict `handoff` (author the spec), never `execute` — e.g. a `surfaced_no_spec` count folded into `classify-verdict.sh`'s handoff branch. The class-3 signal keys on the SURFACED status marker per-repo-convention — do NOT build a tests-dir `# roadmap:` scan that assumes that convention exists in every repo. (4) document `@owner-verify` / `@owner-accepted` / `@manual` side-by-side in `relay/references/hard-lanes.md` (what each marks; which excludes from `actionable_routine_open`; un-normalized on-device smells get normalized to `@owner-verify` at the source — doc guidance, not fuzzy detection). — **DONE 2026-07-20 (execute+review SHIP):** 3-class hybrid (`@owner-verify` excluded from actionable_routine_open / typed `gated-on:` via the SHARED id:46f6 engine — blocks ONLY OPEN targets, DONE/dangling do not block / SURFACED→handoff verdict); extracted shared `relay/scripts/lib-typed-edges.sh` + `resolve-gates.sh`, `meeting/orphan-scan.sh` refactored to consume it (behaviour-preserving, `test_orphan_scan_edges.sh` green). `test_classifier_not_ready.sh` green, suite 289/0.
  - **Why HARD — pool**: dispatch-classifier semantics across two scripts + the shared edge-resolver reuse; wrong direction silently over- or under-dispatches the whole fleet.
  - **Acceptance**: all three classes flip verdicts exactly per the marker-present/absent control pairs; exclusions and dangling edges are loud on stderr; the classifier's existing verdicts are unchanged for marker-free repos.
  - **Tests**: `tests/test_classifier_not_ready.sh` (`# roadmap:65f5`) (currently RED — 11 assertions incl. controls)
  - **Done-check**: `tests/run-tests.sh tests/test_classifier_not_ready.sh` then tick + full `make test` green; `tests/test_classify_repo.sh`, `tests/test_classify_verdict.sh`, `tests/test_wire_grammar_classify.sh`, `tests/test_classify_repo_gated_section.sh` must stay green.
  - **Context**: `relay/scripts/classify-repo.sh` (:80–160 derivation loop), `relay/scripts/classify-verdict.sh` (D3 cascade), `meeting/orphan-scan.sh` (id:46f6 engine: local_state map + gated_csv parse), `relay/references/hard-lanes.md`. TODO twin id:65f5 (routed:1c08a). Relates id:46f6, id:4da4, id:ac7f.

- [x] [ROUTINE] **User-visible-close + bump gate: fail-closed `@owner-accepted` marker, contract v10 provenance, §2b entrypoint judgment check** (owner-ratified D3, meeting `docs/meeting-notes/2026-07-20-1918-relay-lease-scope-executor-readiness-bump-gate.md`; BUILDABLE-NOW parts only) <!-- routed:1c08 --> <!-- id:8089 --> — a `@manual`-acceptance item was bump-closed on a "driver's directive" → premature version bump. (3a) `relay/references/review.md` gains the FAIL-CLOSED gate: a user-visible/`@manual`-acceptance item cannot be counted in the user-observable-close set feeding the id:e647 bump without an explicit greppable `@owner-accepted:YYYY-MM-DD` marker; absent → the item stays OPEN, is EXCLUDED from that close set (item-scoped — NOT a repo-wide bump block), and gets a REVIEW_ME "needs owner-accept" box; a driver's directive is insufficient (delegated verdicts never self-settle). (3a-provenance) the marker is spoofable by the incident's own actor, so `relay/references/executor-contract.md` FORBIDS executors/drain sessions writing `@owner-accepted` — a contract-surface change: bump the marker v9→**v10** and refresh this repo's `CLAUDE.md` `## Relay contract` pointer to v10 in the same change; review.md §2b gains a gaming-check "was `@owner-accepted` introduced inside the reviewed diff by executor commits? → flag + reopen" (same forcing-function shape as the §2b.6 `refactor:` check). (3b) review.md §2b gains the reviewer JUDGMENT cross-check "does the app's REAL entrypoint (not a dev harness) call the new path?" — grep-assisted, loud, explicitly NOT a mechanical pass/fail (grep is unreliable through indirection). **GATED SEAM, NOT this item**: the 3a git-hook enforcement is a PLUGIN into the shared id:7a05/id:077d framework (reconcile-before-greenfield), built only when 077d ships — reuse this item's marker grammar there. — **DONE 2026-07-20 (execute+review SHIP):** `review.md` §5c fail-closed `@owner-accepted` gate (ITEM-scoped exclusion, NOT a repo-wide bump block) + §2b.7/2b.8 checks; `executor-contract.md` v9→**v10** forbids executor/drain writing `@owner-accepted`; `CLAUDE.md` `## Relay contract` pointer → v10 (no stale `contract v9` pointer remains). `test_owner_accept_bump_gate.sh` green, suite 289/0.
  - **Acceptance**: the four surfaces carry the gate/provenance/judgment text; the executor-contract marker and the CLAUDE.md pointer both read v10 and agree.
  - **Tests**: `tests/test_owner_accept_bump_gate.sh` (`# roadmap:8089`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_owner_accept_bump_gate.sh` then tick + full `make test` green; `tests/test_meeting_c1_executor_contract.sh` and the review-doc tests must stay green. NOTE: other managed repos' CLAUDE.md pointers go stale at v10 — that fleet refresh is review-mode step 4's existing auto-refresh job, NOT this item's.
  - **Context**: `relay/references/review.md` (§2b judgment-residue list; place the 3a gate with the §5 close discipline or its own subsection), `relay/references/executor-contract.md` (marker line + Maintenance section), `CLAUDE.md` `## Relay contract`. TODO twin id:8089 (routed:1c08b). Relates id:e647, id:b8fa, id:7a05, id:077d.

- [x] [ROUTINE] **Migrate the hand-rolled anchored-token extraction callers onto `lib-anchored-id.sh` shape-B primitives** (id:3add follow-up) <!-- id:3743 --> — HIGHEST VALUE first: `meeting/append.sh` `inbox-done`'s twin check is still a bare `grep -qsF "routed:$token"` — a real anchoring bug against a DESTRUCTIVE store (substring false-twin deletes an inbox line whose durable twin never landed; an anchored `<!-- id:XXXX -->` adoption is missed so resolved lines linger). Migrate it onto `token_marker_in_files` (`(routed|id):$tok` + trailing token boundary — scan-routed.sh's shipped twin semantics). Then the remaining family callers, per-caller and behavior-preserving: `unpromoted-scan.sh`'s inline grep (PRESERVE the id:798d relaxed end-anchor + id:1312 prose-non-match — their tests must stay green), `roadmap-lint.sh` (already on shape-A — verify, no change expected), `meeting/md-merge.py` (Python heredoc cannot source the bash lib — add a minimal Python-side twin of the anchored regexes OR a subprocess shim, executor's pick; the id:1b1a fail-open APPEND policy is OUT OF SCOPE — only the matching primitive migrates). — **DONE 2026-07-20 (execute+review SHIP):** `meeting/append.sh` inbox-done twin-check migrated onto `lib-anchored-id.sh` `token_marker_in_files` (anchored `(routed|id):$tok`, fixes substring false-twin against the DESTRUCTIVE inbox store); other append.sh callers behaviour-preserving (inbox write-integrity test green). `test_anchored_caller_migration.sh` green, suite 289/0.
  - **Acceptance**: inbox-done refuses a substring false-twin and accepts an anchored id-marker twin; INBOUND-stub and no-twin behaviors unchanged; append.sh uses the shared primitive.
  - **Tests**: `tests/test_anchored_caller_migration.sh` (`# roadmap:3743`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_anchored_caller_migration.sh` then tick + full `make test` green; `tests/test_inbox_done_twin_guard.sh`, `tests/test_inbox_done_anchor.sh`, `tests/test_lib_anchored_token.sh`, `tests/test_unpromoted_scan_gated_twin.sh`, `tests/test_unpromoted_scan_anchoring.sh`, `tests/test_roadmap_lint_id_anchoring.sh` must stay green.
  - **Context**: `meeting/append.sh` (inbox-done twin check ~:160), `relay/scripts/lib-anchored-id.sh` (shape-B primitives + header caller inventory), `meeting/md-merge.py`, `relay/scripts/unpromoted-scan.sh` (:~269). TODO twin id:3743.

### 2026-07-21 promoted (relay --drain round 2 handoff)

- [x] **[SUPERSEDED 2026-07-21 — consolidate; apex-drain retired, built-but-moot]** [ROUTINE] **Cron-safety guard for the apex-drain entry — `relay/scripts/drain-cron-guard.sh`** (meeting 2026-07-21-0911 D6; enforce-not-document) <!-- children-of:2b23 --> <!-- id:23d8 --> — a small guard the apex-drain entry calls FIRST: refuse to start when stdin is not a terminal (`! test -t 0`) unless an explicit override (`--allow-cron` flag or `DRAIN_ALLOW_CRON=1` env) is passed. Refusal is LOUD (nonzero exit + stderr naming the override); an interactive tty, or a non-tty WITH override, proceeds. Keeps a stray cron/at invocation of the supervised apex drain from running blind.
  - **Acceptance / done-check**: tick this box, then `make test` green — `tests/test_drain_cron_guard.sh` (`# roadmap:23d8`) EXPECTED-RED→PASS (non-tty-no-override refuses loudly; `--allow-cron` and `DRAIN_ALLOW_CRON=1` proceed; a real-pty tty proceeds).
  - **Context**: TODO id:23d8 (children-of:2b23 apex-TaskList driver); style precedent `relay/scripts/host-gate.sh` (`! -t 0` stdin handling).
- [x] [ROUTINE] **Old-vocab lane-tag ratchet pre-commit hook — `hooks/pre-commit-lane-vocab.sh`** (owner chose HARD-DENY) <!-- id:9ef7 --> — block a commit whose `git diff --cached` ADDED lines introduce an old-vocab lane tag (`[HARD — pool|meeting|hands|decision gate]`) → exit nonzero naming the new-vocab replacement (lane-convert.sh mapping: pool→`[HARD]`, meeting→`[INPUT — meeting]`, decision gate→`[INPUT — decision]`, hands→name candidates). Existing old-vocab in context/unchanged lines WARN only (grandfathered). Tag-vs-prose classification MUST reuse the id:4da4-anchored parser / `roadmap-lint.sh` tag detection (NOT a fresh grep — id:0d58 false-positive class): a backtick-quoted lane mention in an added prose line must NOT block. Self-gated to relay-onboarded repos via `relay/scripts/lib-own-repos.sh` (honors `# path:`; env `LANE_VOCAB_RELAY_TOML` / `LANE_VOCAB_ALL_REPOS`, mirroring the privacy gate). Global install via `make install-lane-ratchet` (core.hooksPath, reusing the privacy gate's don't-overwrite-a-foreign-hooksPath guard + a CLAUDE.md rule append). `git commit --no-verify` is the escape hatch.
  - **Acceptance / done-check**: tick this box, then `make test` green — `tests/test_lane_vocab_ratchet_hook.sh` (`# roadmap:9ef7`) EXPECTED-RED→PASS (added old-vocab blocks + names replacement; new-vocab allowed; context-line old-vocab grandfathered; backtick-prose exempt; non-own repo no-op; `make install-lane-ratchet` exists).
  - **Context**: TODO id:9ef7; model `hooks/pre-push-privacy-gate.sh` + `tests/test_privacy_gate_prepush.sh` (same relay-scoping shape); mapping in `relay/scripts/lane-convert.sh`; complements id:7df1 (does NOT replace it).

### 2026-07-21 promoted (consolidate handoff — mechanical-hop emitter wiring, id:176f child)

- [x] [HARD — pool] **Emit relay-loop.js's proxy-eligible mechanical hops as `model:"bash"` + a ```relay-mech fence** (wiring child of id:176f; owner-ratified CONSOLIDATE, RELAY_LOG 2026-07-21 21:38) <!-- children-of:176f --> <!-- id:6176 -->
- [ ] [HARD — meeting] **HIGH PRIORITY — pool-launch proxy coupling (id:6176 made 5 hops proxy-DEPENDENT).** After id:6176, relay-loop.js emits `model:"bash"` for file-surface / quota / inject-take / heartbeat-beat / heartbeat-stop — these 404 at runtime UNLESS the mechanical-proxy is running AND `ANTHROPIC_BASE_URL` points at it (id:94b8). So running the autonomous pool (`/relay`) WITHOUT the proxy now BREAKS those hops — including **quota gating** (a 404'd quota check risks bypassing the stop → auto-spend) plus heartbeat / injection / decision-surfacing. Consolidate makes the proxy part of the loop, but the pool LAUNCH does not yet start it. **Decide + build (fail-CLOSED is the key property — never let a hop silently 404):** where/how to start the proxy + export `ANTHROPIC_BASE_URL` as part of pool launch — a preflight in the relay launcher that spawns `mechanical-proxy.py` on loopback + sets the env before the Workflow starts, and/or a health check that REFUSES to launch the pool if the proxy is unreachable. **UNTIL THIS LANDS: do not run `/relay` (autonomous pool) without the proxy up + base URL set.** Relates id:6176 / id:176f, the 2026-07-21 consolidate decision. <!-- children-of:176f --> <!-- id:6b35 --> — the `mechanical-proxy.py` short-circuit is CONFIRMED end-to-end (RELAY_LOG 2026-07-21 21:27): a Workflow `agent('```relay-mech\n<cmd>\n```', {model:"bash"})` is intercepted by the proxy, which runs `<cmd>` locally and returns its stdout with ZERO upstream inference. Convert each PROXY-ELIGIBLE mechanical hop in `relay/scripts/relay-loop.js` from `model:'haiku'` (a real Haiku inference call whose only job is to run one relay script) to `agent('```relay-mech\n<the exact relay-script command>\n```', {model:"bash", …})` — the command wrapped in a ```relay-mech fence so `_MECH_FENCE_RE` extracts it and `_command_allowed()` gates it.
  - **Scope — the 5 CONVERTIBLE hops** (each a SINGLE allowlisted-relay-script pipeline the proxy's `_command_allowed()` accepts: no heredoc, no `&&`/`;`/newline, no `$(...)`, no `>>`, no `python3`):
    | Hop label | line (as of this handoff) | command | note |
    |---|---|---|---|
    | `file-surface:${repo}` | ~1506 | `file-surface-decisions.sh '<path>'` | fire-and-forget; output logged verbatim |
    | `quota:${tier}` | ~1699 | `quota-stop.sh --tier <t> --agents <n> --wall 0` | carries `QUOTA_SCHEMA` — the consumer must parse the script's raw JSON stdout instead of a schema-typed return |
    | `inject-take` | ~2129 | `inject.sh take` | carries `INJECT_TAKE_SCHEMA` + post-processing (path-resolve / unit-shape) — that shaping must move to JS/another hop; the fence returns only `inject.sh take`'s raw stdout |
    | `heartbeat-beat` | ~2212 | `heartbeat.sh beat <runId>` | fire-and-forget |
    | `heartbeat-stop` | ~2222 | `heartbeat.sh stop <runId>` | fire-and-forget |
  - **OUT of scope — the 7 NON-eligible hops MUST STAY `model:'haiku'`** (converting them is WRONG and the test guards it): `discover-prelude` (~933, multi-command + LLM JSON assembly), the `discover-run:` classify shard (~1103, the id:7402 RESIDUAL LLM read — never mechanical), `write-relay-status` (~362, heredoc `<<` — proxy refuses redirection), `handback-followup` (~1934, `python3` leader — not an allowlisted relay script), `gaming-log` (~1967, `$(...)` + `&&` + `>>`), `release:` (~1993, `claim.sh release && heartbeat.sh beat` — two commands), `auto-reconcile-restart` (~2248, multi-command + LLM logic). Splitting a multi-command hop into single-command mechanical hops is a POSSIBLE follow-up but is NOT in this unit.
  - **Acceptance (BDD)**:
    - GIVEN `relay/scripts/relay-loop.js` WHEN it dispatches the file-surface / quota / inject-take / heartbeat-beat / heartbeat-stop hop THEN the `agent()` options carry `model:"bash"` (never `model:'haiku'`) AND the first argument contains a ```relay-mech fence whose body is exactly that hop's allowlisted relay-script command.
    - GIVEN the same file THEN the `discover-prelude` hop and the `discover-run:` classify shard STILL carry `model:'haiku'` (they are LLM hops, not proxy-eligible).
    - GIVEN a fenced command from any converted hop WHEN fed to `mechanical-proxy.py`'s `_extract_mechanical_command` + `_command_allowed` THEN it is accepted (single pinned relay pipeline) — i.e. the emitted command shape matches the proxy's contract.
    - Runtime note (NOT tested here): `model:"bash"` only short-circuits when `ANTHROPIC_BASE_URL` points at a running `mechanical-proxy.py`; that is a deploy/runtime concern (a plain-API run forwards `model:"bash"` upstream → 404). This RED test asserts the EMITTER SHAPE only.
  - **Tests**: `tests/test_relay_loop_mech_emitter.sh` (`# roadmap:6176`) — currently RED (relay-loop.js has zero ```relay-mech fences today). Static grep/parse of relay-loop.js: per-hop `model:"bash"` (not haiku), ≥5 model:"bash" dispatches, ≥1 relay-mech fence, each of the 5 commands lives inside a fence, and the 2 boundary LLM hops stay haiku.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_loop_mech_emitter.sh`, then tick the box and run full `make test` green. Also `node --check relay/scripts/relay-loop.js` (the converted template literals must still parse — escape backticks per the loop-crash-class gotcha) and re-run `tests/test_relay_loop_structure.sh` (the existing haiku-hop assertions there must not regress — e.g. the integrator stays `model:'sonnet'`, the classify shard stays `model:'haiku'`).
  - **Context**: proxy = `relay/scripts/mechanical-proxy.py` (`_command_from_wrapped`/`_command_allowed`/`ALLOWED_RELAY_SCRIPTS`); emitter = `relay/scripts/relay-loop.js`; the Workflow runtime FORBIDS `new Date()`/`process.*`/`require()`/`fs` (id:2026-06-15 crash class) — a mechanical fence is a plain template-literal string, so it is safe. TODO parent id:176f; RELAY_LOG 2026-07-21 (probe id:94b8 confirmation + 21:27 end-to-end + 21:38 consolidate ratification).

### Human-triage backlog — decided lane, TODO.md is SSOT (pointers for /relay human)

- [ ] [INPUT — meeting] Use VISIBLE annotations, not HTML comments, for metadata that should render — see TODO.md <!-- id:ee62 -->
- [ ] [INPUT — meeting] Mechanize the keystone-unblock triage as a `/relay human` view (gate-graph fan-out ranking) (us… — see TODO.md <!-- id:c3f6 -->
- [x] [INPUT — meeting] ONE meeting: "who may write the shared thing, and when" — MEETING HELD 2026-07-21 (docs/meeting-notes/2026-07-21-1518-who-may-write-realremotes-uid-scoping.md); d03d pilot ratified → id:ca9e — see TODO.md <!-- id:fa1d -->
- [ ] [HARD — meeting] Fake-Haiku mechanical-dispatch proxy — see TODO.md <!-- id:176f -->
- [x] **[SUPERSEDED 2026-07-21 — consolidate; `claude -p` orchestrator substrate parked]** ~~[INPUT — meeting]~~ Orchestrator-launched host `claude -p` on the local proxy gateway as the off-Workflow dispatch… — see TODO.md <!-- id:b3cc -->
- [ ] [INPUT — meeting] Meeting-as-relay-producer: route `/meeting` ledger writes through a worktree the integrator mer… — see TODO.md <!-- id:5a39 -->
- [ ] [INPUT — meeting] Full-loop relay REPLAY test — see TODO.md <!-- id:5bac -->
- [ ] [INPUT — meeting] Integrator destructive-cleanup ordering: under-the-lease vs release-first (proposed by the 2026… — see TODO.md <!-- id:6613 -->
- [ ] [INPUT — access] Post-Fable transition (after 2026-07-07) (user 2026-07-01): when the Fable window closes — see TODO.md <!-- id:77f3 -->
- [ ] [INPUT — meeting] Human-action dashboard, mechanically refreshed by the relay loop, launchable WITHOUT LLM access… — see TODO.md <!-- id:51d8 -->
- [ ] [INPUT — meeting] chidiai⇄relay calibration cross-pollination (scoping) — see TODO.md <!-- id:2653 -->
- [ ] [INPUT — meeting] 5h session-limit overshoot: quota gate is round-boundary-only, an in-flight wave blows through… — see TODO.md <!-- id:68b1 -->
- [ ] [INPUT — meeting] Capability-keyed lane taxonomy + mechanical-run daemon (meeting 2026-07-02-1924, `docs/meeting-… — see TODO.md <!-- id:4299 -->
- [ ] [INPUT — meeting] A LIVE review child's worktree + branch were swept mid-run (2026-07-01 ~22:56) while the repo's… — see TODO.md <!-- id:6e02 -->
- [ ] [INPUT — meeting] Move relay DISCOVERY off LLM-judgment onto a mechanical TDD red/green flow — see TODO.md <!-- id:4d8e -->
- [ ] [INPUT — meeting] Broker-backed PARALLEL human-decision channel for the relay-loop (reuse meeting-rpg `broker.py`… — see TODO.md <!-- id:b444 -->
- [ ] [INPUT — meeting] Continuous (streaming) dispatch — see TODO.md <!-- id:80b8 -->
- [ ] [INPUT — meeting] Inter-session communication / coordination channel — see TODO.md <!-- id:9000 -->
- [ ] [INPUT — meeting] Encode "ROUTINE requires the test to gate the REAL goal" in the executor scope guard — see TODO.md <!-- id:33c2 -->
- [ ] [INPUT — meeting] Relay broker: stop spawning one agent per mechanical shell command (WALL-TIME driver) — see TODO.md <!-- id:3a1c -->
- [ ] [INPUT — meeting] Audit `/batch` for parallel-processing applications — see TODO.md <!-- id:7b23 -->
- [ ] [HARD — meeting] `drained` machine-verdict + `@wire`/`@manual` grammar split (folds in executor-no-own-RED + spe… — see TODO.md <!-- id:af48 -->
- [ ] [HARD — meeting] Visible-half-is-primary handoff discipline <!-- gated-on:ac7f --> (meeting 2026-07-19-1058, fro… — see TODO.md <!-- id:2b49 -->
- [ ] [HARD — meeting] Ledger-invariant enforcement substrate — see TODO.md <!-- id:7a05 -->
- [ ] [HARD — meeting] Semver-bump enforcement + handoff bump-level annotation (meeting 2026-07-19-1212, user amendmen… — see TODO.md <!-- id:d1b2 -->
- [ ] [INPUT — access] Review→execute chaining within a pool (lane-tagged 2026-07-02 handoff: remaining work = OBSERVE… — see TODO.md <!-- id:b8ae -->
- [ ] [INPUT — meeting] ``/`[MEETING]` tag-taxonomy completion (user 2026-06-15) — see TODO.md <!-- id:d0da -->
- [ ] [INPUT — access] Runtime write-matrix + heartbeat round-trip test for the relay-ro/relay-svc ACLs (id:02c7) — see TODO.md <!-- id:e8a3 -->
- [ ] [INPUT — meeting] Write-scope the LLM tier by uid: separate OS users for the relay supervisor/reviewer vs. the ex… — see TODO.md <!-- id:d03d -->
- [ ] [INPUT — meeting] Custom agent types (`.claude/agents/*.md`) per relay subcommand — see TODO.md <!-- id:931c --> **[2026-07-21 — evaluate UNDER the id:cae2 Agent-SDK audit (candidate #2), not piecemeal. Scope narrowed to the JUDGMENT roles (executor/reviewer/handoff/discover-shard); the mechanical variant id:f599 is SUPERSEDED by the model:"bash" proxy (id:6176/176f). Primary value = RELIABILITY (bake "load+follow the versioned contract" into the subagent prompt so it is not a forgettable per-dispatch step), not token cost. TWO DESIGN KEYS: (1) POINT don't DUPLICATE — the subagent prompt READs `relay/references/executor-contract.md` (vN) at runtime, never copies it (else derived-doc drift vs the ratified SOP); (2) USER-LEVEL install (`~/.claude/agents/` + `make install` symlink), never project-level, because relay runs the whole relay.toml set. `tools:` frontmatter scoping is ergonomic, NOT a security boundary (deny-probe-5937 — the OS-user tier is the real containment).]**
- [ ] [INPUT — meeting] Design tier-robust gate-discipline mechanisms (for a Fable session to consider): the 2026-07-02… — see TODO.md <!-- id:abe7 -->
- [ ] [HARD — meeting] Upgrade `consumer-enum.sh` from content-grep to real import/read-edge resolution (relay human r… — see TODO.md <!-- id:494f -->
- [ ] [HARD — meeting] `/meeting --fabled` (or similar) — see TODO.md <!-- id:7e87 -->
- [ ] [INPUT — meeting] A shared "reasoning-fallacy checkup" step for `/relay` and `/meeting` (user 2026-07-17: "add TO… — see TODO.md <!-- id:0e56 -->


<!-- 2026-07-19 handoff C2 (run relay-handoff, this session): promoted the three ungated,
     handoff-ready af48/related [HARD — pool] children from TODO.md — single-id-two-views
     (D2): ac7f/78df reuse their TODO twins (children-of:af48), 66d4 reuses its TODO twin.
     RED specs authored this handoff (C3): tests/test_wire_grammar_classify.sh (ac7f),
     tests/test_review_gate_tier_coverage.sh (66d4), tests/test_consumer_enum.sh (78df).
     GATED siblings NOT promoted: bea2/2b49 (gated-on:ac7f), 0c86 (gated-on:077d),
     07dc (children-of:7a05 substrate). -->

<!-- 2026-07-19 handoff C2 (supervised, mtg-1726): promoted a17a (state-machine diagram set)
     from TODO — single-id-two-views (D2), reuses the TODO twin id:a17a. RED spec authored
     this handoff (C3): tests/test_a17a_diagram_state_sync.sh. The diagram AUTHORING (topology
     is design judgment, reconciled with the id:4da4 matrix) is the [HARD — pool] execution; the
     guard-test keeps the authored vocabulary from drifting off classify-verdict.sh + SKILL.md. -->

- [x] [HARD — pool] **Author the `/relay` + `/meeting` state-machine diagram set + drift guard-test** <!-- id:a17a --> — **DONE 2026-07-19 (relay HARD child, id:da26)**: authored the THREE Mermaid diagrams under `docs/diagrams/` per mtg-1726 D1 — (a) `ledger-lifecycle.mmd` (TODO↔ROADMAP↔REVIEW_ME↔inbox single-id-two-views; meeting-write seam annotated "pending id:5a39"; inbox routed:XXXX drain), (b) `relay-dispatch.mmd` (all THREE execution substrates — LLM Workflow pool / mechanical daemon+.timer OUTSIDE the Workflow / human — the `[MECHANICAL]` lane, the verdict classes execute→review→hard→handoff plus human/idle, the self-feeding discover→dispatch→integrate loop, quota/MAX_ROUNDS/`/relay stop` gates, and the conditional semver-vs-versionless CHANGELOG branch at integrate; reconciled with the id:4da4 pt2 matrix — relay-doctor.sh I1–I9 shown as the `/relay health` observer, report-only per D2), (c) `meeting-classification.mmd` (C1/C2/C3 → dispatch with the broker/meeting-rpg γ-branch as a conditional sub-branch; POOL/HANDS/RELAY surfaced-not-picked seam). D2 sync = the drift GUARD (not hand-sync, not full generation): `tests/test_a17a_diagram_state_sync.sh` DERIVES the authoritative verdict-set from `classify-verdict.sh` and the mode-set from `relay/SKILL.md` and fails `make test` on divergence. `tests/test_a17a_diagram_state_sync.sh` (`# roadmap:a17a`) GREEN; full suite green. Edge labels use the pipe form (`-->|"…"|`) to keep `--flag` tokens inside labels from breaking Mermaid parsing; no in-repo Mermaid renderer is installed (installing one unattended is forbidden) so rendering is by the format, the guard-test is the automated gate. Out of scope (per item): the git-diary-workflow/todo-update/discovery-shard diagrams and the 5a39 seam redraw (the guard forces the latter when it lands).
  - **Why HARD**: the diagrams' topology (states, transitions, the THREE execution substrates — LLM Workflow pool / mechanical daemon+timer OUTSIDE the Workflow / human — verdict-class flow, the conditional version/changelog integrate branch) is design judgment reconciled with the id:4da4 pt2 matrix (invariants I1–I9, `docs/meeting-notes/2026-07-01-2142-relay-state-machine-invalid-state-detector.md`), not a mechanical transform. Scope decided in `docs/meeting-notes/2026-07-19-1726-relay-meeting-state-machine-flowcharts.md` (D1/D2).
  - **Acceptance**: THREE Mermaid diagrams exist under `docs/diagrams/` — `ledger-lifecycle.mmd` (a: TODO↔ROADMAP↔REVIEW_ME↔inbox, single-id-two-views; annotate the meeting-write seam "pending id:5a39"), `relay-dispatch.mmd` (b: all three substrates + the `[MECHANICAL]` lane + verdict classes execute→review→hard→handoff + the self-feeding loop + quota/stop gates + the conditional semver-vs-versionless changelog branch at integrate), `meeting-classification.mmd` (c: C1/C2/C3 → dispatch, with the broker/meeting-rpg γ-branch as a conditional sub-branch) — AND the drift guard-test passes. Diagram (b) reconciles with the id:4da4 matrix; render them in-repo (Mermaid).
  - **Tests**: `tests/test_a17a_diagram_state_sync.sh` (`# roadmap:a17a`) (currently RED) — asserts the three files exist and that `relay-dispatch.mmd`'s declared verdict-set + relay-mode-set do not drift from the machine-readable source (`classify-verdict.sh` verdict enum, `relay/SKILL.md` invocation list), and that `meeting-classification.mmd` names C1/C2/C3 + broker. The guard DERIVES its authoritative sets from source (never hardcodes them) — this is D2's guard-not-hand-sync strategy; design it as a candidate consumer of the inflownistration/info-flow idea (id:aae4), not against it.
  - **Done-check**: author the diagrams, tick this box, then `make test` fully green (`tests/test_a17a_diagram_state_sync.sh` goes EXPECTED-RED → PASS).
  - **Context**: `docs/meeting-notes/2026-07-19-1726-relay-meeting-state-machine-flowcharts.md` (D1/D2 scope), the id:4da4 matrix note, `relay/scripts/classify-verdict.sh` (verdict enum), `relay/SKILL.md` (mode list), `relay/scripts/render-verdict.sh` (idle→drained). Out of scope this item: diagrams for git-diary-workflow/todo-update/discovery-shard (judgment per skill, later); the meeting-write-seam redraw when id:5a39 lands (the guard-test forces it). TODO twin id:a17a.

- [x] [HARD — pool] **`@wire` grammar + `classify-repo` count + `drained` render-alias** (KEYSTONE — build first; af48 child C1) <!-- children-of:af48 --><!-- id:ac7f --> — **DONE 2026-07-19 (relay HARD child, id:da26)**: (1) grammar — `@wire` documented in `relay/references/hard-lanes.md` (new "## The `@wire` marker" section: orthogonal marker recorded by the executor-verifiable-via-a-host/e2e-RED-spec property, the D3 two-linked-items split, the D1 drained=render-alias note) + a marker pointer in `templates.md`; `executor-contract.md` deliberately UNTOUCHED (`@wire` adds no new executor obligation — an executor picks a `@wire` item like any RED-spec-backed ROADMAP item — so no version bump). (2) `classify-repo.sh` — an open `@wire` item on a primary executor lane (`[ROUTINE]`/`[HARD — pool]`/`[HARD]`), not `@manual`/human-gated/blocked/exempt, now counts toward `actionable_routine_open` → the classify-verdict execute gate fires (`verdict=execute`); `@manual` stays excluded. (3) `drained` render-alias — new `relay/scripts/render-verdict.sh` (idle→"drained", every other verdict verbatim; the ONLY sanctioned emitter of the word, NO new classify-verdict enum). `tests/test_wire_grammar_classify.sh` (`# roadmap:ac7f`) GREEN; full suite 263/0. — define `@wire` as a new **orthogonal marker** (like `@manual`/`@needs-auth`, NOT a lane), recorded by the *executor-verifiable-via-a-host/e2e-RED-spec* property (NOT narrowly "UI wiring"). Three deliverables, all pinned by `tests/test_wire_grammar_classify.sh`:
  1. **Grammar docs** — `relay/references/hard-lanes.md` (+ `templates.md`, `references/executor-contract.md`) document `@wire` by its property, orthogonal to lane tags, AND the **two-linked-items split** for a two-phase feature (a `@wire` executor item + a separate `@manual` human item `gated-on:` it; split ONLY where both phases are real — D3).
  2. **`classify-repo.sh` count (D4)** — an open item carrying `@wire` on a primary executor lane (`[ROUTINE]`/`[HARD — pool]`/`[HARD]`), NOT human-gated/`@manual`/blocked/exempt-section, **counts toward `actionable_routine_open`** (today only `[ROUTINE]` does — `:131`/`:142`). `@manual` stays excluded (unchanged, the safe under-dispatch direction). Downstream consumer: `classify-verdict.sh:131` execute gate → a `@wire` item yields `verdict=execute`.
  3. **`drained` render-alias (D1)** — NO new `classify-verdict.sh` enum. A mechanical render path emits the token `"drained"` **only** as a rendering of `verdict=idle` (which, once (2) lands, already implies zero open `@wire` half) — the word is quoted from the classifier, never authored freehand. Interface authored by this handoff: a new `relay/scripts/render-verdict.sh` reading a classify-verdict JSON on stdin → prints a display label, `idle`→`drained`, every other verdict verbatim. (Interface is the spec — see REVIEW_ME judgment note.)
  - **Acceptance / done-check**: tick this box, then `make test` green — `tests/test_wire_grammar_classify.sh` (`# roadmap:ac7f`) goes from EXPECTED-RED to PASS across all three deliverables. **Consumers enumerated** (per id:78df discipline): `actionable_routine_open` is read by `classify-verdict.sh` (execute gate, `:51`/`:131`), `classify-repo.sh` `--emit unit` field (`:294`), and relay-doctor check 10 / invariant I2 — the spec covers the classify-verdict execute-gate path (the routing-determining consumer); the `--emit unit` + relay-doctor passthroughs are field re-exports of the same integer and need no separate wire logic.
  - **Context**: `relay/scripts/classify-repo.sh` (:80-144), `relay/scripts/classify-verdict.sh` (:38-135), `relay/references/hard-lanes.md`; design `docs/meeting-notes/2026-07-19-1152-drained-verdict-wire-manual-grammar.md` (D1/D3/D4). TODO twin id:ac7f.

- [x] [HARD — pool] **Tier-coverage checkpoint gate** (mechanizes `review.md §3` / id:f032) <!-- id:66d4 --> — **DONE 2026-07-19 (relay HARD child, id:da26)**: shipped `relay/scripts/review-gate.sh` (`--repo <dir> --entry <file>`). Enumerates declared test tiers (package.json `scripts` keys containing "test" — the RED-spec source — plus Makefile `test`-named targets, deduped; tier-name = key/target verbatim so `test`≠`test:e2e`) and refuses the checkpoint (nonzero + offending tier on stderr) unless the entry covers each tier with a `<tier>: <result>` line OR a `SKIPPED-TIER: <tier> — <reason>` line. Toolchain-presence probe scoped to a marker UNDER `<dir>` (populated `<dir>/node_modules`) to stay HERMETIC — global caches (`~/.cache/ms-playwright`) are deliberately NOT consulted (a home-cache probe would make the acceptance test host-dependent); the result-token/skip matchers anchor on `<tier>: `/`SKIPPED-TIER: <tier> ` (colon-space / trailing space) so a `test:e2e:` line can't falsely satisfy the bare `test` tier. `tests/test_review_gate_tier_coverage.sh` (`# roadmap:66d4`) GREEN across all four cases (a missing-tier→refuse, b all-reported→accept, c skip+toolchain-present→refuse, d skip+toolchain-absent→accept); full suite 264/0. CI-config manifest source noted as a future extension point in the script header (no tier source needs it yet). — a review-checkpoint script (`relay/scripts/review-gate.sh`) that enumerates the repo's **declared** test tiers from its own manifests (`Makefile` targets, `package.json` scripts, CI config) and **refuses the checkpoint** (nonzero exit) unless the checkpoint entry carries, per declared tier, either a **result token** (`<tier>: <N> passed` / `<tier>: <result>`) or a **`SKIPPED-TIER: <tier> — <reason>`** line. Crucially the gate **probes toolchain presence to validate a skip**: a `SKIPPED-TIER` claim is REJECTED (nonzero) if the toolchain is in fact present (e.g. `node_modules`/`~/.cache/ms-playwright` populated for an e2e tier) — a judgment excuse ("doc-only window") must NOT satisfy it. Because it is a script, subagents running it are bound automatically (a filed chidiai case does not propagate to subagents; only a gate does).
  - **Interface authored by this handoff** (the spec): `review-gate.sh --repo <dir> --entry <file>` — reads declared tiers from `<dir>`'s manifests, checks `<file>` (the checkpoint entry text) covers each; exit 0 = all tiers accounted, nonzero + the offending tier on stderr = refuse. Toolchain-presence probe is per-tier (a tier maps to a presence marker under `<dir>`).
  - **Acceptance / done-check**: tick this box, then `make test` green — `tests/test_review_gate_tier_coverage.sh` (`# roadmap:66d4`) PASS: (a) missing-tier entry → refuse; (b) all-tiers-reported entry → accept; (c) `SKIPPED-TIER` with toolchain PRESENT → refuse; (d) `SKIPPED-TIER` with toolchain ABSENT → accept.
  - **Context**: `relay/references/review.md §3`, `relay/scripts/ckpt-tag.sh` (candidate co-host), id:f032 (the fully-specified-but-LLM-trusted rule). TODO twin id:66d4.

- [x] [HARD — pool] **Spec-completeness handoff consumer-enumeration aid** (af48 child C4) <!-- children-of:af48 --><!-- id:78df --> — **DONE 2026-07-19 (relay HARD child, id:da26)**: shipped `relay/scripts/consumer-enum.sh <artifact> [root]` — `grep -rlF --exclude-dir=.git` over `[root]` (default `git rev-parse --show-toplevel`), one absolute path per line, `sort -u`. LISTING AID not gate: `|| true` on the empty-match path so a nonexistent/unreferenced artifact lists nothing and STILL exits 0; the artifact's own definition file (basename match `/​<artifact>`) is excluded (a file reads an artifact, not itself). `tests/test_consumer_enum.sh` (`# roadmap:78df`) GREEN across both cases (3 readers of edges.json listed, .git + non-reader excluded; nonexistent artifact → empty + exit 0); full suite green. — a handoff-time listing aid `relay/scripts/consumer-enum.sh <artifact> [root]` that lists every file referencing/reading `<artifact>` (the readers of the artifact a RED spec governs), so a handoff author cannot silently miss a consumer. **A listing aid, not a gate** — it surfaces readers (exit 0, one path per line), it does NOT mechanically prove coverage. Pairs with the discipline (documented in `references/handoff.md`) that a RED spec **names the consumers it covers**.
  - **Acceptance / done-check**: tick this box, then `make test` green — `tests/test_consumer_enum.sh` (`# roadmap:78df`) PASS: given a fixture tree where an artifact is read by N files, the aid lists all N (and excludes the artifact's own definition file / non-readers); a nonexistent artifact lists nothing and still exits 0 (aid, not gate).
  - **Context**: `references/handoff.md` (C3 spec discipline), chidiai `red-spec-verified-named-consumers`. TODO twin id:78df.

<!-- 2026-07-19 handoff C2 (run relay-20260719-132549-15264): promoted the sole `promote`-
     disposition TODO item (unpromoted-scan: 1 promote / 75 surface / 4 laned). The three
     af48 children ac7f/66d4/78df were promoted+executed earlier THIS session (already [x]).
     Single-id-two-views (D2): id:798d reuses its open TODO.md twin (INBOUND routed:8911 from
     zkWhale). RED spec authored this handoff (C3): tests/test_unpromoted_scan_gated_twin.sh. -->

- [x] [ROUTINE] **unpromoted-scan twin check misses an auto-GATED ROADMAP item (marker not line-terminal) → phantom re-dispatch** (INBOUND routed:8911 from zkWhale relay handoff relay-20260717-182134-8632) <!-- id:798d -->
  - **Problem**: `relay/scripts/unpromoted-scan.sh`'s twin regex (line ~269) anchors the id marker to END-OF-LINE (`<!-- id:$token -->[[:space:]]*$`). But `handback-followup.py`'s `gate_line` (id:1b1a) DELIBERATELY inserts its gate note AFTER the id marker (`<!-- id:XXXX --> — 🚧 GATED (auto, id:3801; route:…): …`), because the marker is not always line-terminal. So once a ROADMAP item is auto-GATED, the end-of-line-strict twin check MISSES it, its TODO source with that id re-surfaces as phantom `promote` backlog every relay round, and the pool re-dispatches a no-op handoff (observed live: zkWhale id:4148/4944). Same hidden/phantom-backlog family as id:2dea / id:1312, reached from the opposite side (a false-NEGATIVE twin miss vs. id:1312's false-POSITIVE prose match).
  - **Fix**: relax the twin check at `unpromoted-scan.sh:~269` to anchor on the `<!-- id:$token -->` HTML-comment marker form REGARDLESS of trailing notes — drop the `[[:space:]]*$` end-anchor (change `<!-- id:${token} -->[[:space:]]*$` to `<!-- id:${token} -->`). The comment-marker form is itself the anchor that prevents the id:1312 prose false-match (a bare `id:XXXX` mention in prose is never `<!-- id:XXXX -->`), so this must NOT touch that behaviour. Do NOT instead change `handback-followup.py` to insert the note before the marker — that would regress id:1b1a's deliberate after-marker placement. **Consumers enumerated**: `unpromoted-scan.sh` line 269 is the sole twin-check site; the disposition classifier (`classify_disp`, :280+) and the emit loop consume its result but need no change. `lib-anchored-id.sh`'s header (id:521f, lines 14-26) documents that unpromoted-scan was left "end-of-line-strict" on purpose — that decision predates this gate-note interaction and is what 798d corrects; a doc note there is optional, not required.
  - **Acceptance / done-check**: tick this box, then `make test` green — `tests/test_unpromoted_scan_gated_twin.sh` (`# roadmap:798d`) goes EXPECTED-RED→PASS: (a) a ROADMAP item whose marker is followed by a decision-gate note → its TODO twin is SUPPRESSED (not reported); (b) same for a human-route gate note; (c) an ordinary line-terminal marker still suppresses (true-twin regression control); (d) a bare `id:XXXX` prose mention still does NOT twin (id:1312 regression control — still reported); (e) an id absent from ROADMAP is still reported as `promote`. Also `bash tests/test_unpromoted_scan_anchoring.sh` must stay green.
  - **Context**: `relay/scripts/unpromoted-scan.sh:~269`, `relay/scripts/handback-followup.py:60-73` (gate_line, id:1b1a), `relay/scripts/lib-anchored-id.sh` (id:521f), `tests/test_unpromoted_scan_anchoring.sh` (id:1312 companion). TODO twin id:798d.

- [x] [HARD — pool] **Execute+review for the SAME repo in one run collides on the non-union ROADMAP.md** — ARCHITECTURE COMMITMENT, owner decision required; do NOT implement from this entry. Problem + candidates + a recommendation are drafted; take them to `/meeting`. Evidence: run `relay-20260717-100452-13146` (loderite) — the review→execute re-chain (`relay-loop.js:~1966`) fires when the review CHILD RETURNS, before `integrate()` merges the review's worktree, so the execute child branched from a pre-promotion `main`, ticked 4c02, and conflicted with the merged review. `ROADMAP.md` is explicitly NOT `merge=union` (checkbox toggles cannot union — SKILL.md Guardrails), so an execute+review pair on one repo is a near-guaranteed ledger collision. **RECOMMENDATION (not a decision — requires owner ratification at `/meeting`): C1 now** (move the re-chain's `queue.push` from the child-settle path into `integrate()`'s merged branch, gated on `result.openRoutine > 0`, with a loud dispatch assertion) **with C2 as fallback** (hard invariant: never dispatch two units for the same repo in one round — defers the re-chained execute to round N+1's fresh discovery) **if C1's "re-chained unit silently never dispatched" risk proves real; C3 (split the ledger) explicitly NOT here — route into id:2840.** Weaknesses stated plainly: this is a one-instance fix (C2 is the class-fix, recommended against on cost grounds only, not correctness — if the owner weights class-safety over round latency, C2 is the better choice); C1's own failure mode is the same family as id:1735; n=1 (rate unknown, "log it and wait" per id:194e's `merge-conflict` category is a legitimate fourth option not developed here); `queue.push` pickup from inside the integrator chain in all lane orderings is UNVERIFIED. Relates id:1735, id:689c. **DECIDED 2026-07-19 (meeting mtg-1726, D3): C2 NOW** (one-unit-per-repo-per-round invariant) **+ C3 via id:2840 as the true dissolution; NOT C1.** fa1d's 'decide with d03d' hold amended on a false premise — real-remotes is topology-invariant for this merge-time ledger collision (only C3 dissolves it). Owner weighted class-safety over the ~1-round latency. Now routine: implement the one-unit-per-repo-per-round scheduler invariant. **ROUTED 2026-07-19 (relay human): to `/relay handoff` to author the RED spec** — decision stands (C2, mtg-1726); `relay-loop.js` runs only in the Workflow sandbox, so this is NOT a direct `[ROUTINE]` executor pickup (the RED-spec-from-worktree hazard, cf id:2d20). **SPEC AUTHORED 2026-07-20 (handoff relay-handoff-ebd81aaf; re-laned `[INPUT — meeting]`→`[HARD — pool]`)**: extract the C2 invariant as a PURE module `relay/scripts/round-plan.mjs` exporting `enforceOneUnitPerRepo(units)` → `{plan, deferred}` — first unit per repo in scheduling order wins (scheduling order IS verdict-class-priority order), every later same-repo unit lands in `deferred` carrying repo+verdict (surfaced loudly in RELAY_STATUS/events, never silently dropped; the deferred unit re-enters via round N+1's fresh discovery) — and wire an inline copy/call into `relay-loop.js`'s dispatch path (the id:1735 handback-summary.mjs pattern; the sandbox cannot import). The .mjs + spec are worktree-verifiable; the relay-loop.js wiring is pinned structurally by the spec; live pickup-in-all-lane-orderings is sandbox residue verified at the next supervised pool run (record in RELAY_LOG). <!-- id:dc5b --> — **DONE 2026-07-20 (execute+review SHIP, worktree-verifiable part):** `round-plan.mjs` `enforceOneUnitPerRepo` C2 invariant + byte-equivalent inline copy wired into `relay-loop.js` (`node --check` passes); `test_round_plan_one_unit_per_repo.sh` green, suite 289/0. LIVE-ONLY residue (pickup-in-all-lane-orderings in a real Workflow pool) pending next supervised run — recorded in RELAY_LOG, not executor-verifiable (id:2ec4 sandbox limit).
  - **Tests**: `tests/test_round_plan_one_unit_per_repo.sh` (`# roadmap:dc5b`) (currently RED)
  - **Done-check**: `tests/run-tests.sh tests/test_round_plan_one_unit_per_repo.sh` then tick + full `make test` green; `tests/test_relay_loop_structure.sh` + `node --check relay/scripts/relay-loop.js` + `relay/scripts/lint-workflow-templates.mjs` must stay clean.

<!-- 2026-07-19 handoff C2 (run relay-20260719-185534-26123): re-laned id:4a46 from
     [INPUT — decision] → [ROUTINE] — the owner RESOLVED its design-judgment gate (TODO twin,
     relay human 2026-07-19: "the event log is meant to be complete … now routine executor work").
     Single-id-two-views (D2): reuses the TODO twin id:4a46. RED spec authored this handoff (C3):
     tests/test_handback_invariant_equality.sh. NOT promoted (documented in RELAY_LOG C2):
     3add (reviewer-flagged refactor → /relay refactor id:22da, reopens 521f), 2e6d (shipped;
     residual is INPUT-user hook install + an unspecced --check invariant), d5e0 (status-summary
     prose, not executable — folds into id:1de1), 2d20 option-c (decision-gated → meeting id:719e),
     02c7 (needs OS users relay-ro/relay-svc provisioned — INPUT/access, human). -->

- [x] [ROUTINE] **relay-loop: complete the handback event log — make the id:1735 invariant EQUALITY, emit at the two missing real-worktree sites** <!-- id:4a46 --> — **GATE RESOLVED 2026-07-19 (relay human): the event log IS meant to be complete** (re-laned `[INPUT — decision]`→`[ROUTINE]` by handoff C2 this session; reuses TODO twin id:4a46). The design-judgment half is decided: every REAL handback (a held worktree) must also emit a `handback` event, and `assertHandbackInvariant` tightens from `⊇` to **equality over the real-worktree subset**. The one deliberate exclusion is the INTENSIVE fail-closed skip (`worktreePath:'-'`), which is not a handback in the summary's sense — it stays non-emitting, mirroring `reconcileHandbacks`'s existing `worktreePath !== '-'` filter.
  - **Problem**: today `state.handbacks.push` fires at three sites that do NOT emit a `pushEvent('handback')` + `emittedHandbackEvents.push`: `relay-loop.js:~1701` (child failed terminally, real worktree), `:~1712` (`contract_met=false` handback, real worktree), and `:~1966` (INTENSIVE fail-closed, `worktreePath:'-'`). Only `:~1857` and `:~2050` emit. So `~/.config/relay/relay-events.jsonl` under-reports real handbacks (a terminal child failure and a `contract_met=false` handback both leave NO event), and `assertHandbackInvariant` (handback-summary.mjs:45) is one-directional (`emitted ⊆ accumulator`) — it cannot catch the reverse gap. (NB: the old ROADMAP line-numbers 1807/1999/1657/1668/1915 are STALE post-1735-refactor; the current sites are the five above — the executor re-locates by the `state.handbacks.push` / `pushEvent('handback'` grep, not by line number.)
  - **Fix (two parts, both required)**:
    1. **`relay/scripts/handback-summary.mjs` — make `assertHandbackInvariant` bidirectional (equality over the real-worktree subset).** Keep the existing forward check (every emitted event has a matching accumulator entry). ADD the reverse check: every accumulator entry with a REAL worktree — i.e. every entry in `reconcileHandbacks(accumulator)` (`worktreePath && !== '-'`) — must have a matching emitted event (same `repo`+`reason`). Return the union of both directions in `violations` (tag or keep them distinguishable so the log names which direction tripped). Update the doc comment (lines 37-44) to state equality-over-real-worktree and DROP the "id:4a46 tracks that asymmetry as a separate optional audit" sentence (this item closes it). The `worktreePath:'-'` INTENSIVE entries are excluded from the reverse check exactly as `reconcileHandbacks` already excludes them.
    2. **`relay/scripts/relay-loop.js` — emit at the two missing REAL-worktree sites, keep the inline copy byte-identical.** At `:~1701` and `:~1712`, after the `state.handbacks.push`, add the same `pushEvent('handback', { repo, mode: unit.verdict, reason })` + `emittedHandbackEvents.push({ repo, reason })` pair the `:~1857`/`:~2050` sites already use (use the entry's own `reason`/`hbReason`). Do NOT add an emit at `:~1966` (INTENSIVE, `worktreePath:'-'` — deliberately excluded). Update relay-loop.js's INLINE copy of `assertHandbackInvariant` (`:~788`) to stay byte-identical with the .mjs (the id:1735 structural test `tests/test_relay_loop_structure.sh` pins this — keep it green).
  - **Acceptance / done-check**: tick this box, then `make test` green — `tests/test_handback_invariant_equality.sh` (`# roadmap:4a46`) goes EXPECTED-RED→PASS: (a) an accumulator entry with a real worktree and NO matching emitted event → reported as a violation (the reverse direction — currently NOT caught, this is the RED assertion); (b) an emitted event with no accumulator entry → still a violation (forward direction preserved); (c) an accumulator entry with `worktreePath:'-'` and no emitted event → NOT a violation (INTENSIVE exclusion); (d) full bidirectional match → `ok:true`, empty violations. AND `tests/test_relay_loop_structure.sh` stays green (inline copy byte-identical).
  - **Consumers enumerated**: `assertHandbackInvariant` is called once, at `relay-loop.js:~2283` (the loud backstop that logs `violations`); `handback-summary.mjs`'s exports are imported by the tests only (the Workflow sandbox uses the inline copy). No other consumer. `reconcileHandbacks` already encodes the `worktreePath:'-'` exclusion the reverse check reuses — model the filter on it, do not re-derive.
  - **Context**: `relay/scripts/handback-summary.mjs:37-53` (the invariant + `reconcileHandbacks` filter), `relay/scripts/relay-loop.js:~1701/~1712/~1857/~1966/~2050` (the five handback sites) + `:~788` (inline copy) + `:~2283` (call site), `tests/test_relay_loop_structure.sh` (id:1735 byte-identical pin), `tests/test_relay_loop_handback_summary.sh`. TODO twin id:4a46 (owner decision 2026-07-19, "now routine executor work").

- [x] [INPUT — decision · SUPERSEDED 2026-07-21] echo-runner agentType for relay-loop mechanical agents — measure, then adopt or reject (id:f599) — 🚧 GATED (auto, id:3801; route:human): Needs a live instrumented probe run (per-hop subagent token cost with vs without agentType:'echo-runner' over a representative round); the mechanical agent() hops execute only in the Workflow-sandbox runtime, unreachable from a worktree, and the item bars a reasoned decision without measured data. Re-lane back to the pool lane once the measurement exists. — needs /relay human <!-- id:f599 --> — **DECIDED 2026-07-13 (relay human): BUILD THE PROBE.** Owner authorized building the instrumented in-sandbox probe run (per-hop subagent token cost with vs without `agentType:'echo-runner'` over a representative round), then decide adopt/reject on the measured delta. Next step: author the probe harness (runs only in the Workflow-sandbox runtime); keep this box open until the measurement exists. **SUPERSEDED 2026-07-21 — the model:"bash" proxy (id:6176/176f, confirmed working end-to-end) runs the proxy-eligible mechanical hops with ZERO inference, strictly better than a haiku echo-runner; the mechanical-runner-as-subagent rationale is obsoleted (no probe needed). The surviving subagent idea = JUDGMENT roles under id:931c/cae2. Delete the loose `~/.claude/agents/echo-runner.md` once id:6176 lands.**
  - **Why** (TODO id:f599): `~/.claude/agents/echo-runner.md` (haiku + Bash-only + 3-line system prompt) was verified working via Workflow `agentType` on 2026-07-02 (a probe returned verbatim stdout; the registry picks up new defs mid-session with lag). Candidate adoption: the relay-loop.js prelude + the mechanical-runner `agent()` calls gain `agentType: 'echo-runner'` so a purely-mechanical "run this command and echo stdout" hop can't be mangled by a general-purpose agent.
  - **Design / GATE (measure-then-decide, why this is [HARD] not [ROUTINE])**: GATE on a MEASURED relay-econ before/after — one probe run cost ~20.6k subagent tokens, so the harness floor may dominate and swamp any real saving. This is not a mechanical apply: the strong session must (a) measure the per-hop token cost of the current mechanical `agent()` calls vs the same calls with `agentType: 'echo-runner'` over a representative round, and (b) decide by the pre-registered criterion: **adopt only if the delta is real** (a measured, non-noise reduction). If ADOPTED: move `~/.claude/agents/echo-runner.md` INTO this repo (under a tracked path) + add a `make install`/`make install-<x>` symlink for it, and wire `agentType: 'echo-runner'` into the mechanical-runner `agent()` calls in `relay/scripts/relay-loop.js`. If REJECTED: record the measurement + the reason in RELAY_LOG.md and delete the loose `~/.claude/agents/echo-runner.md`. Either way the loose out-of-repo def must not persist unexamined.
  - **Acceptance**: a decision recorded in RELAY_LOG.md with the before/after measurement; on adopt — the agent def is in-repo + installable + wired, `lint-workflow-templates.mjs` clean, `make test` green; on reject — the loose def deleted and the rationale logged. No red test (the deliverable is a measured decision + its follow-through, not a fixed behavior).
  - **Context**: `~/.claude/agents/echo-runner.md` (the loose def), `relay/scripts/relay-loop.js` (prelude + mechanical-runner `agent()` calls), the id:d267 quota-sample / subagent-token accounting for the econ measurement, TODO id:f599.

<!-- 2026-07-08 handoff C2 (run relay-20260708-162516-22523): promoted the sole `promote`-
     disposition TODO item (unpromoted-scan: 1 promote / 58 surface / 1 laned). Single-id-two-
     views (D2): id:356f reuses its open TODO.md twin (routed:dfc1 from llm-from-scratch). -->

- [ ] [HARD — decision gate] Relay consumer of the id:2840 derived ledger index (cross-ledger / count / promotion) — ✅ DECISION RESOLVED + BUILD AUTHORIZED 2026-07-14 (relay human): id:2840 producer shipped (project_manager id:bac5 CORE + id:608c `proj graph`, edges.json contract locked) → build the relay-side consumer. Artifact confirmed live 2026-07-14 (`proj refresh` → 1288 nodes / 2791 edges, `proj graph` consumes it); wire relay review/human + the count line to read it via the stable contract (retire `orphan-scan --cross-ledger` + the d5e0 count prose, id:1de1). <!-- id:659c --> — 🚧 GATED (auto, id:3801; route:decision-gate): Premise false: shipped edges.json is a co-citation graph (no checkbox-state/count) — cannot retire orphan-scan --cross-ledger; decide project_manager index-extension vs. keep-guard + drop-count-only (id:1de1). — needs a /meeting
  - ✅ GATE RESOLVED 2026-07-14 (relay human): the project_manager derived index (id:2840, `routed:1e99`) shipped its producer + locked artifact contract (id:bac5 CORE + id:608c `proj graph`), so this re-lanes `[INPUT — decision]`→`[HARD — pool]` and is now pool-dispatchable. Build: relay `review`/`human` + the TODO count line read the artifact instead of hand-grepping; retire the per-review TODO-twin close + the `orphan-scan --cross-ledger` hand-check; DROP the d5e0 count prose (folds in TODO id:1de1). Artifact confirmed live 2026-07-14: `proj refresh` emits a real populated `~/.cache/project_manager/edges.json` (1288 nodes / 2791 edges over 39 repos) and `proj graph [--public]` consumes it — build against the live artifact. Meeting: `docs/meeting-notes/2026-06-23-0803-ledger-drift-derived-index.md`.

- [x] [HARD] Explicit `[HARD]` lane tags + bucket the human-backlog HARD surface (done 2026-06-22, relay HARD child — relay/bash half) <!-- id:78ff -->
  - **Done 2026-06-22** (relay HARD child, id:da26): shipped the relay/bash half. (1) Lane vocabulary doc `relay/references/hard-lanes.md` — the single shared contract both `gather-human-backlog.sh` (id:78ff) and project_manager `scan.py` (id:b466) read: `[HARD — pool|meeting|hands]` lanes + `[HARD — decision gate]`/`🚧 route:meeting|human|decision-gate` as meeting-lane aliases (id:3801); `[INTENSIVE]` is the orthogonal resource axis, not a lane. (2) `gather-human-backlog.sh`: replaced `emit_gated_hard` (single `gated_hard` lump) with `emit_hard_lanes` — READS the explicit lane tag → emits per-lane kind `hard_pool`/`hard_meeting`/`hard_hands`; an open `[HARD]` with NO recognized lane prints a stderr `ERROR:` and forces a NONZERO exit (id:415b grammar-tightening-with-loud-rejection, never silently default). (3) `references/human.md` §2/§3/return-summary: the three buckets are now distinct call-to-actions (pool→FYI/`--afk`, meeting→`/meeting`, hands→"you run these"), not one /meeting firehose. (4) Back-filled THIS repo's bare `[HARD — strong model]` items: de4e→meeting, 401c→pool, 3346→meeting; dba3 left as its machine-managed `[HARD — decision gate]` alias. Acceptance test `tests/test_hard_lane_buckets.sh` (roadmap:78ff) green. **Residual (not this worktree's scope):** cross-repo back-fill of OTHER confirmed-own repos' bare `[HARD — strong model]` tags — a relay child works ONE repo's worktree; the per-repo lane back-fill belongs to each repo's next handoff/review or a `/relay human` sweep (the collector now LOUD-rejects any un-back-filled untagged HARD, so the gap is self-surfacing). project_manager id:b466 (Python half) consumes this same `hard-lanes.md` contract.
  - **Design + rationale: TODO id:78ff** (single-id-two-views — the "why" lives there). DECISION 2026-06-21 (user "obviously explicit"): every open `[HARD]` ROADMAP item declares a lane in its bracket tag — `[HARD — pool]` (this `--afk` pool runs it via the `hard` verdict, id:da26), `[HARD — meeting]` (≡ `[HARD — decision gate]`/`🚧 route:…`, id:3801 → `/meeting`), `[HARD — hands]` (hardware/sudo/secret/on-device/rehearsal → "you run these"). `[INTENSIVE — <resource>]` (id:8d52) is an ORTHOGONAL resource axis, not a lane.
  - **Scope (this is the relay/bash half; `proj relay` half = project_manager id:b466):**
    1. Document the lane vocabulary ONCE in `relay/references/` (the single source both tools read).
    2. `gather-human-backlog.sh`: replace the "emit every `[HARD]` as gated_hard" lump with reading the explicit lane tag → emit a `bucket` field (pool|meeting|hands); a `[HARD]` with NO lane tag is emitted as `untagged` and the script EXITS NONZERO / prints a LOUD warning (id:415b grammar-tightening-with-loud-rejection — never silently default).
    3. `references/human.md`: present the three buckets as distinct call-to-actions (pool→"run /relay --afk", meeting→/meeting, hands→checklist), not one "/meeting" firehose.
    4. Back-fill every existing bare `[HARD — strong model]` across all confirmed `own` repos to an explicit lane (use the 2026-06-21 manual re-bucketing in the diary as the starting classification).
  - **Acceptance:** a new `tests/test_hard_lane_buckets.sh` (`# roadmap:78ff`): a ROADMAP fixture with one item per lane + one untagged asserts gather-human-backlog emits the right `bucket` per item AND exits nonzero (loud) on the untagged one; the lane vocabulary doc exists; cross-check that the marker set matches project_manager's (id:b466). RED until implemented.
  - **Coupling:** ships its vocabulary doc BEFORE or WITH project_manager id:b466 (shared contract; keep them in sync). Relates id:3801/da26/8d52/9c92/415b.

- [ ] [HARD — decision gate] Cold fixed-prompt probe: re-pose Opus-degradation incidents #2 (confident-wrong "zkm-* on another machine") and #3 (over-engineered ~/.claude branch-split) against fresh Opus; record pass/fail vs the recorded incident behaviour, finding written into `docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md`. Promoted 2026-07-13 (user) from TODO id:e3c0 (single-id-two-views — same id spans both ledgers). **Why HARD**: requires apex judgment to assess whether fresh Opus reproduces the confident-wrong / over-engineering behaviour. Bounded: two fixed prompts, pass/fail each, one meeting-note write. <!-- id:e3c0 --> — 🚧 GATED (auto, id:3801; route:human): Cold probe needs memory/CLAUDE.md-free Opus (id:2d01 relay-probe user); creds not yet copied (id:dba3 HANDS residue) + sudo forbidden; same-user run is contaminated. — needs /relay human
- [ ] [HARD] Strong-model audit: code review, security, and design coherence <!-- id:401c --> <!-- relay:recurring-audit -->
  - **Why HARD**: requires adversarial judgment — finding subtle bugs, security issues,
    and internal contradictions in design docs that a weaker model would miss or dismiss.
    Also requires holding the full design history in mind to spot feasibility gaps.
  - **Acceptance**: a meeting note documenting findings across three passes:
    (1) **Code review** — correctness bugs, error handling gaps, shell quoting issues,
    race conditions, unhandled edge cases in scripts and Python helpers;
    (2) **Security audit** — injection risks (command, path, jq), unvalidated inputs
    at system boundaries, secrets exposure, file permission assumptions;
    (3) **Design coherence** — check currently-unreviewed design decisions (anything
    added since last Fable turn) for sensibility, feasibility, and internal
    contradictions (e.g. a TODO gate that can never fire, a contract rule that
    contradicts another). Each finding is either fixed inline (if trivial), or
    becomes a new TODO/ROADMAP item with the finding quoted as context. No finding
    is silently dropped — if assessed as acceptable risk, say so explicitly.
  - **Tests**: none (audit output is the deliverable; follow-on items get their own tests)
  - **Done-check**: meeting note at `docs/meeting-notes/YYYY-MM-DD-HHMM-strong-model-audit.md`
    exists; every finding is either fixed, tracked, or explicitly accepted with rationale.
  - **Context**: run after each significant batch of Sonnet executor work or design changes.
    First run: covers all work since `fable-ckpt-20260612-1328`. Subsequent runs: diff
    against the most recent `fable-ckpt-*` tag (same window as review mode step 2).
  - **Run log** (recurring item — stays open by design):
    - Run 1 (2026-06-12-1811): `fable-ckpt-20260612-1328`..HEAD — see meeting note.
    - Run 2 (2026-06-15-1520): `fable-ckpt-20260612-1827`..HEAD (relay scripts surface) — F1/F2 → id:c8db.
    - Run 3 (2026-06-15-1745): `relay-ckpt-20260615-1559`..HEAD — **2 defects fixed inline**:
      `test_relay_executor.sh` asserted a stub commit 608800b removed (suite was 1-red on
      arrival, now 48/0); id:3826 gaming-flag logger was a dead feed (review dispatch prompt
      never requested its fields) — fixed + regression-guard added. See
      `docs/meeting-notes/2026-06-15-1745-strong-model-audit.md`.
    - Run 4 (2026-06-15-1759): `relay-ckpt-20260615-1748`..HEAD (1 commit: `bf70a52`
      statusline/check-deps.sh) — **clean**: no code/security defects. One **coherence drift
      fixed inline** — id:414a was still marked `GATED` on id:fa05+id:dfaf, both now shipped;
      updated the gate line to CLEARED so a future strong session isn't misled into skipping it.
      See `docs/meeting-notes/2026-06-15-1759-strong-model-audit.md`.
    - Run 5 (2026-06-15-1937): `relay-ckpt-20260615-1748`..HEAD (~270 lines / 10 files; code:
      relay-loop.js ×2 + 2 tests) — **clean**: no code/security defects, no inline fix needed.
      Verified the two pool-crash fixes (failed-shard surfacing via order-preserving `chunks[i]`;
      removal of `new Date()`/`process.env` forbidden in the Workflow sandbox) correct with genuine
      regression guards, and the cross-ledger state coherent (0 open ROUTINE / 3 open HARD; d5e0
      summary agrees). See `docs/meeting-notes/2026-06-15-1937-strong-model-audit.md`.
    - Run 6 (2026-06-15-1937b): `relay-ckpt-20260615-1937..HEAD` (only first-seen code:
      the 2-line `paused` filter in gather-human-backlog.sh, 7456e1f) — **clean**: no
      code/security/coherence defects. One forward-robustness gap **fixed inline** — the
      new `paused = true` sweep-skip filter shipped without a test; added a non-vacuous
      regression guard (repoD fixture) to `test_relay_human.sh`. Suite 50/0. See
      `docs/meeting-notes/2026-06-15-1937b-strong-model-audit.md`.
    - Run 7 (2026-06-15-2147): `relay-ckpt-20260615-2129..HEAD` (only first-seen code:
      the `warn_nested_worktrees` stale-checkout guard in gather-human-backlog.sh,
      83d8614) — **clean**: no code/security/coherence defects (`set -e`-safe grep
      guards, `-F` fixed-string prefix match with trailing-slash, stdout/stderr split all
      correct). One forward-robustness gap **fixed inline** (same class as Run 6) — the
      new warning shipped without a test; added a non-vacuous regression guard (section 4:
      real-git nested-worktree fixture + clean-repo negative control + stdout-clean
      assertion) to `test_relay_human.sh`. Suite 50/0. See
      `docs/meeting-notes/2026-06-15-2147-strong-model-audit.md`.
    - Run 8 (2026-06-16-0650): `relay-ckpt-20260615-2150..HEAD` (first-seen code: the
      profiler batch — `profile-run.sh` + `profile-runs-batch.sh` + their tests, id:a59e/
      id:08a3, ~615 lines) — **clean**: no code/security defects (pure-read, stdlib-only,
      `grep -- "$ARG"` option-safe, no injection/traversal/secrets). One coherence drift
      **fixed inline** — both scripts' header comments documented a one-wildcard search root
      (`projects/*/subagents/workflows`) while the code+real layout use two
      (`projects/*/*/...`); updated the comments to match. One cosmetic dead-code residue in
      profile-run.sh (empty-list loop + unused `at_cap_intervals`) flagged + explicitly
      accepted (no behavioural effect). Cross-ledger coherent (0 ROUTINE / 3 HARD, d5e0
      agrees). Suite 52/0. See `docs/meeting-notes/2026-06-16-0650-strong-model-audit.md`.
    - Run 9 (2026-06-16-0928): `relay-ckpt-20260616-0653..HEAD` (~586 lines / 14 files;
      observability id:c8b6 + drain/gated-HARD id:2d20 + quota-seatbelt id:4267 + new
      relay-burn.sh id:219b) — **clean**: no code/security defects. One doc/impl discrepancy
      **fixed inline** — `relay-state-write.sh` event-append header claimed "SAME flock" but
      correctly flocks the target events file (not the shared $LOCK); corrected the comment +
      Paths note + `--help` range. Three findings **accepted** w/ rationale: relay-burn.sh
      `date -d "$reset"` awk-shellout injection seam (LOW — `resets_at` is provider-controlled
      API data; filed as forward-robustness TODO id:287b), a dead tautology sub-condition in
      the segment reduce (cosmetic), and code-only sub-ids 15bd/cd19/03a5/219b (inline
      provenance for tracked parents, not ledger tokens). Cross-ledger coherent (0 ROUTINE /
      3 HARD, d5e0 agrees). Suite 53/0. See `docs/meeting-notes/2026-06-16-0928-strong-model-audit.md`.
    - Run 10 (2026-06-16-1247): `95d3d07..HEAD` (first-seen code since Run 9; ~944 lines /
      16 files: orphan-reconcile D1/D2/D3 + relay-econ.py + archive-done multiline +
      gather-human-backlog gated-HARD sweep) — **1 defect fixed inline**: `relay-reconcile.sh`
      `--integrate`/`--discard` with no branch arg died on a `set -e` `shift 2` count error
      BEFORE the friendly `<branch> required` guard; fixed to `shift; shift || true` + a
      non-vacuous behavioural regression guard in `test_relay_reconcile_mode.sh` (proven it
      fails on the reverted form). One **doc nit fixed inline** (relay-econ.py header field
      names). One **LOW accepted** (gather-human-backlog `awk -v`, id:c8db class). No security
      defects; cross-ledger coherent (0 ROUTINE / 3 HARD, d5e0 agrees). Suite 58/0. See
      `docs/meeting-notes/2026-06-16-1247-strong-model-audit.md`.
    - Run 11 (2026-06-16-1222): `5ab8c12..HEAD` (first-seen since Run 10, EXCLUDING Run 10's
      own already-audited merge d36208a) — **clean**: window was LEDGER-ONLY (TODO id:0547
      +1, RELAY_LOG ckpt +4; zero code/scripts/python). No code to review, no security
      surface. Coherence pass verified TODO id:0547's injected-unit-vs-discovery-unit race
      diagnosis against relay-loop.js (L71 invariant, L617 un-deduped injection merge, L808
      same-run re-entrant lease — all accurate; sound entry, no contradiction). Cross-ledger
      coherent (0 ROUTINE / 3 HARD, d5e0 agrees). Suite 58/0 (audit-only, no test changes).
      See `docs/meeting-notes/2026-06-16-1222-strong-model-audit.md`.
    - Run 12 (2026-06-16-1122): `d3ca7a9..HEAD` (first-seen since Run 11, EXCLUDING Run
      11's own already-audited merge `5914c72`) — **clean**: window was LEDGER-ONLY (sole
      first-seen change = the Run 11 checkpoint paragraph in RELAY_LOG.md +4; zero
      code/scripts/python — `git diff --name-only -- '*.sh' '*.py' '*.js'` empty). No code
      to review, no security surface, no new design decision/gate. Cross-ledger coherent
      (0 ROUTINE / 3 HARD; all three HARD ids `[ ]` in both ROADMAP+TODO, d5e0 agrees).
      Suite 58/0 (audit-only, no test changes). See
      `docs/meeting-notes/2026-06-16-1122-strong-model-audit.md`.
    - Run 13 (2026-06-17-1102): first-seen code since the last audit (`2026-06-16-1247`) —
      5 files: `discover-sig.sh` (88L), `relay-loop.js` diff (id:c3a6 cache integration, ~52L),
      `model-probe.sh` (241L), `settings-env.py` (90L), `model-probe.battery.jsonl`. **Clean —
      no inline fixes** (code clean to a high bar): discovery cache correctly hashes a superset
      of the 9 shard inputs, fail-open sound throughout; settings-env.py idempotent/non-clobbering;
      battery JSONL valid, no secrets. **2 LOW findings tracked**: id:4348 (discover-sig.sh
      `upstream` read without fetch → bounded origin-behind under-invalidation — needs a measured
      fetch-vs-accept decision) + id:b9b5 (model-probe.sh grade `echo`→`printf` robustness). 3
      findings explicitly accepted (awk -v repo-name = id:c8db-class zero-risk; review-range
      covered by HEAD+tag hashing; probe's no-`--model` = D6 observe-don't-assert by design). Run
      via `/relay . --afk` (Opus hard-execute). See `docs/meeting-notes/2026-06-17-1102-strong-model-audit.md`.
    - Run 14 (2026-06-17, via /relay human Pareto pick): `relay-ckpt-20260617-1326..HEAD` — first-seen
      code = the id:bbd2 `migrate-state-dirs.sh` rewrite (166L) + `test_migrate_state_dirs.sh` (new).
      Ran as a 3-pass adversarial audit (correctness / security / design-coherence) of THIS session's
      own work. **4 real defects fixed inline** (audit caught them in freshly-written code): (1) HIGH —
      jsonl merge `cat src dest | awk` fused two records into one corrupt line when src lacked a trailing
      newline (silent log loss); fixed with `awk 1 … | awk 'NF && !seen'` + a no-trailing-newline test.
      Verified the LIVE `relay-events.jsonl` was NOT corrupted (the appender always terminates lines → 0
      fused / 358 valid). (2) MED — dir-union swallowed a partial `cp` failure then `rm -rf`'d src → lost
      un-copied children; now drops src only on cp success, else refuses. (3) MED — idle guard failed OPEN
      on `claim.sh`/`stat` errors and peeked one base; now fails CLOSED and peeks both old+new. (4) MED —
      `ASSUME_IDLE` bypass now warns loudly on stderr. Test grew 9→12 cases (added no-trailing-newline,
      NEW-newer snapshot, type-mismatch refusal). Design/spec claims all independently re-verified TRUE
      (symlinks, 358 events, 48 gather). 1 LOW tracked: id:16e9 (pre-existing flaky `test_relay_claim_liveness.sh`,
      roadmap:7570 — unrelated to this change). Suite 66/66.
    - Run 15 (2026-06-19-2005): first-seen code since Run 14's own audit commit `61020a0`
      (`61020a0..HEAD`, ~1.9 kLOC / 9 prod files) — the L1/L2 token-skeleton + data-loss-fix
      batch (ids aa93 clean-tree-gate + git-lock-push autostash-refuse, 11ad gather-repo-state,
      0d31 relay-status-publish, c855 push-seed cache, 3801 handback-followup.py, b841 nested
      quotaThresholds fold, 2425 crossedBucket). **Clean** — no inline code/security fix needed.
      Verified: gather-repo-state.sh builds JSON via env vars (no injection), discover-sig.sh ⟷
      gather-repo-state.sh hash the SAME superset (no stale-verdict hazard for the c3a6/c855
      caches), push-seed seeds `idle` only at provably-drained 0/0 (no under-dispatch), handback
      follow-up POSIX-escapes every shell arg + fire-and-forget, git-lock-push/clean-tree-gate
      both refuse to force-clean a foreign-dirty tree, profile-run.sh rollup-needle removed.
      shard-canary corpus is the correct behavior-preservation net for the 11ad refactor.
      1 LOW tracked: id:05e8 (`test_git_lock_push_slash_branch.sh` flaked on the first full-suite
      run, green in isolation + on re-run — pre-existing fetch/push timing flake, id:16e9 class,
      NOT new /tmp contention; both tests isolate via mktemp). Suite 76/0 on a clean run. See
      `docs/meeting-notes/2026-06-19-2005-strong-model-audit.md`.
    - Run 16 (2026-06-19-2015): first-seen change since Run 15's own audit commit `36fb824`
      (`36fb824..HEAD`) — **clean: LEDGER-ONLY window**. Sole first-seen change = the Run 15
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      36fb824..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security surface,
      no new design decision/gate. The RELAY_LOG paragraph is internally consistent (audit
      verdict + suite count + tracked-flake id) — no contradiction. Cross-ledger coherent
      (0 open ROUTINE / 3 HARD — dba3/401c/3346; the 4th `[ ]` HARD line is the DEFERRED
      design entry de4e, not executable; d5e0 agrees). Both pre-existing tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 76/0 (audit-only, no test changes). See
      `docs/meeting-notes/2026-06-19-2015-strong-model-audit.md`.
    - Run 17 (2026-06-19-2017): first-seen change since Run 16's own audit commit `250613f`
      (`250613f..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16 class). Sole first-seen change
      = the Run 16 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff
      --name-only 250613f..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface, no new design decision/gate. **One coherence drift fixed inline** (Run 4/Run 8
      class) — TODO id:d5e0's hand-rolled "review 2026-06-16 1900" summary still listed the
      CLOSED id:10c0 (state-dir rename, `[x]` 2026-06-17 w/ completion id:bbd2) as an open HARD
      and OMITTED the open id:dba3; corrected the enumeration to the live ROADMAP set
      (dba3/401c/3346 + DEFERRED de4e). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3/401c/3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0. See
      `docs/meeting-notes/2026-06-19-2017-strong-model-audit.md`.
    - Run 18 (2026-06-19-2039): first-seen change since Run 17's own audit commit `c4c0fdc`
      (`c4c0fdc..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17 class). Sole first-seen
      change = the Run 17 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only c4c0fdc..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. The RELAY_LOG paragraph is
      internally consistent (verdict + inline-fix note + suite count). Cross-ledger coherent
      (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e DEFERRED non-executable;
      all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's drift fix holds).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0. See
      `docs/meeting-notes/2026-06-19-2039-strong-model-audit.md`.
    - Run 19 (2026-06-19-2117): first-seen change since Run 18's own audit commit `c4c0fdc`
      (`c4c0fdc..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18 class). All first-seen
      changes are Run 18's own ledger/doc artifacts (RELAY_LOG checkpoint paragraph +8,
      ROADMAP run-log line +10, the Run 18 meeting note +67, a 1-line TODO d5e0 touch);
      `git diff --name-only c4c0fdc..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. The two new RELAY_LOG
      paragraphs (Run 17 + Run 18) are internally consistent (verdict + suite count 76/0).
      Cross-ledger coherent (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e
      DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees,
      Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur.
      Suite 76/0. See `docs/meeting-notes/2026-06-19-2117-strong-model-audit.md`.
    - Run 20 (2026-06-19-2118): first-seen change since Run 19's own audit commit `f24b99e`
      (`f24b99e..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19 class). Sole first-seen
      change = the Run 19 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff
      --name-only f24b99e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface, no new design decision/gate. The RELAY_LOG paragraph is internally consistent
      (verdict + no-inline-fix note + suite count 76/0). Cross-ledger coherent (0 open ROUTINE /
      3 executable HARD — dba3/401c/3346; de4e DEFERRED non-executable; all three open in both
      ROADMAP+TODO; d5e0 summary agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9,
      id:05e8) did NOT recur. Suite 76/0. See `docs/meeting-notes/2026-06-19-2118-strong-model-audit.md`.
    - Run 21 (2026-06-19-2155): first-seen change since Run 20's own audit commit `39592e8`
      (`39592e8..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20 class). First-seen
      changes = the Run 20 strong-execute + review checkpoint paragraphs in RELAY_LOG.md and two
      newly-minted TODO design items (id:81cb statusline per-session ctx state file; id:daf0
      screenshots + README refresh) under a new `## docs & presentation` header; `git diff
      --name-only 39592e8..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface (the two specs are purely-local additive sketches; id:daf0 itself flags the
      capture-privacy hazard for the build pass). Both new items internally sound (id:81cb's
      `.session_id`/`$CLAUDE_SESSION_ID` key both sides agree on is correct — statusline parses only
      `.transcript_path` today; id:daf0's README-vs-SKILL.md boundary consistent). **One coherence
      drift fixed inline (Run 4/8/17 class)** — the TODO id:401c MIRROR line still read "Latest ✓
      Run 19"; Run 20 had since run (ledger-only); refreshed it to Run 21. Cross-ledger coherent
      (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e DEFERRED non-executable; all three
      open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's drift fix holds). id:16e9 did NOT
      recur; id:05e8 flaked once (75/1) then green in isolation + full-suite rerun (76/0), exactly
      as id:05e8 predicts. Suite 76/0 on rerun. See `docs/meeting-notes/2026-06-19-2155-strong-model-audit.md`.
    - Run 22 (2026-06-21-1656): first-seen change since Run 21's own audit commit `b0b4076`
      (`b0b4076..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20 class).
      First-seen changes = Run 21's strong-execute checkpoint + the two 2026-06-21 review
      checkpoint paragraphs in RELAY_LOG.md, a REVIEW_ME box (flaky-claim-liveness note),
      two new TODO design items (id:ebd0 [HIGH PRIORITY — SECURITY] global pre-push privacy
      gate; id:d2cd [HIGH PRIORITY] lock-hygiene umbrella), the id:ebd0 privacy sanitization,
      and an archived done entry; `git diff --name-only b0b4076..HEAD -- '*.sh' '*.py' '*.js'`
      is EMPTY. No code to review, no security surface. gaming-scan clean (no DELETED_TEST/
      ADDED_SKIP/REMOVED_ASSERT). **One coherence drift fixed inline (Run 4/8/17/21 class)** —
      the TODO id:401c MIRROR line still read "Latest ✓ Run 21"; refreshed to Run 22. Design
      coherence verified on both new items: id:d2cd's 5 cited sub-ids (3b18/6366/bae5/d187/
      3558) all exist in the ledgers and the umbrella framing is sound; id:ebd0's sanitization
      (e886e6f) correctly moved leak specifics to private memory (no-leak-specifics directive).
      Cross-ledger coherent (0 open ROUTINE / 3 executable HARD — dba3/401c/3346; de4e DEFERRED
      non-executable; d5e0 summary agrees, Run 17's drift fix holds). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 76/0 on a clean run. See
      `docs/meeting-notes/2026-06-21-1656-strong-model-audit.md`.
    - Run 23 (2026-06-21-1713): first-seen change since Run 22's own audit merge `c40b20e`
      (`c40b20e..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20/21/22 class).
      Sole first-seen change = the Run 22 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only c40b20e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally consistent
      (Run 22 verdict + mirror-line drift fix + suite 76/0). **One coherence drift fixed inline
      (Run 4/8/17/21/22 class)** — the TODO id:401c MIRROR line still read "Latest ✓ Run 22";
      refreshed to Run 23. Cross-ledger coherent (0 open ROUTINE / 3 executable HARD —
      dba3/401c/3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0
      summary agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur. Suite 76/0 on a clean run. See `docs/meeting-notes/2026-06-21-1713-strong-model-audit.md`.
    - Run 24 (2026-06-21-1626): first-seen change since Run 23's own audit merge `b2db0bc`
      (`b2db0bc..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16/17/18/19/20/21/22/23 class).
      Sole first-seen change = the Run 23 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only b2db0bc..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally consistent
      (Run 23 verdict + mirror-line drift fix + suite 76/0). **One coherence drift fixed inline
      (Run 4/8/17/21/22/23 class)** — the TODO id:401c MIRROR line still read "Latest ✓ Run 23";
      refreshed to Run 24. Cross-ledger coherent (0 open ROUTINE / 3 executable HARD —
      dba3/401c/3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0
      summary agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur. Suite 76/0 on a clean run. See `docs/meeting-notes/2026-06-21-1626-strong-model-audit.md`.
    - Run 25 (2026-06-21-1842): first-seen change since Run 24's own audit merge `99a1f2e`
      (`99a1f2e..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–24 class). First-seen = three
      RELAY_LOG checkpoint paragraphs + a real ROADMAP design-state change (`01e54c4`): id:dba3
      auto-gated `[HARD — strong model]` → `[HARD — decision gate]` route:human. `git diff
      --name-only 99a1f2e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY → no code/security surface.
      gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). **Design coherence: the
      id:dba3 gate change verified COHERENT** — closure genuinely needs the claude-probe OS user
      (id:d0c0, useradd/sudo — forbidden for an unattended relay child) + real Opus/Sonnet/Haiku
      token runs, so route:human is correct (consistent with the id:dba3 body, the open id:23e9
      seeding gate, and project memory; the gate will fire for a human, not silently — no
      can-never-fire gate). **One coherence drift fixed inline (Run 4/8/17/21/22/23/24 class)** —
      the TODO id:401c MIRROR line still read "Latest ✓ Run 24"; refreshed to Run 25. Cross-ledger
      coherent (0 open ROUTINE / 3 open HARD — dba3 now decision-gated, 401c, 3346 gated; de4e
      DEFERRED non-executable; d5e0 summary agrees, Run 17's drift fix holds). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 76/0 on a clean run. See
      `docs/meeting-notes/2026-06-21-1842-strong-model-audit.md`.
    - Run 26 (2026-06-21-1835): first-seen change since Run 25's own audit merge `cb83ad1`
      (`cb83ad1..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–25 class). Sole first-seen
      change = the Run 25 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only cb83ad1..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 25 verdict + dba3-gate-coherent + mirror-line drift fix + suite 76/0).
      **One coherence drift fixed inline (Run 4/8/17/21/22/23/24/25 class)** — the TODO
      id:401c MIRROR line still read "Latest ✓ Run 25"; refreshed to Run 26. Cross-ledger
      coherent (0 open ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346;
      de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0 summary
      agrees, Run 17's drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur. Suite 76/0 on a clean run. See `docs/meeting-notes/2026-06-21-1835-strong-model-audit.md`.
    - Run 27 (2026-06-21-1903): first-seen change since Run 26's own audit merge `32f430d`
      (`32f430d..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–26 class). Sole first-seen
      change = the Run 26 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 32f430d..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 26 verdict + mirror-line drift fix + suite 76/0). **One coherence
      drift fixed inline (Run 4/8/17/21/22/23/24/25/26 class)** — the TODO id:401c MIRROR
      line still read "Latest ✓ Run 26"; refreshed to Run 27. Cross-ledger coherent (0 open
      ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED
      non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's
      drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0 on
      a clean run. See `docs/meeting-notes/2026-06-21-1903-strong-model-audit.md`.
    - Run 28 (2026-06-21-1919): first-seen change since Run 27's own audit merge `8b82136`
      (`8b82136..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–27 class). Sole first-seen
      change = the Run 27 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 8b82136..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 27 verdict + mirror-line drift fix + suite 76/0). **One coherence
      drift fixed inline (Run 4/8/17/21/22/23/24/25/26/27 class)** — the TODO id:401c MIRROR
      line still read "Latest ✓ Run 27"; refreshed to Run 28. Cross-ledger coherent (0 open
      ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED
      non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's
      drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0 on
      a clean run. See `docs/meeting-notes/2026-06-21-1919-strong-model-audit.md`.
    - Run 29 (2026-06-21-1935): first-seen change since Run 28's own audit merge `8016dfa`
      (`8016dfa..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–28 class). Sole first-seen
      change = the Run 28 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 8016dfa..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 28 verdict + mirror-line drift fix + suite 76/0). **One coherence
      drift fixed inline (Run 4/8/17/21/22/23/24/25/26/27/28 class)** — the TODO id:401c
      MIRROR line still read "Latest ✓ Run 28"; refreshed to Run 29. Cross-ledger coherent
      (0 open ROUTINE / 3 executable HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED
      non-executable; all three open in both ROADMAP+TODO; d5e0 summary agrees, Run 17's
      drift fix holds). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 76/0 on
      a clean run. See `docs/meeting-notes/2026-06-21-1935-strong-model-audit.md`.
    - Run 30 (2026-06-22-0140): first-seen change since Run 29's own audit merge `422e95d`
      (`422e95d..HEAD`) — **SUBSTANTIVE CODE window** (breaks the Runs 11/12/16–29
      ledger-only streak): ~831 insertions / 11 code files. Production: gather-human-backlog.sh
      `emit_gated_hard`→`emit_hard_lanes` (id:78ff explicit `[HARD — pool|meeting|hands]`
      lane tags, untagged=LOUD nonzero reject id:415b); relay-reconcile.sh `--all` cross-repo
      orphan list (unreadable repo SURFACED not swallowed — the id:4e14 anti-pattern avoided);
      orphan-scan.sh `--promotion` + `xledger-ok` (id:d9b0 seam tooling); git-lock-push.sh
      `GIT_TERMINAL_PROMPT=0` + `ssh-add -l` precheck + BatchMode push; new
      tools/check-no-silent-swallow.sh swallow-ban guard (id:4347, advisory→`--enforce`).
      **CLEAN — no code/security defects** across all 3 passes: lane awk regex verified
      against the live 4 open HARD items (all classify right; `[—-]` backwards-range is a
      benign gawk literal set); rc-plumbing survives `set -e`; no injection (relay.toml
      trusted, fixed grep patterns, quoted `git -C`); git-lock-push HARDENS auth. Design
      coherent: id:78ff contract consistent across hard-lanes.md/collector/human.md/test;
      `route:human`→meeting bucket (not hands) **explicitly accepted** (auto-gate emits a
      coarse human-route; fine pool/meeting/hands is a human hand-tag job); swallow-ban
      ships ADVISORY (231 un-annotated swallows in 51 scripts = exactly why not yet
      enforcing). gaming-scan clean. **One coherence drift fixed inline (Run 4/8/17/21–29
      class)** — TODO id:401c MIRROR line still read "Latest ✓ Run 29"; refreshed to Run 30
      (d5e0 itself NOT stale this run). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED non-executable; all three open
      in both ROADMAP+TODO; d5e0 agrees). Both tracked flakes (id:16e9, id:05e8) did NOT
      recur (id:6b91's CLAIM_TTL fix hardens the id:16e9 class). Suite 80/0 on a clean run.
      See `docs/meeting-notes/2026-06-22-0140-strong-model-audit.md`.
    - Run 31 (2026-06-22-0145): first-seen change since Run 30's own audit merge `00cfff7`
      (`00cfff7..HEAD`) — **LEDGER-ONLY window** (Runs 11/12/16–29 class). Sole first-seen
      change = the Run 30 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --name-only 00cfff7..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to
      review, no security surface, no new design decision/gate. gaming-scan clean (no
      DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT). The RELAY_LOG paragraph is internally
      consistent (Run 30 verdict + suite 80/0). **No coherence drift this run** — unlike
      the Run 4/8/17/21–30 class, the TODO id:401c MIRROR line and d5e0 summary were BOTH
      already current on arrival (Run 30 refreshed the mirror to Run 30; d5e0 not stale).
      Cross-ledger coherent (0 open ROUTINE / 3 executable HARD — dba3 decision-gated /
      401c / 3346; de4e DEFERRED non-executable; all three open in both ROADMAP+TODO; d5e0
      agrees). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean
      run. See `docs/meeting-notes/2026-06-22-0145-strong-model-audit.md`.
    - Run 32 (2026-06-22-0215): first-seen change since Run 31's own audit merge `d55fd25`
      (`d55fd25..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0208` / `e37df3a`) —
      **LEDGER-ONLY window** (Runs 11/12/16–29/31 class). Sole first-seen change = the Run 31
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      d55fd25..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security surface,
      no new design decision/gate. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).
      The RELAY_LOG paragraph is internally consistent (Run 31 verdict + suite 80/0). **No
      coherence drift this run** — the TODO id:401c MIRROR line and d5e0 summary were BOTH
      already current on arrival (Run 31). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED non-executable; all three open in
      both ROADMAP+TODO; d5e0 agrees). Both tracked flakes (id:16e9, id:05e8) did NOT recur.
      Suite 80/0 on a clean run. See `docs/meeting-notes/2026-06-22-0215-strong-model-audit.md`.
    - Run 33 (2026-06-22-0317): first-seen change since Run 32's own audit merge `b315aed`
      (`b315aed..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0217` / `59b0b99`) —
      **LEDGER-ONLY window** (Runs 11/12/16–29/31/32 class). Sole first-seen change = the Run 32
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      b315aed..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security surface,
      no new design decision/gate. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).
      The RELAY_LOG paragraph is internally consistent (Run 32 verdict + suite 80/0). **No
      coherence drift this run** — the TODO id:401c MIRROR line and d5e0 summary were BOTH
      already current on arrival (Run 32). Cross-ledger coherent (0 open ROUTINE / 3 executable
      HARD — dba3 decision-gated / 401c / 3346; de4e DEFERRED non-executable; all three open in
      both ROADMAP+TODO; d5e0 agrees). Both tracked flakes (id:16e9, id:05e8) did NOT recur.
      Suite 80/0 on a clean run. See `docs/meeting-notes/2026-06-22-0317-strong-model-audit.md`.
    - Run 34 (2026-06-22-0712): first-seen change since Run 33's own audit merge `62b58fa`
      (`62b58fa..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0712` / `c95852b`) —
      **LEDGER-ONLY window**: `git diff --name-only 62b58fa..HEAD -- '*.sh' '*.py' '*.js'`
      is EMPTY (the window = two TODO+ROADMAP design-analysis commits, `ca1e5f1` id:7809 +
      `31d854b` id:98f0, plus the Run 33 RELAY_LOG checkpoint paragraph). No code to review,
      no security surface. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT).
      **Design-coherence pass (substantive this run, unlike the pure-vacuity LEDGER runs):**
      the two NEW `[HARD — meeting]` items are internally consistent and well-formed —
      id:7809 (auto-reconcile-on-restart: a `.relayactive`/heartbeat marker + a TIERED
      safe-vs-judgment orphan classifier — auto-integrate clean/green/ledger-only, SURFACE
      BLOCKED/partial/red; the zkm-stt fixture case is cited as live evidence the judgment
      tier is justified; relates 689c/3313/4e14/0902/98f0/194e — no contradiction) and
      id:98f0 (outage-resilient LOCAL loop: the user-corrected three-way bind — cloud
      `/schedule` survives an outage but can't reach local `~/src`/worktrees/fievel; the only
      local-reaching fit, an OS systemd timer running `claude -p "/relay --afk"`, hits the
      headless permission wall the user won't bypass with `--dangerously-skip-permissions`;
      options a–f well-formed, ties to id:2d01 dedicated-OS-user path — coherent). Both
      correctly routed `[HARD — meeting]` per id:78ff lanes and mirrored single-id-two-views
      into ROADMAP. **2 coherence drifts fixed inline** (the recurring Run 4/8/17 class): the
      TODO d5e0 summary still read "3 open ROADMAP items, all HARD" but the window added two
      open HARD (7809/98f0) → corrected to 5; the id:401c MIRROR line still read "Latest ✓
      Run 33" → refreshed to Run 34. Cross-ledger coherent after fix (0 open ROUTINE / 5
      executable HARD — 401c [pool] / 3346 / dba3 [decision-gate] / 7809 / 98f0; de4e DEFERRED
      non-executable; all five open in both ROADMAP+TODO; d5e0 agrees). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0712-strong-model-audit.md`.
    - Run 35 (2026-06-22-0722): first-seen change since Run 34's own merge `40bc011`
      (`40bc011..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0722` / `9702417`) —
      **LEDGER-ONLY window** (Runs 11/12/16/17 class). Sole first-seen change = the Run 34
      strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines); `git diff --name-only
      40bc011..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review, no security
      surface, no new design decision/gate. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/
      REMOVED_ASSERT). The Run 34 RELAY_LOG paragraph is internally consistent (verdict +
      window + suite count + mirror-drift note match its own meeting note + run log).
      Cross-ledger coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] / 3346
      [meeting] / dba3 [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED
      non-executable; all five open in both ROADMAP+TODO; d5e0 agrees, no count drift this
      run). **1 coherence drift fixed inline** (Run 4/8/17 mirror class) — the TODO id:401c
      MIRROR line still read "Latest ✓ Run 34"; refreshed to Run 35. Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0722-strong-model-audit.md`.
    - Run 36 (2026-06-22-0737): first-seen change since Run 35's own merge `69c0bc5`
      (`69c0bc5..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0737` / `c0dece8`) —
      **LEDGER-ONLY window**: `git diff --name-only 69c0bc5..HEAD -- '*.sh' '*.py' '*.js'`
      is EMPTY (window = the new id:f576 TUI ghost-fragment TODO meta-issue `c54c96e`, the
      `-0730` review(relay) LEDGER-ONLY commit+merge `852c58a`/`4f2200d`, plus the
      `-0730`/`-0737` RELAY_LOG checkpoint paragraphs). No code to review, no security
      surface. gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT; no test files
      changed). **Design-coherence pass (substantive):** the new id:f576 entry
      (Claude Code TUI ghost workflow-progress/statusline fragments after exiting
      `/workflows`) is internally consistent and well-formed — correctly classified
      cosmetic (Ctrl+L/SIGWINCH clears it), plausible render-race root cause, routed as an
      external/harness meta-issue with NO executable lane tag → correctly TODO-only (not
      promoted to ROADMAP, not in the d5e0 count); `#1 upgrade past v2.1.181` is sound (box
      runs 2.1.177); `disableWorkflows: true` correctly flagged UNSUITABLE here (relay pool
      depends on the Workflow tool) — no contradiction. RELAY_LOG checkpoint paragraphs
      internally consistent. **1 coherence drift fixed inline** (recurring Run 4/8/17/35
      mirror class) — the TODO id:401c MIRROR line still read "Latest ✓ Run 35"; refreshed
      to Run 36. Cross-ledger coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED
      non-executable; all five open in both ROADMAP+TODO; d5e0 agrees, no count drift this
      run). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 80/0 on a clean run.
      See `docs/meeting-notes/2026-06-22-0737-strong-model-audit.md`.
    - Run 37 (2026-06-22-0942): first-seen change since Run 36's own audit merge `b93f024`
      (`b93f024..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0942` / `183a272`) —
      **SUBSTANTIVE CODE window** (breaks the Run 31/32/33/35/36 ledger-only streak): 403
      insertions / 6 files. First-seen code = the new `relay/scripts/roadmap-archive.sh`
      (id:6b67 [ROUTINE], Relay ROADMAP archiver, 167 L, shipped by a Sonnet executor in
      `f6f594b`) + `tests/test_roadmap_archive.sh` (201 L, 9 hermetic cases, `# roadmap:6b67`)
      + Makefile registration (relay_FILES/EXEC/ALLOW). **CLEAN — no code/security defects**
      across all 3 passes: trap-ordering sound (last EXIT trap cleans both temp+lock, no leak);
      conservative prior-commit/≥30d gate correct — a working-tree-only tick is NEVER archived
      (verified T3 positive / T4 negative); multi-line block capture + `<!-- id:XXXX -->` token
      preservation + no-section-pruning (deliberate divergence from archive-done.sh, ROADMAP
      headers are structural) all verified; quoted `<<'PYEOF'` heredoc with argv-passed inputs
      = no injection, no path traversal beyond the repo, stdlib-only Python, no secrets/network,
      lock covered by the `*.lock` gitignore. gaming-scan clean (test file wholly NEW — additions
      only, no deleted asserts / added skips / removed checks). Design coherent: id:93cc→id:6b67
      single-id-two-views chain sound (93cc = TODO "Prompt is too long" meta-issue, 6b67 =
      fix-direction (b) archiver promoted to ROADMAP; no duplicate-id mint; test maps its item;
      ticked `[x]` ⇒ suite green = DoD). **1 LOW accepted** — `trap 'rm "$LOCK_FILE"'` removes a
      flock'd lock file (unlink-race vs the canonical append.sh/git-lock-push.sh persistent-lock
      pattern); theoretical only — script is `-n` non-blocking (concurrent run cleanly skips),
      has NO automated caller today, rare+idempotent+single-writer; documented future-fix trigger
      (drop the rm if an automated caller is added). **Pre-existing accepted (out of window)** —
      `orphan-scan --cross-ledger` flags id:78ff/id:d9b0 as TODO:[ ]/ROADMAP:[x]; both predate
      this window and are the intended single-id-two-views shape (ROADMAP execution unit closed,
      broader TODO design-ledger umbrella stays open) — not drift from this window. **1 coherence
      drift fixed inline (recurring Run 4/8/17/35/36 mirror class)** — the TODO id:401c MIRROR
      line still read "Latest ✓ Run 36"; refreshed to Run 37 (d5e0 count line NOT stale this run
      — already 5 open HARD / 0 ROUTINE after id:6b67 closed). Cross-ledger coherent (0 open
      ROUTINE / 5 executable HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / 7809
      [meeting] / 98f0 [meeting]; de4e DEFERRED non-executable; all five open in both
      ROADMAP+TODO; d5e0 agrees, no count drift this run). Both tracked flakes (id:16e9, id:05e8)
      did NOT recur. Suite 81/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0942-strong-model-audit.md`.
    - Run 38 (2026-06-22-0953): first-seen change since Run 37's own audit merge `8258aa3`
      (`8258aa3..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0953` / `9ec0b6b`) —
      **clean: LEDGER-ONLY window** (Run 11/12/16/17/31/32/33/35/36 class). Sole first-seen
      change = the Run 37 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --stat` = `RELAY_LOG.md | 4 ++++` and `git diff --name-only 8258aa3..HEAD --
      '*.sh' '*.py' '*.js'` is EMPTY. No code to review (Pass 1 CLEAN by vacuity), no security
      surface (Pass 2 CLEAN by vacuity; `gaming-scan.sh "$repo" 8258aa3` exit 0, no output),
      no new design decision/gate (Pass 3 — the Run 37 checkpoint paragraph is internally
      consistent with the Run 37 run-log entry + meeting note: same window `b93f024..HEAD`,
      same id:6b67 subject, same suite 81/0; no contradiction). **Pre-existing accepted (out
      of window)** — `orphan-scan --cross-ledger` flags id:78ff/id:d9b0 as TODO:[ ]/ROADMAP:[x];
      both predate this window and are the intended single-id-two-views shape (already accepted
      Run 37). **1 coherence drift fixed inline (recurring Run 4/8/17/35/36/37 mirror class)** —
      the TODO id:401c MIRROR line still read "Latest ✓ Run 37"; refreshed to Run 38 (d5e0 count
      line NOT stale this run — already 5 open HARD / 0 ROUTINE, no items opened/closed). Cross-ledger
      coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED non-executable; all five
      open in both ROADMAP+TODO; d5e0 agrees, no count drift this run). Both tracked flakes
      (id:16e9, id:05e8) did NOT recur. Suite 81/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-0953-strong-model-audit.md`.
    - Run 39 (2026-06-22-1004): first-seen change since Run 38's own audit merge `0174a69`
      (`0174a69..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-1004` / `3cb4d7a`) —
      **clean: LEDGER-ONLY window** (Run 11/12/16/17/31/32/33/35/36/38 class). Sole first-seen
      change = the Run 38 strong-execute checkpoint paragraph in RELAY_LOG.md (+4 lines);
      `git diff --stat` = `RELAY_LOG.md | 4 ++++` and `git diff --name-only 0174a69..HEAD --
      '*.sh' '*.py' '*.js'` is EMPTY. No code to review (Pass 1 CLEAN by vacuity), no security
      surface (Pass 2 CLEAN by vacuity; `gaming-scan.sh . 0174a69` exit 0, no output), no new
      design decision/gate (Pass 3 — the Run 38 checkpoint paragraph is internally consistent
      with the Run 38 run-log entry + meeting note: same window `8258aa3..HEAD`, same LEDGER-ONLY
      verdict, same suite 81/0; no contradiction). **Pre-existing accepted (out of window)** —
      `orphan-scan --cross-ledger` flags id:78ff/id:d9b0 as TODO:[ ]/ROADMAP:[x]; both predate
      this window and are the intended single-id-two-views shape (already accepted Run 37/38).
      **1 coherence drift fixed inline (recurring Run 4/8/17/35/36/37/38 mirror class)** — the
      TODO id:401c MIRROR line still read "Latest ✓ Run 38"; refreshed to Run 39 (d5e0 count
      line NOT stale this run — already 5 open HARD / 0 ROUTINE, no items opened/closed).
      Cross-ledger coherent (0 open ROUTINE / 5 executable HARD — 401c [pool] / 3346 [meeting]
      / dba3 [decision-gate] / 7809 [meeting] / 98f0 [meeting]; de4e DEFERRED non-executable;
      all five open in both ROADMAP+TODO; d5e0 agrees, no count drift this run). Both tracked
      flakes (id:16e9, id:05e8) did NOT recur. Suite 81/0 on a clean run. See
      `docs/meeting-notes/2026-06-22-1004-strong-model-audit.md`.
    - Run 40 (2026-06-22-1601): first **CODE** window since Run 39's LEDGER-ONLY runs —
      `3600642..HEAD` (HEAD = `relay-ckpt-20260622-1715` / `10d837e`), ~251 lines / 12 files.
      First-seen code: the id:93cc ROADMAP discovery-trimmer in `gather-repo-state.sh`, the
      id:7d1e per-verdict progress buckets in `relay-loop.js`, and the id:bde8 loop-hint
      resilience-wording correction (`loop-hint.sh` + SKILL.md), plus the id:98f0/7809
      outage-resilience meeting note. **1 forward-robustness defect fixed inline** — the id:93cc
      trimmer's `python3 … 2>/dev/null || true` failed CLOSED to an EMPTY roadmap on a trimmer
      crash → would silently misclassify the repo as `handoff` (relay-loop.js ~L630 "roadmap
      missing") and re-do C1/C2; changed to fail-OPEN `|| cat "$path/ROADMAP.md"` + a non-vacuous
      regression guard in `test_gather_repo_state.sh` (proven RED on the reverted `|| true` form).
      Pass-1 otherwise clean (trimmer block-parsing correct; per-verdict buckets pure display
      grouping, zero behavioural change, consistent with the pre-existing Integrate bucket).
      Pass-2 security clean (`gaming-scan.sh . 3600642` exit 0; no injection — trimmer reads a
      quoted env path, JS changes are literals). Pass-3 design-coherence: loop-hint correction
      matches memory `babysitter-durable-cron-no-op`; verified the meeting note's claimed
      `[HARD — meeting]→[HARD — hands]` retag of 7809/98f0 landed in ROADMAP and that new items
      e149/0994 are wired. **2 coherence drifts fixed inline (recurring d5e0/mirror class)** —
      (a) the d5e0 count line read "5 open ROADMAP items" with 7809/98f0 mislabelled
      `[HARD — meeting]`; corrected to 7 open HARD with e149/0994 added + the lane fix; (b) the
      TODO id:401c MIRROR line read "Latest ✓ Run 39"; refreshed to Run 40. Cross-ledger coherent
      (0 open ROUTINE / 7 open HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] /
      e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; all open in both ROADMAP+TODO).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 82/0 test-files on a clean run
      (the new regression guard is an assertion inside test_gather_repo_state.sh, 17→18 cases).
      See `docs/meeting-notes/2026-06-22-1601-strong-model-audit.md`.
    - Run 41 (2026-06-22-1757): first-seen change since Run 40's own audit merge `f3c26f8`
      (`f3c26f8..HEAD`, HEAD = `relay-ckpt-20260622-1757` / `4574c3b`) — **LEDGER-ONLY window**
      (Runs 11/12/16/17/18/19/20/21/22/40 class). `git diff --name-only f3c26f8..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY — the only code in the raw `10d837e..HEAD` range
      (`gather-repo-state.sh` + `test_gather_repo_state.sh`, `c941c4e`) is Run 40's OWN
      already-audited id:93cc fail-open fix, out of this window. First-seen changes: Run 40's
      strong-execute+review checkpoint paragraphs in RELAY_LOG.md; the Agent-SDK / `claude -p`
      subscription-billing DEFERRAL note (`e06088f` — new TODO `[MEETING]` id:00a5 multi-perspective
      applications eval + a dba3 "Billing path REAFFIRMED" addendum + a 98f0 billing parenthetical);
      and the review tick of TODO id:bde8 `[ ]`→`[x]` (`561c3fa`, cross-ledger D2 fix). No code to
      review, no security surface (`gaming-scan.sh . f3c26f8` exit 0). Pass-3 design-coherence:
      id:00a5 is internally sound (single TODO-only token, meeting-lane → correctly NOT promoted to
      ROADMAP; cross-refs id:2d01/98f0/dba3/hermes-deferral-contract all resolve), the billing notes
      across dba3/98f0/00a5/memory `anthropic-agent-sdk-billing-deferred` are mutually consistent (no
      contradiction with id:2d01's path-A rationale), and bde8 is now canonically `[x]` in both
      ledgers. **One coherence drift fixed inline (recurring mirror class, Run 4/8/17/21/40)** — the
      TODO id:401c MIRROR line read "Latest ✓ Run 40"; refreshed to Run 41. The d5e0 count line needed
      NO change (already 7 open HARD / 0 ROUTINE; no items opened/closed this window). Cross-ledger
      coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; all open in both
      ROADMAP+TODO). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 82/0 on a clean run.
      See `docs/meeting-notes/2026-06-22-1757-strong-model-audit.md`.
    - Run 42 (2026-06-22-1818): first-seen change since Run 41's own audit merge `b65ba59`
      (`b65ba59..HEAD`, HEAD = `relay-ckpt-20260622-1818` / `00f54cf`) — **LEDGER-ONLY window**
      (Runs 11/12/16/17/18/19/20/21/22/40/41 class). `git diff --name-only b65ba59..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY. Sole first-seen change = the 4-line Run 41 strong-execute checkpoint
      paragraph in RELAY_LOG.md (`00f54cf`). No code to review, no security surface
      (`gaming-scan.sh . b65ba59` exit 0). Pass-3 design-coherence: the checkpoint paragraph
      accurately mirrors Run 41 (LEDGER-ONLY, CLEAN by vacuity, suite 82/0, 1 mirror-line drift);
      no item opened/closed this window. **One coherence drift fixed inline (recurring mirror
      class, Run 4/8/17/40/41)** — the TODO id:401c MIRROR line read "Latest ✓ Run 41"; refreshed
      to Run 42. The d5e0 count line needed NO change (already 7 open HARD / 0 ROUTINE).
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED
      non-executable; all open in both ROADMAP+TODO). Both tracked flakes (id:16e9, id:05e8) did
      NOT recur. Suite 82/0 on a clean run. See `docs/meeting-notes/2026-06-22-1818-strong-model-audit.md`.
    - Run 43 (2026-06-22-1827): first-seen change since Run 42's own audit commit `a56bed7`
      (`a56bed7..HEAD`, HEAD = `relay-ckpt-20260622-1827` / `9db884a`) — **LEDGER-ONLY window**
      (Runs 11/12/16/17/18/19/20/21/22/40/41/42 class). `git diff --name-only a56bed7..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY. Sole first-seen change = the 4-line Run 42 strong-execute checkpoint
      paragraph in RELAY_LOG.md (`9db884a`). No code to review, no security surface
      (`gaming-scan.sh . a56bed7` exit 0). Pass-3 design-coherence: the checkpoint paragraph
      accurately mirrors Run 42 (LEDGER-ONLY, CLEAN by vacuity, suite 82/0); no item opened/closed
      this window. **One coherence drift fixed inline (recurring mirror class, Run 4/8/17/40/41/42)**
      — the TODO id:401c MIRROR line read "Latest ✓ Run 42"; refreshed to Run 43. The d5e0 count
      line needed NO change (already 7 open HARD / 0 ROUTINE).
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED
      non-executable; all open in both ROADMAP+TODO). Both tracked flakes (id:16e9, id:05e8) did
      NOT recur. Suite 82/0 on a clean run. See `docs/meeting-notes/2026-06-22-1827-strong-model-audit.md`.
    - Run 44 (2026-06-23-0701): first-seen code since Run 43's own audit commit `c66c6f4`
      (`c66c6f4..HEAD`, HEAD = `relay-ckpt-20260622-2215` / `e5962f3`) — **REAL CODE window**
      (not LEDGER-ONLY): id:bae5 uv.lock-cascade exemptions (`gather-repo-state.sh`
      `lock_only_unaudited`/`dirty_lock_only` + relay-loop.js review/dirty exemptions),
      id:e107 EXECUTOR-ACTIONABLE @manual/human-only guard (relay-loop.js), id:2c42 deferred
      ledger write-back (meeting/SKILL.md + todo-update/SKILL.md + .gitignore + red→green spec).
      **CLEAN — no inline code/security fix.** Pass-1: bae5's lock booleans diff the SAME
      `latest..HEAD` range as `commits_since` (can't disagree with the review verdict), use a
      fixed-string whole-line `grep -vx 'uv.lock'` (root-only, conservative), all new pipelines
      `set -e`-safe (`|| true` + `[[ ]]`); `$NF` porcelain extraction correct for modify/rename;
      e107 mirrors the EXECUTABLE-HARD gate pattern (id:2d20) — no-op-execute thrash rationale
      sound. Pass-2: gather additions pure-read (no eval/injection/secrets); bae5 dirty-lock
      auto-commit is a bounded named git op on a trusted relay.toml path; id:2c42 replay applies
      only under a FRESH claim via allowlisted flock'd helpers. Pass-3: bae5/e107 slot cleanly
      into the documented precedence (no never-firing gate, no contradiction); id:2c42 matches
      its acceptance verbatim (generic breadcrumb wired only at step 2a, replay in both /meeting
      + /todo-update, gitignore entry); af04 note records the worktree-per-/meeting rejection.
      `gaming-scan.sh . c66c6f4` exit 0. **One coherence drift fixed inline (recurring mirror
      class, Run 4/8/17/40/41/42/43)** — the TODO id:401c MIRROR line read "Latest ✓ Run 43";
      refreshed to Run 44. The d5e0 count line needed NO change (already 7 open HARD / 0 ROUTINE;
      the id:2c42 ROUTINE item closed this window). Cross-ledger coherent (0 open ROUTINE / 7 open
      executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] /
      e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; all open in both ROADMAP+TODO).
      Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite 83/0 on a clean run. See
      `docs/meeting-notes/2026-06-23-0701-strong-model-audit.md`.
    - Run 45 (2026-06-23-0939): first-seen code since Run 44's own audit commit `0e60f1f`
      (`0e60f1f..HEAD`, HEAD = `relay-ckpt-20260623-0923` / `6dbecf9`) — **REAL CODE window**:
      id:000d deterministic `is_finished` guard (gather-repo-state.sh + relay-loop.js),
      id:1d64 margin-aware quota-stop staleness, id:3c0f `[HARD — pool]` token sync,
      id:69ef install-manifest completeness guard; id:09a3 (`roadmap-lint.sh`) shipped only
      its RED spec `tests/test_roadmap_lint.sh` (script not yet written) — correctly
      EXPECTED-RED, item still open. **1 HIGH defect FIXED INLINE (id:000d):** the JS-side
      `is_finished` demote guard was DEAD code — `DISCOVER_SCHEMA.units[]` did not declare
      `is_finished` and the shard-prompt per-repo-fields list never instructed copying it, so
      the deterministic value computed by gather-repo-state.sh never reached the unit object
      (the JS reads `u.is_finished`, which was always `undefined`). The only live path was the
      non-deterministic LLM shard-prompt instruction — exactly the path id:000d's backstop
      existed to correct; the pre-existing structural test passed because it grepped the guard
      TEXT, not its behaviour. Fixed: declared the schema property, added an explicit "COPY
      is_finished verbatim" prompt line, and added two non-vacuous assertions to
      `test_relay_loop_structure.sh` (schema declares it + prompt instructs the copy) that fail
      on the pre-fix form. Pass-1 otherwise CLEAN: id:1d64 moved `decay_threshold`/`bucket_threshold`
      earlier so they're defined before the new stale-margin block calls them (correct ordering),
      margin math + missing-bucket→exit2 sound; id:3c0f/69ef pure literal/positive-grammar checks.
      Pass-2: no new injection/traversal/secrets (`awk -v` + `${!envname}` read fixed-domain
      provider/bucket inputs; is_finished block pure-read). Pass-3: the guard now closes its own
      loop (deterministic value → unit → JS backstop), demote-only invariant intact, no
      contradiction with the bae5 lock-only-dirty exemption. `gaming-scan.sh . d068334` exit 0.
      **Mirror drift fixed inline (Run 4/8/17/… class)** — TODO id:401c MIRROR line read "Latest
      ✓ Run 44"; refreshed to Run 45. Cross-ledger coherent (0 open ROUTINE after 000d/1d64/3c0f/69ef
      closed this window; open executable-or-gated HARD: 09a3 [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149/7809/98f0/0994 [hands]; de4e DEFERRED non-executable; the d5e0 prose
      enumeration is slated for dissolution under id:1de1/659c and still predates id:09a3 — left
      as-is, not re-enumerated, since 09a3's re-dispatch is suppressed and the count authority is
      moving to the id:2840 index). Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite
      87/0 + 1 EXPECTED-RED (id:09a3) on a clean run. See
      `docs/meeting-notes/2026-06-23-0939-strong-model-audit.md`.
    - Run 46 (2026-06-23-0945): `d342839..HEAD` (window start = Run 45's audit-note
      commit) — **LEDGER-ONLY, CLEAN by vacuity**. Only commits: `b2b6ee9` (the `--no-ff`
      merge LANDING Run 45's already-audited work — not re-audited) + `1d4b9cb` (checkpoint,
      RELAY_LOG +4). `git diff d342839..HEAD` excluding RELAY_LOG/relay.toml is EMPTY → no
      first-seen code (passes 1+2 N/A). **One coherence finding, fixed inline:**
      `orphan-scan --cross-ledger` flagged id:3c0f/69ef (TODO:[ ] vs ROADMAP:[x]) — a
      scope-split FALSE-POSITIVE (id:d9b0 §3 class): both builds genuinely closed in
      ROADMAP/Run 45; their tokens appear in TODO only inside the still-open umbrella
      line-34 ("lane-token drift + grammar lint", pending id:09a3). Added the
      `<!-- xledger-ok: ... -->` annotation id:d9b0 built for exactly this → cross-ledger
      now exits clean. id:09a3 NOT annotated (still open in ROADMAP too, parked orphan, no
      divergence). gaming-scan `"$PWD" d342839` exit 0; suite 87/0 + 1 EXPECTED-RED (id:09a3).
      Mirror: TODO id:401c line refreshed Run 45→Run 46. See
      `docs/meeting-notes/2026-06-23-0945-strong-model-audit.md`.
    - Run 48 (2026-06-23-1730): first-seen code since Run 46's own audit commit `993d905`
      (merge `80a8441..HEAD`) — **REAL CODE** (Run 47 review shipped id:ad74 + id:09a3 in
      this window, never strong-audited). **1 HIGH defect fixed inline**: the id:ad74
      JS-side INTENSIVE promote backstop in relay-loop.js was a NO-OP — the exact symmetric
      twin of the id:401c Run 45 dead-guard bug, in the very feature meant to be the PROMOTE
      counterpart of that DEMOTE guard. Branch 1 (skipped→unit) was provably-dead code
      (`top_intensive && !u` unreachable; skipped rollup items carry no `top_intensive`);
      branch 2 patched an idle unit's `.intensive` but never flipped `verdict` off `'idle'`,
      so `actionable = units.filter(u => u.verdict !== 'idle')` dropped it BEFORE the
      INTENSIVE partition — silent drop, not even surfaced as deferred. Rewrote to operate
      on emitted units only and FLIP idle→execute (survives the filter → intensive partition
      → `ALLOW_INTENSIVE ? intensiveUnits : intensiveDeferred`); dropped the dead branch.
      Added non-vacuous static guards (2c)/(2d) to `test_relay_loop_intensive_emit.sh`
      (verified: both FAIL against pre-fix JS, pass against fix). roadmap-lint.sh (id:09a3)
      + gather `top_intensive` field clean; lint correctly wired into review §5 + human. 1
      coherence ACCEPTED (c3a6 cache: `top_intensive` is a pure fn of the already-hashed
      ROADMAP blob → no sig change). Cross-ledger drift fixed inline (id:ad74 TODO:[ ] vs
      ROADMAP:[x] — build now genuinely complete post-fix → ticked the TODO twin). gaming-scan
      `"$PWD" 80a8441` exit 0; suite 89/0/0. Mirror: TODO id:401c refreshed Run 46→Run 48
      (Run 47 was the review that shipped this window, not an audit run). See
      `docs/meeting-notes/2026-06-23-1730-strong-model-audit.md`.
    - Run 49 (2026-06-23-1749): first-seen change since Run 48's own audit merge `7dfe7e0`
      (`7dfe7e0..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46 class). Sole
      first-seen change = the Run 48 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only 7dfe7e0..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. The RELAY_LOG
      paragraph is internally consistent (Run 48 verdict + suite 89/0/0 + the id:ad74 fix).
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] /
      3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED
      non-executable; all open in both ROADMAP+TODO; d5e0 agrees). roadmap-lint.sh exit 0;
      gaming-scan `"$PWD" 7dfe7e0` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT
      recur. Mirror: TODO id:401c line refreshed Run 48→Run 49. See
      `docs/meeting-notes/2026-06-23-1749-strong-model-audit.md`.
    - Run 50 (2026-06-23-1724): first-seen change since Run 49's own audit merge `12b151e`
      (`12b151e..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49 class). Sole
      first-seen change = the Run 49 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only 12b151e..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. The RELAY_LOG
      paragraph is internally consistent (Run 49 verdict + roadmap-lint 0/gaming-scan 0/suite
      89/0/0). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c
      [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan
      --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 12b151e` exit 0;
      suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line
      refreshed Run 49→Run 50. See `docs/meeting-notes/2026-06-23-1724-strong-model-audit.md`.
    - Run 51 (2026-06-23-1724b): first-seen change since Run 50's own audit merge `b46be9a`
      (`b46be9a..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50 class). Sole
      first-seen change = the Run 50 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only b46be9a..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY (verified
      the earlier `efbb7bd` id:d530 TODO note is an ancestor of `b46be9a` — covered by Run 50,
      not first-seen). No code to review, no security surface, no new design decision/gate. The
      RELAY_LOG paragraph is internally consistent (Run 50 verdict + roadmap-lint 0/gaming-scan
      0/suite 89/0/0). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD —
      401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan
      --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" b46be9a` exit 0;
      suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line
      refreshed Run 50→Run 51. See `docs/meeting-notes/2026-06-23-1724b-strong-model-audit.md`.
    - Run 52 (2026-06-23-1724c): first-seen change since Run 51's own audit merge `9dfce93`
      (`9dfce93..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51 class). Sole
      first-seen change = the Run 51 strong-execute checkpoint paragraph in RELAY_LOG.md
      (+4 lines); `git diff --name-only 9dfce93..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No
      code to review, no security surface, no new design decision/gate. The RELAY_LOG
      paragraph is internally consistent (Run 51 verdict + orphan-scan/roadmap-lint/gaming-scan
      0/suite 89/0/0). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD —
      401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan
      --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9dfce93` exit 0;
      suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line
      refreshed Run 51→Run 52. See `docs/meeting-notes/2026-06-23-1724c-strong-model-audit.md`.
    - Run 53 (2026-06-23-1724d): first-seen change since Run 52's own audit merge `8052b4f`
      (`8052b4f..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52 class).
      Window = the Run 52 strong-execute checkpoint paragraph in RELAY_LOG.md (+4) AND one new
      TODO discussion item, id:9000 (`[HARD — meeting]` inter-session coordination channel, +1);
      `git diff --name-only 8052b4f..HEAD -- '*.sh' '*.py' '*.js'` is EMPTY. No code to review,
      no security surface. Coherence pass on the sole new design artifact (TODO id:9000):
      `[HARD — meeting]` lane correct for a discussion placeholder; every cross-reference
      resolves to a real, consistent item (id:0902/ebfb lease / id:c144 ledger-lease-exempt /
      id:2c42 deferred write-back / id:c012 `/relay stop` / id:98f0/e149 watchdog heartbeat);
      observe-first gate (≥2–3 recurrences, FIRST logged instance) intact, no contradiction
      with the af04 worktree-per-meeting rejection — sound entry, no defect. Cross-ledger
      coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting]
      / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger exit 0;
      roadmap-lint.sh exit 0; gaming-scan `"$PWD" 8052b4f` exit 0; suite 89/0/0. Tracked flakes
      16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed Run 52→Run 53. See
      `docs/meeting-notes/2026-06-23-1724d-strong-model-audit.md`.
    - Run 54 (2026-06-23-1909): first-seen change since Run 53's own audit merge `e905c84`
      (`e905c84..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53 class).
      Window = two RELAY_LOG checkpoint paragraphs (Run 53 strong-execute 18:38 + reviewer
      doc-only 18:51, +8) AND one in-place TODO edit to id:9000 (the UPDATE 2026-06-23
      incident-resolved urgency-reframe, ±1); `git diff --name-only e905c84..HEAD -- '*.sh'
      '*.py' '*.js'` is EMPTY. No code to review, no security surface. Coherence pass on the
      sole new design artifact (id:9000 reframe): correctly narrows scope from "prevent
      corruption" (now redundant) to "avoid wasted stale-base work + surface intent" because
      the cited backstop **id:aa93** (dirty-main-checkout guard, ROADMAP `[x]` shipped
      2026-06-18 — clean-tree-gate.sh in integrate step 1) RESOLVES and supports the claim;
      observe-first gate STRENGTHENED ("the backstop held"), every original cross-ref
      preserved + resolves, lane tag unchanged — sound entry, no defect. Cross-ledger
      coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting]
      / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      all open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger exit 0;
      roadmap-lint.sh exit 0; gaming-scan `"$PWD" e905c84` exit 0; suite 89/0/0. Tracked flakes
      16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed Run 53→Run 54. See
      `docs/meeting-notes/2026-06-23-1909-strong-model-audit.md`.
    - Run 55 (2026-06-23-1724e): window = since Run 54's audit merge `2cd8d6e`
      (`2cd8d6e..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54
      class). `git diff --name-only 2cd8d6e..HEAD` = only RELAY_LOG.md + TODO.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Window = three RELAY_LOG checkpoint paragraphs
      (8e041af reviewer 18:51, 92addcb strong-execute 19:13 = Run 54's own ckpt, 4ee6ffd
      reviewer 19:40) AND one `todo(meeting)` commit (8679992) minting two new
      design-deferred TODO items. No code → no Pass-1/Pass-2 surface (clean by vacuity).
      Pass-3 coherence on the sole new design artifact: id:74c7 (`/meeting --cross` inline
      path skips canonical persona-load setup) + id:d23f (same inline path skips the
      EnterPlanMode→ExitPlanMode approval gate) — both minted, sharply scoped to an
      explicit a-vs-b decision (re-dispatch-always vs carry-scaffolding), correctly
      cross-referenced (id:1d01 distinguished, id:d44d, id:a6cb, each other), cite the
      source zkm meeting note, and correctly TODO-parked (design judgment needed, not
      ROADMAP-promotable). id:d23f correctly carves out the by-design Class-3
      decisions→ledger deferral as NOT-the-bug. No contradiction, no dead gate, no defect.
      Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated HARD — 401c [pool]
      / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e
      DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees).
      orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 2cd8d6e`
      exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c
      line refreshed Run 54→Run 55. See `docs/meeting-notes/2026-06-23-1724e-strong-model-audit.md`.
    - Run 56 (2026-06-23-2024): window = since Run 55's audit merge `578c854`
      (`578c854..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55
      class). `git diff --name-only 578c854..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `ca4a743` (checkpoint 20260623-2001
      strong-execute) adds one RELAY_LOG paragraph = Run 55's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 578c854` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 55→Run 56. See `docs/meeting-notes/2026-06-23-2024-strong-model-audit.md`.
    - Run 57 (2026-06-23-2031): window = since Run 56's audit merge `9782379`
      (`9782379..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56
      class). `git diff --name-only 9782379..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `2b60f5f` (checkpoint 20260623-2011
      strong-execute) adds one RELAY_LOG paragraph = Run 56's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9782379` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 56→Run 57. See `docs/meeting-notes/2026-06-23-2031-strong-model-audit.md`.
    - Run 58 (2026-06-23-2037): window = since Run 57's audit merge `9b2abd7`
      (`9b2abd7..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57
      class). `git diff --name-only 9b2abd7..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `3813fef` (checkpoint 20260623-2021
      strong-execute) adds one RELAY_LOG paragraph = Run 57's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9b2abd7` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 57→Run 58. See `docs/meeting-notes/2026-06-23-2037-strong-model-audit.md`.
    - Run 59 (2026-06-23-2040): window = since Run 58's audit merge `c8d4469`
      (`c8d4469..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58
      class). `git diff --name-only c8d4469..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `8d8838d` (checkpoint 20260623-2029
      strong-execute) adds one RELAY_LOG paragraph = Run 58's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" c8d4469` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 58→Run 59. See `docs/meeting-notes/2026-06-23-2040-strong-model-audit.md`.
    - Run 60 (2026-06-23-2044): window = since Run 59's audit merge `73e4903`
      (`73e4903..daf5694`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59
      class). `git diff --name-only 73e4903..daf5694` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `daf5694` (checkpoint 20260623-2038
      strong-execute) adds one RELAY_LOG paragraph = Run 59's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 73e4903` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 59→Run 60. See `docs/meeting-notes/2026-06-23-2044-strong-model-audit.md`.
    - Run 61 (2026-06-23-2054): window = since Run 60's audit merge `9da3a6f`
      (`9da3a6f..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59/60
      class). `git diff --name-only 9da3a6f..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `a4d670b` (checkpoint 20260623-2047
      strong-execute) adds one RELAY_LOG paragraph = Run 60's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 9da3a6f` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 60→Run 61. See `docs/meeting-notes/2026-06-23-2054-strong-model-audit.md`.
    - Run 62 (2026-06-23-2102): window = since Run 61's audit merge `91d639a`
      (`91d639a..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59/60/61
      class). `git diff --name-only 91d639a..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `564f217` (checkpoint 20260623-2056
      strong-execute) adds one RELAY_LOG paragraph = Run 61's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" 91d639a` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 61→Run 62. See `docs/meeting-notes/2026-06-23-2102-strong-model-audit.md`.
    - Run 63 (2026-06-23-2110): window = since Run 62's audit merge `a360ac6`
      (`a360ac6..HEAD`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49/50/51/52/53/54/55/56/57/58/59/60/61/62
      class). `git diff --name-only a360ac6..HEAD` = only RELAY_LOG.md;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `e7d7e4f` (checkpoint 20260623-2104
      strong-execute) adds one RELAY_LOG paragraph = Run 62's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" a360ac6` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 62→Run 63. See `docs/meeting-notes/2026-06-23-2110-strong-model-audit.md`.
    - Run 64 (2026-06-23-1724f): `c8127e0..HEAD` (HEAD `69dd4d8`) — **LEDGER-ONLY clean
      by vacuity**. `git diff --name-only c8127e0..HEAD` = only `RELAY_LOG.md`;
      `*.sh`/`*.py`/`*.js` diff EMPTY. Sole commit `69dd4d8` (checkpoint 20260623-2113
      strong-execute) adds one RELAY_LOG paragraph = Run 63's own checkpoint record. No
      code → no Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design
      item, gate, or contract change → no Pass-3 artifact. Cross-ledger coherent (0 open
      ROUTINE / 7 open executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3
      [decision-gate] / e149 / 7809 / 98f0 / 0994 [hands]; de4e DEFERRED non-executable;
      401c/3346/dba3 open in both ROADMAP+TODO; d5e0 agrees). orphan-scan --cross-ledger
      exit 0; roadmap-lint.sh exit 0; gaming-scan `"$PWD" c8127e0` exit 0; suite 89/0/0.
      Tracked flakes 16e9/05e8 did NOT recur. Mirror: TODO id:401c line refreshed
      Run 63→Run 64. See `docs/meeting-notes/2026-06-23-1724f-strong-model-audit.md`.
    - Run 65 (2026-06-23-1724g): window = since Run 64's audit merge `69dd4d8`
      (`69dd4d8..HEAD`, HEAD `17c062f`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49–64
      class). `git diff --name-only 69dd4d8..HEAD` = RELAY_LOG.md + ROADMAP.md + TODO.md + the
      Run 64 meeting note (all Run 64's own audit + checkpoint ledger writes);
      `*.sh`/`*.py`/`*.js` diff EMPTY. Commits = `34c8a1c` (Run 64 audit), `417321f` (its
      merge), `17c062f` (checkpoint 20260623-2123 = Run 64's own record). No code → no
      Pass-1/Pass-2 surface (clean by vacuity); no new TODO/ROADMAP design item, gate, or
      contract change → no Pass-3 artifact (Run 64's own ledger records are internally
      consistent: its verdict + cited gates match this run's re-verification; TODO mirror
      Run 63→64 correct). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated
      HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994
      [hands]; de4e DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO; d5e0
      agrees). orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan
      `"$PWD" 69dd4d8` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror:
      TODO id:401c line refreshed Run 64→Run 65. See
      `docs/meeting-notes/2026-06-23-1724g-strong-model-audit.md`.
    - Run 66 (2026-06-23-1724h): window = since Run 65's audit commit `9330f72`
      (`9330f72..HEAD`, HEAD `62fc2c7`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49–65
      class). `git diff --name-only 9330f72..HEAD` = RELAY_LOG.md only (Run 65's own checkpoint
      paragraph); `*.sh`/`*.py`/`*.js` diff EMPTY. Commits = `5b1e0a4` (Run 65 merge), `62fc2c7`
      (checkpoint 20260623-2132 = Run 65's own record). No code → no Pass-1/Pass-2 surface (clean
      by vacuity); no new TODO/ROADMAP design item, gate, or contract change → no Pass-3 artifact
      (Run 65's own RELAY_LOG paragraph is internally consistent: its verdict + cited gates match
      this run's re-verification). Cross-ledger coherent (0 open ROUTINE / 7 open executable-or-gated
      HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 / 98f0 / 0994
      [hands]; de4e DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO; d5e0
      agrees). orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan
      `"$PWD" 9330f72` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror:
      TODO id:401c line refreshed Run 65→Run 66. See
      `docs/meeting-notes/2026-06-23-1724h-strong-model-audit.md`.
    - Run 67 (2026-06-23-2145): window = since Run 66's audit commit `a689119`
      (`a689119..HEAD`, HEAD `5e1a216`) — **clean: LEDGER-ONLY window** (Run 11/12/16/17/46/49–66
      class). `git diff --name-only a689119..HEAD` = RELAY_LOG.md only (Run 66's own checkpoint
      paragraph, +4 lines); `*.sh`/`*.py`/`*.js` diff EMPTY. Commits = `b8cda3c` (Run 66 merge),
      `5e1a216` (checkpoint 20260623-2140 = Run 66's own record). No code → no Pass-1/Pass-2 surface
      (clean by vacuity); no new TODO/ROADMAP design item, gate, or contract change → no Pass-3
      artifact (Run 66's own RELAY_LOG paragraph is internally consistent: its verdict + cited checks
      match this run's re-verification). Cross-ledger coherent (0 open ROUTINE / 7 open
      executable-or-gated HARD — 401c [pool] / 3346 [meeting] / dba3 [decision-gate] / e149 / 7809 /
      98f0 / 0994 [hands]; de4e DEFERRED non-executable; 401c/3346/dba3 open in both ROADMAP+TODO;
      d5e0 agrees). orphan-scan --cross-ledger exit 0; roadmap-lint.sh exit 0; gaming-scan
      `"$PWD" a689119` exit 0; suite 89/0/0. Tracked flakes 16e9/05e8 did NOT recur. Mirror:
      TODO id:401c line refreshed Run 66→Run 67. See
      `docs/meeting-notes/2026-06-23-2145-strong-model-audit.md`.
    - Run 69 (2026-06-30-1855): window = `8d8d40b..HEAD` (HEAD `7527cb1`), since Run 68 —
      133 commits / ~6007 insertions across 88 files; substantive engine surface ~21
      scripts+code files + tests (`substantive_unaudited=true`). Four days of mechanical-classifier
      (id:4d8e) + outage-resilience build: NEW classify-verdict.sh (85df), classify-repo.sh (3f0f),
      backtest-verdict.py (5f93), decision-queue.sh (de31), drain.mjs (d58f), heartbeat.sh (e149),
      host-gate.sh (43b9), memory-append.sh (6f61), pathspec-drop-guard.py (b67e), relay-watchdog
      (98f0); MODIFIED relay-loop.js (drain/heartbeat/phase-buckets/worked_ids/quota-extrapolation),
      gather-repo-state.sh + classify-repo.sh execve-overflow temp-file fix (07be/3f0f), claim.sh
      heartbeat-gated liveness (33d3), scan-routed --apply (678e), ckpt-tag graceful degrade (a7a3).
      **Pass-1 code review CLEAN** + **Pass-2 security CLEAN** (no correctness/injection defects —
      verified classify-verdict pure-stdin parity-guards, execve temp-file fixes, heartbeat
      ts+TTL, claim fail-safe heartbeat gate, decision-queue set-e-safe resolve, drain.mjs
      byte-identical inline copy, scan-routed idempotent flock'd write, per-round heartbeat keyed on
      stable state.runId). **Pass-3: 2 ledger drifts FIXED INLINE** — (1) id:1bbd `[x]` ROADMAP /
      `[ ]` TODO (lane-anchor fix shipped+merged → ROADMAP authoritative; ticked the TODO twin);
      (2) d5e0 count prose listed the shipped e149/7809/98f0/0994 [HARD — hands] batch as open —
      re-derived to 3 open executable-or-gated (401c [pool] / 3346 [meeting] / dba3 [decision-gate];
      de4e [meeting] DEFERRED). orphan-scan --cross-ledger now 0; roadmap-lint 0; gaming-scan
      `"$PWD" 8d8d40b` 0; todo-conformance 0; suite 135/0/0. 3 accepted-not-defect items (scan-routed
      inbox-done swallow + new-id fallback, pathspec-guard conservative-block). See
      `docs/meeting-notes/2026-06-30-1855-strong-model-audit.md`.
    - Run 68 (2026-06-26-0926): window = `5e1a216..HEAD` (HEAD `8d8d40b`), since Run 67 —
      **first NON-ledger window since Run 48** (`substantive_unaudited=true`): ~4091/-50 across
      35 files (14 scripts + 21 tests), three days of relay-engine work (id:5c00 quota pre-gate,
      c012 graceful-stop, d530 --priority/--exclude, 9973 HARD-pool demote-guard, 365b
      recurring-audit gate + circuit breaker, a707 human-gated INTENSIVE carve-out, 1b11 PID
      claim, 9221 orphan first-wins, c095 heading-as-item, a643 resource claim, 2147 atomic
      ledger commit, 71f2 workflow-template lint, 3441 todo-conformance, 678e scan-routed,
      2dea unpromoted-scan, relay-doctor). **Pass-1 code review CLEAN** (no correctness defects —
      verified commit-ledger scoped-add+escape-reject, todo-conformance stable-lineno --fix +
      duplicate-mint guard, gather substantive_unaudited fail-open + deterministic work_sig,
      relay-loop demote/breaker/pre-gate all demote-only+injected-exempt, the
      lint-workflow-templates single-pass lexer). **Pass-2 security CLEAN** (sed/jq/path/PID
      surfaces: 4-hex id validation before sed, realpath `../*|/*` reject, `jq -n --arg`,
      numeric-only `kill -0` with documented conservative PID-reuse caveat). **Pass-3: 1
      cross-ledger drift FIXED INLINE** — id:5c00 was `[x]` in ROADMAP but `[ ]` in TODO (work
      genuinely done+merged → ROADMAP authoritative); ticked the TODO twin, orphan-scan
      --cross-ledger now exit 0. todo-conversion-policies.md v1 + the 9973/365b/a707/000d guard
      lattice internally coherent. **Accepted (not a defect):** gaming-scan
      `ADDED_SKIP:test_relay_doctor_wiring.sh:60` = benign false-positive (the regex
      `report.only` substring tripped the heuristic on a real report-only assertion).
      roadmap-lint exit 0; todo-conformance exit 0; gaming-scan `"$PWD" 5e1a216` exit 0;
      suite 106/1/0 — the 1 failure is the KNOWN flaky `test_resource_claim_pid.sh` (id:ab5c),
      passed 3/3 in isolation → effectively 107 green. Mirror: TODO id:401c line refreshed
      Run 67→Run 68. See `docs/meeting-notes/2026-06-26-0926-strong-model-audit.md`.

- [ ] [INPUT — meeting] Sub-agent meeting simulation for main-ctx isolation <!-- id:3346 -->
  - **Why HARD**: architectural — moves the whole meeting transcript generation out
    of the main context into a sub-agent; touches broker contract, persona loading,
    decision routing, and note-writing; wrong cut loses the user's live view.
  - **Acceptance**: see TODO id:3346. **GATED — do not start**: gate is "opencode
    port validated (proves broker contract is stable) + ≥1 meeting with ctx > 200k".
    Listed here for visibility only; remains parked in TODO.md until the gate fires.

## Capability-keyed lane taxonomy — slice A (meeting 2026-07-02-1924)

Slice A of the capability-keyed lane taxonomy + mechanical-run daemon
(`docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md`).
**Additive only** — introduces the `[MECHANICAL]` capability tier, its recipe/permit/probe
substrate, and the check-and-defer resource arbitration, WITHOUT renaming any existing lane
(the `[HARD — *]`→new-vocab rename is slice B, GATED below). Single-id-two-views (D2): every
id reuses its open TODO.md twin under the `[UMBRELLA]`.

## Capability-keyed lane taxonomy — wave 2a (MECHANICAL end-to-end)

Wave 2a makes the `[MECHANICAL]` tag END-TO-END: slice A shipped the CONSUMER half only
(the classifier RECOGNIZES `[MECHANICAL]`→the pool-inert `mechanical` verdict), but no
relay layer PRODUCES the tag and nothing RUNS it. Source of truth: the
`## Amendment 2026-07-02 (post-build — the `[MECHANICAL]` producer gap)` section of
`docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md`. These
three items (single-id-two-views D2 — each reuses its open TODO.md twin) are UN-GATED —
their deps (A1 id:7616, A2 id:64d3, A4 id:e407, A5 id:68dc) are all landed `[x]`. Uses the
CURRENT lane vocabulary (`[ROUTINE]`/`[HARD — pool]`) — the two-axis rename is wave 2b
(B1/B2, GATED below), NOT here.

## Capability-keyed lane taxonomy — wave 2b (lane-vocabulary RENAME)

Wave 2b executes the `[HARD — <suffix>]` → two-axis-vocabulary RENAME ratified in the meeting
(`docs/meeting-notes/2026-07-02-1924-relay-mechanical-lane-capability-taxonomy.md`, decisions
1+2). **This is the meeting's flagged BLAST-RADIUS step** — the lane vocabulary was hardened
four days ago across ~30 lane-asserting tests + the crash-prone `relay-loop.js` engine, so the
rename is deliberately staged **additive-then-flip** with a deterministic converter and a
DUAL-VOCABULARY lint window (both old and new accepted ERROR-free for one window). NEVER a
flag-day (Riku). Dep A1 (id:7616, `[MECHANICAL]` tag) is landed `[x]`, so B1 is now UN-GATED
and dispatchable; B2 stays gated on B1 (below). Single-id-two-views (D2): both ids reuse their
open TODO.md twin.

**Target taxonomy (decision 1).** Two orthogonal axes — **capability**: `[ROUTINE]` (executor
LLM) · `[HARD]` (strong LLM) · `[INPUT — {meeting,decision,access}]` (human ± LLM; sub-type =
effort) · `[MECHANICAL]` (compute only) — × **resource** (orthogonal): `[INTENSIVE — <res>]`.
The MAPPING: the THREE UNAMBIGUOUS 1:1 renames the converter AUTO-APPLIES — `[HARD — pool]`→`[HARD]`,
`[HARD — meeting]`→`[INPUT — meeting]`, `[HARD — decision gate]`→`[INPUT — decision]`. `[HARD — hands]`
is DELIBERATELY NOT auto-converted: "hardware/sudo/secret/on-device/rehearsal" fragments across FOUR
destinations — `[MECHANICAL]` (a daemon can run it) · `[INPUT — access]` (human provides a
credential/key/physical access) · `[INPUT — decision]` (human must ratify, e.g. it-infra fd30
post-gate decisions) · `[INPUT — meeting]` (human+LLM design judgment, e.g. a rehearsal whose
outcome needs interpretation) — so the converter FLAGS every `[HARD — hands]` item for per-item
human judgment (those four candidates) and converts it to NONE of them (no default). Aligns with M3
(id:3ef7) + the conformance-sweep detector-surfaces/human-decides rule. `[ROUTINE]` / `[MECHANICAL]`
/ `[INTENSIVE — <res>]` are UNCHANGED. **SCOPE (owner-locked):** this wave
migrates THIS repo's contract + lane-readers + tests + THIS repo's own ROADMAP/TODO item tags
only. Cross-repo item re-tagging in OTHER repos is a SEPARATE gated migration — the dual-vocab
window is exactly what lets those migrate later.

### GATED — B2 migration (DEP: 4f02, NOT dispatchable until B1 lands)

Parked under a GATED heading (roadmap-lint-exempt, non-dispatchable) until B1 (id:4f02) ships
the converter + dual-vocab window. This is a LARGE migration — its acceptance DECOMPOSES into
three separable sub-checks (B2a readers+references / B2b relay-loop.js / B2c this-repo
ledgers+tests) that MAY be dispatched as separate executors (see the handoff report's split
recommendation). Do NOT dispatch until 4f02 is ticked.

- [ ] [INPUT — decision] B2c-finalizer — CLOSE the dual-vocab window: convert this-repo ledgers + migrate ~30 lane tests + flip old-vocab→lint ERROR 🚧 GATED (DEP: 3ef7 + cross-repo re-tag) — **human 2026-07-11 (relay human): keep OPEN, gate re-confirmed.** Blocker is the cross-repo re-tag, NOT tooling (lane-convert id:4b37 shipped): 27 own repos + project_manager scan.py still emit old vocab (71 live `[HARD — pool|meeting|hands|decision gate]` tags), so flipping old→ERROR now would break them. This is `[INPUT — decision]` = a deliberate coordinated migration the human triggers (each repo's next `/relay handoff` runs `lane-convert`, then this closes), never autonomous pool work. <!-- id:7df1 -->
  - **Why**: B2 (id:8111) landed reader+reference+engine DUAL-ACCEPT — old and new vocab both
    ERROR-free. The window must stay OPEN until every OTHER surface is on the new vocab, then close
    in one deliberate flip. This is the tail the meeting deliberately deferred.
  - **Acceptance**:
    1. `lane-convert.sh --in-place` on THIS repo's `ROADMAP.md` + `TODO.md` (own tags only; the
       converter auto-renames pool/meeting/decision-gate and FLAGS each `[HARD — hands]` — resolve
       those per-item into one of the four candidates by M3/human judgment, never a blanket default).
    2. Migrate the ~30 lane-asserting `tests/test_*.sh` + `test_hard_lane_buckets.sh` marker-set
       cross-check to the new vocab.
    3. FINAL step — CLOSE the window: `roadmap-lint.sh` + `gather-human-backlog.sh` make an OLD-vocab
       lane a hard ERROR (drop the dual-accept branches; delete the "window OPEN" prose in
       hard-lanes.md/human.md/review.md/handoff.md/conventions.md).
  - **Done-check**: `make test` fully green with every lane-asserting test on the new vocab AND an
    old-vocab `[HARD — pool]` fixture now LINT-REJECTED (a new red-then-green window-closed test).
  - **Blocked on**: 3ef7 (M3 per-item `[HARD — hands]` re-lane must resolve this repo's hands items
    first) AND the cross-repo re-tag (other own repos + `project_manager`'s `scan.py`, id:b466, must
    speak new vocab — the window can't close while any consumer is old-vocab-only). Closing early
    would break every repo still on `[HARD — *]`.
  - **d259 RATIFIED 2026-07-06 (meeting `docs/meeting-notes/2026-07-06-0959-machine-tag-format-endgame.md`):** endgame = (C) tag-first bracketed position (B rejected). The reorder tool (`lane-convert --reorder` isolated mode) + tag-first WARN lint are built AHEAD, ungated, as **id:4b37** — NOT authored inside this item. So this item's acceptance step 1 becomes: run the ALREADY-BUILT `lane-convert --in-place --reorder` (renames + reorders in one pass), and step 3's FINAL flip also flips 4b37's tag-first lint WARN→ERROR alongside old-vocab→ERROR (one window-close). Delete the 7 anchoring reimplementations in the step-2 reader migration.

## lane-anchor hotfix (relay handoff 2026-07-03)

## recipe explicit-success-marker doctrine (relay handoff 2026-07-03)

## case-c bare-only lane count (relay handoff 2026-07-03, owner-signed-off)

## mechanical-lane representability fix (relay HARD, user-injected id:baf1, 2026-07-10)

## Relay orphan-worktree reconcile (meeting 2026-06-16-0938, id:a4e9)

Decomposition of the orphan-reconcile design. **Sequence: D1 → D2/D3** (D2's reconcile
mode and D3's binding both operate on the `relay/orphan/*` namespace D1 creates). D4
(id:a692, note-only forward-flag) and D6 (id:122f, fsck ADVISORY follow-on, gated "ships
after D1–D3") stay in TODO.md — not executor work yet.

## Model probe (id:dba3 deliverable)

Sub-items of the `[HARD — strong model]` umbrella id:dba3. Design fully settled in
`docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md` (D2/D5/D6) and
`docs/meeting-notes/2026-06-17-0905-model-probe-tos-and-band.md` (D1/D2). Promoted to
ROADMAP 2026-06-17 so executors can work them; id:dba3 and id:23e9 (seed) stay `[HARD]`.

## Install-drift detection (meeting-adjacent, 2026-07-17, id:1102)

<!-- 2026-07-17. Filed by the apex session after VERIFYING and REPAIRING the live incident
     (make install-relay; roadmap-lint.sh now exits 0). Two of the apex's own hypotheses were
     FALSIFIED before this item was written — both recorded in TODO id:1102 rather than
     deleted, because the wrong ones explain why the existing guards missed it. -->

- [x] [ROUTINE] **memory-index.py silently mis-resolves `title:`/`hook:` when a writer re-nests them under `metadata:`** — OBSERVED TWICE 2026-07-17 (not speculative). Two memory files authored with top-level `title:`/`hook:` had both keys relocated **under `metadata:`** by a later write, so `build_entries` (`tools/memory-index.py` ~L237-241: `fm.get("title")`, `fm.get("hook")`) found neither at top level and **silently fell back** to `description:` (hook) and the filename stem (title) — a verbose, wrong index line with no error. <!-- id:e875 -->
  - **Step 1 — establish the culprit before fixing (do NOT guess; per the item's own directive):** reproduce by writing a memory file with top-level `title:`/`hook:`, then run each candidate writer and observe which relocates them under `metadata:` — candidates: the `Write`/`Edit` path, a frontmatter normalizer, the `claude-sessions-backup` commit, or `memory-index.py --write` round-tripping. Record the finding in the item/RELAY_LOG.
  - **Step 2 — fix (robust regardless of culprit, since some candidates are uncontrollable):** make `memory-index.py` resolve `title:`/`hook:` from BOTH top-level AND `metadata.*` (tolerate the nesting), AND make the fallback LOUD — emit a stderr warning when a file has `metadata.hook` but no top-level `hook:` (almost certainly this bug), never a silent `description:` substitution ([[no-swallow-stderr]] doctrine). If Step 1 finds a controllable writer, ALSO fix it to preserve key position.
  - **Acceptance**: `tests/test_memory_index_metadata_nesting.sh` (`# roadmap:e875`) green — RED spec written by the handoff. It asserts (a) a file whose `title:`/`hook:` live under `metadata:` resolves to those values (not stem/description), and (b) the resolver warns loudly to stderr on the metadata-only-hook case.
  - **Done-check**: tick this box, then `tests/run-tests.sh` fully green.
  - **Context**: `tools/memory-index.py` (`build_entries` resolution ~L234-253; `parse_frontmatter_text` already stores nested keys as `metadata.<key>` ~L152-162). Relates id:2e6d (the generated-index dissolution this depends on), [[memory-index-derived-2e6d]].

- [x] [ROUTINE] **`model-probe.sh grade` uses `echo "$output"` — bash builtin `echo` eats leading `-n`/`-e`/`-E` and mangles backslashes** — audit id:401c Run 11. `tools/model-probe.sh:38` is `echo "$output" | grep -qP "$regex"`; an output beginning with `-n`/`-e`/`-E` or containing backslashes is misinterpreted by the `echo` builtin, so grading can mismatch. Zero impact on today's numeric/word goldens, forward-robustness only. LOW severity, one-line fix. <!-- id:b9b5 -->
  - **Fix**: replace `echo "$output"` with `printf '%s\n' "$output"` at line 38.
  - **Acceptance**: `tests/test_model_probe.sh` extended with a `# roadmap:b9b5` case (RED spec written by the handoff): `grade` of an output that begins with a literal `-n ` (and one containing a backslash) against a regex that matches that literal text must exit 0. Currently RED (the `-n` is consumed by `echo`); GREEN after the `printf` change.
  - **Done-check**: tick this box, then `tests/run-tests.sh` fully green.
  - **Context**: `tools/model-probe.sh` grade arm (L34-40). Battery goldens unaffected.

- [x] [ROUTINE] **`tests/test_resource_claim_pid.sh` is FLAKY in the full suite** — passes 3/3 in isolation, fails ~50% of full-suite runs with "a stale-mtime claim with a LIVE live_pid was stolen — PID-liveness not honored": `claim.sh::pid_alive` intermittently false-negatives on a live `--pid` claim. Suspect root cause: `pid_alive` reads `.live_pid` via `jq … 2>/dev/null` and treats ANY transient read failure as empty→dead (the swallow, [[feedback-mechanize-no-swallow-stderr]]); under full-suite load a slow/interrupted `jq` or a background-`sleep`/PID-reuse race in the harness anchor makes the liveness check miss. Corrosive because every item's done-check runs `make test`. FIXED 2026-07-18 (executor): `pid_alive` now retries the `jq` read up to 3× (50ms backoff) before concluding dead — a transient fork/read failure clears on retry, while a genuine empty `.live_pid` still returns "" every time (legacy no-`--pid` path unaffected, test §3 still green). 20/20 parallel stress runs + full `make test` (262/0) green. <!-- id:ab5c -->
  - **Fix (do both):** (a) in `relay/scripts/claim.sh` `pid_alive`, distinguish "`jq` failed to read the file" from "`live_pid` field absent" — do NOT collapse a read error into a false "dead" (capture jq's exit status; only treat a successfully-parsed empty/non-numeric value as dead). (b) harden `tests/test_resource_claim_pid.sh`: assert `kill -0 $LIVE_PID` succeeds immediately before the liveness assertion (retry/poll rather than one-shot), and confirm no other test's cleanup can signal `$LIVE_PID`.
  - **Done-check**: tick this box, then run `tests/run-tests.sh` **five consecutive times, all fully green** (the flake reproduces ~50% of full-suite runs, so a single green run does NOT prove the fix — the 5× loop is the acceptance). No fresh RED spec: `test_resource_claim_pid.sh` itself IS the (intermittently) failing spec; the fix makes it deterministically green.
  - **Context**: `relay/scripts/claim.sh` (`pid_alive` ~L107, `.live_pid` read), `tests/test_resource_claim_pid.sh` (the `( trap - EXIT; exec sleep 600 ) & LIVE_PID=$!` anchor). Pre-existing since id:1b11.

- [x] [HARD — decision gate] **Relay children must run with a FAILING askpass so a sub-process `sudo` can never pop a GUI password prompt** — OBSERVED 2026-07-18 (run relay-20260717-182134-8632): a loderite `execute` child running `npx playwright test` triggered a graphical sudo password dialog (almost certainly Playwright `install-deps` → `sudo apt-get`); the user was prompted and dismissed it. The executor contract's "missing dep → handback, not sudo" is PROSE and cannot stop a *sub-process* from calling `sudo`. Mechanical fix: give every relay child an environment where `sudo` fails INSTANTLY and non-interactively (`SUDO_ASKPASS=/bin/false`, or `sudo` aliased to `-n`), so no dialog ever reaches the user — the child just gets a non-zero exit and hands back the missing dep. <!-- id:eb46 --> — 🚧 GATED (auto, id:3801; route:human): Only reachable env-injection point is ~/.claude/settings.json (relay-untouched); needs the user to add SUDO_ASKPASS=/bin/false there. — needs /relay human
  - **Step 1 — locate the env-injection point (this decides the lane):** find where a relay child inherits its process environment (the pool launch / the harness `agent()` spawn / a wrapper). Set `SUDO_ASKPASS=/bin/false` there. **BAILOUT GUARD:** if the ONLY reachable injection point is `~/.claude/settings.json` `env`, STOP — that file is [INPUT — user] and deliberately untouched by relay work; re-lane this item `[INPUT — user]` with the exact settings.json snippet to add, and hand back. Do NOT edit settings.json from a worktree.
  - **Step 2 (if an in-repo/pool injection point exists):** set it, and verify the child still SURFACES the missing dep in its handback rather than silently swallowing the failure ([[feedback-mechanize-no-swallow-stderr]]).
  - **Done-check**: a child (or a simulation of the child env) whose task shells out to `sudo` gets an immediate non-interactive failure (no GUI prompt) and hands back; `tests/run-tests.sh` still fully green. If Step 1 bails to settings.json, the done-check is the re-lane + handback instead.
  - **Context**: `relay/scripts/relay-loop.js` spawns children via the Workflow `agent()` API (no `process.env` reachable inside the sandbox — see L1907); the env is set at pool launch, OUTSIDE relay-loop.js. A git pre-commit hook does NOT catch this (sudo is runtime, not a git write). Relates id:077d. **JUDGMENT CALL flagged in REVIEW_ME** (env-injection point / possible [INPUT — user] re-lane).
- [ ] [INPUT — access] **Build the ebd0 privacy pre-push gate** (design: meeting `docs/meeting-notes/2026-07-20-1241-privacy-gate-pre-push-ebd0.md` D1-D4) — `hooks/pre-push-privacy-gate.sh`: warn+LOG engine (print loudly + append findings to a log, exit 0, NEVER blocks), classify the push remote from its URL (public forge → scan; private host e.g. fievel → skip), scan only ADDED diff lines, read leak patterns+allowlist from a configurable PRIVATE file PATH (env/default under ~/.config, absent → no-op with a notice), best-effort `scan_pii` shell-out iff present. Plus a `make install-privacy-gate` target that wires global `core.hooksPath` (author the target; do NOT run the global install in a worktree). Hermetic test with a fixture pattern file + fixture public/private remote URLs. Private-file population = id:7fff (hands); warn→block flip = id:df87; 7a05 adoption later. — **BUILD SHIPPED (item stays OPEN until ACTIVE — tick-on-active invariant, chidiai case 2026-07-20-relay-integrator-ticked-high-priority-security) 2026-07-20 (execute[opus]+review SHIP):** hooks/pre-push-privacy-gate.sh (warn+LOG, D1-D4) + test + `make install-privacy-gate` target shipped, suite 276/0. **The gate is INERT until ACTIVATED** — activation = populate the private pattern file (id:7fff, hands) + run `make install-privacy-gate` to set global core.hooksPath (hands) + later warn→block flip (id:df87). Buildable core complete; activation tracked by id:7fff/df87. <!-- id:ebd0 -->
- [x] [ROUTINE] gather-human-backlog.sh ALSO scans TODO.md human-lane items ([INPUT — meeting|access|decision], [HARD — meeting]) + dedup by id — DECIDED option (a) 2026-07-20; closes the e9cd TODO-blindness. Full context + rationale in TODO.md. — DONE 2026-07-20 (execute[opus]+review SHIP): gather-human-backlog.sh scans TODO human-lanes + dedup-by-id (test_gather_todo_human_lanes.sh), suite 284/0 — closes e9cd TODO-blindness. <!-- id:4e67 -->
- [x] [ROUTINE] Make drain-driver heartbeat + events specs HERMETIC — stub DRAIN_QUOTA_CMD in test_drain_driver_heartbeat.sh + test_drain_driver_events.sh so they do not depend on live quota (id:f9d2/dd1e follow-up). — DONE 2026-07-20 (execute[sonnet]+review SHIP): DRAIN_QUOTA_CMD stubbed in heartbeat+events specs (deterministic under high quota, proven). <!-- id:5eb8 -->

### 2026-07-21 handoff (run relay-handoff, supervised) — unknown-switch arg-guard (unblocks 7e87)

<!-- 2026-07-21 handoff C2: promoted the design-settled id:7681 (meeting
     2026-07-20-2304). single-id-two-views (D2): REUSES the TODO.md twin id:7681 — NOT a
     new mint. RED spec authored this handoff (C3): tests/test_unknown_switch_guard.sh.
     Why promoted: id:7e87 (/meeting --fabled) is gated-on 7681, so building 7681 is the
     unblock. Interface pinned below so the executor has a green target; the ONE genuine
     judgment call (coverage grep-scoping) is single-sourced inside validate-flags.sh's
     --coverage mode and flagged to REVIEW_ME id:7681. -->

- [x] [ROUTINE] **Unknown skill switches must WARN, not silently become subject/args — shared arg-guard** (design settled 2026-07-20 `docs/meeting-notes/2026-07-20-2304-fabled-meeting-flow-and-unknown-switch-guard.md` D1/D2) <!-- id:7681 --> — build `relay/scripts/validate-flags.sh` + a per-skill known-flags **manifest** (arity-aware: each entry records the flag AND whether it takes a value, so a dash-starting value like `--exclude -x` isn't false-dropped), wired into `/meeting` and `/relay` setup as a REQUIRED DISPLAYED warning artifact. Ship manifest+enforcement **atomically** (a `--coverage` mode is the drift guard). N=2 consumers (meeting+relay). Out of scope: a global CLAUDE.md directive (rejected — prose no-ops), mid-string dash content, non-dash subject content.
  - **Pinned interface** (the RED spec drives exactly this):
    - `validate-flags.sh <skill> -- <args...>` — runtime guard. `<skill>` ∈ {`meeting`,`relay`} selects the manifest. Prints the CLEANED args to stdout (unknown leading-dash flags dropped). Keys ONLY on leading-dash tokens; non-dash subject text always passes through untouched.
    - **Known flag** → passes through, no warning, exit 0.
    - **Unknown leading-dash flag** → LOUD warning to **stderr** that NAMES the flag AND LISTS the skill's known flags (the displayed artifact); the flag is DROPPED (not folded into the subject); exit 0 (proceed).
    - **Arity** → a value-taking flag's following token (even dash-starting, e.g. `--exclude -x`) is its VALUE: not warned, preserved in stdout.
    - **Near-miss escalation** → an unknown flag within **edit-distance ≤2 of a mode-changing flag** (`--afk`/`--cross`/`--fabled`/`-d`) does NOT warn-and-drop: it ESCALATES via a **non-zero exit** (reserve exit 2) and names the suspected mode-flag on stderr, so the caller does `AskUserQuestion` when attended / abort when not. A far-from-any-mode-flag unknown must NOT over-escalate (exit 0) — escalating *every* unknown was rejected (D2).
    - `validate-flags.sh <skill> --coverage <skill-md-path>` — the drift guard: exit 0 iff every INVOCATION flag documented in that SKILL.md is in the manifest; non-zero listing the missing flag(s). **The grep-SCOPING is the one real judgment call** — both SKILL.md files mention many helper-script `--flag` tokens in prose (`--mode`, `--show-toplevel`, `--apply`, `--json`, …) that are NOT skill-invocation flags; the coverage grep MUST scope to actual `/meeting`·`/relay` invocation flags (e.g. those in the invocation code-fence / config-knobs table), NOT a naive `grep -oE '\-\-[a-z]+'` over the whole file (which would be unsatisfiable). Single-source this scoping inside `--coverage`. **→ REVIEW_ME box (id:7681): confirm the coverage scoping is right, not over/under-broad.**
    - **Manifests**: `/meeting` lists `--cross` (its exact-whole-arg semantics preserved by /meeting's own handling — the manifest only needs to KNOW it so the guard never warns) and `--fabled` (the id:7e87 coupling). `/relay` lists its invocation flags (`--fable-down`/`-d`, `--interactive`, `--afk`, `--intensive`/`--allow-intensive`, `--strong-tier <v>`, `--priority <v>`, `--exclude <v>`, `--only <v>`, `--quota-7d <v>`, `--quota-5h <v>`, `--pool-width <v>`, `--once`, `--after <v>`, `--drain`, `--parallel <v>`, `--stop-path <v>`, `--all` and the keyword modes) with correct arity.
  - **Acceptance / done-check**: tick this box, then `make test` fully green — `tests/test_unknown_switch_guard.sh` (`# roadmap:7681`) goes EXPECTED-RED→PASS (17 assertions: known-flag accept, unknown warn-and-drop with listed flags, subject passthrough, arity-preserved value, mode-flag near-miss escalation, no over-escalation, `--coverage` green for both skills, both SKILL.md wired). Do NOT weaken any assertion — if the coverage scoping needs a different shape than the test drives, adjust the SCRIPT, keep the assertion.
  - **Context**: `meeting/SKILL.md` + `relay/SKILL.md` setup steps, `tests/test_fable_down_flag.sh` (structural-test pattern). TODO twin id:7681 (single-id-two-views). **Unblocks id:7e87** (`/meeting --fabled`, `gated-on: 7681`). Relates id:0e56, id:de36 ("a check nothing invokes isn't a check").

### 2026-07-23 handoff (run relay-20260723-110229-15341) — per-repo inbox scan (routed:bdee)

<!-- 2026-07-23 handoff C2: promoted the ONE promote-disposition backlog item, id:ce50
     (routed:bdee, adopted 2026-07-21 meeting). single-id-two-views (D2): REUSES the
     TODO.md twin id:ce50 — NOT a new mint. RED spec authored this handoff (C3):
     tests/test_inbox_scan_repo.sh. The other 228 open TODO ids classify `surface` (needs a
     lane decision a handoff can't make → left for the human-verdict filer, per handoff.md
     §surface) or `laned` (already ROADMAP-twinned); none were promotable here. No [HARD]
     executed (C5): the open HARD items are all decision-gated or the large drain-decomp
     residue — nothing small+ungated enough to finish safely this turn. -->

- [ ] [ROUTINE] **Repo-scoped relay commands must ALSO scan the shared inbox for `[<repo>]`-targeted open items — `relay/scripts/inbox-scan-repo.sh`** (chidiai `/relay human .` directive 2026-07-20, adopted 2026-07-21 meeting) <!-- routed:bdee --> <!-- id:ce50 --> — a repo-scoped run (`/relay human .`, `/relay <repo>`, `/relay . --drain`, `/relay next`) currently SKIPS the shared inbox entirely (SKILL.md invariant-1: "a directed single-repo / non-`--all` run does NOT touch the global inbox"), so a `[<repo>]`-targeted inbox item is invisible to it. Gap hit 2026-07-20: `/relay human .` on chidiai skipped the inbox while a `[chidiai]`-targeted item (routed:4975) sat unrouted. Build a per-repo FILTERED surface — distinct from `scan-routed.sh`'s `--all` dead-letter RECONCILE (which greps every target and is intentionally skipped on non-`--all` runs). This is report-only VISIBILITY, never a write. id:2ca6 is the `--drain` slice of the same directive; this covers the rest (human/`<repo>`/next).
  - **Pinned interface** (the RED spec drives exactly this):
    - `inbox-scan-repo.sh <repo>` — resolve the inbox (`RELAY_INBOX`, else the documented default `~/.claude/projects/todo-inbox.md`; do NOT re-implement scan-routed.sh's legacy-migration — that stays scan-routed's job), then print every OPEN `- [ ]` inbox item whose TARGET bracket is `[<repo>]`. Report-only, exit 0 with findings.
    - **Missing repo arg** → nonzero (misuse); a filtered scan needs a target.
    - **Anchored on the TARGET bracket**, not a repo-name substring: match the first `[...]` after the `- [ ]` checkbox (`^- \[ \] \[<repo>\]`), so an item targeting another repo whose PROSE mentions `<repo>` does NOT false-match (the id:be0e/1bbd anchoring-not-substring class).
    - **`[x]` DONE items are NOT surfaced** — only open work.
    - **Repo-scoped, no cross-repo leak** — scanning `<repoA>` never surfaces a `[<repoB>]` item.
    - **Missing inbox file → BENIGN** (exit 0, nothing surfaced): the inbox is optional and often absent for a directed run; this is a visibility surface, not a reconcile, so absence is not a dead-letter error. An **unreadable** inbox (present but not a readable regular file) is LOUD (nonzero) — never a silent `2>/dev/null` swallow (no-swallow rule).
    - **Wiring** — the repo-scoped surfaces must actually invoke it ("a check nothing invokes isn't a check", id:de36): `relay/references/human.md` §2 (add the per-repo filtered scan alongside the `--all`-only `scan-routed.sh`), and `relay/SKILL.md` invariant-1 (amend the "non-`--all` run does NOT touch the inbox" carve-out to name this filtered scan for the repo-scoped case). Leave `scan-routed.sh` and its `--all` reconcile UNCHANGED.
  - **Acceptance / done-check**: tick this box, then `make test` fully green — `tests/test_inbox_scan_repo.sh` (`# roadmap:ce50`) goes EXPECTED-RED→PASS (10 assertions: misuse reject, both open target items surfaced, `[x]` excluded, other-repo excluded, prose-substring not-matched, no cross-repo leak, missing-inbox benign, unreadable-inbox loud, both SKILL.md + human.md wired). Do NOT weaken any assertion — adjust the SCRIPT to satisfy the test, not the test.
  - **Context**: `relay/scripts/scan-routed.sh` (`resolve_inbox`, the `--all` dead-letter model to mirror the inbox-path convention from — but NOT to extend), `relay/SKILL.md` invariant-1 (lines ~290–299), `relay/references/human.md` §2. TODO twin id:ce50 (routed:bdee). Relates id:2ca6 (the `--drain` slice), id:1d3f (the `--all` reconcile it complements), id:de36.

### 2026-07-23 handoff (scoped C2/C3: id:99a4 + id:69f6, mechanical-proxy probe + always-on service)

<!-- 2026-07-23 SCOPED handoff (relay-handoff-20260723-125329-628-handoff): promoted
     EXACTLY the two owner-directed items from TODO.md's `## Relay` section — id:99a4
     (mechanical-proxy availability probe + two-mode discriminator) and id:69f6
     (always-on mechanical-proxy systemd --user service). single-id-two-views (D2):
     BOTH reuse their existing TODO.md tokens — no new mint. RED spec authored this
     handoff (C3) for id:99a4 only: tests/test_mech_proxy_probe.sh (the cleanly
     worktree-testable core — the discriminator script). id:69f6 is host-infra
     (systemd --user unit + install target); its acceptance is an authored artifact,
     not a hermetic RED test, per the handoff.md author-then-run guidance for
     scriptable device-adjacent work. id:7e6d (the root-cause TODO item both these
     items fix) stays in TODO.md — it is the diagnosis, not new dispatchable work. -->

- [x] [ROUTINE] **Mechanical-proxy availability probe + two-mode discriminator + Haiku fallback (mode a only) — `relay/scripts/probe-mech-proxy.sh`** (owner directive 2026-07-23, fixes id:7e6d) <!-- id:99a4 --> — mirror `relay/scripts/probe-fable.sh`'s shape (cache file + `check`/`set` subcommands + staleness), but the probe's core deliverable here is a DISCRIMINATOR that distinguishes two failure classes needing different remedies. Read `ANTHROPIC_BASE_URL` via plain `"$ANTHROPIC_BASE_URL"` (never `${VAR:-}`, per repo convention). Port from `MECH_PROXY_PORT`, default `61843`.
  - **Pinned interface**: `probe-mech-proxy.sh discriminate` prints exactly one of:
    - `mode-a` — `ANTHROPIC_BASE_URL` is empty, OR set but not `http://127.0.0.1:<port>` (loopback+port literal match). Session wasn't launched through the proxy → `model:"bash"` hits the real API directly. **Unfixable in-session** (the harness binds the global base URL at startup): the remedy is a LOUD warning naming the exact restart env (`ANTHROPIC_BASE_URL=http://127.0.0.1:61843`) plus falling `model:"bash"` steps back to Haiku for this run (real API IS reachable directly in mode-a).
    - `mode-b` — `ANTHROPIC_BASE_URL` IS the loopback+port form, but a liveness check (TCP-connect the port, or a trivial `model:"bash"` echo whose stdout must come back) fails. Proxy is down/broken at the session's actual base URL → normal `agent()` traffic is ALSO dead (nothing routes, Haiku fallback is equally unreachable through a dead proxy) → NOT a Haiku-fallback case; the remedy is attempt (re)start / else LOUD ABORT (never silently degrade).
    - `healthy` — loopback+port base URL AND the liveness check succeeds.
  - **Acceptance / done-check**: tick this box, then `make test` fully green — `tests/run-tests.sh tests/test_mech_proxy_probe.sh` (`# roadmap:99a4`) goes EXPECTED-RED→PASS. Triangulated cases: base-URL empty → `mode-a`; base-URL non-loopback (e.g. `https://api.anthropic.com`) → `mode-a`; base-URL loopback but a definitely-closed port → `mode-b`; base-URL loopback with a real stub HTTP server answering on the port → `healthy`. The relay-loop.js wiring of the 12 `model:'bash'` hops to the discriminator's verdict (Haiku fallback / warning text) is the EXECUTOR's implementation on top of this script — this item specs the probe + discriminator core only.
  - **Context**: `relay/scripts/probe-fable.sh` (template), `relay/scripts/mechanical-proxy.py` (header — binds 127.0.0.1:MECH_PROXY_PORT, intercepts `model:"bash"`). TODO twin id:99a4. Pairs with id:69f6 (parallel, no hard dependency — id:69f6 is the durable fix that makes mode-b rare; this probe is the defense-in-depth detector). Fixes id:7e6d.

- [x] [ROUTINE] [host:zomni] **Always-on mechanical-proxy systemd --user service — `tools/mechanical-proxy.service` + `make install-mech-proxy`** (owner directive 2026-07-23) <!-- id:69f6 --> — author a systemd `--user` unit running `relay/scripts/mechanical-proxy.py` with `Restart=always` (+ `RestartSec`), following the EXISTING systemd-user precedent in this repo (`tools/quota-sample.service`/`.timer` + `make install-quota-timer`, `tools/relay-watchdog.service`/`.timer` + `make install-relay-watchdog`) EXACTLY — same symlink-into-`~/.config/systemd/user/` shape, same `daemon-reload` + `enable --now` sequence. No timer needed (long-running daemon, not a periodic sampler). Proxy binds `127.0.0.1` only (per its own security posture — the unit does not need to enforce this, the script already does).
  - **Acceptance**: `tools/mechanical-proxy.service` exists, `ExecStart` invokes `relay/scripts/mechanical-proxy.py` via an absolute `%h/src/dotclaude-skills/...` path (matching the quota-sample/relay-watchdog `%h` convention), `Restart=always` set. `make install-mech-proxy` target added to the Makefile (mirrors `install-relay-watchdog`'s body: `mkdir -p $(SYSTEMD_USER)`, symlink the unit, `daemon-reload`, `enable --now`). `make help` lists it.
  - **Done-check (host-gated, host:zomni)**: after `make install-mech-proxy`, `systemctl --user is-active mechanical-proxy` returns `active`. This is on-device verification (real systemd, real daemon) — not hermetically testable in a worktree; the artifact-existence half (service file content, Makefile target present) is the worktree-verifiable acceptance.
  - **Context**: `relay/scripts/mechanical-proxy.py` (id:176f, the daemon this unit runs), `tools/quota-sample.service`/`.timer`, `tools/relay-watchdog.service`/`.timer` (the precedent to copy, not reinvent). TODO twin id:69f6. Pairs with id:99a4 (parallel, no hard dependency) — this is the durable fix that makes id:99a4's mode-b rare.

- [x] [HARD] **Front-door mechanical-tier preflight — consume the probe: warn on mode-a/mode-b + fall the 12 `model:"bash"` hops back to Haiku in mode-a** (owner directive 2026-07-23) <!-- id:4239 --> — id:99a4 shipped the discriminator but NOTHING consumes it: `relay-loop.js` + the front-door SKILL.md have zero probe references, so a session launched WITHOUT the proxy still silently degrades (the 39-error swarm from run relay-20260723-110229-15341) instead of warning + falling back. This is id:99a4's unwired "warn or auto-fall-back" half and the end-to-end fix for id:7e6d when a session is not launched via `claude-relay`.
  - **Design**: extract a TESTED helper `relay/scripts/mech-preflight.sh` (mirror how `probe-fable.sh` is a tested helper the front-door prose calls) that runs `probe-mech-proxy.sh discriminate` and: mode-a → print the LOUD restart warning (naming `ANTHROPIC_BASE_URL=http://127.0.0.1:61843`) AND signal "enable Haiku fallback" (real API reachable directly); mode-b → print "proxy down" + signal ABORT (Haiku unreachable through a dead proxy); healthy → signal "proceed". `relay-loop.js` reads the signal at startup and, when Haiku-fallback is enabled, dispatches the 12 `model:"bash"` hops as `model:"haiku"` instead. Front-door SKILL.md gains a step-0 preflight call (mirror the Fable probe step 0).
  - **Acceptance**: `mech-preflight.sh` RED-specced (`tests/test_mech_preflight.sh`: mode-a→warn+fallback-signal, mode-b→abort-signal, healthy→proceed-signal, stubbing the probe); `relay-loop.js` wires the per-hop Haiku fallback keyed on the preflight signal; SKILL.md documents the step-0 preflight. Full suite green.
  - **SAFETY (relay-loop.js is the critical Workflow script)**: after any `relay-loop.js` edit, run `node --check relay/scripts/relay-loop.js` AND the exec-smoke guard (id:5bac/aec5 — the loop-template-runtime-crash class); escape backticks in any added template. If the wiring can't be done green + smoke-clean in one pass, HANDBACK rather than ship a broken loop.
  - **Context**: `relay/scripts/probe-mech-proxy.sh` (id:99a4, the discriminator this consumes), `relay/scripts/probe-fable.sh` (the tested-helper-called-by-prose pattern), the step-0 Fable probe in SKILL.md (the mirror). Fixes id:7e6d end-to-end. TODO twin id:4239.

- [x] [ROUTINE] [host:zomni] **Add `WatchdogSec` + `sd_notify` to mechanical-proxy — catch a hung (accepting-but-wedged) daemon** (resolves REVIEW_ME id:69f6, review 2026-07-23) <!-- id:4044 --> — today `mechanical-proxy.service` has `Restart=always`/`RestartSec=5`, which recovers from a CRASH but not from a daemon that is alive-and-listening-but-wedged. A `WatchdogSec=` + `sd_notify` heartbeat catches that.
  - **Acceptance**: `relay/scripts/mechanical-proxy.py` calls `sd_notify("READY=1")` after the socket binds and emits `sd_notify("WATCHDOG=1")` on a periodic heartbeat (interval < WatchdogSec/2, from a thread/timer; use the `$NOTIFY_SOCKET` env directly via a small stdlib helper — no new dependency). `tools/mechanical-proxy.service` gains `Type=notify` + `WatchdogSec=30` (tune as sensible). Guard the notify calls so the daemon still runs standalone (NOTIFY_SOCKET unset → no-op) — a `tests/test_*.sh` asserting the standalone/no-op path is worktree-testable. **DONE 2026-07-23**: `_sd_notify`/`_start_sd_watchdog` added (guarded on `$NOTIFY_SOCKET`, stdlib `AF_UNIX`/`SOCK_DGRAM` only); `main()` sends `READY=1` post-bind and starts the 10s heartbeat thread; service file gained `Type=notify`/`WatchdogSec=30`; `tests/test_mechanical_proxy_sdnotify.sh` (standalone no-op + positive-control) green; `systemd-analyze verify` clean; full suite 294/1(pre-existing unrelated flake)/1-expected-red.
  - **Done-check (host-gated, host:zomni)**: after `make install-mech-proxy`, `systemctl --user show mechanical-proxy -p WatchdogUSec` is non-zero and `systemctl --user is-active mechanical-proxy` → `active`. **DEFERRED to the orchestrator** (post-merge, from `main` — installing from this worktree would dangle the systemd symlink on prune) — NOT verified by this build child.
  - **Context**: `relay/scripts/mechanical-proxy.py` (id:176f), `tools/mechanical-proxy.service` (id:69f6). Resolves the REVIEW_ME id:69f6 WatchdogSec box. TODO twin id:4044.
