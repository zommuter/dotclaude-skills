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

- [ ] [HARD] `/relay . --parallel N` — **[RE-FRAMED 2026-07-24, owner-directed: parallel fan-out is now pool `pipeline()` in the Workflow loop (id:1f4f), NOT the retired off-Workflow driver (id:93fe). Verifiable children id:5367/2062 stay substrate-agnostic; off-Workflow live-residue id:7fae is moot.]** 🚧 @container DECOMPOSED 2026-07-20 (handoff relay-20260720-144400-4669) — TRACKING LINE ONLY, work the children: verifiable id:5367 (disjoint-path greenlight) + id:2062 (serial one-writer integrator) below. Tick this parent only when the children are closed. Full context TODO.md. <!-- id:ebbe -->
  - **DEAD GATE DROPPED 2026-07-31** — this line carried `<!-- gated-on:0534 -->`, but `id:0534` is `[x]` archived at `TODO.archive.md:432` (a `[HARD — pool]` mechanical-daemon lease item) and was **never** a ROADMAP item, so the gate was PERMANENT and could never open. Found by `roadmap-lint` rule 3(d) DEAD-GATE (`id:49e0`) within minutes of that rule existing — the fourth instance of the trap in one day, after `a955`→`87f5`, `8123`→`1a34` and `f6d5`→`8ba1`. **Dropped rather than re-targeted** because this line is an `@container` DECOMPOSED tracking entry with `children:` — it is not dispatchable in the first place, so a gate on it is meaningless twice over. Its children carry their own gates.
### 2026-07-21 promoted (consolidate handoff — mechanical-hop emitter wiring, id:176f child)

- [ ] [HARD — meeting] **HIGH PRIORITY — pool-launch proxy coupling (id:6176 made 5 hops proxy-DEPENDENT).** After id:6176, relay-loop.js emits `model:"bash"` for file-surface / quota / inject-take / heartbeat-beat / heartbeat-stop — these 404 at runtime UNLESS the mechanical-proxy is running AND `ANTHROPIC_BASE_URL` points at it (id:94b8). So running the autonomous pool (`/relay`) WITHOUT the proxy now BREAKS those hops — including **quota gating** (a 404'd quota check risks bypassing the stop → auto-spend) plus heartbeat / injection / decision-surfacing. Consolidate makes the proxy part of the loop, but the pool LAUNCH does not yet start it. **Decide + build (fail-CLOSED is the key property — never let a hop silently 404):** where/how to start the proxy + export `ANTHROPIC_BASE_URL` as part of pool launch — a preflight in the relay launcher that spawns `mechanical-proxy.py` on loopback + sets the env before the Workflow starts, and/or a health check that REFUSES to launch the pool if the proxy is unreachable. **UNTIL THIS LANDS: do not run `/relay` (autonomous pool) without the proxy up + base URL set.** Relates id:6176 / id:176f, the 2026-07-21 consolidate decision. <!-- children-of:176f --> <!-- id:6b35 --> — the `mechanical-proxy.py` short-circuit is CONFIRMED end-to-end (RELAY_LOG 2026-07-21 21:27): a Workflow `agent('```relay-mech\n<cmd>\n```', {model:"bash"})` is intercepted by the proxy, which runs `<cmd>` locally and returns its stdout with ZERO upstream inference. Convert each PROXY-ELIGIBLE mechanical hop in `relay/scripts/relay-loop.js` from `model:'haiku'` (a real Haiku inference call whose only job is to run one relay script) to `agent('```relay-mech\n<the exact relay-script command>\n```', {model:"bash", …})` — the command wrapped in a ```relay-mech fence so `_MECH_FENCE_RE` extracts it and `_command_allowed()` gates it.
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

- [ ] [INPUT — meeting] Use VISIBLE annotations, not HTML comments, for metadata that should render — see TODO.md <!-- id:ee62 -->
- [ ] [INPUT — meeting] Mechanize the keystone-unblock triage as a `/relay human` view (gate-graph fan-out ranking) (us… — see TODO.md <!-- id:c3f6 -->
- [ ] [HARD — meeting] Fake-Haiku mechanical-dispatch proxy — see TODO.md <!-- id:176f -->
- [ ] [INPUT — meeting] Meeting-as-relay-producer: route `/meeting` ledger writes through a worktree the integrator mer… — see TODO.md <!-- id:5a39 -->
- [ ] [INPUT — meeting] Full-loop relay REPLAY test — see TODO.md <!-- id:5bac -->
- [ ] [INPUT — meeting] Integrator destructive-cleanup ordering: under-the-lease vs release-first (proposed by the 2026… — see TODO.md <!-- id:6613 -->
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
- [ ] [INPUT — meeting] Visible-half-is-primary handoff discipline <!-- gate DISCHARGED 2026-08-20: was gated-on:ac7f, which is `- [x]` in ROADMAP.archive.md — the gate was satisfied, not dead; the lint only read it as DEAD because the archived item lost its live ROADMAP stub --> (meeting 2026-07-19-1058, fro… — see TODO.md <!-- id:2b49 -->
- [ ] [HARD — meeting] Ledger-invariant enforcement substrate — see TODO.md <!-- id:7a05 -->
- [ ] [HARD — meeting] Semver-bump enforcement + handoff bump-level annotation (meeting 2026-07-19-1212, user amendmen… — see TODO.md <!-- id:d1b2 -->
- [x] [ROUTINE] Review→execute chaining within a pool — **emit a `review→execute re-enqueue` EVENT into `relay-events.jsonl`** (RE-LANED from `[INPUT — access]` 2026-08-14, `/relay human .`, OWNER-DECIDED: "Mechanize it — emit an event") — see TODO.md <!-- id:b8ae --> (archived — see ROADMAP.archive.md)
- [ ] [INPUT — meeting] ``/`[MEETING]` tag-taxonomy completion (user 2026-06-15) — see TODO.md <!-- id:d0da -->
- [ ] [INPUT — access] Runtime write-matrix + heartbeat round-trip test for the relay-ro/relay-svc ACLs (id:02c7) — see TODO.md <!-- id:e8a3 -->
- [ ] [INPUT — meeting] Write-scope the LLM tier by uid: separate OS users for the relay supervisor/reviewer vs. the ex… — see TODO.md <!-- id:d03d -->
- [ ] [INPUT — meeting] Custom agent types (`.claude/agents/*.md`) per relay subcommand — see TODO.md <!-- id:931c --> **[2026-07-21 — evaluate UNDER the id:cae2 Agent-SDK audit (candidate #2), not piecemeal. Scope narrowed to the JUDGMENT roles (executor/reviewer/handoff/discover-shard); the mechanical variant id:f599 is SUPERSEDED by the model:"bash" proxy (id:6176/176f). Primary value = RELIABILITY (bake "load+follow the versioned contract" into the subagent prompt so it is not a forgettable per-dispatch step), not token cost. TWO DESIGN KEYS: (1) POINT don't DUPLICATE — the subagent prompt READs `relay/references/executor-contract.md` (vN) at runtime, never copies it (else derived-doc drift vs the ratified SOP); (2) USER-LEVEL install (`~/.claude/agents/` + `make install` symlink), never project-level, because relay runs the whole relay.toml set. `tools:` frontmatter scoping is ergonomic, NOT a security boundary (deny-probe-5937 — the OS-user tier is the real containment).]**
- [ ] [INPUT — meeting] Design tier-robust gate-discipline mechanisms (for a Fable session to consider): the 2026-07-02… — see TODO.md <!-- id:abe7 -->
- [ ] [HARD — meeting] Upgrade `consumer-enum.sh` from content-grep to real import/read-edge resolution (relay human r… — see TODO.md <!-- id:494f -->
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
    - Run 70 (2026-08-11-2039): window per the mechanical watermark = **0 commits**
      (`last_strong_ckpt`==HEAD), but that is FALSE — the last actual audit was Run 69
      (2026-06-30), so the true id:401c window is `7527cb1..HEAD` = **1709 commits**. Root
      cause filed as **id:da95**: a strong-EXECUTE checkpoint advances `last_strong_ckpt`
      (the id:ecce integrate carve-out was left half-closed), starving this pass ~6 weeks.
      Did NOT audit the 1709-commit window (unsound in one turn); instead filed id:da95 and
      ran a bounded pass over the newest UNWIRED engine surface (id:1f4f wave), yielding
      **id:ac8a** (disjoint-greenlight exact-string disjointness is fail-OPEN on subpath
      overlaps). `provision-worktree.sh`/`drain-integrate.sh` otherwise clean. Windows before
      Run 70 remain uncertified. See `docs/meeting-notes/2026-08-11-2039-strong-model-audit.md`.
    - Run 71 (2026-08-11-2145): first-seen code since Run 70's audit merge (`2c989a9..HEAD`) =
      **one feature**, the id:33b2 / id:a05c-option-B opt-in proxy stdin channel
      (`mechanical-proxy.py` +133/−8 + `test_mech_stdin_channel_33b2.sh` +78). Ran a full 3-pass
      adversarial audit (code / security / design-coherence) of that bounded diff — **the id:33b2
      code is CLEAN**: payload reaches `subprocess.run(input=)` never the `-c` string (no
      word-split/expand/subst — proven by the canary-inert test), the opt-in is genuinely
      AND-gated with the unchanged `_command_allowed()` gate, `_last_stage_relay_script` mirrors
      the command gate's last-stage identity, the two fences are disjoint by construction, and
      the single admitted member (`relay-status-publish.sh`) honours the STANDING OBLIGATION
      (`raw="$(cat)"`, never eval/source). **1 LOW forward-robustness finding filed → id:09e4**:
      the channel silently misdirects its payload when the admitted script is a NON-leading
      pipeline stage (`echo x | relay-status-publish.sh` — stdin goes to the shell/first stage,
      not the admitted last stage); not attacker-reachable (bare-invoked, trusted caller), fix =
      require single-stage when a stdin fence is present. 2 nits accepted (re-parse micro-inefficiency;
      `Optional[str]` hint). NOT fixed inline (needs a design choice + red-green test). id:da95
      (Run 70's watermark-starvation defect) untouched, stays open. Suite 383/0/1-xred (audit-only).
      See `docs/meeting-notes/2026-08-11-2145-strong-model-audit.md`.
    - Run 72 (2026-08-12-1413): first-seen code since Run 71's audit commit (`0454e8f..HEAD`,
      HEAD `1b7e9bb`) = the mechanical-proxy/provisioning hardening batch (~780 prod LOC / 10
      scripts + 12 tests: routed:a923 inject-scope, id:76d2/66d9 provision self-verify+gitignore,
      id:9e48 proxy-currency, id:93ac command-fence precedence, id:06a1/3222/a104 hop-failure
      visibility, id:ed3f lint coverage, verify-isolation `|| true` fix). Full 3-pass adversarial
      audit — **code CLEAN, security CLEAN, no inline fix**: provision emits `PROVISION-OK` only
      after both postconditions (fail-closed cert); mech-currency fail-closed on every unknown;
      id:93ac excises the stdin payload span before command extraction so a payload can't supply
      the command (verified the asymmetric-parse reasoning); INJECT_SCOPE is `[A-Za-z0-9._-]`-
      validated before shell splice, sentinel-on-refusal; relay-loop.js +270 is all
      visibility/scope/doc, zero control-flow change. **1 design-coherence finding TRACKED (not
      fixed inline)**: in-window archival of id:33b2 + id:93ac left stale `gated-on:33b2,93ac`
      markers on d4ca/e405 → roadmap-lint DEAD-GATE; NOT cleared here because naive clearing
      unblocks d4ca into dispatch ahead of the unresolved id:09e4 payload-misdirection, and the
      id:6b35 cluster is owner-gated (b0b1) — recommend the next handoff re-target to the real
      gate. Pre-existing lint debt (2b49→ac7f, ae08 DECOMPOSED-CONTAINER, 1b13 NO-ACCEPTANCE) and
      the correct owner-gated 540f/c179 DEAD-GATE noted, not this window's. Suite 394/0/1-xred.
      See `docs/meeting-notes/2026-08-12-1413-strong-model-audit.md`.

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

- [ ] [INPUT — decision] B2c-finalizer — CLOSE the dual-vocab window: convert this-repo ledgers + migrate ~30 lane tests + flip old-vocab→lint ERROR 🚧 GATED (DEP: 3ef7 + cross-repo re-tag) — **human 2026-07-11 (relay human): keep OPEN, gate re-confirmed.** Blocker is the cross-repo re-tag, NOT tooling (lane-convert id:4b37 shipped): 27 own repos + project_manager scan.py still emit old vocab (71 live `[HARD — pool|meeting|hands|decision gate]` tags), so flipping old→ERROR now would break them. This is `[INPUT — decision]` = a deliberate coordinated migration the human triggers (each repo's next `/relay handoff` runs `lane-convert`, then this closes), never autonomous pool work. **RE-CONFIRMED 2026-08-14 (`/relay human .`): KEEP GATED — gate clause re-dated so it stops re-surfacing as an undecided item on every triage.** Nothing has changed since the 2026-07-11 hold: the blocker remains the CROSS-REPO re-tag, not tooling (`lane-convert` shipped as `id:4b37`), with 27 own repos plus `project_manager`'s `scan.py` still emitting old vocab. Flipping old-vocab to a lint ERROR now would break every one of them. Considered and rejected: (a) converting THIS repo's ledgers + ~30 lane tests early while leaving only the ERROR flip gated — a partial close whose benefit does not survive the fleet still emitting old vocab, and which would need re-verifying at the real close anyway; (b) driving the fleet re-tag now as the work item — out of scope for a single-repo triage pass and a materially larger commitment than the owner was asked to make here. **The bleeding is already stopped** by the pre-commit lane-vocab ratchet, which BLOCKS newly-added old-vocab tags, so the gate is not accruing new debt — only holding existing debt. Re-open when the cross-repo re-tag actually happens. <!-- id:7df1 -->
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

- [x] [INPUT — access] **Build the ebd0 privacy pre-push gate** (design: meeting `docs/meeting-notes/2026-07-20-1241-privacy-gate-pre-push-ebd0.md` D1-D4) — `hooks/pre-push-privacy-gate.sh`: warn+LOG engine (print loudly + append findings to a log, exit 0, NEVER blocks), classify the push remote from its URL (public forge → scan; private host e.g. fievel → skip), scan only ADDED diff lines, read leak patterns+allowlist from a configurable PRIVATE file PATH (env/default under ~/.config, absent → no-op with a notice), best-effort `scan_pii` shell-out iff present. Plus a `make install-privacy-gate` target that wires global `core.hooksPath` (author the target; do NOT run the global install in a worktree). Hermetic test with a fixture pattern file + fixture public/private remote URLs. Private-file population = id:7fff (hands); warn→block flip = id:df87; 7a05 adoption later. — **BUILD SHIPPED (item stays OPEN until ACTIVE — tick-on-active invariant, chidiai case 2026-07-20-relay-integrator-ticked-high-priority-security) 2026-07-20 (execute[opus]+review SHIP):** hooks/pre-push-privacy-gate.sh (warn+LOG, D1-D4) + test + `make install-privacy-gate` target shipped, suite 276/0. **The gate is INERT until ACTIVATED** — activation = populate the private pattern file (id:7fff, hands) + run `make install-privacy-gate` to set global core.hooksPath (hands) + later warn→block flip (id:df87). Buildable core complete; activation tracked by id:7fff/df87. **ACTIVATION INSTALLED BUT NOT PROVEN — 2026-07-24 (relay human; owner call: KEEP OPEN).** Installed state VERIFIED: global `core.hooksPath` = `~/.config/git/hooks`, `pre-push` → `dotclaude-skills/hooks/pre-push-privacy-gate.sh` (symlink present), private pattern file present + populated (5686 B, 2026-07-20), id:7fff `[x]` archived. NOT ticked because the only 2 lines in the gate log come from a `/tmp` test fixture (2026-07-20) — no genuine public-remote push has exercised it. **Tick criterion: ≥1 log line from a real repo push** (installed ≠ proven; the tick-on-active invariant exists for exactly this item, chidiai `2026-07-20-relay-integrator-ticked-high-priority-security`). Block flip = id:df87; pattern curation = id:6afb. **OWNER-DECIDED 2026-08-14 (`/relay human .`): "Tick, but verify a live push first" — so it stays OPEN pending exactly one check.** Activation state verified this pass and all of it is in place: `core.hooksPath` → `~/.config/git/hooks`, `pre-push` symlinked to `hooks/pre-push-privacy-gate.sh`, `privacy-patterns.txt` populated (5686 bytes, 2026-07-20), and the log carries a REAL public-push line (`zkm-whatsapp.git`, 2026-08-11) alongside two fixture-remote entries. Both hands prerequisites (`id:7fff` pattern file, `make install-privacy-gate`) are done. The owner declined ticking on that evidence alone because the newest real entry was 3 days old — it proves the gate ran THEN, not now. **DONE-CHECK, and the trap in it:** the push must go to a PUBLIC remote. In this repo `origin` is `fievel:src/dotclaude-skills.git`, a private LAN host, which the gate SKIPS BY DESIGN — a push to `origin` would append nothing and must NOT be read as a failure. Use the `github` remote (`https://github.com/zommuter/dotclaude-skills.git`), then confirm a NEW line appears: `wc -l ~/.claude/logs/privacy-gate.log` (4 as of 2026-08-14) and check its newest timestamp. Not done this pass: a second session was concurrently committing to `main`, so pushing would have published its in-flight work. Tick on a fresh log line. The warn→block flip stays separately tracked as `id:df87`. **DONE-CHECK CORRECTED 2026-08-14 (same session) — the check written above is UNFALSIFIABLE; do not use it.** A live public push DID occur later in that session: `git-lock-push.sh` pushed `878574a..c5c58cf` to BOTH remotes, including the public `https://github.com/zommuter/dotclaude-skills.git`. The gate log stayed at 4 lines. That is NOT evidence of failure — and not evidence of success either: `hooks/pre-push-privacy-gate.sh` is a **FINDINGS** log (header D3: "print loudly + append findings to a log, exit 0"), so a CLEAN scan appends nothing. "A new line appears" therefore distinguishes nothing in the normal case, and the owner's "verify a live push first" cannot be discharged that way. **A correct check must prove the hook EXECUTED, not that it found something.** Options, cheapest first: (a) run the push with the hook's stderr visible and NOT truncated (the notice lines it prints on skip/scan are the signal — the run above was piped through `tail`, so any notice was discarded, which is the second time that pipe destroyed evidence this session); (b) temporarily point `PRIVACY_GATE_LOG` at a scratch file and push a throwaway branch carrying a KNOWN fixture pattern, confirming a line lands (never commit the fixture); (c) add a one-line "scanned <remote> <n> refs" heartbeat to the log so future activation checks are answerable at all — this is arguably worth doing anyway, since the current design makes "is the gate live?" unanswerable from its own artifacts. STILL NOT TICKED, and now for a better-understood reason than before. — **✅ TICKED 2026-08-26 (owner-authorized; TODO twin ticked in the same pass).** The 2026-08-18 blocker (`id:293f`'s local `core.hooksPath` override shadowing the global hook) is discharged — verified live, `git config --local --get core.hooksPath` exits 1. The hook demonstrably EXECUTES here (~8 observations this session, stderr visible and untruncated: `privacy-gate: … is a PRIVATE host — skipping leak scan`), and the PUBLIC-remote scan path is proven from THIS repo — the log grew 4 → 38 lines with **34 naming `https://github.com/zommuter/dotclaude-skills.git`**, dated 2026-08-20..23. Both the execution notice and real findings lines exist, so the 2026-08-14 unfalsifiability trap (a clean scan appends nothing to a FINDINGS log) does not apply. Warn→block flip stays `id:df87`; pattern curation stays `id:6afb` (38/50). <!-- id:ebd0 --> (archived — see ROADMAP.archive.md)
## Mechanical-tier + arg-guard findings (relay session 2026-07-28, run relay-20260728-104330-9348)

- [ ] [ROUTINE] **`write-relay-status`: haiku → `model:'bash'`** 🚧 GATED (DEP: id:33b2 — needs the stdin channel BUILT; the decision itself is settled, id:a05c option B — AND id:93ac, the command-fence precedence boundary: converting this hop is exactly what makes 93ac live, since this payload is cross-repo ledger prose) <!-- children-of:6b35 -->  **GATE RE-TARGETED 2026-08-13**: the `gated-on:33b2`/`gated-on:93ac` markers were STALE — both targets are `[x]` DONE and archived to `ROADMAP.archive.md`, which `resolve-gates.sh:36` does NOT include in its resolution set (`ROADMAP.md ∪ TODO.md ∪ TODO.archive.md`), so they read as dangling and the item was blocked by accident rather than on purpose — the `id:47f7`(b) archived-gate class, live. NOT cleared: the 2026-08-12 strong-model audit (`ROADMAP.md:1128`) explicitly declined naive clearing because it would unblock this into dispatch ahead of the unresolved `id:09e4` payload-misdirection while the `id:6b35` cluster is owner-gated on `id:b0b1`. Re-targeted to those two REAL gates, both open and both in `TODO.md` (hence resolvable). This keeps the item blocked — it does NOT make it actionable. <!-- gated-on:09e4 --> <!-- gated-on:b0b1 --> <!-- id:d4ca -->
  - **Why it qualifies**: id:0d31 already collapsed this hop to "pipe one blob to one command" — `relay-status-publish.sh` does all deterministic work (path resolve + c34a guard, claims peek, burnup render, atomic flock'd write, event append). The Haiku agent contributes nothing but latency, cost, and drift risk on a **write path**, and it fires every round.
  - **Why it is BLOCKED today (verified 2026-07-28, not theorised)**: the payload rides in the command string as a heredoc, and `_command_allowed()` refuses it three independent ways — `_has_unquoted_sequence_operator` (payload is multi-line), `_has_unquoted_redirection` (`<<'RELAY_STATUS_EOF'`), and the backtick/`$(` substring scan. Those scans are **quote-blind**, so even a safely single-quoted payload is refused; measured against the live predicate: `echo 'a; b; c' | relay-status-publish.sh` → False, `echo 'see \`foo.sh\`' | …` → False, `echo 'run $(date)' | …` → False. A bare `relay-status-publish.sh --path … --run …` with no payload → **True** (the script is already allowlisted), so it is purely the payload transport that fails.
  - **Do NOT "fix" this by flipping the model**: a refused command fail-opens to the real model, and `"bash"` is not a real model → 404. Because status content embeds repo/item prose (the queued / blocked / REVIEW_ME sections routinely carry code spans), this would break the status write on essentially every substantive round. Fail-CLOSED is the property to preserve (id:6b35).
  - **Unblocks when** id:33b2 lands; then the change is: fence carries the bare one-liner, payload moves to the stdin channel, `model: 'bash'`.
  - **Done-check**: `_command_allowed()` accepts the emitted command; a round-trip test writes a status body containing backticks, `$(`, `;` and newlines and asserts the file content is byte-identical to the payload.

## Executor-death cluster — promoted from TODO 2026-07-28 (parent meta id:93cc, open since 2026-06-22)

### 🔴🔴 ABSOLUTELY URGENT — owner directive 2026-08-01. Work these two FIRST, ahead of every other item in this file.

> **Why, in one line:** the parent `id:93cc` recurred live on 2026-08-01 (run
> `relay-20260801-213927-29875`) and killed this repo's own `execute` child with
> `Prompt is too long`, parking 481 lines of unverified work as
> `relay/orphan/relay-20260801-213927-29875-execute`. Until these land, **every `execute`
> dispatch on `dotclaude-skills` is at risk of the same death** — the repo with the largest
> ROADMAP and the most `[ROUTINE]` items blocks its own executors first.

- [ ] [HARD — decision gate] **Record the ACTUAL child death cause — relay child deaths are currently untracked** (promoted from TODO `routed:9c91`) <!-- children-of:93cc --> <!-- id:61fa --> — 🚧 GATED (auto, id:3801; route:decision-gate): Transcript-parsing half needs an architecture call: parse in the off-Workflow driver (id:65f9/2ec4) vs. route through a mechanical model:'bash' hop — the Workflow sandbox itself has no filesystem access to read agent-<id>.jsonl. — needs a /meeting — **FRESH EVIDENCE 2026-08-10 (run `relay-20260810-103858-20326`)**: fired again on this repo's own `execute` unit. The handback recorded the hardcoded generic string; the REAL cause (`Prompt is too long`) was present in the Workflow's `<failures>` block but discarded before it reached `handbacks[].reason`, so the status file and the turn summary both showed only the anonymous terminal-failure text. Recovering the actual cause took manual forensics (`show-ref` → `git show --stat` on the parked branch). **This instance also refutes the natural reading that the recurrence is a dispatch-time overflow the id:4f9b gate should have caught**: `roadmap_bytes` was 254,087 (~63.5k tok), so the gate's estimate landed near 77k against its 100k cap and it correctly did NOT fire — and the child then created its worktree and produced 566 committed lines (`lint-embedded-literals.mjs` + its test, `id:ef9e`) *before* dying, i.e. the death was in-session context growth, not prompt assembly. So id:4f9b closes the dispatch-time half of id:93cc and this is the uncovered run-time half — which is precisely why the death-cause record this item specifies is load-bearing: without it, the two halves are indistinguishable in the ledger and the wrong remedy (`roadmap-archive.sh`) gets recommended.
  - **Defect**: `relay-loop.js:1913` hardcodes `terminalFailReason = 'child agent failed/skipped (API error or terminal failure)'` and DISCARDS the real cause. Every recurrence needs manual transcript forensics and nobody can see the rate. The cause is already on disk: the last entry of `<workflowDir>/agent-<id>.jsonl` carries `isApiErrorMessage:true` plus the literal text (e.g. `Prompt is too long` for loderite run `relay-20260728-112417-3898`, agent `a7106578a0da7e9f6` — 181 entries, 491 KB, died 12 min in, mid-`Read REVIEW_ME.md offset 920`).
  - **Do this FIRST in the cluster**: it is the only item that makes the others' effect measurable. Every other item here fixes ONE cause; none of them counts occurrences.
  - **RED spec**: `tests/test_child_death_cause_61fa.sh` (`# roadmap:61fa`, hermetic — fixture `agent-*.jsonl` in `mktemp -d`). On a null child report, parse the transcript tail and record into the handback reason AND `relay-events.jsonl`: the actual terminal error string, the token count, and a tool histogram. Fixtures: a transcript ending in `isApiErrorMessage:true` + `Prompt is too long`; one ending in a normal result (must NOT be reported as a death); a truncated/corrupt transcript (must degrade to the generic reason, never crash the integrator).
  - **Also emit a running per-cause tally** so recurrence is visible without forensics (mechanize-first / loud-failure heuristic).
  - **SCOPE EXTENDED 2026-07-28 (adversarial review) — add re-dispatch SUPPRESSION, not just recording.** Verified: the `report == null` terminal-fail path (`integrate()`, `relay-loop.js:1908–1922`) pushes a handback but does **NOT** stamp the `noWorkNegCache` — that only fires on `contract_met=false` + route none (`:1940`). Combined with the discovery signature cache reusing an unchanged verdict, **the same repo re-dispatches into the identical death next round**, which is consistent with the 2× same-day deaths on 2026-07-26. Recording the cause without gating on it means the tally grows while quota burns. Add: on a context-death handback, suppress re-dispatch of that repo until the cause is cleared (e.g. its ROADMAP shrinks) — the loud-failure half of the mechanize-first heuristic.
  - **⚠️ PREMISE PROBLEM — found by the 2026-07-28 executor survey, must be resolved before this is worked.** This item assumes `relay-loop.js` can parse the child's `agent-<id>.jsonl`. **It cannot: `relay-loop.js` runs inside the Workflow sandbox, which has NO filesystem access** (confirmed by `test_backstop_fire_log.sh`'s own comment). So the transcript-parsing half is not implementable where this item places it, and likely belongs in the **off-Workflow substrate** (id:65f9 / id:2ec4) — an unresolved architecture question, not a same-repo `[ROUTINE]` fix. **Re-scope before dispatching**: either (a) move the parsing to the off-Workflow driver/daemon and keep only the *recording* side here, or (b) route the cause out through a mechanical hop that CAN touch disk (`relay-state-write.sh` / the `model:"bash"` tier). The **re-dispatch suppression** half may still be in-sandbox (it is a cache stamp, not file I/O) and could be split out as the independently-landable piece.
  - **Why [ROUTINE]** *(now questionable — see the premise problem above; may need re-laning once the substrate question is settled)*: read-side parsing plus two existing sinks and one cache stamp; no contract or model change.

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

- [ ] [HARD] **Convert the two remaining payload-trapped haiku hops once the stdin channel exists** 🚧 GATED (DEP: id:33b2, id:93ac) — **APEX lane (owner 2026-07-28), same reasoning as id:33b2**: this item's job includes ADMITTING two scripts to `STDIN_ALLOWED_SCRIPTS`, which is exactly the deliberate, reviewable act option B exists to force. Having the cheap tier perform that admission would hollow out the ruling — the gate's value is the judgement exercised at admission time, not the edit itself. <!-- children-of:6b35 -->  **GATE RE-TARGETED 2026-08-13**: the `gated-on:33b2`/`gated-on:93ac` markers were STALE — both targets are `[x]` DONE and archived to `ROADMAP.archive.md`, which `resolve-gates.sh:36` does NOT include in its resolution set (`ROADMAP.md ∪ TODO.md ∪ TODO.archive.md`), so they read as dangling and the item was blocked by accident rather than on purpose — the `id:47f7`(b) archived-gate class, live. NOT cleared: the 2026-08-12 strong-model audit (`ROADMAP.md:1128`) explicitly declined naive clearing because it would unblock this into dispatch ahead of the unresolved `id:09e4` payload-misdirection while the `id:6b35` cluster is owner-gated on `id:b0b1`. Re-targeted to those two REAL gates, both open and both in `TODO.md` (hence resolvable). This keeps the item blocked — it does NOT make it actionable. <!-- gated-on:09e4 --> <!-- gated-on:b0b1 --> <!-- id:e405 -->
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
## Diagrams: enforce what is already drawn (2026-07-28)

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
  - **The INTERIM ask above was DISSOLVED then UN-DISSOLVED the same session (D3 → D3-A).** Dissolved because a `RELAY_STATUS.md` row cannot cover its own residual — a SIGKILLed front door has no writer, and the Workflow is gone too. Un-dissolved because the `--fabled` pass verified that D3's dissolution rested on D removing `release` from the classifier's reach, and **it does not**: `releaseLease` is per-unit and mid-round (`:2415`), not teardown. Was **gated on id:e62c** — whether classifier-blocked per-unit releases can recur depended on F2. **F2 RESOLVED 2026-08-11 (id:e62c CLOSED, branch (1)): classifier-blocked per-unit releases CAN recur** — the classifier fires at the `agent()` dispatch layer regardless of whether the proxy is in path, so a per-unit `releaseLease` (`:2415`) is reachable by it whenever it degrades to inference, and even a hardcoded `model:'bash'` release was blocked in a proxy-in-path run (see id:e62c's verdict). This **VINDICATES D1-A's front-door EXIT-ONLY teardown** (a front-door shell command is not an `agent()` dispatch, so no classifier sits in its path) — id:89d6 (the `claim.sh release --run` sweep) and id:54be (the trap) are the load-bearing fix, not the in-Workflow refusal. The reopen trigger's "isn't a classifier block" exclusion is **STRUCK** (it excluded by definition the recurrence F2 could not rule out). Rider that stands regardless: the real detector for a lease held by a dead run is the already-open **id:33d3/id:9000** claim-liveness item.
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

- [ ] [ROUTINE] **`mech-preflight.sh`: mode-a AND mode-b become launch REFUSALS; the `abort` token actually aborts** (D1/D2) 🚧 GATED — **OWNER GATE (owner directive 2026-07-31): this refusal does NOT land until the owner explicitly says so.** Rationale: the refusal makes the relay pool unrunnable in any session launched WITHOUT `ANTHROPIC_BASE_URL`, i.e. every `/remote-control` session (id:b0b1) — today mode-a is merely costly (~12 hops degrade to Haiku), after the refusal it is fatal. Do NOT treat the discharge of the e62c gate as authorisation to build; that gate is technical, this one is the owner's. (Prior DEP: id:e62c — the fail-closed rationale must survive F2; a branch-(1) verdict removes the classifier-exposure argument but NOT the cost / hardcoded-no-fallback-discover-hops arguments, so re-read e62c's verdict before implementing) <!-- gated-on:b0b1 --> <!-- e62c half DISCHARGED 2026-08-20: e62c is `- [x]` in ROADMAP.archive.md; STILL BLOCKED on b0b1, which lives only in TODO.md and was never promoted --> <!-- children-of:6b35 --> <!-- id:540f -->
  - **Today's behaviour, verified**: `mech-preflight.sh preflight` exits **0 for all three modes** and the caller branches on the stdout token. Mode-a emits `fallback-haiku`, and `relay-loop.js:248` reduces it to `const MECH_MODEL = MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'` — degrading ~12 mechanical hops into real Haiku inference. Mode-b emits `abort`, and `relay-loop.js:243`-ish logs *"WHOLE SESSION DEGRADED"* **and keeps `model:"bash"`** — it fails OPEN. **The token has been lying since id:4239 shipped.**
  - **Why mode-b's refusal is entailed a fortiori**: in mode-a the real API IS reachable (the fallback at least executes); in mode-b `ANTHROPIC_BASE_URL` points at a DEAD proxy, so *nothing* is reachable and a Haiku fallback is impossible. If mode-a refuses to launch, mode-b refusing follows. Leaving mode-b a warning is the "loud detection whose resolution silently no-ops" anti-pattern.
  - **What to build**: mode-a and mode-b both become **launch refusals** at the front door — the helper emits a refusal signal the front door cannot ignore (non-zero exit and/or a distinct token), the loud stderr warning naming the relaunch env (`ANTHROPIC_BASE_URL=http://127.0.0.1:61843`) is PRESERVED verbatim, and the front door does **not** launch the Workflow. `proceed` is unchanged.
  - **Contract**: `preflight` against a **stubbed** mode-a probe emits a refusal and the front door does not launch; same for a stubbed mode-b probe; a stubbed healthy probe still emits `proceed` and launches. Stub via `MECH_PROBE=<fixture>` — the helper already takes that override and is documented hermetic (no writes, no cache, no `~/.claude` touches).
  - **Tests**: extend `tests/test_mech_preflight.sh` (do not fork a parallel file — it already stubs all three modes); add the front-door-does-not-launch assertion as a new `# roadmap:540f`-headed case there or in a sibling if the existing header must stay `4239`.
  - **Done-check**: the mode-a and mode-b cases assert refusal, the healthy case still passes, then tick and run full `make test`.
  - **Out of scope**: the `MECH_MODEL` ternary deletion and the self-attesting hop (both id:c179); the seven non-eligible `model:'haiku'` hops; any third enforcement layer.

- [ ] [ROUTINE] **`relay-loop.js`: self-attesting first mechanical hop; delete the fallback ternary** (D2-A, SUPERSEDES D2's token assertion) 🚧 GATED — **OWNER GATE (owner directive 2026-07-31): the ternary deletion does NOT land until the owner explicitly says so** — deleting the `MECH_FALLBACK === 'fallback-haiku' ? 'haiku' : 'bash'` ternary IS half the refusal (it removes the only path that lets a no-`ANTHROPIC_BASE_URL` session run at all), so it carries the same id:b0b1 `/remote-control` conflict as id:540f and is gated identically. Note this line previously carried NO `gated-on:` marker at all despite its 🚧 prose — the mechanical edge engine read it as ungated; that is now fixed. (Prior DEP: id:e62c — this hop doubles as the F2 probe, so run e62c's observation first and record its verdict; implementing before then risks encoding the wrong rationale) <!-- gated-on:b0b1 --> <!-- e62c half DISCHARGED 2026-08-20: e62c is `- [x]` in ROADMAP.archive.md; STILL BLOCKED on b0b1, which lives only in TODO.md and was never promoted --> <!-- children-of:6b35 --> <!-- id:c179 -->
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

- [ ] [INPUT — decision] **Wire the built-but-unreferenced fan-out machinery (`disjoint-greenlight.sh` + `drain-integrate.sh`) into `relay-loop.js`** @container <!-- children-of:1f4f --> <!-- id:ae08 --> — 🚧 GATED (auto, id:3801; route:hard-split): DECOMPOSED into seams id:02b2, id:99e5, id:5b12 — pick those, not this. ae08 bundles 3 scopes incl. a tick-ownership contract inversion (executor-contract v11→v12); too large for one turn — decompose into greenlight-wire / drain-integrate-route / tick-ownership seams (deps b099/923b already closed; design ratified meeting 2026-07-26-1922).
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

- [x] [INPUT — decision] **Pre-register the burn-ranking decision rule — THE GATE that orders id:a955 and id:3ca7** <!-- children-of:1f4f --> <!-- id:87f5 --> — **PRE-REGISTRATION MADE 2026-08-18 (`/relay human .`, OWNER-DECIDED) — this item's human half is DELIVERED, so it is TICKED.** The rule, fixed BEFORE any number is looked at: **rank levers by their target phase's share of PARALLELITY-WEIGHTED WALL-CLOCK** (`relay-econ.py`'s third lens — per-category UNION of `[start,end]`), **not by cost**; **n = all retained runs**; **promote a lever iff its phase clears ≥25% of that share**; **order = descending share**. Per-phase attribution stays REQUIRED (a whole-run total-burn ranking provably cannot order levers targeting different phases). **Why wall-clock over cost** (the owner's reasoning, recorded so `id:4438` cannot quietly substitute the easier axis): the banked `relay-econ.py` finding is that status+scaffold are a bigger share of WALL-CLOCK than of COST — i.e. they run at low concurrency and sit on the critical path. Ranking by cost would systematically under-weight exactly the phases worth mechanizing. The accepted trade-off is explicit: a lever may be promoted that saves time but little money. **Reconciliation against the banked 47.6% discover baseline is still REQUIRED of `id:4438`** — in numbers, agreeing or disagreeing, never ignored. **GATE TOPOLOGY CORRECTED in the same pass:** `id:a955` and `id:3ca7` were `gated-on:87f5`, which under the 2026-08-14 split would have released BOTH into dispatch the moment this pre-registration landed — before any ranking exists, which is the precise outcome the gate was filed to prevent. Both are re-targeted to `gated-on:4438` (the item that actually PUBLISHES the ranking). This is a mechanical consequence of the owner's already-ratified split, not a new decision. **The `Contract (unchanged)` bullet above is STALE** — "a published per-phase ranking that ORDERS a955 and 3ca7" is now `id:4438`'s contract, not this item's; this item's contract was the pre-registration alone. (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Run the burn measurement and publish the per-phase ranking (measurement half of `id:87f5`)** <!-- children-of:87f5 --> <!-- gated-on:87f5 --> <!-- id:4438 --> (archived — see ROADMAP.archive.md)
- [x] **[HARD] [INTENSIVE — disk-io] Standalone warm-vs-cold copy timing on a build-dep repo (H3)** <!-- id:3c9d --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`top_intensive`'s human-gated exclusion list is OLD-VOCAB ONLY — a new-vocab human-gated `[INTENSIVE]` item will be auto-dispatched** **SECOND INDEPENDENT INSTANCE — `routed:2d94` from loderite, folded in here rather than filed separately (2026-08-14).** In loderite run `relay-20260814-133435-24323` a HARD-child brief **re-derived the pool-lane enumeration by raw grep** instead of consuming `gather-repo-state`'s already-resolved list, grepped only the OLD `[HARD — pool]` spelling, found 0, and **refused 5 real bare-`[HARD]` items** — a whole dispatch round wasted on a repo that had work. Same root cause as this item's `top_intensive` finding: the lane-vocab migration left old-spelling greps behind in the dispatch path, and every correctly re-laned item widens the hole. Two instances found independently within hours, in different scripts, is the argument for fixing the CLASS. **Adds to this item's scope**: the HARD-child brief must be handed the resolved list and FORBIDDEN from re-deriving it (mechanize-first — the resolved list already exists; re-deriving it by grep is the defect). Sibling detector `id:bfbf` (`routed:9371`) is what would have caught this on its first occurrence: a handback claiming zero-dispatchable must enumerate the ids it considered. Source: `docs/meeting-notes/2026-08-14-1338-empty-dispatch-container-and-vocab.md`. <!-- routed:2d94 --> **OPEN QUESTION carried in from `routed:34a2` (loderite, same session): should `@owner-gated` join the `open_hard_pool` exclusion list, or does it carry no dispatch meaning?** Answer it while fixing the exclusion list, since that is the same code. **`routed:34a2` also carries a REFUTATION that must not be re-filed**: the claim that `gather-repo-state`'s `open_hard_pool` omits `@container`/gated exclusions is FALSE — `gather-repo-state.sh:435-480` already excludes parked headings, `@container` (`id:d808`), typed `gated-on:` edges (`id:1022`), any 🚧, `blocked*`, and the recurring audit; and `:395-409` maps `[HARD]` to `[HARD — pool]` before comparing. Do NOT re-open that. Note the tension worth resolving here: that mapping means `open_hard_pool` handles both spellings correctly while `top_intensive`'s exclusion list does not — the fix should make them consistent. <!-- routed:34a2 --> — DONE 2026-08-14 — covered by tests/test_dispatch_vocab_owner_gate.sh. top_intensive's exclusion is now vocab-complete across BOTH spellings including the fourth [INPUT — author] lane, @owner-gated is a first-class exclusion in top_intensive/open_hard_pool/is_human per the owner ruling, and the HARD child is HANDED gather's resolved open_hard_pool_ids and forbidden to re-derive it by grep. Verified on the real loderite incident fixture (run relay-20260814-133435-24323): all five bare-[HARD] shapes now resolve, and open_hard_pool is deliberately 4 not 5 because 0873 carries a mid-line @owner-gated. routed:34a2's REFUTATION was honoured — open_hard_pool's existing exclusions were verified correct and left alone. The @owner-gated OPEN QUESTION it carried is answered: it IS an exclusion. <!-- id:7517 --> (archived — see ROADMAP.archive.md)
- [x] [HARD] **L1 — mechanize the integrator into one `integrate.sh` relay-mech hop** <!-- children-of:1f4f --> <!-- gated-on:4438 --> <!-- id:a955 --> — 🚧 GATED (auto, id:3801; route:hard-split): DECOMPOSED into seams id:9e50, id:087b — pick those, not this. Mechanizing the whole integrate() Sonnet agent (11 steps + verbatim aa93/6e02 safety rules + relay-loop.js rewire + forced-failure tests) exceeds one turn on the merge-to-main critical path; split into build-script then rewire seams. — **GATE RE-TARGETED 2026-08-18 (`/relay human .`): `gated-on:87f5` → `gated-on:4438`.** `id:87f5` was re-scoped by the owner on 2026-08-14 to the PRE-REGISTRATION alone, with the measurement+ranking split out as `id:4438`. The pre-registration landed 2026-08-18 (wall-clock share, n = all retained runs, promote-iff ≥25%), so `87f5` is now `[x]` — and this item's gate must follow the RANKING, not the rule that describes it, or ticking `87f5` would release this into dispatch before any ordering exists. Nothing about the gate's strength changes: this item stays parked until `id:4438` publishes. — **CLOSED 2026-08-21, SUPERSEDED BY ITS SEAMS (owner-ratified).** Both seams shipped and merged: `id:9e50` built `relay/scripts/integrate.sh` (all 11 deterministic steps, fail-closed) and `id:087b` rewired `relay-loop.js` `integrate()` onto it via the mechanical hop — **no LLM agent remains in `integrate()` at all**, which is MORE than this item asked (it reserved a semver micro-hop as an LLM agent; the owner ruled 2026-08-21 that the micro-hop be mechanized too). Merged at `relay-ckpt-20260821-0855`, suite green. **Its gate `id:4438` is CLOSED** — the burn ranking published — so the parked-until-ranking condition is discharged. Ratified by the owner 2026-08-21 after `roadmap-lint` flagged this line as a DECOMPOSED-CONTAINER whose seams were both already `[x]`. **Lane drift recorded, not hidden:** this item carried `[HARD]` in TODO.md and `[INPUT — decision]` in ROADMAP.md; the CHECKBOX agreed, so `orphan-scan --cross-ledger` (which compares checkbox state only) never flagged it — normalised to `[HARD]`, which is what the work actually was. Sibling `id:3ca7` shares the `4438` gate and is therefore now UN-GATED. (archived — see ROADMAP.archive.md)
## 2026-07-31 handoff C2 — execute→review cadence starvation (+ two watermark/registry defects)

> Promoted from `TODO.md` reusing each item's existing id (single-id-two-views — no duplicate
> minted). Items id:907e / id:8123 / id:6217 come from the owner-ratified meeting
> `docs/meeting-notes/2026-07-31-1231-execute-review-cadence-starvation.md`; id:c500 and id:069b
> are independent defects found the same day. **Work id:907e FIRST** — it is that meeting's
> re-ranked PRIMARY fix (D3/A4) and the only decision that addresses the observed incident.
> Every line/behaviour claim below was re-verified against the working tree at promotion time
> (2026-07-31, base `b92c4ab`); one claim inherited from the meeting was found FALSE and is
> corrected in place under id:8123.

- [ ] [INPUT — decision] **Extract `isDryRound`/`workCreated` into ONE shared definition — CROSS-FILE, via a generation step; record the drain-path gap MOOT-BY-RETIREMENT** <!-- id:6217 --> — 🚧 GATED (auto, id:3801; route:decision-gate): **TWO independent blockers — the /meeting must reconcile BOTH (gate_reason previously recorded only (B); corrected 2026-08-13 by `/relay human`).** **(A)** spec assertion 4's `grep -q 'keep byte-equivalent'` is UNSCOPED over the whole of relay-loop.js and contradicts the spec's own assertion 5: the literal appears in FIVE comments (998/1065/1087/1185/2090), four unrelated to this item, so it can never pass without the blanket sweep assertion 5 exists to forbid — fix is to LINE-SCOPE it to id:4ca8's line 1185, or an owner call on whether the other four inline-copy comments are in scope. **(B)** RED spec requires literal one-declaration count across both files; relay-loop.js's no-import sandbox constraint makes that structurally unreachable without an unverified eval/Function-constructor escape-hatch — owner must confirm sandbox posture or relax the assertion to match the byte-verified generation mechanism already designed. Resolving (B) toward a generation-verification shape would naturally re-scope (A); do NOT let a partial fix re-dispatch the item while the other blocker stands. — needs a /meeting
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

## Human triage 2026-08-01 (relay human `.`, owner-decided)

- [ ] [INPUT — decision] **`--fabled` (B): fire the Fable adversarial pass BEFORE each `AskUserQuestion`, not only at the closing pass** (owner-decided, `/relay human` 2026-08-01 — the id:8df5 escalation trigger fired twice and the owner chose (B); (C), the full multi-pass, is NOT built) <!-- children-of:7e87 --> **TRIGGER FIRED TWICE MORE — 2026-08-14, both routed in from other repos (evidence appended, not re-filed as new items).** **(1) `routed:43a8` (lodelore, `docs/meeting-notes/2026-08-14-1223-loderia-creation-history.md`)**: a closing Fable-5 pass returned **8 FORCED amendments** to already-ratified decisions against a ≥2 threshold. Its deepest finding was a foundational cosmology fork that four decisions had been built on unnoticed — **invisible to every earlier pass because it only existed once the later decisions had been ratified**. That is the sharpest argument yet for the split this item is about: a per-decision pass (B) structurally CANNOT catch a conflict that does not exist until two decisions coexist, so B and C complement rather than substitute, and neither replaces the closing pass. **(2) `routed:690b` (leAIrn2learn, `docs/meeting-notes/2026-08-14-0959-metro-map-nn-weight-distance-scoping.md`)**: a `--fabled` closing pass returned **6 forced-amendment findings**, amending all 4 ratified decisions. **Its filer attached an honest caveat that should be preserved and not quietly dropped**: a scoping meeting (4 decisions, 2 batches, no code) is the shape MOST favourable to a closing pass, so treat 6 as an UPPER bound, not a typical yield. Taken with the four firings already recorded here, the base-rate caveat is dead but the effect size is not yet well estimated — the honest reading is "fires reliably, magnitude uncertain and probably shape-dependent". Sequencing note: the owner already ruled 2026-08-14 (on `id:43c8`) that the deterministic premise-check `id:f346` is built BEFORE the (B) per-decision pass, because the forced findings cluster in the unchecked-premise class that mechanism targets — `43a8`'s cosmology-fork finding is a genuine counter-example to that clustering (no grep would have caught it), so it is evidence for (C), not against the sequencing. <!-- routed:43a8 --> <!-- routed:690b --> **TRIGGER FIRED AGAIN — 2026-08-19, routed in from leAIrn2learn (evidence appended, not re-filed as a new item).** A `--fabled` closing pass returned **5 forced-amendment findings** against the >=2 threshold, in `docs/meeting-notes/2026-08-19-1241-post-r3-disposition-emotions-formal-rigor.md`. **Why this firing carries more weight than its predecessors, and what it costs an earlier caveat:** its findings were grounded in verified errors in ALREADY-SHIPPED code and docstrings, not in fresh-design gaps. That directly weakens the 2026-08-14 "inflated by being a scoping meeting" caveat recorded on the sixth firing above — that caveat argued a no-code scoping meeting is the shape MOST favourable to a closing pass and so treated its yield as an upper bound. A shipped-code firing is the opposite shape and still cleared the threshold, so the effect is not confined to greenfield scoping. Running count: 4 / 4 / 5 / 7 / 6 / 5. The base-rate question is now settled in favour of "fires reliably across shapes"; magnitude remains shape-dependent and is still not well estimated. Sequencing unchanged: the owner ruled 2026-08-14 (on `id:43c8`) that the deterministic premise-check `id:f346` is built BEFORE the (B) per-decision pass. <!-- routed:4702 --> <!-- id:8df5 --> — 🚧 GATED (auto, id:3801; route:decision-gate): id:8df5 collides across ledgers: ROADMAP:1478=per-decision Fable pass (2026-08-01), TODO:415=deterministic premise-check (children-of:43c8, 2026-08-10 owner "mechanize FIRST, LLM pass deferred"). ROADMAP line is stale-superseded; reconcile the id + confirm scope before any build. — needs a /meeting — the pre-registered trigger (≥2 findings forcing the reopening/amending of an already-ratified decision in one session) fired **2026-07-26** (count 4, meeting `docs/meeting-notes/2026-07-26-1922-relay-efficiency-in-repo-parallelism.md`, caveated at the time as an unusually large surface) and again **2026-07-29** (count 4 on a deliberately smaller surface — 3 decisions, no engine rewrite — meeting `docs/meeting-notes/2026-07-29-0911-mechanical-hop-proxy-coupling.md`), which is exactly the "stronger signal on a normal-sized meeting" the pre-registration named. Both firings share one shape: a **factually wrong premise survived into ratification** and was caught only afterwards (2026-07-29 F1: the teardown premise was wrong — `releaseLease` is per-unit at `relay-loop.js:2415`, not teardown; F2: the incident diagnosis did not fit the code, becoming id:e62c).
  - **What (B) is**: a Fable pass that runs against each decision's stated premises + options *immediately before* the `AskUserQuestion` that ratifies it, so a wrong premise is refuted while the owner can still act on it — instead of at the closing pass, after ratification, where today's `id:7e87` pass sits.
  - **Acceptance**: a meeting whose decision rests on a checkably-false premise surfaces that refutation in the SAME turn as the question, not in a closing-pass finding; the pass never blocks or answers the question (it informs it — Fable stays an optional bonus reviewer, never a gate, per `[[feedback-fable-optional-not-gate]]`); a Fable-unavailable session degrades to today's behaviour with a loud notice, never a stall.
  - **Out of scope**: (C) the full multi-pass — explicitly NOT built by this decision; building it later is a fresh owner call, not a discharge of this trigger. Also out of scope: making Fable a required gate anywhere.

## Handoff C2 2026-08-01 (relay handoff, owner-scoped 5-item promotion)

> Owner-scoped promotion of exactly five already-filed TODO items (ids REUSED —
> single-id-two-views). The scan found 13 promote- and 90 surface-disposition items; the
> surface set is deliberately NOT touched here (id:5eb3 — the `human` verdict's mechanical
> filer owns it). Rationale and full evidence for each item stay in `TODO.md`; these entries
> are the execution spec only.

- [ ] [INPUT — meeting] **@container — relay children can write the target's MAIN checkout; "Work EXCLUSIVELY in that worktree" is prose with zero enforcement** (4th+ occurrence, INBOUND `routed:f91a` from loderite 2026-07-30) <!-- children:d464,34b7 --> <!-- routed:f91a --> <!-- id:f91a -->
  **RE-LANED 2026-08-14 (`/relay human .`, owner-directed inspection): `[ROUTINE]` → `[INPUT — meeting]`, gated on `id:d464`.** A review box flagged it as an open `[ROUTINE]` with NO RED spec (`grep -rl 'roadmap:f91a' tests/` empty), i.e. not executor-ready. Inspection settles WHY: this is a **pure container** — it carries `<!-- children:d464,34b7 -->` and no work of its own, so there is nothing for a spec to specify. Child `id:34b7` (the DISSOLUTION half — parent creates the worktree before dispatch) is `[x]` DONE; child `id:d464` (a PreToolUse hook denying writes into a claimed repo's main checkout) is `[INPUT — meeting]`, explicitly "DISCUSSION ONLY, deliberately NOT queued", blocked on an unresolved afk-compat question. So f91a closes by CHILD CLOSURE (`id:46f6`), not by execution, and its only open dependency is a meeting-lane item. Leaving it `[ROUTINE]` left a specless trap in the dispatchable pool. Do NOT author a RED spec for it. **No `gated-on:d464` marker is written here, deliberately**: `id:d464` lives only in `TODO.md` and is explicitly never queued, so a typed gate pointing at it is a PERMANENT one and `roadmap-lint` correctly reports it as a DEAD-GATE (verified — adding it took the repo from 9 to 10 warnings). This is precisely the deliberately-held-gate class the `<!-- owner-hold:REASON -->` marker is being built for (`id:d119` ships the grammar + linter recognition; `id:b8e8` applies it). Give this item an `owner-hold:` marker once `id:b8e8` lands; until then the gate is recorded in prose only.
  - **This is a CONTAINER, not a dispatchable unit** — marked `@container` so no executor picks it up (`classify-repo.sh`'s `is_human` excludes the marker, id:0cf5). It carries the problem statement and the damage trail; the work lives in its two children. Promoted for VISIBILITY of the epic alongside its queued child, per the owner-scoped 2026-08-01 handoff.
  - **Verified defect (see `TODO.md` id:f91a for the full evidence)**: `relay-loop.js:2413` builds agent options as `{ label, phase, schema }` plus `opts.model` — across every `agent()` call in `relay/scripts/*.js|mjs` the keys are 16×label, 16×model, 15×phase, 2×schema, **zero `cwd`, zero `isolation`**. The child is handed `main checkout: ${unit.path}` (`relay-loop.js:1958`, and again in the resume prompt at `:1988`) with no warning, then told `Work EXCLUSIVELY in that worktree` (`:1963`). Detection (`verify-isolation.sh`, id:f682) fires only AFTER the write, and the residue surfaces as an *unattributed* "main checkout dirty" in a later, innocent run.
  - **Children and their status** — `id:34b7` (dissolution: parent creates + provisions the worktree pre-dispatch) is the queued executor work, promoted below. `id:d464` (a PreToolUse deny hook) carries a standing owner directive **"DISCUSSION ONLY — DO NOT PROMOTE TO ROADMAP AND DO NOT BUILD"** and is deliberately absent from this roadmap; do not build it from this entry.
  - **Close condition**: tick when `id:34b7` is closed AND the owner has ruled on `id:d464`. It has no test of its own; `tests/test_parent_creates_worktree_34b7.sh` is the spec for the queued half.
  - **SUPERSESSION NOTE**: `TODO.md` id:f91a still carries a 2026-07-30 status line reading "NOTHING IS QUEUED … do not promote either to ROADMAP". That hold is superseded for `id:34b7` only, by the owner-scoped 2026-08-01 handoff that produced this section. `id:d464`'s hold STANDS. Flagged in `REVIEW_ME.md` for owner confirmation.


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

- [ ] **[INPUT — decision]** Wire disjoint-greenlight.sh plan into the drain-mode fan-out planner — seam of id:ae08 (auto, id:3801) <!-- id:02b2 --> — 🚧 GATED (auto, id:3801; route:decision-gate): Needs /meeting: per-unit file-set provenance + which same-repo units are concurrency-eligible under the review-barrier — else the greenlight call is a forbidden dead branch. — needs a /meeting
  - **Acceptance**: grep -c 'disjoint-greenlight' relay/scripts/relay-loop.js is non-zero and the call is reachable from a drain-mode (--only) round's planner (a real call site, NOT the existing line-3009 comment or a dead branch); fleet-mode fan-out is byte-unchanged (enforceOneUnitPerRepo untouched outside --only, id:dc5b).
  - **Done-check**: tests/run-tests.sh tests/test_disjoint_greenlight.sh (unmodified) green AND node --check relay/scripts/relay-loop.js clean
  - **Context**: relay/scripts/relay-loop.js (drain-mode planner / round dispatch near enforceOneUnitPerRepo, ~line 1167-1189) + relay/scripts/disjoint-greenlight.sh
- [ ] **[INPUT — decision]** Route same-repo drain-mode integration through drain-integrate.sh (serialized one-writer safety net) (after id:<seam-1 id>) — seam of id:ae08 (auto, id:3801) <!-- id:99e5 --> — 🚧 GATED (auto, id:3801; route:decision-gate): Wiring drain-integrate.sh into relay-loop.js's shared integrate() path depends on seam-1 id:02b2 (decision-gated /meeting on drain-mode fan-out planner + review-barrier concurrency); acceptance invariant D3a undefinable until then, and done-check tests already pass so there is no RED guard for the guard-less core-loop change. — needs a /meeting
  - **Acceptance**: grep -c 'drain-integrate' relay/scripts/relay-loop.js is non-zero and reachable from the drain-mode integration path (enqueueIntegration); a review unit never runs concurrently with any other unit in its own repo; integrate checks are NOT relaxed because greenlight proved disjointness (design rule D3a).
  - **Done-check**: tests/run-tests.sh tests/test_relay_integrate_contain.sh AND tests/test_drain_serial_integrator.sh (both unmodified) green AND node --check relay/scripts/relay-loop.js clean
  - **Context**: relay/scripts/relay-loop.js (enqueueIntegration ~line 1001 and the integration-drain path) + relay/scripts/drain-integrate.sh
- [x] [ROUTINE] **Teach the generic `roadmap-archive.sh` to LEAVE a one-line stub per moved item** (recurrence-prevention for loderite `id:2ab3`) <!-- routed:f833 --> **RED SPEC LANDED 2026-08-13** (`relay-ckpt-20260813-2332`): `tests/test_roadmap_archive_leaves_stub.sh` (`# roadmap:cd9c`, 4 triangulated hermetic cases — stub emission + grammar, two different gate paths with per-item titles/ids, cross-run round-trip, and `archive-closed.sh`). Verified RED against an UNMODIFIED `roadmap-archive.sh` (`FAIL: id:1a2b no longer resolves from the LIVE ROADMAP.md — archiving left NO stub`), and non-vacuous in both directions via a throwaway stub-emitter prototype that turned cases 1-3 green while case 4 stayed red. Suite 420/0/3-xred, this file EXPECTED-RED. IMPLEMENTER: the spec is the contract — do not weaken it. **TWO IMPLEMENTATION CONSEQUENCES, both verified against the code 2026-08-13 (do not skip):** (1) `relay/scripts/relay-loop.js:2614` — the integrator prompt asserts the archiver "moves each `- [x]` block (and any heading this run empties) into ROADMAP.archive.md verbatim" and instructs the agent not to "fix up" what it moved. Under (a) the archiver ALSO writes a stub into the LIVE file, so that sentence becomes a stale claim-about-code the moment this ships — refresh it in the same commit (the CLAUDE.md "a claim about CODE behaviour is a derived doc" rule). (2) **MEASURED COST to the `id:4f9b` prompt-size remedy.** `relay/scripts/prompt-size-gate.mjs:72` prescribes running `roadmap-archive.sh` as THE remedy when `ROADMAP.md` is too large to dispatch a child ("REMEDY: run roadmap-archive.sh … to move the done items into ROADMAP.archive.md"). Under (a) archiving no longer shrinks the live file nearly as much: one stub line accrues per archived item, permanently. Measured on THIS repo 2026-08-13: **333** archived top-level items vs a live `ROADMAP.md` of 216,993 bytes / 1,602 lines — so a full-history stub set would add roughly a third again to a file whose size already triggers the id:4f9b skip. This is a genuine cost of (a), NOT a re-opening of it (owner ruled (a); recorded per the decision-provenance rule). The implementer should say explicitly whether a companion mechanism is needed — e.g. prune a stub once no open gate/typed edge still references its id, or stub only ids that are actually referenced — and if none is added, update the id:4f9b remedy text so it stops promising headroom it no longer delivers. **↳ Both consequences above are now TRACKED ITEMS, not just prose here** (filed 2026-08-13, since a consequence recorded only inside another item's body is invisible to every checkbox-driven collector): `id:b30c` (`gated-on:cd9c`) — refresh the `relay-loop.js:2614` verbatim claim; `id:36f7` (owner decision) — whether (a) ships bare or with a stub-pruning / selective-stub companion, given the measured `id:4f9b` headroom cost. The cd9c implementer MUST state which `id:36f7` option they assumed. <!-- id:cd9c --> — **OWNER RULED (a) on 2026-08-13**, re-laned `[INPUT — decision]` → `[ROUTINE]`. **Decision provenance:** owner, this session, verbatim: "(a) and also consider cartulary interaction on this". Branch (b) (delegate to a per-repo archiver when one exists) is REJECTED-as-chosen; it is recorded, not adopted — the deciding argument was N=1: a fleet sweep of all 51 relay.toml own repos (2026-08-13) found loderite is the ONLY repo with a per-repo archiver and the ONLY one emitting the stub suffix, so (b)'s override seam had exactly one consumer, below the `id:415b` determinism gate (>=2 consumers or a logged recurring cost). **Acceptance**: `relay/scripts/roadmap-archive.sh` (and `archive-closed.sh`) write a one-line stub into the LIVE ledger for each item they move, using the grammar `12e9825` already hard-codes — `- [x] <title> <!-- id:XXXX --> (archived — see ROADMAP.archive.md)` — which under (a) is PROMOTED from a borrowed loderite constant to the fleet standard, since the generic script now owns it. The already-shipped `stub_line_re` guard (`12e9825`) is the necessary precondition and must keep passing: a stub written by run N must classify `keep` in run N+1, so `tests/test_roadmap_archive_stub_guard.sh`'s cross-run idempotence case becomes the round-trip test for this item too. **CARTULARY INTERACTION — checked against the code, 2026-08-13, all four axes CLEAN** (`~/src/cartulary/scripts/prose-tail-scan.py`): (1) the prose-tail bare-ref count is UNAFFECTED — `COMMENT_RE.sub()` (:143) strips HTML comments BEFORE `BARE_ID_RE` (:144), so a stub's `<!-- id:XXXX -->` is counted by `MARKER_RE` and never as a bare prose ref; (2) the `routed:1c50` qualify-new-prose-refs ratchet does NOT fire on stubs for the same reason, and because 1c50 keys on FILE-LEVEL token presence a stub actually keeps the token PRESENT in `ROADMAP.md`, so archiving stops producing a presence-removal delta (a small improvement); (3) the `routed:ed25` collision census (98 colliding of 3581) is UNAFFECTED — `token_repos` maps token -> SET of REPO NAMES and collision is `len(set) >= 2`, so the same token in `ROADMAP.md` + `ROADMAP.archive.md` within ONE repo collapses to a single entry, and stubs mint no new ids; (4) `LEDGER_FILES` (:46) already includes BOTH `ROADMAP.md` and `ROADMAP.archive.md`, so the marker census loses nothing today and GAINS live-file resolvability, which is precisely what `orphan-scan --cross-ledger` needs. **CONSEQUENCE TO PROPAGATE (the one real cost of (a))**: live+archive id duplication becomes INTENTIONAL and UNIVERSAL fleet-wide. Any detector using "same id in both the live ledger and its archive" as a damage signal will false-positive after this ships — including the ad-hoc sweep used on 2026-08-13 to answer "was any repo other than loderite affected". Audit such heuristics in the same pass; the correct damage signal becomes "a FULL BODY (not a stub) present in both". Relates `id:3262` (scan_ids now reads `ROADMAP.archive.md`, which (a) makes load-bearing since ids will live in both files). **Out of scope**: loderite's data-restore half (`id:154a`); deciding whether loderite keeps its own archiver (under (a) it may, but the generic path no longer depends on it). (archived — see ROADMAP.archive.md)
## Review-derived promotion 2026-08-14 (relay review, reverse-handoff §5b)

- [x] [ROUTINE] **`md-merge.py update-ids` must ASSERT the id:6059 multi-marker REFUSAL — redefined 2026-08-20 (owner ruling, `/relay human --all`), supersedes the original last-vs-first own-id spec.** ORIGINAL SPEC (now retired): resolve an item's OWN id as the LAST `<!-- id:XXXX -->` on the line, never the first. That spec CONFLICTED with the already-shipped id:6059 design — `meeting/md-merge.py` REFUSES any line carrying multiple anchored `id` markers (raises `AmbiguousOwnId`) rather than resolving own-id positionally at all, so the old test case (A) (a write aimed at the line's trailing OWN id must APPLY) could never pass against the intended behaviour. The executor correctly BLOCKED rather than gaming it (relay-ckpt-20260819-1449). **OWNER DECIDED 2026-08-20: option (2) REDEFINE, not close** — the refusal is currently pinned only by md-merge.py's own code, with no spec asserting it is deliberate rather than incidental; cc7e now owns that assertion. NEW CONTRACT: author a fresh RED spec asserting that `update-ids` RAISES `AmbiguousOwnId` (and writes nothing) for a line bearing >1 anchored `<!-- id:XXXX -->` marker, and that a single-marker line still applies normally; retire/replace `tests/test_md_merge_own_id_last.sh`, whose current assertions encode the retired spec. Re-lane [INPUT — decision] → [ROUTINE]: with the direction decided this is ordinary executor work. Re-checkable: `grep -n AmbiguousOwnId meeting/md-merge.py`; the new spec must be RED before the assertion exists and GREEN after. <!-- id:cc7e --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Make `@owner-gated` a FIRST-CLASS exclusion in `lib-roadmap-sections.sh` — the PREREQUISITE for `id:6446`** — DONE 2026-08-14 — covered by tests/test_owner_gated_first_class_f391.sh (4 fail -> 10 pass). @owner-gated is now a separately-defined, standalone-anchored marker composed into the parked-heading vocab, so the id:6446 anchoring can land WITHOUT un-protecting owner-gated work; the test includes a faithful id:6446 stand-in mutation proving exactly that. id:6446's gate is now RESOLVABLE. The parked-vocab ANCHORING item stays gated and untouched. <!-- id:f391 --> (archived — see ROADMAP.archive.md)
- [ ] [ROUTINE] **Parked-section vocab match is a bare substring — a heading that merely mentions `archive`/`done`/`gated`/etc. in descriptive prose parks its whole section** 🚧 **GATED 2026-08-14 (`/relay human .`) on `id:f391` — DO NOT DISPATCH.** This item was promoted and made executor-actionable earlier the same session on the owner's greenlight; `routed:ed4f` (loderite) then arrived and showed that landing it as written would **silently un-protect owner-gated work**. The parked-heading vocab `(gated|deferred|done|icebox|archive|parked)` is matched as an unanchored substring, so a heading containing the literal `@owner-gated` is parked ONLY because that string contains `gated` — verified 2026-08-14: `@owner-gated` appears nowhere in `lib-roadmap-sections.sh`. Loderite has three open items (`f303`, `d385`, `6e7a`) whose dispatch protection rests on that coincidence. Anchoring the match — exactly this item's job — removes it. **The substring defect and the owner-gate protection are the same mechanism**, so the fix cannot be applied blind. `id:f391` makes `@owner-gated` a first-class exclusion with a fixture that must pass BOTH before and after this item; once it lands, this ungates and the acceptance below is unchanged. The `id:cd9c` heading rename remains the interim workaround in the meantime. <!-- gated-on:f391 --> <!-- id:6446 -->
  - **Promoted 2026-08-14 by `/relay human .` (OWNER-DECIDED: "Confirm rename + promote id:6446").** Same id as the TODO twin at `TODO.md` (single-id-two-views, D2) — no duplicate token minted. Found 2026-08-14 during the `id:cd9c` review; the TODO line already carried a full acceptance + done-check, carried across here verbatim rather than re-authored.
  - **The defect**: `relay/scripts/lib-roadmap-sections.sh`'s `ROADMAP_PARKED_HEADING_VOCAB=(gated|deferred|done|icebox|archive|parked)` is applied as an **unanchored substring** search over the heading line. So `## User-injected promotion 2026-08-13 (id:baf1) — archive-path stub design call` parked the live, owner-ruled, ungated `[ROUTINE]` item beneath it: `classify-repo.sh` reported `actionable_routine_open:0` while a landed RED-spec item sat dispatch-ready, and **nothing errored** — the item was simply never dispatched. Same class as the `gated?`-substring FP fixed under `id:259f`.
  - **Acceptance**: a fixture ROADMAP with a heading like `## … — archive-path stub design call` above an open `[ROUTINE]` item classifies that item as **actionable** (not parked), WHILE a genuine `## Gated / deferred` / `## Done` / `## Archive` bucket heading still parks its section. Both cases are required — the negative (a real parking heading still parks) is the load-bearing one, since a fix that merely stops matching would silently un-park every deliberately-parked section in the fleet.
  - **Approach (not prescriptive)**: make the match *intentional* — the vocab word must be a standalone token adjacent to the heading marker, or the heading must be a recognized parking bucket — rather than any occurrence anywhere in the title prose.
  - **Done-check**: the new RED case fails against today's substring match and passes after the anchor fix; then full `make test` green.
  - **Context**: `relay/scripts/lib-roadmap-sections.sh` is the SINGLE parked-heading definition; consumers are `classify-repo.sh`, `gather-repo-state.sh`, `roadmap-lint.sh` — verify the fix at the lib, and check all three consumers still agree. Add cases to the lib's existing section tests. Relates `id:259f` (sibling substring-FP, shipped), `id:bb32` (single-definition reconcile), `id:cd9c` (the item this FP hid; its heading rename is a workaround this item makes unnecessary).


## Test-harness throughput 2026-08-14 (/relay human, owner-directed)

- [x] [ROUTINE] **LANDED 2026-08-19 — measured, not assumed.** **Parallelise `tests/run-tests.sh`** <!-- id:f69b --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Make the fast subset first-class: `make test FILES=…` / `make test-changed`** <!-- id:d3f8 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`relay-doctor` check 9: distinguish ABANDONED main-checkout residue from IN-FLIGHT residue via live-claim state** <!-- id:aee5 --> (archived — see ROADMAP.archive.md)
- [x] [HARD] **`scan-routed.sh --apply` silently DELETED inbox items whose token was merely quoted in a sibling item's prose — the twin check now requires the token to be a line's OWN marker** <!-- id:c97c --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Author the systemd units + hardening for the two relay service users (authoring half of `id:8e7a`)** — see TODO.md for the full spec <!-- children-of:8e7a --> <!-- id:5bef --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Re-dispatch of an item that already has a prior attempt's branch carrying commits must REFUSE and surface, and integrate must compare against any sibling branch for the same item.** Reuses the existing TODO id (single-id-two-views; no duplicate minted) — `TODO.md` stays the prose SSOT for the incident trail, this item is the executor spec. <!-- routed:d99c --> <!-- routed:678c --> <!-- id:dd7d --> (archived — see ROADMAP.archive.md)
## meeting-question-guard was a live no-op — flush-wait fix + live confirmation (2026-08-19, `id:2419` second round)

- [ ] [ROUTINE] **`@owner-verify` — confirm the `meeting-question-guard` flush-wait actually fires in the LIVE harness** <!-- id:cf2d -->
  - **Context — the defect this closes out.** The `Stop` hook shipped 2026-08-13 for `routed:29bc`/`id:2419` **blocked nothing for six days**: `~/.claude/logs/meeting-question-guard.log` held 50 firings, every one `WARN … trailing segment is empty`, with **zero BLOCK and zero SKIP**. Cause: the Stop hook chain runs **before** the harness appends the just-ended turn's assistant lines to the session JSONL, so `trailing_segment()` was structurally always `[]`. Measured on a live session transcript (2026-08-19): the cost logger — first in the same Stop chain — recorded `wc -l` = 83, and line 83 was the `attachment` following a `user` tool_result; the turn's own 3159-char assistant `text` was line **84**, appended afterwards. On a second live transcript the same ordering hid a **7515-char bare-prose meeting turn** — exactly the defect the hook exists to block.
  - **Why the green suite missed it.** Every fixture in `tests/test_meeting_question_guard_29bc.sh` writes the trailing assistant entry **before** invoking the hook — a state the live harness never presents at Stop time. 16/16 green tested a premise, not the environment.
  - **Fix (LANDED this session).** `await_trailing_segment()` in `hooks/meeting-question-guard.py` polls until the turn appears and settles (`DEFAULT_WAIT_SECS=3.0`, `POLL_SECS=0.05`, `SETTLE_SECS=0.30`, budget overridable via `MEETING_STOP_GUARD_WAIT`). A turn that never appears is logged at a distinct **`NOFLUSH`** level and fails open — loudly, never silently (`id:4347`). The meeting-open check runs **twice**: cheaply on the first read so a non-meeting Stop pays no wait, and again on the settled entries so the turn that WRITES the meeting note is not judged as still inside the window. `tests/test_meeting_question_guard_flush.sh` is the missing negative control (6 tests; verified to FAIL 3/6 against the pre-fix hook, reproducing the production `WARN … trailing segment is empty` line).
  - **What is NOT yet established, and is the whole point of this item.** The tests prove the wait works when a writer appends **concurrently**. They do **not** prove the live harness appends the turn while a Stop hook is still running rather than strictly **after** all Stop hooks return. If it is the latter, every meeting turn pays the 3 s budget and the guard is still a no-op — it would just say so at `NOFLUSH` instead of `WARN`. That premise could not be settled from existing data (both orderings are consistent with the second-precision timestamps available) and was deliberately **not assumed**.
  - **`@owner-verify` because it is an observability claim, not a code claim** (global CLAUDE.md §"Poolability is decided by observability"): it can only be produced by exercising a real `/meeting`, which the pool cannot manufacture.
  - **Acceptance** — after the next real `/meeting` on a non-Fable session:
    - GIVEN `~/.claude/logs/meeting-question-guard.log` WHEN grepped for that session THEN it contains at least one `OK` or `BLOCK` line (the turn became visible) — and **no** `NOFLUSH` line for a turn that did end.
    - GIVEN a `NOFLUSH` line IS present THEN the poll premise is REFUTED for this harness: do **not** raise the budget blindly — reopen with the measured `waited` value and route the redesign to the owner (a Stop hook may simply be unable to see its own turn, in which case the guard needs a different event or a deferred-by-one-turn design, both of which are behaviour changes).
    - GIVEN a non-meeting session THEN no wait is paid (already covered mechanically by `tests/test_meeting_question_guard_flush.sh` test 5, <1000 ms).
  - **Done-check**: record the observed log lines in this item, tick the checkbox, then `tests/run-tests.sh` fully green.

- [x] [ROUTINE] **`tests/test_run_tests_parallel.sh` is itself load-flaky — its `-j 1`/`NESTED` seriality checks intermittently observe 2 when they require 1** <!-- id:f875 --> (archived — see ROADMAP.archive.md)
## Human triage 2026-08-19 (`/relay human .`, owner-decided)

- [x] [ROUTINE] **Mechanical `core.hooksPath` shadowing detector across the relay own-set** — PROMOTED from TODO 2026-08-19 (owner-decided), reusing the existing id per single-id-two-views. It was `promote`-classified by `unpromoted-scan` but lived ONLY in `TODO.md`, so the pool could never author or execute it — while `id:293f`'s sweep names it as its gate, making that gate structurally unopenable rather than merely pending. That dead stop is why this promotion happened. A repo that sets a LOCAL `core.hooksPath` silently loses **every** global hook, because `core.hooksPath` REPLACES rather than overlays; on 2026-08-18 that held for **7 of 51 own repos**, each unguarded by both the pre-push privacy gate and the pre-commit lane-vocab ratchet, one pointing at a *different repo's* hook directory (a rename residue). The condition recurs on every clone/move/rename, so a one-off manual sweep rots. **Consume the canonical own-set primitive** (`relay/scripts/lib-own-repos.sh`'s `own_repos`, honoring `# path:` overrides) — **never a `~/src` glob, never a re-derived repo list** (the `id:7877` defect class). Report each repo's local `core.hooksPath` (empty = correct) and classify **EMPTY-SHADOW** (points at a dir with no non-sample hooks → gate silently hollowed, actionable) vs **DELIBERATE** (real repo-local hooks → an owner call, since fixing means merging them into the global dir, not unsetting). Read-only `git config` + a directory listing; **no writes, no unsetting** — the detector reports, the human acts. <!-- id:2bc6 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`md-merge.py`: add insert-relative-to-id and an IN-LOCK line transform — the mandated flock path cannot express what agents actually need** (INBOUND `routed:f88b` from loderite, NARROWED by its own author's correction `routed:9aaf`; filed 2026-08-19 `/relay human .`) — **read the correction first, the original claim is overstated.** `f88b` said md-merge has "NO line-prefix/lane rewrite"; that is wrong — `update-ids` accepts a full replacement `{"id":X,"line":…}` which CAN rewrite a lane, and with `--commit` does the write and the scoped commit under the same flock (verified 2026-08-19 re-laning a loderite item). What is genuinely missing: **(a) insert-relative-to-id** — place a new item before/after a given id. Absent, and it is the operation that forced every unflocked hand-rolled read-modify-write observed: ids-not-found are appended at EOF, which is the wrong placement for a seam that must sit beside its siblings. **(b) a TOCTOU-free line EDIT** — the caller must read the line OUTSIDE the lock to compute the replacement, so a concurrent append to that SAME id between read and lock is silently overwritten (last-under-lock wins). The existing `append` mode has no such window and should be preferred wherever it suffices; add an in-lock transform (replace-prefix-by-id, or a regex-sub applied under the lock) so whole-line edits stop needing an out-of-lock read. **Evidence this is not theoretical:** 5 unflocked RMW writes to a loderite `ROADMAP.md` while an autonomous pool was concurrently integrating and running an archive sweep on the same file — no corruption that time, verified after the fact, i.e. luck not design. It recurred in THIS repo the same day: the session that filed this item appended a ROADMAP section and edited TODO.md by hand, outside the flock, for exactly the reason (a) names. **CLAUDE.md states ROADMAP.md/TODO.md/REVIEW_ME.md are written by BOTH the relay pool and `/meeting` and are NOT `merge=union`.** <!-- routed:f88b --> <!-- routed:9aaf --> <!-- id:f26d --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **UNTRACKED-only dirt no longer blocks relay dispatch or integration; TRACKED dirt still does** — SHIPPED 2026-08-20 (owner-ratified, `/relay human --all`). **The defect, measured not hypothesised:** `gather-repo-state.sh` set `dirty=true` from a bare `git status --porcelain`, which counts untracked `??` entries, so `classify-verdict.sh`'s `dirty_block` returned `verdict=blocked`. Two stray untracked campaign assets (1 MB of PNG/SVG, created 2026-08-01) made **yinyang-puzzle unreachable by the pool for 19 days** — no checkpoint after `relay-ckpt-20260731-1801` — while it held the fleet's largest open REVIEW_ME queue. Nothing surfaced it; it was found only because the owner asked why repos get skipped. Fleet snapshot at the time: 51 clean, 1 untracked-only-blocked, 0 tracked-dirty. **Fix:** `gather-repo-state.sh` emits a new `dirty_untracked_only` (mirroring the `dirty_lock_only` precedent, `id:bae5`, which already established that some dirt is dispatchable); `classify-verdict.sh` excludes it from `dirty_block`; `clean-tree-gate.sh` skips `??` entries so DISPATCH and INTEGRATE agree — narrowing only one would dispatch work that then cannot merge. **Safety argument:** a child works in its own `git worktree add` clone and never touches the main checkout's untracked files, and `git merge` itself REFUSES any merge that would overwrite an untracked file, so integrate safety is enforced by git rather than by this verdict. **`id:aa93` is INTACT:** tracked dirt still blocks, the gate still never stashes/checks-out/resets/cleans, and untracked files still SURVIVE. `RELAY_STRICT_UNTRACKED=1` restores the old strict defer. **One existing assertion was explicitly SUPERSEDED, not silently weakened:** `tests/test_integrator_foreign_dirty.sh` (`roadmap:aa93`) asserted untracked ⇒ exit 2; it now asserts exit 0 plus a new strict-mode case, with the supersession and its rationale written into the test header. Tests: `tests/test_untracked_only_dispatchable_27b4.sh` (8 checks, both directions incl. mixed-dirt negative control). Suite: 450 passed, 0 failed. — ⚠️ **SHADOW PARITY: this change BREAKS relay-core's Lean shadow until it adopts the same rule — routed the same day.** Confirmed live on loderite (an untracked meeting note from a concurrent `/meeting`): `bash=execute`, `lean=blocked` ("Dirty main working tree (uncommitted, non-lock-only)"), logged as MISMATCH in `~/.claude/logs/relay-core-shadow.jsonl`. **Bash stays authoritative** (the shadow is observe-only), so nothing is wrong with the shipped behaviour — but every repo carrying a stray untracked file will now log a mismatch until relay-core changes too. Routed to relay-core via the shared inbox with the exact contract (the new `dirty_untracked_only` boolean + the amended `dirty_block` expression) and a pointer to `tests/test_untracked_only_dispatchable_27b4.sh`. Expected and benign in the meantime; do NOT "fix" it by reverting the bash side. <!-- id:27b4 --> (archived — see ROADMAP.archive.md)
- [x] **[HARD]** Build relay/scripts/integrate.sh — standalone mechanical integrator (all 11 deterministic steps, fail-closed LOUD), tested in isolation — seam of id:a955 (auto, id:3801) <!-- id:9e50 --> (archived — see ROADMAP.archive.md)
- [x] **[INPUT — decision]** Rewire relay-loop.js integrate() to dispatch integrate.sh via the mechanical hop (id:6176 relay-mech/MECH_MODEL), leaving only the semver micro-hop as an LLM agent (after id:seam-1) — seam of id:a955 (auto, id:3801) <!-- id:087b --> — 🚧 GATED (auto, id:3801; route:decision-gate): Done-check requires 3 tests unmodified, but noop_guard + ckpt_merged_tip structurally assert the very Sonnet integrator prompt this item removes (Acceptance vs Done-check contradict); also seam 9e50/integrate.sh omits tick/archive/6b/push-seed/siblingBranches — owner must rule before build. — needs a /meeting — **SHIPPED + VERIFIED + MERGED 2026-08-21** (`relay-ckpt-20260821-0855`, merge `c31a401`): all five previously-LLM-only behaviours ported into `integrate.sh`, **no LLM agent remains in `integrate()`** (the only `agent()` call is the `MECH_MODEL` fence, and `test_relay_integrator_noop_guard.sh` now actively REFUSES `sonnet|haiku|opus|fable` on that dispatch). Suite green at 453 at merge time. The Acceptance-vs-Done-check contradiction was resolved by the owner-ratified D1 amendment (2026-08-21): the two structurally-blocking tests were rewritten to assert the mechanical dispatch, preserving their real invariants. Bump trigger ships fail-closed pre-merge (`HANDBACK[bump]` exit 30) per the owner's ship-as-is ruling. **TICK WAS LATE — the box stayed `[ ]` for hours after merge because the executor was told to leave it for owner verification and the ticking was then missed; while unticked, `tests/test_integrate_mechanized_ports_087b.sh` counted as EXPECTED-RED, so a genuine regression on the merge-to-main path would not have failed the suite.** (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **A POST-PUSH integrate failure is no longer misread as a retryable defer** — PROMOTED from TODO 2026-08-21 (blast-radius review; the item was TODO-only, promoted with the SAME id per the single-id-two-views rule). `integrate.sh` now emits a STDERR handback block that names the class: PRE-push exits print `handback=<step>` + `landed=false` and NEVER a `merged=` line, while the POST-push exits (retire 28, state-write 29, strong-state 33) print `handback=<step>`, `landed=true`, `merged=<sha>`, `ckpt=<tag>`, `push=pushed`, `remaining=<steps that did NOT run>` and `ckptRecorded=<bool>`. STDERR because `mechanical-proxy.py` DISCARDS a non-zero-exit child's stdout. `parseIntegrateResult` returns a THIRD outcome, `landedUnfinished`, distinct from `deferred`; the integrate call site gives it its own branch that SURFACES the unit as a handback naming the merged sha, ckpt, failing step and unrun steps — and never re-merges it (a retry would fail forever at merge/isolation). `push(27)` stays DEFERRED (the push failed, the remote is untouched) and every pre-push exit behaves exactly as before. The stale-`last_ckpt` symptom is closed by a best-effort in-handback reconcile of `relay.toml last_ckpt` to the already-pushed tag, reported as `ckptRecorded`. Tests: `tests/test_integrate_post_push_handback_5fe2.sh` (real git fixtures, one PRE-push and one POST-push failure plus push(27) and the happy path, asserting the caller's parsed state differs). Suite green at 461. Relates id:087b, id:9e50. <!-- id:5fe2 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **The `id:4f9b` prompt-size gate UNDER-COUNTS by ~50% — it never counts `TODO.md`** — see `TODO.md` for the measured incident. `relay-loop.js:2466-2473` (inline copy of `relay/scripts/prompt-size-gate.mjs`) estimates `round((promptChars + roadmapBytes)/4) + 12000`; the child prompt also embeds `TODO.md`, which is absent from the estimate. loderite: ROADMAP 350,698 B → est. 99,674 tok → ALLOW (under a 100,000 budget by 326) → child died `Prompt is too long`, recorded as the generic failure string `4f9b` exists to eliminate. ROADMAP+TODO = 197,685 tok, ~2× budget. <!-- id:b018 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Orchestrator writes the ledger SLICE to a tmp file and hands the child a PATH — the child can no longer over-read, because the bytes are not in its prompt** (owner proposal 2026-08-21) — today the prompt embeds/points at the whole `ROADMAP.md` + `TODO.md` and a prose instruction TELLS the child to slice; a prose instruction the child can get wrong is not a guard. <!-- id:e68f --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **URGENT — prompt-size gate must measure the `id:e68f` SLICE when one exists (this repo was un-dispatchable)** — `id:b018` and `id:e68f` were ratified INDEPENDENT and are not: `oversizeDispatchReason` counted `roadmap_bytes + todo_bytes` unconditionally, so dotclaude-skills estimated ~301,349 tok against a 100,000 budget and the gate refused EVERY dispatch — on bytes the child no longer reads, because `sliceLedgerForUnit()` stamps `unit.slice_path` immediately BEFORE the gate's call site. See `TODO.md` for the full statement. <!-- id:35b7 --> <!-- relates:b018 --> <!-- relates:e68f --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`id:e68f`'s slicer bounded an item block by INDENTATION, so column-0 acceptance criteria were silently dropped** — the block now extends to the next COLUMN-0 checkbox line or the next `#`-heading, fenced blocks are never split mid-fence, and the owning section HEADING is stamped into the slice header (parked/exempt context, `id:356f`). Promoted from TODO with the same id (single-id-two-views). <!-- id:b015 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Suppression must DEMOTE the verdict, not DROP the unit — a stuck item starves every lower verdict class indefinitely** — observed live on loderite, run `relay-20260820-180056-4594`: `actionable_routine_ids: ['57d1']` (one item, whose child died on prompt size) pinned the repo at `execute` while both anti-spin mechanisms (`id:1432` no-work suppression, `relay-loop.js:1235`; `id:365b` >3× circuit breaker, `:1196`) dropped the unit — pinned to `execute` AND `execute` suppressed, so the repo could reach NOTHING while 9 promotable items sat unreachable. <!-- id:bc2b --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **`drained` must distinguish FINISHED from HUMAN-BLOCKED — two repos with 31 open items between them read as done** — `classify-verdict.sh:235` emits `human` ONLY when `surface > 0`; a repo whose ENTIRE open backlog is human-lane but whose `surface == 0` falls through to `idle`, and `control-board.sh:162` maps `idle → design-drained`. Measured 2026-08-21: helferli = 18 open, ALL `[INPUT — …]`, zero poolable → `design-drained`, "Waiting on a human: _(none)_"; csgebra = 13 open, all executable items `gated-on:` `940f` `[INPUT — decision]` → same false-clean. <!-- id:4a76 --> (archived — see ROADMAP.archive.md)
## Parallel-suite flakiness — OBSERVE-FIRST (promoted from TODO 2026-08-21, `id:7518`)

> Promoted reusing the existing TODO id (single-id-two-views). `TODO.md` stays the prose
> SSOT for the accumulated observations; this is the execution spec. **This item is
> deliberately OBSERVE-FIRST** (CLAUDE.md "observe before preventing"): its deliverable is
> EVIDENCE plus a recommendation, not a speculative fix. It stays OPEN until a cause is
> identified — "could not reproduce" is NOT a close.

- [ ] [INPUT — decision] **General parallel-suite flakiness — four unrelated tests have flaked in-suite and passed standalone; build the per-run failure logger before any fix** — **REVIEW 2026-08-21 (`relay-ckpt-20260820-2044..HEAD`): confirmed still legitimately OPEN, on TWO distinct unmet conditions, not one.** (i) The prose close-condition ("closes when `id:81d5` has landed and the suite stops flaking") is now HALF met: `id:81d5` is `[x]` and a full `make test` this review was green (467 passed / 0 failed / 1 expected-red) — but that is n=1 and clause 2 wants multiple runs at three widths, so it is not yet "stops flaking". (ii) **Acceptance clause 4 is UNMET and is NARROWER in the prose than in the Acceptance list** — the entry ranks KILLED hypotheses but never ranks the SURVIVING ones with a confirm/kill observation each, which clause 4 requires; the "NOT established" bullet concedes exactly this ("not… that this is the ONLY live cause"). Do NOT close on the green-suite half alone. Not forgotten; no re-scope recommended. <!-- id:7518 --> — @container 🚧 GATED (auto, id:3801; route:hard-split): DECOMPOSED into seams id:372a, id:166a — pick those, not this. Remaining work is (a) more post-fix flake-log runs at j1/j-oversubscribed widths (executor-doable, but each j1 run took &gt;120s and the host was already at load ~15-19 from concurrent relay siblings, so a full 3-width×multi-run confirmation batch does not fit one session) and (b) writing clause 4's surviving-hypothesis confirm/kill ranking into the ROADMAP.md item body, which only the reviewer can edit per executor-contract rule 5.
  - **CAUSE FOUND 2026-08-21 (evidence attached; the item stays OPEN because the fix is not small — it is `id:81d5`)**: the flake is `set -o pipefail` combined with a producer piped into an EARLY-EXITING consumer (`grep -q`, `head -N`). The consumer exits on its first match while the producer is still writing, the producer dies of SIGPIPE, `pipefail` promotes 141 to the pipeline's status, and the caller's `|| fail` (or a bare `set -e`) fires on an assertion that was actually TRUE. Nothing is shared between the failing tests — which is exactly why they span integrate / statusline / mechanical-daemon / git-lock / gaming-scan with no common fixture. **Measured 8/400 (2%)** on the exact assertion that failed in-suite (`tail -n +35 relay/references/handoff.md | grep -qF '[MECHANICAL]'`) — a static 262-line file, no fixture, no lock, no network. Control form `grep -qF P < <(producer)`: **0/400**. `git log … | grep -q <first-line-match>`: **400/400**, i.e. near-deterministic once the producer has more to write than the consumer reads. **Scope: 427 at-risk pipeline sites across 162 of 459 test files; all 459 set `pipefail`.** Two reproductions are self-proving: `test_integrate_sh_mechanized.sh` PASSED the un-piped `git merge-base --is-ancestor` check at line 97 (so the merge demonstrably landed) and then FAILED line 99's `git log --oneline | grep -q` for that same commit; `test_gaming_scan.sh`'s failure message interpolates `$out`, and the printed `$out` visibly CONTAINS the very string line 52's `printf '%s' "$out" | grep -q` had just reported absent.
  - **HYPOTHESES KILLED BY THE LOG — do not re-run these**: tmpfs/`/tmp` exhaustion (headroom never fell below 2.27 GiB across 55 samples spanning the campaign — though 2132 stale `/tmp/tmp.*` dirs did accumulate and 7 `mktemp` tests carry no cleanup trap, a separate tidiness matter); fd exhaustion (system-wide allocated fds 16.8k-19.5k against `ulimit -n` 524288, flat across runs); the shared `relay-state-write.sh` lock (refuted upstream, `FABLES_CONFIG` makes it per-fixture); and a first-run / warm-cache / sibling-agent TEMPORAL artifact (runs 14-20 each went red after a 6-run green streak). **Parallel WIDTH does not separate either**: j1 0/2, j8 8/13, j16 1/4, j32 0/2 — both j32 runs passed at the HIGHEST observed load (20.9→26.4) while a j8 run failed at 15.1. Width is only a proxy for scheduling latency, which is the actual driver; per-width n is 2-13 and cannot support a rate claim (the ~10pp-at-n=10 limit). Read the run-level rate as "the suite goes red often at j8 on this host", not as a per-width comparison.
  - **Instrument**: `tests/flake-log.sh` → `~/.cache/dotclaude-flake/runs.jsonl` (outside any repo). **21 full-suite runs + 11 standalone re-runs recorded; 9 of the 21 runs went red, 12 test-failures in total across SIX distinct tests** (`test_git_lock_push_slash_branch.sh` ×4, `test_integrate_mechanized_ports_087b.sh` ×3, `test_statusline_tokens.sh` ×2, `test_handoff_produces_mechanical.sh`, `test_integrate_sh_mechanized.sh`, `test_gaming_scan.sh`) — including three of the four historically banked ones, every single one green standalone immediately afterwards. A wide, rotating, non-repeating failure set is what 427 sites across 162 files PREDICTS — a cause confined to a handful of named tests would have been the wrong shape.
  - **NOT established**: a controlled load dose-response (started, killed for budget — the latency-dependence of the RATE is inferred from contention windows, not measured); and that this is the ONLY live cause. It is the only one with direct evidence, and it accounts for every failure observed. `id:7518` closes when `id:81d5` has landed and the suite stops flaking, not before.
  - **Acceptance**:
    1. A per-run failure log exists at a single named path OUTSIDE any repo, and the report states that path. Each row records: timestamp, parallel width (`-j`), the FULL SET of tests that failed in that run (not just the first), total pass/fail/expected-red counts, wall-clock, and the load average (`uptime`) sampled at start AND end of the run.
    2. At least three distinct parallel widths are exercised, including `-j1` and `-j<nproc>`, with more than one run at each. The report states `nproc` for this host and the exact number of runs at each width.
    3. The report contains an explicit correlation statement — does the observed failure rate track parallel width? — with n stated per width, and an explicit acknowledgement of what that n can and cannot distinguish (the ~10pp-at-n=10 limit).
    4. The report ranks the surviving hypotheses, and for EACH gives the concrete observation that would confirm it and the one that would kill it. A hypothesis with no kill-criterion does not count as ranked.
    5. Any test that fails in-suite is re-run standalone and BOTH outcomes are recorded in the log. A red run is data, not a failure of the task.
    6. No speculative fix is merged. A fix lands ONLY if the evidence identifies the cause unambiguously AND the change is small; otherwise the item stays open with the evidence attached.
    7. `id:7518` remains OPEN (unticked) unless clause 6's condition is genuinely met. "Could not reproduce" MUST NOT close it.
  - **Tests**: NONE, deliberately — recorded so its absence is not read as a skipped step. This item has no conventional RED spec: a test asserting "N consecutive suite runs are green" would be non-hermetic, ~5 min per iteration, flaky by construction, and would pass by luck rather than by fix. A hermetic regression test becomes writable only once a cause is identified — authoring it is then a FOLLOW-UP item, not part of this one. No `# roadmap:7518` test exists, so the open checkbox creates no EXPECTED-RED.
  - **Done-check**: the named log file exists and holds one row per run performed, matching the counts claimed in the report; `make test` is green on the final recorded run (a red earlier run is expected and fine — it is the data); the report states n plainly and does not claim a rate the sample cannot support.
  - **Context**: `tests/run-tests.sh` (`-j`/`JOBS`, `RUN_TESTS_NESTED=1` forces serial, longest-first duration cache). REFUTED hypothesis — do not re-run it: shared global state via the `relay-state-write.sh` lock (`FABLES_CONFIG` override makes it per-fixture). Observed flakers: `test_integrate_sh_mechanized.sh` (x2), `test_integrate_mechanized_ports_087b.sh`, `test_statusline_tokens.sh`, `test_mechanical_orphan_draft.sh`.

- [x] [ROUTINE] **Remove the `pipefail` + early-exiting-pipe-consumer race repo-wide, and lint it so it cannot return** — this is the FIX for the cause diagnosed under `id:7518`; that item stays open until this lands and the suite stops flaking. <!-- relates:7518 --> <!-- id:81d5 --> (archived — see ROADMAP.archive.md)
## Integrator ledger staging + stale slicer wording (2026-08-21)

- [x] [ROUTINE] **POOL-BLOCKING — the mechanized TODO-twin tick wrote `TODO.md` but nothing staged or committed it, wedging the repo permanently** — `roadmap-tick.sh` performs no git mutation, `integrate.sh` staged only `ROADMAP.md`, and step 8's `git-lock-push.sh --ff-only` returns before the `id:aa93` tracked-dirty guard (which lives in the rebase branch). An execute/hard integrate whose worked ids had an open TODO twin therefore left `TODO.md` modified-but-uncommitted in the CANONICAL checkout, reported clean, and one round later classified `dirty_block` with every later `integrate.sh` handing back at step-1 `EX_CLEAN_TREE` forever (the tick is idempotent, so a retry cleared nothing). Promoted from TODO with the same id (single-id-two-views). <!-- id:e82e --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **The `id:7575` hardened brief asserted a slicer defect `id:b015` had already removed** — the child-facing string in `relay/scripts/prompt-size-gate.mjs` and its byte-identical inline copy in `relay/scripts/relay-loop.js` both said *"the slicer bounds an item block by INDENTATION, so a criterion written at column 0 can be missing"*. `id:b015` bounds a block by the next column-0 checkbox or `#`-heading with fence tracking, so column-0 prose is INCLUDED — the branch was telling children to hand back citing a slice gap that cannot occur. Wording only, no behaviour change. Promoted from TODO with the same id (single-id-two-views). <!-- id:31c3 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Destructive-git PreToolUse guard — `hooks/destructive-git-guard.py`** — three-way, positive-signal detection: UNATTENDED (`RELAY_RUN_ID`/`RELAY_AFK`/a live `id:e149` heartbeat) ⇒ BLOCK; INTERACTIVE (explicit CLI entrypoint AND no unattended signal) ⇒ defer to the existing `permissions.ask`; EVERYTHING ELSE ⇒ AMBIGUOUS ⇒ BLOCK. An absent heartbeat dir is no signal; a heartbeat probe that ERRORED is ambiguous and blocks. An untokenisable command falls back to a conservative regex scan rather than passing through. 20 blocked tree-wide forms (incl. `git -C . checkout -- .` and `&&`-chained), 18 allowed — path-scoped reverts stay allowed BY DESIGN so the guard never pushes anyone toward the tree-wide form. Refusal teaches three alternatives. **INSTALLED BUT NOT WIRED — activation is the owner's**: `settings.json` untouched (mtime 2026-08-19, independently verified) and a test asserts it is unregistered. Promoted + ticked by the integrator; the executor correctly declined to edit ROADMAP per contract rule 5. <!-- id:3a09 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Destructive-git guard: the `discovery-producer` daemon is no longer read as an unattended run** -- `hooks/destructive-git-guard.py`'s heartbeat probe accepted ANY live marker, and `heartbeat.sh live-runs` always reports the non-pool `discovery-producer` sampler (fixed runId, 2100s TTL, id:54fc), so every INTERACTIVE session (`CLAUDE_CODE_ENTRYPOINT=cli`, empty `RELAY_RUN_ID`) got a hard `deny` on a FALSE stated reason -- strictly worse than the `permissions.ask` it replaced, and the exact over-blocking failure the built-but-unwired split (id:3a09) existed to prevent. The probe now requires the marker to name a real POOL run via the SHARED predicate `relay/scripts/lib-pool-runs.py::is_pool_run`, extracted from `stop-request.sh`'s inline copy so ONE definition serves both callers (a test asserts neither carries a second copy). Four context branches pinned: producer-only + cli DEFERS; `RELAY_RUN_ID` set BLOCKS; a live REAL pool heartbeat BLOCKS (also when the producer beats beside it); ambiguity (no/unrecognised entrypoint, heartbeat probe ERROR) BLOCKS, absent heartbeat dir stays no-signal. The refusal now NAMES the trigger that fired instead of asserting `(relay run id / live heartbeat detected)`, and remedy #1 teaches scoped `git add -- <paths>` rather than the repo-banned tree-wide staging (id:debf). Path-scoped allow branch unchanged; `settings.json` still NOT written -- wiring remains the owner's switch. Tests: `tests/test_destructive_git_guard_pool_signal_6f62.sh` (12 assertions RED before, green after). <!-- id:6f62 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Destructive-git guard: a malformed PreToolUse payload no longer FAILS OPEN** -- an exit-1 PreToolUse hook is a NON-BLOCKING error: Claude Code prints stderr and RUNS the command, so a crash in `hooks/destructive-git-guard.py` silently BYPASSED the guard. Four payload shapes crashed with exit 1 -- a top-level JSON array or string (`.get` on a non-dict), `tool_input` a string, and a non-string `command` (`"git" not in 123`, or a list reaching `shlex.split`). The one input class that should never be trusted was exactly the class that got through. Every branch of `main()` now exits 0, `find_violation` never raises (an unexpected failure of the tokenised analysis routes to the SAME conservative regex scan a shlex error already took, not to a traceback), and an outermost `try` catches anything else. **Disposition for an unreadable payload: DEFER (exit 0, EMPTY stdout) plus a one-line stderr note** -- a payload that will not parse carries no command, so there is nothing destructive to block, and blocking instead would turn any future hook-protocol change into a fleet-wide outage in front of every Bash call; the stderr note keeps the deferral observable rather than a silent hole. The fail-SAFE branches are untouched: breaking `lib-pool-runs.py` (missing / syntax error / missing `is_pool_run`), with or without a heartbeat dir, still yields `deny` naming `heartbeat probe ERRORED`. Latency 27 ms/call, still no `subprocess`. `settings.json` NOT written. Tests: `tests/test_destructive_git_guard_malformed_3866.sh` (the four shapes verbatim + empty stdin + invalid JSON, each asserted exit 0 / empty stdout / non-empty stderr, plus a hostile-input sweep of `find_violation`). <!-- id:3866 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Destructive-git guard: a fresh heartbeat marker with an unusable `runId` is now a probe ERROR, not a non-signal** -- `is_pool_run("")`/`is_pool_run(None)` answer `False` exactly as they do for a known non-pool daemon, and `_heartbeat_signal` `continue`d on `False`, so a LIVE but unclassifiable marker contributed no signal and an interactive session DEFERRED. That inverts the guard's own stated doctrine, where "cannot tell whether a pool is live" is ambiguity and must BLOCK. The split now lives in the caller: a fresh marker whose `runId` is empty, whitespace, or not a string returns `error` (⇒ ambiguous ⇒ BLOCK, naming `heartbeat probe ERRORED`), while a fresh marker naming a known non-pool run still contributes nothing. A marker that is valid JSON but not an object is likewise an error. `relay/scripts/lib-pool-runs.py` is UNCHANGED -- `stop-request.sh` genuinely cannot address an unnamed run, so the permissive answer is right there. Staleness is still checked BEFORE the runId, so a stale empty-runId marker remains no signal. Tests: `tests/test_destructive_git_guard_malformed_3866.sh`. <!-- id:8987 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Destructive-git guard no-drift test pins the RULE, not one spelling** -- the assertion grepped both callers for `!= "discovery-producer"`, so a reintroduced inline copy written `== "discovery-producer": continue`, `not in ("discovery-producer",)` or `startswith("discovery")` passed it untouched. Both callers mention the literal ONLY in comments today (the guard's module docstring, one `#` comment and a function docstring; two `#` lines in `stop-request.sh`), so the strictly stronger assertion -- ZERO NON-COMMENT occurrences of the literal in either caller -- is available and already true. The guard is checked with `tokenize` (COMMENT tokens and triple-quoted docstrings exempt, plain string literals NOT, so `== "discovery-producer"` still counts); `stop-request.sh` with `#`-line stripping. Negative control run: the injected `== "discovery-producer": continue` mutant is MISSED by the old grep and CAUGHT by the new assertion. The original spelling assertion is retained beside it, so this is strictly additive. Tests: `tests/test_destructive_git_guard_pool_signal_6f62.sh`. <!-- id:4c14 --> (archived — see ROADMAP.archive.md)
- [x] [ROUTINE] **Version the last unmanaged hook — `rm-force-guard.sh`** — it was wired in `settings.json` but was a REAL LOCAL FILE with no counterpart in this repo (unversioned, absent on other hosts, lost on a rebuild). Copied in byte-identical; the Makefile's eight hand-written `ln -sf` lines replaced by ONE `HOOK_FILES` manifest driving both `install-hooks` and a new `status-hooks` (now part of `make status`) that flags real-file-instead-of-symlink drift AND any hook present in `~/.claude/hooks/` this repo does not manage. Audit result: `rm-force-guard.sh` was the ONLY unmanaged hook path — all others already symlink into the repo. The live `~/.claude/hooks/` file was deliberately NOT replaced with a symlink; that is `make install-hooks`' job when the owner runs it. Promoted + ticked by the integrator. <!-- id:5218 --> (archived — see ROADMAP.archive.md)
- [ ] **[INPUT — decision]** Gather post-id:81d5-fix flake-log confirmation runs at j1 and an over-subscribed width (e.g. j24/j32), ≥2 runs each — seam of id:7518 (auto, id:3801) <!-- id:372a --> — @container 🚧 GATED (auto, id:3801; route:hard-split): DECOMPOSED into seams id:97e0, id:f2ef, id:b1ef, id:c3be, id:6ab7 — pick those, not this. Each of 4 required flake-log runs (2× width=1, 2× width≥16) takes multiple minutes wall-clock; doesn't fit one executor turn as a single unit.
  - **Acceptance**: tests/flake-log.sh has appended ≥2 rows each at width=1 and at a width ≥2×nproc, all timestamped after id:81d5 landed, to ~/.cache/dotclaude-flake/runs.jsonl; findings summarized in RELAY_LOG.md (no ROADMAP.md edit)
  - **Done-check**: grep the new rows in ~/.cache/dotclaude-flake/runs.jsonl by timestamp and width; all rc=0 or failures logged per the instrument's own contract
  - **Context**: tests/flake-log.sh, ~/.cache/dotclaude-flake/runs.jsonl, RELAY_LOG.md
- [ ] **[HARD]** Reviewer: fold the three-width post-fix data into ROADMAP.md id:7518, rank surviving hypotheses with confirm/kill criteria each (Acceptance clause 4), and decide closure per clause 6/7 (after id:(depends on the data-gathering seam above)) — seam of id:7518 (auto, id:3801) <!-- id:166a -->
  - **Acceptance**: ROADMAP.md id:7518 body states the correlation across 3 widths with n-per-width and the ~10pp-at-n=10 caveat, ranks every surviving hypothesis with a confirm-observation and a kill-observation, and either ticks the item (only if clause 6 is genuinely met) or explains why it stays open
  - **Done-check**: manual reviewer read of the updated ROADMAP.md block against Acceptance clauses 1-7
  - **Context**: ROADMAP.md:1653 (id:7518 block)
- [ ] **[INPUT — decision]** flake-log width=1 confirmation run #1 (post-id:81d5) — seam of id:372a (auto, id:3801) <!-- id:97e0 --> — 🚧 GATED (auto, id:3801; route:human): flake-log -j1 (sequential full suite) exceeds one executor turn's wall-clock budget under current host load (~10-16 loadavg); needs a longer-lived/background run or a lower-load window, not a code change. — needs /relay human
  - **Acceptance**: tests/flake-log.sh -j 1 completes and appends one new row to ~/.cache/dotclaude-flake/runs.jsonl with ts after 2026-08-21T10:58:33Z
  - **Done-check**: grep the new row's ts in ~/.cache/dotclaude-flake/runs.jsonl; rc recorded per the row's rc (0 or failure logged)
  - **Context**: tests/flake-log.sh, ~/.cache/dotclaude-flake/runs.jsonl
- [x] **[ROUTINE]** flake-log width=1 confirmation run #2 (post-id:81d5) (after id:(seam 1, independent — no id yet)) — seam of id:372a (auto, id:3801) <!-- id:f2ef --> (archived — see ROADMAP.archive.md)
- [ ] **[ROUTINE]** flake-log over-subscribed-width confirmation run #1 (post-id:81d5) — seam of id:372a (auto, id:3801) <!-- id:b1ef -->
  - **Acceptance**: tests/flake-log.sh -j 16 (or -j 24/-j 32) completes and appends one new row to ~/.cache/dotclaude-flake/runs.jsonl with ts after 2026-08-21T10:58:33Z
  - **Done-check**: grep the new row's ts and width in ~/.cache/dotclaude-flake/runs.jsonl
  - **Context**: tests/flake-log.sh, ~/.cache/dotclaude-flake/runs.jsonl
- [ ] **[ROUTINE]** flake-log over-subscribed-width confirmation run #2 (post-id:81d5) — seam of id:372a (auto, id:3801) <!-- id:c3be -->
  - **Acceptance**: tests/flake-log.sh -j 16 (or matching width) completes and appends a second new row to ~/.cache/dotclaude-flake/runs.jsonl with ts after 2026-08-21T10:58:33Z
  - **Done-check**: grep the new row's ts and width in ~/.cache/dotclaude-flake/runs.jsonl
  - **Context**: tests/flake-log.sh, ~/.cache/dotclaude-flake/runs.jsonl
- [ ] **[ROUTINE]** Summarize the 4 post-id:81d5 flake-log confirmation rows in RELAY_LOG.md (after id:all 4 run seams above) — seam of id:372a (auto, id:3801) <!-- id:6ab7 -->
  - **Acceptance**: RELAY_LOG.md gets one committed self-report paragraph summarizing pass/fail across the 4 new rows (no ROADMAP.md edit); id:372a can then be ticked by the integrator
  - **Done-check**: grep the new RELAY_LOG.md entry; confirm it cites all 4 new runs.jsonl timestamps
  - **Context**: RELAY_LOG.md

- [x] **[ROUTINE]** **Apex `hard` dispatch MUST require `--afk`, and the HARD-execute gate must key on `STRONG_TIER === 'opus'` instead of the model-id literal `claude-opus-4-8`** — combines `id:7986` (owner 2026-08-22, after a live pool spent Opus on three `[HARD]` units against his cap) with `id:da51` (`routed:fba9` from csgebra; owner-ratified 2026-08-23). Today `relay-loop.js` has NO consumer of `A.afk` at all, so the owner's rule is prose only; and the hard gate compares `STRONG_MODEL !== 'claude-opus-4-8'`, so bumping the pin to the live apex model would make the inequality TRUE and defer every hard unit while reporting "requires apex Opus" — a message false precisely when the pin is correct. The two must land together or the next reader inherits the same contradiction. **SETTLED, do NOT re-open:** (1) `handoff` is PERMITTED ALWAYS at apex, exactly like `review` — ONLY `hard` is gated on `--afk` (owner 2026-08-22; this OVERRIDES the contrary recommendation recorded when `id:7986` was filed, and the SKILL.md wording must not imply handoff is gated). (2) The gate asks `STRONG_TIER === 'opus'`; the model id becomes a pure OUTPUT value, bumped to `claude-opus-5` (owner 2026-08-23). (3) Runtime auto-detection of the live apex model id is OUT OF SCOPE (filed separately as `id:f6a1`). <!-- id:7986 --> <!-- ref:da51 --> (archived — see ROADMAP.archive.md)
