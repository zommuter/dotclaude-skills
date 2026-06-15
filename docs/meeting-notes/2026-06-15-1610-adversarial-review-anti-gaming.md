# 2026-06-15 — Adversarial / plural review verification for relay (anti-gaming) — id:2909

**Started:** 2026-06-15 16:10
**Session:** 75898d32-ce0a-410d-a07b-a32f1afa0d22
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration)
**Topic:** Should relay `review` get an adversarial/plural verification layer to harden anti-gaming, and if so with what trigger, topology, and wiring?

## Surfaced discoveries
- [2026-06-12 dotclaude-skills] `/batch` vs relay: the relay's anti-gaming mechanism is checkpoint tags + independent re-run of the *original* tests — adversarial review is the differentiator over plain Ralph.
- [2026-06-12 dotclaude-skills] Workflow engine `parallel()` primitive already exists in relay-loop.js; fan-out is mechanically available at the supervisor (script) level only — child agents cannot spawn sub-agents.

## Agenda
1. Warrant + trigger: is full plural verification warranted now (vs cheap hook + observe), and what triggers it?
2. Gaming-canary corpus: scope, mechanical-vs-model split, cadence.
3. Wiring: source-of-truth, logger placement, item slicing.

## Discussion

### Agenda 1 — Warrant + trigger

**🎛️ Orla:** The orchestration case for adversarial review is real in principle — a single verifier is a single point of trust, and the whole reason the relay beats plain Ralph is the *independent, stronger* verifier. The standard fix is to make that verifier plural and adversarial. The Workflow already has the `parallel()` primitive, so the machinery is nearly free to wire.

**😈 Riku:** Before we build a refuter fleet, what is the minimum evidence that would change this decision? I read all ~12 review entries in `RELAY_LOG.md`. Every single one says "no gaming flags, genuinely green." Zero observed incidents of a reviewer being talked past. We'd be building a safety mechanism for a failure whose frequency is, on the record, *zero*. The global CLAUDE.md heuristic is explicit: "Observe before preventing — when considering a safety mechanism for a failure whose frequency is unknown, build a logger first."

**✂️ Petra:** And the N=2 rule on cost. A full plural pass over *every closed item* multiplies review token cost by ~4× (3 refuters). The 2026-06-12 pilot already showed review starvation (id:1dff) — making review 4× more expensive makes that worse. If we spend the tokens, the anti-gaming window stays open longer, which is the exact thing we're trying to shorten.

**🏗️ Archie:** But note the asymmetry. The review child *already* produces `gaming_flags[]`. The cheap version isn't "refute every closed item" — it's "only escalate items the first reviewer already flagged." That bounds cost to the flag rate, which on the record is ~0.

**😈 Riku:** Then what does escalation actually buy? If the single reviewer flags it, the supervisor can just reopen it — no fleet needed. The fleet only adds value for the case the single reviewer *misses* gaming and reports green. Escalating on flags hardens nothing the first pass didn't already catch; escalating on *greens* is where the value is, and that's the expensive path.

**🎛️ Orla:** Two distinct failure modes: (a) reviewer flags a false positive → fleet refutes the flag, avoids a needless reopen — cheap, low value; (b) reviewer misses real gaming, reports green → only a fleet over *greens* catches it — the anti-gaming win, costly.

**✂️ Petra:** The valuable version is the expensive version, and we have zero evidence the expensive failure mode has ever occurred. Proportionate move: build the cheap supervisor-side escalation hook over `gaming_flags` + a flag-rate logger, and defer the fleet. If flags start firing and reviews disagree, then we have the evidence.

**🏗️ Archie:** Forward-compatible — the hook + logger establishes the seam; turning on plural-over-greens later is a knob change, not a re-architecture.

**😈 Riku:** Agreed, with teeth: the logger must record closed-item ids + the reviewer's verdict, not just "flag fired" — otherwise it can't measure mode (b) and a future plural-over-greens pilot has no baseline.

**Zommuter:** Option 1 — and now that I think about it, maybe we should create a few test cases for intentionally crafted gaming items that must be detected by tests? Clearly not use the model every time, but after significant changes etc. to verify the gaming detection works at all.

### Agenda 2 — Gaming-canary corpus

**🏗️ Archie:** The corpus exposes a structural problem: today the "detector" is *prose in `review.md` §2*, executed by a model. There is no code to unit-test. Half those checks are mechanical and already written as bash one-liners — deleted test (`git diff --diff-filter=D`), added `skip`/`xfail`/`.only`, removed `assert`. I'd extract the mechanical detections into a `gaming-scan.sh` the review child runs first — cheaper deterministic common path, and something the canary corpus can call hermetically with zero model tokens.

**✂️ Petra:** Scope discipline: fixtures map exactly to `review.md` §2's existing checklist — deleted, weakened-assert, added-skip, hardcoded-actual, fixture-special-casing, skipped-counted-green, frozen-green-regression-guard. Closed set; one fixture per claim, not a combinatorial explosion.

**😈 Riku:** Two teeth. First, every canary needs a **negative control** — a *legitimate* green diff (e.g. the real id:3b02 resurrection case from RELAY_LOG, where the executor fixed only the input line and assertions stayed intact) that must NOT be flagged. A detector that flags everything is useless; prove specificity, not just sensitivity. Second, be honest about bash's reach: deleted/skip/weakened-assert are grep-mechanical; resurrection-check and fixture-special-casing are genuine model judgment — a bash test there would be theater. Those need a model-driven canary, run on-demand.

**🎛️ Orla:** Two tiers, two cadences. **Tier A** — mechanical canaries against `gaming-scan.sh`: hermetic bash, every `make test`, free. **Tier B** — judgment canaries (resurrection, fixture special-casing): a model harness run on-demand via `make gaming-canary` after detector changes. Trigger is a detector change, not a calendar.

**🏗️ Archie:** Tier B is a `tests/`-style harness excluded from `run-tests.sh`'s default sweep so `make test` stays zero-token. Each fixture = a tiny prepared diff + expected verdict; harness spawns one review-style agent, asserts `gaming_flags` contains the expected id.

**✂️ Petra:** The Tier A extraction earns its keep beyond testing — it makes the common review path cheaper every round. N=2: consumer one the canary suite, consumer two the live review child. Both real. Extraction justified.

**😈 Riku:** Acceptable. One thing I won't concede: Tier B existing must not let us pretend we've solved mode (b). The canary proves the detector catches *known* gaming patterns — it says nothing about *novel* ones a real executor invents. The flag-rate logger from Decision 1 still stands. Canary = "detector works on patterns we thought of"; logger = "are we seeing anything in the wild." Different jobs.

**Zommuter:** Two-tier.

### Agenda 3 — Wiring: source-of-truth, logger placement, item slicing

**🏗️ Archie:** `gaming-scan.sh` lives in `relay/scripts/` beside `claim.sh`/`inject.sh`/`quota-stop.sh`; `set -euo pipefail`, takes `<repo-root> <since-tag>`, emits one parseable line per detection. The review child runs it first, then does the model-judgment residue. Tier B harness: `tests/gaming-canary/` + a `make gaming-canary` target, excluded from `run-tests.sh`.

**😈 Riku:** Authority question or we get drift: once mechanical checks live in `gaming-scan.sh`, `review.md` §2 must STOP describing them as procedure and *delegate* — "run `gaming-scan.sh`; it covers deleted/weakened/skip; you own resurrection + fixture-special-casing." Script owns mechanical, prose owns judgment. Single source of truth.

**🎛️ Orla:** On the logger — per-repo gaming *findings* land in the repo's relay files (review.md already reopens + logs to RELAY_LOG). The flag-*rate* logger is different: cross-repo aggregate telemetry like `meeting-cost.log`. That goes in `~/.claude/logs/relay-gaming-flags.log`, written by the supervisor at integrate time. Findings → repo; base-rate telemetry → `~/.claude/logs`. Don't conflate.

**✂️ Petra:** Four pieces with red spec tests:
1. `gaming-scan.sh` — mechanical detector, args `<repo-root> <since-tag>`, emits flag lines. `[ROUTINE]`.
2. `review.md` §2 rewrite — delegate to script, prose retains only resurrection + fixture-special-casing. `[ROUTINE]`.
3. Tier B `tests/gaming-canary/` + `make gaming-canary` — model harness for resurrection + fixture-special-casing fixtures, with negative controls. `[HARD — strong model]`.
4. Supervisor flag-rate logger in `relay-loop.js` `integrate()` → `~/.claude/logs/relay-gaming-flags.log`. `[ROUTINE]`.

**🏗️ Archie:** The deferred-fleet seam is a documented comment at the logger site ("future: spawn `parallel()` refuters over flagged/green items here") — no code until evidence.

**Zommuter:** Piece 3 = [HARD], rest [ROUTINE].

## Decisions

- **D1 — Defer the plural refuter fleet; build the cheap hook + a flag-rate logger.** Relay `review` stays single-pass for now. The supervisor escalation over `gaming_flags` reduces to: a base-rate logger + a documented seam where a future `parallel()` refuter fan-out slots in. Justification: RELAY_LOG shows zero recorded gaming incidents across ~12 reviews — observe-before-preventing. **Out of scope:** the refuter fleet, plural-over-greens, any majority-vote topology (revisit only if the logger shows flags firing / reviewer disagreement).
- **D2 — Build a gaming-canary corpus in two tiers with a mechanical/judgment split.** Extract `review.md` §2's mechanical checks into `gaming-scan.sh`. **Tier A:** hermetic bash canaries (deleted-test, added-skip/xfail, weakened-assert) + **negative controls** (a legitimate green that must NOT flag, e.g. the real id:3b02 resurrection case), run every `make test`. **Tier B:** model-driven canary harness for the judgment checks (resurrection-check, fixture-special-casing), run on-demand via `make gaming-canary` after detector changes — NOT in the per-round relay loop. **Out of scope:** novel/unknown gaming patterns (corpus only covers patterns we thought of); combinatorial fixtures (one per §2 claim).
- **D3 — Single source of truth + logger placement + slicing.** `gaming-scan.sh` owns the mechanical checks; `review.md` §2 is rewritten to *delegate* to it (no inlined mechanical one-liners — prose owns only resurrection + fixture-special-casing judgment). The flag-rate logger is cross-repo aggregate telemetry → `~/.claude/logs/relay-gaming-flags.log` (distinct from per-repo gaming findings). Pieces 1/2/4 `[ROUTINE]`, piece 3 `[HARD]`. **Out of scope:** moving per-repo findings out of the repo; touching the existing reopen path.

## Action items

- [ ] **Piece 1 — `gaming-scan.sh`** (`relay/scripts/`): `set -euo pipefail`, args `<repo-root> <since-tag>`, emits one parseable flag line per mechanical detection (deleted test via `git diff --diff-filter=D`, added `skip`/`xfail`/`.only`/`@pytest.mark.skip`, removed `assert`/expectation lines). Red test (`tests/test_gaming_scan.sh`): crafted diffs emit the expected flags; a clean diff emits nothing. `[ROUTINE]`. Source: `docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md` <!-- id:fa05 -->
- [ ] **Piece 2 — `review.md` §2 delegate rewrite**: §2 invokes `gaming-scan.sh` for the mechanical pass and retains only the resurrection-check + fixture-special-casing judgment prose; the inlined mechanical one-liners are removed (single source of truth). Static-grep test asserts §2 references `gaming-scan.sh` and no longer inlines the `--diff-filter=D` / skip-grep one-liners. `[ROUTINE]`. Source: `docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md` <!-- id:dfaf -->
- [ ] **Piece 3 — Tier B model canary harness** (`tests/gaming-canary/` + `make gaming-canary`): each fixture is a prepared gamed diff (resurrection-rewrite, fixture-special-casing) + expected verdict + at least one negative control (id:3b02 legitimate resurrection as a non-flag control); the harness spawns one review-style agent and asserts `gaming_flags` contains the expected id (and is empty for controls). Excluded from `run-tests.sh` default sweep (stays zero-token). `[HARD — strong model]`. Source: `docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md` <!-- id:414a -->
- [ ] **Piece 4 — supervisor flag-rate logger** in `relay-loop.js` `integrate()`: append a line to `~/.claude/logs/relay-gaming-flags.log` with repo/run/closed-item-ids/`gaming_flags`/`reopened`/`verified_green` at integrate time; leave a documented comment marking the deferred-fleet escalation seam. Red test: a fixture report carrying `gaming_flags` yields a log line with the expected fields. `[ROUTINE]`. Source: `docs/meeting-notes/2026-06-15-1610-adversarial-review-anti-gaming.md` <!-- id:3826 -->

(All four sit under umbrella **id:2909**; pieces 1/2/4 are relay-ready `[ROUTINE]`, piece 3 is `[HARD]`. The plural refuter fleet remains a deferred follow-up gated on logger evidence.)
