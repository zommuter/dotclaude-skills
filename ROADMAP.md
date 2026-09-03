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
- [ ] [INPUT - meeting] Custom agent types (`.claude/agents/*.md`) per relay subcommand — see TODO.md <!-- id:931c --> **[2026-07-21 — evaluate UNDER the id:cae2 Agent-SDK audit (candidate #2), not piecemeal. Scope narrowed to the JUDGMENT roles (executor/reviewer/handoff/discover-shard); the mechanical variant id:f599 is SUPERSEDED by the model:"bash" proxy (id:6176/176f). Primary value = RELIABILITY (bake "load+follow the versioned contract" into the subagent prompt so it is not a forgettable per-dispatch step), not token cost. TWO DESIGN KEYS: (1) POINT don't DUPLICATE — the subagent prompt READs `relay/references/executor-contract.md` (vN) at runtime, never copies it (else derived-doc drift vs the ratified SOP); (2) USER-LEVEL install (`~/.claude/agents/` + `make install` symlink), never project-level, because relay runs the whole relay.toml set. `tools:` frontmatter scoping is ergonomic, NOT a security boundary (deny-probe-5937 — the OS-user tier is the real containment).]**
- [ ] [INPUT - meeting] Design tier-robust gate-discipline mechanisms (for a Fable session to consider): the 2026-07-02… — see TODO.md <!-- id:abe7 -->
- [ ] [INPUT - meeting] Upgrade `consumer-enum.sh` from content-grep to real import/read-edge resolution (relay human r… — see TODO.md <!-- id:494f -->
- [ ] [INPUT - meeting] A shared "reasoning-fallacy checkup" step for `/relay` and `/meeting` (user 2026-07-17: "add TO… — see TODO.md <!-- id:0e56 -->


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
## Review-derived promotion 2026-08-14 (relay review, reverse-handoff §5b)

- [ ] [ROUTINE] **Parked-section vocab match is a bare substring — a heading that merely mentions `archive`/`done`/`gated`/etc. in descriptive prose parks its whole section** -- detail: `docs/ledger-notes/6446.md` 🚧 `@owner-gated` <!-- gated-on:f391 --> <!-- id:6446 -->


## Test-harness throughput 2026-08-14 (/relay human, owner-directed)

## meeting-question-guard was a live no-op — flush-wait fix + live confirmation (2026-08-19, `id:2419` second round)

- [ ] [ROUTINE] **`@owner-verify` — confirm the `meeting-question-guard` flush-wait actually fires in the LIVE harness** -- detail: `docs/ledger-notes/cf2d.md` <!-- id:cf2d -->

## Human triage 2026-08-19 (`/relay human .`, owner-decided)

## Parallel-suite flakiness — OBSERVE-FIRST (promoted from TODO 2026-08-21, `id:7518`)

> Promoted reusing the existing TODO id (single-id-two-views). `TODO.md` stays the prose
> SSOT for the accumulated observations; this is the execution spec. **This item is
> deliberately OBSERVE-FIRST** (CLAUDE.md "observe before preventing"): its deliverable is
> EVIDENCE plus a recommendation, not a speculative fix. It stays OPEN until a cause is
> identified — "could not reproduce" is NOT a close.

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
## 2026-09-01 review reverse-handoff (run relay-20260901-101120-32404, review.md §5b)

> Qualified from TODO.md items the owner filed manually this window. Ids REUSED
> (single-id-two-views D2) -- both lines also live in `TODO.md` under the same token.


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

- [x] [HARD] **`shape-prose` SATURATES at ~114 standing findings, so it regulates nothing and cannot surface #115.** -- detail: `docs/ledger-notes/2d17.md` <!-- routed:3924 --> <!-- id:2d17 -->
- [ ] [ROUTINE] **A regrowth BELOW the baselined value is forgiven -- the `id:718c` shape the snapshot ratchet structurally cannot catch.** -- detail: `docs/ledger-notes/cf64.md` <!-- children-of:2d17 --> <!-- gated-on:2654 --> <!-- id:cf64 -->
- [ ] [HARD] **Reconcile the indented-id count before any promote pass -- 11 (ruled) vs 21 (measured) vs 10 (measured now).** -- detail: `docs/ledger-notes/8679.md` <!-- id:8679 -->
- [ ] [ROUTINE] **`grammar_item_class` counts the `-- detail:` pointer as title while `shape-prose` excludes it, so planting a REQUIRED pointer pushes an item over budget.** -- detail: `docs/ledger-notes/60eb.md` <!-- id:60eb -->
- [ ] [INPUT - decision] **Section preamble prose has no home in the three-shape grammar; 154 ROADMAP lines are refused with nowhere to go.** -- detail: `docs/ledger-notes/800f.md` <!-- id:800f -->
- [ ] [INPUT - decision] **The archive stub is written AFTER the id marker, which the grammar forbids; 2 writers and 7 tests pin it.** -- detail: `docs/ledger-notes/d05d.md` <!-- id:d05d -->
- [ ] [ROUTINE] **Move ROADMAP.md continuation lines into per-id notes -- under the ratified line grammar they are not large blocks to budget, they are INVALID.** -- detail: `docs/ledger-notes/40c0.md` <!-- gated-on:b048 --> <!-- id:40c0 -->
- [x] [ROUTINE] **The `id:0d7c` ratchet keys on HEAD-LINE length, so it is structurally blind to 79% of ROADMAP.md and can be fully GREEN while the file grows without limit.** -- detail: `docs/ledger-notes/b048.md` <!-- gated-on:f193 --> <!-- id:b048 -->
- [ ] [ROUTINE] **Make the ratification gate BIND: move it from the unit to the REMOTE, and make the queue self-verifying (option A+D, owner-ratified 2026-09-02).** -- detail: `docs/ledger-notes/3c04.md` -- detail: `docs/ledger-notes/7408.md` <!-- children-of:3c04 --> <!-- id:7408 -->
- [ ] [ROUTINE] **The length ratchet cannot detect its own STALE baseline, so a shrunk item silently keeps its old floor and a regrowth reads as grandfathered.** -- detail: `docs/ledger-notes/2654.md` <!-- id:2654 -->
- [ ] [ROUTINE] **257 ledger items have a TITLE that is itself over budget -- no relocation can shorten a title, so these need rewriting.** -- detail: `docs/ledger-notes/64f9.md` <!-- gated-on:ff7c,2654 --> <!-- id:64f9 -->
- [x] [ROUTINE] **Build the DIRECTIONAL round-trip validator the id:0d7c format ratified and nobody built -- a trimming pass must be provable, not eyeballed.** -- detail: `docs/ledger-notes/ff7c.md` <!-- id:ff7c -->
- [x] [ROUTINE] **`id:401c` is an append-only audit LOG occupying 42% of ROADMAP.md -- relocate its body under the ratified `id:0d7c` topology.** -- detail: `docs/ledger-notes/f193.md` <!-- id:f193 -->
- [ ] [ROUTINE] **`shape-prose` becomes an ERROR -- the closing act of the no-prose bar.** -- detail: `docs/ledger-notes/8524.md` <!-- gated-on:1608,2d17 --> <!-- id:8524 -->
- [ ] [INPUT - decision] **Three items carry a de-facto lane derived from BODY PROSE, which `classify-repo` reads as their real lane.** -- detail: `docs/ledger-notes/1254.md` <!-- id:1254 -->
