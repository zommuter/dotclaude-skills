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

### Pool-executable [HARD] — decided, needs per-item RED spec (route to handoff)

- [ ] [HARD] `/relay . --parallel N` — **[RE-FRAMED 2026-07-24, owner-directed: parallel fan-out is now pool `pipeline()` in the Workflow loop (id:1f4f), NOT the retired off-Workflow driver (id:93fe). Verifiable children id:5367/2062 stay substrate-agnostic; off-Workflow live-residue id:7fae is moot.]** -- detail: `docs/ledger-notes/ebbe.md` 🚧 @container <!-- id:ebbe -->
### 2026-07-21 promoted (consolidate handoff — mechanical-hop emitter wiring, id:176f child)

- [ ] [INPUT - meeting] **HIGH PRIORITY — pool-launch proxy coupling (id:6176 made 5 hops proxy-DEPENDENT).** -- detail: `docs/ledger-notes/6b35.md` <!-- children-of:176f --> <!-- id:6b35 -->
  - **DECIDED 2026-07-29** (meeting `docs/meeting-notes/2026-07-29-0911-mechanical-hop-proxy-coupling.md`, D1/D2 + amendments D1-A/D2-A, owner-ratified). Posture is **fail-closed**: `mech-preflight.sh` mode-a AND mode-b become launch refusals (the `abort` token starts aborting), and `MECH_MODEL` stops being a fallback selector — the `MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'` ternary at `:248` is deleted. Second enforcement layer is a **self-attesting first mechanical hop** (fenced `true` as `model:'bash'`), NOT a token assertion — `A.MECH_FALLBACK || ''` makes a front-door-skipping caller indistinguishable from healthy. Cap: exactly two layers. Children: **id:540f** (preflight refusal), **id:c179** (self-attesting hop + ternary deletion), **id:c480** (this item's own scope table is STALE — it lists `release:` as MUST-STAY-`model:'haiku'` while id:f7d3 converted it to `model:'bash'` at `:2316`; fix before implementing or the table will mislead). **Rationale correction (UPDATED 2026-08-11 by id:e62c's branch-(1) verdict):** the surviving drivers are **cost** + the hardcoded-no-fallback `discover-prelude`/`discover-run` hops (`:1114`/`:1279`) — NOT the quota gate, which already fails closed (`:1956`), and **NOT classifier exposure**. id:e62c CONFIRMED **branch (1)**: the safety classifier sits at the `agent()` DISPATCH layer, upstream of where `mechanical-proxy.py` intercepts at the HTTP layer, so proxying a hop confers **NO** classifier protection and cannot justify the fail-closed posture. **F2 is now RESOLVED (id:e62c CLOSED)** — the earlier "whether proxying confers classifier protection at all is UNRESOLVED" is superseded. The fail-closed refusal (id:540f/c179) therefore stands on its OTHER, independent grounds only (cost + the hardcoded-no-fallback discover hops), and whether to BUILD it remains the **owner's call** via its `gated-on:b0b1` owner gate.
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
- [x] [ROUTINE] Review→execute chaining within a pool — **emit a `review→execute re-enqueue` EVENT into `relay-events.jsonl`** -- detail: `docs/ledger-notes/b8ae.md` <!-- id:b8ae --> (archived — see ROADMAP.archive.md)
- [ ] [INPUT - meeting] ``/`[MEETING]` tag-taxonomy completion (user 2026-06-15) — see TODO.md <!-- id:d0da -->
- [ ] [INPUT - access] Runtime write-matrix + heartbeat round-trip test for the relay-ro/relay-svc ACLs (id:02c7) — see TODO.md <!-- id:e8a3 -->
- [ ] [INPUT - meeting] Write-scope the LLM tier by uid: separate OS users for the relay supervisor/reviewer vs. the ex… — see TODO.md <!-- id:d03d -->
- [ ] [INPUT - meeting] Custom agent types (`.claude/agents/*.md`) per relay subcommand — see TODO.md <!-- id:931c --> **[2026-07-21 — evaluate UNDER the id:cae2 Agent-SDK audit (candidate #2), not piecemeal. Scope narrowed to the JUDGMENT roles (executor/reviewer/handoff/discover-shard); the mechanical variant id:f599 is SUPERSEDED by the model:"bash" proxy (id:6176/176f). Primary value = RELIABILITY (bake "load+follow the versioned contract" into the subagent prompt so it is not a forgettable per-dispatch step), not token cost. TWO DESIGN KEYS: (1) POINT don't DUPLICATE — the subagent prompt READs `relay/references/executor-contract.md` (vN) at runtime, never copies it (else derived-doc drift vs the ratified SOP); (2) USER-LEVEL install (`~/.claude/agents/` + `make install` symlink), never project-level, because relay runs the whole relay.toml set. `tools:` frontmatter scoping is ergonomic, NOT a security boundary (deny-probe-5937 — the OS-user tier is the real containment).]**
- [ ] [INPUT - meeting] Design tier-robust gate-discipline mechanisms (for a Fable session to consider): the 2026-07-02… — see TODO.md <!-- id:abe7 -->
- [ ] [INPUT - meeting] Upgrade `consumer-enum.sh` from content-grep to real import/read-edge resolution (relay human r… — see TODO.md <!-- id:494f -->
- [ ] [INPUT - meeting] A shared "reasoning-fallacy checkup" step for `/relay` and `/meeting` (user 2026-07-17: "add TO… — see TODO.md <!-- id:0e56 -->


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

- [ ] [INPUT - decision] Cold fixed-prompt probe: re-pose Opus-degradation incidents #2 (confident-wrong "zkm-* on another machine") and #3 (over-engineered ~/.claude branch-split) against fresh Opus; record pass/fail vs the recorded incident behaviour, finding written into `docs/meeting-notes/2026-06-17-0836-opus-degradation-investigation.md`. Promoted 2026-07-13 (user) from TODO id:e3c0 (single-id-two-views — same id spans both ledgers). **Why HARD** -- detail: `docs/ledger-notes/e3c0.md` <!-- id:e3c0 --> 🚧
- [ ] [HARD] Strong-model audit: code review, security, and design coherence -- detail: `docs/ledger-notes/401c.md` <!-- id:401c --> <!-- relay:recurring-audit -->

- [ ] [INPUT - meeting] Sub-agent meeting simulation for main-ctx isolation -- detail: `docs/ledger-notes/113e.md` <!-- id:113e -->

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

- [ ] [INPUT - decision] B2c-finalizer — CLOSE the dual-vocab window: convert this-repo ledgers + migrate ~30 lane tests + flip old-vocab→lint ERROR 🚧 GATED (DEP: 3ef7 + cross-repo re-tag) — **human 2026-07-11 (relay human): keep OPEN, gate re-confirmed.** -- detail: `docs/ledger-notes/7df1.md` [INPUT — decision] <!-- id:7df1 -->

## lane-anchor hotfix (relay handoff 2026-07-03)

## recipe explicit-success-marker doctrine (relay handoff 2026-07-03)

## case-c bare-only lane count (relay handoff 2026-07-03, owner-signed-off)

## mechanical-lane representability fix (relay HARD, user-injected id:baf1, 2026-07-10)

## Relay orphan-worktree reconcile (meeting 2026-06-16-0938, id:a4e9)

Decomposition of the orphan-reconcile design. **Sequence: D1 → D2/D3** (D2's reconcile
mode and D3's binding both operate on the `relay/orphan/*` namespace D1 creates). D4
(id:a692, note-only forward-flag) and D6 (id:122f, fsck ADVISORY follow-on, gated "ships
after D1–D3") stay in TODO.md — not executor work yet.

- [x] [INPUT - access] **Build the ebd0 privacy pre-push gate** -- detail: `docs/ledger-notes/ebd0.md` <!-- id:ebd0 --> (archived — see ROADMAP.archive.md)
## Mechanical-tier + arg-guard findings (relay session 2026-07-28, run relay-20260728-104330-9348)

- [ ] [ROUTINE] **`write-relay-status`: haiku → `model:'bash'`** -- detail: `docs/ledger-notes/d4ca.md` 🚧 <!-- children-of:6b35 --> gated-on:33b2 gated-on:93ac <!-- gated-on:09e4 --> <!-- gated-on:b0b1 --> <!-- id:d4ca -->

## Executor-death cluster — promoted from TODO 2026-07-28 (parent meta id:93cc, open since 2026-06-22)

### 🔴🔴 ABSOLUTELY URGENT — owner directive 2026-08-01. Work these two FIRST, ahead of every other item in this file.

> **Why, in one line:** the parent `id:93cc` recurred live on 2026-08-01 (run
> `relay-20260801-213927-29875`) and killed this repo's own `execute` child with
> `Prompt is too long`, parking 481 lines of unverified work as
> `relay/orphan/relay-20260801-213927-29875-execute`. Until these land, **every `execute`
> dispatch on `dotclaude-skills` is at risk of the same death** — the repo with the largest
> ROADMAP and the most `[ROUTINE]` items blocks its own executors first.

- [ ] [INPUT - decision] **Record the ACTUAL child death cause — relay child deaths are currently untracked** -- detail: `docs/ledger-notes/61fa.md` <!-- children-of:93cc --> <!-- id:61fa --> 🚧

- [ ] [INPUT - decision] **Executor dispatch DOUBLE-LOADS the executor contract — RESCOPED 2026-07-28 after an adversarial review refuted this item's own fix direction and its RED spec** -- detail: `docs/ledger-notes/9eb7.md` <!-- children-of:93cc --> <!-- id:9eb7 --> 🚧

- [ ] [HARD] **Convert the two remaining payload-trapped haiku hops once the stdin channel exists** -- detail: `docs/ledger-notes/e405.md` 🚧 <!-- children-of:6b35 --> gated-on:33b2 gated-on:93ac <!-- gated-on:09e4 --> <!-- gated-on:b0b1 --> <!-- id:e405 -->

## Fable is permanent — retire the availability probe (owner 2026-07-28)

- [ ] [INPUT - meeting] **Fable escalation chain — let an Opus agent say "I need Fable on this"** -- detail: `docs/ledger-notes/211d.md` <!-- children-of:698d --> <!-- id:211d -->
## Diagrams: enforce what is already drawn (2026-07-28)

- [ ] [INPUT - meeting] **Extend the state model to ROUND OUTCOMES (the id:4da4 matrix's missing axis)** -- detail: `docs/ledger-notes/5f31.md` 🚧 <!-- id:5f31 -->

- [ ] [INPUT - meeting] **A safety classifier blocked a MECHANICAL teardown by reading conversational context** (promoted from TODO `routed:643f`, loderite 2026-07-28) -- detail: `docs/ledger-notes/51f0.md` <!-- id:51f0 -->

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

- [ ] [ROUTINE] **`mech-preflight.sh`: mode-a AND mode-b become launch REFUSALS; the `abort` token actually aborts** -- detail: `docs/ledger-notes/540f.md` 🚧 <!-- gated-on:b0b1 --> <!-- e62c half DISCHARGED 2026-08-20: e62c is `- [x]` in ROADMAP.archive.md; STILL BLOCKED on b0b1, which lives only in TODO.md and was never promoted --> <!-- children-of:6b35 --> <!-- id:540f -->

- [ ] [ROUTINE] **`relay-loop.js`: self-attesting first mechanical hop; delete the fallback ternary** -- detail: `docs/ledger-notes/c179.md` 🚧 <!-- gated-on:b0b1 --> <!-- e62c half DISCHARGED 2026-08-20: e62c is `- [x]` in ROADMAP.archive.md; STILL BLOCKED on b0b1, which lives only in TODO.md and was never promoted --> <!-- children-of:6b35 --> <!-- id:c179 -->

- [ ] [ROUTINE] **(F5) A fail-closed refusal is INVISIBLE to the id:98f0 watchdog** -- detail: `docs/ledger-notes/554b.md` 🚧 <!-- gated-on:540f --> <!-- id:554b -->

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

- [ ] [INPUT - decision] **Wire the built-but-unreferenced fan-out machinery (`disjoint-greenlight.sh` + `drain-integrate.sh`) into `relay-loop.js`** -- detail: `docs/ledger-notes/ae08.md` @container <!-- children-of:1f4f --> <!-- id:ae08 --> 🚧

- [x] [INPUT - decision] **Pre-register the burn-ranking decision rule — THE GATE that orders id:a955 and id:3ca7** -- detail: `docs/ledger-notes/87f5.md` <!-- children-of:1f4f --> <!-- id:87f5 --> gated-on:87f5 gated-on:4438 (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Run the burn measurement and publish the per-phase ranking (measurement half of `id:87f5`)** -- detail: `docs/ledger-notes/4438.md` <!-- children-of:87f5 --> <!-- gated-on:87f5 --> <!-- id:4438 --> (archived — see ROADMAP.archive.md)
- [x] **[HARD] [INTENSIVE — disk-io] Standalone warm-vs-cold copy timing on a build-dep repo (H3)** <!-- id:3c9d --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`top_intensive`'s human-gated exclusion list is OLD-VOCAB ONLY — a new-vocab human-gated `[INTENSIVE]` item will be auto-dispatched** -- detail: `docs/ledger-notes/7517.md` <!-- routed:2d94 --> `@owner-gated` `@container` 🚧 <!-- routed:34a2 --> @owner-gated <!-- id:7517 --> (archived — see ROADMAP.archive.md)
- [x] [HARD] **L1 — mechanize the integrator into one `integrate.sh` relay-mech hop** -- detail: `docs/ledger-notes/a955.md` <!-- children-of:1f4f --> <!-- gated-on:4438 --> <!-- id:a955 --> 🚧 gated-on:87f5 gated-on:4438 (archived — see ROADMAP.archive.md)
## 2026-07-31 handoff C2 — execute→review cadence starvation (+ two watermark/registry defects)

> Promoted from `TODO.md` reusing each item's existing id (single-id-two-views — no duplicate
> minted). Items id:907e / id:8123 / id:6217 come from the owner-ratified meeting
> `docs/meeting-notes/2026-07-31-1231-execute-review-cadence-starvation.md`; id:c500 and id:069b
> are independent defects found the same day. **Work id:907e FIRST** — it is that meeting's
> re-ranked PRIMARY fix (D3/A4) and the only decision that addresses the observed incident.
> Every line/behaviour claim below was re-verified against the working tree at promotion time
> (2026-07-31, base `b92c4ab`); one claim inherited from the meeting was found FALSE and is
> corrected in place under id:8123.

- [ ] [INPUT - decision] **Extract `isDryRound`/`workCreated` into ONE shared definition — CROSS-FILE, via a generation step; record the drain-path gap MOOT-BY-RETIREMENT** -- detail: `docs/ledger-notes/6217.md` <!-- id:6217 --> 🚧

## Human triage 2026-08-01 (relay human `.`, owner-decided)

- [ ] [INPUT - decision] **`--fabled` (B): fire the Fable adversarial pass BEFORE each `AskUserQuestion`, not only at the closing pass** -- detail: `docs/ledger-notes/8df5.md` <!-- children-of:7e87 --> <!-- routed:43a8 --> <!-- routed:690b --> <!-- routed:4702 --> <!-- id:8df5 --> 🚧

## Handoff C2 2026-08-01 (relay handoff, owner-scoped 5-item promotion)

> Owner-scoped promotion of exactly five already-filed TODO items (ids REUSED —
> single-id-two-views). The scan found 13 promote- and 90 surface-disposition items; the
> surface set is deliberately NOT touched here (id:5eb3 — the `human` verdict's mechanical
> filer owns it). Rationale and full evidence for each item stay in `TODO.md`; these entries
> are the execution spec only.

- [ ] [INPUT - meeting] **@container — relay children can write the target's MAIN checkout; "Work EXCLUSIVELY in that worktree" is prose with zero enforcement** -- detail: `docs/ledger-notes/f91a.md` <!-- children:d464,34b7 --> <!-- routed:f91a --> <!-- id:f91a -->


## Provision fail-open cluster 2026-08-11 (inbox `routed:8d64` + `routed:d9a5`; parent `id:f91a`, post-`id:34b7`)

> **Both inbox reports reduce to ONE code defect plus ONE operational blind spot**, established by two
> independent investigations that converged on the same evidence (`/tmp/mechanical-proxy.log` — which
> neither reporter consulted). **Read this before working any item below; both reporters' own diagnoses
> were wrong in mechanism**, and a fix aimed at either stated cause would miss.
>
> **What actually happened.** The running `mechanical-proxy.py` (pid 1131, started 2026-08-11 13:32:59)
> predated commit `7437880` (2026-08-11 19:22), which added `provision-worktree.sh` to
> `ALLOWED_RELAY_SCRIPTS`. Python binds the allowlist at import and the file has no reload path, so the
> live process held a **pre-19:22 in-memory frozenset**. Every provision hop was therefore
> `mechanical_refused` → fail-open passthrough to the real API → 404, because no model is named `bash`
> → the reported *"issue with the selected model (bash)"*. **20 refusals across 4 runs; not one
> successful provision hop exists in the log — parent-side provisioning had never once succeeded since
> `id:34b7` landed.** The proxy was restarted 2026-08-11 23:2x (owner-authorised), which clears the
> symptom but fixes none of the defects below.
>
> **Corrections to the reports, on the record** (a report's own diagnosis is a derived doc — CLAUDE.md):
> `routed:8d64` says *"relay-loop created the worktree DIRECTORY"* — **false**; the provisioning command
> never executed at all, so nothing on the parent path could have created it (`claim.sh` never mkdirs the
> recorded `--worktree`; a failing `git worktree add` leaves no directory). Who made the empty dir is
> UNCONFIRMED — most likely the child while investigating. A fix aimed at *"mkdir happens before worktree
> add"* would target a mechanism that does not exist. `routed:d9a5` says *"the discriminator validates a
> path that provision does not use"* — right in effect, wrong in mechanism: `probe-mech-proxy.sh:43-49`
> is a **pure TCP connect** (`exec 3<>/dev/tcp/…`) that sends no HTTP request, no model name and no
> command, so there is no "path provision doesn't use" — no path is exercised at all. `routed:d9a5` also
> attributes the RELAY_STATUS silence to a rendering gap; the rendering gap is **real and separately
> filed (id:06a1)**, but it is NOT why this run was silent — the guard simply never fired.
>
> **The blast radius is the reason this is urgent, and it is worse than either report says.** Children
> that found no worktree did not all refuse. `relay-events.jsonl:3727` — a `hard` child: *"the pre-created
> worktree did not exist at dispatch, so I created it via `git worktree add`"*; `relay-worktree-retire.log:8572-8583`
> shows those self-created worktrees being retired **as merged**. So multiple children silently
> self-provisioned and their work merged. The careful refusal quoted in `routed:8d64` was the
> **exception, not the rule** — the `id:c6c8` hazard `id:34b7` was closed to remove is actively occurring.

- [ ] **[INPUT — decision]** Wire disjoint-greenlight.sh plan into the drain-mode fan-out planner — seam of id:ae08 (auto, id:3801) -- detail: `docs/ledger-notes/02b2.md` <!-- id:02b2 --> — 🚧 GATED (auto, id:3801; route:decision-gate): Needs /meeting: per-unit file-set provenance + which same-repo units are concurrency-eligible under the review-barrier — else the greenlight call is a forbidden dead branch. — needs a /meeting
- [ ] **[INPUT — decision]** Route same-repo drain-mode integration through drain-integrate.sh (serialized one-writer safety net) (after id:<seam-1 id>) — seam of id:ae08 (auto, id:3801) -- detail: `docs/ledger-notes/99e5.md` <!-- id:99e5 --> — 🚧 GATED (auto, id:3801; route:decision-gate): Wiring drain-integrate.sh into relay-loop.js's shared integrate() path depends on seam-1 id:02b2 (decision-gated /meeting on drain-mode fan-out planner + review-barrier concurrency); acceptance invariant D3a undefinable until then, and done-check tests already pass so there is no RED guard for the guard-less core-loop change. — needs a /meeting
- [x] [ROUTINE] **Teach the generic `roadmap-archive.sh` to LEAVE a one-line stub per moved item** -- detail: `docs/ledger-notes/cd9c.md` <!-- routed:f833 --> gated-on:cd9c <!-- id:cd9c --> <!-- id:XXXX --> (archived — see ROADMAP.archive.md)
## Review-derived promotion 2026-08-14 (relay review, reverse-handoff §5b)

- [x] [ROUTINE] **`md-merge.py update-ids` must ASSERT the id:6059 multi-marker REFUSAL — redefined 2026-08-20 (owner ruling, `/relay human --all`), supersedes the original last-vs-first own-id spec.** -- detail: `docs/ledger-notes/cc7e.md` <!-- id:XXXX --> <!-- id:cc7e --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Make `@owner-gated` a FIRST-CLASS exclusion in `lib-roadmap-sections.sh` — the PREREQUISITE for `id:6446`** -- detail: `docs/ledger-notes/f391.md` @owner-gated <!-- id:f391 --> (archived — see ROADMAP.archive.md)
- [ ] [ROUTINE] **Parked-section vocab match is a bare substring — a heading that merely mentions `archive`/`done`/`gated`/etc. in descriptive prose parks its whole section** -- detail: `docs/ledger-notes/6446.md` 🚧 `@owner-gated` <!-- gated-on:f391 --> <!-- id:6446 -->


## Test-harness throughput 2026-08-14 (/relay human, owner-directed)

- [x] [ROUTINE] **LANDED 2026-08-19 — measured, not assumed.** **Parallelise `tests/run-tests.sh`** <!-- id:f69b --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Make the fast subset first-class: `make test FILES=…` / `make test-changed`** <!-- id:d3f8 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`relay-doctor` check 9: distinguish ABANDONED main-checkout residue from IN-FLIGHT residue via live-claim state** <!-- id:aee5 --> (archived — see ROADMAP.archive.md)
- [x] [HARD] **`scan-routed.sh --apply` silently DELETED inbox items whose token was merely quoted in a sibling item's prose — the twin check now requires the token to be a line's OWN marker** -- detail: `docs/ledger-notes/c97c.md` <!-- id:c97c --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Author the systemd units + hardening for the two relay service users (authoring half of `id:8e7a`)** -- detail: `docs/ledger-notes/5bef.md` <!-- children-of:8e7a --> <!-- id:5bef --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Re-dispatch of an item that already has a prior attempt's branch carrying commits must REFUSE and surface, and integrate must compare against any sibling branch for the same item.** -- detail: `docs/ledger-notes/dd7d.md` <!-- routed:d99c --> <!-- routed:678c --> <!-- id:dd7d --> (archived — see ROADMAP.archive.md)
## meeting-question-guard was a live no-op — flush-wait fix + live confirmation (2026-08-19, `id:2419` second round)

- [ ] [ROUTINE] **`@owner-verify` — confirm the `meeting-question-guard` flush-wait actually fires in the LIVE harness** -- detail: `docs/ledger-notes/cf2d.md` <!-- id:cf2d -->

- [x] [ROUTINE] **`tests/test_run_tests_parallel.sh` is itself load-flaky — its `-j 1`/`NESTED` seriality checks intermittently observe 2 when they require 1** -- detail: `docs/ledger-notes/f875.md` <!-- id:f875 --> (archived — see ROADMAP.archive.md)
## Human triage 2026-08-19 (`/relay human .`, owner-decided)

- [x] [ROUTINE] **Mechanical `core.hooksPath` shadowing detector across the relay own-set** -- detail: `docs/ledger-notes/2bc6.md` <!-- id:2bc6 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`md-merge.py`: add insert-relative-to-id and an IN-LOCK line transform — the mandated flock path cannot express what agents actually need** -- detail: `docs/ledger-notes/f26d.md` <!-- routed:f88b --> <!-- routed:9aaf --> <!-- id:f26d --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **UNTRACKED-only dirt no longer blocks relay dispatch or integration; TRACKED dirt still does** -- detail: `docs/ledger-notes/27b4.md` <!-- id:27b4 --> (archived — see ROADMAP.archive.md)
- [x] **[HARD]** Build relay/scripts/integrate.sh — standalone mechanical integrator (all 11 deterministic steps, fail-closed LOUD), tested in isolation — seam of id:a955 (auto, id:3801) <!-- id:9e50 --> (archived — see ROADMAP.archive.md)
- [x] **[INPUT — decision]** Rewire relay-loop.js integrate() to dispatch integrate.sh via the mechanical hop (id:6176 relay-mech/MECH_MODEL), leaving only the semver micro-hop as an LLM agent (after id:seam-1) — seam of id:a955 (auto, id:3801) <!-- id:087b --> — 🚧 GATED (auto, id:3801; route:decision-gate): Done-check requires 3 tests unmodified, but noop_guard + ckpt_merged_tip structurally assert the very Sonnet integrator prompt this item removes (Acceptance vs Done-check contradict); also seam 9e50/integrate.sh omits tick/archive/6b/push-seed/siblingBranches — owner must rule before build. — needs a /meeting — **SHIPPED + VERIFIED + MERGED 2026-08-21** (`relay-ckpt-20260821-0855`, merge `c31a401`): all five previously-LLM-only behaviours ported into `integrate.sh`, **no LLM agent remains in `integrate()`** (the only `agent()` call is the `MECH_MODEL` fence, and `test_relay_integrator_noop_guard.sh` now actively REFUSES `sonnet|haiku|opus|fable` on that dispatch). Suite green at 453 at merge time. The Acceptance-vs-Done-check contradiction was resolved by the owner-ratified D1 amendment (2026-08-21): the two structurally-blocking tests were rewritten to assert the mechanical dispatch, preserving their real invariants. Bump trigger ships fail-closed pre-merge (`HANDBACK[bump]` exit 30) per the owner's ship-as-is ruling. **TICK WAS LATE — the box stayed `[ ]` for hours after merge because the executor was told to leave it for owner verification and the ticking was then missed; while unticked, `tests/test_integrate_mechanized_ports_087b.sh` counted as EXPECTED-RED, so a genuine regression on the merge-to-main path would not have failed the suite.** (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **A POST-PUSH integrate failure is no longer misread as a retryable defer** -- detail: `docs/ledger-notes/5fe2.md` <!-- id:5fe2 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **The `id:4f9b` prompt-size gate UNDER-COUNTS by ~50% — it never counts `TODO.md`** -- detail: `docs/ledger-notes/b018.md` <!-- id:b018 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Orchestrator writes the ledger SLICE to a tmp file and hands the child a PATH — the child can no longer over-read, because the bytes are not in its prompt** -- detail: `docs/ledger-notes/e68f.md` <!-- id:e68f --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **URGENT — prompt-size gate must measure the `id:e68f` SLICE when one exists (this repo was un-dispatchable)** -- detail: `docs/ledger-notes/35b7.md` <!-- id:35b7 --> <!-- relates:b018 --> <!-- relates:e68f --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`id:e68f`'s slicer bounded an item block by INDENTATION, so column-0 acceptance criteria were silently dropped** -- detail: `docs/ledger-notes/b015.md` <!-- id:b015 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Suppression must DEMOTE the verdict, not DROP the unit — a stuck item starves every lower verdict class indefinitely** -- detail: `docs/ledger-notes/bc2b.md` <!-- id:bc2b --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`drained` must distinguish FINISHED from HUMAN-BLOCKED — two repos with 31 open items between them read as done** -- detail: `docs/ledger-notes/4a76.md` <!-- id:4a76 --> (archived — see ROADMAP.archive.md)
## Parallel-suite flakiness — OBSERVE-FIRST (promoted from TODO 2026-08-21, `id:7518`)

> Promoted reusing the existing TODO id (single-id-two-views). `TODO.md` stays the prose
> SSOT for the accumulated observations; this is the execution spec. **This item is
> deliberately OBSERVE-FIRST** (CLAUDE.md "observe before preventing"): its deliverable is
> EVIDENCE plus a recommendation, not a speculative fix. It stays OPEN until a cause is
> identified — "could not reproduce" is NOT a close.

- [ ] [INPUT - decision] **General parallel-suite flakiness — four unrelated tests have flaked in-suite and passed standalone; build the per-run failure logger before any fix** -- detail: `docs/ledger-notes/7518.md` <!-- id:7518 --> @container 🚧

- [x] [ROUTINE] **Remove the `pipefail` + early-exiting-pipe-consumer race repo-wide, and lint it so it cannot return** -- detail: `docs/ledger-notes/81d5.md` <!-- relates:7518 --> <!-- id:81d5 --> (archived — see ROADMAP.archive.md)
## Integrator ledger staging + stale slicer wording (2026-08-21)

- [x] [ROUTINE] **POOL-BLOCKING — the mechanized TODO-twin tick wrote `TODO.md` but nothing staged or committed it, wedging the repo permanently** -- detail: `docs/ledger-notes/e82e.md` <!-- id:e82e --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **The `id:7575` hardened brief asserted a slicer defect `id:b015` had already removed** -- detail: `docs/ledger-notes/31c3.md` <!-- id:31c3 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Destructive-git PreToolUse guard — `hooks/destructive-git-guard.py`** -- detail: `docs/ledger-notes/3a09.md` <!-- id:3a09 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Destructive-git guard: the `discovery-producer` daemon is no longer read as an unattended run** -- detail: `docs/ledger-notes/6f62.md` <!-- id:6f62 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Destructive-git guard: a malformed PreToolUse payload no longer FAILS OPEN** -- detail: `docs/ledger-notes/3866.md` <!-- id:3866 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Destructive-git guard: a fresh heartbeat marker with an unusable `runId` is now a probe ERROR, not a non-signal** -- detail: `docs/ledger-notes/8987.md` <!-- id:8987 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Destructive-git guard no-drift test pins the RULE, not one spelling** -- detail: `docs/ledger-notes/4c14.md` <!-- id:4c14 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Version the last unmanaged hook — `rm-force-guard.sh`** -- detail: `docs/ledger-notes/5218.md` <!-- id:5218 --> (archived — see ROADMAP.archive.md)
- [ ] **[INPUT — decision]** Gather post-id:81d5-fix flake-log confirmation runs at j1 and an over-subscribed width (e.g. j24/j32), ≥2 runs each — seam of id:7518 (auto, id:3801) -- detail: `docs/ledger-notes/372a.md` <!-- id:372a --> — @container 🚧 GATED (auto, id:3801; route:hard-split): DECOMPOSED into seams id:97e0, id:f2ef, id:b1ef, id:c3be, id:6ab7 — pick those, not this. Each of 4 required flake-log runs (2× width=1, 2× width≥16) takes multiple minutes wall-clock; doesn't fit one executor turn as a single unit.
- [ ] **[HARD]** Reviewer: fold the three-width post-fix data into ROADMAP.md id:7518, rank surviving hypotheses with confirm/kill criteria each (Acceptance clause 4), and decide closure per clause 6/7 (after id:(depends on the data-gathering seam above)) — seam of id:7518 (auto, id:3801) -- detail: `docs/ledger-notes/166a.md` <!-- id:166a -->
- [ ] **[INPUT — decision]** flake-log width=1 confirmation run #1 (post-id:81d5) — seam of id:372a (auto, id:3801) -- detail: `docs/ledger-notes/97e0.md` <!-- id:97e0 --> — 🚧 GATED (auto, id:3801; route:human): flake-log -j1 (sequential full suite) exceeds one executor turn's wall-clock budget under current host load (~10-16 loadavg); needs a longer-lived/background run or a lower-load window, not a code change. — needs /relay human
- [x] **[ROUTINE]** flake-log width=1 confirmation run #2 (post-id:81d5) (after id:(seam 1, independent — no id yet)) — seam of id:372a (auto, id:3801) <!-- id:f2ef --> (archived — see ROADMAP.archive.md)
- [x] **[ROUTINE]** flake-log over-subscribed-width confirmation run #1 (post-id:81d5) — seam of id:372a (auto, id:3801) <!-- id:b1ef --> (archived — see ROADMAP.archive.md)
- [x] **[ROUTINE]** flake-log over-subscribed-width confirmation run #2 (post-id:81d5) — seam of id:372a (auto, id:3801) <!-- id:c3be --> (archived — see ROADMAP.archive.md)
- [x] **[ROUTINE]** **Route the integrate hop's FREE-TEXT fields (`--summary`/`--label`) through the `relay-mech-stdin` payload channel instead of inline shell args** (owner decision 2026-08-26 "sanitize now, migrate durably" — this is the DURABLE half; the sanitize half landed as `17b4e4e0`). Promoted at review 2026-08-26b (mini-handoff, review.md §5b) reusing the existing TODO token. <!-- id:76fd --> (archived — see ROADMAP.archive.md)
- [ ] **[INPUT — decision]** Summarize the 4 post-id:81d5 flake-log confirmation rows in RELAY_LOG.md (after id:all 4 run seams above) — seam of id:372a (auto, id:3801) -- detail: `docs/ledger-notes/6ab7.md` <!-- id:6ab7 --> — 🚧 GATED (auto, id:3801; route:human): only 3/4 required flake-log confirmation rows exist — 4th seam id:97e0 still gated on /relay human (width=1 run exceeds one turn's wall-clock budget) — needs /relay human
- [x] **[ROUTINE]** **Base-ref resolution must use the repo's ACTUAL checked-out branch — never a hard-coded `origin/main` → `main` → `master` guess** (owner ruling 2026-08-26; PROPAGATION of the already-ratified id:8739 posture to the two remaining offenders, not a new design) <!-- id:758a --> — CLOSED at review 2026-08-26 (run `relay-20260826-162405-7522`): verified green against the pre-authored RED spec `tests/test_base_ref_checked_out_branch_758a.sh`, which the fix commit `478d70d2` did NOT touch (independent spec); TODO twin already `[x]`, cross-ledger drift resolved. (archived — see ROADMAP.archive.md)
- [x] **[ROUTINE]** **Apex `hard` dispatch MUST require `--afk`, and the HARD-execute gate must key on `STRONG_TIER === 'opus'` instead of the model-id literal `claude-opus-4-8`** — combines `id:7986` (owner 2026-08-22, after a live pool spent Opus on three `[HARD]` units against his cap) with `id:da51` (`routed:fba9` from csgebra; owner-ratified 2026-08-23). Today `relay-loop.js` has NO consumer of `A.afk` at all, so the owner's rule is prose only; and the hard gate compares `STRONG_MODEL !== 'claude-opus-4-8'`, so bumping the pin to the live apex model would make the inequality TRUE and defer every hard unit while reporting "requires apex Opus" — a message false precisely when the pin is correct. The two must land together or the next reader inherits the same contradiction. **SETTLED, do NOT re-open:** (1) `handoff` is PERMITTED ALWAYS at apex, exactly like `review` — ONLY `hard` is gated on `--afk` (owner 2026-08-22; this OVERRIDES the contrary recommendation recorded when `id:7986` was filed, and the SKILL.md wording must not imply handoff is gated). (2) The gate asks `STRONG_TIER === 'opus'`; the model id becomes a pure OUTPUT value, bumped to `claude-opus-5` (owner 2026-08-23). (3) Runtime auto-detection of the live apex model id is OUT OF SCOPE (filed separately as `id:f6a1`). <!-- id:7986 --> <!-- ref:da51 --> (archived — see ROADMAP.archive.md)

- [x] **[ROUTINE]** **Mid-run context-budget check that triggers a clean CHECKPOINT-AND-HANDBACK before an executor dies of `Prompt is too long`** — two loderite executors in run `relay-20260826-162405-7522` died mid-unit and orphaned partial work onto `relay/orphan/…-execute-5adb-0` / `…-execute-repo-0`, SUPPRESSING re-dispatch of those items until a human ran `/relay reconcile`. The cause is pure ACCUMULATION, not an oversized dispatch: initial prompts were **8,275 B / 6,359 B**, final transcripts **428,151 B / 477,574 B** over **166 / 193** turns, growth LINEAR (~100 KB by line 24/30, ~400 KB by line 152/150) with no single line above ~5% of its transcript. **This is NOT `id:35b7` / `id:4f9b` and that gate MUST NOT be touched** — it sized correctly here (the 5adb unit even consumed its `id:e68f` ledger slice as designed) and mid-run growth is structurally invisible to any dispatch-time gate. **BYTE-ATTRIBUTED breakdown of both dead transcripts (measured 2026-08-26; it CORRECTS the first-pass "streamed build/test output" diagnosis, which is refuted):** build/test output **3.3% / 1.5%** — the SMALLEST named bucket, partly because several invocations already redirect to a file and only `tail` it; code navigation **14.5% / 11.9%** (grep-style symbol lookup only 2.5% / 2.7% of it); docs / ledgers / relay brief **18.3% / 23.0%**; git plumbing **0.4% / 0.2%**. **THE STANDOUT IS STRUCTURAL, and it is what this item designs against: both units burned the overwhelming majority of their budget INVESTIGATING BEFORE THEIR FIRST PRODUCTIVE EDIT** — execute-5adb's first `Edit` came at line 99 after **282,716 B = 63.9%** of the whole transcript; execute-repo's at line 133 after **379,317 B = 76.8%**. Two-thirds to three-quarters of the window was gone before one line changed. Owner's recorded judgement stands and is strengthened by the attribution: of candidates (a) redirect build/test output to a file, (b) cap/truncate `tool_result` payloads, (c) mid-run budget check → checkpoint-and-handback, **(c) is the highest-value half** — dying costs a human `/relay reconcile` per orphan AND blocks re-dispatch, whereas an early handback costs nothing and keeps the work in the normal flow; the failure is also SILENT to the operator until they notice a suppressed re-dispatch. **(a) is measured at ~2% here and is explicitly DEMOTED** — it is a minor note, not a fix, and no part of this item pursues it. Promoted from TODO with the same id (single-id-two-views). <!-- children-of:93cc --> — **DONE 2026-08-27, with LIVE evidence** (not a green-suite inference — that was the 08-27 morning mistake this item itself had to be reverted for). Rule 2c ran in a real pool for the first time in run `relay-20260827-102629-23445`, once `id:c219` fixed the transcript resolver that had made it silently inert: **7 real verdicts — 5× `ok`, 1× `warn` (265,470 B), 1× `handback` (310,010 B / 77,502 tok)** — and zero resolution failures. So the check resolves, sizes, and crosses both thresholds against real children. The one `handback` fired on the `leancow` hard unit at byte 310,292 of a 335,766-byte transcript (~92% through); it finished green and integrated. That deviation from v15's unconditional disposition was ADJUDICATED, not ignored: contract **v16** adds the near-done carve-out, because handing back 25 KB from the end would discard a nearly-complete unit while averting no death. Remaining branches of rule 2c are still unexercised (ZERO-COMMIT, the repeat escalation to `route="hard-split"`, the NARROW-SCOPE pre-first-edit warn, and v16's own carve-out wording) — those accrue over future runs and are tracked in `TODO.md` as [[5fd1]], deliberately NOT as a ROADMAP item: no executor can produce an observation, and filing one here is what caused this repo's `id:bfbf` handback in this very run. <!-- id:5eeb --> (archived — see ROADMAP.archive.md)
- [x] **[ROUTINE]** **Machine-visible DECIDED-ANSWER marker plus the lint rule that reads it** -- add an owner-only `@owner-answered:YYYY-MM-DD` marker (sibling of `@owner-accepted`, id:8089) with a mandatory anchored source comment in the `answer-src:` namespace, document it in `relay/references/hard-lanes.md` beside its siblings, and add a `roadmap-lint.sh` grammar rule that validates it: well-formed date, source present, source resolves (a repo-relative path, optionally with an `#anchor` fragment, or a 4-hex ledger id resolving through the shared id:46f6 engine over ROADMAP.md union TODO.md union TODO.archive.md). Malformed or dangling fires ERROR and exits nonzero UNCONDITIONALLY (never gated behind `--strict`): the rule can only fire on a line that already carries the marker, so it reddens nothing that does not opt in, and a dangling citation is the rot mode that would make the whole scheme worthless. Matching is ANCHORED -- backtick spans masked before the marker match, source read only through a comment-anchored `grep -oP` extractor in `relay/scripts/lib-typed-edges.sh`, never a raw-line substring (the id:4da4/0d58 trap; three separate defects this month came from unanchored matching). The marker asserts that ONE QUESTION inside the item is answered, NOT that the item is finished, so it must not imply a tick and must not suppress or weaken rule 3(b). SCOPE GUARDS: do NOT flip rule 3(b) from WARN to ERROR and do NOT change what `--strict` means (fleet-wide behaviour change, owner's call); do NOT retro-apply the marker to any existing item anywhere (writing it is the OWNER's alone -- an executor or reviewer minting it is the id:8089 gaming class); do NOT touch the em-dash migration seams or `docs/migration-em-dash-delimiter.md`. Tests: `tests/test_owner_answered_marker_ca14.sh` (`# roadmap:ca14`, hermetic, fixtures in `mktemp -d`, no `~/.claude`, no network). Done-check: that spec green, then a full `tests/run-tests.sh`. Full context, evidence and the loderite `id:ed3a` case: the TODO twin (single-id-two-views). -- DONE 2026-08-27: `@owner-answered:YYYY-MM-DD` plus the anchored `answer-src:` citation comment are documented in `relay/references/hard-lanes.md`; `roadmap-lint.sh` rule 3(h) ANSWER-SRC validates them (backtick-masked marker match, citation read only through `typed_edges_answer_src_of_line`, ERROR + nonzero unconditionally, runs on ticked and parked lines too); `tests/test_owner_answered_marker_ca14.sh` covers 11 cases (A..K), authored RED first. Rule 3(b) was NOT flipped to ERROR: that stays the owner's call. <!-- id:ca14 --> (archived — see ROADMAP.archive.md)
- [x] **[ROUTINE]** **`@owner-answered` enforcement arms + the CONSUMER-side surface (follow-on to id:ca14)** -- `ca14` shipped the marker plus `roadmap-lint.sh` rule 3(h), which validates its GRAMMAR only. An adversarial review rebuilt the loderite `id:ed3a` incident with a CONFORMING marker on it and got exit 0 / zero findings, and separately found the marker FORGEABLE: `hard-lanes.md` called it owner-only citing `@owner-accepted` (id:8089) as precedent, but 8089's two enforcement arms had no twin, so `grep -rn 'owner-answered'` found the token in only three files and an executor could mint `@owner-answered:<today>` unflagged. THIS ITEM: (a) executor-contract rule 8 (v16 -> v17) forbidding an executor/drain session from writing the marker or its `answer-src:` citation, worded from rule 7; (b) `review.md` §2b.9 grepping the reviewed diff for either half in an executor-attributed commit; (c) `review.md` §2b.10 flagging a diff that MODIFIES a line already carrying the marker, for contradiction review against the cited answer (that edit IS re-ask (1) of the incident); (d) a new `answered_question` row kind in `gather-human-backlog.sh`, emitted FIRST per repo across ROADMAP/TODO/REVIEW_ME, naming the citation, so `/relay human` and a `/meeting` agenda-builder read "already answered, cited at X" before re-opening the question. DESIGN CONSTRAINT: surface, NEVER suppress -- purely additive, no existing row changes, no bucket loses a member, no dispatch verdict changes, the marker does not gate `actionable_routine_open`. Tests: `tests/test_answered_question_surface_6621.sh` (`# roadmap:6621`, hermetic, A..I). <!-- id:6621 --> (archived — see ROADMAP.archive.md)
## Em-dash delimiter migration (owner-ratified, `docs/migration-em-dash-delimiter.md`) — S0..S10

- [x] [HARD] Em-dash delimiter migration S0 — build `relay/scripts/lane-delimiter-scan.sh`, the mechanical completion detector that distinguishes a LIVE lane tag from a backtick'd/prose mention (must reuse `roadmap-lint.sh`'s `leading_lane_run` anchoring exactly, not reimplement it); load-bearing for every later seam's rollback/half-applied detection, must land first. -- detail: `docs/ledger-notes/70bc.md` <!-- id:70bc --> (archived — see ROADMAP.archive.md)
- [x] [HARD] Em-dash delimiter migration S1 — flip `relay/references/hard-lanes.md` to hyphen delimiters, change all six scrape regexes (across `lane-convert.sh`, `roadmap-lint.sh`, `pre-commit-lane-vocab.sh`) to an explicit two-delimiter alternation, and DELETE all six hardcoded vocabulary fallbacks in favour of a loud non-zero exit; MUST land as one atomic commit (a split window makes the SSOT read new while readers silently enforce old). -- detail: `docs/ledger-notes/71d6.md` <!-- gated-on:70bc --> <!-- id:71d6 --> (archived — see ROADMAP.archive.md)
- [x] [HARD] Em-dash delimiter migration S2 — fix `gather-repo-state.sh`'s backwards lane-vocabulary map (`:337-351`) and its three `[INTENSIVE — ]` hardcodes (`:361/364/378`) to canonicalize on the hyphen spelling while accepting both delimiters on input; author the new RED spec pinning the canonical spelling (`tests/test_gather_lane_canonical_delimiter.sh` does not exist yet — writing it is part of this seam, and its RED evidence must be captured before the fix). -- detail: `docs/ledger-notes/098a.md` <!-- gated-on:71d6 --> <!-- id:098a --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] Em-dash delimiter migration S3 — make `hooks/pre-commit-lane-vocab.sh`'s ratchet delimiter-agnostic by deriving `old_vocab_replacement` from the same SSOT scrape that populates `all_lane_tags`, keyed on the LANE NAME rather than the delimiter byte; must land before any ledger rewrite (S9) or the ratchet is disarmed silently. -- detail: `docs/ledger-notes/2ee5.md` <!-- gated-on:098a --> <!-- id:2ee5 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] Em-dash delimiter migration S4 — convert the em-dash lane-tag match patterns in the 12 remaining `relay/scripts/*.sh` readers (incl. `lane-convert.sh`'s own `[INTENSIVE — ]` regexes and the `todo-conformance.sh` `'[HARD-'` defect) to the two-delimiter alternation; do it in two batches of 6 files. <!-- gated-on:2ee5 --> — **BATCH 1 of 2 LANDED 2026-08-31** -- detail: `docs/ledger-notes/e8d4.md` <!-- children:6bf5 --> <!-- id:e8d4 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] Em-dash delimiter migration S4 BATCH 2 — convert the REMAINING 8 `relay/scripts/*.sh` readers to the two-delimiter alternation (batch 1 landed the first 4 as part of `id:e8d4`). -- detail: `docs/ledger-notes/6bf5.md` <!-- gated-on:2ee5 --> <!-- id:6bf5 --> (archived — see ROADMAP.archive.md)
- [x] [HARD] Em-dash delimiter migration S5 — convert the non-bash relay consumers (`relay-loop.js`, `drain.mjs`, `handback-guard.mjs`, `handback-followup.py`, `backtest-historical.py`) to the two-delimiter alternation; kept as a SEPARATE seam because a `relay-loop.js` template-string edit is the `loop-crash-class` runtime hazard that `node --check` + grep cannot catch — verify with the exec-smoke guard (id:5bac/aec5). -- detail: `docs/ledger-notes/1a03.md` <!-- gated-on:2ee5 --> <!-- id:1a03 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] Em-dash delimiter migration S6 — convert `meeting/classify.sh` (the lane floor, `:101-128`), `meeting/orphan-scan.sh`, `meeting/SKILL.md`, `Makefile` and `hooks/lane-vocab.claude-rule.md` to the two-delimiter alternation, verifying each hyphen-spelled lane routes identically to its em-dash twin. -- detail: `docs/ledger-notes/d0aa.md` <!-- gated-on:2ee5 --> <!-- id:d0aa --> (archived — see ROADMAP.archive.md)
- [x] [HARD] Em-dash delimiter migration S7 — flip the 26 NORMATIVE contract/doc markdown files (`relay/references/*.md`, `relay/SKILL.md`, `ARCHITECTURE.md`, `docs/diagrams/*.mmd`, `tracker/SCHEMA.md`, `hooks/lane-vocab.claude-rule.md`) to hyphen spelling while leaving every HISTORICAL doc (`docs/HANDOVER-*.md`, `docs/meeting-notes/**`, `CHANGELOG.md`, `*.archive.md` prose) byte-identical — distinguishing normative from historical is a judgment call per file, not a mechanical sweep, and rewriting a historical doc destroys the audit trail hazard 7 protects. -- detail: `docs/ledger-notes/55c7.md` <!-- gated-on:2ee5 --> <!-- id:55c7 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] Em-dash delimiter migration S8 — purely mechanical rewrite of the delimiter inside the 86 test-fixture files' heredocs and assertion strings, batched by prefix (`test_classify_*`, `test_gather_*`/`test_relay_*`, the rest, plus `tests/shard-canary/**` and `tracker/fixtures/**`); after EACH batch `tests/run-tests.sh` must read 519 passed / 0 failed / 1 expected-red plus the seam's own new specs — never open all 86 files in one turn. -- detail: `docs/ledger-notes/ee31.md` <!-- gated-on:e8d4 --> <!-- gated-on:1a03 --> <!-- gated-on:d0aa --> <!-- gated-on:55c7 --> <!-- id:ee31 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] Em-dash migration: `tracker/ledger-map.py` lane regexes + its golden fixtures, as ONE commit — `RE_HARD_LEGACY`/`RE_INPUT`/`RE_INTENSIVE` (`:132-134`) each require a literal em dash with `\\s+` around it, so a hyphen-spelled ledger cannot match. -- detail: `docs/ledger-notes/c442.md` <!-- gated-on:ee31 --> <!-- id:c442 --> (archived — see ROADMAP.archive.md)
- [ ] [HARD] Em-dash delimiter migration S9 — rewrite this repo's own LIVE lane tags in `TODO.md`/`ROADMAP.md`/`REVIEW_ME.md` and their `.archive.md` siblings to hyphen delimiters, through `meeting/md-merge.py` / `relay/scripts/commit-ledger.sh` only (never `Edit`/`sed -i` — these are shared non-union ledgers); per dc5b C2, this seam never runs concurrently with any other dotclaude-skills unit (one unit per repo per round). <!-- gated-on:ee31 --> — **MEASURED 2026-08-31** -- detail: `docs/ledger-notes/6958.md` [HARD - pool] [HARD] <!-- id:6958 -->
- [x] [INPUT - decision] **S9 archive conflict: the delimiter migration and the vocabulary ratchet cannot both be satisfied on `*.archive.md` without a ruling.** MEASURED 2026-08-31: migrating the 85 live lane tags in `ROADMAP.archive.md` (47) + `TODO.archive.md` (38) makes them ADDED lines carrying venue-keyed old vocabulary (`[HARD - pool]` x39, `[HARD - hands]` x6, `[HARD - decision gate]` x4), so `hooks/pre-commit-lane-vocab.sh` blocks both files (exit 1, verified with `LANE_VOCAB_ALL_REPOS=1`). ALL 85 are closed `- [x]` entries; zero are open. Three ways out, none takeable without you: (a) ** -- detail: `docs/ledger-notes/2065.md` <!-- gated-on:6958 --> <!-- id:2065 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] Em-dash delimiter migration S5b (the EMIT side) -- the closed reader seams (id:e8d4/id:6bf5/id:1a03) left every EMITTER on the legacy U+2014 delimiter, contrary to the migration doc's own rule at `docs/migration-em-dash-delimiter.md:36` ("Every **emitter** -- detail: `docs/ledger-notes/32f9.md` <!-- id:32f9 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] `lane-delimiter-scan.sh` returns exit **1** -- detail: `docs/ledger-notes/4ce8.md` <!-- id:4ce8 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] Hermetic test fixtures INHERIT the global `core.hooksPath`, so a fixture repo whose `RELAY_TOML`/`SRC_DIR` point into itself makes the lane-vocab hook fire at test RUNTIME and the test exits 1 -- detail: `docs/ledger-notes/4d1c.md` <!-- id:4d1c --> (archived — see ROADMAP.archive.md)
- [ ] [INPUT - meeting] Em-dash delimiter migration S10 (seam B) — drop the dual-vocab tolerance fleet-wide: delete the em-dash arm of every alternation and turn a live old-delimiter/old-vocabulary lane tag into a LOUD (nonzero) error in `roadmap-lint.sh`, `gather-human-backlog.sh` and the ratchet; MUST NOT be bundled with anything else. -- detail: `docs/ledger-notes/da55.md` <!-- gated-on:6958 --> <!-- id:da55 -->
## 2026-09-01 review reverse-handoff (run relay-20260901-101120-32404, review.md §5b)

> Qualified from TODO.md items the owner filed manually this window. Ids REUSED
> (single-id-two-views D2) -- both lines also live in `TODO.md` under the same token.

- [x] [ROUTINE] **`tracker/ledger-map.py` loses parents on a multi-`children-of:` line -- silent DATA LOSS.** <!-- id:8302 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`children-of:` and `children:` still resolve to TWO different relations -- the UNMET half of id:8302's acceptance.** <!-- id:59c5 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Executor-contract rule 2c's ZERO-COMMIT branch leaks its own escalation counter, so `route="hard-split"` is unreachable.** <!-- id:d8b3 --> (archived — see ROADMAP.archive.md)

## 2026-09-02 shrink-programme gaps (handoff C2, run relay-handoff-019adc92)

> Promoted from `TODO.md` after the wave-3 shrink landed. Ids REUSED where the item
> already existed there (single-id-two-views D2); the three `roadmap:` tokens below are
> NEW and name the RED specs authored in this handoff, whose items are the fix.
>
> The unifying finding: every consumer that reads an item's BODY breaks when the body
> moves, and SEVEN have now been found this way (`id:2ee1` ledger-slice, `id:f3d2` the
> byte gate, `id:e95b` roadmap-lint rule 3(c), roadmap-lint's `has_todo_twin`,
> `lib-state-claim.sh` reached from two directions, and `orphan-scan --shipped`). Six of
> the seven fail toward SILENCE; the seventh invents a wrong recommendation.

- [x] [ROUTINE] **`shrink-acceptance.py` must ATTRIBUTE a lost violation, not score it as a win -- the gate is structurally blind to a detector going blind.** -- detail: `docs/ledger-notes/5f34.md` <!-- id:5f34 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`orphan-scan --shipped` must follow the per-id detail pointer -- it is the only consumer measured to MANUFACTURE a wrong recommendation.** -- detail: `docs/ledger-notes/1608.md` <!-- gated-on:5f34 --> <!-- id:1608 --> (archived — see ROADMAP.archive.md)
- [ ] [HARD] **`shape-prose` SATURATES at ~114 standing findings, so it regulates nothing and cannot surface #115.** -- detail: `docs/ledger-notes/2d17.md` <!-- routed:3924 --> <!-- id:2d17 -->
- [ ] [HARD] **Reconcile the indented-id count before any promote pass -- 11 (ruled) vs 21 (measured) vs 10 (measured now).** -- detail: `docs/ledger-notes/8679.md` <!-- id:8679 -->
- [ ] [ROUTINE] **`grammar_item_class` counts the `-- detail:` pointer as title while `shape-prose` excludes it, so planting a REQUIRED pointer pushes an item over budget.** -- detail: `docs/ledger-notes/60eb.md` <!-- id:60eb -->
- [ ] [INPUT - decision] **Section preamble prose has no home in the three-shape grammar; 154 ROADMAP lines are refused with nowhere to go.** -- detail: `docs/ledger-notes/800f.md` <!-- id:800f -->
- [ ] [INPUT - decision] **The archive stub is written AFTER the id marker, which the grammar forbids; 2 writers and 7 tests pin it.** -- detail: `docs/ledger-notes/d05d.md` <!-- id:d05d -->
- [ ] [ROUTINE] **Move ROADMAP.md continuation lines into per-id notes -- under the ratified line grammar they are not large blocks to budget, they are INVALID.** -- detail: `docs/ledger-notes/40c0.md` <!-- gated-on:b048 --> <!-- id:40c0 -->
- [ ] [ROUTINE] **The `id:0d7c` ratchet keys on HEAD-LINE length, so it is structurally blind to 79% of ROADMAP.md and can be fully GREEN while the file grows without limit.** -- detail: `docs/ledger-notes/b048.md` <!-- gated-on:f193 --> <!-- id:b048 -->
- [ ] [ROUTINE] **Make the ratification gate BIND: move it from the unit to the REMOTE, and make the queue self-verifying (option A+D, owner-ratified 2026-09-02).** -- detail: `docs/ledger-notes/3c04.md` -- detail: `docs/ledger-notes/7408.md` <!-- children-of:3c04 --> <!-- id:7408 -->
- [ ] [ROUTINE] **The length ratchet cannot detect its own STALE baseline, so a shrunk item silently keeps its old floor and a regrowth reads as grandfathered.** -- detail: `docs/ledger-notes/2654.md` <!-- id:2654 -->
- [ ] [ROUTINE] **257 ledger items have a TITLE that is itself over budget -- no relocation can shorten a title, so these need rewriting.** -- detail: `docs/ledger-notes/64f9.md` <!-- gated-on:ff7c --> <!-- id:64f9 -->
- [ ] [ROUTINE] **Build the DIRECTIONAL round-trip validator the id:0d7c format ratified and nobody built -- a trimming pass must be provable, not eyeballed.** -- detail: `docs/ledger-notes/ff7c.md` <!-- id:ff7c -->
- [ ] [ROUTINE] **`id:401c` is an append-only audit LOG occupying 42% of ROADMAP.md -- relocate its body under the ratified `id:0d7c` topology.** -- detail: `docs/ledger-notes/f193.md` <!-- id:f193 -->
- [x] [ROUTINE] **The lane grammar is hand-mirrored in three places; make ONE source serve both the actor and the checker.** -- detail: `docs/ledger-notes/6546.md` <!-- id:4983 --> (archived — see ROADMAP.archive.md)
- [ ] [ROUTINE] **`shape-prose` becomes an ERROR -- the closing act of the no-prose bar.** -- detail: `docs/ledger-notes/8524.md` <!-- gated-on:1608,2d17 --> <!-- id:8524 -->
- [ ] [INPUT - decision] **Three items carry a de-facto lane derived from BODY PROSE, which `classify-repo` reads as their real lane.** -- detail: `docs/ledger-notes/1254.md` <!-- id:1254 -->
