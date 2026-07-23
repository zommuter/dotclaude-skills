# 2026-07-23 — Orphan existence must never block progress (amends a4e9)

**Started:** 2026-07-23 17:35
**Session:** f44a210d-827d-42ec-8a6a-b8e1bd7ccdad
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (relay orchestration), 🔩 Gil (git merge-integrity)
**Topic:** Should a parked orphan's mere existence ever suppress a repo's classification/dispatch — reopening the 2026-06-16 (id:a4e9) "NO auto-integration" ruling that spawned the repo-scoped suppress at relay-loop.js:1163 (id:1f53).

## Agenda
1. Is there EVER a sound reason for an orphan's mere existence to block progress?
2. (Demoted) Should the loop also auto-integrate the safe orphan subclass?

## Discussion

Opened mis-framed as "should we auto-integrate orphans (reverse a4e9)?" — the owner corrected the framing: auto-integration is a secondary efficiency question; the actual requirement is near-axiomatic — **an orphan's existence must not prevent actual progress** unless there is a genuinely sound reason. The owner named the candidates to test: broken executor, handback loop.

**Reasoning through every case where blocking might be justified:**
- **Disjoint other items** (id:dfb9 open while id:ce50's orphan is parked): no shared state, no possible conflict → blocking is pure loss (the observed ce50/loderite bug).
- **Same item, orphan COMPLETE**: don't re-dispatch — *close* it by integrating the orphan. "Block" is the wrong verb; **reconcile-first** is right.
- **Same item, orphan PARTIAL**: re-dispatch wastes work (two competing orphans) but is not unsafe — worktrees are isolated, integration is serialized, any collision surfaces as a loud 3-way merge conflict (never silent corruption). Response is item-scoped ("handle this item's orphan first"), never repo-scoped.
- **Broken executor** (this run: it-infra died "Prompt is too long"): leaves NO orphan; the signal to suppress is "*this dispatch just failed*", not "an orphan exists". Wrong key.
- **Handback loop**: real thrash — but ALREADY handled by the correct, orphan-independent mechanism: `id:1432` `applyNoWorkSuppression` (re-dispatch suppressed when a unit hands back with `work_sig` **unchanged**) and `id:365b` (`>3×`-this-run circuit breaker, also `work_sig`-keyed).

**Conclusion (all five personas converge):** there is **no sound reason for an orphan's mere existence to block progress**. Every genuine "stop working this" reason is a *failure-repetition* signal, and each already has a correct, orphan-independent guard (id:1432 / id:365b). The orphan-existence block (id:1f53 at relay-loop.js:1163, and its twin CASE-A shard-prompt text) is a fourth mechanism that adds only false suppression — it fires on *success* (a complete orphan) and on *unrelated items*. Riku's premise-check: a4e9 was cautious because June's dominant orphan source was a bug (handback-note commits, id:8b1f, since fixed); today's orphans are genuine completed work stranded at the push step — the evidence base has materially changed, warranting an explicit amendment, not a reinterpretation.

## Decisions

**Decision provenance:** owner ratified via AskUserQuestion → "Ratify: existence never blocks (Recommended)", selecting the rule below verbatim.

- **D1 — Orphan existence NEVER suppresses a repo's classify verdict or dispatch.** A parked orphan is **additive SURFACE only** (loud, every round). The rule:
  - `orphan exists` → surface, **never** block.
  - `same item + parked orphan` → **reconcile-first** (integrate-if-safe / surface), not re-dispatch a duplicate. This is the ONLY item-scoped carve-out, and it is item-scoped, never repo-scoped.
  - `repeated failure, work_sig unchanged` → suppress (id:1432 / id:365b) — **the only real "stop"**.
  - `broken executor / handback loop` → already covered by the failure-keyed guards above (orphan-independent).
  - **Remove** the id:1f53 repo-scoped `surfaced → units:[] + STOP` at relay-loop.js:1163 (and the twin CASE-A shard-prompt routing text). Replace with item-scoped/additive routing per the ratified contract. This is captured by the already-authored RED spec **id:bc49** (`tests/test_orphan_additive_surface_bc49.sh`), promoted `[HARD — pool]`.
  - **Amends id:a4e9** on a changed premise (the id:8b1f orphan-source bug is gone). This is an explicit amendment, not a silent reinterpretation.
  - **Corner-case now RESOLVED** (the handoff had flagged it for REVIEW_ME): when the parked item is the *only* open item, the repo does NOT emit a duplicate execute unit AND does NOT go `units:[]` — it **reconciles that orphan first** (integrate-if-safe, else surface). D1's same-item carve-out answers it.
- **D2 — Auto-integration (id:1048) is DEMOTED to a separate, optional efficiency follow-up**, decoupled from the blocking fix. It is NOT what fixes the complaint (bc49 is). Out of scope for D1: whether/when to auto-close the safe complete-orphan subclass — decide later if orphan pile-up becomes a real cost.
- **Out of scope:** re-deriving the a4e9 orphan-park/reconcile design; the auto-integrate predicate; changing the failure-keyed guards (id:1432/365b stay as-is — they are the correct "stop").

## Action items
- [ ] Implement id:bc49 per D1 — discover-repo.sh + relay-loop.js:1163 twin: orphan-surface additive/item-scoped, never repo-suppress; same-item → reconcile-first. RED spec authored (`tests/test_orphan_additive_surface_bc49.sh`). Contract: a repo with `ambiguous:false` verdict + a parked orphan for a DIFFERENT item still emits its execute unit. <!-- id:bc49 -->
- [ ] Demote id:1048 to optional auto-integrate follow-up (not the blocking fix); record D1 as its resolution of the "does existence block" question. <!-- id:1048 -->
- [ ] Owner-ratify handoff-proposed 24ec decomposition: id:6eb3 (CASE-A content-address mechanization) + id:86a2 (prelude → model:'bash' split). Surfaced, NOT auto-promoted. <!-- id:6eb3 --> <!-- id:86a2 -->

## Amendment session — `--fabled` closing pass (id:7e87)

A Fable-5 adversarial reviewer re-read the code + the a4e9 source against D1/D2 and returned **9 confirmed holes**. The core principle (a *different* item's parked orphan must not block a repo's independent work) SURVIVED; the decision as first ratified was under-specified, one "resolved corner" was a regression, and the provenance was mislabeled. Owner ratified the amendments below (AskUserQuestion, three questions).

- **A1 (supersedes D2) — build a BOUNDED auto-integrate; 1048 is UN-DEMOTED.** Hole 2: "reconcile-first (integrate-if-safe)" is a null op while 1048 is unbuilt (the loop has no integrate primitive; `/relay reconcile` is human-only), so a single-item-only-orphan repo STALLS pending human reconcile — the exact original complaint. Owner chose **build minimal auto-integrate**: the loop auto-completes an orphan that is COMPLETE + clean-3-way-merge + non-diverged + full-suite-green (the interrupted-integration case, e.g. ce50), so a single-item repo never stalls. Everything else (partial/mid-cutoff, conflict, red, diverged) stays human-gated `/relay reconcile`. This IS the bounded amendment to a4e9-D1's "NO auto-integration" — now explicit and owner-ratified.
- **A2 (supersedes D1's provenance) — D1 RESTORES a4e9-D3, it does not blanket-amend a4e9.** Hole 5: a4e9-D3 was explicitly ITEM-scoped; the repo-scoped `surfaced→units:[]` was id:1f53 implementation OVER-REACH, never ratified. So removing it *restores* a4e9-D3 compliance. The genuine a4e9 amendments are exactly two: (A1) the bounded auto-integrate (amends a4e9-D1), and (A3) the ambiguous-binding default (amends a4e9-D3's asymmetry).
- **A3 (amends a4e9-D3) — rule the AMBIGUOUS-binding orphan explicitly.** Hole 4: a4e9-D3's "ambiguous binding → default to suppress" is silently inverted by an item-scoped-only carve-out. EXPLICIT ruling (not reinterpretation): an unbindable orphan (no/mis-ordered `id:` token in its commit) is **additive-surface + auto-integrate-if-safe**; if not auto-integratable it is a human-reconcile item, and the failure-keyed guards (id:1432/id:365b) are the ONLY backstop against duplicate work — NO existence-keyed or repo-scoped suppression is resurrected. Rationale: a complete unbound orphan gets consumed by A1 anyway; blocking the repo for a partial unbound orphan is the exact over-reach being removed.
- **A4 (amends the bc49 contract + RED spec) — surface-class table + executor enforcement + spec coverage.** Holes 1/6/8/9: (i) SAFETY — the removed block fired on ~5 surface classes; only **orphan-suppress is additive**, while **in-flight-elsewhere/claimed (id:ebfb), diverged, e3ad fail-closed-refusal, and discover-error stay SUBSTITUTIVE** (`units:[]`) — else an executor dispatches into a repo held by another live run (the dc5b collision). (ii) ENFORCEMENT — item-scoping must reach the executor: `discover-repo.sh` injects "orphan-parked, reconcile-first, do NOT work id:X" into `unit.reason` (the child prompt already relays it). (iii) SPEC — add cases: (C) in-flight/live-claimed repo → substitutive; (D) same-item-only → auto-integrate-if-safe else surface; (E) ambiguous-binding per A3. (iv) fix the twin prompt surfaces beyond :1163 — the `relay-loop.js:1172` "each repo appears exactly once across units+surfaced" invariant + the schema comment "a surfaced repo is never dispatched" both become false under the additive contract.
- **A5 (notes) — durable-guard honesty + surfacing loudness.** Holes 3/7: id:1432/365b are in-memory WITHIN one pool invocation (the orphan ref was the only durable cross-run suppression) → the same-item carve-out is the acknowledged durable guard, and the unbindable-orphan case (A3) is its gap, capped by the 3× breaker. "additive SURFACE only (loud, every round)" is false — the discover sig-cache surfaces once per invalidation then goes silent on cache-hit rounds → cache the surfaced lines and re-emit on hits (or restate as "once per invalidation + in the run summary").

### Amended action items
- [ ] **id:1048 UN-DEMOTED → build BOUNDED auto-integrate** (`[HARD — pool]`, needs RED spec): loop auto-completes a COMPLETE+clean-merge+non-diverged+suite-green orphan; all else human-gated. Amends a4e9-D1. <!-- id:1048 -->
- [ ] **id:bc49 spec + contract AMENDED per A2/A3/A4**: surface-class table (only orphan-suppress additive); unit.reason item-scoping enforcement; spec cases C/D/E; twin surfaces :1163 + :1172 + schema comment. <!-- id:bc49 -->
- [ ] **id:86a2 PROMOTED** to ROADMAP as a separate item (prelude → model:'bash'). <!-- id:86a2 -->
- [ ] **id:6eb3 UN-GATED** — the launch-wall (id:af30/2ec4) dissolution by a36e is ALREADY empirically confirmed this session (model:bash 12/12 agents 0 errors, memory `relay-model-proxy-probe-gated-substrate`); no spike needed. Spec CASE-A content-address → model:'bash'. <!-- id:6eb3 -->
