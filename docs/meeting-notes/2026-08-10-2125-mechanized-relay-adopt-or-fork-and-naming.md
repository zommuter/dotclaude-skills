# 2026-08-10 — Naming and chartering the mechanized-relay project — and the adopt-or-fork reframe

**Started:** 2026-08-10 21:25
**Session:** 7ba3c9c2-fda7-40bb-980d-8fd8d89dcc48
**Invoked from:** `~/src/project_manager` (a stub note lives there; this is the full record — the centre of gravity is `dotclaude-skills`)
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🏷️ Nomi (naming & brand-linguistics), 🎛️ Orla (multi-agent orchestration), 🗂️ Tilda (work-management substrate — *registry emoji 🏷️ clashes with Nomi's; rendered 🗂️ here*)
**Topic:** Name and charter a new "pure mechanization, LLM only where truly needed" relay project — which became, at the owner's instruction, a survey of whether that project should exist at all.

> **`--fabled`:** run. One closing Fable-5 adversarial pass, **8 findings, 6 forced amendments, all accepted.** The pre-registered escalation trigger (≥2) **FIRED** — see `## --fabled closing pass`.

**Direct amendment to the 09:06 session of the same day** (`2026-08-10-0906-tracker-substrate-replacing-markdown-ledgers.md`). Read as a pair.

## Owner's opening request (verbatim)

> "The /relay and TODO/ROADMAP mechanics have become quite the mess... I'll start a new project to start from pure mechanization with llm only where truly needed in parallel. What could be nice names for such a project? I was thinking on a play on 'Power Loom' (but really not just 'power llm'), since that's what a mechanized relay skill basically does, but I'm open to other suggestions. The TODO/ROADMAP part should probably be an external tool like Vikunja/Plane which we're currently piloting for the 'normal' relay skill already, but the new project may just as well try and do something sophisticated itself. And the project _might_ become a full Claude / opencode replacement attempt, we'll see..."

## Surfaced discoveries
- `[2026-08-10 dotclaude-skills]` Archiving DONE items does not bound a markdown ledger — `ROADMAP.md` stayed 254 KB / 1738 lines with 69 open items after 100 were archived.
- `[2026-07-10 relay-core]` A script that does side effects *then* emits an `actions` array has a receipt, not a plan — no parity oracle in any substrate.
- `[2026-07-10 relay-core]` A pre-registered criterion must be **observable at evaluation time**, or it silently resolves to whatever the evaluator already preferred.
- `[2026-07-31 dotclaude-skills]` A strict if/elif verdict cascade makes a lower-priority verdict unreachable.
- `[2026-07-29 dotclaude-skills]` A model-string-keyed assumption about where safety evaluation happens must be verified empirically.

## Agenda
1. What exactly is being named — and does it collide with `relay-core`?
2. The name.
3. TODO/ROADMAP: inherit the 09:06 tracker decision, or build in-house?
4. *(Amendment session, owner-raised)* Are any existing tools already good enough to use or fork instead of reinventing?

## Discussion

### Round 1 — what is being named

🏷️ **Nomi** refused to name anything before the scope was fixed: *"'Power Loom' is a metaphor for a thesis, not for a scope… whether this name will appear on a private `~/src` directory forever, or on a public agent harness competing with opencode"* — different screening standards, per her `lodelore` lens split.

😈 **Riku** raised the collision nobody had named: **`~/src/relay-core` already exists** and its README says *"The relay mechanization core, in Lean 4… the same deterministic decisions, ported to a typed substrate where the recorded bug classes are dissolved by construction."* Last commit 2026-07-11. *"relay-core stalled, and the response is to mint a fresh one. That is a pattern, not a plan."* **(This premise was later refuted by the `--fabled` pass — see finding 1.)**

🏗️ **Archie** agreed on the fact and disputed the verdict: relay-core was chartered as **island 1 = `classify-verdict`**, types-only, under a strangler where bash stays the only authoritative output and the flip is gated on 100% fixture parity + N=5 clean shadow rounds — *"a substrate experiment, deliberately forbidden from changing behaviour"*, not a mechanical-by-default orchestrator.

🎛️ **Orla**: every mechanization win to date was *"a hop extracted from a bash+prompt pipeline that already existed. You cannot reach 'mechanical by default' by subtraction from that starting point, because the LLM is the substrate the pipeline is written in — the prompt string IS the program."*

✂️ **Petra** flagged the harness clause as a **forward-flag, not a requirement**, but noted it is the single biggest input to the name.

🗂️ **Tilda** flagged that "the new project may do something sophisticated itself" is a live proposal to abandon a decision nine hours old that has not yet produced its first import — *"What must not happen is the new project reinventing the schema."*

🏗️ **Archie** added the constraint that decides item 3: `id:4a5c` recorded that **in-progress is not expressible at all** in the current ledger (strict 2-state checkbox; in-flight state lives in `claim.sh` + `RELAY_STATUS.md` and evaporates when the run ends).

### Round 2 — the name

🏷️ **Nomi** screened before proposing, and called the result *"the cleanest kill I have ever produced, and I produced four of them."*

| Candidate | What already exists under that name | Verdict |
|---|---|---|
| **Heddle** | `roackb2/heddle` — "open-source terminal coding agent runtime and CLI"; heddle.sh — "version control for agent work" | KILL — same product |
| **Millwright** | `njcameron/Millwright` — "cron-driven orchestrator that works off a project board, dispatching **Claude Code** to implement issues autonomously"; millwrighthq.com; `Northwood-Systems/millwright` (LLM router) | KILL — that *is* the relay |
| **Weft** | `WeaveMindAI/weft` (language for AI orchestrations), `ailiheizi/weft`, `Weft-io/weft`, crates.io/weft, `hyperledger-labs/weft` | KILL — five deep |
| **Jacquard** | `jbwinters/jacquard-lang` ("a regime in which most code is written by ML models and reviewed by people"), `young-steveo/jacquard-ai`, Google Jacquard | KILL — plus a megacorp |

She then tested whether it was luck or structure, screening the two most obscure textile words available: `viksit/selvedge` — *"Weaving prompts and code into structured, resilient patterns that **won't unravel under pressure**"* — her exact metaphor, already written down; plus `masondelan/selvedge` + selvedge.sh. **Conclusion: the weaving metaphor is the most-mined vein in agent orchestration right now**, because the 1780s textile mill is the most famous mechanization story in English.

😈 **Riku** asked what the failure mode actually is for a `~/src` directory. 🏷️ **Nomi**: the serious one is the forward-flag — if it fires, these are *"direct competitors in the same category"*, and renaming then costs every cross-repo `routed:` breadcrumb plus ~60 `CLAUDE.md` files. *"Accept-and-disclose only when the later re-screen is cheap. Here it is not — the rename cost scales with the fleet."*

✂️ **Petra**: *"Then the decision is not 'which name'. It is which screening standard, and Tobias owns that."*

🏗️ **Archie** proposed the pivot: **railway interlocking**. *"A lever frame is a mechanical machine in which the signalman pulls levers, and the frame physically refuses every combination that would put two trains on one track. The unsafe state is not detected, it is unrepresentable."* — the same sentence as relay-core's own ratified finding (*"a sum type … makes the fail-closed guard unrepresentable rather than proved"*). And "relay" is itself railway/telegraph vocabulary.

🎛️ **Orla**: *"In a signal box, the frame is mechanical and always right; the human contributes exactly one thing — the routing decision no machine of that era could make. A loom does not have that property. A loom just repeats."*

🏷️ **Nomi** screened the pivot — *"I am not making the same mistake twice in one meeting"*: **`tappet` clean** (and sits in both metaphors — a tappet loom is the mechanization step *before* Jacquard, and tappet locking is what makes conflicting lever settings impossible), **`escapement`/`detent` clean**, **`leverframe`/`signalbox`** clean but bare `Frame` is taken by `kaanozhan/Frame`, **`remontoire`** taken by `regolith-linux/remontoire`.

### Round 3 — adopt-or-fork (amendment session, owner-raised)

> Owner, verbatim: *"But obviously I fell into the not-invented-here trap. Let's check which of those (or similar) tools are how similar to /relay and/or what it's supposed to be like as well as my initial vision description for this meeting's target 'tool' to consider whether one of them is already good enough to use / fork off instead of re-inventing a /relay-based Frankenstein"*

😈 **Riku**: *"Four independent teams shipping an agent orchestrator under our exact metaphor is market evidence that the product exists, and we treated it as a trademark inconvenience. That is the not-invented-here trap with an extra step."*

🏗️ **Archie**'s comparison against the relay's actual discriminators (single README fetch per tool — **treat as UNVERIFIED**):

| | **relay (today)** | **Millwright** | **Frame** | **Agent Orchestrator** | **Gastown + Beads** | **repomon** |
|---|---|---|---|---|---|---|
| Many repos as a fleet | ✅ ~60 | ✅ one board, many repos | ❌ single | ❌ single | ✅ "rigs" | ✅ |
| Works with no GitHub / no PRs | ✅ | ❌ requires GH Projects v2 + PRs | ✅ | ~ optional | ✅ | ✅ |
| No hosted service | ✅ | ~ VPS + cron | ✅ | ✅ local daemon | ✅ local git/Dolt/tmux | ✅ |
| Model tiering | ✅ Opus→Sonnet | ✅ plan vs exec | ❌ | ❌ | ✅ Mayor → Polecats | ❌ |
| RED-spec handoff | ✅ | ❌ | ~ specs, not failing tests | ❌ | ❌ | ❌ |
| Anti-gaming test audit | ✅ | ❌ CI auto-fix ×2 | ~ footprint drift check | ~ CI feedback | ~ Bors-style merge queue | ❌ |
| Human lanes / judgment queue | ✅ | ~ plan review | ~ approval | ~ | ✅ Deacon→Mayor→Overseer | ❌ |
| Typed-dep + in-progress ledger | ❌ **the pain** | GH Projects | tasks.json | daemon dir | ✅ Beads DAG | ❌ |
| Mechanical-by-default | partial — **the goal** | hybrid | ❌ | ~ | ❌ **Mayor is an LLM** | n/a |
| Maturity (repo page reports) | — | MIT, 8★/25 commits | Apache-2.0, 322★ | Apache-2.0, 9.2k★ | **MIT, 17.5k★** | — |

🗂️ **Tilda**: *"Beads is the design we ratified nine hours ago, already shipped… I would rather amend my own decision than defend it."* **(Her factual basis was partly stale — see finding 3.)**

✂️ **Petra**: *"What is genuinely unbuilt anywhere I have seen tonight is the pair the relay was actually built around: the reviewer authors a failing test, and the executor is audited for not having weakened it. That is the invention. Everything else is assembly."* **(Contested by finding 5.)**

🎛️ **Orla** on forking Gastown: *"Adopting Beads costs one binary and a data model; forking Gastown costs a doctrine."*

😈 **Riku**: *"Everything above is secondary sources and one README fetch each. I have not run `bd`."* → the spike.

🏷️ **Nomi**: *"The name is downstream and should stay unmade tonight."*

## Decisions

**Decision provenance:** ratified via `AskUserQuestion` at four decision points; the amended set below was ratified in one pass after the `--fabled` findings, with the owner accepting all four finding groups and answering D6 *"Still open — measure first."*

Originals are kept; amendments are **superseding entries**, never rewrites.

- **D1 — Charter: mechanized relay engine.** v1 = the relay workflow rebuilt mechanical-by-default, LLM called as a typed exception. "Claude/opencode replacement" is a **forward-flag, not a requirement**.
  - **D1-A (supersedes D1, per finding 6).** The charter stands as *direction* but is **not ratified as a v1 spec** until it names a **falsifiable metric** — e.g. LLM invocations per integrated item, count of judgment call-sites each with a typed input/output schema, fraction of pipeline under fixture tests — **with the incumbent measured first as baseline** (`RELAY_LOG` + `relay-gaming-flags.log` make this measurable today). *Out of scope:* declaring the incumbent non-mechanical without that measurement.
- **D2 — `relay-core` left alone, decided later.** Riku's "pattern, not a plan" objection recorded OPEN.
  - **D2-A (supersedes D2, per finding 1).** The premise was **false**. relay-core's Lean classifier has shadowed **every** relay classify since 2026-07-08: **95,663 rounds / 281 mismatches (~0.29%), still accruing**, flip gate no longer met (`id:d5bd`); and its island-2 blocker `routed:2f0c` **has landed** (`id:77ce` done), so its ROADMAP "🚧 GATED" annotation is stale. relay-core's disposition is therefore an **input to D6, not deferred past it**. *Out of scope:* deciding relay-core's substrate future here.
- **D3 — Inherit the 09:06 schema, own the store.** Recorded as an amendment note on `id:2bb1`, not a cancellation.
  - **D3-A (supersedes D3, per finding 7).** **Withdrawn to OPEN**, pending D6 — a decision that was already annotated "partially overtaken" is born pre-drifted. Unconditionally and regardless of D6: the markdown→`2bb1` importer gets **one named owner** (`id:94ce`; other consumers consume its output, never re-implement), and the start-by backstop extends to **first-full-import**, not just `id:2bb1`'s start.
- **D4 — Brand screening standard for the name.** No in-category collisions accepted.
  - **D4-A (per finding 8).** Standard stands, on its **honest justification**: fleet-wide rename cost (~60 `CLAUDE.md` + committed `routed:` breadcrumbs), **not** D1's demoted forward-flag. "In-category" stays **undefined** until D6 settles (the collision set differs for a tracker adapter vs an orchestrator vs an agent CLI, and a fork largely inherits its upstream name). The screen is **re-run mechanically at ratification time** — "clean at time of search" has a short shelf life.
- **D5 — Name family: escapement (`escapement` / `detent`) — SELECTED, RATIFICATION HELD** until the scope settles. Clean at time of search, as are `tappet` and `leverframe`/`signalbox`. *Out of scope:* registering anything tonight.
- **D6 — Build vs adopt: OPEN. Measure first.** Two measurements gate the re-decision: the **`id:d5bd` mismatch triage** (single systematic serializer cause vs long tail of logic divergence) and the **incumbent baseline** of D1-A's metric. *Out of scope:* creating the new repo before those return.
- **D7 — A Beads spike gates the store question.**
  - **D7-A (supersedes D7, per findings 2 and 3).** The spike **gates the store question only, never D6** (tracker ≠ engine). Rescoped: run as an **adapter over the shipped `id:2bb1` fixture JSON** under `id:90f2`'s contract (incl. `id:857d`'s per-view-status clause) so its report is comparable to the Vikunja/Plane reports — **not** a hand-rolled markdown mapping, which would duplicate `id:94ce` and measure the spike author's effort rather than Beads' capacity. Must have a **pre-registered pass/fail criterion**, a **pinned `bd` version**, and run **in a clone** (`bd` writes `.beads/` into the working tree; relay ran live on loderite at 21:39 today). It must test `routed:2558`'s **actual** criterion: git-reviewable state transitions, offline edit, survives merge, ideally from Termux.
- **D8 — Vikunja/Plane pilot runs with Beads as a third candidate.**
  - **D8-A (supersedes D8, per finding 4).** **`id:330d` is decided first** (the offline/Termux write path), because it differentially kills two of the three arms before the race starts — a server cannot take a write from an offline phone. Only then: amend `id:90f2`/`id:da1a` **explicitly** to admit a third candidate, or record Beads as outside the pre-registration. *Out of scope:* running three arms while `id:330d` is undecided.

## --fabled closing pass

**Verdict: run. 8 findings; 6 forced amendments to already-ratified decisions; all accepted by the owner.** Against the pre-registered threshold of ≥2, the **escalation trigger FIRED** — this is the second recorded firing (after mathematical-writing 2026-07-31, 7/11) and is auditable evidence for building the per-decision Fable pass and the full multi-pass (`id:8df5` variants B and C).

Findings, abbreviated (full verbatim text is in the session transcript):

1. **D2's premise was false** — relay-core is live in shadow (95,663 rounds / 0.29% drift) and its island-2 gate has landed. A *third* mechanization implementation would start while the second accrues unassigned divergence.
2. **D7 was a category error** — Beads is a tracker, D6 is about the engine. Plus: no markdown importer in `bd`, no pre-registered criterion, and in-place import collides with the live relay run.
3. **The Beads facts were stale, and the `routed:2558` swap is criterion-drift** — the current README calls `.beads/issues.jsonl` *"an export for viewers and interchange, not the source of truth"*, which is the shape the 09:06 meeting **disqualified Taskwarrior 3 for**. `routed:2558` asks about *git-object storage*; answering it with "agent ergonomics + dependency DAG" is a criterion swap under the same gate name.
4. **D8 is incoherent with D3 and mis-sequenced against `id:330d`** — and the ledger still says "both adapters".
5. **"RED-spec + anti-gaming is the invention" is weak on both legs** — `relay-gaming-flags.log`: **726 review-integrations since 2026-06-24, 7 flagged, 6 adjudicated false-positive, exactly 1 genuine catch** (collaib `id:a37f`), and that one was premature ledger closure, not test-weakening; the audit is already mechanized in `gaming-scan.sh`. Caveats Fable kept: near-zero may be **deterrence**, and the one real catch was exactly the failure class markdown ledgers invite. Crucially, RED-spec authoring **does not discriminate build-vs-adopt** — it bolts onto any of them.
6. **D1's charter is not falsifiable as written** — the incumbent arguably already satisfies "mechanical-by-default" (~60 scripts, fixture corpora, backtests, a `--dry-run` parity oracle), and the irreducibly-LLM parts stay LLM in any successor. *"If the charter cannot name which specific LLM call-sites v1 eliminates, it is rhetoric."*
7. **D3 leaves contradictory ratified text live and nobody owns the importer** — three markdown-mapping implementations plausibly in flight; the never-started residual reopens because the start-by backstop bound only `id:2bb1`.
8. **Naming is substantially sound**; two nits recorded, not reversed (see D4-A).

**Fable's advisory net recommendation on D6** (declined as a decision, recorded as input): *keep the incumbent engine; add Beads as one more adapter against the shipped `2bb1` schema; spend the greenfield energy on the `id:d5bd` triage — the only open question with a measured dataset behind it.* Its own stated weakness: *"it does nothing for the owner's stated pain if the mess is conceptual sprawl rather than defect rate — no log I can read measures how much of the owner's own time the incumbent's complexity consumes, and that may be the real driver."*

## Action items

- [ ] `[INPUT — decision]` Author and ratify the **pre-registered pass/fail criterion** for the rescoped Beads adapter spike (D7-A) — owner call; without a threshold the spike settles nothing. `project_manager/TODO.md` <!-- id:c56a -->
- [ ] `[HARD]` **Beads adapter spike** over the `id:2bb1` fixture JSON under `id:90f2`'s contract, in a **clone**, pinned `bd` version; report unmapped constructs *and* test `routed:2558`'s actual criterion (git-reviewable transitions, offline edit, merge survival, Termux). Contract a future test would verify: the adapter's report is field-comparable to the Vikunja/Plane adapter reports. `project_manager/TODO.md` <!-- id:cb9e --> <!-- routed:2558 -->
- [ ] Decide `id:330d` (offline/Termux write path) **before** the tracker pilot runs; then amend `id:90f2`/`id:da1a` explicitly to admit a third candidate, or record Beads as outside the pre-registration (D8-A). → routed to `dotclaude-skills` inbox <!-- routed:14ed -->
- [ ] Name **one owner** for the markdown→`2bb1` importer (`id:94ce`); other consumers consume its output. Extend the start-by backstop to **first-full-import** (D3-A / finding 7). → routed to `dotclaude-skills` inbox <!-- routed:8440 -->
- [ ] Define the falsifiable **mechanical-by-default metric** and measure the **incumbent as baseline** from `RELAY_LOG` + `relay-gaming-flags.log` (D1-A / finding 6). Gates D6. → routed to `dotclaude-skills` inbox <!-- routed:1731 -->
- [ ] Un-gate island-2: `routed:2f0c` has landed (`id:77ce` done) — correct the stale "🚧 GATED" annotation in `relay-core/ROADMAP.md`; relay-core's disposition is an input to D6 (D2-A / finding 1). → routed to `relay-core` inbox <!-- routed:6309 -->
- [ ] *(already filed, cited not duplicated)* `id:d5bd` mismatch triage — now load-bearing for D6, not just for the flip gate.
