# 2026-07-31 — execute→review cadence: total review starvation in the relay pool

**Started:** 2026-07-31 12:31
**Session:** cc940f4c-a8b0-4750-a4a4-37c3dd66d756
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🧭 Wren (new — scheduler/queueing lens: starvation, aging, priority inversion, fairness-vs-throughput)
**Topic:** Settle `id:d147` (both halves) jointly with `id:cc90`, since all three govern the same execute→review cadence knob.

> **Persona correction (in-session):** this meeting first introduced the scheduler lens as "Quinn (new)". **Quinn already exists** in `personas.md` — 🔧 Quinn, *inference-server internals; llama.cpp/llama-server, KV-cache, slot/sequence/batch management* (introduced 2026-05-21, zkm/embed-rebuild-500). The facilitator had read only `head -30` of the registry. The ad-hoc persona was renamed 🧭 **Wren** for the remainder. Incidental: **Quinn is registered twice** (personas.md lines 32 and 74, near-identical lens) — registry hygiene, filed nowhere yet.

## Surfaced discoveries

- `[2026-07-23 dotclaude-skills]` A procedure that lives only inside ONE caller's LLM prompt string is invisible to sibling execution paths — enumerate sibling paths before calling a step landed. *(Load-bearing: drove agenda item 4.)*
- `[2026-07-02 dotclaude-skills]` The a0b6 classifier flip's own quality gate was RED>0 in 3 of 7 post-flip snapshots, filed nowhere — an irreversible flip relaxed at n≈1 shipped with its gate already violated.
- `[2026-07-30 it-infra]` A measurement coupled to its own trigger cadence manufactures the symptom it exists to explain. *(Exactly the `id:d147` half-B shape.)*

## Agenda

1. Where does the (A) starvation fix live — classifier verdict, scheduler, or subsumed by cc90?
2. One cadence mechanism or two? (coherence with cc90's ratified K≤3 rechain)
3. (B) drain dry-round accounting — same change or separate?
4. Sibling-path enumeration: which dispatch paths must the fix reach?

## Discussion

### Item 1 — the starvation is structural, not contention

🏗️ **Archie** put the code first: `relay/scripts/classify-verdict.sh:137-147` is a strict `elif` chain — `actionable_routine > 0` → `execute` (rank 1); only `elif substantive_unaudited` → `review` (rank 2). One verdict per repo per round. So `review` is **unreachable** while a single actionable `[ROUTINE]` item exists. This repo has 18. He corrected the framing inherited from the `routed:9107` inbox item, which said review "never won a slot" — that implies contention, and there is none. No aging term, no unaudited-depth term, no forced-review path in `relay-loop.js`. The starvation is total.

🧭 **Wren**: textbook priority-inversion-by-omission. A strict priority scheduler without aging starves the lower band by construction. Classical fixes are aging, reservation, or a bounded quantum — and the third is literally what cc90 describes.

😈 **Riku** named both failure directions: flip the order and every execute produces unaudited commits, so review fires 1:1 against Sonnet executes — one apex review per cheap execute, the exact cost cc90 exists to avoid. Leave it and unaudited work accumulates unboundedly. His checklist question — *what is the minimum evidence that would change this?* — established that n=2 traces prove the starvation (it is arithmetic from the `elif`, not sampling) but say nothing about where a threshold goes.

✂️ **Petra** applied N=2 to any new "cadence policy" layer: two real consumers exist (`relay-loop.js`, `drain-driver.mjs`), so it clears the bar — but only if genuinely shared, else it repeats the 2026-07-23 discovery.

⚙️ **Sage** supplied the constraint that shaped everything after: `classify-verdict.sh` is a **pure** classifier — one state JSON in, one verdict out, no cross-round memory. Aging is implementable there (unaudited depth and watermark age are derivable per-round from git). A *quantum* is not — "K executes since last review" is scheduler state.

🧭 **Wren** drew the distinction that survived to the end: cc90's K counts **dispatches**; aging counts **unaudited work**. Three no-op executes don't need an audit; one execute that mangled a test suite does. Dispatch-counting is the cheap proxy, wrong exactly at the edges.

### Item 2 — cc90's ratified premise is false

🏗️ **Archie** checked cc90's spec and found its semantic (a), verbatim: *"A chained execute is NOT reviewed mid-chain; the whole chain's commits are reviewed by the next round's `review` verdict, **exactly as a single execute's are today**."* The final clause is false — a single execute's commits are never reviewed today; that is the starvation. cc90 bounds the chain at K and hands back to the same cascade, which says `execute` again.

🧭 **Wren** identified the pattern: a decision restated in a derived doc where the restatement embeds a false premise about current behaviour. Nobody checked the `elif`.

⚙️ **Sage** noted `chainDepth` is already the counter a forced review needs; ✂️ **Petra** insisted the scope change to a just-ratified item with an authored RED spec be said out loud rather than slid in.

### Items 3 & 4 — the (B) half is a deliberate decision, not a bug

🏗️ **Archie**: `relay-loop.js:2255-2266` (`id:c919`) *deliberately* excluded gate-writing handbacks — *"route decision-gate/human do NOT — they re-tag the parent into a classifier-EXCLUDED lane, which REMOVES work rather than adding it… (This narrows routed:b945's proposed `{hard-split, decision-gate}`)"*. So `workCreated = report.route === 'hard-split' && hbSplit > 0`.

🧭 **Wren** located the hole precisely: c919 reasons about *dispatchable `[ROUTINE]` work*, but termination should key on *"did this round change the classifier's answer?"*. Dropping `actionable_routine_open` to 0 flips `execute → review` — the round created a **review** unit, which c919 counted as nothing.

😈 **Riku** conceded c919's asymmetry ("under-draining merely runs an extra round; over-draining could strand work") is correct — and that it argues *for* counting the gate-write. c919 got its own asymmetry backwards for this case.

⚙️ **Sage** found two sibling-path defects: `isDryRound` duplicated byte-identically (`drain.mjs:103`, `relay-loop.js:1072`, with a "keep in sync" comment admitting it), while the **producer** exists only at `relay-loop.js:2266` — `drain-driver.mjs` has zero references, so on that path `workCreated` is permanently `undefined → 0`.

🏗️ **Archie** flagged the blocker: the producer fix site is inside `relay-loop.js`, under the owner's 2026-07-30 do-not-modify directive (`id:4313`).

## Amendment session — 🜛 Fable closing pass (`--fabled`, requested at the closure gate)

`fable-config.sh check` → `available`. One Fable-5 subagent, design-critique framing, fed a closing-time digest with the ratified decisions verbatim. Six findings; **four forced amendments** — the pre-registered escalation trigger (≥2) **FIRES**, having previously fired at count 4.

Two findings were independently verified by the facilitator before being acted on:

- **F1 (confirmed)** — `relay-loop.js:2437-2445`: *"Only reviews chain — an execute never re-enqueues… the execute's own commits are reviewed next pool."* So today `chainDepth ≡ 1` always; the 16 unaudited checkpoints accumulated at depth 1, and **a `chainDepth === K` trigger would not have fired for the incident it was designed to fix.** Every chain ending *below* K — handback mid-chain (Trace B exactly), one-unit-per-repo-per-round topology, `contract_met:false`, quota-stop, agent error — leaves commits unaudited. That made D1's "subordinate safety net" framing false: the unbuilt, unspecified aging term was load-bearing. Note the code comment carries the **same** false "reviewed next pool" premise as cc90's (a) — two places assert it, neither true.
- **F5 (confirmed)** — `ROADMAP.md:32`: *"the OFF-Workflow `drain-driver.mjs` deliverable is **FROZEN** as a headless fallback, go-forward = re-wire onto the Workflow substrate id:7488."* D4 would have spent the `id:4313` directive-lift partly to wire a retired driver. Fable added that import ≠ wired: drain-driver has no handback-report plumbing to call a producer from (banked `id:5367`/`2062` class).

Remaining findings: **F2** — `chainDepth === K` *is* the dispatch counter D1 rejected on record, so D2 rebuilt the rejected alternative complete with the flaw D1 named. **F3** — cc90's reset condition unspecified, and each choice fails differently (dispatch-reset degrades the guard to nothing under apex outage; watermark-reset halts execution at K under outage and is wedged by the banked `id:1a34` stale-watermark bug even after a *successful* review). **F4** — D3's predicate silently no-ops if re-classification hits the `id:c3a6` signature cache; also D3 is the only decision that would have prevented Trace B. **F6** — K=3 against 18 items implies a fixed ~25% apex duty cycle from a hardcoded K, and D3's keep-alive can livelock on verdict-class oscillation.

## Decisions

Superseded entries are retained in order; each amendment cites what it supersedes.

- **D1 (superseded by A1)** — cc90's bounded K≤3 chain is the everyday cadence mechanism; a classifier aging term is a subordinate safety net, not a peer.
- **D2 (superseded by A1)** — amend cc90 to force a `review` unit at `chainDepth === K`, emitted by the loop directly, bypassing the classifier.
- **A1 (supersedes D1 and D2)** — **the cadence mechanism is a classifier RE-ASK at chain end, not a dispatch quantum.** At chain end the loop re-invokes `classify-verdict.sh`, and the cascade is amended so `review` is reachable while `[ROUTINE]` work is open. The classifier remains the sole verdict authority — the loop supplies the *fact* that a chain ended; the classifier decides. cc90's K≤3 still bounds chain length but is **no longer the audit trigger**. No separate aging term is built. Both false-premise sites are corrected in the same change: cc90's semantic (a) and the `relay-loop.js:2441` comment.
  - *Recorded ambiguity, deliberately left to the RED spec:* making `review` **unconditionally** reachable would restore the 1:1 apex-per-execute cost D1 rejected. The intended shape is that the loop passes a "chain ended" fact into the state JSON and `review` outranks `execute` only under it. The exact predicate is the spec's to pin.
  - *Out of scope:* rewriting the D3 verdict cascade wholesale; any multi-knob review budget.
- **D2b (A2)** — `chainDepth` resets on **strong-audit watermark advance**, not on review dispatch, plus a named escape so an apex outage degrades to surfaced-and-skipped rather than a silent halt at K per repo. **Depends on `id:1a34`** (stale `last_strong_ckpt`) being fixed, or the watermark validated as resolvable before it is trusted. *Out of scope:* changing what advances the watermark.
- **D3 (A4) — the PRIMARY fix; implement first.** Amend `id:c919` (closed, `ROADMAP.md:1753`) so `workCreated` counts a handback that **changes the repo's verdict class**, not only one adding dispatchable `[ROUTINE]`. Mandatory clauses in the decision text: (i) **direct `classify-verdict.sh` invocation, cache-bypassed** — without this the `id:c3a6` signature cache makes the predicate answer "unchanged" and the amendment ships as a silent no-op, the banned detector-without-resolution anti-pattern; (ii) predicate scoped **repo-wide** ("this round changed the repo's verdict class"), not per-handback causality, since in-repo parallelism (`id:1f4f`) lets another unit flip the class within a round; (iii) an **oscillation guard** — verdict-class flapping within a window counts as dry, or at minimum the seatbelt exit reason distinguishes this case so it fails loudly. Re-ranked primary because it is the only decision that addresses the observed Trace B. *Out of scope:* changing the K=2 dry threshold itself.
- **D4 (amended by A3)** — scope-lift `id:4313` for this work and extract `isDryRound`/`workCreated` into one shared module, **within `relay-loop.js` only**. The drain-path `undefined → 0` gap is recorded **MOOT-BY-RETIREMENT** citing `ROADMAP.md:32` / `id:7488`. The shared module is still extracted so the coming Workflow re-wire (`id:7488`) adopts one implementation rather than inheriting the duplication. *Out of scope:* un-freezing `drain-driver.mjs` (that would be a separate owner call this meeting did not make).
- **Accepted cost (F6)** — K=3 against 18 open items implies a fixed **~25% apex duty cycle** on chained work, imposed by a hardcoded K rather than a tunable threshold. Recorded as knowingly accepted; it is the opposite trade from the one D1's rejection text worried about, so it is stated here rather than discovered later in a burn report.

## Action items

- [ ] Amend `id:cc90` in place: chain-end classifier re-ask replaces the `chainDepth === K` forced-review trigger (A1); pin watermark-advance reset + outage escape (D2b); correct semantic (a)'s false *"exactly as a single execute's are today"* clause and the matching `relay-loop.js:2441` comment. Contract: a test proves a chain ending **below** K (handback, `contract_met:false`, quota-stop) still yields a review, and that `review` does **not** become unconditionally reachable. <!-- id:8123 -->
- [ ] Amend `id:c919`'s `workCreated` predicate to verdict-class change, with the cache-bypass, repo-scoping and oscillation-guard clauses from D3. Contract: a fixture where a gate-writing handback drops `actionable_routine_open` to 0 must NOT count as a dry round, and the predicate must be shown to bypass the `id:c3a6` signature cache. <!-- id:907e -->
- [ ] Extract `isDryRound`/`workCreated` into one shared module inside `relay-loop.js` under the scoped `id:4313` lift; record the drain-path gap moot-by-retirement. Contract: exactly one definition of each remains, and `drain.mjs`'s "keep the two in sync" comment is deleted rather than left lying. <!-- id:6217 -->

### Filed elsewhere / not action items here

- `id:da87`'s premise needs **correcting, not ticking** — the collector never under-reported; the facilitator's own `| head -80` truncated 9 of 89 rows (`review_me` is emitted last). Handled outside this meeting.
- `personas.md` has a **duplicate Quinn** entry (lines 32 and 74). Not filed.
