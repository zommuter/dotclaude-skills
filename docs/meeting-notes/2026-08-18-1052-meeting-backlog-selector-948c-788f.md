# 2026-08-18 — Selecting from a 218-item meeting backlog: `--triaged` (948c) and blocking-rank (788f)

**Started:** 2026-08-18 10:52
**Session:** 69603951-a444-4ea2-ad22-587134c770b8
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing per `meeting-style.md`)
**Topic:** How `/meeting` should select from a 218-item C3 backlog — `id:948c` (`--triaged`) and `id:788f` (blocking-rank) treated as one design surface.

> **How this meeting was reached.** The owner invoked `/meeting --fabled --triaged`. The
> arg-guard (`validate-flags.sh`, id:7681) correctly rejected `--triaged` as unknown and
> dropped it rather than folding it into the subject. It then turned out `--triaged` is not a
> typo but a **filed, unbuilt feature** — `id:948c`, INBOUND `routed:c8d7` from `escapement`.
> The guard behaved exactly as designed; the flag simply does not exist yet.

## Measured state at meeting time

- `classify.sh` over `TODO.md`: **218 C3** (meeting-worthy), 91 C2, 39 C1; plus 91 EXEC / 34 POOL / 11 HANDS / 5 HUMAN / 1 MECH surfaced as not-meeting-worthy. `head -1` of C3 would have picked `id:9d06`.
- 55 lines carry a `gated-on:` edge — **10 in `ROADMAP.md`, 45 in `TODO.md`**. `resolve-gates.sh` reports 6 ROADMAP items with unresolved gates; `roadmap-lint.sh` emits 9 gate warnings.
- `orphan-scan.sh --cross-ledger`: 3 rows at meeting start (`cd9c`, `d119`, `ec3c`); **1 row by meeting end** — see D4.
- Typed-edge vocabulary in `lib-typed-edges.sh`: `children_of`, `gated`, `settles`, `decided_in`, `owner_hold`, `own_id`, `dep_prose`. **No coupling / same-session relation exists** — confirming `948c` constraint (c).

## Agenda

1. Are `id:948c` (combination-forming) and `id:788f` (blocking-rank) one mechanism or two?
2. The coupling-edge schema — what relation, and where does it live?
3. Gate-state verification: mechanical, or an honestly-declared LLM step?
4. Constraint (b)'s replacement gate, and whether the no-prompt path should exist at all.

**Agenda item 2 was dissolved by D1** — the coupling edge records combinations, so it goes with the deferred half.

## Discussion

**Item 1 — one mechanism or two.** 🏗️ Archie argued `788f` is the ranking function `948c` consumes: a combination-former needs a reason to prefer one grouping, and blocking weight is that reason. 😈 Riku rejected the derivation on the evidence: blocking weight ranks items *individually* (how much does X unblock), while a combination is about *relatedness* (do these belong in one session), and they come apart immediately — the three highest-blocking items may sit in three unrelated subsystems and produce a session with no thread, while two items blocking nothing may be the ideal pair because they share a premise. Ranking gives *what matters*; combination needs *what coheres*.

✂️ Petra pressed the N=2 rule: if only `948c` consumes the ranking, it is a scoring pass, not an artifact. 🏗️ Archie named `/relay human` as the second consumer — the surface that this morning listed 65 meeting-lane items with no ordering at all. ⚙️ Sage added the decisive asymmetry: `788f`'s ranking is derivable **offline** from `lib-typed-edges.sh` — no model, no session — while `948c` explicitly says "the model forms the COMBINATION". They sit on opposite sides of the mechanize-first line, so the ranking can run in `relay-doctor.sh`, on a timer, in a statusline; the combination cannot.

😈 Riku then named the failure mode that shaped D1b: if blocking weight is the *only* input, the selector systematically starves items that block nothing — most of a 218-item backlog, including the settled-but-open class. A ranking sorted by downstream blocking buries exactly the items whose problem is that nothing depends on them any more. 🏗️ Archie conceded, noting `788f` as filed already says such items are "PARKED OPENLY … not silently deprioritised".

**Item 3 — is gate-state verification mechanical?** 😈 Riku showed the mechanism failing its own test with two primitives that disagree: `resolve-gates.sh` resolves over ROADMAP ∪ TODO ∪ both archives (its `:31` comment says the executor gate must see an archived resolution), while `roadmap-lint.sh` calls the same edge a `DEAD-GATE`. On `id:2b49` these gave opposite answers this morning, and the lint's recommended remedy — drop the marker — would have destroyed a correct dependency edge.

⚙️ Sage reframed it and found the hole in `948c` constraint (e): it offers a binary between "mechanical" and "honestly-declared LLM step", but **both scripts are fully mechanical, deterministic and tested — they simply disagree**. The actual failure is two mechanical answers and no adjudicated definition; an LLM step would not help, it would just pick one. 🏗️ Archie proposed making `resolve-gates.sh` the single definition. 😈 Riku escalated: that makes the disagreement a fourth instance of `id:7877`, whose class had been recorded that morning as standing at three and explicitly not growing.

*(The closing Fable pass subsequently refuted both the single-definition framing and the fourth-instance count — see Amendments.)*

**Item 4 — second signal and constraint (b).** ⚙️ Sage proposed cross-ledger drift as the cheapest discriminator between "blocks nothing because resolved" and "blocks nothing because nothing depends yet" — mechanical, already shipping, zero cost. 😈 Riku bounded it: it is **sound but badly incomplete**, catching the 3 drift rows but missing `id:2419` (fixed in code, test green 16/16, box still open) and `id:bf54` (subsumed by `id:43c8`) — so at least 5 known settled-but-open items and the signal detects 3. ✂️ Petra: name the limit in the artifact and stop; `orphan-scan --shipped` is ADVISORY-only and fires on 57+ candidates, so folding it in now buys noise.

On constraint (b), 🏗️ Archie observed D1 had changed its status — it gates the no-prompt path, which now lives in the deferred half — so amending it is bookkeeping on a constraint nothing pends on. 😈 Riku argued that is exactly when to write it: a falsified premise left in place gets re-read as live by the next reader, who will not have this morning's finding.

## `--fabled` closing pass

Run per the `--fabled` flag. `fable-config.sh check` → `available`, so the pass ran for real (no degrade). One Fable-5 subagent, fed the ratified decisions verbatim plus the measured facts, framed as design critique. **7 findings: 3 FORCES-AMENDMENT, 4 HARDENING.** All three forced findings were independently re-verified against the code before acceptance; two of the three were confirmed by the facilitator's own commands.

**Escalation trigger FIRED — 3 forces-amendment ≥ 2. This is the 5th recorded firing** (`id:43c8` records four: 4 / 4 / 5 / 7). Consistent with the recorded design steer: all three forced findings were premises about *what the code actually does*, verifiable by reading it.

Finding 2 carries a sting worth preserving: **D3b corrected one count by corrupting another** — it padded `id:7877`'s instance count in the course of a session whose own forced-amendment count feeds a pre-registered trigger.

## Decisions

**Decision provenance:** ratified via `AskUserQuestion` at each decision point; amendments ratified at the second closure gate after the `--fabled` pass.

- **D1 — `id:948c` and `id:788f` are TWO artifacts; build the RANKING only.** Defer `948c`'s combination-forming. *Amended per F5:* the un-defer criterion as first ratified ("until we know whether a machine-formed combination beats reading the list") was **circular** — unknowable without building the deferred artifact. It becomes the evaluable form: **defer until manual picking is judged insufficient**, with a recorded trigger, owner and venue so the deferral cannot become forever-by-accident. *Also per F5:* `948c` axis 2 (gate-state verified, not tag-trusted) is **absorbed into `788f`'s build-time acceptance** as a one-time check, NOT deferred with `948c` as a per-session-open check. **Out of scope:** the coupling-edge schema (`948c` constraint (c)) — it records combinations, so it goes with the deferred half; this dissolves agenda item 2.

- **D1b — Blocking weight is ONE SIGNAL, not the ranking.** An item blocking nothing because it is already resolved must sort differently from one blocking nothing because nothing depends on it yet. **Out of scope:** any weighting formula — the decision is that the signal is plural, not what the weights are.

- **D3 — AMENDED (supersedes the ratified wording).** As first ratified: "`resolve-gates.sh` is the source of truth and `roadmap-lint` consumes it rather than re-deriving." **That is withdrawn.** Fable finding 1 showed, and the facilitator confirmed at `roadmap-lint.sh:348-354`, that the two tools answer **different questions by documented design** — resolve-gates answers *is this dispatchable now* (satisfaction); the DEAD-GATE rule answers *can this gate ever open through the execution queue* (location) — and the comment names resolve-gates as "correctly" merging for "its own, different question". Consuming it would erase the never-promoted class, which is live today (`d4ca`→`09e4`, `e405`→`09e4`, `540f`→`b0b1`, `c179`→`b0b1`). **The amended decision:** share the satisfaction **predicate/state-map** (ticked-anywhere-in-span ⇒ SATISFIED, never a warning) and **keep** roadmap-lint's three-way location taxonomy. Root cause is one branch — `roadmap-lint.sh:532` tests archive-map *existence* (`${RL_GATE_ARCHIVE[$_dg_t]+x}`) and never the stored checkbox *state*; since `archive-done.sh` archives only `[x]` items, essentially every archive hit is a false PERMANENT verdict (`2b49`, `540f`, `c179` today). **Out of scope:** rebuilding the location taxonomy on a shared source. Note the first ratification was **broader than its own source defect** (`id:8de9`, TODO.md:496) and contradicted it.

- **D3b — REVERTED.** As first ratified, the lint/resolve disagreement was recorded as `id:7877`'s **fourth** instance. **That is withdrawn.** Fable finding 2 showed it fails the ratified signature ("the same fact computed twice **in one round** by two different methods, **one result discarded**") on all three qualifiers: not the same fact (the code comment documents a deliberate different-question split); nothing discarded (both outputs are emitted and consumed — `classify-repo.sh:36,107` consumes resolve-gates; roadmap-lint runs on the doctor/handoff/human paths); not one round (different drivers, different invocation contexts). `id:7877` forbids widening twice in its own text, and the widened reading is not self-consistent at n=4 — `id:ca9e`'s edit-integrity note from the same morning would be a fifth. **`id:7877` stays at n=3.** The disagreement files under the existing `id:8de9`, which already names "two implementations of one predicate is the drift that caused this". **Out of scope:** widening `7877`'s signature — that would make it a different and harder detector.

- **D4 — Signal two is CROSS-LEDGER DRIFT, sound-but-partial.** It detects the drift subset and **not** the code-fixed-but-unticked (`2419`) or subsumed (`bf54`) shapes; that limitation is stated in the artifact so the next reader does not mistake the detected rows for the whole class. *Hardened per F4:* **record the signal, never the count.** The population went 3 → 1 within this session (`cd9c` and `d119` were resolved by a concurrent relay review), and the surviving row `ec3c` is `[ROUTINE]`, not a meeting-lane item — so signal two contributes **zero** rows to the ranked population today. The artifact must invoke the scanner at **build time**; a baked-in count is false on arrival. **Out of scope:** folding in `orphan-scan --shipped` TICK-READY as a third signal (ADVISORY-only, 57+ candidates, buys noise).

- **D4b — `id:948c` constraint (b): premise FALSIFIED, gate re-anchored.** Its "~9-10 known settled-but-open instances" were **loderite's**, and that half is DONE (2026-07-24, 16 findings, all owner-ratified). This repo's residue is of **unknown** size. *Hardened per F6:* the replacement gate must name a **defined milestone**, not an artifact `id:d1fb` is not scoped to produce — `d1fb` is the full loderite-recipe sweep (Opus pass + Fable cross-audit + per-finding ratification), and its mechanical candidate-list attempt on 2026-08-18 mostly failed. Either write `gated-on:d1fb` plainly, or name the worksheet milestone precisely; as first worded it failed `948c` constraint (e)'s own machine-checkable standard. **Out of scope:** deciding the no-prompt path itself — that belongs to whoever picks up the combination half.

- **D5 — `D3` does NOT gate `id:788f`** (new, per F7). Verified: `resolve-gates.sh` already returns the correct satisfaction answer today (no `2b49` row; the six blocked rows are `d4ca`/`e405`/`540f`/`c179`/`554b`/`a955`), and the ranking does not consume `roadmap-lint`. **The ranking dispatches immediately, in parallel with D3.** Recorded explicitly because the owner asked for a selector and the ratified set otherwise reads as a three-link repair chain in front of it — sequencing `D3 → 788f` would put the selector behind a dependency it never had.

## Action items

- [x] **Amend `id:788f`'s consumption clause** — it directs the implementer to consume `resolve-gates.sh` and "never re-derive the edge set by grep", but `resolve-gates.sh:45-49` iterates **only `ROADMAP.md`** for edge-carrying lines and emits nothing for a satisfied edge. 45 of 55 `gated-on:` lines live in `TODO.md`, so an implementer obeying that clause literally builds the blocking graph from ≤10 of 55 edges with zero satisfied-edge data — making D1b's distinction unsatisfiable. Name `lib-typed-edges.sh`'s extractors + `typed_edges_build_state_map` over the four-ledger span as the consumable primitive; record that `resolve-gates.sh` is the wrong shape for a **reverse** graph (forward-direction, ROADMAP-only, silent-on-clean). Contract: a future test asserts the graph accounts for every `gated-on:`-carrying line across all four ledgers. — `TODO.md` `id:788f`

- [x] **Amend `id:8de9`** (`TODO.md:496`) to carry the narrow D3 fix and the lint/resolve disagreement — share the satisfaction predicate/state-map, keep the three-way location taxonomy, fix `roadmap-lint.sh:532` to test archive checkbox *state* not existence. Contract: a fixture whose gate target is `[x]` in `TODO.archive.md` yields SATISFIED (no warning), while a target living only in `TODO.md` still yields the never-promoted warning — assert both, since a positive-only test passes against a lint that warns on nothing. — `TODO.md` `id:8de9`

- [x] **Amend `id:7877`** — revert the n=4 count recorded earlier this session; the class stays at **three**, and the reasoning (all three signature qualifiers fail) is recorded so it is not re-counted. — `TODO.md` `id:7877`

- [x] **Amend `id:948c`** — constraint (b) premise falsified and gate milestone defined (D4b); constraint (e)'s mechanical-vs-LLM binary corrected to name the real failure mode (two mechanical answers, no adjudicated definition); axis 2's disposition recorded per D1. — `TODO.md` `id:948c`

- [x] **Record `id:43c8`'s escalation count at 5** — the trigger fired again this session (3 forces-amendment). — `TODO.md` `id:43c8`
