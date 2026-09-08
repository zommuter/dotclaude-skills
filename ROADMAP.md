# Roadmap <!-- fables-turn roadmap v1 -->

Executor-facing task spec. Each item is sized for ONE Sonnet session. Items are
the single source of truth — TODO.md carries only a summary line. Executors tick
checkboxes; only the reviewer adds, removes, or re-scopes items.

Read `CLAUDE.md` (§Testing, §Gotchas, §Relay contract) before starting any item.
Done-check for every item: tick the item's checkbox below, then `make test` must
be fully green (see CLAUDE.md §Testing for the expected-red semantics).

## Items

### Pool-executable [HARD] — decided, needs per-item RED spec (route to handoff)

- [ ] [HARD] `/relay . --parallel N` — **[RE-FRAMED 2026-07-24, owner-directed: parallel fan-out is now pool `pipeline()` in the Workflow loop (id:1f4f), NOT the retired off-Workflow driver (id:93fe). Verifiable children id:5367/2062 stay substrate-agnostic; off-Workflow live-residue id:7fae is moot.]** -- detail: `docs/ledger-notes/ebbe.md` 🚧 @container <!-- id:ebbe -->
### 2026-07-21 promoted (consolidate handoff — mechanical-hop emitter wiring, id:176f child)

- [ ] [INPUT - meeting] **HIGH PRIORITY — pool-launch proxy coupling (id:6176 made 5 hops proxy-DEPENDENT).** -- detail: `docs/ledger-notes/6b35.md` <!-- children-of:176f --> <!-- id:6b35 -->

### Human-triage backlog — decided lane, TODO.md is SSOT (pointers for /relay human)

- [ ] [INPUT - meeting] Use VISIBLE annotations, not HTML comments, for metadata that should render — see TODO.md <!-- id:ee62 -->
- [ ] [INPUT - meeting] Mechanize the keystone-unblock triage as a `/relay human` view (gate-graph fan-out ranking) (us… — see TODO.md <!-- id:c3f6 -->
- [ ] [INPUT - decision] Derived-index pilot arm (`tracker/derived-index.py`, built + tested) awaits the `id:a08d` pre-registration amendment — see TODO.md <!-- gated-on:a08d --> <!-- id:dcf3 -->
- [ ] [INPUT - decision] ONE amendment covering ALL candidate tracker-pilot arms (derived index `id:dcf3` + Forgejo `id:016e`): PROPOSAL, owner ratification required — see TODO.md <!-- id:a08d -->
- [ ] [INPUT - meeting] Fake-Haiku mechanical-dispatch proxy — see TODO.md <!-- id:176f -->
- [ ] [INPUT - meeting] Meeting-as-relay-producer: route `/meeting` ledger writes through a worktree the integrator mer… — see TODO.md <!-- id:5a39 -->
- [ ] [INPUT - meeting] Full-loop relay REPLAY test — see TODO.md <!-- id:5bac -->
- [ ] [INPUT - meeting] Integrator destructive-cleanup ordering: under-the-lease vs release-first (proposed by the 2026… — see TODO.md <!-- id:6613 -->
- [ ] [INPUT - meeting] Human-action dashboard, mechanically refreshed by the relay loop, launchable WITHOUT LLM access… — see TODO.md <!-- id:51d8 -->
- [ ] [INPUT - meeting] chidiai⇄relay calibration cross-pollination (scoping) — see TODO.md <!-- id:2653 -->
- [ ] [INPUT - meeting] 5h session-limit overshoot: quota gate is round-boundary-only, an in-flight wave blows through… — see TODO.md <!-- id:68b1 -->
- [ ] [INPUT - meeting] Capability-keyed lane taxonomy + mechanical-run daemon (meeting 2026-07-02-1924, `docs/meeting-… — see TODO.md <!-- id:4299 -->
- [ ] [INPUT - meeting] A LIVE review child's worktree + branch were swept mid-run (2026-07-01 ~22:56) while the repo's… — see TODO.md <!-- id:6e02 -->
- [ ] [INPUT - meeting] Move relay DISCOVERY off LLM-judgment onto a mechanical TDD red/green flow — see TODO.md <!-- id:4d8e -->
- [ ] [INPUT - meeting] Broker-backed PARALLEL human-decision channel for the relay-loop (reuse meeting-rpg `broker.py`… — see TODO.md <!-- id:b444 -->
- [ ] [INPUT - meeting] Continuous (streaming) dispatch — see TODO.md <!-- id:80b8 -->
- [ ] [INPUT - meeting] Inter-session communication / coordination channel — see TODO.md <!-- id:9000 -->
- [ ] [INPUT - meeting] Encode "ROUTINE requires the test to gate the REAL goal" in the executor scope guard — see TODO.md <!-- id:33c2 -->
- [ ] [INPUT - meeting] Relay broker: stop spawning one agent per mechanical shell command (WALL-TIME driver) — see TODO.md <!-- id:3a1c -->
- [ ] [INPUT - meeting] Audit `/batch` for parallel-processing applications — see TODO.md <!-- id:7b23 -->
- [ ] [INPUT - meeting] `drained` machine-verdict + `@wire`/`@manual` grammar split (folds in executor-no-own-RED + spe… — see TODO.md <!-- id:af48 -->
- [ ] [INPUT - meeting] Visible-half-is-primary handoff discipline <!-- gate DISCHARGED 2026-08-20: was gated-on:ac7f, which is `- [x]` in ROADMAP.archive.md — the gate was satisfied, not dead; the lint only read it as DEAD because the archived item lost its live ROADMAP stub --> (meeting 2026-07-19-1058, fro… — see TODO.md <!-- id:2b49 -->
- [ ] [INPUT - meeting] Ledger-invariant enforcement substrate — see TODO.md <!-- id:7a05 -->
- [ ] [INPUT - meeting] Semver-bump enforcement + handoff bump-level annotation (meeting 2026-07-19-1212, user amendmen… — see TODO.md <!-- id:d1b2 -->
- [ ] [INPUT - meeting] ``/`[MEETING]` tag-taxonomy completion (user 2026-06-15) — see TODO.md <!-- id:d0da -->
- [ ] [INPUT - access] Runtime write-matrix + heartbeat round-trip test for the relay-ro/relay-svc ACLs (id:02c7) — see TODO.md <!-- id:e8a3 -->
- [ ] [INPUT - meeting] Write-scope the LLM tier by uid: separate OS users for the relay supervisor/reviewer vs. the ex… — see TODO.md <!-- id:d03d -->
- [ ] [INPUT - meeting] Custom agent types (`.claude/agents/*.md`) per relay subcommand — see TODO.md -- detail: `docs/ledger-notes/931c.md` <!-- id:931c -->
- [ ] [INPUT - meeting] Design tier-robust gate-discipline mechanisms (for a Fable session to consider): the 2026-07-02… — see TODO.md <!-- id:abe7 -->
- [ ] [INPUT - meeting] Upgrade `consumer-enum.sh` from content-grep to real import/read-edge resolution (relay human r… — see TODO.md <!-- id:494f -->
- [ ] [INPUT - meeting] A shared "reasoning-fallacy checkup" step for `/relay` and `/meeting` (user 2026-07-17: "add TO… — see TODO.md <!-- id:0e56 -->


- [ ] [INPUT - decision] Cold fixed-prompt probe: re-pose Opus-degradation incidents #2 (confident-wrong "zkm-* on another machine") and #3 (over-engineered ~/.claude branch-split) against fresh Opus; record pass/fail vs the recorded incident behaviour, finding written into `docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md`. Promoted 2026-07-13 (user) from TODO id:e3c0 (single-id-two-views — same id spans both ledgers). **Why HARD** -- detail: `docs/ledger-notes/e3c0.md` <!-- id:e3c0 --> 🚧
- [ ] [HARD] Strong-model audit: code review, security, and design coherence -- detail: `docs/ledger-notes/401c.md` <!-- id:401c --> <!-- relay:recurring-audit -->

- [ ] [INPUT - meeting] Sub-agent meeting simulation for main-ctx isolation -- detail: `docs/ledger-notes/113e.md` <!-- id:113e -->

### GATED — B2 migration (DEP: 4f02, NOT dispatchable until B1 lands)

- [ ] [INPUT - decision] B2c-finalizer — CLOSE the dual-vocab window: convert this-repo ledgers + migrate ~30 lane tests + flip old-vocab→lint ERROR 🚧 GATED (DEP: 3ef7 + cross-repo re-tag) — **human 2026-07-11 (relay human): keep OPEN, gate re-confirmed.** -- detail: `docs/ledger-notes/7df1.md` [INPUT — decision] <!-- gated-on:4f02 --> <!-- id:7df1 -->

## lane-anchor hotfix (relay handoff 2026-07-03)

## recipe explicit-success-marker doctrine (relay handoff 2026-07-03)

## case-c bare-only lane count (relay handoff 2026-07-03, owner-signed-off)

## mechanical-lane representability fix (relay HARD, user-injected id:baf1, 2026-07-10)

## Mechanical-tier + arg-guard findings (relay session 2026-07-28, run relay-20260728-104330-9348)

- [ ] [ROUTINE] **`write-relay-status`: haiku → `model:'bash'`** -- detail: `docs/ledger-notes/d4ca.md` 🚧 <!-- children-of:6b35 --> gated-on:33b2 gated-on:93ac <!-- gated-on:09e4 --> <!-- gated-on:b0b1 --> <!-- id:d4ca -->

## Executor-death cluster — promoted from TODO 2026-07-28 (parent meta id:93cc, open since 2026-06-22)

### 🔴🔴 ABSOLUTELY URGENT — owner directive 2026-08-01. Work these two FIRST, ahead of every other item in this file.

- [ ] [INPUT - decision] **Record the ACTUAL child death cause — relay child deaths are currently untracked** -- detail: `docs/ledger-notes/61fa.md` <!-- children-of:93cc --> <!-- id:61fa --> 🚧

- [ ] [INPUT - decision] **Executor dispatch DOUBLE-LOADS the executor contract — RESCOPED 2026-07-28 after an adversarial review refuted this item's own fix direction and its RED spec** -- detail: `docs/ledger-notes/9eb7.md` <!-- children-of:93cc --> <!-- relates:61fa --> <!-- id:9eb7 --> 🚧

- [ ] [HARD] **Convert the two remaining payload-trapped haiku hops once the stdin channel exists** -- detail: `docs/ledger-notes/e405.md` 🚧 <!-- children-of:6b35 --> gated-on:33b2 gated-on:93ac <!-- gated-on:09e4 --> <!-- gated-on:b0b1 --> <!-- relates:61fa --> <!-- id:e405 -->

## Fable is permanent — retire the availability probe (owner 2026-07-28)

- [ ] [INPUT - meeting] **Fable escalation chain — let an Opus agent say "I need Fable on this"** -- detail: `docs/ledger-notes/211d.md` <!-- children-of:698d --> <!-- id:211d -->
## Diagrams: enforce what is already drawn (2026-07-28)

- [ ] [INPUT - meeting] **Extend the state model to ROUND OUTCOMES (the id:4da4 matrix's missing axis)** -- detail: `docs/ledger-notes/5f31.md` 🚧 <!-- id:5f31 -->

- [ ] [INPUT - meeting] **A safety classifier blocked a MECHANICAL teardown by reading conversational context** (promoted from TODO `routed:643f`, loderite 2026-07-28) -- detail: `docs/ledger-notes/51f0.md` <!-- id:51f0 -->

## mechanical-hop proxy coupling — fail-closed launch posture (meeting 2026-07-29, parents id:6b35 + id:51f0)

- [ ] [ROUTINE] **`mech-preflight.sh`: mode-a AND mode-b become launch REFUSALS; the `abort` token actually aborts** -- detail: `docs/ledger-notes/540f.md` 🚧 <!-- gated-on:b0b1 --> <!-- e62c half DISCHARGED 2026-08-20: e62c is `- [x]` in ROADMAP.archive.md; STILL BLOCKED on b0b1, which lives only in TODO.md and was never promoted --> <!-- children-of:6b35 --> <!-- id:540f -->

- [ ] [ROUTINE] **`relay-loop.js`: self-attesting first mechanical hop; delete the fallback ternary** -- detail: `docs/ledger-notes/c179.md` 🚧 <!-- gated-on:b0b1 --> <!-- e62c half DISCHARGED 2026-08-20: e62c is `- [x]` in ROADMAP.archive.md; STILL BLOCKED on b0b1, which lives only in TODO.md and was never promoted --> <!-- children-of:6b35 --> <!-- relates:540f --> <!-- id:c179 -->

- [ ] [ROUTINE] **(F5) A fail-closed refusal is INVISIBLE to the id:98f0 watchdog** -- detail: `docs/ledger-notes/554b.md` 🚧 <!-- gated-on:540f --> <!-- relates:540f --> <!-- id:554b -->

## In-repo parallelism wave model (id:1f4f children) + round-verdict observability — promoted from TODO 2026-07-30 (handoff C2/C3)

- [ ] [INPUT - decision] **Wire the built-but-unreferenced fan-out machinery (`disjoint-greenlight.sh` + `drain-integrate.sh`) into `relay-loop.js`** -- detail: `docs/ledger-notes/ae08.md` @container <!-- children-of:1f4f --> <!-- id:ae08 --> 🚧

## 2026-07-31 handoff C2 — execute→review cadence starvation (+ two watermark/registry defects)

- [ ] [INPUT - decision] **Extract `isDryRound`/`workCreated` into ONE shared definition — CROSS-FILE, via a generation step; record the drain-path gap MOOT-BY-RETIREMENT** -- detail: `docs/ledger-notes/6217.md` <!-- id:6217 --> 🚧

## Human triage 2026-08-01 (relay human `.`, owner-decided)

- [ ] [INPUT - decision] **`--fabled` (B): fire the Fable adversarial pass BEFORE each `AskUserQuestion`, not only at the closing pass** -- detail: `docs/ledger-notes/8df5.md` <!-- children-of:7e87 --> <!-- routed:43a8 --> <!-- routed:690b --> <!-- routed:4702 --> <!-- id:8df5 --> 🚧

## Handoff C2 2026-08-01 (relay handoff, owner-scoped 5-item promotion)

- [ ] [INPUT - meeting] **@container — relay children can write the target's MAIN checkout; "Work EXCLUSIVELY in that worktree" is prose with zero enforcement** -- detail: `docs/ledger-notes/f91a.md` <!-- children:d464,34b7 --> <!-- routed:f91a --> <!-- id:f91a -->


## Provision fail-open cluster 2026-08-11 (inbox `routed:8d64` + `routed:d9a5`; parent `id:f91a`, post-`id:34b7`)

- [ ] **[INPUT — decision]** Wire disjoint-greenlight.sh plan into the drain-mode fan-out planner — seam of id:ae08 (auto, id:3801) -- detail: `docs/ledger-notes/02b2.md` <!-- relates:99e5 --> <!-- id:02b2 --> — 🚧 GATED (auto, id:3801; route:decision-gate): Needs /meeting: per-unit file-set provenance + which same-repo units are concurrency-eligible under the review-barrier — else the greenlight call is a forbidden dead branch. — needs a /meeting
- [ ] **[INPUT — decision]** Route same-repo drain-mode integration through drain-integrate.sh (serialized one-writer safety net) (after id:<seam-1 id>) — seam of id:ae08 (auto, id:3801) -- detail: `docs/ledger-notes/99e5.md` <!-- id:99e5 --> — 🚧 GATED (auto, id:3801; route:decision-gate): Wiring drain-integrate.sh into relay-loop.js's shared integrate() path depends on seam-1 id:02b2 (decision-gated /meeting on drain-mode fan-out planner + review-barrier concurrency); acceptance invariant D3a undefinable until then, and done-check tests already pass so there is no RED guard for the guard-less core-loop change. — needs a /meeting
## Review-derived promotion 2026-08-14 (relay review, reverse-handoff §5b)

- [ ] [ROUTINE] **Parked-section vocab match is a bare substring — a heading that merely mentions `archive`/`done`/`gated`/etc. in descriptive prose parks its whole section** -- detail: `docs/ledger-notes/6446.md` 🚧 `@owner-gated` <!-- gated-on:f391 --> <!-- id:6446 -->


## Test-harness throughput 2026-08-14 (/relay human, owner-directed)

## meeting-question-guard was a live no-op — flush-wait fix + live confirmation (2026-08-19, `id:2419` second round)

- [ ] [ROUTINE] **`@owner-verify` — confirm the `meeting-question-guard` flush-wait actually fires in the LIVE harness** -- detail: `docs/ledger-notes/cf2d.md` <!-- id:cf2d -->

## Human triage 2026-08-19 (`/relay human .`, owner-decided)

## Parallel-suite flakiness — OBSERVE-FIRST (promoted from TODO 2026-08-21, `id:7518`)

- [ ] [INPUT - decision] **General parallel-suite flakiness — four unrelated tests have flaked in-suite and passed standalone; build the per-run failure logger before any fix** -- detail: `docs/ledger-notes/7518.md` <!-- id:7518 --> @container 🚧

## Integrator ledger staging + stale slicer wording (2026-08-21)

- [ ] **[INPUT — decision]** Gather post-id:81d5-fix flake-log confirmation runs at j1 and an over-subscribed width (e.g. j24/j32), ≥2 runs each — seam of id:7518 (auto, id:3801) -- detail: `docs/ledger-notes/372a.md` <!-- id:372a --> — @container 🚧 GATED (auto, id:3801; route:hard-split): DECOMPOSED into seams id:97e0, id:f2ef, id:b1ef, id:c3be, id:6ab7 — pick those, not this. Each of 4 required flake-log runs (2× width=1, 2× width≥16) takes multiple minutes wall-clock; doesn't fit one executor turn as a single unit.
- [ ] **[HARD]** Reviewer: fold the three-width post-fix data into ROADMAP.md id:7518, rank surviving hypotheses with confirm/kill criteria each (Acceptance clause 4), and decide closure per clause 6/7 (after id:(depends on the data-gathering seam above)) — seam of id:7518 (auto, id:3801) -- detail: `docs/ledger-notes/166a.md` <!-- id:166a -->
- [ ] **[INPUT — decision]** flake-log width=1 confirmation run #1 (post-id:81d5) — seam of id:372a (auto, id:3801) -- detail: `docs/ledger-notes/97e0.md` <!-- id:97e0 --> — 🚧 GATED (auto, id:3801; route:human): flake-log -j1 (sequential full suite) exceeds one executor turn's wall-clock budget under current host load (~10-16 loadavg); needs a longer-lived/background run or a lower-load window, not a code change. — needs /relay human
- [ ] **[INPUT — decision]** Summarize the 4 post-id:81d5 flake-log confirmation rows in RELAY_LOG.md (after id:all 4 run seams above) — seam of id:372a (auto, id:3801) -- detail: `docs/ledger-notes/6ab7.md` <!-- id:6ab7 --> — 🚧 GATED (auto, id:3801; route:human): only 3/4 required flake-log confirmation rows exist — 4th seam id:97e0 still gated on /relay human (width=1 run exceeds one turn's wall-clock budget) — needs /relay human

## Em-dash delimiter migration (owner-ratified, `docs/migration-em-dash-delimiter.md`) — S0..S10

- [x] [HARD] Em-dash delimiter migration S1 — flip `relay/references/hard-lanes.md` to hyphen delimiters, change all six scrape regexes (across `lane-convert.sh`, `roadmap-lint.sh`, `pre-commit-lane-vocab.sh`) to an explicit two-delimiter alternation, and DELETE all six hardcoded vocabulary fallbacks in favour of a loud non-zero exit; MUST land as one atomic commit (a split window makes the SSOT read new while readers silently enforce old). -- detail: `docs/ledger-notes/71d6.md` <!-- gated-on:70bc --> <!-- id:71d6 -->
- [x] [HARD] Em-dash delimiter migration S2 — fix `gather-repo-state.sh`'s backwards lane-vocabulary map (`:337-351`) and its three `[INTENSIVE — ]` hardcodes (`:361/364/378`) to canonicalize on the hyphen spelling while accepting both delimiters on input; author the new RED spec pinning the canonical spelling (`tests/test_gather_lane_canonical_delimiter.sh` does not exist yet — writing it is part of this seam, and its RED evidence must be captured before the fix). -- detail: `docs/ledger-notes/098a.md` <!-- gated-on:71d6 --> <!-- id:098a -->
- [x] [HARD] Em-dash delimiter migration S5 — convert the non-bash relay consumers (`relay-loop.js`, `drain.mjs`, `handback-guard.mjs`, `handback-followup.py`, `backtest-historical.py`) to the two-delimiter alternation; kept as a SEPARATE seam because a `relay-loop.js` template-string edit is the `loop-crash-class` runtime hazard that `node --check` + grep cannot catch — verify with the exec-smoke guard (id:5bac/aec5). -- detail: `docs/ledger-notes/1a03.md` <!-- gated-on:2ee5 --> <!-- id:1a03 -->
- [x] [HARD] Em-dash delimiter migration S7 — flip the 26 NORMATIVE contract/doc markdown files (`relay/references/*.md`, `relay/SKILL.md`, `ARCHITECTURE.md`, `docs/diagrams/*.mmd`, `tracker/SCHEMA.md`, `hooks/lane-vocab.claude-rule.md`) to hyphen spelling while leaving every HISTORICAL doc (`docs/HANDOVER-*.md`, `docs/meeting-notes/**`, `CHANGELOG.md`, `*.archive.md` prose) byte-identical — distinguishing normative from historical is a judgment call per file, not a mechanical sweep, and rewriting a historical doc destroys the audit trail hazard 7 protects. -- detail: `docs/ledger-notes/55c7.md` <!-- gated-on:2ee5 --> <!-- id:55c7 -->
- [x] [ROUTINE] Em-dash delimiter migration S8 — purely mechanical rewrite of the delimiter inside the 86 test-fixture files' heredocs and assertion strings, batched by prefix (`test_classify_*`, `test_gather_*`/`test_relay_*`, the rest, plus `tests/shard-canary/**` and `tracker/fixtures/**`); after EACH batch `tests/run-tests.sh` must read 519 passed / 0 failed / 1 expected-red plus the seam's own new specs — never open all 86 files in one turn. -- detail: `docs/ledger-notes/ee31.md` <!-- gated-on:e8d4 --> <!-- gated-on:1a03 --> <!-- gated-on:d0aa --> <!-- gated-on:55c7 --> <!-- id:ee31 -->
- [ ] [HARD] Em-dash delimiter migration S9 — rewrite this repo's own LIVE lane tags in `TODO.md`/`ROADMAP.md`/`REVIEW_ME.md` and their `.archive.md` siblings to hyphen delimiters, through `meeting/md-merge.py` / `relay/scripts/commit-ledger.sh` only (never `Edit`/`sed -i` — these are shared non-union ledgers); per dc5b C2, this seam never runs concurrently with any other dotclaude-skills unit (one unit per repo per round). <!-- gated-on:ee31 --> — **MEASURED 2026-08-31** -- detail: `docs/ledger-notes/6958.md` [HARD - pool] [HARD] <!-- id:6958 -->
- [x] [INPUT - decision] **S9 archive conflict: the delimiter migration and the vocabulary ratchet cannot both be satisfied on `*.archive.md` without a ruling.** MEASURED 2026-08-31: migrating the 85 live lane tags in `ROADMAP.archive.md` (47) + `TODO.archive.md` (38) makes them ADDED lines carrying venue-keyed old vocabulary (`[HARD - pool]` x39, `[HARD - hands]` x6, `[HARD - decision gate]` x4), so `hooks/pre-commit-lane-vocab.sh` blocks both files (exit 1, verified with `LANE_VOCAB_ALL_REPOS=1`). ALL 85 are closed `- [x]` entries; zero are open. Three ways out, none takeable without you: (a) ** -- detail: `docs/ledger-notes/2065.md` <!-- gated-on:6958 --> <!-- id:2065 -->
- [ ] [INPUT - meeting] Em-dash delimiter migration S10 (seam B) — drop the dual-vocab tolerance fleet-wide: delete the em-dash arm of every alternation and turn a live old-delimiter/old-vocabulary lane tag into a LOUD (nonzero) error in `roadmap-lint.sh`, `gather-human-backlog.sh` and the ratchet; MUST NOT be bundled with anything else. -- detail: `docs/ledger-notes/da55.md` <!-- gated-on:6958 --> <!-- id:da55 -->

## 2026-09-02 shrink-programme gaps (handoff C2, run relay-handoff-019adc92)

- [ ] [INPUT - decision] **Section preamble prose has no home in the three-shape grammar; 154 ROADMAP lines are refused with nowhere to go.** -- detail: `docs/ledger-notes/800f.md` <!-- relates:2d17 --> <!-- id:800f -->
- [ ] [INPUT - decision] **The archive stub is written AFTER the id marker, which the grammar forbids; 2 writers and 7 tests pin it.** -- detail: `docs/ledger-notes/d05d.md` <!-- relates:2d17 --> <!-- id:d05d -->
- [ ] [INPUT - decision] **Move ROADMAP.md continuation lines into per-id notes -- under the ratified line grammar they are not large blocks to budget, they are INVALID.** -- detail: `docs/ledger-notes/40c0.md` <!-- gated-on:b048 --> <!-- relates:2d17 --> <!-- id:40c0 --> — 🚧 GATED (auto, id:3801; route:decision-gate): Acceptance requires a fleet-wide (46-repo) recoverable-fraction measurement under undefined "options" plus id:03a3 citing it -- id:03a3 itself is gated on unresolved shrink-programme items (id:5f34/1608/4983) and this repo's worktree cannot touch other repos' ledgers; needs a /meeting decision on what "each option" even means before any executor can act. — needs a /meeting
- [ ] [INPUT - decision] **Make the ratification gate BIND: move it from the unit to the REMOTE, and make the queue self-verifying (option A+D, owner-ratified 2026-09-02).** -- detail: `docs/ledger-notes/3c04.md` -- detail: `docs/ledger-notes/7408.md` <!-- children-of:3c04 --> <!-- relates:2d17 --> `@container` <!-- id:7408 --> — 🚧 GATED (auto, id:3801; route:hard-split): DECOMPOSED into seams id:4d65, id:5ad9 — pick those, not this. Multi-file safety-critical release-gate change (integrate.sh + ratify-queue.sh) with 4 hermetic tests and a historical-run replay done-check; too large for one executor session, no committable sub-seam found.
- [ ] [INPUT - decision] **257 ledger items have a TITLE that is itself over budget -- no relocation can shorten a title, so these need rewriting.** -- detail: `docs/ledger-notes/64f9.md` -- REOPENED 2026-09-08, see note. <!-- gated-on:ff7c,2654 --> <!-- relates:2d17 --> <!-- id:64f9 --> — 🚧 GATED (auto, id:3801; route:hard-split): DECOMPOSED into seams id:521b, id:b437 — pick those, not this. 42-item judgment-heavy batch + missing enforcement gate + id:963c unconditional-tick hazard makes safe partial progress un-reportable this session.
- [ ] [INPUT - decision] **`shape-prose` becomes an ERROR -- the closing act of the no-prose bar.** -- detail: `docs/ledger-notes/8524.md` <!-- gated-on:1608,2d17 --> <!-- relates:2d17 --> <!-- id:8524 --> — 🚧 GATED (auto, id:3801; route:decision-gate): Acceptance needs 0 remaining shape-prose findings but 216 (TODO.md) + 31 (ROADMAP.md) remain; recorded gates 1608/2d17 are closed yet don't track this real precondition -- needs an owner call on how to gate/schedule the remaining shrink work. — needs a /meeting
- [ ] [INPUT - decision] **Three items carry a de-facto lane derived from BODY PROSE, which `classify-repo` reads as their real lane.** -- detail: `docs/ledger-notes/1254.md` <!-- relates:2d17 --> <!-- id:1254 -->
- [ ] [INPUT - decision] **Both ledger ratchets are INERT on the install path, their baseline key has no repo dimension, and their length metric is locale-dependent -- fix all three or none.** -- detail: `docs/ledger-notes/4839.md` <!-- relates:0d7c --> <!-- id:4839 --> — 🚧 GATED (auto, id:3801; route:hard-split): @container DECOMPOSED into seams id:eccb, id:c655, id:aa5e, id:cb9a — pick those, not this. id:4839 spans 3 ordering-constrained dimensions + 2 aggravations + 4 hermetic tests in one heavily-invariant script; too large for one session, split into 4 ordered seams
## 2026-09-04 handoff C2 -- ledger-tooling and test-harness defects from the 09-04 design day (run relay-20260904-145432-15472)

- [ ] [INPUT - decision] **`ledger-shrink.py` hoists an EXAMPLE marker quoted in prose as if it were real -- 30 lines, and it defeated the shrink on `ee62`.** -- detail: `docs/ledger-notes/8372.md` <!-- relates:14e5 --> <!-- id:8372 --> — 🚧 GATED (auto, id:3801; route:decision-gate): Needs an owner/meeting ruling on the positional (or other) discriminator for a backticked @-family marker quoted mid-prose vs the item's own trailing marker run -- the 2026-09-07 review explicitly recorded this as a design call it did not settle (docs/ledger-notes/8372.md), and both obvious heuristics (comma/lowercase-follows; sentence-boundary-follows) are disproved by existing passing tests or by the real ee62/case-B shapes traced this session. — needs a /meeting
## 2026-09-05 handoff C2 -- `md-merge.py update-ids` silent no-op + wrapped-item reach (user-injected `id:baf1`, run relay-20260905-083048-18379)

- [ ] **[ROUTINE]** integrate.sh step 8: bind the declared-public remote push to the whole repo's ratification queue, not the current unit (Acceptance A) (after id:(seam 1 above)) — seam of id:7408 (auto, id:3801) <!-- id:5ad9 -->
  - **Acceptance**: Before pushing a declared-public remote for a repo, integrate.sh's step 8 queries the ratification queue for that repo (using seam 1's self-verifying read) for any entry whose recorded merge sha is an ancestor of current HEAD and is still genuinely unresolved (not remote-confirmed-landed). If one exists, that declared-public remote's push is withheld for THIS run regardless of whether the current unit is itself substantive or non-substantive -- closing the exact regression named in the item's Context (a non-substantive unit currently republishes everything behind it). Private/LAN remotes are unaffected. The withholding is written loudly to RELAY_STATUS.md and the turn/integrate summary, not only visible via `ratify-queue.sh list`.
  - **Done-check**: new tests/test_integrate_remote_gate_binds.sh: hermetic repo + fake ratification-queue entry ancestral to HEAD -> run integrate.sh through a NON-substantive unit -> assert the declared-public remote is NOT pushed while the private/LAN remote IS pushed, and RELAY_STATUS.md/summary records the withholding; once the entry resolves (or self-verifies landed per seam 1), assert the next integrate proceeds to push. Then replay the shape of run relay-20260902-164744-26939 (four substantive units deferred, one non-substantive) and confirm the public remote does not advance. Full make test green.
  - **Context**: relay/scripts/integrate.sh (step 8/8b region, ~lines 939-1405), relay/scripts/ratify-queue.sh (read-only query reused from seam 1), RELAY_STATUS.md writer
- [ ] **[ROUTINE]** Add a repo dimension to the head-length and shape-prose baseline keys — seam of id:4839 (auto, id:3801) <!-- id:c655 -->
  - **Acceptance**: LENGTH_BASELINE_MAP and SHAPE_BASELINE_MAP keys include the owning repo, so a row minted in one repo can never supply a ceiling for another repo's item sharing the same 4-hex id (verified in both directions: an over-ceiling row must not read as regrowth, an under-ceiling row must not read as grandfathered, for a foreign repo). A lookup that finds no row for the invoking repo behaves as not-baselined (the existing loud -new/-over-budget classes), never silently borrowing another repo's row. Legacy two-column-key rows are refused loudly or migrated by an explicit, separately-tested act.
  - **Done-check**: tests/test_conformance_baseline_repo_key_4839.sh green (two fixture repos sharing a 4-hex token with different lengths; neither repo's baseline supplies a ceiling for the other, both directions, reproducing the id:55c7 shape from the ledger note); make test green.
  - **Context**: relay/scripts/todo-conformance.sh (length_baseline_load, shape_baseline_load, LENGTH_LEDGER_KEY, the two BASELINE_MAP key builders), relay/head-length-baseline.txt, relay/shape-prose-baseline.txt (row format gains a repo column)
- [ ] **[ROUTINE]** Install the head-length and shape-prose baselines via the Makefile, gated on the repo-keyed baseline format landing first (after id:<the repo-dimension seam's id — seam 2 above>) — seam of id:4839 (auto, id:3801) <!-- id:aa5e -->
  - **Acceptance**: relay_FILES in the Makefile ships relay/head-length-baseline.txt and relay/shape-prose-baseline.txt; `bash ~/.claude/skills/relay/scripts/todo-conformance.sh TODO.md` (install path) prints neither INERT warning and agrees, finding-for-finding, with the repo-path invocation on this repo's TODO.md and ROADMAP.md. This seam must not be started before the repo-dimension seam has landed — shipping baseline installation without repo-keying converts an announced-inert failure into an unannounced-wrong one on every other repo.
  - **Done-check**: tests/test_conformance_baseline_installed_4839.sh green (`make DEST_DIR=<mktemp -d> install-relay`; assert both baseline files present in the install tree and the installed script prints neither INERT warning); make test green.
  - **Context**: Makefile (relay_FILES)
- [ ] [ROUTINE] **`workflow_node_check`'s lexical scan goes blind over 1,251 of relay-loop.js's 4,930 lines: a `//` comment holding a glob like `relay/orphan/*` opens a never-closing block-comment state.** -- detail: `docs/ledger-notes/8627.md` <!-- relates:e044 --> <!-- id:8627 -->
- [ ] [ROUTINE] **id:1b0e's two mechanisms are BOTH unpinned: the hardening spec still passes with either the readability guard or the awk/sed status captures removed (mutation-tested).** -- detail: `docs/ledger-notes/0165.md` <!-- relates:1b0e --> <!-- id:0165 -->

## 2026-09-08 review findings (run relay-20260908-231617-32609)

- [ ] [ROUTINE] **`roadmap-tick.sh` ticks every `worked_ids` id unconditionally, so an executor reporting PARTIAL progress has its item closed and archived.** -- detail: `docs/ledger-notes/963c.md` <!-- relates:5b12 --> <!-- relates:64f9 --> <!-- id:963c -->
  - **Acceptance**: after the integrator ticks a set of `worked_ids`, a tick that turns a `# roadmap:<id>`-headed test file from EXPECTED-RED into a REAL failure is REFUSED or LOUDLY reverted, naming the id and the test file -- an item may not be recorded closed while its own spec test is red. The guard is mechanical (it re-uses `tests/run-tests.sh`'s existing expected-red semantics, which already know the mapping) and never depends on the child self-reporting honestly. A tick whose spec test is green, or which has no `# roadmap:` test at all, behaves byte-identically to today; archiving is unaffected except that it can no longer sweep away an item the guard refused.
  - **Done-check**: `tests/run-tests.sh tests/test_tick_refuses_red_spec_963c.sh` green -- hermetic fixture repo with one open `[ROUTINE]` item, one `# roadmap:<id>` test that FAILS, and one that passes; assert ticking the failing item is refused/reverted and LOUD, ticking the passing item succeeds, and an id with no spec test is unaffected. Replay the shape of this incident (`id:64f9` at `35e8983c`) and confirm the guard fires. Then full `make test` green.
  - **Context**: `relay/scripts/roadmap-tick.sh` (the tick pass and its post-write assertion), `relay/scripts/integrate.sh` (~lines 803-825, the `EX_TICK` handback path already exists and is the natural place to fail), `tests/run-tests.sh` (the `# roadmap:` / expected-red mapping this re-uses -- read it, do not reimplement it).
- [ ] **[ROUTINE]** Implement the batch-acceptance invariance checks in tools/shrink-acceptance.py that the id:64f9 RED spec already demands (verbatim title preservation in notes, checkbox/lane/gated-on-edge invariance, dropped-prose refusal) — seam of id:64f9 (auto, id:3801) <!-- id:521b -->
  - **Acceptance**: tests/test_title_rewrite_batch_acceptance_64f9.sh cases (2) through (7) all PASS (currently case 2 fails: a batch that drops original title prose is wrongly accepted)
  - **Done-check**: bash tests/test_title_rewrite_batch_acceptance_64f9.sh prints ALL PASS; make test still fully green (610 passed / 0 failed / 5 expected-red)
  - **Context**: tools/shrink-acceptance.py, tests/test_title_rewrite_batch_acceptance_64f9.sh
- [ ] **[ROUTINE]** Rewrite the first ~10 over-budget TODO.md titles (of 42) with full original preserved verbatim in docs/ledger-notes/<id>.md, verified against the new shrink-acceptance.py gate (after id:(the gate seam above)) — seam of id:64f9 (auto, id:3801) <!-- id:b437 -->
  - **Acceptance**: todo-conformance.sh grammar-item-title-long count for TODO.md drops by the number of items rewritten; each item's id, lane, checkbox state and every marker (gated-on:, relates:, routed:) is byte-identical; shrink-acceptance.py run over before/after accepts the batch
  - **Done-check**: relay/scripts/todo-conformance.sh TODO.md | grep -c grammar-item-title-long shows the reduced count; python3 tools/shrink-acceptance.py --before <snapshot> --after TODO.md --notes-dir docs/ledger-notes exits 0
  - **Context**: TODO.md, docs/ledger-notes/<id>.md for each rewritten item
