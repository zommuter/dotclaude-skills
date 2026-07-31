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

- [ ] [HARD] `/relay . --parallel N` — **[RE-FRAMED 2026-07-24, owner-directed: parallel fan-out is now pool `pipeline()` in the Workflow loop (id:1f4f), NOT the retired off-Workflow driver (id:93fe). Verifiable children id:5367/2062 stay substrate-agnostic; off-Workflow live-residue id:7fae is moot.]** 🚧 @container DECOMPOSED 2026-07-20 (handoff relay-20260720-144400-4669) — TRACKING LINE ONLY, work the children: verifiable id:5367 (disjoint-path greenlight) + id:2062 (serial one-writer integrator) below. Tick this parent only when the children are closed. Full context TODO.md. <!-- id:ebbe -->
  - **DEAD GATE DROPPED 2026-07-31** — this line carried `<!-- gated-on:0534 -->`, but `id:0534` is `[x]` archived at `TODO.archive.md:432` (a `[HARD — pool]` mechanical-daemon lease item) and was **never** a ROADMAP item, so the gate was PERMANENT and could never open. Found by `roadmap-lint` rule 3(d) DEAD-GATE (`id:49e0`) within minutes of that rule existing — the fourth instance of the trap in one day, after `a955`→`87f5`, `8123`→`1a34` and `f6d5`→`8ba1`. **Dropped rather than re-targeted** because this line is an `@container` DECOMPOSED tracking entry with `children:` — it is not dispatchable in the first place, so a gate on it is meaningless twice over. Its children carry their own gates.
- [x] **[SUPERSEDED 2026-07-24 — consolidate ratified (owner-directed); the OFF-Workflow `drain-driver.mjs` deliverable is FROZEN as a headless fallback, go-forward = re-wire onto the Workflow substrate id:7488]** [HARD] `/relay . --drain` — shipped children id:cd7a/f9d2/838d/dd1e/864e stay DONE artifacts (drain-driver.mjs works); live-only residue id:23ff is now moot (its live-verify target is the Workflow re-wire, not this driver). Full context TODO.md (guard-parity list). <!-- id:93fe -->

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

- [x] **[SUPERSEDED 2026-07-24 — moot under consolidate; the live-verify target is the Workflow re-wire id:7488, not the frozen off-Workflow driver]** [HARD] 🚧 sandbox/live-verify-only — **end-to-end off-Workflow drain on a live repo** (id:93fe residue) <!-- children-of:93fe --><!-- gated-on:cd7a --><!-- id:23ff --> — why not worktree-verifiable: the real `DRAIN_ROUND_CMD` dispatches LIVE model agents (auto-spend — forbidden in hermetic tests) against a real repo, real quota cache and real integrator; every hermetic child (cd7a/f9d2/838d/dd1e) stubs that seam BY DESIGN. Verify by ONE supervised live drain run after the children land; record the run in RELAY_LOG.md, then tick.
- [x] **[SUPERSEDED 2026-07-24 — moot; off-Workflow parallel residue retired, fan-out reborn as pool `pipeline()` id:1f4f which brings its own live-verification]** [HARD] 🚧 sandbox/live-verify-only — **parallel fan-out N>1 live behaviour** (id:ebbe residue) <!-- children-of:ebbe --><!-- gated-on:2062 --><!-- id:7fae --> — why not worktree-verifiable: real CONCURRENT executor agents in sibling worktrees (scheduling, contention, lease + heartbeat + watchdog interplay under load) cannot be reproduced hermetically — the tests prove only the plan/merge logic (id:5367/2062). Verify by ONE supervised live `--parallel 2` round on declared-disjoint units after 5367+cd7a+2062 land; record in RELAY_LOG.md, then tick.

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
  - **DECIDED 2026-07-29** (meeting `docs/meeting-notes/2026-07-29-0911-mechanical-hop-proxy-coupling.md`, D1/D2 + amendments D1-A/D2-A, owner-ratified). Posture is **fail-closed**: `mech-preflight.sh` mode-a AND mode-b become launch refusals (the `abort` token starts aborting), and `MECH_MODEL` stops being a fallback selector — the `MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'` ternary at `:248` is deleted. Second enforcement layer is a **self-attesting first mechanical hop** (fenced `true` as `model:'bash'`), NOT a token assertion — `A.MECH_FALLBACK || ''` makes a front-door-skipping caller indistinguishable from healthy. Cap: exactly two layers. Children: **id:540f** (preflight refusal), **id:c179** (self-attesting hop + ternary deletion), **id:c480** (this item's own scope table is STALE — it lists `release:` as MUST-STAY-`model:'haiku'` while id:f7d3 converted it to `model:'bash'` at `:2316`; fix before implementing or the table will mislead). **Rationale correction:** the driver is classifier exposure + cost + the hardcoded-no-fallback `discover-prelude`/`discover-run` hops (`:1114`/`:1279`) — NOT the quota gate, which already fails closed (`:1956`). **Gated on id:e62c** (F2: whether proxying confers classifier protection at all is UNRESOLVED).
  - **Scope — the 5 CONVERTIBLE hops** (each a SINGLE allowlisted-relay-script pipeline the proxy's `_command_allowed()` accepts: no heredoc, no `&&`/`;`/newline, no `$(...)`, no `>>`, no `python3`):
    | Hop label | line (as of this handoff) | command | note |
    |---|---|---|---|
    | `file-surface:${repo}` | ~1506 | `file-surface-decisions.sh '<path>'` | fire-and-forget; output logged verbatim |
    | `quota:${tier}` | ~1699 | `quota-stop.sh --tier <t> --agents <n> --wall 0` | carries `QUOTA_SCHEMA` — the consumer must parse the script's raw JSON stdout instead of a schema-typed return |
    | `inject-take` | ~2129 | `inject.sh take` | carries `INJECT_TAKE_SCHEMA` + post-processing (path-resolve / unit-shape) — that shaping must move to JS/another hop; the fence returns only `inject.sh take`'s raw stdout |
    | `heartbeat-beat` | ~2212 | `heartbeat.sh beat <runId>` | fire-and-forget |
    | `heartbeat-stop` | ~2222 | `heartbeat.sh stop <runId>` | fire-and-forget |
  - **OUT of scope — the 6 NON-eligible hops MUST STAY `model:'haiku'`** (converting them is WRONG and the test guards it): `discover-prelude` (~933, multi-command + LLM JSON assembly), the `discover-run:` classify shard (~1103, the id:7402 RESIDUAL LLM read — never mechanical), `write-relay-status` (~362, heredoc `<<` — proxy refuses redirection), `handback-followup` (~1934, `python3` leader — not an allowlisted relay script), `gaming-log` (~1967, `$(...)` + `&&` + `>>`), `auto-reconcile-restart` (~2248, multi-command + LLM logic). **The `release` hop (label prefix "release:") is REMOVED from this list (id:c480)** — id:f7d3 SPLIT and CONVERTED it to a mechanical dispatch (one fenced-command dispatch per sub-command); it is no longer MUST-STAY-haiku, and the count above drops 7→6 accordingly. **Current state, verified 2026-07-31**: the hop is `relay-loop.js:2361`, dispatched as **`model: MECH_MODEL`** — commit 490ac6e (id:4239) replaced the literal `model: 'bash'` here (and at `discover-prelude` / the `discover-run:` shard) with the single `MECH_MODEL` indirection defined at `:118` (`MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'`). It is still mechanical; it is no longer a `'bash'` LITERAL, so any check anchored on that literal must accept `MECH_MODEL` too. Splitting a multi-command hop into single-command mechanical hops is a POSSIBLE follow-up but is NOT in this unit.
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
- [x] [INPUT — access] Post-Fable transition (after 2026-07-07) — **CLOSED 2026-07-28 as MOOT: the pre-registration's factual PREMISE turned out FALSE, and is amended explicitly rather than reinterpreted (CLAUDE.md derived-doc/pre-registration rule).** This item pre-registered actions for "when the Fable window CLOSES". It did not close — owner 2026-07-28: **Fable became a fixed part of the Max subscription**, i.e. permanently available. Every sub-action is therefore moot or inverted: (a) "stop passing `--strong-tier fable`" — inverted, Fable is now always available; (b) "default reverts to Opus apex automatically (probe-fable cache flips unavailable)" — premise false, the cache reads `available:true`; (d) Sonnet executors unaffected — still true but never at risk. Sub-action (c) — verify nothing treats `fable_rechecked = false` as PENDING work (id:e030 semantics) — is the one live remnant and is CARRIED FORWARD into id:698d, not dropped. Replacement work: **id:aa26** (retire the probe → explicit config) and **id:698d** (does permanent Fable change the Opus-apex posture — owner's call). <!-- id:77f3 -->
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
- [x] [HARD] `/meeting --fabled` (or similar; design-settled 2026-07-20, gate id:7681 landed) — see TODO.md <!-- id:7e87 --> — **DONE 2026-07-26 (relay HARD child, id:da26)**: v1 opt-in `--fabled` closing pass documented in `meeting/SKILL.md` — Setup step 1b captures the mode flag; End-of-meeting **step 0f** runs ONE closing adversarial Fable-5 subagent (`Task` tool, `model: claude-fable-5`, design-critique framing per id:aa68/a4f5 to sidestep the `reasoning_extraction` refusal; subagent-not-driver), fed a repo-state DIGEST built AT CLOSING TIME incl. the ratified `## Decisions` VERBATIM. Availability reuses the tested `probe-fable.sh check` (no re-derived probe); **LOUD degrade** records the exact `Fable unavailable — \`--fabled\` pass skipped` line in the note (never silent — silent = re-creates id:7681). Findings are ADVISORY only ([[feedback-fable-optional-not-gate]]) — accepted ones re-open via the closure-gate "amend a decision" flow; the pre-registered **≥2 forced-amendment findings** trigger (hardening-only excluded) gates the per-decision (B) + full multi-pass (C) escalation, unifying id:8df5. `--fabled` already registered in `known-flags-meeting.tsv` (7681). `tests/test_fabled_closing_pass.sh` (`# roadmap:7e87`) GREEN; full suite green.
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

- [x] [HARD — decision gate] Relay consumer of the id:2840 derived ledger index (cross-ledger / count / promotion) — **CLOSED 2026-07-29 (relay human, owner call): the item AS TITLED is dead.** Its 2026-07-14 build authorization was RETRACTED 2026-07-28 because the premise is false — the shipped `edges.json` is a co-citation graph carrying no checkbox-state and no counts, so it can neither retire `orphan-scan --cross-ledger` nor source the count line. "Build the relay consumer of the index" is therefore not a live task, and leaving it open misrepresented a retracted authorization as pending work. The residual LIVE question — extend the project_manager index to emit checkbox-state + counts, vs. keep `orphan-scan --cross-ledger` as the guard and drop the count prose only (id:1de1) — is re-filed as **id:75db**. Closing also clears the permanent roadmap-lint DECIDED-LEFT-OPEN WARN that id:5533's expanded predicate fires on this line (the REVIEW_ME box that raised it is ticked). Producer facts as of 2026-07-14 (still true, just insufficient): `proj refresh` → 1288 nodes / 2791 edges. Meeting `docs/meeting-notes/2026-06-23-0803-ledger-drift-derived-index.md`. <!-- id:659c -->
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
- [ ] [INPUT — access] **Build the ebd0 privacy pre-push gate** (design: meeting `docs/meeting-notes/2026-07-20-1241-privacy-gate-pre-push-ebd0.md` D1-D4) — `hooks/pre-push-privacy-gate.sh`: warn+LOG engine (print loudly + append findings to a log, exit 0, NEVER blocks), classify the push remote from its URL (public forge → scan; private host e.g. fievel → skip), scan only ADDED diff lines, read leak patterns+allowlist from a configurable PRIVATE file PATH (env/default under ~/.config, absent → no-op with a notice), best-effort `scan_pii` shell-out iff present. Plus a `make install-privacy-gate` target that wires global `core.hooksPath` (author the target; do NOT run the global install in a worktree). Hermetic test with a fixture pattern file + fixture public/private remote URLs. Private-file population = id:7fff (hands); warn→block flip = id:df87; 7a05 adoption later. — **BUILD SHIPPED (item stays OPEN until ACTIVE — tick-on-active invariant, chidiai case 2026-07-20-relay-integrator-ticked-high-priority-security) 2026-07-20 (execute[opus]+review SHIP):** hooks/pre-push-privacy-gate.sh (warn+LOG, D1-D4) + test + `make install-privacy-gate` target shipped, suite 276/0. **The gate is INERT until ACTIVATED** — activation = populate the private pattern file (id:7fff, hands) + run `make install-privacy-gate` to set global core.hooksPath (hands) + later warn→block flip (id:df87). Buildable core complete; activation tracked by id:7fff/df87. **ACTIVATION INSTALLED BUT NOT PROVEN — 2026-07-24 (relay human; owner call: KEEP OPEN).** Installed state VERIFIED: global `core.hooksPath` = `~/.config/git/hooks`, `pre-push` → `dotclaude-skills/hooks/pre-push-privacy-gate.sh` (symlink present), private pattern file present + populated (5686 B, 2026-07-20), id:7fff `[x]` archived. NOT ticked because the only 2 lines in the gate log come from a `/tmp` test fixture (2026-07-20) — no genuine public-remote push has exercised it. **Tick criterion: ≥1 log line from a real repo push** (installed ≠ proven; the tick-on-active invariant exists for exactly this item, chidiai `2026-07-20-relay-integrator-ticked-high-priority-security`). Block flip = id:df87; pattern curation = id:6afb. <!-- id:ebd0 -->
- [x] [ROUTINE] gather-human-backlog.sh ALSO scans TODO.md human-lane items ([INPUT — meeting|access|decision], [HARD — meeting]) + dedup by id — DECIDED option (a) 2026-07-20; closes the e9cd TODO-blindness. Full context + rationale in TODO.md. — DONE 2026-07-20 (execute[opus]+review SHIP): gather-human-backlog.sh scans TODO human-lanes + dedup-by-id (test_gather_todo_human_lanes.sh), suite 284/0 — closes e9cd TODO-blindness. <!-- id:4e67 -->
- [x] [ROUTINE] Make drain-driver heartbeat + events specs HERMETIC — stub DRAIN_QUOTA_CMD in test_drain_driver_heartbeat.sh + test_drain_driver_events.sh so they do not depend on live quota (id:f9d2/dd1e follow-up). — DONE 2026-07-20 (execute[sonnet]+review SHIP): DRAIN_QUOTA_CMD stubbed in heartbeat+events specs (deterministic under high quota, proven). <!-- id:5eb8 -->
- [x] [ROUTINE] **Install-drift guard — `relay/scripts/check-install-drift.sh` detects a canonical script (or a `source` target) missing from the per-file-symlink install** (routed:35eb, 2nd instance in 8 days) — DONE 2026-07-24: `check-install-drift.sh --canonical <dir> --installed <dir>` follows each script's `source`/`.` lines and exits non-zero naming every missing script (direct + source-target); RED spec `test_install_drift_guard.sh` green; wired into `relay_FILES`/`relay_EXEC`/`relay_ALLOW`. <!-- id:c5ed --> — skills install as per-file symlinks, so a newly-added canonical script needs `make install-<skill>` to appear under `~/.claude/skills/<skill>/scripts/`; nothing FAILS on drift today, it surfaces only as a runtime "command not found" inside an agent — or (the NASTIER routed:35eb recurrence) as a SILENT death when an installed script `source "$dir/<sibling>.sh"`s a sibling that is not installed (`set -e` + source-not-found kills it mid-run → a FALSE-GREEN a stdout-reading caller misses). Build the mechanical fix candidate (a): a guard that diffs canonical scripts against the install AND follows each script's `source` lines, exiting non-zero + naming every missing script. Interface: `check-install-drift.sh --canonical <dir> --installed <dir>` (roots passed by arg — hermetic, no HOME override). Must cover BOTH the directly-invoked case (original c5ed) AND the `source`-target case (routed:35eb) — the source check is independent of the canonical∖installed set-diff (an installed script may source a sibling that the enumeration would call green). TODO.md id:c5ed is the "why" (single-id-two-views). Relates id:69ef, id:373e, id:f682.
  - **RED spec**: tests/test_install_drift_guard.sh (# roadmap:c5ed, hermetic — all fixtures under mktemp, never touches ~/.claude/network). 4 assertions: (a) NEGATIVE-DIRECT — uninstalled canonical script → non-zero + names it; (b) NEGATIVE-SOURCE — installed script whose `source` target is uninstalled → non-zero + names the target (the roadmap-lint→lib-state-claim routed:35eb shape); (d) SOURCE-ONLY — direct enumeration green but a dangling source-target still non-zero (forces real source-following, not a blind set-diff); (c) POSITIVE — full parity → exit 0.
  - **Acceptance**: `relay/scripts/check-install-drift.sh` exists + executable with the `--canonical`/`--installed` interface; `tests/test_install_drift_guard.sh` goes EXPECTED-RED→PASS (all 4 cases), and the guard covers `source`-targets (case b + d), not only directly-invoked scripts; tick this box, then `tests/run-tests.sh` fully green.

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

- [x] [ROUTINE] **Repo-scoped relay commands must ALSO scan the shared inbox for `[<repo>]`-targeted open items — `relay/scripts/inbox-scan-repo.sh`** (chidiai `/relay human .` directive 2026-07-20, adopted 2026-07-21 meeting) <!-- routed:bdee --> <!-- id:ce50 --> — a repo-scoped run (`/relay human .`, `/relay <repo>`, `/relay . --drain`, `/relay next`) currently SKIPS the shared inbox entirely (SKILL.md invariant-1: "a directed single-repo / non-`--all` run does NOT touch the global inbox"), so a `[<repo>]`-targeted inbox item is invisible to it. Gap hit 2026-07-20: `/relay human .` on chidiai skipped the inbox while a `[chidiai]`-targeted item (routed:4975) sat unrouted. Build a per-repo FILTERED surface — distinct from `scan-routed.sh`'s `--all` dead-letter RECONCILE (which greps every target and is intentionally skipped on non-`--all` runs). This is report-only VISIBILITY, never a write. id:2ca6 is the `--drain` slice of the same directive; this covers the rest (human/`<repo>`/next).
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

### 2026-07-23 handoff (scoped C2/C3: id:dfb9 speedtest + id:24ec discovery→bash — post-a36e-fix promotions)

- [x] [ROUTINE] **Speedtest harness: host `claude -p` spawn vs Workflow `agent()` spawn — `relay/scripts/relay-spawn-bench.sh`** (promoted from TODO id:dfb9; the missing EVIDENCE under the off-Workflow thread, [[relay-drain-apex-tasklist-decision]]) <!-- id:dfb9 --> — build the 3-subcommand timing harness the RED spec pins. DONE 2026-07-23: harness built, RED spec green.
  - **RED spec**: `tests/test_relay_spawn_bench.sh` (`# roadmap:dfb9`, hermetic — stubs `claude` via `CLAUDE_BIN`, no real spawns/network/auto-spend). Pinned interface: `claude-p [--n N]` → one JSON line `{mode:"claude-p",n,median_ms,p90_ms,samples_ms}`; a missing `claude` fails LOUDLY (no silent-zero); `agent-record [--from FILE]` → `{mode:"agent",median_ms}` from `profile-run.sh --json` records; `compare` → `{mode:"compare",claude_p_median_ms,agent_median_ms,ratio}`.
  - **Acceptance**: tick this box, then `make test` green (the RED test PASSes). The agent() side is NOT re-spawned (only a Workflow dispatches `agent()`; its durations come from `profile-run.sh --json` / relay-econ id:08a3). The REAL cross-substrate number is a documented LIVE run (record in RELAY_LOG.md), not hermetic.
  - **Context**: id:cd7a (drain-driver — the off-Workflow `claude -p` spawn path this measures), id:08a3 (relay-econ, the existing `agent()` timing instrument), id:a36e (the just-fixed proxy — model:bash now resolves). TODO twin id:dfb9.

- [x] [HARD — pool] **Mechanize relay discovery (prelude + shards) `model:'haiku'` → `model:'bash'` — eliminate the id:7402 residual LLM surface — NEEDS per-item RED spec** (promoted from TODO id:24ec; user-flagged 2026-07-23; UNBLOCKED by the id:a36e proxy fix) <!-- id:24ec --> — the `discover-prelude` (relay-loop.js:993) + `discover-run` shards (:1163) are pinned `model:'haiku'` (the biggest remaining real-model cost per round) because each runs a per-repo reconcile+classify LOOP + sig-gated content-address, not a single fenced command. DISTINCT from id:6b35 (that converts the ~12 MECHANICAL hops; this is the DISCOVERY CLASSIFICATION agents). **DONE 2026-07-23 (the discover-run SHARD half; the prelude half was id:86a2): the `discover-run` shard is now a deterministic `model:'bash'` dispatch of the new `relay/scripts/discover-chunk.sh` (CASE B — per-repo `discover-repo.sh` reconcile+classify LIVE, concatenated; zero agents, no LLM). CASE-A queue content-address copy (the id:7402 residual read) is ELIMINATED for now and DEFERRED to the follow-on id:6eb3 (which re-adds it mechanically via discover-chunk.sh's reserved `--queue-latest`/`--queue-fresh-secs` flags). Reconcile now runs LIVE every round for every repo (FINDING-1 preserved by construction). Registered in Makefile + mechanical-proxy allowlist. Structural coverage relocated faithfully (test_relay_loop_mech_emitter / test_relay_discover_shard / test_relay_runner_swap / test_discover_cache / test_discovery_queue_consume, each `id:24ec`-commented); spec `tests/test_discover_chunk_mechanized_24ec.sh`.**
  - **Approach**: wrap the per-chunk `reconcile-repo.sh` + classify + content-address into ONE `relay-mech` script (the id:c14d pattern that just shipped), then dispatch the shard as `model:"bash"`. `classify-repo.sh` already proved the classification deterministic (`ambiguous:false`, zero agents), so the LLM read is genuinely eliminable.
  - **Why [HARD] + needs-RED-spec (NOT yet executor-ready)**: touches the CRITICAL discovery path in `relay-loop.js` (Workflow-sandbox-only → the [[sandbox-2ec4]] RED-spec-from-worktree hazard: spec via structural/exec-smoke tests, cf id:5bac), and mechanizing the id:7402 "irreducible-for-now LLM read" is a correctness-sensitive claim (a wrong sig-gate silently mis-classifies → mis-dispatches). Route to a dedicated handoff to author the RED spec (a new `discover-chunk.sh` wrapper test + a structural assertion that the discover-run dispatch is `model:"bash"`) BEFORE execute. `node --check` + exec-smoke guard on any relay-loop.js edit.
  - **Context**: id:7402 (the residual surface), id:9d97 / id:65f9 (mechanical discovery producer — reconcile against these; the queue-read was gated on the "launch-wall" id:af30/id:2ec4, which the a36e fix may dissolve), [[classifier-4d8e]], id:a36e. TODO twin id:24ec.

- [x] [HARD — pool] **Orphan-suppress must be ITEM-scoped/ADDITIVE, not REPO-scoped — a parked `relay/orphan/*` for one item must not collateral-block a repo's independent open work** (promoted from TODO id:bc49; OBSERVED twice 2026-07-23 — loderite AM + dotclaude-skills PM; observe-first discharged) <!-- id:bc49 --> — the ratified contract (2026-06-16 meeting D3 / id:1f53) is suppress-redispatch is ITEM-scoped ("still-open ITEM with parked partial work"), but `discover-repo.sh` step 1 (mirrored by the shard prompt at `relay/scripts/relay-loop.js:1163`) returns `{units:[]}` for the WHOLE repo the moment reconcile's `surfaced` array is non-empty — so one parked orphan zeroes out every independent `[ROUTINE]` unit and the repo vanishes from dispatch.
  - **Provenance (A2, amended --fabled 2026-07-23)**: this is NOT a blanket amendment of a4e9. a4e9-D3 was already ITEM-scoped; the repo-scoped `surfaced→units:[]` was **id:1f53 implementation OVER-REACH, never ratified**, so removing it **RESTORES a4e9-D3** (and fixes id:1f53). The genuine a4e9 amendments are exactly two, and they live elsewhere: (A1) the bounded auto-integrate (amends a4e9-D1 → id:1048), and (A3) the ambiguous-binding default (amends a4e9-D3's asymmetry, encoded here as spec case E). Meeting `docs/meeting-notes/2026-07-23-1735-relay-orphan-existence-never-blocks.md` (D1 + amendments A2/A3/A4).
  - **RED spec (AMENDED A2/A3/A4)**: `tests/test_orphan_additive_surface_bc49.sh` (`# roadmap:bc49`, hermetic). **Surface-class table (A4-i, SAFETY)**: ONLY the parked-orphan-suppress surface (reconcile-repo.sh `action.kind=="suppress"`, id:1f53) is ADDITIVE; ALL other surface classes stay SUBSTITUTIVE (`units:[]`) — in-flight-elsewhere/claimed (id:ebfb), diverged-from-origin, e3ad fail-closed refusal, discover-error — else an executor dispatches into a repo held by another live run (the **dc5b cross-run collision**). Cases: (A) independent open `[ROUTINE]` id:aaaa + parked orphan for a DIFFERENT open id:bbbb → STILL emit the id:aaaa execute unit + surface the id:bbbb suppress ALONGSIDE (additive). (B) diverged → SUBSTITUTIVE. (C) in-flight/live-claimed repo → SUBSTITUTIVE even with an executable item (dc5b guard). (D) same-item-only: the orphan is bound to the repo's ONLY open item → NO duplicate execute unit; surface reconcile-first (the auto-integrate half is gated on id:1048). (E) ambiguous-binding (A3): an orphan whose commit carries NO bindable `id:` token → ADDITIVE-surface (NOT repo-suppress); failure-keyed guards id:1432/365b are the only backstop. **Enforcement (A4-ii)**: `discover-repo.sh` injects an item-scoped "orphan-parked, reconcile-first, do NOT work id:X" note into the emitted `unit.reason` (the child prompt already relays `unit.reason`), so item-scoping actually reaches the executor.
  - **Acceptance**: tick this box, then `make test` green (the RED test PASSes). The FULL fix surface (all become FALSE under the additive contract): (1) `discover-repo.sh` step-1 routing; (2) the `relay-loop.js:1163` CASE-A shard-prompt routing ("surfaced NON-EMPTY → units:[] and STOP — a surfaced repo is never classified"); (3) the `relay-loop.js:1172` "each repo appears exactly once across units+surfaced" invariant; and (4) the schema comment "a surfaced repo is never dispatched" (relay-loop.js:539/1596). Fix the shard prompt + invariant + comment to mirror the discover-repo.sh additive routing (`node --check` + exec-smoke guard on any relay-loop.js edit). Same-item + parked orphan = reconcile-first, never re-dispatch a duplicate (the sole item-scoped carve-out); its integrate-if-safe half is id:1048.
  - **Context**: D1/A2/A3/A4 (meeting 2026-07-23-1735), a4e9-D3 (RESTORED, not amended) / id:1f53 (the over-reach removed), id:1048 (bounded auto-integrate — the same-item reconcile-first half), id:1432/id:365b (failure-keyed guards — the real "stop"), [[review-me-relay-discipline-cluster-16e3-3684]] (same class), id:75b3, id:3a7a. TODO twin id:bc49.

- [x] [HARD — pool] **Build BOUNDED auto-integrate for stranded orphans — the relay loop auto-completes a COMPLETE + clean-3-way-merge + non-diverged + full-suite-green orphan; everything else stays human-gated `/relay reconcile`** (promoted from TODO id:1048; UN-DEMOTED --fabled 2026-07-23 A1) <!-- id:1048 --> — the D1 "reconcile-first (integrate-if-safe)" rule is a NULL op while this is unbuilt (the loop has no integrate primitive; `/relay reconcile` is human-only), so a single-item-only-orphan repo STALLS pending human reconcile — the exact original complaint (Fable hole-2 regression). This IS the bounded, owner-ratified amendment to a4e9-D1's "NO auto-integration". Extends id:2370 (ledger-only) to CODE-BEARING orphans. Pairs with id:bc49 (existence-never-blocks) — it discharges bc49's same-item reconcile-first integrate half.
  - **RED spec**: `tests/test_bounded_auto_integrate_1048.sh` (`# roadmap:1048`, hermetic). NEW primitive `relay/scripts/auto-integrate-orphan.sh --repo <main-abs> --orphan-branch <relay/orphan/*> [--main-branch <name>]`; suite command injectable via `RELAY_SUITE_CMD` (default `make test`) run in a SCRATCH worktree post-merge; exit 0 = auto-integrated (main advanced `--no-ff`), exit !0 = left parked + surfaced (main UNCHANGED). Cases: (a) COMPLETE+clean+non-diverged+GREEN → auto-integrated (main contains the orphan commit); (b1) RED suite → NOT integrated, main unchanged, orphan intact, surfaced; (b2) CONFLICTING merge → NOT integrated, clean abort (tree left clean), orphan intact, surfaced.
  - **Why [HARD — pool]**: touches the critical integrate path; ANY failure mode (partial/conflict/red/diverged) MUST stay human-gated — a wrong auto-merge is hard-to-reverse. Standard integrate on success (verify→`--no-ff`→ckpt-tag→push equivalent), reusing `drain-integrate.sh`/`ckpt-tag.sh` primitives; NO force/destructive git flags.
  - **Context**: A1 (meeting `docs/meeting-notes/2026-07-23-1735-relay-orphan-existence-never-blocks.md`), id:2370 (ledger-only auto-integrate this extends), id:bc49 (same-item reconcile-first), a4e9-D1 (the "NO auto-integration" ruling this bounded-amends), id:373e (force-free cleanup discipline). TODO twin id:1048.

- [x] [HARD — pool] **Mechanize the discover-PRELUDE (`relay-loop.js:1008` `discover-prelude`) `model:'haiku'` → `model:'bash'`** (promoted from TODO id:86a2; owner-ratified SEPARATE item --fabled 2026-07-23) <!-- id:86a2 --> — the prelude's steps (runId gen, `inject.sh take`, `claim.sh peek`, `discover-sig.sh`, relay.toml own-repo enumeration via lib-own-repos.sh, `stop-sentinel.sh check`) are ALREADY shell, so wrap them into ONE deterministic script dispatched via a single fenced `model:"bash"` command (id:c14d pattern; mirror `discover-repos-mechanical.sh`). No LLM judgment — the prelude never classifies. UN-GATED: the id:af30/2ec4 launch-wall is dissolved by the id:a36e proxy fix (empirically confirmed this session, [[relay-model-proxy-probe-gated-substrate]]). Companion to id:24ec (the SHARD half); DISTINCT item.
  - **RED spec**: `tests/test_prelude_mechanized_86a2.sh` (`# roadmap:86a2`, hermetic). NEW wrapper `relay/scripts/discover-prelude.sh` emits the PRELUDE_SCHEMA object {runId, ts, repos, skippedConfig, liveClaimRepos, injectedUnits, signatures, stopRequested}. Pins: (1) BEHAVIOR — enumerates own repos from `RELAY_TOML` + rolls non-own into skippedConfig + well-formed `runId` (`relay-YYYYMMDD-HHMMSS-<suffix>`); (2) DETERMINISM — the relay.toml-derived parts (repos/skippedConfig) are byte-identical across two invocations; (3) STRUCTURAL — the `discover-prelude` dispatch in relay-loop.js is `model:'bash'`, not `'haiku'`.
  - **Why [HARD — pool]**: touches the CRITICAL discovery path in `relay-loop.js` (Workflow-sandbox-only, [[sandbox-2ec4]] RED-spec-from-worktree hazard — spec via structural/exec-smoke tests). `node --check` + exec-smoke guard on any relay-loop.js edit. Note `inject.sh take` is CONSUMING (side-effecting) — the wrapper runs it exactly once, as the prompt already mandates.
  - **Context**: id:24ec (the discover-run SHARD half → `discover-chunk.sh`), id:6eb3 (the CASE-A content-address residual), id:7402 (residual LLM surface), id:c14d (multi-step-Haiku→one-command pattern), id:a36e (proxy fix), [[classifier-4d8e]]. TODO twin id:86a2.

## Settled-decision detection (meeting `2026-07-24-0929-settled-decision-restated-as-open-968c`, parent TODO id:968c)

- [x] [ROUTINE] **Shared two-directional state-claim contradiction predicate — one engine, two linters (AMENDS id:dafa)** (promoted from TODO id:5533; meeting D2/D5/A3 + the 2026-07-24 owner amendment folding in the 0e99 direction) <!-- children-of:968c --> <!-- id:5533 -->
  - **RED spec**: `tests/test_contradiction_predicate_5533.sh` (`# roadmap:5533`, hermetic — fixture ledgers in `mktemp -d`, never `~/.claude`). NEW shared helper `relay/scripts/lib-state-claim.sh` exposing one function over a single ledger line, modelled on `relay/scripts/lib-typed-edges.sh` (id:65f5, "one engine, two callers"). **Direction (i)** — an OPEN `- [ ]` item whose VISIBLE text asserts a terminal state about ITSELF (`RESOLVED` / `DECIDED <YYYY-MM-DD>` / `SUPERSEDED` / `DONE` / `CLOSED` / `DEFERRED`) is a violation, **UNLESS** the assertion is scoped to another id (`id:XXXX is superseded`). **Direction (ii)** — an OPEN `- [ ]` item whose HTML COMMENT asserts a close while the visible text and the checkbox both say open is a violation. Must-pass fixtures: `- [ ] foo — id:YYYY is SUPERSEDED by this <!-- id:aaaa -->` PASSES (scoped to another id); `- [ ] foo — RESOLVED 2026-07-19 <!-- id:bbbb -->` FAILS (i); `- [ ] foo <!-- closed 2026-07-19 --> <!-- id:cccc -->` FAILS (ii). **Cross-linter invariant**: `roadmap-lint.sh` and `todo-conformance.sh` MUST return the SAME verdict on identical line text — assert it directly (today `roadmap-lint` reads only ROADMAP.md, `todo-conformance` only TODO.md, with divergent word lists, and under single-id-two-views the same line lives in both).
  - **Wiring**: replace `roadmap-lint.sh`'s bare-substring `DECIDED-LEFT-OPEN` rule (`:350-359`) with a call to the helper, keeping its existing WARN/`--strict`-ERROR severity (`:335`); add the same call to `todo-conformance.sh`. Then **revert the id:931c prose reword** at `ROADMAP.md:162` (`SUPERSEDED` → `obsoleted`, made 2026-07-24) — that reword appeased the bug rather than fixing the item, and the scoped predicate exempts the line correctly.
  - **Why [ROUTINE]**: bounded, worktree-verifiable, no sandbox seam — a pure-function predicate plus two call sites, with the acceptance fully expressible as fixtures.
  - **Out of scope**: cross-FILE contradiction detection (the id:74e7 Makefile-vs-SKILL.md class); any new severity mechanism.
  - **Context**: meeting note above; AMENDS id:dafa; evidence for direction (ii) = loderite id:0e99 via `routed:fb6e` (a close recorded only in a comment held 3 ledgers open for a day). Relates id:521f/id:3743 (the anchored-extraction family this must not re-hand-roll).

- [x] [ROUTINE] **Anchored `settles:` / `decided-in:` typed-edge grammar + `orphan-scan --unbackrefed` / `--settled`** (promoted from TODO id:8913; meeting D1/A2) <!-- children-of:968c --> <!-- id:8913 -->
  - **RED spec**: `tests/test_settled_edges_8913.sh` (`# roadmap:8913`, hermetic). Extend id:46f6's typed-edge vocabulary with `<!-- settles:XXXX -->` (authored on a meeting-note `## Decisions` bullet) and `<!-- decided-in:<note-relpath> -->` (authored on the ledger item), reusing the existing `lib-typed-edges.sh` extraction — do NOT hand-roll a sixth extractor. Add two ADVISORY directions to `meeting/orphan-scan.sh`: `--settled` (report ids carrying a `settles:` edge that are still OPEN in a ledger) and `--unbackrefed` (report OPEN `[* — meeting]` / `[INPUT — decision]` items with NO `decided-in:` backref).
  - **REQUIRED must-not-fire fixture**: a note whose `## Decisions` section merely MENTIONS an id, with no `settles:` edge, must produce **zero** `--settled` output. Ground truth in-repo: **id:010c** is open at `TODO.md` and appears under the 2026-07-23 note's Decisions heading *because that decision filed it*; reporting it is the refuted design. Second fixture: a Decisions section using backticked bare tokens (`` `e647` ``, as `docs/meeting-notes/2026-07-17-1541-*.md` does) must also produce zero output — bare tokens are not edges.
  - **PRESENCE-only, never a date comparison** — D1(i) was refuted as self-defeating (adding the backref is itself an edit, so no fixed point exists). Both directions stay advisory (`exit 0`), matching orphan-scan's stated contract ("caller decides severity").
  - **Precedence**: when `--settled` and `--unbackrefed` both fire on one item, `--settled` wins — it carries the evidence; the obligation reports only an absence.
  - **Why [ROUTINE]**: additive directions in a script that already has five, over a grammar that already exists; no severity mechanism, no cross-cutting change.
  - **Out of scope**: retrofitting `settles:` markers into the existing 203-note corpus (that is the accepted forward-looking trade; the backlog is TODO id:d1fb's human pass).
  - **Context**: meeting note above; extends id:46f6; sibling of id:5533.

- [x] [ROUTINE] **Committed fixture snapshot for the WARN→ERROR boundary** (promoted from TODO id:cb3e; meeting D3/A1 — REPLACES the refuted git-blame dating) — UNGATED 2026-07-24 review (dep id:5533 shipped, relay-ckpt-20260724-1632); DONE 2026-07-24: baseline file + `state_claim_in_baseline` wired into both linters (`tests/test_state_claim_baseline_cb3e.sh`, suite 306/0/0). <!-- children-of:968c --> <!-- id:cb3e -->
  - **RED spec**: `tests/test_state_claim_baseline_cb3e.sh` (`# roadmap:cb3e`, hermetic). Capture the open meeting-lane id set at rule-land time into a checked-in baseline file; "new item" = absent from that baseline. Enforced where `--strict` already lives (`roadmap-lint.sh:335`); the baselined population stays WARN. **Acceptance fixture**: an item whose line is rewritten wholesale (as `meeting/md-merge.py` does — it replaces WHOLE LINES by id token and is the mandated edit path for `/meeting` write-back, `/relay human` and `todo-update`) **STAYS in the WARN tier**. That is precisely what killed `git blame` author-time, which dates the last edit rather than creation.
  - **Why [ROUTINE]**: a baseline file plus a membership test; pattern precedent already in-repo (`tools/check-no-bare-rm-f.sh`).
  - **Document the known weakness**: a stale baseline silently re-grandfathers — say so in the file header rather than guarding it.
  - **Out of scope**: `git blame` author-time and `git log --reverse -S` dating (both refuted / O(items)-per-run).
  - **Context**: meeting note above; gated on id:5533 shipping the predicate it draws a boundary for.

- [x] [ROUTINE] **Word-boundary-anchor the `lib-state-claim.sh` terminal-word regex (fixes the compound-word false-positive class)** (filed 2026-07-24 review of id:5533) — DONE 2026-07-26: `STATE_CLAIM_TERMINAL_RE` anchored with a boundary that excludes hyphen (a plain `\b`/`\<...\>` still fires inside a hyphen-joined compound like "fail-CLOSED"); `tests/test_state_claim_word_boundary_78e1.sh`, suite green. <!-- id:78e1 -->
  - **Defect**: the shipped `STATE_CLAIM_TERMINAL_RE` has no word boundaries, so direction (i) fires inside compound words. LIVE false positive on this repo's own ROADMAP — id:6b35's visible prose "fail-CLOSED is the key property" trips the terminal-word match and reports a spurious DECIDED-LEFT-OPEN (verified: `state_claim_violation` on the id:6b35 line returns `i`). The same class would fire on `disclosed`/`enclosed`/`undone`. Precision regression id:5533 introduced by expanding the word list (the old rule had only the deferred/superseded/dated-decision words, none colliding with in-repo prose).
  - **RED spec**: `tests/test_state_claim_word_boundary_78e1.sh` (`# roadmap:78e1`, hermetic) — an OPEN item whose visible text contains `fail-CLOSED` (and `disclosed`, `enclosed`) must NOT fire direction (i); a standalone terminal word still MUST fire; the id:8913 and id:5533 tests both stay green.
  - **Fix**: anchor each terminal word with a word boundary (`\b`, or a bash-portable equivalent) at the two `=~` sites of `lib-state-claim.sh`; the dated-decision and dated-close regexes already carry a trailing space anchor and are unaffected.
  - **Why [ROUTINE]**: a two-line regex tightening plus one fixture; no design decision.

## Mechanical-tier + arg-guard findings (relay session 2026-07-28, run relay-20260728-104330-9348)

- [x] [ROUTINE] **Arg-guard: dropping an unknown flag can silently INVERT the run's scope** (found live 2026-07-28: `/relay --afk --except loderide --quota-7d 100`) <!-- id:f475 --> — **DONE 2026-07-28 (execute):** widened `nearest_escalate_flag` in `validate-flags.sh` to also near-miss-escalate `SCOPE_FLAGS` (`--exclude`/`--only`/`--priority`), with a length-scaled threshold (min 2, else `len/2`) since `--except`→`--exclude` measures edit-distance 4, not the 2 first estimated in the item text. Separately, ANY dropped unknown flag (near-miss or not) now also drops a following non-dash token as its presumed value, so it can never leak through as a bare positional — this is the general fix for the "value survives as an inverted-scope positional" defect, independent of the escalation-set widening. `tests/test_unknown_switch_guard.sh` (roadmap:f475) extended with 3 new cases (§9-11: scope near-miss escalates, far-unknown's value is dropped too, genuine bare positional still passes through); full suite 309/0.
  - **Defect**: `validate-flags.sh` warns-and-drops an unknown leading-dash token, then the front door consumes the CLEANED args. When the dropped flag took a value, that value is left behind as a **bare positional** — which the front door reads as `args.onlyRepo` (the id:7633 single-repo scope). So `--except <repo>` (a plausible misspelling of `--exclude`) silently becomes `--only <repo>`: "every repo BUT this one" inverts to "ONLY this one". Under `--afk` nobody is watching. The live case failed loudly only by luck, because `loderide` was also a typo and LOUD-rejected against `relay.toml`; a correctly-spelled repo name would have run the exact inverse of the request and looked normal in `RELAY_STATUS.md`.
  - **Why the existing escalation misses it**: the guard escalates (non-zero exit) only on an edit-distance-≤2 near-miss of `--afk`/`-d` — the flags that change *mode*. `--except`→`--exclude` is distance 2 but is not in that set, so it takes the silent-drop path. The escalation set was scoped to mode-changing flags; **scope-changing** flags are an equally consequential class and were not considered.
  - **RED spec**: `tests/test_unknown_switch_guard.sh` (existing, `# roadmap:7681`) — add cases. (a) `--except foo` must ESCALATE (non-zero), not drop-and-leave `foo` as a positional. (b) More generally: when an unknown flag is dropped, any token following it that does NOT itself start with `-` must NOT be emitted as a bare positional — either both are dropped together, or the guard escalates. (c) A genuine bare repo positional (`/relay zkm`) must still pass through unchanged — this is the must-not-break fixture, since `--only`-by-positional is a supported form.
  - **Fix direction (executor picks, both defensible)**: EITHER widen the near-miss escalation set to every flag whose drop changes scope (`--exclude`/`--only`/`--priority`), OR make the drop swallow a following non-dash token as the dropped flag's value. Prefer whichever keeps (c) green with less special-casing; state the choice in the test comment.
  - **Why [ROUTINE]**: bounded change to one script that already has the escalation machinery, with acceptance fully expressible as fixtures.
  - **Out of scope**: any change to what `--only`/bare-positional MEANS (id:7633 / the 2026-07-19 drain amendment).

- [x] [ROUTINE] **Mechanize the `release:` hop — haiku → two `model:'bash'` dispatches** (no proxy change needed) — DONE 2026-07-28: `releaseLease()` now dispatches one `model:'bash'` fence per command (`claim.sh release`, the conditional `resource:` release, `heartbeat.sh beat`) via a shared `dispatch()` helper, instead of one Haiku call over an `&&`-bundled prompt. Each fence is a clean single-stage pipeline ending in an allowlisted script, so `_command_allowed()` accepts it standalone; `.catch()` non-fatal semantics preserved per dispatch. `tests/test_release_hop_mechanical_f7d3.sh` (roadmap:f7d3) verified RED before the fix (haiku label) and GREEN after; `tests/test_relay_phase_buckets.sh` updated to match the new `release:${repo}:${label}` label shape (still phase:'Leases'). Full suite 310/0. <!-- children-of:6b35 --> <!-- id:f7d3 -->
  - **Defect**: `releaseLease()` in `relay/scripts/relay-loop.js` (~:2155) spends a **Haiku inference call** whose entire job is running two fixed, allowlisted relay-script commands (`claim.sh release …` and `heartbeat.sh beat …`). It fires **once per completed unit**, so it is the highest-frequency LLM hop in the loop that carries zero judgment.
  - **Why it is not already `model:'bash'`**: the prompt bundles TWO commands (plus a third `&&`-joined branch when `unit.intensive` is set). `mechanical-proxy.py`'s `_command_allowed()` refuses any unquoted sequence operator (`&&`, newline, `;`) — verified — so a single fenced dispatch of the pair can never pass, and a refused command fail-opens to the real model where `"bash"` is not a model (the id:6b35 fail-CLOSED hazard).
  - **Fix**: split into SEPARATE `model:'bash'` dispatches, one fenced command each — `claim.sh release <repo> --run <runId>`, the conditional `claim.sh release resource:<r> --run <runId>`, and `heartbeat.sh beat <runId>`. Each is a clean single-stage pipeline leading with an allowlisted script, so each passes the gate as-is (`claim.sh` and `heartbeat.sh` are both already in `ALLOWED_RELAY_SCRIPTS`). Preserve the existing `.catch()` non-fatal semantics per dispatch — a failed release must stay non-fatal (TTL backstops it).
  - **RED spec**: `tests/test_release_hop_mechanical_f7d3.sh` (`# roadmap:f7d3`, hermetic) — assert the dispatches carry `model: 'bash'` and that each fenced command string is accepted by `_command_allowed()` (drive the predicate directly, as `tests/test_mech_proxy_*.sh` do); assert the intensive branch emits its own dispatch rather than an `&&`-joined one.
  - **Why [ROUTINE]**: mechanical edit to one function, acceptance is a predicate check; no contract or security surface changes.
  - **Context**: sibling of id:4f10 (the remaining haiku hops) and id:d4ca (write-relay-status, which CANNOT take this route — see its gate).

- [x] [ROUTINE] **Audit the two remaining `model:'haiku'` hops (`handback-followup`, `gaming-log`) for mechanization** — AUDITED 2026-07-28, NEITHER converted (both verdict (iii), verified against the live `_command_allowed()` predicate, not theorised): (1) `handback-followup:<repo>` — the script itself IS pure mechanism (a fixed idempotent CLI, no authored prose beyond what the caller passes in), and it is already `+x` with a shebang, so a direct-exec invocation (not `python3 handback-followup.py …`) plus adding it to `ALLOWED_RELAY_SCRIPTS` DOES pass `_command_allowed()` for a plain payload (`_command_allowed()` → True, tested live). But the payload rides in `--gate-reason`/`--split-json`, both composed from a strong child's free-text `handback`/`gate_reason`/seam titles — exactly the class of arbitrary prose this repo's own docs routinely contain backticks/`$(` in, and the quote-blind backtick/`$(` scan refuses those unconditionally even when safely single-quoted (tested live: a backtick in `--gate-reason` → `_command_allowed()` = False). Same fail-closed hazard and same unblock (id:a05c's stdin channel) as id:d4ca — recorded, not converted. (2) `gaming-log:<repo>` — structurally worse: the authored command uses `&&` (`mkdir -p "$(dirname "$log")" && printf … >> "$log"`), a `$(dirname …)` substitution, and `>>` redirection, none of which is a single pipeline ending in a pinned relay script (`_command_allowed()` → False on the as-authored command, tested live) — there is also no existing `ALLOWED_RELAY_SCRIPTS` entry that appends an arbitrary JSON blob to a log path. The JSON payload itself embeds `gaming_flags`, an array of freely-authored `"<id>: <reason>"` reviewer prose (`relay/references/review.md:367`) that can equally carry backticks. Converting this hop would need a NEW dedicated allowlisted script (mirroring `relay-status-publish.sh`) PLUS the same stdin-channel decision as id:a05c — filed as the natural extension of that gate rather than a new one. <!-- children-of:6b35 --> <!-- id:4f10 -->
  - **Task**: `relay-loop.js` still dispatches `handback-followup:<repo>` (~:2101) and `gaming-log:<repo>` (~:2134) on Haiku. Neither was examined in the 2026-07-28 pass. For EACH, determine whether it is (i) pure mechanism — a fixed command over allowlisted scripts, so it can become `model:'bash'` like id:f7d3; (ii) genuine composition (it must *author* prose or make a judgment), so Haiku stays and that is the correct answer; or (iii) mechanism trapped behind a payload the command gate refuses, i.e. the id:d4ca/a05c class.
  - **Done-check**: a written verdict per hop in the item's close note, naming which of (i)/(ii)/(iii) applies and the evidence (the actual command string tested against `_command_allowed()`). Any hop landing in (i) is converted **in this item** with a test mirroring id:f7d3's. Hops landing in (ii) or (iii) are recorded, NOT converted — record *why*, so this is not re-litigated.
  - **Do NOT** convert a hop that composes prose just to save a call: `handback-followup` writes a follow-up ledger line, which may be authorship, not transcription. Check before converting; a wrong conversion silently degrades a write path.
  - **Why [ROUTINE]**: bounded read-and-classify over two call sites with a mechanical acceptance test for any conversion.

- [ ] [ROUTINE] **`write-relay-status`: haiku → `model:'bash'`** 🚧 GATED (DEP: id:33b2 — needs the stdin channel BUILT; the decision itself is settled, id:a05c option B) <!-- children-of:6b35 --> <!-- gated-on:33b2 --> <!-- id:d4ca -->
  - **Why it qualifies**: id:0d31 already collapsed this hop to "pipe one blob to one command" — `relay-status-publish.sh` does all deterministic work (path resolve + c34a guard, claims peek, burnup render, atomic flock'd write, event append). The Haiku agent contributes nothing but latency, cost, and drift risk on a **write path**, and it fires every round.
  - **Why it is BLOCKED today (verified 2026-07-28, not theorised)**: the payload rides in the command string as a heredoc, and `_command_allowed()` refuses it three independent ways — `_has_unquoted_sequence_operator` (payload is multi-line), `_has_unquoted_redirection` (`<<'RELAY_STATUS_EOF'`), and the backtick/`$(` substring scan. Those scans are **quote-blind**, so even a safely single-quoted payload is refused; measured against the live predicate: `echo 'a; b; c' | relay-status-publish.sh` → False, `echo 'see \`foo.sh\`' | …` → False, `echo 'run $(date)' | …` → False. A bare `relay-status-publish.sh --path … --run …` with no payload → **True** (the script is already allowlisted), so it is purely the payload transport that fails.
  - **Do NOT "fix" this by flipping the model**: a refused command fail-opens to the real model, and `"bash"` is not a real model → 404. Because status content embeds repo/item prose (the queued / blocked / REVIEW_ME sections routinely carry code spans), this would break the status write on essentially every substantive round. Fail-CLOSED is the property to preserve (id:6b35).
  - **Unblocks when** id:33b2 lands; then the change is: fence carries the bare one-liner, payload moves to the stdin channel, `model: 'bash'`.
  - **Done-check**: `_command_allowed()` accepts the emitted command; a round-trip test writes a status body containing backticks, `$(`, `;` and newlines and asserts the file content is byte-identical to the payload.

- [x] [INPUT — decision] **Proxy stdin channel — separate the data plane from the command plane** — **OPTION B RATIFIED by the owner 2026-07-28: opt-in subset, NOT all allowlisted scripts.** The stdin fence is gated on an explicit `STDIN_ALLOWED_SCRIPTS` set (initially `relay-status-publish.sh` only), so admitting a script to the channel stays a deliberate, reviewable act rather than a property every future `ALLOWED_RELAY_SCRIPTS` addition silently inherits. Option A (all scripts) was rejected as buying nothing over B except one fewer constant while making the hazard invisible; option C (don't build) was weighed and passed over now that the id:4f10 audit showed the channel unblocks THREE hops, not one. Build carried by **id:33b2**; hop conversions by id:d4ca + id:e405. <!-- children-of:176f --> <!-- id:a05c -->
  - **Proposal**: add a second fence, `` ```relay-mech-stdin ``, whose content `mechanical-proxy.py` pipes to the child process's **stdin** without ever handing it to the shell. The command fence then carries a clean single-stage allowlisted one-liner that passes today's `_command_allowed()` unchanged, and the payload may contain arbitrary markdown because nothing parses it as shell.
  - **Security argument FOR**: stdin is data, not shell input — the injection classes the substring scans defend against (command substitution, sequence operators, redirection) do not exist on a pipe. The id:f9cd property is preserved: stdout is still only the pinned last-stage relay script's own output. It arguably *improves* posture by removing the incentive to smuggle payloads through the command string.
  - **The honest counter-argument** (why this is the owner's call, not an executor's): it introduces a channel that the command scanner does not inspect. That is safe only if every allowlisted script treats stdin as untrusted data — true today for `relay-status-publish.sh`, but it becomes a **standing obligation on every future entry** in `ALLOWED_RELAY_SCRIPTS`. If a script is ever added that `eval`s or sources its stdin, the channel becomes an execution path. Mitigation to decide on: restrict the stdin fence to an explicit opt-in subset of scripts rather than all of them.
  - **Decision needed**: build it (and if so, all-scripts or opt-in subset), or leave `write-relay-status` on Haiku and accept the per-round cost.
  - **Blocks**: id:d4ca. **Not blocking** id:f7d3 or id:4f10 — those need no proxy change.

## Executor-death cluster — promoted from TODO 2026-07-28 (parent meta id:93cc, open since 2026-06-22)

> **Why this section exists.** Every item below was already filed in `TODO.md` — several since
> 2026-06-22 — and **none had ever been promoted to ROADMAP**, so the pool could not dispatch a
> single one while executors kept dying (n>=4: 2026-06-22 ai-codebench; 2x 2026-07-26 loderite at
> ~177,029 / ~176,616 tok; 2026-07-28 loderite). Classic handoff-C2 promotion gap (the 2026-06-25
> truncocraft class): the design ledger held the fixes, the execution queue held none of them.
> Ids are REUSED from TODO (single-id-two-views) — nothing re-minted.

- [ ] [HARD — decision gate] **Record the ACTUAL child death cause — relay child deaths are currently untracked** (promoted from TODO `routed:9c91`) <!-- children-of:93cc --> <!-- id:61fa --> — 🚧 GATED (auto, id:3801; route:decision-gate): Transcript-parsing half needs an architecture call: parse in the off-Workflow driver (id:65f9/2ec4) vs. route through a mechanical model:'bash' hop — the Workflow sandbox itself has no filesystem access to read agent-<id>.jsonl. — needs a /meeting
  - **Defect**: `relay-loop.js:1913` hardcodes `terminalFailReason = 'child agent failed/skipped (API error or terminal failure)'` and DISCARDS the real cause. Every recurrence needs manual transcript forensics and nobody can see the rate. The cause is already on disk: the last entry of `<workflowDir>/agent-<id>.jsonl` carries `isApiErrorMessage:true` plus the literal text (e.g. `Prompt is too long` for loderite run `relay-20260728-112417-3898`, agent `a7106578a0da7e9f6` — 181 entries, 491 KB, died 12 min in, mid-`Read REVIEW_ME.md offset 920`).
  - **Do this FIRST in the cluster**: it is the only item that makes the others' effect measurable. Every other item here fixes ONE cause; none of them counts occurrences.
  - **RED spec**: `tests/test_child_death_cause_61fa.sh` (`# roadmap:61fa`, hermetic — fixture `agent-*.jsonl` in `mktemp -d`). On a null child report, parse the transcript tail and record into the handback reason AND `relay-events.jsonl`: the actual terminal error string, the token count, and a tool histogram. Fixtures: a transcript ending in `isApiErrorMessage:true` + `Prompt is too long`; one ending in a normal result (must NOT be reported as a death); a truncated/corrupt transcript (must degrade to the generic reason, never crash the integrator).
  - **Also emit a running per-cause tally** so recurrence is visible without forensics (mechanize-first / loud-failure heuristic).
  - **SCOPE EXTENDED 2026-07-28 (adversarial review) — add re-dispatch SUPPRESSION, not just recording.** Verified: the `report == null` terminal-fail path (`integrate()`, `relay-loop.js:1908–1922`) pushes a handback but does **NOT** stamp the `noWorkNegCache` — that only fires on `contract_met=false` + route none (`:1940`). Combined with the discovery signature cache reusing an unchanged verdict, **the same repo re-dispatches into the identical death next round**, which is consistent with the 2× same-day deaths on 2026-07-26. Recording the cause without gating on it means the tally grows while quota burns. Add: on a context-death handback, suppress re-dispatch of that repo until the cause is cleared (e.g. its ROADMAP shrinks) — the loud-failure half of the mechanize-first heuristic.
  - **⚠️ PREMISE PROBLEM — found by the 2026-07-28 executor survey, must be resolved before this is worked.** This item assumes `relay-loop.js` can parse the child's `agent-<id>.jsonl`. **It cannot: `relay-loop.js` runs inside the Workflow sandbox, which has NO filesystem access** (confirmed by `test_backstop_fire_log.sh`'s own comment). So the transcript-parsing half is not implementable where this item places it, and likely belongs in the **off-Workflow substrate** (id:65f9 / id:2ec4) — an unresolved architecture question, not a same-repo `[ROUTINE]` fix. **Re-scope before dispatching**: either (a) move the parsing to the off-Workflow driver/daemon and keep only the *recording* side here, or (b) route the cause out through a mechanical hop that CAN touch disk (`relay-state-write.sh` / the `model:"bash"` tier). The **re-dispatch suppression** half may still be in-sandbox (it is a cache stamp, not file I/O) and could be split out as the independently-landable piece.
  - **Why [ROUTINE]** *(now questionable — see the premise problem above; may need re-laning once the substrate question is settled)*: read-side parsing plus two existing sinks and one cache stamp; no contract or model change.

- [x] [HARD] **Dispatch must NAME the item instead of handing over the whole ROADMAP** (promoted from TODO `routed:79dc`) — **DONE 2026-07-28** (background builder + independent adversarial reviewer, apex-supervised). `classify-repo.sh` now appends `own_id` where it used to `+= 1`, and DERIVES the count as `len(actionable_routine_ids)` — so the count↔list invariant is structurally impossible to break, not merely tested. The field flows classify-repo → discover-repo → discover-chunk → `unitPrompt`, verified live end-to-end. Dispatch renders "Work specifically the ROADMAP.md item tagged <!-- id:XXXX -->" plus a bounded 2-item fallback, and fails OPEN to the historical plural instruction on any missing/malformed input. Selection = first in ROADMAP file order (deterministic; a user-injected `--item` outranks it). **Review found and I fixed TWO HIGH issues before merge**: (1) the spec passed on a FULLY UNWIRED build (helper defined, never called — the banked built-green-but-unreferenced class), now pinned by case (8); (2) a named item could be one the classifier had just told the child NOT to work (orphan-parked reconcile-first) — the imperative naming overrode the reason beside it, benign pre-b09e — fixed by publishing `suppressed_item_ids` as a FIELD and subtracting it in the picker, pinned by case (9). Both new cases MUTATION-VERIFIED to fail when their target breaks. Suite 320/0/4-xred. **Honest limit**: this proves prompt text + plumbing, NOT that a Sonnet child stops surveying — that needs a measured tool histogram on the next live dispatch (same limit id:6f1c carries). <!-- children-of:93cc --> <!-- id:b09e -->
  - **🔴 HIGHEST PRIORITY IN THE CLUSTER — the 2026-07-28 ranking flip to `9eb7 > b09e` is REFUTED BY EXPERIMENT.** A loderite child died `Prompt is too long` (218 entries, 12.4 min) with **BOTH landed fixes in force**: `Skill call: None` (the id:9eb7 countermand held, ~26.4k of fixed overhead genuinely gone) and the ledger **6× smaller** after archiving. It still exhausted the window, and its dispatch still read *"Work the open `[ROUTINE]` items in ROADMAP.md"* — plural, unnamed. **Removing the fixed overhead and 5/6 of the ledger was NOT sufficient; the unbounded survey alone is fatal.** So `b09e` is the critical path and `9eb7` was the cheap win — restore this above `9eb7`.
    - **Why the earlier reordering was wrong, recorded so it is not re-derived**: it was made on Fable's corrected tokenizer math, which measured *fixed* overhead. This run measured the thing that actually kills children — the *variable* survey. Correct arithmetic about the wrong quantity. Chain of corrections worth remembering: byte-math estimate → tokenizer measurement → live experiment; each better-grounded than the last, and the final arbiter was running it.
  - **🔴 SECOND CONFIRMATION, now in THIS repo (run relay-20260728-212859-24420, 2026-07-28)**: an execute child died `Prompt is too long` at **peak context 176,841** over 242 entries. Measured tool histogram: **Bash 52, Read 19, Edit 8 — Skill 0, LSP 0, Grep 0**. So the id:9eb7 countermand held (zero Skill calls) and the child STILL exhausted the window purely exploring. This is no longer a loderite-only phenomenon and no longer explicable by fixed overhead. **Until b09e lands, every execute dispatch on a large-ledger repo is a coin-flip on death** — and because id:61fa's re-dispatch suppression is still decision-gated, a relaunch walks straight back into it.
  - **Defect**: the execute-verdict dispatch prompt (`relay-loop.js:1756`) says "Work the open `[ROUTINE]` items in ROADMAP.md" — plural, unnamed — so the child must survey the entire ledger to find its own work. loderite's ROADMAP is **622 KB / 5,619 lines**. One dead child burned 6.5 min ranging over >=8 roadmap ids (c844, bc0e, 5983, 1a5b, 2f81/e7a3, b4b6, d4e9, touch-slot-picker) and died mid-survey **without starting an implementation**.
  - **The data already exists and is thrown away**: `classify-repo.sh:196-214` evaluates the `actionable_routine_open` predicate PER LINE with the item's own 4-hex id in scope (`own_id`, `:159`), and an id-emitting stderr channel already exists there (`why_not_ready`) — but only an integer COUNT survives. Extending that channel is an existing pattern, not new machinery.
  - **RED spec**: `tests/test_dispatch_names_item_b09e.sh` (`# roadmap:b09e`, hermetic). `classify-repo.sh` emits the qualifying ids + their ROADMAP line offsets; the dispatch prompt carries the SELECTED item (or top 2-3 candidates) so the survey phase is **deleted, not merely cheapened**. Fixtures: a ROADMAP with 3 actionable + 5 blocked `[ROUTINE]` items must emit exactly the 3 ids; zero actionable must emit none and change nothing about the existing count.
  - **Highest single leverage in the cluster** — it removes the phase the children actually died in. Independent of id:9eb7 and id:6f1c (those cut fixed overhead; this deletes variable overhead).

- [ ] [HARD — decision gate] **Executor dispatch DOUBLE-LOADS the executor contract — RESCOPED 2026-07-28 after an adversarial review refuted this item's own fix direction and its RED spec** (promoted from TODO `routed:d2a1`) <!-- children-of:93cc --> <!-- id:9eb7 --> — 🚧 GATED (auto, id:3801; route:decision-gate): 9eb7 step 2 (fleet pointer rewrite) needs an owner call between "dedicated relay-executor skill" vs "pointer rewrite" (item's own text) AND touches other repos' CLAUDE.md, out of this repo's executor scope; whole 93cc cluster (61fa/b09e/1af1) is likewise oversized for ROUTINE — recommend a reviewer/meeting pass to hard-split the cluster into pickable seams. — needs a /meeting
  - **Defect, REPRODUCIBLE at n=2** (independent dispatches, not an anomaly): `Skill relay executor` loads a large payload (originally reported as **+26,674 / +26,425 tok** — see the discrepancy note below), then the child Reads `executor-contract.md` + `conventions.md` **again** (+9,505 / +9,473 tok). Combined fixed overhead is a large share of budget, leaving well under 100k working room.
  - **DISCREPANCY SETTLED 2026-07-28 BY TOKENIZER TRUTH — the original `routed:d2a1` numbers were RIGHT; two later "corrections" (including this item's own) were wrong.** The transcripts carry the API's own per-turn `usage.cache_creation_input_tokens` — the exact tokenizer cost of everything added since the previous turn. Nobody had used it; everyone was estimating. **Independently re-verified here** by reading both raw JSONLs:
    - `agent-a7106578a0da7e9f6` and `agent-aa6f06048d7493f02`, entry **[11]** (the `Skill relay executor` turn): **26,394 tok in BOTH children, identical.** Entry [14] (`Read executor-contract.md`): 5,513 / 5,510.
    - vs `routed:d2a1`'s reported Skill = **+26,674** → agreement within **1.05%**, across different runs. **The Skill turn alone really costs ~26.4k. There is no double-count.**
  - **❌ MY RECONCILIATION (the "double-count" hypothesis) IS REFUTED — recorded so it is not re-derived.** It argued `17,548 + 9,505 = 27,053 ≈ 26,674`. That added a **chars/4 UNDER-estimate** to a **measurement** and landed near a third measurement by coincidence — numerology, not reconciliation. A 1.4% fit from mixed-provenance numbers is a warning sign, not evidence.
  - **❌ The evidence file's ~17,548 is also wrong** (its conclusion 2), though its MECHANISM findings all stand. It divided chars by 4. This corpus actually tokenizes at **2.66 chars/tok** (70,194 chars ÷ 26,394 tok) — dense markdown full of code fences, paths and 4-hex ids. Low by ~34%.
  - **⚠️ CLUSTER-WIDE COROLLARY — every `chars/4` estimate in this cluster is ~1.5× LOW for this corpus.** Notably the ledger sizing: loderite's 668 KB ROADMAP is **~250k tok** if fully ingested, not the ~167k a chars/4 estimate gives — i.e. instantly fatal on its own. Even the 81%-archived ~130 KB file is **~49k** if fully read. Re-do any sizing in this cluster at ~2.66 chars/tok before relying on it.
  - **The `+9,505` is REAL and SEPARATE, and reveals a second defect.** Contract Read measured 5,513; `conventions.md` (8,796 B) ≈ ~3.9k at the same ratio; 5.5k + 3.9k ≈ 9.5k. So the 07-26 children read BOTH files as the dispatch instructs — while **both 07-28 children never read `conventions.md` at all** (it appears only in the dispatch prompt). **True combined overhead: ~36.2k when the child obeys the dispatch fully, ~31.9k when it skips conventions — i.e. the ORIGINAL ~36k, not ~27k.**
  - **Post-archive budget reality**: 55.8k baseline + ~31.9k skill/contract ≈ **88k of a ~177k window (50%) consumed before the first exploration step.** (Baseline is not universal — measured `[2]` was 55,757 in one child but 25,856 in the other; do not treat 55.8k as a constant.)
  - **FIX DIRECTION REVERSED — drop the SKILL load, keep the ~9.5k Reads. MEASURED, not inferred** (loderite session 2026-07-28, from both dead children's transcripts; supersedes this item's earlier byte-math estimate).
  - **What the child actually receives.** Transcript entry [10], immediately after the `Skill(relay, executor)` call: **63,220 chars ≈ 15,805 tok** — and the payload is the **orchestrator `relay/SKILL.md`** (64,376 B locally, consistent), NOT the executor contract. Confirmed by content probes finding orchestrator-only sections in the injected text: *Orchestrator invariants (never skip)*, *Drain mode*, *HARD-execute verdict*, *Default mode: autonomous pool*. The executor-contract body is **absent** — children Read it separately, which is the 9.5k half. Total skill overhead ≈ **17.5k** (15.8k SKILL.md + ~1.7k skill_listing attachment).
  - **CORRECTION to this item's own earlier figure**: the ~26.7k / "entire relay doc set" estimate was **byte-math inference and over-stated by ~9k**. The real number is ~17.5k. The verify-first gate this item carried did its job — do not restore the old figure.
  - **The MECHANISM is different from what was assumed, and this is what changes the fix.** The Skill tool **ignores the `executor` arg entirely** and injects the orchestrator doc regardless; the arg is honoured only by *prose inside the payload* (`SKILL.md:35` — "ignore everything below (orchestrator-only)"). So the child pays ~15.8k **in order to be told to skip it**. That is harness-level behaviour, which means **"make the pointer load the contract directly" may not be achievable by editing SKILL.md at all** — do not assume an in-repo edit can fix it.
  - **`SKILL.md:32` is FALSE documentation — fix it regardless of the rest.** It states `/relay executor` "loads **only** `references/executor-contract.md` … it does NOT load the rest of this orchestrator SKILL.md". Measurement refutes both clauses. Self-refuting placement: the claim that the doc is not loaded sits *inside the doc that was loaded*. Correct the text even if the token fix lands elsewhere; a false claim here is what made this overhead invisible for so long.
  - **✅ STEP 1 ACCEPTANCE MET — MEASURED on run `relay-20260728-133022-49` (the pre-registered check, not a re-assertion).** Across **all 67 agents of the run: ZERO `Skill` tool calls** (`grep -c '"name":"Skill"'` = 0 in every `agent-*.jsonl`), and **no ~26.4k `cache_creation_input_tokens` entry anywhere** — the 26,394 turn that appeared in both dead children is simply absent. The children that needed the contract read it directly instead (contract references: 30 / 8 / 5 / 5 / 1 in the working children; the other 62 agents are mechanical/discovery/status hops that never needed it). **Zero child deaths this run** (67 agents, 0 errors) vs n≥4 previously. So the countermand DID beat the CLAUDE.md pointer — the "instruction is not a guarantee" risk did not materialise here.
    - **Do NOT over-claim the baseline.** Entry `[2]` measured 29,945 here vs 55,757 in a loderite child — that gap is **repo-to-repo variation (different CLAUDE.md, different dispatch content), NOT an effect of this change**. If anything the countermand makes the dispatch prompt marginally LONGER. The only defensible claim is the one above: the Skill turn is gone.
  - **⚠️ FRAGILITY — the countermand is currently the ONLY thing preventing the load.** `CLAUDE.md:180` still reads "Load `/relay executor` before working on any item" (unchanged at contract v11). Delete or reword the countermand and every child resumes paying ~26.4k. `tests/test_dispatch_skill_countermand_9eb7.sh` is what stands between that and a silent regression — do not weaken it.
  - **ITEM STAYS OPEN**: step (1) has landed and is verified; step (2) (fleet pointer rewrite) and the dedicated-skill trade have not. Note step (2) is now a *robustness* fix rather than a *savings* fix — the saving is already banked by (1).
  - **FIX — do (1) NOW in one file; (1) is not blocked on anything.**
    1. ✅ **LANDED 2026-07-28** (hand-built, not executor — `tests/test_dispatch_skill_countermand_9eb7.sh` `# roadmap:9eb7`, suite 312/0). **Immediate countermand in the dispatch prompt** (`relay-loop.js` `unitPrompt`): "Do NOT invoke the Skill tool for `relay` — the contract you must follow is the file at `relay/references/executor-contract.md`." The Skill call is triggered by the TARGET repo's `CLAUDE.md` `## Relay contract` section (verified present, loderite `CLAUDE.md:260`); the dispatch prompt never mentions the Skill. A fleet-wide pointer rewrite rides the review cycle and takes as long as the slowest repo — but the countermand lands in ONE file today and covers the dying population (pool children) regardless of fleet state. **Saving: ~26.4k per dispatch** (31.9k → ~5.5k, the contract Read alone).
    2. **Then** rewrite the fleet `## Relay contract` pointer to instruct a direct Read instead of `Load /relay executor`. **Open question to resolve first**: does the pointer auto-refresh rewrite the section TEXT or only the `vN` marker? That decides whether this propagates free at the v11 bump or needs its own sweep.
  - **ALTERNATIVE the owner should weigh (may dominate)**: a dedicated **`relay-executor` skill whose SKILL.md *is* the contract** (12,504 B ≈ ~4.7–5.5k injected). Token-equal to the Read for pool children, but it ALSO fixes **interactive** `/relay executor` sessions, which the pointer-to-Read fix leaves paying the full 26.4k, and it preserves "load the skill" semantics so nobody must remember a path. Cost: new skill surface (Makefile/allowlist/install) + keeping the old arg as a deprecation stub. **If interactive executor sessions are rare, the pointer fix is simpler; if common, this wins.** Owner's trade — do not decide it in the executor lane.
  - **What a child LOSES by never loading the orchestrator doc: nothing identified.** The contract's outbound references (`hard-lanes.md` — `@needs-auth` summarized inline with all 4 mandatory fields; `review.md` §5c/§2b; `handoff.md`; `docs/relay.md`) are pointers, none load-bearing for an executor, and the dispatch prompt independently supplies worktree/lease/size-out/return-schema. The separation `SKILL.md:32` *claims* is real in the docs — only the loader ignores it. *Not exhaustively verified: every contract rule was not diffed against orchestrator-only elaborations.*
  - **SECOND DEFECT FOUND — a silently-skipped instruction**: the dispatch tells the child to Read `conventions.md`, and **both 07-28 children ignored it**. So whatever `conventions.md` carries is already not reliably reaching children. Either fold its load-bearing content into the contract and DROP the instruction (saving ~3.9k when obeyed), or demote it to explicitly advisory. An instruction that is silently skipped is this repo's own no-silent-swallow anti-pattern (memory `no-swallow-stderr` / id:4347).
  - **RANKING FLIPPED — this item now OUTRANKS id:b09e on token savings**: 26.4k deterministic, every dispatch, every repo, with a one-file interim fix — vs b09e's survey saving, which the archive already cut to an estimated ~5–10k on the shrunken ledger. **But b09e is NOT made optional**: the archive is a decaying mitigation (it re-fattens without id:046a wiring), b09e is behavioural rather than merely token-saving (it deletes the phase where children mis-select and range), and it covers every other fat-ledger repo.
  - **THE RED SPEC WAS TESTING THE WRONG SURFACE** (original: "assert the dispatch path references the contract exactly once"). The Skill load is **not commanded by the dispatch prompt at all** — it comes from each target repo's `CLAUDE.md` `## Relay contract` pointer ("Load `/relay executor` before working on any item"). So that assertion can pass green while children keep double-loading via CLAUDE.md. Replacement `tests/test_contract_single_load_9eb7.sh` (`# roadmap:9eb7`) must assert the CHILD'S ACTUAL LOAD BEHAVIOUR — i.e. that the dispatch prompt countermands the pointer, and/or that the fleet pointer text no longer instructs a Skill load — not a property of the dispatch string.
  - **Fleet-pointer change ⇒ ship with id:6f1c in ONE contract bump** (see that item). Changing the pointer text and bumping the contract version separately means two fleet refreshes and a window where pointers and prompt disagree.
  - **Also audit while there**: the pre-first-tool-call baseline measured 57,559 / 55,818 tok — **32% of the window, and no item owns decomposing it**. Report the composition; a reduction is welcome but not required here.

- [x] [ROUTINE] **Teach the executor contract symbol-level exploration — it never mentions LSP / Grep / Glob** (promoted from TODO `routed:59b2`) <!-- children-of:93cc --> <!-- id:6f1c --> — **DONE 2026-07-28 (execute)**: new rule 5c in `relay/references/executor-contract.md` — prefer Grep/Glob/LSP over uncapped Read/`cat`, and never re-read a file already held in this session's context unless there's positive reason to believe its on-disk content changed. Bounded-survey half dropped per the 2026-07-28 amendment (id:b09e obsoletes it once dispatch names the item). Contract bumped v10→v11 (rule content changed); CLAUDE.md `## Relay contract` pointer + the versioning-surfaces table row updated to match. `tests/test_contract_mentions_symbol_tools_6f1c.sh` (roadmap:6f1c) green; asserts the tool mentions, the re-read warning, and vN/pointer agreement. Honest limit unchanged from the item text: this proves the contract TEXT, not a Sonnet child's behaviour.
  - **Defect, n=3**: every dead child used ONLY Bash/Read/Skill and never once called Grep, Glob or LSP. The 2026-07-28 child's tool histogram is `Bash:46 Read:11 Edit:6 Skill:1` — **ZERO Grep, ZERO Glob, ZERO LSP**. They explore by uncapped `cat` / `grep -rn` plus full-file Read; largest single read was 8,074 tok from one `cat src/onboarding-overlay.ts`.
  - **Measured alternative**: `typescript-lsp documentSymbol` on `src/onboarding.ts` ≈ **600 tok** vs ≈ **3,500 tok** for the full Read. LSP is already enabled in `settings.json` — this is a contract-prose gap, not a capability gap.
  - **AMENDED 2026-07-28 (adversarial review): the "BOTH halves required" claim is RETRACTED.** The original text demanded the cheap-tools half AND a bounded-survey half. But **id:b09e obsoletes the bounded-survey half**: once dispatch names the item, there is no survey left to bound. Keep ONLY the tool-teaching half here; if b09e lands first, drop the survey half entirely rather than writing prose for a phase that no longer exists.
  - **📉 SECOND MEASUREMENT CONTRADICTS THE FIRST — this repo, run relay-20260728-212859-24420: `LSP: 0`, `Grep: 0`, `Bash: 52`, `Read: 19`.** With 6f1c LANDED, the child used the old shell-exploration pattern exclusively and made **zero** symbol-level calls. So across two measured children the effect is LSP 1 and LSP 0 — "landing, barely" was generous; here it did not land at all. **Do not close 6f1c on the contract text existing.** The premise that prose changes a Sonnet child's tool behaviour is now weakly contradicted, not supported. If a third child also shows LSP 0, treat exhortation as REFUTED and re-scope: the effective lever is removing the need to explore (id:b09e), not asking nicely.
  - **📊 FIRST MEASURED EFFECT (loderite, 2026-07-28): `LSP: 1` vs `Bash: 53` in one child — the first LSP call an executor has EVER made in that repo.** Read it honestly: the item is landing, *barely*. One call out of 54 tool uses is a signal that the contract text is being read at all, NOT evidence that behaviour changed — exactly the limit this item's RED spec disclaims. Do **not** close on this number. Keep measuring the ratio across runs; a real win looks like LSP/Grep displacing the bulk of exploratory `Bash`, not appearing once beside 53 shell calls.
  - **THE BIGGER HALF IS "NEVER RE-READ WHAT YOU ALREADY HOLD" — measured 2026-07-28, add it to the contract text.** The single largest exploration line items in the dead transcripts were **repeated re-reads of the SAME file**: `agent-aa6f06048d7493f02` read regions of `src/menu.ts` at entries [25], [29], [31], [85], [97] for **+1.4k, +2.1k, +8.2k, +8.1k, +8.5k ≈ 28k tokens on one file**. No tool-choice rule prevents that — a child using Grep perfectly can still re-read. "Prefer LSP/Grep/Glob" is the smaller half; the contract must ALSO state that a file already read this session is in context and must not be re-read, and that re-reading is a signal to re-orient rather than re-fetch.
  - **Honest limit of this item's RED spec — label it, don't oversell it.** `tests/test_contract_mentions_symbol_tools_6f1c.sh` can only prove the contract TEXT names Grep/Glob/LSP. It cannot prove a Sonnet child's behaviour changes. That premise is unverified and this is the least evidentially-supported intervention in the cluster: the tools were **already available** (LSP enabled in `settings.json`) and were ignored in n=3 observed children. Exhortation may simply not work. Treat any measured effect as the real acceptance, and say so in the close note; do NOT record this as "fixed" on a passing grep.
  - **Contract-surface discipline**: `references/executor-contract.md` is a VERSIONED surface (currently v10). Editing it REQUIRES bumping the `contract vN` marker in-file AND updating the `## Relay contract` pointer in `CLAUDE.md` to match — a stale pointer is exactly the silent-breakage class the version marker exists for.
  - **RED spec**: `tests/test_contract_mentions_symbol_tools_6f1c.sh` (`# roadmap:6f1c`) — contract names Grep/Glob/LSP and states the bounded-survey rule; the vN marker and the CLAUDE.md pointer agree.

- [x] [ROUTINE] **BUG: discovery agent surfaced a PHANTOM parked orphan and idled the pool with 0 dispatched** (promoted from TODO `routed:30fd`) — **DONE 2026-07-28** (apex, hand-built): fixed at the root the executor survey located. Two halves, because the parity oracle (id:77ce) forbids the obvious fix of emitting the line from APPLY: **(a) TENSE** — the PLAN-phase surfaced line no longer asserts a COMPLETED rename (`ref renamed to …`, false by construction in `--dry-run` where APPLY never runs); it now states intent and tells the reader to verify the ref. **(b) VERIFY** — `reconcile-repo.sh`'s APPLY park loop now checks `refs/heads/relay/orphan/<bn>` really exists after `worktree-retire.sh` and fails LOUDLY to stderr + `RECONCILE_LOG` when it does not, replacing the silent `|| true` swallow (id:4347). Verification writes to stderr/log ONLY, never to actions/surfaced, so dry-run↔live parity is preserved — asserted directly by the test. `tests/test_phantom_park_verify_1af1.sh` (`# roadmap:1af1`, hermetic) pins all of it, including the case that matters: a FORCED park failure (dirty worktree ⇒ retirement refuses) must make the verifier fire and name the missing ref — the happy path alone cannot prove a verifier works. Suite 316/0. <!-- id:1af1 -->
  - **Defect**: the discovery agent returned `{"surfaced":[{"repo":"loderite","reason":"parked orphan from a dead run — ref renamed to relay/orphan/specfix-1792 …"}]}` and stopped the pool `blocked-pending-human` with **0 dispatched** — but no such ref ever existed. Verified four ways: `relay-reconcile.sh .` → "no parked orphans"; `relay-reconcile.sh --all` → "0 parked orphan(s)"; `git for-each-ref refs/heads/relay` → 15 refs, all `relay/exec/*`+`relay/handoff/*`, no `relay/orphan/*`; `~/.cache/relay/worktrees/loderite/` empty. The nearest real branch `fix/1792-spec-offbyone` is FULLY MERGED. The repo classified `verdict=execute` with `actionable_routine_open=9` throughout, and an identical relaunch dispatched fine and closed id:2f81.
  - **Root shape**: a MODEL CLAIM was trusted as ground truth about ref existence. The repo already has the precedent fix — id:4e14's false-clean bug — and the canonical enumerator `relay-reconcile.sh`.
  - **RED spec**: `tests/test_orphan_surface_real_ref_1af1.sh` (`# roadmap:1af1`, hermetic). The orphan-park surface must be derived from a REAL ref-existence check (reuse `relay-reconcile.sh`, never a hand-rolled `git for-each-ref … 2>/dev/null`), and a surfaced park naming a nonexistent ref must **LOUD-fail**, not silently idle a round. Fixtures: a real parked ref surfaces; a claimed-but-absent ref raises loudly and does NOT suppress dispatch.
  - **Relates**: memory `relay-orphan-existence-never-blocks` (D1 — a parked orphan must never suppress classify/dispatch); this is the same invariant violated via a phantom.
  - **ROOT CAUSE LOCATED 2026-07-28** (executor survey; not yet fixed — it sized out, worktree left clean): `reconcile-repo.sh` emits a PLAN-phase **"ref renamed" surfaced claim UNCONDITIONALLY**, while APPLY-side rename failures are **silently swallowed via `|| true`**. So the surface reports a park that the apply never performed — exactly the phantom. That is the same silent-swallow anti-pattern as the `conventions.md` skip and memory `no-swallow-stderr`.
  - **Constraint on the fix**: it must respect the documented dry-run/APPLY **parity-oracle invariant (id:77ce)** — do not simply make PLAN conditional in a way that breaks parity. This is why the survey judged it too large for one session despite the cause being known; budget accordingly.
  - **Evidence**: run `relay-20260728-111835-4075`, `wf_099fc97f-6d6` journal.jsonl.

- [x] [ROUTINE] **`roadmap-lint.sh`: add an acceptance/done-check clause so a structurally un-workable item is caught** (promoted from TODO `routed:14f4`) <!-- id:213a --> — **DONE 2026-07-28 (execute)**: new doctrine rule 3(c) NO-ACCEPTANCE-NO-TWIN in `relay/scripts/roadmap-lint.sh` (`item_body_end`/`item_has_body_clause`/`has_todo_twin` helpers) — WARN by default, ERROR under `--strict`, same shape as 3(a)/3(b). Tolerates QUALIFIED headings (`**Done-check (when built)**`, the id:89bb/8a5c shape) via a `\*\*(Acceptance|Tests|Done-check)[^*]*\*\*` match, not an exact-close regex. `tests/test_roadmap_lint_acceptance_213a.sh` (roadmap:213a) green. **Blast-radius note**: the new rule fires on almost every minimal one-line test fixture across the suite (they lack body clauses and TODO twins) — fixed by adding sibling `TODO.md` twin stubs to the 5 affected fixture files (`test_roadmap_lint.sh`, `test_roadmap_lint_doctrine.sh`, `test_roadmap_lint_tag_first.sh`, `test_state_claim_baseline_cb3e.sh`, `test_contradiction_predicate_5533.sh`) rather than weakening any assertion — full suite 314/0.
  - **Defect**: the lint's grammar is exactly two clauses (recognized lane tag + 4-hex id) plus two doctrine WARN rules (DECOMPOSED-parent-carrying-a-lane, DECIDED-LEFT-OPEN) — **none of the four inspects the item BODY**. So a bare one-liner with no Acceptance, no Tests and no Done-check passes lint and lands in the dispatchable lane.
  - **Evidence**: all 3 currently-open id:3801-minted seams in loderite (182c, 6258, f0ec — `ROADMAP.md:5614-5619`) are bare one-liners with zero TODO.md twin occurrences.
  - **Clause**: an open item with NO Acceptance/Tests/Done-check in its body **AND** no TODO twin is un-dispatchable → flag it. **ALL LANES** (owner 2026-07-26: measured on loderite, the twin-check alone discriminates — 10 of 13 acceptance-less items are legit `[HARD — pool]` with twins, so `[ROUTINE]`-only scoping is unnecessary).
  - **CRITICAL false-positive guard**: the body matcher MUST tolerate QUALIFIED headings — a naive `/\*\*Done-check\*\*/` regex false-positived id:89bb and id:8a5c, which carry `**Done-check (when built)**`. **Use those two as fixtures.** Key on `seam of <id>`, NOT on `(auto, id:3801)` — 89bb/8a5c prove the bare-title-seam shape predates that script.
  - **RED spec**: `tests/test_roadmap_lint_acceptance_213a.sh` (`# roadmap:213a`, hermetic). Twin of the emitter-side fix id:44a1.

- [x] [ROUTINE] **id:3801's seam emitter CANNOT express an acceptance block — extend the `proposed_split` schema** (promoted from TODO `routed:dbd6`) <!-- id:44a1 --> — **DONE 2026-07-28 (execute)**: `proposed_split` items in `REPORT_SCHEMA` (`relay-loop.js`) now require `acceptance`/`done_check`/`file` alongside `title`; the dispatch-prompt description updated to match. `handback-followup.py`'s `seam_line()` renders each seam with `**Acceptance**`/`**Done-check**`/`**Context**` sub-bullets instead of a bare title line, and a new pre-write guard (`seam_missing_fields`) REJECTS (exit 2, writes NOTHING — same fail-LOUD-write-nothing shape as md-merge's id:1b1a) any hard-split seam missing one of the 3 required fields. `tests/test_seam_emitter_acceptance_44a1.sh` (roadmap:44a1) covers reject-on-missing, reject-on-partial, conforming-render, and an integration check that the rendered seam passes id:213a's `roadmap-lint.sh` NO-ACCEPTANCE-NO-TWIN clause without a TODO.md twin. Updated `tests/test_handback_followup.sh`'s hard-split fixtures to the new required-field shape (existing assertions unchanged, only fixture data extended). **Tradeoff recorded as asked**: this adds prompt/schema surface and mildly disincentivizes the honest bare-title size-out id:3801 exists to encourage — real cost, accepted per the item's own instruction. Full suite green (see RELAY_LOG.md).
  - **Defect is STRUCTURAL, not an oversight**: `handback-followup.py:104` emits each seam as ONE formatted line, and the `proposed_split` schema (`relay-loop.js:1765`, declared again `:667`) is `[{title, tier, dep, id}]` — `title` is the ONLY prose field. So bare one-liners are unavoidable, and `tier:"ROUTINE"` seams drop straight into the dispatchable lane as bare titles. The mechanism also **recurses** (loderite's 182c was itself split into f0ec by the same script, one generation deep already).
  - **Fix**: extend `proposed_split` with REQUIRED `acceptance` + `done_check` fields emitted as sub-bullets, AND (explicit owner requirement 2026-07-26) require each seam to NAME the FILE and the FUNCTION(S) it concerns, so the executor goes straight to the work.
  - **Record the tradeoff honestly in the close note**: this adds prompt surface, mildly disincentivising the honest size-out that id:3801 exists to encourage. That is a real cost, not a nit.
  - **RED spec**: `tests/test_seam_emitter_acceptance_44a1.sh` (`# roadmap:44a1`) — a seam emitted without acceptance/done_check/file is REJECTED at the schema boundary; a conforming seam renders as sub-bullets that id:213a's lint clause accepts. Emitter-side twin of id:213a.

- [x] [ROUTINE] **ONE shared ledger-only-diff predicate — three consumers now want it, including the isolation gate that just false-handed-back** <!-- id:88f0 -->
  - **Trigger (observed live 2026-07-28, run relay-20260728-105959-1379)**: the round-5 `dotclaude-skills` review handed back with `isolation gate failed — worktree/main-checkout isolation breach suspected (id:7612)`. It was a FALSE POSITIVE: the worktree was empty and clean (0 commits ahead of base, `git status` clean — verified before retiring it, nothing lost). What actually advanced main was **three sanctioned ledger-only commits from this session** — `e1ff923` (ROADMAP promotion), `71ddd75` + `23e676a` (inbox ingest stubs). The run ended `blocked-pending-human` on it.
  - **The rules collide by construction**: id:c144 explicitly EXEMPTS ledger-only writes from the relay lease and mandates doing them in the main checkout under flock + atomic scoped commit (that is the documented `/relay human` + `/meeting` write-back path, id:15d5/2147). The isolation gate's heuristic is "worktree empty AND main advanced with a NON-MERGE commit ⇒ suspected child wrote to main". Every id:c144-sanctioned write therefore trips it. This is not a tuning nit — the two documented rules cannot both hold as written.
  - **Fix**: classify the advancing commits. If main's new commits touch ONLY the ledger set (`TODO.md`, `ROADMAP.md`, `REVIEW_ME.md`, `RELAY_LOG.md`, `CHANGELOG.md`), that is the id:c144-sanctioned class → NOT a breach, proceed. If any touches code, defer exactly as today. Fail-safe direction is unchanged: anything not provably ledger-only still defers.
  - **Why ONE predicate, not a local patch (id:415b determinism gate — ≥2 consumers)**: the same classification is already wanted by **two other filed items**, so this is the third consumer and the gate is satisfied. (i) `routed:f5e1` / **id:0f1e** — the classifier counts ledger-only commits as `substantive_unaudited`, producing same-run echo reviews. (ii) `routed:68d7` — the classifier should treat a ledger-only unaudited diff as audit-exempt so it cannot co-schedule a review against an execute round (the id:1735 collision trigger). Build the predicate once as a shared helper (the `lib-typed-edges.sh` / `lib-state-claim.sh` "one engine, N callers" pattern) and wire all three call sites; do NOT hand-roll a third copy.
  - **RED spec**: `tests/test_ledger_only_diff_88f0.sh` (`# roadmap:88f0`, hermetic). Fixtures: a commit range touching only ROADMAP.md → ledger-only TRUE; a range touching ROADMAP.md AND a `.sh` → FALSE; an empty range → FALSE (never vacuously true); a merge commit → unchanged from today. Then assert the isolation gate PASSES on the ledger-only case and still DEFERS on the mixed case.
  - **Do not "fix" this by loosening the gate generally** — the gate caught a real class (id:c6c8: a child dispatched with `isolation: worktree` from the wrong cwd committed straight to a target's main). Narrow it to the sanctioned file set only.
  - **DONE 2026-07-28 (execute):** new shared `relay/scripts/lib-ledger-only-diff.sh` (`ledger_only_diff <repo> <rev-range>`, sanctioned set `TODO.md ROADMAP.md REVIEW_ME.md RELAY_LOG.md CHANGELOG.md`; empty range is never vacuously true) wired into `verify-isolation.sh`'s empty-worktree+main-moved(nonmerge) branch — a ledger-only range now exits 0 naming the id:88f0 exemption; any other content still defers (exit 2) exactly as before. Only the isolation-gate consumer is wired here; id:0f1e and routed:68d7 remain separate items reusing this same function. Registered in `relay_FILES` (Makefile) — not in `relay_EXEC`/`relay_ALLOW` (sourced lib, not directly invoked, matches `lib-own-repos.sh`/`lib-typed-edges.sh`/`lib-state-claim.sh`). `tests/test_ledger_only_diff_88f0.sh` (roadmap:88f0) green; full suite 311/0.

- [ ] [HARD] **Build the opt-in proxy stdin channel** (`` ```relay-mech-stdin ``) — carries the id:a05c option-B ruling. **APEX lane (owner 2026-07-28): this is security-boundary code and is NOT executor work**, regardless of how bounded the acceptance set looks. <!-- children-of:a05c --> <!-- id:33b2 -->
  - **What it is**: a SECOND fence type alongside `` ```relay-mech ``, separating the DATA plane from the COMMAND plane — the command stays a single allowlisted script invocation, while its payload arrives on stdin instead of being interpolated into the command line. This is what unblocks the hops whose payload embeds arbitrary repo/item prose (`write-relay-status`'s heredoc, id:d4ca) that `_command_allowed()` must otherwise refuse.
  - **Acceptance (from the id:a05c ruling, verbatim constraint — do NOT widen it)**: the stdin fence is gated on an explicit **`STDIN_ALLOWED_SCRIPTS`** set, **initially `relay-status-publish.sh` ONLY**. Option A (every `ALLOWED_RELAY_SCRIPTS` entry inherits stdin) was **rejected**: admitting a script must stay a deliberate, reviewable act, never a property a future allowlist addition silently inherits. A change that makes `STDIN_ALLOWED_SCRIPTS` default to, alias, or be derived from `ALLOWED_RELAY_SCRIPTS` is a ruling violation, not an optimization.
  - **Tests** (`relay/scripts/mechanical-proxy.py` has NO `stdin` handling today — verified 2026-07-29, `grep -c stdin` = 0, so every case below starts red): (a) a `` ```relay-mech-stdin `` fence naming `relay-status-publish.sh` runs it with the payload on stdin and the command line free of the payload; (b) the SAME fence naming any script NOT in `STDIN_ALLOWED_SCRIPTS` is **refused**, even when that script IS in `ALLOWED_RELAY_SCRIPTS` — this is the whole point of option B and is the one test that must never be relaxed; (c) a payload containing backticks, `$(…)`, newlines and an unquoted `&&` reaches the script byte-identical on stdin and is never evaluated by a shell; (d) the existing `` ```relay-mech `` fence is unchanged — no regression in `_command_allowed()`'s sequence-operator refusal.
  - **Done-check**: `make test` green including the four cases above, and `grep -n STDIN_ALLOWED_SCRIPTS relay/scripts/mechanical-proxy.py` shows a literal, hand-maintained set — not a derivation.
  - **Out of scope**: converting any hop to use the channel (that is id:d4ca and id:e405, both `gated-on:33b2`); widening the initial set beyond `relay-status-publish.sh`.
  - **What**: `mechanical-proxy.py` gains a SECOND fence, `` ```relay-mech-stdin ``, whose content is piped to the child process's **stdin** and is NEVER handed to the shell. The `` ```relay-mech `` command fence then carries a clean single-stage one-liner that passes today's `_command_allowed()` unchanged. Mirror `_MECH_FENCE_RE` (`:221`) for extraction.
  - **OPT-IN GATE — this is the whole point of option B**: a new `STDIN_ALLOWED_SCRIPTS` frozenset, **initially `{relay-status-publish.sh}` only**, SEPARATE from `ALLOWED_RELAY_SCRIPTS`. A stdin fence addressed to a command whose pinned script is not in that set is REFUSED (fail-open to the real model, exactly as an unallowed command is today). Admitting a script to the channel must be a deliberate edit, never inherited by adding to `ALLOWED_RELAY_SCRIPTS`.
  - **Document the standing obligation IN THE CODE**, next to `STDIN_ALLOWED_SCRIPTS`: every member must treat stdin as INERT DATA — never `eval`, `source`, or shell-interpolate it. This is the one hazard the command scanner cannot see, and the comment is the only place a future author will meet it.
  - **Unchanged invariants** (assert, don't assume): `_command_allowed()` still governs the command fence with no loosening; the id:f9cd property holds — returned stdout is still only the pinned last-stage script's own output; a request with NO stdin fence behaves exactly as today (byte-identical path).
  - **RED spec**: `tests/test_mech_stdin_channel_33b2.sh` (`# roadmap:33b2`, hermetic). (a) payload containing backticks, `$(`, `;`, `&&` and newlines round-trips to the script's stdin **byte-identical** — the exact content classes that make the command-string route impossible; (b) a stdin fence for a script NOT in `STDIN_ALLOWED_SCRIPTS` is refused; (c) a stdin fence whose command fence is itself disallowed is refused (the gate is AND, not OR); (d) no-stdin-fence requests are unaffected; (e) the payload is never shell-evaluated — a payload of `$(touch /tmp/pwned-33b2)` must leave no such file.
  - **Why [HARD] (apex), not [ROUTINE]** — owner call 2026-07-28, overriding this item's original lane. The earlier justification ("ratified design + pinned acceptance set ⇒ bounded enough for an executor") weighed the *specification's* clarity and ignored the *blast radius*: this edits the one component that decides what may execute locally without inference, and its central risk — a payload reaching a shell parser — is precisely the kind a test suite can under-specify while every listed fixture still passes. A pinned acceptance set bounds what is CHECKED, not what is BUILT. Judgement about what was not enumerated is exactly the apex tier's job.
  - **Dispatch note**: `[HARD]` (bare) is the pool-executable apex lane — it routes to the `hard` verdict, which is dispatched ONLY when `STRONG_TIER=opus` (id:da26). It does NOT need a meeting and must not be filed as one.
  - **Unblocks**: id:d4ca (`write-relay-status`) and id:e405 (the other two payload-trapped hops).

- [ ] [HARD] **Convert the two remaining payload-trapped haiku hops once the stdin channel exists** 🚧 GATED (DEP: id:33b2) — **APEX lane (owner 2026-07-28), same reasoning as id:33b2**: this item's job includes ADMITTING two scripts to `STDIN_ALLOWED_SCRIPTS`, which is exactly the deliberate, reviewable act option B exists to force. Having the cheap tier perform that admission would hollow out the ruling — the gate's value is the judgement exercised at admission time, not the edit itself. <!-- children-of:6b35 --> <!-- gated-on:33b2 --> <!-- id:e405 -->
  - **Which two hops**: the payload-trapped `model:'haiku'` hops that id:6b35's scope table lists as NON-eligible *because their payload cannot survive command-line interpolation* — `handback-followup` (`python3` leader + a JSON payload) and `gaming-log` (`$(…)` + `&&` + `>>`). The third such hop, `write-relay-status` (heredoc), is **id:d4ca**, filed separately and also `gated-on:33b2`; the id:4f10 audit found three, so this item is the remaining two. Confirm the exact pair against the id:4f10 audit before starting — do not re-derive it from the table, which is stale in at least one row (see id:c480).
  - **Acceptance**: each converted hop dispatches as `model:'bash'` via a `` ```relay-mech-stdin `` fence whose command is a bare allowlisted script and whose payload travels on stdin; and **each converted script is added to `STDIN_ALLOWED_SCRIPTS` as an explicit, individually-justified line**. That admission IS the deliverable's judgement content (the a05c option-B ruling exists to force it) — a change that admits both in one unexplained edit, or that widens the set by derivation, fails this item even with a green suite.
  - **Tests**: (a) each hop's `agent()` options carry `model:'bash'` and a `relay-mech-stdin` fence; (b) each hop's payload — including one containing backticks, `$(…)` and a newline — round-trips byte-identical to the script; (c) `STDIN_ALLOWED_SCRIPTS` contains exactly the intended entries and no others (guards silent widening); (d) the seven still-ineligible hops in id:6b35's table remain `model:'haiku'` — the same guard id:6b35's own BDD already asserts, extended to the post-conversion set.
  - **Done-check**: `make test` green, and a live pool round completes with both hops exercised (they are low-frequency, so assert via `relay-events.jsonl` rather than assuming a round hits them).
  - **Out of scope**: `write-relay-status` (id:d4ca); building the channel (id:33b2); any hop not in the id:4f10 audit's three.
  - **Source**: the id:4f10 audit (2026-07-28), which classified both as verdict (iii) — pure mechanism trapped behind a payload the command gate refuses — and deliberately did NOT convert them. This item is the conversion it deferred; do not re-audit, the evidence is in id:4f10's close note.
  - **(1) `handback-followup:<repo>`** — the script IS pure mechanism (fixed idempotent CLI, already `+x` with a shebang), and a direct-exec invocation plus an `ALLOWED_RELAY_SCRIPTS` entry already passes `_command_allowed()` for a plain payload (tested live). The blocker is only that `--gate-reason` / `--split-json` carry a strong child's free-text prose, which the quote-blind backtick/`$(` scan refuses unconditionally. **Fix**: move those two payloads onto the stdin channel, add the script to `ALLOWED_RELAY_SCRIPTS` AND to `STDIN_ALLOWED_SCRIPTS`, invoke by direct exec (NOT `python3 handback-followup.py …`, which would lead the pipeline with a non-allowlisted token).
  - **(2) `gaming-log:<repo>`** — structurally worse: the authored command uses `&&`, a `$(dirname …)` substitution and `>>` redirection, so it is not a single pipeline ending in a pinned script, and **no existing allowlisted script appends a JSON blob to a log path**. **Fix**: author that small appender script first (path + blob via args/stdin, creates the parent dir itself, idempotent), allowlist it, then dispatch it as one fenced command with the blob on stdin.
  - **RED spec**: `tests/test_remaining_hops_mechanical_e405.sh` (`# roadmap:e405`) — for each hop, the emitted command is accepted by `_command_allowed()` AND its payload survives byte-identical through the stdin fence, including a `--gate-reason` containing backticks and a `$(`; the new appender creates a missing parent directory and is idempotent on repeat calls.
  - **Do NOT convert a hop whose prose is AUTHORED rather than transcribed** — id:4f10 already established both of these merely pass through caller-supplied text, which is why they qualify. That finding is the licence for this item; re-check it holds if the call sites changed.

## Fable is permanent — retire the availability probe (owner 2026-07-28)

- [x] [ROUTINE] **Retire the Fable-availability PROBE; replace it with explicit local config** (owner 2026-07-28: "there shouldn't _be_ a Fable probe anymore since Fable has become a fixed part of the Max subscription") <!-- id:aa26 -->
  - **DONE 2026-07-28 (execute):** retired `relay/scripts/probe-fable.sh` + `~/.config/relay/fable-probe.json` + `tests/test_probe_fable.sh`. New `relay/scripts/fable-config.sh check` reads `relay.toml`'s `[relay] fable_available` (absent/true ⇒ `available`, `false` ⇒ `unavailable`) — no cache, no staleness window, no spawned agent-probe. SKILL.md step 0 and the Configuration-knobs table rewritten to call it instead of the old probe procedure; `meeting/SKILL.md`'s `--fabled` closing-pass Availability step now calls it too. Makefile's `relay_FILES`/`relay_EXEC`/`relay_ALLOW` swap `probe-fable.sh` → `fable-config.sh`. Default posture UNCHANGED (Opus stays apex, `STRONG_TIER` still defaults `opus`) per this item's explicit behaviour-preserving constraint; `tests/test_strong_tier_knob.sh` + `tests/test_fable_down_strong_tier.sh` needed no changes (neither referenced the probe). `tests/test_fable_config_aa26.sh` (`# roadmap:aa26`) green; full suite green.
  - **Constraint archaeology (CLAUDE.md heuristic), not a cleanup**: the probe was built to dodge a constraint — Fable being intermittently unavailable — that **no longer binds**. The rule says re-justify defensive machinery when its constraint lapses, and do NOT extend a vestige. Everything below exists only to answer "is Fable up?", a question with a now-constant answer.
  - **Retire**: `relay/scripts/probe-fable.sh`, the `~/.config/relay/fable-probe.json` cache, and SKILL.md **step 0**'s probe procedure (the "spawn ONE tiny agent pinned to `claude-fable-5`" branch). Note the probe cost is not merely wasted — it is a spawned agent per staleness window.
  - **Replace with explicit config, NOT a new default guess**: a declared setting (relay.toml `[relay] fable_available = true` or a settings.json env knob — implementer picks, states which) so a user WITHOUT Fable can turn it off. This is the owner's stated reason for keeping any switch at all: other users, not this host. `STRONG_TIER` and `--strong-tier` stay as manual overrides; `-d`/`--fable-down` stays as the honest "my Fable is down" escape hatch and is no longer probe-driven.
  - **BEHAVIOUR MUST NOT CHANGE in this item**: default posture stays exactly as today (Opus apex, Fable optional bonus — the standing 2026-06-15 directive). Whether permanent Fable should CHANGE that posture is **id:698d**, an owner decision, and must not be smuggled in here.
  - **RED spec**: `tests/test_fable_config_aa26.sh` (`# roadmap:aa26`, hermetic) — config absent ⇒ Fable treated available (Max default); config false ⇒ treated unavailable without ever spawning a probe agent; no code path reads or writes `fable-probe.json`. Update/retire `tests/test_strong_tier_knob.sh` + `tests/test_fable_down_strong_tier.sh` to match rather than deleting their coverage.
  - **Docs**: SKILL.md step 0 + the Configuration-knobs table both describe the probe; both must be rewritten in the same change or the doc becomes the vestige.

- [x] [INPUT — decision] **Does PERMANENT Fable change the Opus-apex posture?** — **RULED by the owner 2026-07-28: NO CHANGE. Opus stays APEX; Fable is used OPTIONALLY, ON-DEMAND.** The 2026-06-15 directive (memory `feedback-fable-optional-not-gate`) therefore STANDS unamended even though the scarcity premise it was calibrated against has lapsed — permanent availability makes Fable *reachable*, not *authoritative*, and the owner declined to promote it. Q1 answered. **Q2 (the `fable_rechecked` dormant-queue remnant carried over from id:77f3(c)) is NOT settled here** and moves to id:211d: the owner's "on-demand" framing is PULL-based, which makes a scheduled recheck queue questionable, but retiring `last_strong_ckpt`/`fable_rechecked` (id:e030) is a separate cleanup call to be made while building the escalation chain — **verify nothing already treats it as pending work before touching it**. <!-- id:698d -->
  - **The standing directive** (user 2026-06-15, memory `feedback-fable-optional-not-gate`): **Opus is APEX; Fable is an OPTIONAL bonus re-review, NEVER a required gate.** That was set when Fable was scarce and intermittent — a run could not depend on it. Fable being permanent removes the premise the directive was calibrated against, so it is worth re-confirming rather than assuming either way.
  - **Question 1**: does Fable now become the apex tier for `review`/`hard`, or does Opus stay apex with Fable as bonus? (Do NOT infer from this item that a change is wanted — the directive stands until the owner says otherwise.)
  - **Question 2** (carried forward from the closed id:77f3 sub-action (c), the one live remnant of that item): `fable_rechecked = false` entries in relay.toml were designed as a **dormant, non-gating** queue awaiting "a future window" (id:e030). There is no window any more — Fable is always available. So either that queue becomes LIVE work (optional rechecks actually get scheduled) or it should be retired as a vestige. **Verify nothing already treats it as pending work** before deciding.
  - **Not blocking** id:aa26 — that item is explicitly behaviour-preserving.

- [ ] [INPUT — meeting] **Fable escalation chain — let an Opus agent say "I need Fable on this"** (owner idea 2026-07-28, raised alongside the id:698d ruling) <!-- children-of:698d --> <!-- id:211d -->
  - **Acceptance for a MEETING-lane item is a DECISION LIST, not a test** (roadmap-lint's NO-ACCEPTANCE rule is generic; this is the correct shape for `[INPUT — meeting]`). The meeting is done when each question below has a ratified answer recorded in a meeting note with a `**Decision provenance:**` line.
  - **Inherited constraint — do not re-litigate**: id:698d RULED (owner, 2026-07-28) that permanent Fable does **NOT** change the posture — **Opus stays APEX; Fable is used OPTIONALLY, ON-DEMAND**, and the 2026-06-15 directive stands unamended. Permanent availability makes Fable *reachable*, not *authoritative*. So any design in which Fable becomes a required gate, or in which Opus work is marked "pending Fable", is out of bounds by construction ([[feedback-fable-optional-not-gate]]).
  - **D1 — the escalation MECHANISM**: how does an Opus agent express "I need Fable on this"? Candidates: a typed handback `route:` value the integrator acts on (reuses the existing handback-followup path); an `inject.sh` unit with a Fable verdict (reuses id:baf1, visible in the queue); or a REVIEW_ME box (human-mediated, slowest but zero new machinery). Decide which, and whether the request names a specific ITEM or a whole unit.
  - **D2 — who ratifies**: does an escalation request auto-dispatch a Fable child, or SURFACE for the owner to approve? The 698d "on-demand" framing is **PULL-based**, which argues for surface-then-approve; auto-dispatch would quietly make Fable part of the default path, which is the thing 698d declined.
  - **D3 — Q2, explicitly deferred here by id:698d**: retire the `fable_rechecked` / `last_strong_ckpt` dormant-queue remnant (id:e030, carried from id:77f3(c)) or keep it? The owner's pull-based framing makes a SCHEDULED recheck queue questionable — a pull mechanism and a push queue are redundant. **id:698d attached a precondition to this one, carry it verbatim: "verify nothing already treats it as pending work before touching it."** Concretely: `grep -rn 'fable_rechecked\|last_strong_ckpt' relay/ ~/.config/relay/relay.toml` and confirm no live consumer, before proposing removal.
  - **Out of scope**: re-opening 698d's Opus-apex ruling; making Fable a gate in any form; the `--fabled` meeting closing-pass escalation (that is id:8df5, a different mechanism with its own pre-registered trigger).
  - **The gap it fills**: id:698d settled that Opus stays apex and Fable is used *on-demand* — but there is currently **no mechanism to express the demand**. Fable can only be selected up-front (`--strong-tier fable` / `STRONG_TIER`) by a human at launch. An Opus child that discovers mid-task that it is out of its depth has exactly two options today: push on, or hand back generically. Neither routes to the tier that is now permanently available.
  - **Shape to design**: a structured ESCALATION signal an Opus agent can return — e.g. a `needs_fable: {reason, item}` field in the child report — which the integrator turns into a queued Fable unit (plausibly reusing the existing `inject.sh` path, id:baf1, rather than a new queue). Pull-based, matching the owner's "on-demand" framing.
  - **Why `[INPUT — meeting]` and not pool-executable**: this is not a bounded edit. It needs decisions with real anti-gaming consequences, at least: (1) **what legitimately warrants escalation** — an unbounded "I'd like a second opinion" field is a gaming surface and a cost leak, since the cheapest way to avoid hard work is to declare it someone else's; (2) whether escalation **defers** the item (hand back, requeue for Fable) or **blocks** waiting for it; (3) whether the escalating agent's partial work is kept or discarded; (4) how it interacts with the `hard` verdict's existing `STRONG_TIER=opus` gate (id:da26) and the `fable-standin` marker.
  - **Fold in the id:698d Q2 remnant**: decide here whether the `last_strong_ckpt` / `fable_rechecked` durable recheck queue (id:e030) survives at all. A pull-based escalation chain arguably SUPERSEDES a scheduled push-based recheck queue — if so, retire it as a vestige (constraint archaeology, same reasoning as id:aa26) rather than maintaining both. **Verify nothing currently treats `fable_rechecked = false` as pending work before removing it.**
  - **Prior art in-repo to reuse, not re-invent**: `inject.sh` (queued high-priority units), the `hard` verdict's tier gate (id:da26), and the `@fable-optional-recheck` marker (id:9821) which is the closest existing expression of "Fable could look at this".
  - **Depends on** id:aa26 landing first (the probe retirement) so escalation targets a declared-available tier rather than a probe result.
- [x] [ROUTINE] **Re-dispatch SUPPRESSION after a context death (the in-sandbox half of id:61fa)** — SPLIT OUT 2026-07-28 so the landable half is not blocked by an unresolved architecture question. **This half needs no filesystem access**: on a `report == null` terminal-fail handback, stamp the `noWorkNegCache` (today it is stamped only on `contract_met=false` + route none, `relay-loop.js:1940`) so the discovery signature cache cannot re-dispatch the same repo straight back into the identical death. That gap is consistent with the 2× same-day deaths on 2026-07-26. **Acceptance**: a null-report handback marks the repo suppressed for the run; a normal handback keeps today's behaviour; suppression is visible in `RELAY_STATUS.md` rather than silent. RED spec `tests/test_redispatch_suppression_e3b7.sh` (`# roadmap:e3b7`, hermetic). Parent id:61fa keeps the transcript-parsing half, which is BLOCKED on the substrate question (the Workflow sandbox has no fs access). <!-- children-of:61fa --> <!-- id:e3b7 -->

- [x] [ROUTINE] **`repeatHandbacks` (id:1432) misreads QUEUE EXHAUSTION as a bug signal** (observed loderite 2026-07-28) — **DONE 2026-07-28, SALVAGED from a dead child's unparked worktree.** `classifyRepeatHandbacks()` added to `drain.mjs` + a byte-identical inline copy in `relay-loop.js` (id:4ca8 sync invariant, asserted): an item repeated (>=2 records sharing a `handback_item`) or carrying a non-legitimate `route` is a BUG item; every other is a legitimate size-out counting toward exhaustion; `mixed` when both are present so a real alert is never swallowed by an exhaustion verdict. Verified against the pre-authored RED spec `tests/test_repeat_handback_semantics_3906.sh` — all 4 cases green, including that the real alarm (same item repeatedly) still fires. **PROVENANCE**: the child implementing this died `Prompt is too long` (run relay-20260728-212859-24420) with the work UNCOMMITTED in a run-id-scoped worktree and NO orphan ref — i.e. exactly the id:4df8 stranding case; it survived only because the death was inspected before anything pruned it. The RED spec is what made salvage safe: it verified the stranded work objectively instead of by eye. <!-- id:3906 -->
  - **Defect**: id:1432 surfaces `repeatHandbacks` (an item handed back ≥2× in one run) as "**a bug signal**". On a loderite run it fired ×3 — but reading the three handbacks shows it was not a bug in any sense: **three INDEPENDENT executors each surveyed the whole ROADMAP and reached the same correct conclusion**, that every remaining item was unsafe to land in one session (owner-gated `@manual` on-device confirms, blast-radius holds, or explicitly gated on unlanded ids). `classify-repo.sh` still reported 6 actionable; three children looked at those 6 and judged all 6 undoable. That is the pool correctly reporting **the cheap work is done** — the single most useful thing it can tell an operator — and the detector labels it a bug.
  - **Why this matters more than a wording nit**: the two states are operationally OPPOSITE. "Bug signal" says *investigate the machinery*; "queue exhausted" says *the machinery is fine, bring the human or re-spec the items*. Mislabelling sends the operator to debug a pool that is working perfectly, and buries the real message under an alarm. It also trains the reader to discount `repeatHandbacks`, which then fails to alarm when something IS broken.
  - **Discriminator to implement (the two are mechanically distinguishable, so this need not stay a judgment call)**: a genuine bug = the SAME item handed back repeatedly for the SAME or an incoherent reason, especially by one child retrying. Queue exhaustion = handbacks spanning DIFFERENT items, by DIFFERENT children, each citing a legitimate size-out/gate reason (`route` ∈ {`hard-split`, `decision-gate`, `human`}). The structured handback fields (`handback_item`, `route`, `gate_reason`) already carry everything needed — id:3801 made them mandatory — so this is a classification over existing data, not new instrumentation.
  - **RED spec**: `tests/test_repeat_handback_semantics_3906.sh` (`# roadmap:3906`, hermetic). Fixtures: (a) 3 handbacks, 3 distinct `handback_item`s, all `route` ∈ {hard-split, decision-gate, human} ⇒ classified **queue-exhausted**, NOT a bug alert; (b) 3 handbacks on the SAME `handback_item` ⇒ still a **bug signal** (do not weaken the real alarm); (c) mixed ⇒ report both, never silently pick one.
  - **Surface it as the useful sentence**: on queue exhaustion `RELAY_STATUS.md` should say the executor queue is drained and name what each remaining item needs (hard-split / meeting / human), rather than an alert. Pairs with the id:2d20 "pool busy-loops re-dispatching un-doable HARD units" family.
  - **Out of scope**: changing when a handback is emitted, or the id:3801 follow-up machinery — this is purely how a REPEAT is interpreted and surfaced.

- [x] [ROUTINE] **BUG: dry-round termination counts a WORK-CREATING handback as no-progress → the pool stops holding seams it just filed** (promoted from TODO `routed:b945`, loderite 2026-07-28) — **FIXED 2026-07-28 (apex, hand-built)**: added a `workCreated` term to the round result and excluded it from `isDryRound` in BOTH `drain.mjs` and `relay-loop.js`'s inline copy (byte-identical per the id:4ca8 sync invariant, asserted by the test). **Narrowed routed:b945's proposal deliberately**: it asked for `route` in {hard-split, decision-gate}; **decision-gate creates NOTHING** — it re-tags the parent into the classifier-EXCLUDED lane, REMOVING work, so counting it would keep the loop spinning on a shrinking backlog. Only `hard-split` with a non-empty `proposed_split` counts. Keyed on emitted INTENT rather than the followup's write count because `durableHandbackFollowup` is fire-and-forget and reports nothing back — over-counting is the safe direction and matches this file's own principle ("under-draining merely runs an extra round, over-draining could strand work"). `tests/test_dry_round_work_creating_handback_c919.sh` (`# roadmap:c919`) pins 6 cases + the two-file sync guard, and was **VERIFIED RED against the unfixed predicate** (a scratch copy without the new term returns `isDryRound===true` for the work-creating case) — it was written after the fix, so that verification is what makes it a spec rather than a tautology. Suite 318/0/1-xred. **The general half is NOT done** — `stopReason:"drained"` still asserts nothing; that is id:d6f0, whose RED spec is authored and correctly failing. <!-- id:c919 -->
  - **Defect, VERIFIED in-code here (2026-07-28), not just reported**: `unitIsSubstantive()` is by its own docstring "**only ever called for units that integrated (contract_met)**" (`drain.mjs:31`), so a handback contributes `substantive = 0`. And `surfaced.push(...)` is called **only from DISCOVERY paths** (`relay-loop.js:1246/1252/1281/1320/1353` — shard failure, queue-sig drop, finished-repo, gated-HARD), **never from a handback**. So a handback round scores `substantive==0 && surfaced==0` → `isDryRound` (`drain.mjs:95`) → two in a row → `stopReason:"drained"`.
  - **Why that is wrong**: a `route:hard-split` handback with a non-empty `proposed_split` **demonstrably CREATES dispatchable work** — `handback-followup.py` writes those seams into ROADMAP.md at integrate (and since id:44a1 each carries acceptance/done_check/file, so they are real, workable items). The round that grew the backlog is scored as the round that proved it empty.
  - **Observed**: loderite run `relay-20260728-155041-20282` (`wf_d71b9496-7d8`, rounds=11). 9 seams landed; round 10 handed back id:ec47, round 11 handed back id:c7de with `route:hard-split` + a 4-seam split; followup filed **id:8f6c / id:2435 / id:4bbf / id:0d97** (all `[ROUTINE]`, DEP-chained). The loop stopped anyway, and a fresh `classify-repo.sh` immediately after returned **verdict=execute with actionable work** — so an operator must notice and relaunch by hand.
  - **FIX — do (1); it is the general invariant. (2) is an optimisation, not the guard.**
    1. **Make `stopReason:"drained"` ASSERT it.** Before returning `drained`, run a final `classify-repo.sh` over the in-scope repos and require it reports **no actionable work**. If it reports actionable work, the run is NOT drained — continue, or return a distinct loud reason (e.g. `stuck-despite-actionable`). This is fail-closed and catches **any** state transition the loop fails to observe, not merely this one. "Drained" must never be able to mean "stuck".
    2. **Reset (not increment) the dry counter** when a round emitted a handback whose followup actually WROTE new open items — keyed on what `handback-followup.py` did, not on the `route` string alone (a `hard-split` whose seams were all rejected for missing acceptance wrote nothing and IS a dry round).
  - **⚠️ SYNC INVARIANT**: `drain.mjs` and `relay-loop.js` carry **byte-identical inline copies** of `isDryRound`/`isBlockedRound` (id:4ca8, `relay-loop.js:1022` says so explicitly — the sandbox cannot `import`). Any change must land in BOTH, byte-identical, or the drain contract silently forks between the Workflow and off-Workflow substrates.
  - **RED spec**: `tests/test_dry_round_work_creating_handback_c919.sh` (`# roadmap:c919`, hermetic, unit-tests the pure functions in `drain.mjs`). Fixtures: (a) a round with a `hard-split` handback whose followup wrote ≥1 open item ⇒ **NOT dry**; (b) a `hard-split` handback whose seams were all rejected (nothing written) ⇒ still dry; (c) two genuinely dry rounds ⇒ still `drained`, and the final-classify assertion passes; (d) two dry rounds where a final classify DOES report actionable work ⇒ must NOT return `drained`. Plus a guard asserting the two inline copies remain byte-identical.
  - **FAMILY — this is the third instance of one pattern, worth naming**: a real state transition the loop never observes. Siblings: **id:61fa** (`report == null` never stamps `noWorkNegCache`, so a dead repo re-dispatches into the same death) and **id:3906** (`repeatHandbacks` reads queue-exhaustion as a bug signal). All three are the loop mis-scoring an event it *has* the data for. If a fourth appears, stop patching instances and model the round outcome explicitly.

- [x] [ROUTINE] **EVERY terminal `stopReason` must ASSERT no actionable work remains — `drained` AND `blocked-pending-human`** — RED spec authored 2026-07-28 (handoff C3), NOT implemented; **WIDENED 2026-07-28 by `routed:b874`** <!-- children-of:c919 --> <!-- id:d6f0 -->
  - **RED spec**: `tests/test_drained_asserts_no_actionable_d6f0.sh` (`# roadmap:d6f0`, hermetic) — **currently RED by design**; it is the executable specification, verified failing (`finalDrainVerdict() is missing`). Deliverable is a PURE exported `finalDrainVerdict({dryStreak, actionableAfter, probeOk}) → {drained, stopReason}` in `drain.mjs`, so both substrates share one implementation per the id:4ca8 precedent, plus its wiring at the drain exit.
  - **Contract** (all four cases pinned by the spec): clean drain ⇒ `drained`; **actionable work found after the streak ⇒ MUST NOT return `drained`** (continue, or a loud distinct reason naming the still-actionable repos); a re-derivation that could not run/parse is **fail-closed** (never evidence of drained-ness); the K-streak still gates.
  - **Why this and not more instance-patching** — it closes the CLASS. `drained` is a *claim* nothing checks, inferred from rounds the loop scored itself. Three different unobserved transitions have already produced a false or misread finish: **id:c919** (work-creating handback scored as no-progress — now fixed), **id:61fa** (null report never stamps `noWorkNegCache`), **id:3906** (`repeatHandbacks` reads exhaustion as a bug). Patching instances leaves the fourth undetected; a self-verifying claim does not care which transition was missed.
  - **Use `classify-repo.sh` as the single source** for actionability — do NOT re-implement the predicate (the standing rule that killed several prose-grep re-derivations).
  - **Relationship to the id:4da4 state-machine work**: `a17a` shipped the three Mermaid diagrams and relay-doctor carries invariant checks I1/I7, I2/I4, I5, I8, I9 — but every one of those is a **static check over repo/ledger state at rest**. This family is **round-outcome scoring inside a live run**, which no existing invariant covers. This item is the round-outcome analogue of an I-invariant; if a fourth instance appears, that is the signal to extend the 4da4 matrix to round outcomes rather than add a fifth patch.
  - **WIDENED by `routed:b874` (loderite, 2026-07-28) — the assertion must cover the BLOCKED branch too, not just `drained`.** id:c919 fixed the narrow half (it taught the DRY counter about work-creating handbacks); `isBlockedRound` → `blocked-pending-human` was untouched and is what stopped an observed run that had **`verdict: execute`, `surfaced: []`, and 4 actionable items**. b874 is explicitly NOT a duplicate of c919 — c919 patched one branch, and a per-branch patch leaves the next branch open. **The assertion is what closes the class**, which is why it belongs here rather than as a third instance-fix.
  - **Therefore the contract applies to EVERY terminal stopReason that CLAIMS no work remains** — at minimum `drained` and `blocked-pending-human`. Extend the spec's `finalDrainVerdict` cases to both, and assert that neither can be returned while a re-derivation reports actionable work.
  - **Out of scope**: when rounds are scored dry (id:c919, landed), the K=2 threshold. (The `blocked-pending-human` path is now explicitly IN scope — this supersedes the earlier out-of-scope line, per routed:b874.)

- [x] [ROUTINE] **FLAKY: `tests/test_redispatch_suppression_e3b7.sh` fails nondeterministically — TRIGGER MET (n≥2), promote from observation to FIX** <!-- id:98ea -->
  - **Evidence 2026-07-28, n≥2 — the pre-registered trigger in this item has FIRED.** Full suite: `317/1` naming this file → re-run `318/0` → later suite `317/1` again. Standalone, with NO file changes between invocations: 6/6 pass, then 3/3 FAIL, then 6/0, 5/1, 6/0. **Nondeterministic even in isolation**, so it is not a load-only effect.
  - **⚠️ MIS-DIAGNOSIS CHAIN, recorded so the next person does not repeat it**: called a flake → re-called it a REGRESSION from the id:c919 edit after 3 consecutive standalone failures → that correction was WRONG; further runs were mixed. Three consecutive failures of a ~50% flake is unremarkable, and I treated the cluster as signal. **Do not diagnose this from a small run count**; use ≥10 runs before concluding anything about its cause.
  - **CONCRETE DEFECT FOUND while chasing it (fix this regardless of the flake)**: the structural assertions extract the `if (!report)` block with `awk '/if \(!report\) \{/{flag=1} flag{print; if (/^  return$/) exit}'` — but **`^  return$` occurs ZERO times in relay-loop.js** (the real terminator is 4-space-indented `    return`). So the "block" never terminates and silently captures **674 of 2600 lines**, i.e. most of the file. The greps then pass or fail on text far outside the intended branch. That is a latent false-pass/false-fail generator independent of the timing flake, and it makes this test's structural half nearly meaningless. Fix the terminator (or extract by brace depth) first, then re-measure the flake.
  - **Why record rather than fix**: n=1 (observe-before-preventing). But flag the precedent — id:ab5c was exactly this shape (`test_resource_claim_pid.sh`, passed in isolation, ~50% under load) and its root cause was a **swallowed `jq … 2>/dev/null` read** treated as empty→false under load. If this recurs, look there first before instrumenting anything.
  - **Why it matters disproportionately**: every item's done-check is `make test`, so a flaky suite makes "green" unfalsifiable — the id:ab5c item called it "corrosive" for exactly this reason. A second occurrence should promote this straight to a fix, not more observation.
  - **Trigger to act**: one more full-suite failure of this file. Until then it is a logged observation, and a red suite naming it should be re-run once before being trusted.

## Diagrams: enforce what is already drawn (2026-07-28)

- [x] [ROUTINE] **Diagram EDGE-coverage guard — every `relay-dispatch.mmd` edge must name its enforcer** — RED spec authored, NOT implemented <!-- id:a225 -->
  - **The finding that motivates this, and it is not hypothetical**: `docs/diagrams/relay-dispatch.mmd:89` has read `handback -->|"route: hard-split"| discover` since 2026-07-19 — a hard-split handback flows BACK to discovery, i.e. it creates work and the loop continues. **The code did the opposite for nine days** (scored the round dry → `stopReason:"drained"`), which is id:c919, fixed only after loderite run `relay-20260728-155041-20282` filed 4 seams and the pool quit anyway. **The diagram was right; the code was wrong; nothing could tell.**
  - **Why the existing guard could not catch it — BY CONSTRUCTION, not by oversight**: every assertion in `tests/test_a17a_diagram_state_sync.sh` is `grep -qiw <noun> <diagram>`. It checks the DIAGRAM NAMES every verdict/mode/substrate the CODE has — direction code→doc, **nouns only**. It never asks whether the code honours the diagram's **edges**. The diagrams are therefore documentation that happens to be accurate, not enforcement.
  - **What is achievable, stated so nobody chases the impossible**: you CANNOT mechanically prove arbitrary code honours a drawn edge. You CAN require every edge to name the artifact that enforces it, and fail when an edge names nothing. That turns the diagram into an **index of enforced invariants** and makes an unenforced edge visible instead of silent — which is precisely the c919 gap.
  - **RED spec**: `tests/test_diagram_edges_enforced_a225.sh` (`# roadmap:a225`, hermetic) — **currently RED by design** (`diagram-edge-coverage.sh` missing). Deliverable: `relay/scripts/diagram-edge-coverage.sh <file.mmd>` parsing edges **mechanically from the .mmd** (never a hand-maintained list, which would drift from the drawing). Pinned cases: an unannotated edge FAILS; an `enforced-by:` naming a nonexistent test FAILS (a false coverage claim is worse than none); an explicit `NONE — <reason>` is REPORTED loudly but tolerated (honest backlog); and the `hard-split→discover` edge must be annotated with `test_dry_round_work_creating_handback_c919.sh` as the regression anchor.
  - **Do this BEFORE drawing anything new.** Enforcing what is already drawn locks in c919 and proves the mechanism; drawing more first only adds unenforced prose. The round-outcome states where id:61fa / id:3906 / id:d6f0 live are NOT yet modelled — extending the diagram to cover them is the follow-on (id:5f31), gated on this.
  - **Out of scope**: proving code implements an edge (impossible in general); the ledger/meeting diagrams (extend once this proves its worth).

- [ ] [INPUT — meeting] **Extend the state model to ROUND OUTCOMES (the id:4da4 matrix's missing axis)** — **UN-GATED 2026-07-29: id:a225 CLOSED** (the diagram edge-coverage guard shipped and merged this day, `relay-ckpt-20260729-1215`), so the `🚧 GATED (DEP: id:a225)` prose this line used to carry was stale and is struck. Ready for a meeting. <!-- id:5f31 -->
  - **Acceptance for a MEETING-lane item is a DECISION LIST, not a test.** Done when each question below is answered in a meeting note with a `**Decision provenance:**` line, and the resulting states are added to the id:4da4 matrix.
  - **The gap**: the id:4da4 state model covers per-repo / per-unit states with invariants I1–I9, but has **no axis for what a ROUND as a whole did**. The vocabulary already exists in code, unmodelled and therefore unenforced: `isDryRound` → `drained` (K=2 consecutive no-substantive-progress, id:d58f/4ca8), `isBlockedRound` → `blocked-pending-human`, `substantive`, and `workCreated` (id:c919 — the term that stops a work-creating handback counting as no-progress), plus the `stopReason` categories (`user-stop`, `quota-cache-unreadable`, `quota-exhausted:<bucket>`, `drained`, `blocked-pending-human`).
  - **Why now, and why the original threshold was wrong**: the item previously said "if a fourth instance appears, model round outcomes explicitly". That was recorded as **too lax on reflection** — three independent instances of one class, *each found only after it cost a run*, is already the signal. Do not wait for a fourth.
  - **D1 — the state set**: what are the round outcomes, exactly, and are they mutually exclusive? (`substantive` / `dry` / `blocked` / `work-creating` are currently overlapping predicates, not a partition.)
  - **D2 — the transitions**: which sequences are legal? Specifically, the K=2 dry-round counter is a transition rule that already had one bug (id:c919: a work-creating handback wrongly incremented it), so the counter's reset conditions belong in the model rather than in one `if`.
  - **D3 — the enforcer for each** — this is what id:a225 unblocked. a225 established that **every `relay-dispatch.mmd` edge must NAME its enforcer**, checked mechanically by `relay/scripts/diagram-edge-coverage.sh`. So each round-outcome state/transition added here must arrive with its enforcer named, and the existing guard extends to cover them. Without that, extending the model just produces a more accurate drawing that still cannot fail — the exact reason it was gated on a225 in the first place.
  - **D4 — relationship to `stopReason`**: is `stopReason` the round-outcome axis under another name, or a separate terminal-only projection of it? Answering this decides whether id:d6f0's "every terminal stopReason must ASSERT no actionable work remains" is an invariant OF this model or a sibling check.
  - **Out of scope**: re-deriving the I1–I9 per-unit invariants; changing the K=2 threshold itself (a tuning question, not a modelling one).
  - **The gap**: `a17a` shipped three diagrams and relay-doctor carries invariants I1/I7, I2/I4, I5, I8, I9 — but **every one of those is a static check over repo/ledger state at rest**. The failures that keep recurring are **round-outcome scoring inside a live run**, which no diagram state and no I-invariant covers. Three instances so far: **id:c919** (work-creating handback scored no-progress), **id:61fa** (null report never stamps `noWorkNegCache`), **id:3906** (`repeatHandbacks` reads queue-exhaustion as a bug signal). All three are the loop mis-scoring an event it already has the data for.
  - **Why `[INPUT — meeting]` and not pool work**: the deliverable is a *model* — what the round-outcome states ARE (substantive / dry / blocked / work-created / quota-stopped / user-stopped), which transitions are legal, and which become enforced I-invariants vs report-only. That is design judgement with real consequences (a wrong model mechanizes the wrong stop condition), and it should reconcile with the existing id:4da4 matrix rather than invent a parallel one. **Note id:4da4 has no owning item in this repo** — it is cited (`ROADMAP.md:180`, `TODO.md:72`) but untracked, so the meeting must first establish where that matrix lives.
  - **Gated on id:a225 deliberately**: without edge-enforcement, extending the model produces more accurate drawings that still cannot fail. Enforce first, then extend.
  - **Trigger already met**: I previously set "if a fourth instance appears, model round outcomes explicitly" (id:c919 note). On reflection that threshold was too lax — three independent instances of one class, each found only after it cost a run, is already the signal. Recorded as a correction rather than left implicit.

- [x] [ROUTINE] **BUG: a context-death worktree is never PARKED, so its completed work is unreachable next run and silently reapable** (promoted from TODO `routed:3f22`, loderite 2026-07-28) <!-- children-of:61fa --> <!-- id:4df8 -->
  - **Defect**: the `report == null` terminal-error path (`relay-loop.js:1927`) pushes a handback naming `worktreePathFor(unit)` — but **never parks the branch**. The path is **run-id-scoped** (`~/.cache/relay/worktrees/<repo>/<runId>-<verdict>`), so a relaunch mints a NEW runId, never looks there, and `/relay reconcile` **truthfully** reports "no parked orphans" because no `relay/orphan/*` ref was ever created. The work is not lost-and-flagged; it is invisible, and the next `git worktree prune` takes it.
  - **Nearly cost real work**: loderite's id:2435 output survived only because a human inspected a stale worktree before relaunching.
  - **Why it is cheap to fix — the asymmetry is the whole point**: D1's orphan-park machinery **already exists** and already fires for killed runs; `contract_met=false` genuinely has nothing to save (the contract mandates a clean worktree on size-out, id:8b1f). It is **specifically the terminal-error path** that skips parking. Reuse the existing D1 path (`worktree-retire.sh` → unmerged branch renamed to `relay/orphan/<bn>`) when the worktree has commits or a dirty tree; when it is clean, reap as today.
  - **RED spec**: `tests/test_context_death_parks_worktree_4df8.sh` (`# roadmap:4df8`, hermetic, real git repos in `mktemp -d`). Fixtures: (a) null-report handback whose worktree HAS commits ⇒ a `relay/orphan/*` ref exists afterwards and `relay-reconcile.sh` LISTS it; (b) null-report with a CLEAN, commitless worktree ⇒ reaped, no orphan ref (do not litter); (c) dirty-but-uncommitted worktree ⇒ parked/surfaced, never force-cleaned (id:373e force-free discipline); (d) the resulting surfaced line must name the ORPHAN ref, not the run-id-scoped path a relaunch can never find.
  - **Pairs with id:61fa**: 61fa makes the death VISIBLE (records the real cause); this makes its WORK RECOVERABLE. Neither subsumes the other.
  - **Also fix the handback text**: naming a run-id-scoped worktree path in an operator-facing reason is actively misleading once the run ends — name the orphan ref instead.
  - **CLOSED 2026-07-29 — implemented, SALVAGED from a context-death, then reviewed before the tick was accepted.** The execute child of run `relay-20260729-111723-7520` wrote `retireDeadWorktree()` (47 lines, `relay-loop.js:2042`, called at `:2073`) and ticked both ledger twins, then **died on "Prompt is too long" before committing** — so the fix for "context-death worktrees strand work" stranded itself, which is the sharpest possible confirmation of this item's premise. Recovered by hand as `46b260e` (the prescribed commit-or-park handling being precisely what did not yet exist), then integrated only after review: the salvage touched **only** ROADMAP/TODO/relay-loop.js, so `tests/test_context_death_parks_worktree_4df8.sh` is byte-identical to its authoring commit `40b0c09` (the spec was NOT weakened); that spec flips EXPECTED-RED → PASS; the full suite goes 322/0/5 → **323/0/4**, exactly the +1-pass/−1-expected-red delta a genuine close produces; and the helper is wired, not dead code. Design reuses the canonical `worktree-retire.sh` D1 machinery rather than improvising disposal, is force-free per id:373e, and its handback text now names the ORPHAN REF (fixture (d)).
  - **REVIEW FINDING (recorded, not blocking) — the fix inherits today's id:e62c vulnerability.** `retireDeadWorktree` dispatches via `agent(…, { model: MECH_MODEL })`, and the **same run** that produced this work established (id:e62c, confirmed by its own pre-registered criterion under a verified-healthy proxy) that the safety classifier sits at the `agent()` DISPATCH layer, upstream of where `mechanical-proxy.py` intercepts. So this retire hop is itself classifier-blockable, exactly as `release:` was in this run — meaning a context-death could still fail to park when it matters most. The `.catch` is non-fatal and logs loudly, so the failure is visible rather than silent, and the item's own text already concedes the `reconcile-repo.sh` backstop "may be skipped by the sig-cache". **The durable fix is the same one id:e62c points at: move it off the `agent()` path** (the id:54be front-door trap shape). Not a reason to hold this merge — parking-usually is strictly better than parking-never.

- [ ] [INPUT — meeting] **A safety classifier blocked a MECHANICAL teardown by reading conversational context** (promoted from TODO `routed:643f`, loderite 2026-07-28) <!-- id:51f0 -->
  - **What happened**: `[heartbeat-stop] blocked by safety classifier: [Interfere With Workloads] — "Stopping the heartbeat for run <id> … would end/disrupt the active relay pool run right after the user explicitly demanded 'Continue until it's truly drained!'"`. A routine end-of-run `heartbeat.sh stop <runId>` was refused because the classifier could not verify the runId's provenance **and had absorbed an unrelated USER UTTERANCE from the surrounding conversation**.
  - **DIAGNOSIS (verified here, and it reframes the bug)**: `heartbeat.sh stop` **is already a `model:"bash"` mechanical hop** (`relay-loop.js:2450`, id:6176). A proxy-intercepted `model:"bash"` hop runs the fenced command locally with **ZERO upstream inference** — so no safety classifier can fire on it. **The classifier firing therefore PROVES the mechanical proxy was not in path**, i.e. that run was in `MECH_FALLBACK=fallback-haiku`, where the ~12 mechanical hops degrade into real Haiku inference calls — and inference is subject to safety classification.
  - **So this is a NEW and WORSE symptom of the already-open id:6b35** ("pool-launch proxy coupling", HIGH PRIORITY): 6b35 was filed for hops *404ing* without the proxy. This shows that under the Haiku fallback they don't merely fail — **mechanical teardown becomes subject to conversational inference**, so an unrelated thing the user said can veto a deterministic cleanup step. That is a stronger argument for 6b35's fail-CLOSED launch gate than the 404 case it was filed on.
  - **Residual that is NOT covered by 6b35, and is why this is its own item**: even correctly routed, a mechanical command should not be *phrasable* as an intent a classifier can reason about. Decide whether the fallback path should (a) refuse to run mechanical hops as inference at all (fail loudly rather than degrade into a classifiable request), or (b) emit them in a form carrying no conversational framing. **(a) is the fail-closed reading and is probably right** — a degraded mode that silently changes the SAFETY SEMANTICS of teardown is worse than one that stops.
  - **Second-order hazard flagged by the reporter**: it fired on a run that WAS ending, so the heartbeat may OUTLIVE its run — which the outage watchdog (id:98f0) then reads as a live run. A blocked teardown is not inert.
  - **FOLDED IN: `routed:0931` / TODO id:ee61 (loderite, 2026-07-28) — the escalation, same root cause, corroborates the DIAGNOSIS above.** Run `relay-20260728-211354-12764` (wf_0665ebca-7c9) had **6 of 28 agents blocked**: 3× `heartbeat-beat`, 2× `release:loderite:claim`, 1× `heartbeat-stop`. **All three labels are `model:"bash"` hops** (`relay-loop.js:2552` beat, `:2560` stop, `:2316` release) — so the same proof applies and this run was likewise on `MECH_FALLBACK=fallback-haiku` (`relay-loop.js:243`). What it ADDS beyond the 643f report: the degraded mode reaches **lease release**, not just teardown. Every block reasoned that the runId "was never established as created via any Workflow call in this session" — **that premise is false by construction**: the front door MINTS the runId in shell and passes it as `args.RUN_ID` (SKILL.md step 3, id:c5ba), so it provably cannot appear in any prior transcript. The loop's normal design is being read as evidence of forgery.
  - **Two harms OBSERVED (from ee61), both new evidence for the fail-closed reading**: (1) **a stuck lease** — the blocked `release` left `claim.sh peek` showing loderite held by a run whose pid (2988585) was already dead; a human released it by hand, and until then every later pool/session would DEFER the repo — the exact collision the lease exists to prevent, now caused BY the lease machinery's own blocked teardown. (2) **escalation by delegation-suspicion** — one block cites `[Auto-Mode Bypass]` and calls the retry "tunneling the same underlying manipulation … via sub-agent delegation to obscure it": the loop's ordinary retry path reads as evasion, so **the more the pool retries the more adversarial it looks**. That is a divergent-feedback loop, not a static misclassification, and it argues (a) over (b) in the Residual bullet above.
  - **INTERIM ask carried over from ee61 (not covered by 6b35 or by (a)/(b))**: the pool should SURFACE a blocked release in `RELAY_STATUS.md`, so a stuck lease is VISIBLE instead of silently wedging the next run. This is a backstop that stays useful even after the fallback path is fixed — a release can fail for reasons other than classification.
  - **DECIDED 2026-07-29** (meeting `docs/meeting-notes/2026-07-29-0911-mechanical-hop-proxy-coupling.md`, D1/D3 + amendments D1-A/D3-A, owner-ratified). **Teardown is EXIT-ONLY at the front door**: a trap owns `heartbeat.sh stop` + a NEW `claim.sh release --run <runId>` sweep, both failing LOUDLY to stderr, never `|| true`. `beatHeartbeat` (`:1743`/`:2552`) and per-unit `releaseLease` (`:2415`) **stay in-Workflow** — the sweep makes per-unit release a latency optimization rather than load-bearing, and moving beat would invert its meaning (beat = "the loop made progress"; a shell-lifetime beater beats through a wedged Workflow, blinding id:98f0 and feeding id:33d3/id:9000 a dead signal). Children: **id:89d6** (sweep verb), **id:54be** (front-door trap + mode-b `--afk` prose), **id:554b** (F5: a refusal mints no runId/heartbeat, so it is invisible to the watchdog).
  - **The INTERIM ask above was DISSOLVED then UN-DISSOLVED the same session (D3 → D3-A).** Dissolved because a `RELAY_STATUS.md` row cannot cover its own residual — a SIGKILLed front door has no writer, and the Workflow is gone too. Un-dissolved because the `--fabled` pass verified that D3's dissolution rested on D removing `release` from the classifier's reach, and **it does not**: `releaseLease` is per-unit and mid-round (`:2415`), not teardown. Now **gated on id:e62c** — whether classifier-blocked per-unit releases can recur depends on F2. The reopen trigger's "isn't a classifier block" exclusion is **STRUCK** (it excluded by definition the recurrence F2 cannot rule out). Rider that stands regardless: the real detector for a lease held by a dead run is the already-open **id:33d3/id:9000** claim-liveness item.
  - **Correction to this item's own DIAGNOSIS bullet above**: it proves too much. `heartbeat-beat`/`heartbeat-stop` use `MECH_MODEL`, so the fallback-haiku inference is established for those. But `release:` at `:2316` is **hardcoded `model: 'bash'`** and never reads `MECH_FALLBACK` — so the 2 blocked release hops in `ee61` should have 404'd under this item's own theory, and did not. See **id:e62c**.

## mechanical-hop proxy coupling — fail-closed launch posture (meeting 2026-07-29, parents id:6b35 + id:51f0)

> Promoted 2026-07-29 by relay handoff run `relay-20260729-100152-27550` from `TODO.md`
> §"mechanical-hop proxy coupling 2026-07-29". **Every id here is REUSED from TODO
> (single-id-two-views)** — the same token spans the design ledger ("why") and this
> execution queue ("now"); `orphan-scan.sh --cross-ledger` keeps their checkbox states
> consistent. Full spec + rationale:
> `docs/meeting-notes/2026-07-29-0911-mechanical-hop-proxy-coupling.md` (D1/D2/D3 plus the
> owner-ratified amendments D1-A/D2-A/D3-A made after the `--fabled` closing pass, whose
> escalation trigger FIRED at count 4). Typed edges (`children-of:`/`gated-on:`) are carried
> over verbatim from TODO.

- [ ] [HARD — pool] **PREREQUISITE FINDING (F2) — determine which layer blocked the two hardcoded `model:'bash'` `release:` hops** <!-- children-of:51f0 --> <!-- id:e62c -->
  - **Lane note**: filed in `TODO.md` as `[INPUT — access]`; **owner re-laned it `[HARD — pool]` on 2026-07-29** (this promotion) — the investigation is doable from a worktree plus a controlled probe run, so it is pool work, not a hands/credential item. The TODO line was updated to match.
  - **The question, stated as a disjunction so it can actually be closed**: in loderite run `relay-20260728-211354-12764`, 6 of 28 agents were blocked by the safety classifier. Four of them (`heartbeat-beat` `:2552`, `heartbeat-stop` `:2562`) read `MECH_MODEL`, so they are fully explained by `MECH_FALLBACK=fallback-haiku` — real Haiku inference, classifiable. **The other two (`release:loderite:claim`, `relay-loop.js:2316`) are hardcoded `model: 'bash'` and never read `MECH_FALLBACK`.** Under the meeting's own theory those two should have **404'd**, not been classifier-blocked. Exactly one of the following must be true:
    - **(1) the classifier is harness-side** — it evaluates an `agent()` dispatch *before* the HTTP request, independent of the model string. If so, **proxying confers NO classifier protection**, and D1-A/D3-A's "fail-closed removes classifier exposure" rationale rests on sand.
    - **(2) unknown model names map to a real default upstream** rather than 404ing — which falsifies the fail-closed-404 assumption threaded through id:6b35's prose and code comments.
  - **LEAD found during this handoff (not in the meeting note — treat as evidence, not proof)**: `relay/scripts/mechanical-proxy.py:211` records, from the id:94b8 probe (2026-07-21), that *"the probe saw `model=="bash"` forwarded upstream → 404, never intercepted"*. That is a direct in-repo observation of branch (2)'s premise **failing** — an unknown model name did 404 — which pushes weight onto branch (1). It is not conclusive: the 94b8 probe was a different request shape (proxy fail-open forward) on a different date, and it does not rule out a later upstream change. **Start the investigation from this data point rather than re-deriving it.**
  - **Why this blocks the rest of the cluster**: id:540f/id:c179 are gated on it because a fail-closed launch refusal justified on *classifier exposure* is unjustified under branch (1) — the refusal would still be defensible on **cost** and on the **hardcoded-no-fallback discover hops** (`discover-prelude` `:1114`, `discover-run` `:1279`, both `model:'bash'` with NO fallback, so mode-a's "graceful degradation" was already partial fiction for the highest-frequency hops), but NOT on the reach argument. It is explicitly **not** justified on the quota gate: `quotaGate` already fails closed (`relay-loop.js:1956`, `if (!v || v.exitCode !== 0) { quotaStopped = true }`), agent death included (`--fabled` F6, verified).
  - **Expected cheap answer**: id:c179's self-attesting first mechanical hop is expected to answer this as a side effect — a fenced `true` dispatched as `model:'bash'` with the proxy deliberately out of path either 404s (branch 2 dead) or comes back with something else (branch 2 live), and if it is classifier-blocked instead of either, branch (1) is confirmed directly. **Do not build c179 to close e62c**; run the probe, record the verdict here, then let c179 land.
  - **✅ ANSWERED 2026-07-29 — BRANCH (1) CONFIRMED, by this item's own pre-registered criterion, without needing c179.** The criterion above reads: *"if it is classifier-blocked instead of either, branch (1) is confirmed directly."* That is exactly what occurred, in a run whose conditions make it a controlled discriminator rather than an anecdote. Run `relay-20260729-111723-7520` (wf_27347d26-007), `--afk --only dotclaude-skills`, launched with the proxy **verified in path**: `ANTHROPIC_BASE_URL=http://127.0.0.1:61843`, `probe-mech-proxy.sh discriminate` → `healthy`, `mech-preflight.sh preflight` → `proceed`, so `MECH_FALLBACK=proceed` and **no Haiku fallback was in effect**. The `release:dotclaude-skills:claim` hop — hardcoded `model:'bash'` at `:2316`, never reading `MECH_FALLBACK` — was **blocked by the safety classifier anyway**, citing the same structurally-false premise as every prior instance (*"no corresponding `claim.sh acquire` for that run id is visible in this session — the id appears freshly constructed"*; it was minted in shell by the front door per id:c5ba and therefore cannot appear in any transcript).
  - **Verdict: the classifier sits at the `agent()` DISPATCH layer, upstream of where `mechanical-proxy.py` intercepts at the HTTP layer.** Proxying a hop therefore **cannot** remove it from the classifier's reach. Branch (2) is separately refuted and now irrelevant to the outcome: an unknown model name does still 404 (the id:94b8 note at `mechanical-proxy.py:211`) — the request simply never gets that far when the classifier fires first, which is why the two observations are consistent rather than contradictory.
  - **CONSEQUENCES for the 2026-07-29 meeting's ratified decisions — recorded as evidence, NOT self-settled; the amendment is the owner's call.** **(a) D1-A's front-door EXIT-ONLY teardown is VINDICATED and is the only mechanism yet shown to work** — a front-door shell command is not an `agent()` dispatch, so no classifier sits in its path; **id:89d6** (`claim.sh release --run` sweep) and **id:54be** (the trap) gain urgency and are now the load-bearing fix. **(b) D1/D2's fail-closed launch refusal does NOT fix this failure.** It was ratified partly on the theory that degraded Haiku dispatch is what exposes mechanical hops to the classifier; this run had zero degradation and the block happened regardless. The refusal remains justified on its OTHER, independent grounds (cost, spurious fail-safe stops, the hardcoded-no-fallback `discover-prelude`/`discover-run` hops) — but its **classifier-exposure rationale is falsified**, and id:540f/id:c179 must be re-read in that light rather than inheriting it. **(c)** id:c179 can no longer be justified as the cheap way to close this item; it is now purely a front-door-bypass guard.
  - **Ungates id:540f, id:c179 and (transitively) id:554b** — their `gated-on:e62c` blocker is discharged by this verdict, but see (b): the rationale they were promoted under has changed, so re-read before building.
  - **Done-check**: a written verdict IN THIS ITEM naming (1) or (2), the exact observation that establishes it (request shape, model string, response status/body or block reason, run id), and — if (1) — an explicit correction of D1-A/D3-A's rationale in `ROADMAP.md`'s id:6b35 + id:51f0 blocks. **A verdict of "unclear" is a legitimate outcome** and must be recorded as such rather than guessed; if unclear, say what further observation would settle it.
  - **No RED spec (deliberate, id:108e honesty)**: the question is about live-API / harness behaviour outside the worktree. Any hermetic test would assert something the repo already controls and would NOT discriminate (1) from (2) — a test that cannot fail on the real question is worse than none.
  - **Out of scope**: implementing any of id:540f/c179/554b; changing `mechanical-proxy.py`.

- [x] [ROUTINE] **`claim.sh`: add a `release --run <runId>` sweep verb** (D1-A) <!-- children-of:51f0 --> <!-- id:89d6 -->
  - **What to build**: `claim.sh release --run <runId>` — with **no `<key>` positional** — releases EVERY live claim shard whose JSON `.runId` equals `<runId>`. Today `release` requires a key (`claim.sh release: <key> required`, exit 2) and `--run` only *scopes* a single-key release; the sweep is the missing shape. Reuse the existing flock (fd 9 on `$CLAIM_BASE/.claim.lock`), the existing `safekey`/`$DONE` move, and the existing `log()` line — no new machinery.
  - **Why it matters (this is the load-bearing half of D1-A)**: today a blocked or failed per-unit `releaseLease` (`relay-loop.js:2415`) strands a lease until `CLAIM_TTL` (1800 s default). Observed harm: loderite held by a run whose pid 2988585 was already dead, until a human released it by hand — every later pool/session DEFERRED the repo, the exact collision the lease exists to prevent, caused BY the lease machinery's own blocked teardown. With an exit sweep, **per-unit release stops being load-bearing** and becomes a latency optimization: a blocked one now costs latency on one repo and nothing else. This is what let the meeting keep `beatHeartbeat` and per-unit `releaseLease` in-Workflow instead of moving them.
  - **Contract (the RED spec pins all of it)**:
    - after a run holds N keys, ONE `release --run <runId>` call releases all N (shards moved to `claims.done/`);
    - it is **idempotent** — a second call, or a call naming a run holding nothing, exits 0 and is a no-op;
    - it **NEVER** releases a key held by a *different* run (the run-scoping that already governs single-key release must hold for the sweep);
    - the existing single-key forms (`release <key>` unscoped force-release, `release <key> --run R` run-scoped) are **unchanged** — do not regress them;
    - `release` with neither a key nor `--run` still exits 2 with the usage error.
  - **Tests**: `tests/test_claim_release_run_sweep_89d6.sh` (`# roadmap:89d6`) — hermetic, `CLAIM_BASE=$(mktemp -d)`, `CLAIM_LOG=/dev/null`, never touches `~/.config/relay`. Currently RED (the sweep form exits 2 today).
  - **Done-check**: `tests/run-tests.sh tests/test_claim_release_run_sweep_89d6.sh` green, `tests/run-tests.sh tests/test_relay_claim.sh` still green (no regression to the existing verbs), then tick and run full `make test`.
  - **Out of scope**: calling the sweep from anywhere (that is id:54be); changing liveness/TTL semantics; a `peek --run` filter.

- [x] [ROUTINE] **Front door: EXIT-ONLY teardown trap + mode-b `--afk` prose fix** (D1-A) <!-- children-of:51f0 --> <!-- id:54be -->
  - **What to build**: in `relay/SKILL.md`'s front-door procedure, the shell that launches the Workflow installs a trap that owns **exactly two** teardown actions and nothing else:
    1. `heartbeat.sh stop <RUN_ID>`
    2. the id:89d6 sweep — `claim.sh release --run <RUN_ID>`
    Both **fail LOUDLY to stderr**; **never `|| true`**, never `2>/dev/null` ([[no-swallow-stderr]]). This is the D3-A rider that survives the dissolution: a loud stderr line is louder than a `RELAY_STATUS.md` row nobody reads — and in the residual case (SIGKILLed front door) there is no writer for a status row at all.
  - **EXIT-ONLY is the point, and the boundary is explicit**: `beatHeartbeat` (`relay-loop.js:1743`, `:2552`) and per-unit `releaseLease` (`:2415`) **STAY in-Workflow**. Beat *means* "the loop made progress" — it fires at the round prelude. A shell-lifetime beater would beat through a **wedged** Workflow, blinding the id:98f0 outage watchdog and feeding id:33d3/id:9000 a signal that no longer tracks liveness (`--fabled` F4). An orphaned beater is strictly worse than a TTL-stale one. Do not "helpfully" move beat.
  - **Second deliverable — the mode-b prose fix**: `relay/SKILL.md` step 0b currently tells an unattended run to "**proceed conservatively** (pass `MECH_FALLBACK=abort` — the loop keeps `model:"bash"`, which fail-opens as before…)". After D2 that is a direct contradiction: mode-b becomes a launch **refusal**. Rewrite that bullet so `abort` means abort. (The code half of that change is id:540f/id:c179; this item owns the front-door prose so the two do not disagree in the interim.)
  - **Contract (the RED spec pins all of it)**:
    - a Workflow that RETURNS leaves no claim shard whose `.runId` is that run;
    - a Workflow that DIES (non-zero exit / signal) leaves no claim shard whose `.runId` is that run — i.e. the trap is on EXIT, not on the success path;
    - a FAILED release/heartbeat-stop **prints to stderr** (assert stderr non-empty) and the failure is not swallowed — assert the SKILL.md teardown block contains no `|| true` and no `2>/dev/null` on either command;
    - the teardown block references `heartbeat.sh stop` and `claim.sh release --run` and **nothing else** (the two-action cap);
    - `relay/SKILL.md` no longer tells an unattended mode-b run to proceed.
  - **HOW the teardown is expressed — an ANCHORED fence, not prose (spec decision made in this handoff)**: `relay/SKILL.md` carries the teardown between `<!-- teardown-trap:start -->` and `<!-- teardown-trap:end -->`, holding **exactly one** ` ```bash ` fence. The snippet is **self-contained**: sourced in a shell where `$RUN_ID` is set it installs an `EXIT` trap and does nothing else, and it names the scripts by their installed prefix `~/.claude/skills/relay/scripts`. **Why**: a prose grep is the vacuous-guard failure id:cdcf documents — reword the sentence and the scoped region silently empties, so the check passes having checked nothing. The anchor makes the region structural AND lets the RED spec *execute* the documented snippet (rewriting only that path prefix to a stub dir) instead of re-implementing it, so the test can never drift from the doc.
  - **Tests**: `tests/test_front_door_exit_teardown_54be.sh` (`# roadmap:54be`) — hermetic, `CLAIM_BASE` + stub scripts in `mktemp -d`. Six sections: (1) the anchored region exists with exactly one fence; (2) exactly the two permitted actions, and it must NOT beat the heartbeat; (3) it is an `EXIT` trap with no `|| true` and no `2>/dev/null`; (4a/4b) the extracted snippet is EXECUTED against the real `claim.sh` after a stub Workflow that returns and one that exits 7 — no shard left carrying that `.runId`, and another run's shard untouched; (4c) a stubbed failing `claim.sh` must leave stderr non-empty; (5) `relay/SKILL.md` no longer says "proceed conservatively". **Currently RED at (1)** — no teardown trap is documented at all today.
  - **Done-check**: `tests/run-tests.sh tests/test_front_door_exit_teardown_54be.sh` green, then tick and run full `make test`. Also re-run `tests/run-tests.sh tests/test_relay_claim.sh tests/test_relay_claim_liveness.sh`.
  - **Depends on** id:89d6 (the sweep verb must exist for the trap to call it) — **not** hard-gated, because the prose half and the trap shape can be authored first; but the behavioural half of the spec cannot go green until 89d6 lands. Sequence 89d6 → 54be.
  - **Out of scope**: moving beat or per-unit release out of the Workflow; any third enforcement layer; a breadcrumb file duplicating `claim.sh peek`.

- [x] [ROUTINE] **Correct the stale `id:6b35` scope table — and add the lint that keeps it honest** <!-- children-of:6b35 --> <!-- id:c480 -->
  - **The defect, exactly** (HISTORICAL — fixed by this item; the id:6b35 table quoted below no longer says this): `ROADMAP.md`'s id:6b35 block used to have an "OUT of scope" bullet that listed the `release` hop's label prefix (~1993, `claim.sh release && heartbeat.sh beat` — two commands) as MUST-STAY-haiku. **That was no longer true**: id:f7d3 SPLIT that hop and converted it to a mechanical dispatch, and `tests/test_release_hop_mechanical_f7d3.sh` asserts it. (Current state, verified 2026-07-31: the hop is `relay-loop.js:2361`, `model: MECH_MODEL` — commit 490ac6e / id:4239 replaced the `model: 'bash'` literal with the `MECH_MODEL` indirection defined at `:118`. Still mechanical, no longer a literal. The `:2316` / `model: 'bash'` phrasing this bullet used to carry was stale on both counts.) An implementer working the id:6b35 table faithfully would have "restored" `model:'haiku'` and thereby **re-introduced the exact invariant violation f7d3 removed** — see the corrected table above (line ~122) and `tests/test_roadmap_scope_table_consistency_c480.sh`, which now guards it.
  - **Why it is more than a text fix**: this is a ledger claim about code that drifted the moment the code changed and nothing noticed for a week. Fix the text **and** add the consistency check, or the next conversion silently re-rots the same table. This is the [[relay-builtgreen-but-unreferenced]] / "loud detection that nothing acts on" class one step earlier: here there was no detection at all.
  - **What to build**:
    1. Correct the id:6b35 "OUT of scope" bullet — remove `release:` from the MUST-STAY-haiku list, and note inline that id:f7d3 converted it (with the current line number), so the correction itself carries its provenance.
    2. A **consistency lint** — extend the existing `relay/scripts/roadmap-lint.sh` (do NOT write a new one-off scanner; see the repo's no-improvise rule) with a check that, for every hop label the id:6b35 scope table names as MUST-STAY-`model:'haiku'`, the corresponding dispatch in `relay/scripts/relay-loop.js` is in fact `model: 'haiku'` — and fails LOUDLY (non-zero) when the table and the code disagree in either direction.
  - **Contract (the RED spec pins all of it)**:
    - the id:6b35 block does NOT list `release:` under MUST-STAY-`model:'haiku'` while `relay-loop.js` dispatches a `label: 'release:…'` as `model: 'bash'` — i.e. the specific live contradiction is gone;
    - the lint EXISTS and is invoked by the suite (a check nothing invokes is not a check, id:de36);
    - the lint FAILS on a fixture where the table and a stub loop disagree, and PASSES on a consistent fixture — **both directions**, so it cannot pass vacuously;
    - the lint's hop-name list is parsed **from the ROADMAP table**, never hardcoded (a hardcoded list is the same drift one level down).
  - **Tests**: `tests/test_roadmap_scope_table_consistency_c480.sh` (`# roadmap:c480`) — hermetic, fixtures in `mktemp -d`. Currently RED on both the live contradiction and the missing lint.
  - **Done-check**: `tests/run-tests.sh tests/test_roadmap_scope_table_consistency_c480.sh` green, then tick and run full `make test`.
  - **Do this FIRST of the three id:6b35 children** (before id:540f/id:c179 are unblocked) — the meeting's own instruction: "Must be fixed in the same change or an implementer will faithfully restore an invariant violation."
  - **Out of scope**: re-auditing the other 6 hops in the OUT-of-scope list (id:4f10 already did two of them and recorded verdicts); converting any hop.

- [ ] [ROUTINE] **`mech-preflight.sh`: mode-a AND mode-b become launch REFUSALS; the `abort` token actually aborts** (D1/D2) 🚧 GATED — **OWNER GATE (owner directive 2026-07-31): this refusal does NOT land until the owner explicitly says so.** Rationale: the refusal makes the relay pool unrunnable in any session launched WITHOUT `ANTHROPIC_BASE_URL`, i.e. every `/remote-control` session (id:b0b1) — today mode-a is merely costly (~12 hops degrade to Haiku), after the refusal it is fatal. Do NOT treat the discharge of the e62c gate as authorisation to build; that gate is technical, this one is the owner's. (Prior DEP: id:e62c — the fail-closed rationale must survive F2; a branch-(1) verdict removes the classifier-exposure argument but NOT the cost / hardcoded-no-fallback-discover-hops arguments, so re-read e62c's verdict before implementing) <!-- gated-on:e62c,b0b1 --> <!-- children-of:6b35 --> <!-- id:540f -->
  - **Today's behaviour, verified**: `mech-preflight.sh preflight` exits **0 for all three modes** and the caller branches on the stdout token. Mode-a emits `fallback-haiku`, and `relay-loop.js:248` reduces it to `const MECH_MODEL = MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'` — degrading ~12 mechanical hops into real Haiku inference. Mode-b emits `abort`, and `relay-loop.js:243`-ish logs *"WHOLE SESSION DEGRADED"* **and keeps `model:"bash"`** — it fails OPEN. **The token has been lying since id:4239 shipped.**
  - **Why mode-b's refusal is entailed a fortiori**: in mode-a the real API IS reachable (the fallback at least executes); in mode-b `ANTHROPIC_BASE_URL` points at a DEAD proxy, so *nothing* is reachable and a Haiku fallback is impossible. If mode-a refuses to launch, mode-b refusing follows. Leaving mode-b a warning is the "loud detection whose resolution silently no-ops" anti-pattern.
  - **What to build**: mode-a and mode-b both become **launch refusals** at the front door — the helper emits a refusal signal the front door cannot ignore (non-zero exit and/or a distinct token), the loud stderr warning naming the relaunch env (`ANTHROPIC_BASE_URL=http://127.0.0.1:61843`) is PRESERVED verbatim, and the front door does **not** launch the Workflow. `proceed` is unchanged.
  - **Contract**: `preflight` against a **stubbed** mode-a probe emits a refusal and the front door does not launch; same for a stubbed mode-b probe; a stubbed healthy probe still emits `proceed` and launches. Stub via `MECH_PROBE=<fixture>` — the helper already takes that override and is documented hermetic (no writes, no cache, no `~/.claude` touches).
  - **Tests**: extend `tests/test_mech_preflight.sh` (do not fork a parallel file — it already stubs all three modes); add the front-door-does-not-launch assertion as a new `# roadmap:540f`-headed case there or in a sibling if the existing header must stay `4239`.
  - **Done-check**: the mode-a and mode-b cases assert refusal, the healthy case still passes, then tick and run full `make test`.
  - **Out of scope**: the `MECH_MODEL` ternary deletion and the self-attesting hop (both id:c179); the seven non-eligible `model:'haiku'` hops; any third enforcement layer.

- [ ] [ROUTINE] **`relay-loop.js`: self-attesting first mechanical hop; delete the fallback ternary** (D2-A, SUPERSEDES D2's token assertion) 🚧 GATED — **OWNER GATE (owner directive 2026-07-31): the ternary deletion does NOT land until the owner explicitly says so** — deleting the `MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'` ternary IS half the refusal (it removes the only path that lets a no-`ANTHROPIC_BASE_URL` session run at all), so it carries the same id:b0b1 `/remote-control` conflict as id:540f and is gated identically. Note this line previously carried NO `gated-on:` marker at all despite its 🚧 prose — the mechanical edge engine read it as ungated; that is now fixed. (Prior DEP: id:e62c — this hop doubles as the F2 probe, so run e62c's observation first and record its verdict; implementing before then risks encoding the wrong rationale) <!-- gated-on:e62c,b0b1 --> <!-- children-of:6b35 --> <!-- id:c179 -->
  - **What to build**: as the loop's FIRST act, dispatch a trivial fenced `true` as `model:'bash'` and **refuse the run** if the proxy sentinel does not come back. Then **delete** the `MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'` ternary at `relay-loop.js:248` so `MECH_MODEL` is an **invariant**, not a fallback selector.
  - **Why a token assertion CANNOT work (`--fabled` F3, verified against the code)**: `const MECH_FALLBACK = A.MECH_FALLBACK || ''` (`:247`) plus `'' → 'bash'` (`:248`) makes a caller that **skips the front door entirely** indistinguishable from a healthy one. An assertion on the token would therefore pass on exactly the threat it was specified to catch. The self-attesting hop trusts **reality** rather than args, resolves the `''`-means-healthy ambiguity without changing SKILL.md's token contract, and stays inside the two-layer enforcement cap.
  - **Contract**: a run launched WITHOUT the proxy refuses at hop 1 and **dispatches nothing** (assert zero subsequent `agent()` dispatches, not merely a logged warning); a run WITH the proxy proceeds normally; `grep -c "fallback-haiku" relay/scripts/relay-loop.js` shows the ternary is gone; `node --check relay/scripts/relay-loop.js` passes (the loop-crash class — escape backticks inside template literals).
  - **Tests**: extend `tests/test_relay_loop_mech_emitter.sh` / `tests/test_relay_loop_structure.sh` rather than forking a new structural scanner; add a `# roadmap:c179` case asserting the first-hop shape and the ternary's absence.
  - **Done-check**: those tests green, `node --check` clean, then tick and run full `make test`.
  - **Out of scope**: any third enforcement layer; changing the SKILL.md token contract; the seven non-eligible haiku hops.

- [ ] [ROUTINE] **(F5) A fail-closed refusal is INVISIBLE to the id:98f0 watchdog** 🚧 GATED (DEP: id:540f — there is no refusal to observe until the refusal exists) <!-- gated-on:540f --> <!-- id:554b -->
  - **The gap**: a refusal mints **no runId and no heartbeat**, and the outage watchdog (`tools/relay-watchdog.sh`, id:98f0) only watches runs that *started* — it reads the shared run-heartbeat (id:e149). So a **timer-launched** pool can refuse for days with nothing observing it. Post-540f/c179 the pool produces **nothing** instead of running degraded: one bounded leaked lease is traded for **unbounded invisible downtime**. That trade is only acceptable if the refusal is loud on its own channel.
  - **What to build — pick ONE and say why in the close note** (both are defensible; this is authoring judgement, not a menu to implement twice):
    - **(a) notify on refusal** — the front door emits a desktop/`notify-send`-class signal when it refuses to launch; simplest, but silent if the refusal path itself never runs (e.g. the timer unit failed to start at all);
    - **(b) a watchdog check for "no run started in N hours"** — `relay-watchdog.sh` gains a liveness-of-the-*scheduler* check independent of any runId; covers strictly more failure modes (including (a)'s blind spot) at the cost of picking N and tolerating legitimate idle periods.
    (b) covers (a)'s blind spot; (a) is cheaper. **Do not build both** — the two-layer cap is about enforcement, but the same restraint applies here: a second redundant alarm channel is noise.
  - **Contract**: given a stubbed refusal (no runId minted, no heartbeat file written), the chosen mechanism produces an observable, assertable artifact within its stated window; given a healthy run that IS beating, it stays silent (no false alarm). Both directions — an alarm that cannot stay quiet is as useless as one that cannot fire.
  - **Tests**: extend the existing watchdog spec rather than writing a parallel one — `tests/` already covers `relay-watchdog.sh`; add a `# roadmap:554b` case with a `mktemp -d` heartbeat root and a fake clock/`--now` injection. **NEVER** install or start a real systemd unit from a test.
  - **Done-check**: the new case green in both directions, then tick and run full `make test`.
  - **Out of scope**: changing the heartbeat TTL; the id:33d3/id:9000 claim-liveness item (that is the detector for a lease held by a dead run, a different question); building both (a) and (b).

## Detector-fidelity cluster — promoted from TODO 2026-07-29 (handoff C2, run relay-20260729-133054-23284)

Six open TODO items promoted with their EXISTING ids (single-id-two-views D2 — no new
tokens minted). Five are the same failure family in different scripts: **a detector that
runs, exits 0, and reports nothing — because its input was resolved by the wrong path, a
bare substring, or a silently-truncating write**. The sixth (id:b460) is the review-side
twin: nothing in `review.md` asks whether an HONEST implementation did MORE than its
ratified source authorized. Evidence for each lives in the cited `TODO.md` line.

- [x] [ROUTINE] **`relay-doctor`: resolve the Makefile manifest by the script's REAL path, not by the invocation path** <!-- children-of:1102 --> <!-- id:cbd2 -->
  - **Why**: `relay-doctor.sh:63` sets `REPO_ROOT="$(cd "$SCRIPTS_DIR/../.." && pwd)"` from `${BASH_SOURCE[0]}`'s **dirname**, which is NOT symlink-resolved. Invoked through its installed symlink (`~/.claude/skills/relay/scripts/relay-doctor.sh` — how `/relay health` and every doc example call it) `REPO_ROOT` becomes `~/.claude/skills`, which has no `Makefile`, so `install_drift_check()` (`:491-496`) prints `SKIP — Makefile not found under …` **every time**. Re-verified in this handoff's worktree: source path → `clean (every manifested relay scripts/*+references/* entry is installed …)`; a staged install symlink → `SKIP — Makefile not found under …`. Same tree, same second, opposite verdicts, purely from the invocation path.
  - **The cost, measured 2026-07-29** (TODO id:cbd2 carries the full evidence): FOUR undetected install-drift instances — `fable-config.sh` (broke `/meeting --fabled` step 0f, exit 127, id:18ed/ba27), the `pre-commit-lane-vocab.sh` ratchet (closed as id:9ef7 on 2026-07-21, never symlinked — the empirical cause of id:7df1's 106→164 tag divergence over 8 days), and `diagram-edge-coverage.sh` (landed as id:a225 and uninstalled within hours). All four were found by `make status` or by hand — never by the check that exists for exactly this. It is the "loud detection whose resolution silently no-ops" anti-pattern one step worse: it does not even detect.
  - **What to build**:
    1. Resolve the repo root from the script's REAL location — `readlink -f "${BASH_SOURCE[0]}"` (the idiom `meeting/orphan-scan.sh:206`/`:226` already uses for exactly this reason), then walk up to the directory that has the `Makefile`. Do NOT re-derive it from `$PWD` or from a `~/src` glob (CLAUDE.md no-improvise rule).
    2. Apply the same fix to the SIBLING check `refs_install_check()` (`:436-444`, id:69ef), which reads `$REPO_ROOT/Makefile` and `$REPO_ROOT/relay/references` and skips on the same assumption. Both must be fixed in ONE change — a repo-root resolver used by both, not two copies.
    3. **A SKIP on either check must never be silent.** If the manifest genuinely cannot be located after real-path resolution, emit a LOUD `WARN` and count it as an unresolved check in the summary — today "skipped" reads identically to "clean".
  - **Acceptance**:
    - invoking `relay-doctor.sh` through an installed-symlink path produces the SAME install-drift verdict as invoking it from the repo (matching verdict lines for both the `id:1102` and the `id:69ef` check);
    - a deliberately-unlinked manifest entry is reported `MISSING` through BOTH paths;
    - an unlocatable manifest emits a `WARN` naming the failure, never a silent skip;
    - a freshly-installed tree still reports clean through both paths (no crying wolf) — `tests/test_relay_install_drift_check.sh` must stay green unmodified.
  - **Tests**: `tests/test_relay_doctor_invocation_path_cbd2.sh` (`# roadmap:cbd2`) — hermetic: synthetic install roots staged via `make DEST_DIR=… install-relay` into `mktemp -d`, `RELAY_INSTALL_ROOT` injection, never touches the real `~/.claude`.
  - **Done-check**: `tests/run-tests.sh tests/test_relay_doctor_invocation_path_cbd2.sh` green AND `tests/run-tests.sh tests/test_relay_install_drift_check.sh tests/test_relay_doctor.sh tests/test_relay_doctor_wiring.sh tests/test_relay_doctor_strict.sh` still green, then tick and run full `make test`.
  - **Noted, NOT in scope** (found while specing; file separately if it ever bites): `ORPHAN_SCAN="$REPO_ROOT/meeting/orphan-scan.sh"` (`:64`) has the same path dependency. It does not misfire in practice because the real install root DOES carry `meeting/orphan-scan.sh` — but a partial install root makes the cross-ledger check skip too. Fixing `REPO_ROOT` once fixes this as a side effect; do not add a separate mechanism for it.
  - **Out of scope**: changing what the drift check reports; making relay-doctor exit non-zero on findings (that is id:0907's deferred report-only-vs-fail-loud decision, still the owner's); auto-installing on drift (id:ba27).

- [x] [ROUTINE] **`orphan-scan.sh`: resolve `children:`/`gated-on:` tokens against `ROADMAP.md` too, so a dependency on a relay seam is typeable** (INBOUND `routed:4f48` from loderite) <!-- id:9be0 -->
  - **Why**: `meeting/orphan-scan.sh:217` builds the typed-edge resolution map from `TODO.md ∪ TODO.archive.md` ONLY (`:214` states the exclusion deliberately: "ROADMAP.md is deliberately excluded (that drift belongs to `--cross-ledger`)"). In a relay-managed repo the SEAMS live in `ROADMAP.md`, so a real dependency on a seam id is **untypeable**: the item can only be marked gate-prose-only and the typed edge is lost. loderite hit this twice — id:3d11 (gate on `ca44`) and id:5d00 (a hard-split umbrella whose 14 seams ALL live in `ROADMAP.md`, so a `children:` marker would report every one of them dangling and exit non-zero).
  - **What to build**: extend the local resolution map to `TODO.md ∪ TODO.archive.md ∪ ROADMAP.md`, first-wins in that order (an active `TODO.md` entry keeps beating a recycled archive/roadmap id, same rationale as id:9221). The map is built by the shared `typed_edges_build_state_map` (`relay/scripts/lib-typed-edges.sh`) which already takes a file list — pass the third file, do not write a second reader.
  - **The judgment call, and why this shape**: `--cross-ledger` exists precisely because the two ledgers can DISAGREE about a shared id's checkbox state. Adding ROADMAP to the *resolution* map does not weaken that — resolution asks "does this token exist?", cross-ledger asks "do the two views agree?". Where they disagree, first-wins means the TODO view decides closure, which is the design ledger and the conservative choice (an item closed in ROADMAP but open in TODO stays OPEN for umbrella purposes). Say this in the close note.
  - **Acceptance**:
    - a `gated-on:` token naming an id that exists ONLY in `ROADMAP.md` resolves — it is NOT reported dangling, and when that roadmap item is `[x]` the gated item reports `GATE-READY`;
    - a `children:` marker whose children ALL live only in `ROADMAP.md` and are all `[x]` reports `UMBRELLA-READY`, and the scan exits 0 (today: `UMBRELLA-UNRESOLVED`, exit 3);
    - a token naming a genuinely absent id STILL reports dangling and still exits non-zero — the guard must not be dissolved into "everything resolves";
    - `--cross-ledger` behaviour is unchanged.
  - **Tests**: `tests/test_orphan_scan_roadmap_seam_9be0.sh` (`# roadmap:9be0`) — modeled on `tests/test_orphan_scan_edges.sh` (fixture `relay.toml`, `mktemp -d` repos, `SRC_DIR`/`HOME`/`RELAY_TOML` overrides).
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_orphan_scan_edges.sh tests/test_orphan_scan_cross_ledger_strict.sh tests/test_orphan_scan_cross_ledger_indent.sh tests/test_orphan_scan_gate_prose_only.sh tests/test_orphan_scan_xgate.sh tests/test_orphan_scan_unmarked_gate.sh` still green (unmodified), then tick and run full `make test`.
  - **Out of scope**: a new out-of-namespace marker syntax (the alternative the inbound item floated — resolving against ROADMAP is strictly cheaper and needs no new grammar); cross-REPO token resolution (that is what `xgate:` id:7f30 is for); changing `--cross-ledger`.

- [x] [ROUTINE] **`md-merge.py update-ids`: refuse a malformed replacement line; add an explicit append mode** (INBOUND `routed:c27e` from loderite) <!-- id:0af4 -->
  - **Why**: `update_ids()` (`meeting/md-merge.py:140-147`) replaces the WHOLE matched line with whatever `line` the caller passed, unconditionally. A caller that meant "append this text to the item" passed a partial line and **wiped a 1400-char TODO item down to the fragment — and exited 0, reporting success**. It was recovered only because the tree happened to be committed. id:1b1a already fixed the OTHER half of this family (an unmatched id used to fail-open into a duplicate append; it now fails loud) — this is the remaining half: a MATCHED id whose payload is destructive.
  - **What to build** (both halves, one change):
    1. **Validate the replacement**, before writing anything: a replacement for a matched id MUST carry that id's own anchored `<!-- id:XXXX -->` marker, and if the line being replaced is a `- [ ]`/`- [x]` checkbox item, the replacement MUST also be one. Violation ⇒ **exit non-zero, name the offending id AND what was wrong, write NOTHING** (same fail-loud shape as id:1b1a, `:150-159`). Mirror `relay/scripts/lib-anchored-id.sh`'s `ANCHORED_ID_MARKER_RE` semantics with a comment citing it (a bash lib is not importable from Python) — do NOT invent a looser pattern.
    2. **An APPEND mode** — `{"id": "XXXX", "append": "<text>"}` — that appends to the EXISTING line (preserving every byte of it, id marker last) instead of replacing it. This is what the wiping caller actually wanted; without it, the refusal in (1) just leaves them stuck.
  - **Acceptance**:
    - a replacement line lacking the item's `<!-- id:XXXX -->` marker is REFUSED (non-zero, file byte-identical);
    - a replacement lacking the leading `- [ ]`/`- [x]` for a target line that HAS one is REFUSED (non-zero, file byte-identical) — this is the exact 1400-char-wipe payload;
    - a well-formed replacement still applies in place, position preserved (no regression to `tests/test_md_merge_update_ids_strict.sh` case 3);
    - `--allow-new` append of a genuinely new well-formed item still works (id:14d0 archive-heading anchoring unchanged);
    - the append mode appends without destroying any of the original line, and the item's id marker is still the line's anchored own-id afterwards;
    - a non-checkbox id-bearing line (e.g. a `## [LANE] Title <!-- id:XXXX -->` heading-as-item) may still be replaced by another non-checkbox line — the checkbox rule is conditional on the TARGET's shape, not absolute.
  - **Tests**: `tests/test_md_merge_append_guard_0af4.sh` (`# roadmap:0af4`) — hermetic, `mktemp -d` fixtures only, style of `tests/test_md_merge_update_ids_strict.sh`.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_md_merge_update_ids_strict.sh tests/test_md_merge_commit.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: `update-sections`; the `--commit` path (id:148b); changing the flock protocol; migrating the four hand-rolled id-matchers onto `lib-anchored-id.sh` (that is the deliberately-separate id:3add follow-up).

- [x] [ROUTINE] **`gather-human-backlog.sh`: anchor the `@manual` marker instead of substring-matching it** <!-- id:05b0 -->
  - **Why**: two sites bucket an item as `kind=manual` on a bare case-insensitive substring — `emit_boxes()` (`relay/scripts/gather-human-backlog.sh:172`) and the ROADMAP scan (`:539`), both `grep -qi '@manual'`. Observed live 2026-07-29 during `/relay human .`: `id:af48` — a DESIGN item whose title discusses the `` `@wire` ``/`` `@manual` `` grammar split — was collected as `manual`, i.e. presented as a scenario a human must RUN. Harmless that once because a human read it; but the "you run these" list is the one tier the owner acts on directly, so polluting it erodes exactly the list that must stay trustworthy. Same unanchored-substring family as id:bf19 (roadmap-lint state claims) and id:0d58/id:d259 (lane tags), and the fix shape is the same: match the tag in its grammatical position.
  - **What to build**: a single shared predicate (one function, used by BOTH sites — do not fix one and leave the other) that treats `@manual` as a marker only when it appears as a standalone token on the item line and NOT inside a backtick-quoted span. `hooks/pre-commit-lane-vocab.sh`'s `mask_backticks()` + leftmost-position idiom is the in-repo precedent for the backtick half; reuse that shape rather than inventing a third.
  - **Acceptance**:
    - an open box whose body merely MENTIONS `` `@manual` `` in prose (backticked, or as part of a longer word) does NOT bucket as `manual`;
    - a real standalone `@manual` marker on the item line STILL buckets as `manual` — from `REVIEW_ME.md` and from `ROADMAP.md`, i.e. both call sites;
    - the `REVIEW_ME.md` default bucket (`review_me`) is unchanged for un-marked boxes;
    - the sibling `@needs-auth` / `@wire` markers are untouched by this change (do not opportunistically re-anchor them here — one behaviour change per item).
  - **Tests**: `tests/test_human_backlog_manual_anchor_05b0.sh` (`# roadmap:05b0`) — hermetic: fixture `relay.toml` + `mktemp -d` repos, `RELAY_TOML`/`SRC_DIR`/`HOME` overridden, never reads the real registry.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_relay_human.sh tests/test_gather_todo_human_lanes.sh tests/test_gather_lane_anchor.sh tests/test_gather_human_decision.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: re-anchoring the lane-tag readers (id:0d58/id:d259 own that); the `--needs-auth` lister; changing which buckets `/relay human` prints.

- [x] [ROUTINE] **`worktree-retire.sh`: a 4th outcome — commit-and-park a DIRTY relay-owned worktree instead of leaving it for a human** <!-- children-of:4df8 --> **DONE 2026-07-31 (execute[sonnet]):** `--commit-residue` opt-in flag added; dirty+relay-owned+flag commits residue (WIP/UNVERIFIED, verbatim content preserved) then flows through the existing park path to `relay/orphan/<bn>`; non-relay branches and `--expect-merged` leave the flag inert; default (no flag) behaviour unchanged. `relay-loop.js`'s context-death caller now passes the flag. `tests/test_dirty_worktree_commit_park_f272.sh` green; `test_context_death_parks_worktree_4df8.sh` + `test_relay_orphan_park.sh` unmodified and green. <!-- id:f272 -->
  - **Why**: id:4df8 closed and genuinely works for what it specced, but it does NOT cover the incident that motivated it. `worktree-retire.sh`'s three outcomes are: commits → branch PARKED as `relay/orphan/<bn>`, ref kept (fixed); clean+commitless → reaped (fixed); **dirty/unremovable → SURFACED and LEFT on disk, exit 3** (`:13-14`, `:120-127`). The RED spec's fixture (c) (`tests/test_context_death_parks_worktree_4df8.sh:68-77`) only asserts a dirty tree is not silently DESTROYED — so the implementation correctly meets its spec. But the original ask in `routed:3f22` was stronger: *"if the worktree has commits **or a dirty tree**, **commit-or-park** it"*. **Live evidence the gap is real**: run `relay-20260729-111723-7520`'s execute child died with **0 commits and a dirty tree carrying 47 lines** (the id:4df8 implementation itself); it survived only because a human noticed and hand-committed it as `46b260e`. Under the shipped fix that same incident still ends at "surfaced and left" — recovery is still manual.
  - **Force-free is PRESERVED, and that is the point**: committing residue onto its own relay-owned branch DESTROYS nothing, unlike stash/clean/reset which id:373e rightly bans. The ban is on DISCARDING; this is the opposite. Say so in the close note so a later reader does not mistake it for a relaxation of id:373e.
  - **What to build** (the helper, per its single-target contract id:6e02 — NOT the relay-loop caller):
    1. `worktree-retire.sh` gains an **opt-in** `--commit-residue` flag. Default behaviour is UNCHANGED (surface-and-leave), so no existing caller or test changes meaning.
    2. Under `--commit-residue`, when the tree is dirty AND the branch is a relay-owned ref (`refs/heads/relay/…`) AND `--expect-merged` was NOT passed: stage everything and commit to that branch with a message that literally contains `WIP` and `UNVERIFIED` and names the worktree, then continue into the normal remove + park path so the branch ends as `relay/orphan/<bn>`.
    3. The surfaced line on stdout must NAME the resulting ref — a message pointing at the run-id-scoped worktree path is actively misleading once the run ends (the id:4df8 §(d) finding).
    4. A dirty worktree on a NON-relay-owned branch is still surfaced-and-left, exit 3, even with the flag — the helper never commits to a branch it does not own.
    5. `relay-loop.js`'s null-report (context-death) path passes `--commit-residue`; no other caller does.
  - **Acceptance**:
    - dirty + relay-owned + `--commit-residue` ⇒ a reachable ref `relay/orphan/<bn>` whose TIP CONTAINS the residue file with its original content, worktree removed, exit 0, and the printed line names that ref;
    - nothing is stashed, cleaned, or reset — `git stash list` on the repo is empty afterwards, and no `git checkout --`/`restore`/`reset --hard`/`clean` appears in the script;
    - dirty + relay-owned + NO flag ⇒ today's behaviour (surfaced, left on disk, exit 3) — `tests/test_context_death_parks_worktree_4df8.sh` fixture (c) must pass UNMODIFIED;
    - dirty + non-relay branch + flag ⇒ surfaced-and-left, exit 3, no commit made;
    - the committed-work and clean-commitless outcomes are unchanged.
  - **Tests**: `tests/test_dirty_worktree_commit_park_f272.sh` (`# roadmap:f272`) — hermetic real git repos under `mktemp -d`, `WORKTREE_RETIRE_LOG` redirected, no network, no `~/.claude` writes.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_context_death_parks_worktree_4df8.sh tests/test_relay_orphan_park.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: changing the no-force policy; `--expect-merged` semantics; discovery/selection of which worktrees to retire (stays in the callers, id:6e02); auto-integrating a parked orphan (id:1048/a4e9).

- [x] [ROUTINE] **`review.md`: add an OVER-REACH check — did the diff do MORE than the ratified source authorized?** (INBOUND `routed:2ae7` from it-infra) — **DONE 2026-07-29 (execute[sonnet]):** anchored `<!-- overreach-check:start/end -->` region added as new §2d in `relay/references/review.md`, sequenced after §2b/§2c; `tests/test_review_overreach_check_b460.sh` green. Executor-contract vN unchanged (this edits the reviewer's own procedure only). <!-- id:b460 -->
  - **Why**: §2b's eight judgment-residue checks all assume the SPEC is correct and the executor might CHEAT it; §4's spec-drift audit only reads repo-internal `ARCHITECTURE.md`/`README.md`. Nothing catches an **honest** implementation that is a strict SUPERSET of what was authorized, with a fully green suite. Live miss 2026-07-29 (it-infra id:3177): the handoff wrote a RED spec whose test 8 only covered a repo pushing nothing but `main`; the executor reasonably generalized to "any `refs/heads/*` != main is a publication channel"; the suite went 8/8 green and review returned `substantive:false`. But the loderite meeting D1 had ratified exactly ONE channel (an ff-only `stable` bookmark), and loderite's bare repo carries 5 live `relay/exec-*` branches that would each have gotten a worktree + a full `npm ci && build` on the Pi — the disk/CPU cost meeting D3 explicitly flagged, multiplied per branch. Caught only by a human re-read; fixed in it-infra `1cf9b8b` via a `PUBLICATION_CHANNELS` allowlist + a new test 9.
  - **The load-bearing case**: when the handoff authored the spec in the SAME relay lineage, the reviewer is the ONLY independent check, and "tests pass" re-uses the handoff's blind spot. This is the implementation-side twin of the global heuristic *"check a derived doc against its ratified source before letting a pre-registered rule fire"* — cite it.
  - **What to build** — a new numbered step in `relay/references/review.md`, sequenced AFTER the §2b residue checks (it presumes the executor was honest) and delimited by an **anchored fence**: `<!-- overreach-check:start -->` … `<!-- overreach-check:end -->`. It must instruct the reviewer to:
    1. locate the ROADMAP item's CITED ratified source — often a meeting note **in another repo**, as in the incident;
    2. read that source, not the ROADMAP restatement of it (the restatement drifts toward whatever the restating author was doing);
    3. ask explicitly whether the diff's BEHAVIOUR is a strict SUPERSET of what was authorized — a generalization, a widened match, an allowlist turned into a wildcard;
    4. FLAG + reopen when it is, even with a fully green suite, and even when the executor was honest — this check has no cheating hypothesis;
    5. record the case where the item cites NO ratified source at all: that is itself a finding (surface to REVIEW_ME), not a pass.
  - **Why an ANCHORED fence and not prose**: a prose-grep guard is the vacuous-guard failure id:cdcf documents — reword the sentence and the scoped region silently empties, so the check passes having checked nothing. The anchor makes the region structural; the spec below asserts on the region, not on the whole file.
  - **Acceptance**:
    - `relay/references/review.md` contains exactly ONE `<!-- overreach-check:start -->` … `<!-- overreach-check:end -->` region, non-empty;
    - the region names the ratified-source re-read, the cross-repo case, the SUPERSET question, and the flag-and-reopen consequence;
    - the region states the honest-implementation premise explicitly (it is NOT a gaming check) so it is not collapsed into §2b on the next edit;
    - the region names the no-cited-source case as a finding;
    - the step is referenced from the review procedure's own ordering (it is not an orphan section nothing points at);
    - the executor contract's version marker is bumped ONLY if the executor-facing contract text changed — this item edits the REVIEWER's procedure, so by default it does not.
  - **Tests**: `tests/test_review_overreach_check_b460.sh` (`# roadmap:b460`) — a REFERENCE-DOC spec: it asserts the anchored region exists and carries each required element. It deliberately does NOT fake a code test; there is no code here to exercise, and a test that pretends otherwise would be the thing this repo bans. Its honest limitation is stated in its own header: it guards the region's EXISTENCE and CONTENT, not the reviewer's compliance — the real enforcement is the Opus reviewer following the contract (same posture as `tests/test_review_tier_enumeration.sh`).
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_review_tier_enumeration.sh tests/test_owner_accept_bump_gate.sh tests/test_gaming_scan.sh` still green, then tick and run full `make test`.
  - **Out of scope**: mechanizing the superset judgement (it is not mechanizable — a diff's behaviour vs a prose ratification); id:c17c (the review-agent anti-spam brief) — distinct item; changing `gaming-scan.sh`; editing meeting notes in other repos.

## `@container` dispatch-collector gap — promoted from TODO 2026-07-29 (handoff C2/C3, routed:02d9 from loderite)

One item, existing id reused (single-id-two-views D2 — no new token). The doctrine in
`relay/references/handoff.md:233` and `relay/references/review.md:304` tells an author to
mark a DECOMPOSED parent `@container` because *"collectors exclude that marker"*. That is
true of the two collectors that dispatch nothing and false of every collector that does.

- [x] [ROUTINE] **`@container` must exclude a line from the DISPATCH collectors, not just the lint/human ones** <!-- routed:02d9 --> <!-- id:0cf5 -->
  - **Why**: `roadmap-lint.sh:396` (the check that *instructs* you to add the marker) and `gather-human-backlog.sh:298` (`if (line ~ /@container/) next`) honour `@container`. Three dispatch-side collectors do not:
    - `classify-repo.sh:190` — `is_human = primary in HUMAN_GATES or "@manual" in ln or is_owner_verify`. No `@container`, so an open `- [ ] [ROUTINE] … DECOMPOSED … @container` parent enters `actionable_routine_ids` and fires `verdict=execute` on a container whose seams are the real work. The `@wire`-on-pool-lane branch (`:215-223`) shares the same `is_human` predicate and the same gap.
    - `gather-repo-state.sh:267` — the `grep -vP '\[HARD — (hands|meeting|decision gate)\]|@manual|\[MECHANICAL\]|🚧|BLOCKED on|blocked on'` exclusion list omits it, so an `@container` `[INTENSIVE — …]` parent can surface as `top_intensive`.
    - `discover-repo.sh:154` — the SAME-ITEM orphan carve-out's `routine_open` filter tests only `"@manual" not in line`. A stray `@container` id inflates that set, so `routine_open - suppressed_ids` is non-empty and the carve-out declines to drop a duplicate execute unit. Fail-OPEN (over-dispatch, not wrong-suppress), hence lowest severity of the three — but it is the same predicate and must not drift.
  - **Observed**: loderite 2026-07-29, ids `c19e` + `2b24` still dispatchable after being correctly marked `@container`. The workaround there was to put "parked" in the *section* heading to trip `classify-repo.sh`'s `_EXEMPT_HEADING_RE` whole-section exemption — which also hides every other item in that section.
  - **What to build**: add `@container` to the per-line conservative exclusion in all three scripts. Direction is under-dispatch-safe (identical to `@manual`): the marker can only ever REMOVE work from a dispatch set, never add it, so a false positive costs one un-dispatched item and never a wrong dispatch. Per `lib-state-claim.sh`'s header rule that twin consumers must return the same answer, land all three in ONE commit — a one-sided fix silently diverges them.
  - **Do NOT**: introduce a new shared helper or refactor `is_human` (out of scope — a 4th call-site refactor is id:3743's family, not this); change `roadmap-lint.sh` or `gather-human-backlog.sh` (they are already correct and are the fixture's positive control); touch the whole-section `_EXEMPT_HEADING_RE` path.
  - **Tests**: `tests/test_container_dispatch_exclusion.sh` (`# roadmap:0cf5`). Behavioural where the surface is observable, and HONEST about where it is not:
    - `classify-repo.sh --emit unit` → `actionable_routine_open` is 0 for an `@container` `[ROUTINE]` line and 1 for the same line without the marker (positive control), and 0 for an `@container` `@wire` `[HARD — pool]` line.
    - `gather-repo-state.sh` → `top_intensive` is empty for an `@container` `[INTENSIVE — …]` line and non-empty without the marker.
    - `discover-repo.sh`'s `routine_open` needs an orphan-suppress reconcile fixture to reach behaviourally; the test instead asserts SOURCE PARITY — that all three per-line exclusion filters name `@container` — and says so in its header. It is a drift guard, not a behavioural proof, and is labelled as one rather than dressed up as a third behavioural case.
  - **Done-check**: `tests/run-tests.sh tests/test_container_dispatch_exclusion.sh` green, plus the existing `tests/test_classify_repo_gated_section.sh tests/test_classify_repo_unit.sh tests/test_gather_repo_state.sh tests/test_classify_verdict_intensive.sh` still green (they pin the surrounding exclusion behaviour), then tick this box and run full `make test`.
  - **Doc twin**: none needed — once fixed, `handoff.md:233` / `review.md:304`'s "collectors exclude that marker" becomes true as written. That is the point of the fix.

## Anchoring + mechanical-tier cluster — promoted from TODO 2026-07-30 (handoff C2, run handoff-manual-20260730-174310)

Twelve open TODO items promoted with their EXISTING ids (single-id-two-views D2 — **no new
tokens minted**). Twelve of the twenty-four `promote` rows were deliberately LEFT; the
reasons are recorded in `RELAY_LOG.md` for this run, not here. Two themes dominate: **a
detector or dispatcher reading a tag by unanchored substring** (id:6b1c, id:5648, id:bf19),
and **a mechanical hop that is authored but unreachable at runtime** (id:5bbb, id:1f8e,
id:4313).

**Standing constraint on this whole section (owner directive 2026-07-30):
`relay/scripts/relay-loop.js` MUST NOT be modified.** Every item below was selected
because it can be completed without touching that file; four sibling items that cannot
were left unpromoted for exactly this reason. If an executor finds itself editing
`relay-loop.js` to close one of these, that is a HANDBACK, not a licence.

- [x] [ROUTINE] **`commit-ledger.sh` takes a PATH but `human.md` documents it as `<repo>`, so the documented invocation hard-fails** <!-- id:7142 -->
  - **Why**: `relay/references/human.md` §5 shows `commit-ledger.sh <repo> \…`; a caller following it literally gets `ERROR: not a git repo:`. Hit live 2026-07-28 during `/relay human .` — and it fails at exactly the step whose whole purpose (id:2147) is to avoid leaving a dirty uncommitted ledger behind, so the doc/script drift produces the very failure the step exists to prevent. Same built-but-not-reachable-as-documented class as id:ba27 / id:5bbb.
  - **Which side to fix — decided here, option (a)**: make `commit-ledger.sh` accept a bare repo NAME *in addition to* a path. Rationale, stated in the TODO item and adopted: every other relay front-door surface takes a repo name, so the doc is describing the interface the rest of the system already has and the script is the outlier. Resolve a bare name through the canonical own-repo set (`relay/scripts/lib-own-repos.sh`, honouring `# path:` overrides) — **do NOT re-derive it from a `~/src/*` glob** (CLAUDE.md no-improvise rule). A value that is an existing directory is still treated as a path, unchanged.
  - **Do NOT** also rewrite `human.md` §5 to `<repo-path>` — that is the rejected alternative (b), and doing both leaves the interface inconsistent with every other front door.
  - **Acceptance**:
    - `commit-ledger.sh <name>` where `<name>` is an `own` repo in the registry resolves and commits in that repo;
    - `commit-ledger.sh <path>` (relative and absolute, including `.`) behaves exactly as today — no regression;
    - a name that resolves to nothing fails LOUDLY naming the name AND the registry it was looked up in, never a bare `not a git repo`;
    - a repo carrying a `# path:` override resolves via the override, not via `~/src/<name>`;
    - the exact invocation form printed in `human.md` §5 is exercised by the test, so the doc and the script cannot drift apart again.
  - **Tests**: `tests/test_commit_ledger_repo_name_7142.sh` (`# roadmap:7142`) — hermetic: fixture `relay.toml` + `mktemp -d` git repos, `RELAY_TOML`/`SRC_DIR`/`HOME` overridden; never touches the real registry or `~/.claude`.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_relay_commit_ledger.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: any other `human.md` step; changing what `commit-ledger.sh` commits or its flock protocol.

- [x] [ROUTINE] **`unpromoted-scan.sh`'s `primary_lane` path 3 reads a lane tag from PROSE, labelling an UNLANED item `promote` — violating the script's own acceptance #3** <!-- id:6b1c -->
  - **Why**: `primary_lane` has three paths — (1) tag-before-bold-title, anchored, correct; (2) bold-titled, strictly anchored since id:fb7f; (3) **everything else → a leftmost-tag-ANYWHERE scan over the whole line**. Path 3's stated justification ("non-bold prose-summary items carry no genuine tag either way") is false for the `- [ ] [INBOUND routed:XXXX from Y] …` class, which is non-bold, prose-heavy, and quotes lane tags *because such items are bug reports about lanes*. Demonstrated on id:3e14: `[ROUTINE]` picked from byte offset 296 of `"while even ONE executor-actionable [ROUTINE] item stays open"` → disposition `promote`, i.e. a design-decision item offered to the executor queue. Head-anchored `classify.sh` read the same line correctly — the two readers disagreeing is the tell.
  - **Blast radius, MEASURED 2026-07-30 and RE-MEASURED in this handoff** (do not re-derive it): 3 of 56 rows. `promote`: 24 rows, all genuine. `laned`: 2 misreads — id:ee61 (since closed) and **id:be40**, whose `[INPUT — access]` came from offset ~132 inside a parenthetical. id:be40 was lane-triaged by hand in this same handoff, so the live misread set is now empty — which is *why this fix must land before it refills*: 10 INBOUND items were routed into this repo on 2026-07-30 alone, so the defect gets worse with use.
  - **Note the two directions differ in severity**: a false `promote` puts a design item into the executor queue (loud, caught at spec time); a false `laned` makes an UNLANED item read as *resolved* so it never reaches triage at all (silent). The second is the one that bit.
  - **What to build**: extend the id:fb7f strictness to path 3 — for a non-bold item accept a lane tag ONLY in the leading position (immediately after `- [ ] `, allowing one preceding `[INBOUND …]` / `[<target-repo>]` prefix bracket), never at arbitrary depth; return empty otherwise, which yields `surface` — the conservative disposition the contract already prefers.
  - **Reuse, do not reimplement**: this is the **THIRD** reader in this family after `meeting/classify.sh` (fixed 2026-07-30, routed:f1e1 / id:4e3b) and `gather-human-backlog.sh` (id:5648, promoted in this same section). The id:415b determinism gate (pure-function + ≥2 consumers) is long since satisfied, so **extract the anchored primary-lane parse into ONE shared helper** and have this script call it — a fourth independent reimplementation is the anti-pattern. If id:5648 lands first, call the helper it created rather than adding a second.
  - **Acceptance**:
    - a non-bold item whose ONLY lane-tag mention is in prose (any offset > the head region) yields NO lane and disposition `surface` — fixture on the `[INBOUND routed:… ] …` shape, mirroring the real id:3e14 and id:be40 lines;
    - a non-bold item with a genuine leading lane tag STILL resolves to that lane (positive control);
    - a non-bold item with a leading `[INBOUND …]` prefix followed by a genuine lane tag resolves to that lane;
    - paths 1 and 2 are behaviourally unchanged;
    - a lane-less item is `surface`, never `promote` — assert the acceptance-#3 invariant directly, not just the lane value.
  - **Tests**: `tests/test_unpromoted_scan_prose_lane_6b1c.sh` (`# roadmap:6b1c`) — **AUTHORED AND VERIFIED RED by this handoff (C3)**; hermetic, `mktemp -d` fixture repos. It reproduces BOTH directions on the real script: `aa01` (prose `[ROUTINE]` at depth) reports `promote` and `aa02` (prose `[INPUT — access]` in a parenthetical, the id:be40 shape) reports `laned`. Its three positive controls (`aa04`/`aa05`/`aa06`) and the three path-1/path-2 regression cases (`bb01`/`bb02`/`bb03`) ALREADY PASS — so the fix is a narrowing of path 3, not a rewrite, and any change that turns non-bold items wholesale into `surface` will fail this test. **Do NOT assume `tests/test_unpromoted_scan_anchoring.sh` (roadmap:1312) covers this**: it guards a DIFFERENT anchoring defect (the twin-check `grep -qF "id:$token"`). Extend it or add a sibling, deliberately.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_unpromoted_scan_anchoring.sh tests/test_unpromoted_scan.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: changing the disposition vocabulary; the `--source-id` exclusion (id:47f1); re-laning any live item (id:be40 is already done).

- [x] [ROUTINE] **`gather-human-backlog.sh` lane detection has NO head-anchoring, so a prose lane tag HIJACKS the lane — and in TODO mode that SILENTLY DROPS the item** <!-- id:5648 -->
  - **Why**: `emit_hard_lanes`'s lane chain tests the whole backtick-stripped line with no positional constraint, and checks the POOL branch FIRST. So an item whose head tag is `[HARD — meeting]` but whose body merely *discusses* `[HARD — pool]` buckets as `hard_pool`; TODO mode then drops pool rows (`if (bucket == "pool" || bucket == "untagged") next`, because the pool runs those unattended) and the item becomes **invisible to `/relay human` entirely** — no reject line, nothing on stderr. Demonstrated: `id:d84f` (the `/filetodo` item) is `[HARD — meeting]` whose body asks *"which relay lane the research seam gets (`[HARD — pool]`? a new `[RESEARCH]`…)"* — unquoted, so it is dropped. It was the ONE item an independent own-id extraction found that the collector never emitted in any bucket.
  - **What to build**: port `classify.sh`'s id:0d58/id:4da4 head-anchoring into `emit_hard_lanes` — extract the lane tag from the item HEAD, then route on the *extracted tag*, rather than substring-matching the whole line. Keep the dual-vocab precedence. **The `route:` aliases must keep scanning the full line** — `🚧 … route:meeting|human|decision-gate` legitimately appears anywhere in the body (hard-lanes.md canonical marker set), so anchoring them would be a new drop bug in the opposite direction.
  - **Why this is riskier than it looks, and what the item therefore REQUIRES**: anchoring changes the bucket of every item whose head tag and prose disagree. The change MUST land with a **before/after row-count diff per bucket across all own repos**, recorded in the close note — a silent bucket reshuffle across the fleet is exactly the failure this item is about. Backtick-stripping (id:306d/id:1bbd) stays; it is orthogonal and only ever helped when the prose mention happened to be backticked.
  - **Acceptance**:
    - (a) an item whose head tag is `[HARD — meeting]` and whose body contains an UNQUOTED `[HARD — pool]` buckets as `meeting`, and is EMITTED in TODO mode (today: dropped);
    - (b) a real head lane tag still wins in every existing bucket (positive controls for pool/meeting/hands/`[INPUT — *]`/`[MECHANICAL]`);
    - (c) a `route:` alias deep in the body is STILL recognized;
    - (d) an item with no recognized lane is still the LOUD `untagged` reject with a non-zero exit — the guard must not be dissolved;
    - (e) the per-bucket row-count diff across own repos is produced and recorded (it is part of the deliverable, not a nicety).
  - **Tests**: extend `tests/test_gather_lane_anchor.sh` — **extend, do not replace** (it pins behaviour this change must preserve). Add `# roadmap:5648` fixtures for (a)–(d). Hermetic: fixture `relay.toml` + `mktemp -d` repos, `RELAY_TOML`/`SRC_DIR`/`HOME` overridden.
  - **Done-check**: `tests/run-tests.sh tests/test_gather_lane_anchor.sh tests/test_relay_human.sh tests/test_gather_todo_human_lanes.sh tests/test_gather_human_decision.sh tests/test_hard_lane_buckets.sh` all green, then tick and run full `make test`.
  - **Relation to siblings — coordinate, do not duplicate**: this is the third reader in the id:4da4-anchoring family. id:6b1c (same section) is the fourth and explicitly asks for a SHARED helper. Whichever lands second should CALL the helper the first created. `id:05b0` (already in ROADMAP) anchors `@manual` in this same script — one behaviour change per item; do not opportunistically fold them.
  - **Out of scope**: the `@manual` anchoring (id:05b0); the lane-tag readers id:0d58/id:d259 own; changing which buckets `/relay human` prints.

- [ ] [ROUTINE] **`DECIDED-LEFT-OPEN` (roadmap-lint rule 3(b)) has two false-positive classes that make it permanently noisy on exactly the items it should ignore** <!-- children-of:968c --> <!-- id:bf19 -->
  - **Why**: **(a) no `@container` exemption** — rule 3(a) `DECOMPOSED-CONTAINER` explicitly exempts `@container` (`roadmap-lint.sh:352`, `"$line" != *@container*`) but 3(b) does not (`:368`, `state_claim_direction_i "$line"` with no marker check). A `@container` parent is BY CONSTRUCTION a decomposed item that records a decision and legitimately stays open until its seams close, so every correctly-marked container trips 3(b) forever and the WARN is unfixable without deleting the decision record the container exists to carry. **(b) the scoped-assertion strip is too narrow** — `lib-state-claim.sh:73` strips only the exact form `id:XXXX[[:space:]]+is[[:space:]]+(TERMINAL|DECIDED <date>)`, requiring a literal `" is "`. Real prose about OTHER ids almost never uses it: ai-codebench 8bea's body says `id:244b CLOSED matrix-complete 2026-06-30`, so the rule fires on an item asserting nothing about ITSELF.
  - **Observed cost**: a permanent WARN auto-filing a REVIEW_ME box for a non-issue — the human triages noise, which is the exact failure mode id:dafa exists to prevent.
  - **What to build** (both halves, ONE change): (a) add the `@container` carve-out to 3(b), mirroring 3(a)'s existing form; (b) widen the strip to `id:XXXX\s+(is\s+)?(TERMINAL|DECIDED …)` and/or require the terminal word to be near a SELF-reference before firing.
  - **Twin-consumer constraint — load-bearing**: `lib-state-claim.sh`'s own header states both consumers MUST return the same answer, so the `roadmap-lint.sh` change and the `todo-conformance.sh` twin-check MUST land together. A one-sided fix silently diverges them, which is the class this repo keeps re-paying for.
  - **Acceptance**:
    - an open `@container` line carrying a decision record produces NO `DECIDED-LEFT-OPEN` WARN;
    - a line whose only terminal words are scoped to OTHER ids (`id:XXXX CLOSED …`, `… DONE + … DONE`) produces no WARN;
    - a genuine self-directed left-open decision claim STILL WARNs — the rule must not be dissolved into silence (assert this explicitly; it is the whole point of the rule);
    - `roadmap-lint.sh` and `todo-conformance.sh` return the SAME verdict on all three fixtures.
  - **Tests**: `tests/test_state_claim_container_fp_bf19.sh` (`# roadmap:bf19`) with the three fixtures above run through BOTH consumers. Hermetic, `mktemp -d`.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_roadmap_lint.sh tests/test_roadmap_lint_doctrine.sh tests/test_todo_conformance.sh tests/test_state_claim_baseline_cb3e.sh tests/test_state_claim_word_boundary_78e1.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: rule 3(a); the anchoring work in id:5648/id:6b1c (different readers); changing what a REVIEW_ME auto-file looks like.

- [ ] [ROUTINE] **Completeness test: assert every `model:'bash'`-dispatched relay script is in `mechanical-proxy.py`'s `ALLOWED_RELAY_SCRIPTS`** <!-- id:5bbb -->
  - **Why — this gap has now shipped THREE times, and the third cost real work.** A script dispatched inside a ` ```relay-mech ` fence but absent from the allowlist is refused by the proxy, which **fails OPEN to the real Anthropic API**, where no model named `bash` exists → the hop dies with *"There's an issue with the selected model (bash)"*. Ships: (1) id:86a2's `discover-prelude.sh`, caught only by the id:24ec executor; (2) the same class again; (3) **2026-07-29, `worktree-retire.sh`** — observed live in run `relay-20260729-142725-13077` as `[retire-death:dotclaude-skills] failed`, so id:4df8's context-death parking silently did not happen, no `relay/orphan/*` ref was created, and an execute child's uncommitted work was left one `git worktree prune` from deletion (hand-salvaged as `06cffba`).
  - **The failure SHAPE is the argument for this item**: a non-allowlisted command fails neither at authoring time nor in the suite — it fails at RUNTIME, in the exact rare path (a dying child) where nobody is watching and the cost is highest. The fail-open design is correct for security; the missing completeness check is what turns it into a silent trap. Ship 3 also passed a supervised apex review that verified wiring, test-integrity, done-check and design and did NOT check allowlist membership — direct evidence that LLM review does not substitute for this deterministic guard.
  - **Verified in this handoff (2026-07-30) — the gap is STILL OPEN and the extractor is harder than it looks.** `grep -c worktree-retire relay/scripts/mechanical-proxy.py` → **0**. And the fences are NOT statically greppable as blocks: `relay-loop.js` has **17** `relay-mech` occurrences, built by string concatenation (`'```relay-mech\n' + …`) and in one case inside a template literal with escaped backticks (`:1942`), so a naive ` ```relay-mech(.*?)``` ` block regex recovers only **4**. Worse, `:2360` and the `releaseLease` dispatcher (`:2048`) build the fence from a **variable** (`'```relay-mech\n' + cmd + '\n```'`), so the script name is not literal at the fence site at all — it arrives from the call sites one level up.
  - **What to build**: a hermetic test that, for every ` ```relay-mech ` fence in `relay-loop.js`, determines the `relay/scripts/<X>.sh` it carries and asserts `<X>.sh ∈ ALLOWED_RELAY_SCRIPTS`. Given the above, **an unresolvable fence MUST fail LOUDLY, never be skipped** — a skip reproduces the exact silent-hole this item exists to close. Resolving one level of indirection (a fence whose command is a parameter, resolved from that function's call sites) is acceptable; anything beyond that should fail loud and name the line number so a human decides.
  - **Do NOT modify `relay-loop.js`** (owner directive 2026-07-30) — this is a read-only test over it, plus (if a real gap is found) an `ALLOWED_RELAY_SCRIPTS` entry in `mechanical-proxy.py`.
  - **Acceptance**:
    - the test enumerates every fence and reports a count; the count MATCHES the number of `relay-mech` occurrences that are real fences (not comments/log strings) — assert the count, so a future fence that the extractor silently misses fails the test;
    - a fence carrying a script absent from `ALLOWED_RELAY_SCRIPTS` FAILS, naming the script and the line;
    - a fence whose command cannot be resolved statically FAILS loudly rather than being skipped;
    - the current tree's real gap (`worktree-retire.sh`) is reported by the test BEFORE the allowlist entry is added — verify the test is genuinely red first, then add the entry and watch it go green (this is also id:1f8e's fix; see the note there);
    - a comment or log string mentioning `relay-mech` is NOT counted as a fence (negative control).
  - **Tests**: `tests/test_mech_fence_allowlist_completeness_5bbb.sh` (`# roadmap:5bbb`). It reads the real `relay-loop.js` + `mechanical-proxy.py` (that is the point — it is a completeness guard over the live files), writes nothing, and must not need network or `~/.claude`.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_relay_loop_mech_emitter.sh tests/test_mechanical_proxy.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: the per-hop `MECH_MODEL` invariant (that is id:4313, a sibling in this section — land them independently, they guard different properties); changing the proxy's fail-open behaviour.

- [ ] [ROUTINE] **HIGH PRIORITY — add `worktree-retire.sh` to `ALLOWED_RELAY_SCRIPTS` and assert it; id:4df8 is ticked but INERT at runtime** <!-- children-of:4df8 --> <!-- gated-on:5bbb --> <!-- id:1f8e -->
  - **Why**: `retireDeadWorktree()` (`relay-loop.js:2042-2049`, merged `relay-ckpt-20260729-1255`) dispatches `~/.claude/skills/relay/scripts/worktree-retire.sh` in a ` ```relay-mech ` fence as `model: MECH_MODEL`, but that script is absent from `mechanical-proxy.py`'s `ALLOWED_RELAY_SCRIPTS` — **re-verified in this handoff, `grep -c worktree-retire relay/scripts/mechanical-proxy.py` → 0**. The proxy refuses it and fails OPEN to the real API → the hop dies. Observed live the day it merged (run `relay-20260729-142725-13077`): `[retire-death:dotclaude-skills] failed`, no `relay/orphan/*` ref, worktree left registered, an execute child's uncommitted `ROADMAP.md` + `roadmap-lint.sh` work one `git worktree prune` from deletion (hand-salvaged `06cffba`).
  - **Why this is filed rather than un-ticking id:4df8**: its code is correct and its RED spec genuinely passes — the spec is hermetic, so it exercises the code path but cannot exercise the real proxy dispatch. That is an honest limitation, not a gamed test. "Green test + ticked box + feature that cannot run" is reachable here, and that combination is the thing worth remembering.
  - **Gate**: `gated-on:5bbb` — id:5bbb is the guard that makes this class detectable. The one-line allowlist entry may land first only if 5bbb's test is written to be RED on the current tree (see 5bbb's acceptance); otherwise fixing this first removes 5bbb's own red fixture. Coordinate: **write 5bbb's test first, see it red, then land this entry.**
  - **What to build**: the `ALLOWED_RELAY_SCRIPTS` entry for `worktree-retire.sh`, with an inline comment naming id:4df8/id:1f8e and the failure it prevents (matching the existing `discover-prelude.sh` / `discover-chunk.sh` comment convention).
  - **Verify by DISPATCH, not only by test** — this is the item's whole point. The hermetic suite cannot prove the proxy path works. Force a context-death (or replay the handback path) and assert a `relay/orphan/*` ref actually appears; record the run id in the close note. **A close note that cites only `make test` green does not satisfy this item.**
  - **Acceptance**: `worktree-retire.sh` ∈ `ALLOWED_RELAY_SCRIPTS`; id:5bbb's completeness test passes with it present and fails with it removed; a real dispatch produces a `relay/orphan/*` ref, evidenced by run id.
  - **Done-check**: `tests/run-tests.sh tests/test_mechanical_proxy.sh tests/test_context_death_parks_worktree_4df8.sh` green plus id:5bbb's test, then tick and run full `make test`.
  - **Out of scope**: the dirty-worktree residue path (that is id:f272, already in ROADMAP — this only restores the COMMITTED-work path); modifying `relay-loop.js`.

- [ ] [ROUTINE] [INBOUND routed:2b51 from loderite] **Lint that EVERY `agent()` carrying a ` ```relay-mech ` fence uses `MECH_MODEL`, never a literal model** <!-- routed:2b51 --> <!-- id:4313 -->
  - **Why**: the SYMPTOM is already fixed by loderite in `490ac6e` — `discover-prelude`, the `discover-run` shard and `releaseLease` all missed the id:4239 `MECH_MODEL` indirection. Because `discover-prelude` is **round-1's FIRST hop**, probe mode-a killed the whole pool with *"There's an issue with the selected model (bash)"* and **zero units dispatched** (run `relay-20260730-115757-3504`). Recurrence is not guarded. `MECH_MODEL` resolves to `'bash'` under a healthy proxy and `'haiku'` under probe mode-a, so a hop hardcoding either literal is the bug.
  - **The invariant is currently CLEAN, so the lint can assert it unconditionally with no carve-out** — verified 2026-07-30 by `/relay human` and re-checked in this handoff: `relay-loop.js` has 10 live `model: MECH_MODEL` assignments and zero live hardcoded `model:'bash'`; the 3 `model:'haiku'` and 1 `model:'sonnet'` hops carry NO fence (they are real inference calls: `handback-followup`, `integrate`).
  - **Reuse, do NOT reinvent (no-NIH)**: this is the same failure family as **id:71f2** — `relay/scripts/lint-workflow-templates.mjs` + `tests/test_workflow_template_lint.sh`, built because an unescaped backtick passed `node --check` AND `make test` yet made the live Workflow parser reject the whole script. Identical shape: green suite, dead pool. Either add the check to that lexer-aware linter or ship a sibling `lint-mech-model.mjs`. **If you ship a sibling, it needs the same Makefile allowlist entries** — `lint-workflow-templates.mjs` appears 3× (≈ lines 55 / 89 / 116) and a sibling missing them reproduces the built-but-not-wired class this section is full of.
  - **⚠ DO NOT MODIFY `relay-loop.js`** (owner directive 2026-07-30) — this is a read-only lint plus its test.
  - **Land with id:c480**: the stale id:6b35 scope table still lists `release:` as "must stay `model:'haiku'`" though id:f7d3 converted it. If that is not corrected in the same change, an implementer may faithfully "restore" the violation the lint then rejects.
  - **Acceptance**:
    - a fence-carrying `agent()` with a literal `model:'bash'` is REJECTED, naming the line;
    - a fence-carrying `agent()` with a literal `model:'haiku'` is REJECTED (both literals, not just `'bash'` — mode-a is exactly why);
    - a fence-carrying `agent()` with `model: MECH_MODEL` PASSES;
    - a NON-fence `agent()` with a literal model (`handback-followup`, `integrate`) PASSES — it is a real inference call and must not be swept up;
    - the current tree passes the lint unmodified;
    - the lint is wired into `make test` and, if a new file, into the Makefile allowlist blocks.
  - **Tests**: `tests/test_mech_model_lint_4313.sh` (`# roadmap:4313`) — fixtures for each acceptance case in `mktemp -d`, plus one assertion over the real `relay-loop.js` (must pass). Model it on `tests/test_workflow_template_lint.sh`.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_workflow_template_lint.sh tests/test_relay_loop_mech_emitter.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: allowlist membership (id:5bbb — different property, same family); id:aec5's executable belt; any `relay-loop.js` edit.

- [ ] [ROUTINE] **Lint the quoting hazard in embedded foreign-language literals — an apostrophe inside `python3 -c '…'` silently corrupts the program and `bash -n` passes** <!-- id:ef9e -->
  - **Why**: `discover-repo.sh` embeds a ~90-line Python program in a single-quoted `python3 -c '...'`. Adding a comment containing `lib-state-claim.sh's` closed the shell quote at that apostrophe. The file stayed **valid bash** (`bash -n` clean), so nothing local complained; the corruption surfaced only at runtime as `IndentationError: expected an indented block after 'if' statement`, in a traceback pointing at a line the author never wrote (`# lib-state-claim.shs`). The full suite caught it (5 red) — but only because a test happens to EXECUTE that path, and only after a full `make test`.
  - **Third instance of one class, which is what lifts it over the id:415b determinism gate rather than being a one-off**: (1) `broker-curl.sh` JSON apostrophes breaking single-quoted literals — already a CLAUDE.md Gotcha; (2) id:5bac/aec5 — `relay-loop.js` prompt-template runtime crashes that `node --check` + grep miss; (3) this. All three are *a foreign language embedded in a host literal, where the host's syntax checker cannot see the guest*.
  - **What to build**: a cheap mechanical check over `relay/scripts/*.sh` that extracts each `python3 -c '…'` / `awk '…'` body and runs the GUEST's own syntax checker (`python3 -c "compile(open(f).read(), f, 'exec')"`, an `awk` parse-only invocation) — so the corruption is caught at lint time, not by whichever test happens to execute that path. **Extend the shape of `tests/test_workflow_template_lint.sh` / `lint-workflow-templates.mjs`, do not start fresh** (no-NIH; it is the same idea for `relay-loop.js` templates).
  - **Honest limit to state in the lint's own header**: extraction is heuristic — a body built by concatenation or interpolation cannot be checked. Such a case must be reported as UNCHECKED and counted, never silently passed (the no-silent-swallow rule); a lint that quietly skips what it cannot parse is the vacuous-guard failure.
  - **Acceptance**:
    - a fixture script with an apostrophe-corrupted embedded Python body is REJECTED, naming the file and the guest language;
    - a fixture with a syntactically valid embedded Python body PASSES;
    - a fixture with a corrupted embedded `awk` body is REJECTED;
    - an embedded body the extractor cannot isolate is reported UNCHECKED with a count, and does not read as clean;
    - the current tree passes.
  - **Tests**: `tests/test_embedded_literal_lint_ef9e.sh` (`# roadmap:ef9e`) — fixtures in `mktemp -d` plus one assertion that the real `relay/scripts/*.sh` tree passes.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_workflow_template_lint.sh tests/test_discover_repo.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: fixing any currently-corrupted script (there are none — the id:0cf5 instance was already repaired); linting embedded languages outside `relay/scripts/`.

- [ ] [ROUTINE] **Lint: flag `(DEP: <id>)` prose gate-annotations that lack a typed `<!-- gated-on:id -->` marker** <!-- id:3f7e -->
  - **Why**: observed 2026-07-24 (run `relay-20260724-160054-19815`) — zelegator's two open `[ROUTINE]` items (id:df0f, id:c106) gate on `(DEP: 0cd5)` **prose**, which `classify-repo.sh` correctly does NOT read as a gate (the settled id:65f5/4da4/0d58 rule: never gate on a prose substring; only typed `<!-- gated-on:XXXX -->` edges are honoured). Both were mis-dispatched as `execute` and handed back with zero actionable work.
  - **The fix is NOT to teach the classifier to read `(DEP:)` prose** — that re-opens the prose-substring trap the rule exists to close. ENFORCE the typed-marker convention instead: WARN when an item carries `(DEP: <id>)` / `(dep …)` prose without a matching `gated-on:` marker, so the author retags it (as zelegator's df0f/c106 were).
  - **Twin-consumer constraint**: land it in `roadmap-lint.sh` AND `todo-conformance.sh` together — the `lib-state-claim.sh` header rule that both consumers must return the same answer applies, and a one-sided fix silently diverges them.
  - **WARN, not ERROR** — the existing backlog carries `(DEP: …)` prose (this ROADMAP has several), so an ERROR would LOUD-reject the backlog on day one. The escalation to ERROR, if ever, is a separate owner call.
  - **Acceptance**:
    - an open item with `(DEP: 0cd5)` prose and NO `gated-on:` marker WARNs, naming the id it should be typed against;
    - the same item WITH `<!-- gated-on:0cd5 -->` does not WARN;
    - a mention of `DEP` inside a backticked span or in a closed `[x]` item does not WARN (reuse the existing backtick-masking idiom — `hooks/pre-commit-lane-vocab.sh`'s `mask_backticks()` is the in-repo precedent);
    - `roadmap-lint.sh` and `todo-conformance.sh` agree on all fixtures;
    - the current tree's WARN count is REPORTED in the close note (it will be non-zero — that is expected and is the backlog this surfaces, not a failure).
  - **Tests**: `tests/test_dep_prose_untyped_gate_3f7e.sh` (`# roadmap:3f7e`), fixtures run through both consumers. Hermetic, `mktemp -d`.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_roadmap_lint.sh tests/test_roadmap_lint_doctrine.sh tests/test_todo_conformance.sh tests/test_orphan_scan_edges.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: teaching `classify-repo.sh` to read prose gates (explicitly rejected); auto-converting prose to typed markers (that is an author judgement — the id in the prose may not be the real gate); the zelegator repo itself.

- [ ] [ROUTINE] **Make `make install`'s `RELAY_QUOTA_DECAY_7D` default agree with `relay/SKILL.md` — adopt the RISING schedule `0.30:0.90`** <!-- id:74e7 -->
  - **Owner decision already taken (2026-07-24, `/relay human`): option (a)** — the Makefile default is the STALE source, the SKILL.md doctrine wins. This item implements that decision; it does not re-open it.
  - **Why**: `Makefile:208` pins `RELAY_ENV_DEFAULTS := RELAY_QUOTA_DECAY_7D=0.30:0.08` under a comment dated *user policy 2026-06-16* ("front-load early, taper to ~8% near reset"), and `install-relay-env` rides the default `install` target — so **every `make install` on every machine rewrites the live value**. Observed live 2026-07-23 and restored by hand. The contradicting SKILL.md knob-table doctrine post-dates it and rests on EVIDENCE: weekly quota is use-it-or-lose-it, so the cap must RISE toward reset (`START < END`); a falling `0.40:0.18` schedule false-stopped a healthy run at 24% 7d-util with ~22 h to reset, forfeiting 76% (2026-06-22). Instance of the CLAUDE.md *derived doc vs ratified source* rule.
  - **What to build**: (1) set `RELAY_ENV_DEFAULTS` to `RELAY_QUOTA_DECAY_7D=0.30:0.90`; (2) **replace** the Makefile comment with a supersession note citing the 2026-06-22 observation, so the 2026-06-16 policy is visibly superseded rather than silently overwritten; (3) the RED spec below.
  - **Acceptance**:
    - a test parses the Makefile default's `START:END` and asserts `START < END` — so any future falling schedule fails loudly;
    - the same test asserts `relay/SKILL.md`'s knob table still documents the RISING direction, so a future edit to EITHER side fails instead of drifting apart again;
    - the Makefile comment names the supersession and its date;
    - `make DEST_DIR=<tmp> install-relay-env` writes `0.30:0.90` into the staged settings file (never the real `~/.claude/settings.json`).
  - **Note on live behaviour**: `~/.claude/settings.json` already holds `0.30:0.90`, so this stops a regression rather than changing today's runtime on zomni. Say so in the close note — a reader must not expect an observable behaviour change.
  - **Tests**: `tests/test_quota_decay_default_74e7.sh` (`# roadmap:74e7`) — hermetic, `DEST_DIR` override into `mktemp -d`; **never point it at the real `~/.claude`**.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_relay_install_manifest.sh tests/test_relay_quota_args.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: the quota-stop algorithm itself; other `RELAY_ENV_DEFAULTS` knobs; changing the SKILL.md doctrine.

- [ ] [ROUTINE] [INBOUND routed:4d2b from loderite] **`/meeting` step 0f.5 must render the `--fabled` findings VERBATIM before any decision prompt** <!-- routed:4d2b --> <!-- id:8c6f -->
  - **Why**: the closing subagent's return lands in a tool result, so a pass can be summarised or numbered `F1..Fn` inside an `AskUserQuestion` while the user has seen NONE of the actual findings. Observed live in loderite (`docs/meeting-notes/2026-07-29-0918-per-piece-material-flavor-model.md`) — the owner had to ask *"I don't see a list of the F's"*. Confirmed in this repo the same day: the 2026-07-29 mechanical-hop meeting presented the assistant's *summary* of each finding with its verification status, not the subagent's prose. Same gap, milder form.
  - **What to build**: mandate in `meeting/SKILL.md` step 0f.5 that the findings are emitted VERBATIM as visible chat text BEFORE any decision prompt — mirroring `meeting/format.md` §Interactive mode's existing rule (*"output the complete verbatim discussion as visible chat content, then call `AskUserQuestion` in the same message"*). Reuse that wording rather than inventing a second phrasing for the same obligation.
  - **Acceptance**:
    - step 0f.5's text names verbatim-before-prompt EXPLICITLY (the words "verbatim" and the ordering constraint, not an implication);
    - it states that summarising or renumbering to `F1..Fn` in place of the prose does NOT satisfy it;
    - a reader following ONLY `meeting/SKILL.md` — without `format.md` — cannot land on summarise-then-ask;
    - `format.md`'s existing Interactive-mode rule is cited, not duplicated in divergent words.
  - **Tests**: `tests/test_meeting_fabled_verbatim_8c6f.sh` (`# roadmap:8c6f`) — a REFERENCE-DOC spec asserting step 0f.5 carries each required element. **State its honest limitation in its own header**: it guards the instruction's presence and content, not the agent's compliance — same posture as `tests/test_review_tier_enumeration.sh`. Do not dress it up as a behavioural test.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_meeting_review_me_wiring.sh tests/test_meeting_c1_executor_contract.sh` still green, then tick and run full `make test`.
  - **Out of scope**: the `--fabled` escalation decision (id:8df5 — the owner's call, `[INPUT — decision]`); changing what the closing subagent returns; `format.md`.

- [ ] [ROUTINE] **Layer A — mechanical declared-path extractor feeding `disjoint-greenlight.sh`** <!-- children-of:1f4f --> <!-- id:b099 -->
  - **Why**: child of id:1f4f, meeting `docs/meeting-notes/2026-07-26-1922-relay-efficiency-in-repo-parallelism.md` D3. The declared path set is NOT missing — 37/39 open items in this repo carry a path-shaped token in `**Context**` / `**Tests**` / `**Wiring**` prose. So this is **EXTRACTION, not invention**. (A field-vocabulary scan for a `**Files**`/`**Touches**` heading returned 0 and was the wrong instrument — owner-corrected in-meeting.) No new authored field for now; promote to an authored `**Touches**` field only if the miss rate justifies it.
  - **Hardening — F3, load-bearing**: an EMPTY extraction ⇒ **run-alone**, never greenlight-all. An empty set is disjoint from everything, so the naive reading turns the maximal under-extraction into the maximal parallelism. This is the single most important acceptance criterion here.
  - **Both metrics are the deliverable, not a nicety** — log the **under-extraction rate** (extracted ⊂ actual merged diff, computable from `drain-integrate.sh`'s merge-check) AND the **false-serialization rate** (declared sets intersect but the actual diffs are disjoint). `**Context**` paths are often CITATIONS rather than touches, so over-extraction would silently destroy the throughput win; a subset-only metric measures half the evidence.
  - **Recorded design rule (D3a), state it in the script header**: the greenlight is a THROUGHPUT OPTIMIZER; the serialized integrator is the SAFETY NET. Never relax integrate checks "because greenlight already proved disjointness".
  - **Scope boundary**: build the extractor as a standalone script with its own test. **It is NOT wired into the engine here** — `disjoint-greenlight.sh` is itself currently unreferenced from `relay-loop.js` (`grep -c` → 0), and the wiring is id:ae08 (PROMOTED 2026-07-30 as a separate `[HARD]` item after the owner lifted the `relay-loop.js` do-not-modify directive). Do not "helpfully" wire it here — id:ae08 owns the wiring and DEPENDS on this extractor.
  - **Acceptance**:
    - given a fixture ROADMAP item with path tokens in `**Context**`/`**Tests**`/`**Wiring**`, the extractor emits that path set;
    - an item with NO extractable path yields an explicit run-alone verdict, NOT an empty-set-is-disjoint greenlight — assert the verdict, not just the empty set;
    - both rates are emitted in a machine-readable form on a fixture corpus with known ground truth;
    - a `**Context**` citation that is demonstrably not a touch is COUNTED in the false-serialization metric rather than silently dropped;
    - the extractor is pure-read: it writes nothing outside its own output stream.
  - **Tests**: `tests/test_declared_path_extractor_b099.sh` (`# roadmap:b099`) — **synthetic fixtures under `mktemp -d` only**. The meeting cites a loderite corpus as evidence; do NOT read another repo at test time (hermeticity, and loderite is off-limits for this run) — copy representative shapes into fixtures instead.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_disjoint_greenlight.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: wiring into `relay-loop.js` (id:ae08); the wave planner (id:1f4f); an authored `**Touches**` field; changing `disjoint-greenlight.sh`'s own contract.

## In-repo parallelism wave model (id:1f4f children) + round-verdict observability — promoted from TODO 2026-07-30 (handoff C2/C3)

> Five items promoted after the owner LIFTED (2026-07-30) the standing directive that
> forbade modifying `relay/scripts/relay-loop.js`. All five were blocked solely on that
> directive. Four are id:1f4f children (meeting
> `docs/meeting-notes/2026-07-26-1922-relay-efficiency-in-repo-parallelism.md`); id:c7dc is
> an independent observability gap filed 2026-07-30. Ids REUSED from TODO.md
> (single-id-two-views) — TODO.md stays the prose SSOT.
>
> `relay-loop.js` editing hazards, read before touching it: it holds 17 ` ```relay-mech `
> fence occurrences, several built by string concatenation and at least one from a VARIABLE
> (`:2360`, `'```relay-mech\n' + cmd + '\n```'`), plus one inside a template literal with
> escaped backticks. After ANY edit run BOTH `node --check relay/scripts/relay-loop.js` and
> `node relay/scripts/lint-workflow-templates.mjs relay/scripts/relay-loop.js`, then the full
> suite. Every line number below was VERIFIED at promotion time (they differ from the numbers
> quoted in the TODO lines, which had drifted) — re-verify before editing.

- [ ] [ROUTINE] **L2 — bounded execute→execute rechain (K≤3)** — **GATE LIFTED — OWNER-RATIFIED 2026-07-31 (`/relay human`).** All three pre-registered rechain semantics stand exactly as written below: **(a)** per-chain deferred review (no mid-chain review), **(b)** NO unwind of already-integrated units on a depth-K reject, **(c)** a chained execute never re-enters the disjoint greenlight. Meeting amendment A2's pre-registration requirement is DISCHARGED — these are now the owner's ruling, not the handoff child's defaults, so the item is PICKABLE. The **(b)** exposure was surfaced explicitly and accepted knowingly: a bad execute at depth 1 can reach `main` before the reject at depth 3 is known. Provenance: `REVIEW_ME.md` (2026-07-30 handoff C2/C3 section) + commit `b311c72`; the 2026-07-30 integrate-time gate line it discharges is in this item's git history. Its RED spec `tests/test_rechain_depth_cc90.sh` is authored and verified genuinely red — executor-ready as specced. <!-- children-of:1f4f --> <!-- id:cc90 -->
  - **Why**: child of id:1f4f, meeting 2026-07-26-1922 D4c. Today ONLY reviews rechain — `relay/scripts/relay-loop.js:2443-2452` gates re-enqueue on `unit.verdict === 'review' && … && !unit.rechained`, with the comment *"Only reviews chain — an execute never re-enqueues"*. So a repo with N open `[ROUTINE]` items drains at ~1 per round and pays one STRONG_MODEL review per Sonnet execute.
  - **What to build**: replace the `rechained` BOOLEAN (`unit.rechained` at `:2445`, set `rechained: true` at `:2449`) with a DEPTH COUNTER (`unit.chainDepth`, default 0), and allow an `execute` unit to re-enqueue another `execute` for the same repo while `chainDepth < K`, K = 3. Chained units stay SERIAL in one lane and are integrated by the existing per-repo `enqueueIntegration` chain (`:820`), so no ROADMAP write collision is possible. The `!rechainedSameRepo` lease-hold exception at `:2460` must extend to the execute→execute case (releasing the lease in the gap lets another run steal the repo).
  - **Pre-registration is MANDATORY and part of the deliverable (amendment A2, `--fabled` F1)** — record all three answers as a block comment at the rechain site, in the SAME commit as the code. The STATUS-QUO-PRESERVING defaults below are what this handoff pre-registers; each is deliberately the choice that changes nothing beyond the chaining itself. **Any DIFFERENT answer is a design decision and needs a `/meeting`, not an executor's judgement** — see REVIEW_ME id:cc90.
    - (a) **Review scope under chaining = PER-CHAIN, deferred.** A chained execute is NOT reviewed mid-chain; the whole chain's commits are reviewed by the next round's `review` verdict, ~~exactly as a single execute's are today~~ **← FALSE PREMISE, CORRECTED 2026-07-31** (meeting `docs/meeting-notes/2026-07-31-1231-execute-review-cadence-starvation.md`): a single execute's commits are **never** reviewed today. `classify-verdict.sh:137-147` is a strict `elif` cascade, so `review` is UNREACHABLE while any actionable `[ROUTINE]` item is open — the deferred review this clause relies on does not happen. The `relay-loop.js:2441` comment (*"the execute's own commits are reviewed next pool"*) asserts the same untruth. **This item's trigger is therefore AMENDED — see `id:8123`**: the audit trigger is a **chain-end classifier RE-ASK** (the loop supplies the fact that a chain ended; `classify-verdict.sh` decides), NOT `chainDepth === K`, because executes never chain today (`chainDepth ≡ 1`) so a depth-K trigger would not have fired for the incident, and every chain ending below K (mid-chain handback, `contract_met:false`, quota-stop) would escape it. `chainDepth` still bounds chain length at K≤3 but is no longer the audit trigger; it resets on strong-audit **watermark advance** (not review dispatch), gated on `id:1a34`. Semantics (b) and (c) are UNCHANGED and remain owner-ratified.
    - (b) **Reject-unwind at depth K = NO UNWIND.** A reject at depth 3 does NOT unwind the already-integrated units at depths 1–2. Integrated is integrated; the reject stops further chaining and surfaces normally. (Unwinding integrated+pushed work is a strictly larger, hazardous design.)
    - (c) **A chained member does NOT re-enter the disjoint greenlight.** A chained execute is dependent on its predecessor — the opposite of what `disjoint-greenlight.sh` certifies — so it runs in its predecessor's lane and is never a member of a parallel wave. Without this the wave silently becomes a DAG.
  - **Acceptance**:
    - a repo with 3 open `[ROUTINE]` items drains all 3 in ONE round with ONE review (not 3 reviews);
    - chaining STOPS at depth K=3 — a 4th chained execute is never enqueued, and K is a named constant, not a magic literal;
    - the depth is carried on the unit (a counter), and `unit.rechained` as a boolean no longer gates the decision anywhere;
    - the lease is HELD across an execute→execute rechain (not released in the gap);
    - `quotaStopped` and `MAX_UNITS` still gate actual dispatch of a chained unit exactly as before;
    - the three pre-registered answers (a)/(b)/(c) are present verbatim as a comment at the rechain site.
  - **Tests**: `tests/test_rechain_depth_cc90.sh` (`# roadmap:cc90`) — source-shape assertions in the style of `tests/test_dispatch_event_sig.sh` (the Workflow engine cannot be run hermetically), PLUS `node --check` and the template linter. Triangulate: assert the counter exists, that K is a named constant with value 3, that the execute branch is reachable (the rechain condition no longer requires `verdict === 'review'`), that the lease-hold exception covers it, and that all three pre-registration answers are recorded.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_dispatch_event_sig.sh tests/test_workflow_template_lint.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: the wave planner (id:1f4f); wiring `disjoint-greenlight.sh` (id:ae08); the round tail (id:3ca7); changing review's own chaining.

- [ ] [ROUTINE] **Layer B — per-unit identity key; re-key the repo-as-primary-key collision sites** <!-- children-of:1f4f --> <!-- id:923b -->
  - **Why**: child of id:1f4f, meeting 2026-07-26-1922 D2 + amendment A3. This is a CONCRETE LATENT BUG TODAY, independent of any fan-out decision — two concurrent same-repo units already collide:
    - `relay-loop.js:1804` — `worktreePathFor` builds a template-literal path of the shape `~/.cache/relay/worktrees/<unit.repo>/<state.runId>-<unit.verdict>` — two concurrent same-repo executes compute the IDENTICAL path.
    - `relay-loop.js:2435` — `state.inFlight = state.inFlight.filter(r => r.repo !== unit.repo)` — clears EVERY same-repo in-flight entry, not just this unit's.
  - **Key shape**: **itemId × attempt**. A bare itemId collides on retries and on the open id:1b1a fail-open-append duplicate-line bug; a bare nonce orphans every pre-crash worktree from id:7809's reconcile view.
  - **RESOLVED — OWNER-RATIFIED 2026-07-31 (`/relay human`): the provisional fallback IS the key.** `${verdict}-${itemId || 'repo'}-${attempt}` is no longer provisional — it is the ratified unit-key shape for the id-less verdicts (`review`/`handoff`/`hard`/injected). It preserves today's one-unit-per-repo-per-verdict behaviour, so it changes nothing beyond making the key total. The HAND-BACK-rather-than-invent instruction below STAYS IN FORCE as the escape hatch if id:ae08's fan-out proves it insufficient. id:ae08 is NOT blocked on this. Provenance: `REVIEW_ME.md` (2026-07-30 handoff C2/C3 section) + commit `b311c72`. The original open-question text follows for the record.
  - **OPEN QUESTION the executor must NOT silently resolve** *(ANSWERED above 2026-07-31 — retained as provenance)* — only `execute` units have an item id (`unit.actionable_routine_ids[0]`, `classify-repo.sh` id:b09e); `review`, `handoff`, `hard` and injected units have NONE. The key needs a defined fallback for them. This handoff's provisional shape is `${verdict}-${itemId || 'repo'}-${attempt}`, which preserves today's one-unit-per-repo-per-verdict behaviour for the id-less verdicts. **If the executor finds this insufficient, hand back rather than invent a scheme** — see REVIEW_ME id:923b.
  - **Lease goes TWO-TIER, NOT flattened (A3)**: the driver keeps the repo-level `claim.sh` lease — that lease is also what a parallel `/meeting` advisory claim collides against ([[claim-lease-mode-blind-no-pool-meeting-skip]]) — while individual units hold unit keys. `enqueueIntegration` (`:820`) stays REPO-keyed; its serialization is correct and must not be re-keyed.
  - **Also required**: an id:7809 reconcile rule for N same-repo worktrees after a crash mid-wave (today's reconcile assumes one worktree per repo).
  - **Acceptance**:
    - two same-repo units in the same run compute DIFFERENT worktree paths (assert with at least two distinct item ids AND a same-item retry, i.e. differing `attempt`);
    - completing one unit removes ONLY that unit's `inFlight` entry; a sibling same-repo entry survives;
    - the repo-level `claim.sh` lease is still acquired/released at repo granularity — a `/meeting` advisory claim on the repo still COLLIDES (this is the regression the two-tier split must not break);
    - `enqueueIntegration` is still keyed by repo;
    - the reconcile rule handles N same-repo worktrees without orphaning any.
  - **Tests**: `tests/test_unit_identity_key_923b.sh` (`# roadmap:923b`) — source-shape assertions plus, where a helper is extracted, a directly-callable purity test of the key function. Triangulate with several unit shapes (two ids, same id different attempt, an id-less review unit). Include `node --check` + the template linter.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_relay_stale_worktree_reap.sh tests/test_context_death_parks_worktree_4df8.sh tests/test_worktree_retire.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: the mode-blind lease REDESIGN (explicitly out of scope per id:1f4f D1); actually fanning out (id:ae08); id:1b1a's md-merge fix.

- [ ] [ROUTINE] **A relay round that dispatches NOTHING leaves no trace of its verdict or reason — emit a `verdict`-kind event per repo per round** <!-- id:c7dc -->
  - **Why**: found 2026-07-30 when a live diagnosis became UNDECIDABLE from the artifacts. `pushEvent` (`relay-loop.js:57`) is called with exactly four kinds — `dispatch` (`:2401`), `integrate` (`:2220`), `handback` (`:2080/:2099/:2268/:2478`), `backstop` (`:67`) — **all of which presuppose a unit EXISTS**. The classification step, the thing that decides every repo's verdict every round, writes nothing durable. In run `relay-20260730-120037-1685` rounds 1–12 each dispatched one `execute` and round 13 dispatched nothing; whether that was a drained backlog, a `blocked` verdict at rank 0 (dirty main checkout, routed:6f85 class), or a replayed `discover-sig` cache verdict is UNRECOVERABLE — and the three imply completely different fixes. `RELAY_STATUS.md` does not close it: it is a per-round SNAPSHOT (rewritten each round) and its `## Stop reason` conflates "still running" with "drained".
  - **This is PLUMBING, not new derivation** — `classify-verdict.sh` already produces `verdict`, `priority_rank`, `reason` and an `evidence[]` array of `{field,value,source}` pointers (`relay/scripts/classify-verdict.sh:118-217`). What is missing is the passthrough: `classify-repo.sh --emit unit` builds the unit dict at `:395-427` and **drops `priority_rank` and `evidence`** — only `verdict`/`reason`/`intensive` survive. So the plumbing spans `classify-repo.sh` → `discover-repo.sh` → `discover-chunk.sh` → `relay-loop.js`.
  - **Emit for the NO-UNIT paths too — this is the whole point.** `discover-repo.sh` routes `blocked` → `surfaced`, no unit (`:135`); `AMBIGUOUS` → `surfaced`, no unit (`:137`); `idle` → unit + `skipped` (`:139`); and a repo-level reconcile block returns `units:[]` SUBSTITUTIVELY at `:98` **before a verdict is ever computed**. A `verdict` event that only covers dispatched units reproduces the exact blind spot. For the substitutive path, where no verdict exists, emit an HONEST sentinel (e.g. `verdict:"", reason:"<the reconcile block reason>"`) — never fabricate a verdict.
  - **Payload**: `{repo, round, verdict, priority_rank, reason, sig, cached}`. `cached` is load-bearing and explicit: the id:c3a6 discover-sig cache means a round may REUSE last round's verdict without re-deriving it (`reusedUnits` / `reusedIdle` in `relay-loop.js`), and a reader currently cannot tell a fresh verdict from a replayed one.
  - **Keep it off the critical path** like the other events — `pushEvent` into `pendingEvents`, drained by `snapshotState` via `relay-state-write.sh event-append`. No new file, no new sink.
  - **Acceptance**:
    - `classify-repo.sh --emit unit` carries `priority_rank` through to the unit (behavioural, hermetic fixture — not a source grep);
    - `pushEvent('verdict', …)` fires once per repo per round, including for repos that produced NO unit (blocked / AMBIGUOUS / substitutive-reconcile / shard-failure) and for `idle` repos;
    - a cache-reused verdict is emitted with `cached: true` and a freshly-derived one with `cached: false`;
    - the substitutive no-verdict path emits an honest empty verdict with the block reason, never a fabricated verdict;
    - the round number is present, so a reader can prove round 13 classified repo X as Y for reason Z;
    - no new file is written and the event goes through the existing `pendingEvents` → `event-append` sink.
  - **Tests**: `tests/test_verdict_event_c7dc.sh` (`# roadmap:c7dc`) — BOTH halves: a hermetic behavioural fixture (in the style of `tests/test_classify_repo_unit.sh`) asserting the `priority_rank` passthrough, AND source-shape assertions (in the style of `tests/test_dispatch_event_sig.sh`) for the `pushEvent('verdict',…)` call, its `cached` field, and its reachability from the no-unit paths. Plus `node --check` + the template linter.
  - **Done-check**: the new test green AND `tests/run-tests.sh tests/test_classify_repo_unit.sh tests/test_dispatch_event_sig.sh tests/test_backstop_fire_log.sh tests/test_discover_repo.sh` still green unmodified, then tick and run full `make test`.
  - **Out of scope**: id:5749 (a BLOCKED agent leaves no on-disk artifact — agent lifecycle, different gap); the injected-unit-never-dispatched item (`inject.sh take` specifically); changing `RELAY_STATUS.md`'s snapshot shape; any new consumer/reporting tool over the events file.

- [ ] [HARD] **Wire the built-but-unreferenced fan-out machinery (`disjoint-greenlight.sh` + `drain-integrate.sh`) into `relay-loop.js`** <!-- children-of:1f4f --> <!-- id:ae08 -->
  - **Why**: child of id:1f4f, meeting 2026-07-26-1922 amendment A1 (`--fabled` finding F2, the strongest of the pass). VERIFIED precondition, re-checked at promotion: `grep -c 'disjoint-greenlight\|drain-integrate' relay/scripts/relay-loop.js` → **0**. Both scripts are built, tested and green (id:5367 / id:2062) but the engine never calls them, so D1's entire one-writer safety argument rests on UNREACHABLE code — while the live path still has executors ticking `ROADMAP.md` in their own worktrees (`relay/references/executor-contract.md:88`), the exact non-union collision id:dc5b C2 exists to prevent, multiplied by N worktrees per wave. *"The plan ships every ingredient and no meal."* This is the [[relay-builtgreen-but-unreferenced]] class.
  - **Scope**: (1) call `disjoint-greenlight.sh plan` from the drain-mode planner; (2) route same-repo integration through `drain-integrate.sh`; (3) change TICK OWNERSHIP in `relay/references/executor-contract.md` — executors report `worked_ids`, the DRIVER ticks — with a contract version bump (currently **v11**; the `## Relay contract` pointer in `CLAUDE.md` must be bumped in the same commit).
  - **Wave model constraints this must respect** (id:1f4f D1, ratified): the wave model is scoped to **drain mode (`--only <cwd>`) ONLY**; fleet mode keeps `enforceOneUnitPerRepo` UNCHANGED. Review is a **HARD BARRIER** — never concurrent with anything in its own repo; review ∥ its follow-up executor is EXPLICITLY REJECTED (the review's output is the executor's input).
  - **Design rule D3a, do not violate**: the greenlight is a THROUGHPUT OPTIMIZER; the serialized integrator is the SAFETY NET. Never relax integrate checks "because greenlight already proved disjointness".
  - **Acceptance**:
    - `grep -c 'disjoint-greenlight' relay/scripts/relay-loop.js` and `grep -c 'drain-integrate' relay/scripts/relay-loop.js` are both non-zero, and the call sites are reachable from an actual drain-mode run (not dead branches);
    - fleet mode behaviour is byte-unchanged — no fan-out outside `--only <cwd>`;
    - a review unit never runs concurrently with any other unit in its own repo;
    - executors no longer tick `ROADMAP.md`; they return `worked_ids` and the driver ticks — asserted against the executor contract text AND the integrate path;
    - the executor contract version marker is bumped and `CLAUDE.md`'s `## Relay contract` pointer matches it;
    - `node --check` and `lint-workflow-templates.mjs` both clean.
  - **Depends on**: id:b099 (the declared-path extractor that FEEDS `disjoint-greenlight.sh`) and id:923b (per-unit identity key — N same-repo worktrees collide on `worktreePathFor` without it). Land both first, or the fan-out is wired onto a known collision.
  - **GATES id:ebbe.**
  - **Done-check**: full `tests/run-tests.sh` green with `tests/test_disjoint_greenlight.sh`, `tests/test_relay_integrate_contain.sh` and `tests/test_workflow_template_lint.sh` unmodified, then tick.
  - **Out of scope**: the fleet-mode fan-out; the mode-blind lease redesign; id:2840 state extraction (D1: not needed under one-writer).

- [ ] [HARD — hands] **Measure first: rank recent relay runs by burn (`relay/scripts/relay-burn.sh`) — THE GATE that orders id:a955 and id:3ca7** <!-- children-of:1f4f --> <!-- id:87f5 -->
  - **PROMOTED 2026-07-31 by owner decision (`/relay human`)** — reusing its existing TODO id (single-id-two-views; no duplicate minted). It was previously tracked ONLY in `TODO.md:62`, so the thing blocking id:a955 (and id:3ca7) was invisible to the execution queue: a955 sat visible-but-unpickable with a `gated-on:87f5` marker pointing at an item the queue did not contain. Promoting it does NOT weaken the gate — a955 stays gated below — it just makes the blocker legible and trackable where the work is scheduled.
  - **Lane**: `[HARD — hands]` (canonical, per `relay/references/hard-lanes.md`) — the OWNER runs this; no pool or executor can. Note the `REVIEW_ME.md` box that surfaced it described 87f5 as "`[INPUT — access]`-class"; its actual head tag in TODO is `[HARD — hands]`. Same meaning (a human must do it by hand), but the tag of record is `[HARD — hands]` — corrected here so scanners and the owner agree.
  - **Why**: child of id:1f4f, meeting `docs/meeting-notes/2026-07-26-1922-relay-efficiency-in-repo-parallelism.md` D4a. Both id:a955 and id:3ca7 are gated on this per-phase burn measurement because it is what ORDERS them — without it the two levers would be picked in an arbitrary order, which is exactly what D4a's pre-registration exists to prevent.
  - **Contract**: a published per-phase ranking that ORDERS id:a955 and id:3ca7. **Pre-register the decision rule BEFORE running** (n runs; per-phase attribution REQUIRED — ranking whole runs by TOTAL burn cannot order levers that target different phases; promote-lever-if-share ≥ X%), and reconcile against the banked 47.6%-discover baseline (`[[skeleton-levers]]`) rather than ignoring it.
  - **Unblocks**: id:a955 (below) and id:3ca7. Until it runs, both stay parked by design.

- [ ] [HARD] **L1 — mechanize the integrator into one `integrate.sh` relay-mech hop** <!-- children-of:1f4f --> <!-- gated-on:87f5 --> <!-- id:a955 -->
  - **GATED on id:87f5 (measure first) — DO NOT START UNTIL 87f5 PUBLISHES ITS RANKING.** id:87f5 is the pre-registered per-phase burn measurement that ORDERS this item against id:3ca7; both are explicitly gated on it (meeting 2026-07-26-1922 D4a). Promoting it here makes it visible in the execution queue; it is NOT pickable yet. id:87f5 itself is still an `[INPUT — access]`-class TODO item and is not promoted.
  - **Why**: child of id:1f4f, meeting 2026-07-26-1922 D4b. `relay-loop.js:2176` builds the integrator prompt and `:2215` dispatches it as a **Sonnet agent** (`model: 'sonnet'`) per completed unit, to run ~40 lines of deterministic steps — lease release → clean-tree gate → verify-isolation → sync-origin → `merge --no-ff` → version-bump → changelog-append → ckpt-tag → git-lock-push → worktree-retire → state-write — each ALREADY a tested script with enumerable exit codes. After id:6176 mechanized quota/inject-take/heartbeat, this is the LAST big LLM agent doing deterministic work, and its cost scales with throughput.
  - **Keep a micro-hop ONLY for the semver "user-observable?" judgement.** That also resolves the recorded contradiction that the bump step's prose says *"the REVIEWER's alone"* while running on a Sonnet integrate agent ([[bump-changelog-reaches-one-of-three-paths]]).
  - **Fail-closed with LOUD escalation, never a silent fallback.** Mechanizing moves the failure mode from visible-and-recoverable to silent-and-corrupting (the id:25aa wrong-anchored-ckpt class). Any nonzero exit ⇒ handback, surfaced.
  - **Preserve, verbatim, the safety rules currently carried in the integrator PROMPT** — they are not decoration and they will be LOST in a naive port: the id:aa93 clean-tree gate (NEVER `git stash` / `checkout --` / `reset --hard` / `git clean` on a foreign-dirty main checkout — DEFER instead) at `:2179`, and the id:6e02 destructive-cleanup scope (remove ONLY this unit's own worktree+branch; a zero-commit branch whose tip is an ancestor of main is NOT proof of a leftover — it is what a LIVE parallel child's fresh worktree looks like) at `:2200`.
  - **Acceptance**:
    - a run completes integration with NO Sonnet integrate agent (the only remaining agent on the path is the semver micro-hop);
    - a forced nonzero at each mechanized step surfaces LOUDLY as a handback — assert several distinct steps, not one;
    - the id:aa93 defer-don't-clean rule and the id:6e02 cleanup-scope rule are enforced MECHANICALLY (fail-closed), not merely restated in a comment;
    - `enqueueIntegration`'s per-repo serialization is unchanged;
    - the id:c563 no-agent-before-dispatch invariant (`tests/test_relay_integrator_noop_guard.sh`) still holds or is deliberately superseded with its test updated, not deleted.
  - **Done-check**: full `tests/run-tests.sh` green with `tests/test_relay_integrate_contain.sh`, `tests/test_integrate_ckpt_merged_tip.sh` and `tests/test_relay_integrator_noop_guard.sh` unmodified, then tick.
  - **Out of scope**: the round tail (id:3ca7); the wave planner; changing the bump/CHANGELOG POLICY (only its execution substrate moves).

## 2026-07-31 handoff C2 — execute→review cadence starvation (+ two watermark/registry defects)

> Promoted from `TODO.md` reusing each item's existing id (single-id-two-views — no duplicate
> minted). Items id:907e / id:8123 / id:6217 come from the owner-ratified meeting
> `docs/meeting-notes/2026-07-31-1231-execute-review-cadence-starvation.md`; id:c500 and id:069b
> are independent defects found the same day. **Work id:907e FIRST** — it is that meeting's
> re-ranked PRIMARY fix (D3/A4) and the only decision that addresses the observed incident.
> Every line/behaviour claim below was re-verified against the working tree at promotion time
> (2026-07-31, base `b92c4ab`); one claim inherited from the meeting was found FALSE and is
> corrected in place under id:8123.

- [x] [ROUTINE] **A `gated-on:` marker whose target is not a dispatchable ROADMAP item reads as "waiting" but means "never" — lint it** <!-- id:49e0 -->
  - **Origin, not symptom.** THREE instances surfaced in a single day (2026-07-31): `a955` gated on `87f5` (which lived only in TODO — fixed by promoting it), `8123` gated on `1a34` (same, fixed by `id:1a34`'s promotion above), and `f6d5` gated on `8ba1` (retired 2026-07-24 — a gate on an item that will never come back). Each was found by a human noticing; nothing detects them.
  - **Why it is worse than a stale marker**: a gated item is deliberately unpickable, so it sits in the queue looking *scheduled*. There is no signal distinguishing "blocked, will unblock" from "blocked forever". The item silently never runs and never surfaces — the loud-detection-that-nothing-acts-on failure family, one step earlier: here there is no detection at all.
  - **What to build**: a check that, for every `<!-- gated-on:XXXX -->` in `ROADMAP.md`, the target `XXXX` (a) EXISTS as a checkbox item in `ROADMAP.md`, and (b) is not already `[x]`-and-retired in a way that makes the gate permanent. Report LOUDLY per violation, naming both ids. Wire it into `roadmap-lint.sh` (grammar/lane sibling) and therefore into `relay-doctor.sh`, which already collates lint output. Decide report-only vs `--strict` consistently with the existing lint tiers.
  - **Out of scope**: auto-promoting a missing target (that is handoff C2's judgement, and guessing a lane is banned); resolving gates across repos.
  - **Acceptance**: a fixture ROADMAP with a `gated-on:` pointing at (i) a TODO-only id, (ii) a retired/archived id, and (iii) a valid open item yields exactly two loud findings and one pass.

- [x] [ROUTINE] **The pool silently works `actionable_routine_ids[0]`, so the item a human cares about is never the one picked — surface the choice** <!-- id:8af2 -->
  - **Origin, not symptom.** An `execute` unit carries `actionable_routine_ids[0]` (`id:b09e`). On 2026-07-31 this repo had **21** actionable `[ROUTINE]` items; the primary cadence fix `id:907e` sat mid-list, so running the pool would have worked `cbd2` instead — and nothing anywhere would have said so. The mismatch is invisible until you read the JSON by hand.
  - **The real defect is VISIBILITY, not ordering.** Mechanisms to override already exist (`/relay inject --item`, `--priority`); what is missing is any surface saying *"this repo's execute unit will work `<id>`"* before it runs. A human who does not already suspect the problem cannot see it.
  - **What to build**: surface the chosen item id — in `RELAY_STATUS.md`'s per-repo row and in the dispatch event (`relay-events.jsonl`), so both the live view and the forensic log record which item an execute unit actually took, alongside how many were eligible (e.g. `execute → id:cbd2 (1 of 21 actionable)`). The count is what makes a mid-list primary fix obvious at a glance.
  - **Out of scope**: changing the SELECTION rule, adding an item-level priority field, or re-ordering `actionable_routine_ids` — those are design calls; this item only makes the existing behaviour legible. If the surfaced counts later justify a selection change, that is a separate item.
  - **Acceptance**: a dispatched execute unit's chosen item id and the eligible count appear in both `RELAY_STATUS.md` and the dispatch event.

- [x] [ROUTINE] 🔴 **GATE-CLEARING — the DOCUMENTED `ckpt-tag.sh` label format never advances `last_strong_ckpt`, so supervised strong checkpoints silently leave the watermark stale** <!-- id:1a34 -->
  - **PROMOTED 2026-07-31 reusing its existing TODO id** (single-id-two-views; no duplicate minted). It was tracked ONLY in `TODO.md:467` while `id:8123` carries `<!-- gated-on:1a34 -->` — so 8123 was gated on an item the execution queue did not contain, and its gate could never clear. Same structural bug as `a955`→`87f5` earlier today; the general fix is `id:49e0`.
  - **The mismatch**: `ckpt-tag.sh:104` detects the strong model with `grep -oE 'claude-[a-z0-9.-]+' <<<"$label"` — it requires a FULL `claude-*` id — and only then runs `toml-set last_strong_ckpt`/`strong_model` (`:106-109`). But the script's own usage line (`:5`) documents `-l "reviewer (fable)"` and `relay/SKILL.md`'s integrate step says `-l "reviewer (<model>)"` — a BARE model name, which never matches. The sync is skipped **with no warning**: the `|| true` plus the `if` make a non-match indistinguishable from success.
  - **Why it gates id:8123**: 8123's `chainDepth` reset fires on strong-audit **watermark ADVANCE**. A watermark that silently fails to advance would wedge the chain even after a genuinely successful review — the reset would never fire, so execution halts at K per repo. 8123 cannot be trusted until this is fixed.
  - **What to build**: make the documented format and the detected format agree — fix the usage line and `SKILL.md` to require a full `claude-*` id, AND make the non-match LOUD (a stderr line naming the label), so a skipped sync can never again be silent. Note the loud half is the same requirement `id:c500` part (2) carries; land them consistently.
  - **Acceptance**: a label with no `claude-*` substring emits a stderr line and does not silently leave `last_strong_ckpt` unchanged; a label following the documented usage line DOES advance it.

- [x] [ROUTINE] **PRIMARY — amend `id:c919`'s `workCreated` predicate to VERDICT-CLASS CHANGE, so the drain does not quit on the exact round its verdict would have flipped** <!-- id:907e -->
  - **Why**: meeting 2026-07-31-1231 decision **D3 (A4)**, re-ranked PRIMARY because it is the only decision from that meeting that addresses the observed incident. `id:c919` is CLOSED (`ROADMAP.md:1753`) and *deliberately* excluded gate-writing handbacks. Its reasoning counts only **dispatchable `[ROUTINE]`** work — but dropping `actionable_routine_open` to 0 flips the verdict `execute → review`, so the round created a **review** unit that c919 scored as nothing. Loderite trace, run `relay-20260730-173701-17132`: rounds 8-9 handed back, wrote the gates, both counted dry, K=2 tripped, the pool quit on the exact round the verdict changed. Riku's concession on record: c919's own asymmetry argument ("under-draining merely runs an extra round; over-draining could strand work") argues *for* counting the gate-write — c919 got its asymmetry backwards for this case.
  - **VERIFIED in-code at promotion (2026-07-31, not merely quoted)**:
    - `relay/scripts/relay-loop.js:2266` — `const workCreated = report && report.route === 'hard-split' && hbSplit > 0` (the sole PRODUCER; `:2255-2265` is c919's rationale comment).
    - `relay/scripts/relay-loop.js:2267` — the value is pushed onto `state.handbacks`; `:2575-2576` folds it into the round result as `workCreated`.
    - `relay/scripts/relay-loop.js:1072` and `relay/scripts/drain.mjs:103` — the two byte-identical CONSUMERS (`isDryRound`).
    - `relay/scripts/classify-verdict.sh:137-147` — the strict `elif` cascade whose class flip this predicate must observe (`actionable_routine > 0` → `execute`, rank 1; `elif substantive_unaudited` → `review`, rank 2).
    - The id:c3a6 discovery cache is in `relay-loop.js` (`:1201-1227`, "Content-addressed discovery cache"), NOT in the classifier — `classify-verdict.sh` and `classify-repo.sh` are documented SIDE-EFFECT-FREE and uncached. That is what makes clause (i) below implementable: bypass = call the classifier scripts directly rather than read the round's cached verdict.
  - **Scope note**: the fix site is inside `relay/scripts/relay-loop.js`, which is under the owner's 2026-07-30 `id:4313` do-not-modify directive. That directive was **scope-lifted for exactly this work** in the 2026-07-31 meeting (D4). Do not take the lift as license to touch anything else in that file.
  - **What to build — THREE MANDATORY CLAUSES, each closes a hole the `--fabled` pass found. Dropping any one ships the amendment as a no-op or a livelock:**
    1. **(i) Direct classifier invocation, CACHE-BYPASSED.** Re-derive the repo's verdict class from a FRESH `classify-repo.sh` / `classify-verdict.sh` run at the point the predicate is computed. It must NOT read the round's cached/reused discovery verdict — under the id:c3a6 signature cache the answer is always "unchanged" and the whole amendment ships as a silent no-op, which is the banned detector-without-resolution anti-pattern. Say in a comment at the site HOW the cache is bypassed and cite `id:c3a6`.
    2. **(ii) Predicate scoped REPO-WIDE, not per-handback causality.** The question is "did THIS ROUND change this REPO's verdict class?", not "did this particular handback cause it?" — in-repo parallelism (`id:1f4f`) lets another unit flip the class within the same round, so per-handback attribution under-counts. The current producer computes `workCreated` inside the per-unit handback `else` branch from a single `report`; the amended predicate needs a repo-scoped before/after comparison.
    3. **(iii) OSCILLATION GUARD.** Verdict-class flapping within a window counts as DRY — or, at minimum, the `--max-rounds` seatbelt exit reason distinguishes this case so it fails LOUDLY instead of looking like a normal termination. Without it a repo whose class alternates `execute ↔ review` keeps the pool alive forever (`--fabled` F6).
  - **Acceptance**:
    - the literal `report.route === 'hard-split' && hbSplit > 0` is no longer the whole predicate;
    - the predicate site invokes `classify-repo.sh` or `classify-verdict.sh` directly and documents the id:c3a6 cache bypass in-source;
    - the predicate compares a repo-scoped verdict class BEFORE vs AFTER the round (a named before/after pair), not a single handback's `route`;
    - a named oscillation guard exists and is reachable from the dry-round path, with its own exit-reason string when it fires;
    - a fixture in which a gate-writing handback drops `actionable_routine_open` to 0 while `substantive_unaudited` is true does NOT score the round dry;
    - `isDryRound`'s existing terms (`substantive`, `surfaced`) are unchanged — this widens `workCreated` only;
    - `node --check relay/scripts/relay-loop.js` and `node relay/scripts/lint-workflow-templates.mjs relay/scripts/relay-loop.js` both clean.
  - **Tests**: `tests/test_workcreated_verdict_class_907e.sh` (`# roadmap:907e`) — source-shape assertions in the style of `tests/test_rechain_depth_cc90.sh` (the Workflow engine cannot be run hermetically), PLUS a real hermetic `classify-verdict.sh` fixture proving the `execute → review` class flip the predicate must observe.
  - **Done-check**: tick this box, then `tests/run-tests.sh` fully green with `tests/test_rechain_depth_cc90.sh` and `tests/test_dispatch_event_sig.sh` unmodified.
  - **Out of scope**: changing the K=2 dry threshold itself; the `substantive`/`surfaced` terms; anything else in `relay-loop.js` beyond the predicate and its guard.

- [x] [ROUTINE] **Amend `id:cc90`: a chain-end classifier RE-ASK replaces the `chainDepth === K` forced-review trigger, and correct two false-premise sites** <!-- gated-on:1a34 --> <!-- id:8123 -->
  - **FIELD NAME — OWNER-RATIFIED 2026-07-31 (`/relay human`, REVIEW_ME): the spec stays PERMISSIVE.** `tests/test_chain_end_reask_8123.sh` deliberately probes four spellings (`chain_ended` / `chainEnded` / `chain_end` / `chain_end_reason`) so it constrains BEHAVIOUR, not vocabulary; the implementer picks. The owner declined to narrow it to a specific name.
  - **⚠ HARD REQUIREMENT that comes with that permissiveness — whichever field name is chosen MUST be added to `relay/scripts/discover-sig.sh`'s hashed blob.** `classify-verdict.sh`'s input object is a contract surface read by `classify-repo.sh`, `discover-sig.sh` and `gather-repo-state`. The sig cache (`id:c3a6`) reuses last round's verdict when a repo's signature is unchanged, and **under-invalidation is its only hazard** — a NEW classifier signal that is not in the hashed blob means a chain-end verdict can be served STALE from cache, i.e. the forced review silently never fires. This is the identical trap `id:907e` clause (i) exists to close on the other side; both must hold or the cadence fix is a no-op in exactly the situation it was built for. Acceptance: the chosen field appears in `discover-sig.sh`'s blob, and a test proves a change in it changes the signature.
  - **Why**: meeting 2026-07-31-1231 amendment **A1** (which supersedes that meeting's own D1 and D2) plus **D2b**. The starvation is structural and total, not contention: `relay/scripts/classify-verdict.sh:137-147` is a strict `elif` cascade, so `review` (rank 2) is UNREACHABLE while a single actionable `[ROUTINE]` item exists (this repo has 18 open). There is no aging term, no unaudited-depth term and no forced-review path anywhere in `relay-loop.js`.
  - **Why the originally-ratified trigger was wrong** (`--fabled` F1, independently confirmed): `relay/scripts/relay-loop.js:2436-2452` gates re-enqueue on `unit.verdict === 'review' && … && !unit.rechained`, with the comment *"Only reviews chain — an execute never re-enqueues"* (`:2440`). So executes never chain today and a depth-K trigger would NOT have fired for the 16-unaudited-checkpoint incident it was designed to fix. Every chain ending BELOW K — mid-chain handback, one-unit-per-repo-per-round topology, `contract_met:false`, quota-stop, agent error — escapes it.
  - **⚠ CORRECTION to a claim carried in the meeting note and in `TODO.md:55`.** Both refer to `chainDepth ≡ 1` today and to `chainDepth` as an existing counter. **`chainDepth` does not exist anywhere in this repo** — verified at promotion: `grep -rn 'chainDepth' relay/ tests/` returns nothing outside `tests/test_rechain_depth_cc90.sh` (which asserts its ABSENCE is the red). Today's mechanism is the BOOLEAN `unit.rechained` (`relay-loop.js:2445`, set at `:2449`); `chainDepth` is `id:cc90`'s own unshipped deliverable. The substantive conclusion is unaffected and in fact strengthened — executes cannot chain at all — but do not write code against a counter that is not there yet.
  - **What to build**: at chain end the loop re-invokes `classify-verdict.sh`, and the cascade is amended so `review` is REACHABLE while `[ROUTINE]` work is open. The loop supplies only the FACT that a chain ended; the classifier remains the sole verdict authority, so its purity is intact and there is no bypass. `id:cc90`'s K≤3 still bounds chain length but is **no longer the audit trigger**. **No separate aging term is built.**
  - **Reset semantics (D2b)**: `chainDepth` resets on **strong-audit watermark ADVANCE**, not on review dispatch — dispatch-reset would silently degrade the guard to nothing under an apex outage. Plus a NAMED escape so an outage degrades to surfaced-and-skipped rather than a silent halt at K per repo.
  - **GATED on `id:1a34`** (stale `last_strong_ckpt`) being fixed, or the watermark validated as resolvable, before it is trusted — otherwise a *successful* review still wedges the chain. Note `id:c500` below is a second, independent way the same watermark fails to advance.
  - **Correct BOTH false-premise sites in the same change**: (a) `id:cc90`'s semantic (a) in `ROADMAP.md:2272` — already struck-through and annotated by an earlier pass, finish it when the code lands; (b) the `relay-loop.js:2441` comment *"the execute's own commits are reviewed next pool"*, which is untrue and still stands verbatim.
  - **THE AMBIGUITY THE RED SPEC MUST PIN — read before writing code.** Making `review` UNCONDITIONALLY reachable would restore the 1:1 apex-review-per-execute cost the meeting explicitly rejected (one Opus review per cheap Sonnet execute). The intended shape is that the loop passes a **"chain ended" fact** into the state JSON and `review` outranks `execute` **only under that fact**. If you cannot make the gating hold, HAND BACK — do not ship an unconditional reordering.
  - **Accepted cost, recorded knowingly**: K=3 against 18 open items implies a fixed ~25% apex duty cycle on chained work, imposed by a hardcoded K rather than a tunable threshold.
  - **Acceptance**:
    - a chain ending BELOW K (mid-chain handback, `contract_met:false`, quota-stop) still yields a review;
    - `review` is NOT unconditionally reachable — with no chain-end fact present the cascade is byte-equivalent to today's, and the chain-end input is a named field, not an implicit default;
    - the trigger is a classifier RE-ASK: the loop does not emit a `review` unit directly, and `classify-verdict.sh` stays side-effect-free;
    - the reset is keyed on watermark ADVANCE, with a named outage escape that surfaces-and-skips rather than halting;
    - both false-premise sites are corrected in the same commit;
    - `node --check` and `lint-workflow-templates.mjs` clean.
  - **Tests**: `tests/test_chain_end_reask_8123.sh` (`# roadmap:8123`) — a real hermetic `classify-verdict.sh` fixture pair (chain-end fact present vs absent) plus source-shape assertions on the loop side.
  - **Done-check**: tick this box, then `tests/run-tests.sh` fully green with `tests/test_wire_grammar_classify.sh` and `tests/test_rechain_depth_cc90.sh` unmodified.
  - **Out of scope**: rewriting the D3 verdict cascade wholesale; any multi-knob review budget; changing what ADVANCES the watermark; a separate aging term.

- [ ] [ROUTINE] **Extract `isDryRound`/`workCreated` into ONE shared definition — CROSS-FILE, via a generation step; record the drain-path gap MOOT-BY-RETIREMENT** <!-- gated-on:907e --> <!-- id:6217 -->
  - **OWNER-RATIFIED 2026-07-31 (`/relay human`, REVIEW_ME): the cross-file single-definition contract STANDS — build the mechanism.** The handoff raised that "exactly one definition" may be unreachable, because `relay-loop.js` is Workflow-sandbox JS and **cannot `import`** (`drain.mjs:20-22` says so verbatim: *"relay-loop.js (the Workflow sandbox cannot `import`) carries BYTE-IDENTICAL inline copies of these bodies"*). The owner considered and **REJECTED** both weaker readings: (a) a byte-equality lint over two hand-maintained copies, and (b) re-scoping to "one definition INSIDE `relay-loop.js`" (already true today, which would make this item near-empty). **So the deliverable is the mechanism itself**: a generation/inlining step that EMITS `relay-loop.js`'s copy from the single source in `drain.mjs`, so the duplication becomes derived rather than maintained. Note this introduces a build step to a repo whose `CLAUDE.md` currently states *"There is no build step"* — that line must be updated in the same change, or the architecture doc immediately contradicts the code (the doc-vs-code rule).
  - **The RED spec stands as written** — `tests/test_dryround_single_definition_6217.sh` asserts the ratified contract and instructs a hand-back rather than a weakening; that is now the correct behaviour, not a blocker.
  - **Do NOT grep-and-delete the sync comments.** `drain.mjs:21` is the `isDryRound` duplication admission and becomes obsolete when generation lands; `drain.mjs:157` is a DIFFERENT comment belonging to `classifyRepeatHandbacks` and MUST survive (the spec carries a negative assertion for it). An earlier version of this item mis-cited `:157` for the `isDryRound` case — corrected here.
  - **Why**: meeting 2026-07-31-1231 decision **D4, amended by A3**. `isDryRound` is duplicated byte-identically and the file says so.
  - **VERIFIED in-code at promotion — with a line-number CORRECTION to `TODO.md:57`**: the duplicated bodies are `relay/scripts/drain.mjs:91-104` (`isBlockedRound`/`isDryRound`) and `relay/scripts/relay-loop.js:1067-1073`. The "keep the two in sync" admission for THESE functions is at **`drain.mjs:21`** (*"relay-loop.js … carries BYTE-IDENTICAL inline copies of these bodies — keep the two in sync"*) and mirrored at `relay-loop.js:1067` (*"inline copies of drain.mjs's isBlockedRound/isDryRound (keep byte-equivalent)"*). `drain.mjs:157` carries a SEPARATE, similarly-worded sync comment that belongs to `classifyRepeatHandbacks`, not to `isDryRound` — the TODO cited that line by mistake. **Delete/repoint only the `isDryRound` comments; leave `:157` alone.** The `workCreated` PRODUCER exists only at `relay-loop.js:2266`.
  - **SCOPE CORRECTED mid-meeting on a verified stale premise — do not widen it back.** The original decision would have imported the shared module into `drain-driver.mjs`, but `ROADMAP.md:32` records that driver **FROZEN** (superseded 2026-07-24; go-forward is the `id:7488` Workflow re-wire). The extraction is therefore **`relay-loop.js`-internal ONLY**, and the drain-path `undefined → 0` gap is recorded **MOOT-BY-RETIREMENT** citing `ROADMAP.md:32` / `id:7488`. The module is still extracted so `id:7488` adopts ONE implementation instead of inheriting the duplication. `--fabled` F5 also noted that import ≠ wired: `drain-driver.mjs` has no handback-report plumbing to call a producer from (the [[relay-builtgreen-but-unreferenced]] class) — a second reason not to touch it.
  - **DO THIS AFTER `id:907e`**, or the extraction will be redone: 907e rewrites the very predicate being extracted.
  - **Acceptance**:
    - exactly ONE definition of `isDryRound` and ONE of the `workCreated` predicate remain reachable from `relay-loop.js`;
    - the `isDryRound`/`isBlockedRound` "keep the two in sync" comments are DELETED (or rewritten to state the new single-source relationship) rather than left lying;
    - `drain.mjs:157`'s `classifyRepeatHandbacks` sync comment is UNCHANGED;
    - `drain-driver.mjs` is not modified and imports nothing new; the moot-by-retirement note is recorded in-source citing `id:7488`;
    - `drain.mjs`'s exported behaviour is unchanged (`tests/run-tests.sh` drain tests untouched and green);
    - `node --check` and `lint-workflow-templates.mjs` clean.
  - **Tests**: `tests/test_dryround_single_definition_6217.sh` (`# roadmap:6217`).
  - **Done-check**: tick this box, then `tests/run-tests.sh` fully green with the `test_drain_driver_*.sh` files unmodified.
  - **Out of scope**: un-freezing `drain-driver.mjs` — a separate owner call this meeting did not make.

- [x] [ROUTINE] **HIGH PRIORITY — `relay-reconcile.sh --integrate` hardcodes a checkpoint label with no model id, so every reconcile-integrate silently leaves `last_strong_ckpt` stale** <!-- id:c500 -->
  - **PART (1) DECIDED — OWNER-RATIFIED 2026-07-31 (`/relay human`, REVIEW_ME): a reconcile checkpoint deliberately does NOT count as STRONG.** The handoff correctly flagged the attribution as genuinely undecided (a reconcile-integrate can be run by a human, an apex session, or `--auto`) and offered three answers; the owner chose this one, and **REJECTED** both alternatives — caller-passes-the-model-id and read-it-from-the-environment — because either would make a reconcile-integrate ADVANCE `last_strong_ckpt`, so merged orphan work would read as audited when nobody audited it. **This ratifies today's de-facto behaviour and makes it deliberate**: `reconcile (auto/human)` already fails `ckpt-tag.sh:104`'s `claude-*` grep, so the audit window correctly stays open across a reconcile (verified live 2026-07-31 — `relay-ckpt-20260731-1147` left `last_strong_ckpt` at `relay-ckpt-20260730-2018`). **What to build for part (1) is therefore documentation, not attribution plumbing**: state explicitly in `relay-reconcile.sh` (at the `-l` call site, `:278`) and in this repo's relay docs that a reconcile checkpoint is intentionally non-strong, so the label can never again be read as an oversight.
  - **PART (2) is unconditional and unchanged** — `ckpt-tag.sh` must be LOUD when a label yields no `claude-*` match. That is what distinguishes "deliberately not strong" (part 1) from "someone forgot the model id", and without it the two are indistinguishable. It lands regardless of part (1).
  - **Consequence for `id:8123`**: its watermark-advance chain reset depends on the watermark being trustworthy. Under this ruling a reconcile never advances it, which is the CONSERVATIVE direction (a chain stays un-reset, so a review is still owed) — no additional gating needed beyond the existing `id:1a34` dependency.
  - **Why**: found 2026-07-31 by the agent that integrated the c480 orphan; the owner asked for it soon. This is the banked [[ckpt-tag-label-needs-full-model-id]] hazard with the difference that makes it worse: that finding is about a HUMAN typing the documented-but-wrong bare form, which a careful operator can avoid — here the bad label is BAKED INTO THE SCRIPT, so it recurs on *every* reconcile-integrate no matter who runs it.
  - **VERIFIED in-code at promotion**:
    - `relay/scripts/relay-reconcile.sh:278` — `ckpt_tag="$("$CKPT_TAG" "$repo" -m "reconcile integrate: $subj" -l "reconcile (auto/human)")"`. The label is a fixed literal containing no `claude-*` string.
    - `relay/scripts/ckpt-tag.sh:104` — `model="$(grep -oE 'claude-[a-z0-9.-]+' <<<"$label" | head -n1 || true)"`; `:105` gates the strong sync on `[[ -n "$model" && … ]]`, so on no match `:106-109` (`last_strong_ckpt`, `strong_model`) never run.
    - **And it skips SILENTLY**: the only `WARNING` lines in that block (`:107`, `:109`) fire when a `toml-set` FAILS, never when the sync is never ATTEMPTED. The `else` branch at `:112` prints a note only for an unmanaged repo. So a reconcile-integrate looks completely successful while the watermark it should have advanced stays put. Confirmed live: `relay-ckpt-20260731-1147` (this repo, the c480 orphan integrate) is labelled `reconcile (auto/human)`; that tag is already pushed and cannot be rewritten.
  - **Compounds `routed:f77d`/`id:3c34`** (a `last_strong_ckpt` that does not resolve): one item makes the watermark point at a missing tag, this one makes it fail to advance at all. It is also a second independent way `id:8123`'s watermark-advance reset can wedge.
  - **What to build — part (2) is unconditional; part (1) carries one open question you must ANSWER, not guess:**
    1. Make `relay-reconcile.sh` record the ACTUAL apex model of the integrating session rather than a fixed string. **A reconcile-integrate may be run by a human, by an apex session, or by `--auto`** — decide whether the model id is passed in by the caller, read from the environment, or whether a reconcile checkpoint should deliberately NOT count as strong at all. **If the last is right, that is a legitimate answer** — but then say so EXPLICITLY in the label text and a comment, so it does not read as an oversight. If you cannot settle it from the code, HAND BACK with `route: decision-gate` rather than picking one silently.
    2. **Regardless of (1), make `ckpt-tag.sh` LOUD** when a label yields no `claude-*` match: a skipped strong-sync must print a stderr line NAMING the label, never pass silently ([[no-swallow-stderr]]; the mechanize-first "loud failure, never a silent fallback" rule).
  - **Acceptance**:
    - a checkpoint label containing no `claude-*` substring makes `ckpt-tag.sh` emit a stderr line that quotes the offending label and says the strong-watermark sync was skipped;
    - that path still exits 0 and still prints the tag name on stdout — this is a warning, not a failure;
    - a label that DOES contain a strong `claude-*` id still syncs `last_strong_ckpt` + `strong_model` exactly as today, with no new stderr noise;
    - a `sonnet`/`haiku` label still skips the strong sync (the existing `:105` exclusion is unchanged) — decide and TEST whether that skip is loud too, and state which you chose;
    - `relay-reconcile.sh:278` no longer passes a hardcoded model-less literal, or passes one that explicitly declares itself non-strong in the label text plus an in-source comment.
  - **Tests**: `tests/test_ckpt_label_no_model_loud_c500.sh` (`# roadmap:c500`) — hermetic, real `git` fixture repo + a scratch `relay.toml`, never touching `~/.config/relay`.
  - **Done-check**: tick this box, then `tests/run-tests.sh` fully green with `tests/test_integrate_ckpt_merged_tip.sh` unmodified.
  - **Out of scope**: rewriting already-pushed tags; `id:3c34`'s unresolvable-watermark half.

- [ ] [ROUTINE] **`meeting/personas.md` has accreted redundant entries because `merge=union` can never reconcile a re-registration** <!-- id:069b -->
  - **Why**: found 2026-07-31 while auditing the registry after a live collision (same meeting). **Root cause is structural, not sloppiness**: `.gitattributes:1` sets `meeting/personas.md merge=union`, so when two sessions append the same persona — or one session re-registers an existing one with enriched wording — union merge keeps BOTH sides forever.
  - **VERIFIED at promotion** (the TODO quotes 79/52; the reproducible commands give): `grep -oE '\*\*[A-Za-z]+\*\*' meeting/personas.md | wc -l` → **81**, `| sort -u | wc -l` → **54**, so **27 redundant**; `| sort | uniq -d | wc -l` → **18 duplicated names**. **Sage** and **Otto** appear 3× each; **Quinn** is at `meeting/personas.md:32` and `:74`. **CORRECTION to `TODO.md:184`, checked line-by-line:** **Cal** is NOT an exact byte-duplicate — `:138` is a strict SUPERSET of `:76` (same text plus an `extended 2026-07-16 (…)` tail). That matters for the fix: naive de-duplication by exact-line equality would keep both, and naive keep-first would DISCARD the richer entry. Also verified: `meeting/append.sh:327` routes `-t personas` to `$SKILL_DIR/personas.md` and `:28` documents that path as *"free prose, no validation, no echo"* — it is the sole sanctioned writer and it validates nothing today.
  - **The reassuring half, verified before filing: NO name means two different things.** Every duplicate is a same-lens re-registration with progressively richer wording (same emoji, same core lens), so nothing is semantically ambiguous today.
  - **The hazard is LENGTH, and it has already bitten**: at ~80 entries the file is long enough that a partial read misses names — which is exactly how the 2026-07-31 session introduced a "new" 🧭 persona under the name **Quinn**, already registered since 2026-05-21, and had to rename it to Wren mid-meeting. A registry whose duplicates are harmless can still cause a harmful collision by being too long to read.
  - **What to build (three parts)**:
    1. A **dedup pass keeping the RICHEST entry per name**, MERGING the `extended <date> (<project>/<slug>)` provenance tails rather than dropping them — the enrichment history is the useful part, and losing it is a silent data loss disguised as cleanup.
    2. **Decide whether `merge=union` is still right for this file given that it cannot dedup.** The alternative is a normal merge plus an `append.sh`-side *"name already registered, extending instead"* path — which is where the reconciliation actually belongs, since `append.sh -t personas` is already the sole sanctioned writer. State which you chose and why in the commit message.
    3. A **conformance check that FAILS when a name appears twice**, wired into the test suite so the file cannot re-accrete. **Path is pinned: `meeting/personas-conformance.sh <personas.md>`** — exit 0 clean, non-zero + the offending names on stderr when a name repeats. The RED spec asserts that exact path, so do not rename it.
  - **Acceptance**:
    - `grep -oE '\*\*[A-Za-z]+\*\*' meeting/personas.md | sort | uniq -d` is EMPTY;
    - every name surviving the dedup carries the union of its variants' provenance tails. Verified target sets (all distinct dates present in the file today, and all must survive): **Sage** `{2026-05-08, 2026-06-11}`, **Otto** `{2026-06-03, 2026-06-17, 2026-07-30}`, **Quinn** `{2026-05-21, 2026-06-16}`, **Cal** `{2026-06-17, 2026-07-16}`. Note Sage has THREE entries but only TWO distinct dates — count dates, not entries;
    - re-registering an EXISTING name through `append.sh -t personas` EXTENDS the existing entry instead of appending a second one, and says so on stderr;
    - registering a genuinely NEW name still appends normally;
    - the conformance check fails loudly on a seeded duplicate and passes on the deduped file;
    - no persona's emoji or core lens text is silently altered by the dedup.
  - **Tests**: `tests/test_personas_no_duplicate_names_069b.sh` (`# roadmap:069b`) — hermetic (`mktemp -d` copy of `meeting/`), never writes the real registry.
  - **Out of scope**: changing the registry's FORMAT; auto-merging lenses that genuinely DIFFER — none exist today, and if one ever does it must be a LOUD reject, never a silent merge.
