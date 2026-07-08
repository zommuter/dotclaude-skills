# 2026-07-08 — Lean4 as the relay mechanization substrate (id:23ab)

**Started:** 2026-07-08 13:37
**Session:** 3de99894-0034-4720-8491-fef80a0ee58b
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🔬 Greta (proof-engineering), 🔬 Lennart (Lean4/Mathlib ergonomics), 🎛️ Orla (multi-agent orchestration / executor economics)
**Topic:** Decide the shape of adopting Lean 4 as the *implementation* substrate for the relay mechanization core (not proofs-about-bash): toolchain/install, pilot island order + flip gates, theorem-vs-types policy, executor-lane economics, and the honest Lean-vs-Rust diligence.

> Method note: three **Fable background agents** (verified `claude-fable-5`, none degraded to Opus) supplied independent diligence on the three hardest questions (substrate, toolchain, theorem policy). Their takes are quoted inline and were pressure-tested by the personas before ratification.

## Agenda
1. Substrate diligence — Lean 4 vs Rust, answered honestly (the gating question).
2. Toolchain / install / triad coordination — elan/lake, shared pin with mathematical-writing (id:aae4), sibling `relay-core` repo + GH-release binaries, opt-in capability-detect.
3. Pilot = classify-verdict port — island order + flip gates + prerequisite bash sequencing.
4. Theorem-vs-types-only policy per module.
5. Executor-lane economics — HARD-lane initially; does theorem-gated delegation flip that?

Explicitly OUT of scope (guardrails, per the item): "prove the relay" wholesale; the full `/relay` repo split (id:a72c, trigger-gated); big-banging the week-old bash mechanical layer.

## Discussion

### Agenda 1 — Substrate diligence: Lean 4 vs Rust

**Independent Fable diligence take:** recommends **Rust**. The stated 80% ("types not theorems") is delivered in full by Rust's type system — `serde(deny_unknown_fields)` = total parsers; `match` on sum types = exhaustiveness; a shared vocabulary crate kills the substring/enum-mismatch class; `Result` + `#[must_use]` + checked `ExitStatus` kills swallowed exits. Every past bug is by-construction in Rust too. So Lean's case rests entirely on the 20% theorems — and those (`reap ∩ live = ∅`, `unknown ⇒ ∅`) are *shallow, non-inductive* properties of small pure functions, which **Kani / Creusot** (bounded model checking for Rust) discharge. Lean's unique value only begins at unbounded/inductive invariants this core never reaches. Rust also has the most-paved binary-distribution road (`cross` + musl + a 20-line GH matrix); a Lean public toolkit has "bus factor ≈ you." Named flip conditions: (a) invariants deepen to inductive/temporal; (b) the triad shares actual Lean *code* (a lib imported by ≥2 repos); (c) binary distribution is dropped.

🔬 **Greta:** Honest verdict, won't soften it. Kani closes the reap invariants. The one thing Kani does *not* give you is *no spec/impl drift*: in Rust the invariant lives in a proptest and in your head; a refactor can weaken the `DeadClaim` constructor and the property test under-samples. In Lean the proven term **is** the shipped function — `reap_fail_closed` cannot silently disarm, exactly the recorded bug class. The real question is how much you value drift-proofness over ecosystem maturity.

😈 **Riku:** Then name the property Rust+Kani cannot give, or admit this is "I like Lean." The *pilot* is classify-verdict — types-only (Fable agrees, zero theorems). It never exercises Lean's differentiator. You'd pay the exotic-substrate distribution + bus-factor tax up front on an island Rust does more cheaply and that never touches the 20% Lean is for.

✂️ **Petra:** So the call turns on one crux: *is the triad-shared-Lean-code future real or aspirational?* If the Grand-Truth shared verification tier (chidiai id:79ee, owned by aae4) will actually `import` Lean across ≥2 repos, Lean's ecosystem cost amortizes across the triad and Fable's own flip-condition (b) fires. If relay-core is a Lean *island*, Rust+Kani wins on diligence.

🏗️ **Archie:** The plan/apply architecture is substrate-agnostic — Lean buys nothing architecturally we couldn't get in Rust. The decision is purely (drift-proofness + triad reuse + existing investment) vs (ecosystem + distribution + bus-factor).

🔬 **Lennart:** Lean's systems libs (`Lean.Data.Json`, `IO.Process`, `batteries`) are adequate but sparse — more glue than Rust. Elaboration latency is irrelevant for a shipped binary. The user's weekly elan/Mathlib muscle memory drops marginal cost to near-zero.

⚙️ **Sage:** Distribution/opt-in is identical either way — capability-detect a binary on PATH, else bash. Neither language changes the `/relay`-works-without-it contract.

😈 **Riku (held):** If the answer is "Lean because triad reuse," that reuse must be a *named, near-term* consumer, not "future plugin X." Petra's N=2 rule applies to the substrate itself.

**→ DECISION 1 (ratified): Lean pilot, substrate REVISITABLE.** See Decisions.

### Agenda 2 — Toolchain / install / triad coordination

**Independent Fable take:** elan everywhere (never system/pamac Lean — Lean releases monthly, Mathlib needs exact matches). Each repo carries its own `lean-toolchain` file (elan multiplexes per-dir), but all three hold the **same version string**, dictated by **mathematical-writing's Mathlib pin** — that repo is the constrained one, so its `lean-toolchain` is THE triad canonical. Bump cadence: when aae4 bumps Mathlib, relay-core bumps the same week. Drift cost: nothing for repos sharing no code (elan isolates; relay-core ships a binary) — the cost appears only when the shared tier `import`s across repos (`.olean` is toolchain-locked). relay-core's lakefile has **zero `require mathlib`** (transitive drags in the multi-hour build); `batteries` is fine. Layout: sibling repo, normal lake package (`lean_exe relay-core @[default_target]`), vX.Y.Z bump-and-tag, per-arch GH-release binaries; toolkit capability-detects on PATH → bash fallback. CI: linux-x86_64 on `ubuntu-22.04` (oldest glibc), linux-aarch64 on `ubuntu-22.04-arm` (native, free for public repos); static-link via `moreLinkArgs` + verify `ldd`. 32-bit armv7 Pis: Lean 4 doesn't target them → bash fallback (document, don't fight). Guard: relay-core CI fetches aae4's canonical `lean-toolchain` and **warns loudly** (not hard-fails); other repos' CLAUDE.md carry a one-line *pointer*, never a copied version string.

⚙️ **Sage:** Matches house doctrine — SSOT pin (aae4's file), no re-derived version strings, loud drift-warn not silent copy. The capability-detect + bash-fallback is the same CASE A/CASE B shape id:7402 just shipped, so relay-doctor already has the idiom for "mechanical core absent — legacy bash path."

🔬 **Lennart:** Zero-Mathlib for relay-core is right — `require mathlib` inherits `lake exe cache get` + a multi-hour cold build; `batteries` is the ceiling. The Mathlib-driven pin is one-directional and harmless.

✂️ **Petra:** Low-regret: aae4 is *already* Lean, so the triad pin exists regardless of relay-core's eventual substrate. relay-core merely *follows* it; if it later forks to Rust, it stops following. Safe under Decision 1's revisitability.

😈 **Riku:** "warn not fail" can ossify if nobody reads CI warnings — but hard-fail on a monthly upstream cadence blocks unrelated work, and relay-doctor is the backstop. Accept warn, but it must be LOUD (relay-doctor line, not a buried CI log).

### Agenda 3 — Pilot islands + flip gates

🏗️ **Archie:** Order is dictated by value/risk. **Island 1 = classify-verdict** (types-only): cheapest real port, ready parity oracle, shakes down toolchain/distribution/flip machinery without theorems. **Island 2 = reconcile planner** (theorem-bearing): highest value but also the substrate-revisit gate. Order forced: 1 then 2.

⚙️ **Sage:** Flip reuses the **a0b6 machinery** verbatim — shadow the Lean binary alongside bash behind the *existing* JSON contract, diff outputs (backtest parity on the fixture corpus), gate the flip on parity + N clean rounds, keep bash as fallback until the flip. Strangler, not big-bang.

😈 **Riku:** Prerequisite: land **id:4860/0fa0/1cb8 in bash first.** Not throwaway — (1) they de-risk the *live* path while Lean is weeks out; (2) the fixed bash IS the parity oracle. Porting first would bake the bugs into the golden corpus.

🏗️ **Archie:** Agreed. Parity = **100% exact match** on the corpus (any diff blocks — a classifier disagreeing on one fixture is not at parity) + **N=5** clean consecutive shadow rounds (mirrors the model-probe c-chart discipline, id:23e9) before freezing bash.

✂️ **Petra:** Pilot is classify-verdict ONLY. DoD = exact parity + 5 clean rounds + capability-detect/bash-fallback + relay-doctor live-path report. Reconcile planner (island 2), a72c, "prove the relay" are out.

**→ DECISIONS 2 & 3 (ratified).** See Decisions.

### Agenda 4 — Theorem-vs-types-only policy per module

**Independent Fable take:**

| Module | Verdict | Why |
|---|---|---|
| classify-verdict | **Types-only** | Substring-match class dissolved by construction — a sum type + total parser leaves no string to substring-match. A theorem restates the type checker. |
| reconcile planner | **THEOREMS — flagship** | "reap-set avoids live claims" is semantic, not type-shaped. The authorized-but-wrong class the OS sandbox explicitly *cannot* catch (containment ≠ authorization) — the one place a proof buys what nothing else does. |
| parsers / vocabulary | **Types-only** + one cheap `parse∘render=id` lemma | Both recorded bugs are type-shaped (missing-field-disarm dies under compile-forced handling; two-call-site mismatch dies under one shared sum type). More is gold-plating. |
| claim/lease | **Mostly types-only; one small theorem** | "INTENSIVE never on a human lane" → make it *unrepresentable* (index the flag by lane type). TTL/mtime: one cheap fail-closed theorem (unparseable mtime ⇒ no reclaim). |

Load-bearing theorems: (1) `reap_fail_closed : claimContext = unknown → reapSet = ∅` — cheap, ship rung one with island 2; (2) `reap_live_disjoint : reapSet ∩ liveClaims = ∅` — **per-input** form first; the "every reachable state" version needs the I1–I9 state machine formalized = staged rung two.

🔬 **Greta:** Prefer *unrepresentable* over *proved* wherever types reach (the INTENSIVE-by-lane-type indexing is the model case) — a proof you don't write can't rot. Reserve theorems for the semantic residue, which here is essentially just the reconcile planner. Enforce axiom hygiene: `#print axioms` on every named theorem, lint out `sorry`/`native_decide`/stray `axiom`, else a "proved" lemma can be vacuous.

🔬 **Lennart:** `reap_fail_closed` ≈ near-`rfl` (guard-structure fact). `reap_live_disjoint` per-input is a tractable finite-case decision-procedure proof. Only the reachable-state version is real proof-engineering cost, correctly deferred. Island 2's first rung is cheap.

😈 **Riku:** Types-only is a legit first rung everywhere EXCEPT — don't ship island 2 without `reap_fail_closed`. That theorem is *why bash wasn't good enough* (the e0f8 near-miss).

### Agenda 5 — Executor-lane economics

🎛️ **Orla:** Economics turn on verification class. (1) **types-only port** — mechanical, type-guided; once the first island establishes the idiom this is ROUTINE-lane-able. (2) **theorem authoring** (stating the invariant) — the hard reviewer act, apex/HARD, non-delegatable. (3) **proof filling against a pinned statement** — the unlock: a reviewer-pinned statement + `sorry` is an **ungameable RED spec** (`lake build` + `#print axioms` clean can't be faked, unlike a weakenable test), so delegatable *in principle*.

😈 **Riku:** "In principle" carries weight — Lean proof-search is genuinely hard and no executor-tier competence is demonstrated yet. Document the mechanism, but gate the lane-flip on evidence: a demonstrated executor Lean proof on a near-`rfl` lemma first.

🎛️ **Orla:** So the honest position: islands 1 & 2 are both apex/HARD-lane initially; the delegation economics is a future unlock, flipped per-theorem after the idiom is established AND an executor closes a clean pinned proof.

✂️ **Petra:** Relay synergy cuts favorably too: a theorem-backed module can be gate-*asserted* with cheaper *review* — the mesh applied to the relay's own review economics. A consequence, not a thing to build now.

🎛️ **Orla (post-ratification, user evidence):** The user notes **toesnail already ships Lean that the Opus tier handled** (Sonnet untried). Opus-tier executor Lean competence is thus *established*; the remaining evidence bar is narrowly a **Sonnet-tier** demonstration on a pinned near-`rfl` proof. Second-order: toesnail being real Lean *code* in the triad moves Decision 1's substrate-commit crux toward "triad reuse is real, not aspirational."

## Decisions

- **D1 — Substrate: Lean pilot, REVISITABLE.** The classify-verdict pilot runs in Lean (exercising toolchain/distribution/flip machinery cheaply). Lean-vs-Rust+Kani stays re-decidable at the **island-2 go/no-go**, judged on (i) whether Lean's systems ergonomics held up in the pilot and (ii) whether triad Lean *code*-reuse is a named consumer by then (toesnail's live Lean + the aae4-owned shared verification tier are the evidence). If either fails, island 2 forks to Rust+Kani/Creusot. *Out of scope:* a final all-triad substrate commitment now; the Fable Rust verdict is recorded as the honest counter-case, not adopted.
- **D2 — Toolchain: adopt Fable's scheme as recommended.** elan everywhere (never system Lean); each repo has a `lean-toolchain` file, all pinned to **mathematical-writing/aae4's canonical (Mathlib-constrained) version**; relay-core lakefile has **zero `require mathlib`** (`batteries` ceiling); relay-core is a **sibling repo**, normal lake package (`lean_exe relay-core @[default_target]`), **vX.Y.Z bump-and-tag**, per-arch **GH-release binaries**; the toolkit **capability-detects on PATH → bash fallback**; CI builds linux-x86_64 on `ubuntu-22.04` + linux-aarch64 on `ubuntu-22.04-arm` (native, free), **static-link via `moreLinkArgs` + `ldd` verify**; 32-bit armv7 Pis take the bash fallback (documented); drift guard = relay-core CI fetches aae4's `lean-toolchain` and **warns LOUDLY via relay-doctor** (not hard-fail); other triad repos' CLAUDE.md carry a one-line *pointer*, never a copied version string. *Out of scope:* hard-fail drift; in-repo lake package forced on toolkit consumers.
- **D3 — Pilot sequence + flip gates.** Land **id:4860/0fa0/1cb8 in bash FIRST** — they become the golden parity oracle (porting first would bake the bugs into the corpus). **Island 1 = classify-verdict** → **Island 2 = reconcile planner** (= the substrate-revisit gate). Reuse the **a0b6 flip machinery** (shadow behind the existing JSON contract → backtest parity → gated flip → bash fallback until flip). Flip gate = **100% exact backtest parity on the fixture corpus** (any diff blocks) **+ N=5 clean consecutive shadow rounds** before freezing bash. Pilot DoD = binary at exact parity + 5 clean rounds + capability-detect/bash-fallback wired + relay-doctor reports the live path. *Out of scope:* reconcile planner (island 2), a72c repo-split, "prove the relay."
- **D4 — Theorem-vs-types policy (per-module).** classify-verdict, parsers, claim/lease = **types-only** (+ cheap `parse∘render=id` round-trip lemma; + cheap fail-closed-mtime lemma on claim/lease). Prefer **unrepresentable over proved** wherever types reach (index the INTENSIVE flag by lane type so "INTENSIVE on a human lane" is unconstructable). **reconcile planner = theorems:** `reap_fail_closed` (unknown ctx ⇒ ∅) + `reap_live_disjoint` **per-input** form at **rung one** (ship with island 2); the "every reachable state" version (needs the I1–I9 state machine formalized) is **staged rung two**, non-blocking. **Axiom hygiene mandatory:** `#print axioms` on every named theorem + lint out `sorry`/`native_decide`/stray `axiom`. Do **not** ship island 2 without `reap_fail_closed`. *Out of scope:* theorems on classify-verdict/parsers (types suffice); the reachable-state disjointness proof at rung one.
- **D5 — Executor-lane economics: apex-initial, delegation gated (observe-first).** Islands 1 & 2 are **both apex/HARD-lane initially.** Document the mechanism — a reviewer-**pinned theorem statement + `sorry`** is an **ungameable RED spec** (`lake build` + `#print axioms` clean cannot be faked, unlike a weakenable test) — as the future delegation unlock. Flip **proof-filling** to a cheaper executor lane **per-theorem**, only after the types-only idiom is established AND the remaining evidence bar is met. **Evidence refinement (user):** Opus-tier executor Lean competence is already demonstrated (toesnail); the outstanding bar is narrowly a **Sonnet-tier** demonstration on a pinned near-`rfl` proof. Per-theorem difficulty decides the lane; never a blanket flip. *Out of scope:* delegating types-only ports to Sonnet now; building the tiered-review economics.

## Action items
- [ ] Create sibling **`relay-core`** Lean repo: elan + `lean-toolchain` (follows aae4 canonical), zero-Mathlib lakefile (`batteries` OK), `lean_exe relay-core @[default_target]`, vX.Y.Z bump-and-tag, CI per-arch GH-release binaries (x86_64 `ubuntu-22.04` + aarch64 `ubuntu-22.04-arm`, static-link + `ldd` verify), capability-detect on PATH → bash fallback, relay-doctor "mechanical core absent — legacy bash path" line + LOUD toolchain-drift warn. (D2) <!-- id:50c4 -->
- [ ] **Island 1 pilot** — port `classify-verdict` to Lean behind the existing JSON contract using the a0b6 strangler; flip gate = 100% exact backtest parity on the golden fixture corpus + N=5 clean consecutive shadow rounds; DoD includes capability-detect/bash-fallback + relay-doctor live-path report. **Blocked-on:** id:4860/0fa0/1cb8 landing in bash first (golden oracle). (D3) <!-- id:82c4 -->
- [ ] **[GATED on island 1 shipped] Island 2** — reconcile PLANNER in Lean with `reap_fail_closed` + `reap_live_disjoint`(per-input) at rung one, reachable-state version staged rung two; axiom hygiene (`#print axioms` + lint `sorry`/`native_decide`/`axiom`); INTENSIVE-flag-by-lane-type unrepresentable. **This item IS the D1 substrate-revisit go/no-go** (Lean ergonomics held + triad Lean code-reuse named ⇒ proceed in Lean; else fork to Rust+Kani). (D1, D4) <!-- id:ba31 -->
- [ ] Executor-lane: document the pinned-statement → ungameable-acceptance (`lake build` + `#print axioms` clean) delegation mechanism in the relay contract; keep islands apex-lane; flip proof-filling to Sonnet-executor lane only after a demonstrated **Sonnet-tier** near-`rfl` Lean proof (Opus-tier already shown via toesnail). (D5) <!-- id:7746 -->
- [ ] → routed to **mathematical-writing** inbox: own the canonical triad `lean-toolchain` pin + add `docs/lean-toolchain-policy.md` (policy + bump-together cadence); triad repos carry a one-line pointer. <!-- routed:b8e5 -->

## Amendment — post-meeting strong-model review (Fable 5, 2026-07-08)

The meeting ran under Opus 4.8 (a Fable server-side safeguard false-positived on the
`/meeting` invocation — [[fable-safeguard-false-positive-2026-07-08]]; three Fable
background agents contributed diligence inline, but the persona synthesis + ratification
turn was Opus). This is the Fable second-opinion pass over the ratified note, verified
against the codebase and the session transcript. **No decision is overturned** — D1–D5
stand. Transcript fidelity check: the note renders the user's answers faithfully,
including the toesnail hedge ("at least Opus could handle, not sure if Sonnet tried"),
correctly narrowed to a Sonnet-tier evidence bar in D5. Four findings extend D2/D3/D4/D5;
constraints folded into the TODO twins (id:50c4/82c4/ba31/7746) in the same commit.

- **F1 — the island-1 blocker is broader than its own rationale (D3) — PROPOSED
  downgrade, needs user ratification.** D3's stated reason for "land id:4860/0fa0/1cb8 in
  bash FIRST" is that the fixed bash becomes the parity oracle ("porting first would bake
  the bugs into the golden corpus"). Verified: **none of the three items touched the
  ported module.** `classify-verdict.sh` — the island-1 port target, pure JSON→JSON — was
  last changed by the id:c79e/7616 work (7622c2d, 3231091, 1f66497); id:4860 fixed
  producer `queue_sig` stamping + relay-loop.js CASE A copy logic, id:0fa0 fixed producer
  robustness, id:1cb8 hardens `mechanical-daemon.sh` — all three live in components that
  stay bash regardless of island 1, and none alters classify-verdict's input/output
  contract or its fixture corpus. With 4860+0fa0 landed (archived 2026-07-08), the only
  remaining hard blocker on id:82c4 is 1cb8 — a large `[HARD — pool]` daemon item whose
  fixes cannot appear in the pilot's corpus. Riku's argument (1) (de-risk the live path
  while Lean is weeks out) is a scheduling priority, not an oracle dependency. Proposal:
  downgrade 1cb8 from blocked-on to "parallel de-risk, before the FLIP at the latest";
  island 1 is otherwise startable now.
- **F2 — "100% exact match" parity needs a pinned canonical JSON form (D3).**
  `classify-verdict.sh:217` emits CPython `json.dumps` bytes: insertion-ordered keys,
  `", "` separators, ASCII escapes. Lean's `Lean.Data.Json` objects serialize with their
  own key ordering — a byte-diff harness false-fails on every output forever, and "make
  Lean reproduce CPython serialization" is brittle wasted work. (The existing byte-parity
  regression guard, `classify-repo.sh:158`, is bash-vs-bash and unaffected.) Constraint
  (id:82c4): the flip gate compares **canonicalized** JSON — `jq -S -c .` on BOTH outputs;
  "100% exact" = byte-equality of the canonical forms, with the `evidence` array ORDER
  declared part of the contract (it is deterministic in bash).
- **F3 — D5's "ungameable acceptance" has named gaming vectors; the gate needs a
  diff-surface restriction + an attribute lint, not just `lake build` + `#print axioms`.**
  (a) `@[implemented_by]`/`@[extern]` swap the **compiled** implementation away from the
  proven definition — theorem still true, build green, axioms clean, the shipped binary
  runs unproven native code; `#print axioms` cannot see attributes. (b) A proof-filling
  executor can weaken a **definition the pinned statement references** (statement text
  unchanged, proposition changed) — pinning the statement string is not pinning the
  proposition. (c) `partial`/`unsafe` in helper defs dodge totality. Constraints
  (id:7746 + id:ba31): the reviewer commits `theorem … := sorry`; executor acceptance =
  the diff touches **only the `sorry` replacement** (mechanically checkable), which
  structurally excludes (b)+(c); and the axiom-hygiene lint extends to `implemented_by`,
  `extern`, `unsafe`, `partial` in the proven core (legitimate ONLY in the declared
  effectful rind, reviewer-owned). With those two additions the ungameable claim holds.
- **F4 — D2's drift guard is unimplementable as ratified: aae4 has no GitHub remote.**
  Verified: mathematical-writing's only remote is a private SSH remote on fievel, and no
  `lean-toolchain` file exists there yet (routed:b8e5 creates it). A public relay-core's
  GH CI cannot fetch the canonical pin. Fix: the drift CHECK moves to where D2 already put
  the WARN — **relay-doctor compares the two local checkouts** (`~/src/mathematical-writing/lean-toolchain`
  vs relay-core's); relay-core CI asserts only internal consistency (its own
  `lean-toolchain` vs what the lakefile expects). Constraint folded into id:50c4.
- **Minor (id:50c4):** `lean_exe relay-core` — a hyphen is not a Lean identifier; use
  `lean_exe «relay-core»` (or name it `relay_core` and rename the release artifact).
  Static linking needs the static archives installed on the runner (libgmp; recent
  toolchains also link libuv) — the ratified `ldd` verify is the catch if they're missing.
  `batteries` is toolchain-coupled too: bump its lake pin in the same week-of-aae4-bump
  cadence as the toolchain.
