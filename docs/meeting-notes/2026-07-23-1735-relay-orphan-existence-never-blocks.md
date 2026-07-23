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
- [ ] Owner-ratify handoff-proposed 24ec decomposition: id:6eb3 (CASE-A content-address mechanization, gated on confirming the id:af30/2ec4 launch-wall is dissolved by a36e — a verification question) + id:86a2 (prelude → model:'bash' split). Surfaced, NOT auto-promoted. <!-- id:6eb3 --> <!-- id:86a2 -->
