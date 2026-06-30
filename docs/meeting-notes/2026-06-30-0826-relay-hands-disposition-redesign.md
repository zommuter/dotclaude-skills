# 2026-06-30 — Relay human-mode disposition redesign

**Started:** 2026-06-30 08:26
**Session:** 4795f91a-97bc-45ef-8371-f67ad230373e
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration)
**Topic:** Shrink the `[HARD — hands]` queue to the irreducible — re-lane policy for INTENSIVE, an author-then-run split disposition, verbose human output, and auto-filing inbox dead-letters on every `--all` run.

## Surfaced discoveries
EMBED unset — no semantic retrieval. Priors: id:678e (inbox slice-2 `--apply`, shipped + used this session), id:78ff (explicit lane vocabulary / orthogonal `[INTENSIVE]` axis), id:da26 (pool `hard` verdict), id:8d52/052c (`--intensive` run-serially-alone, implies `--afk`), conformance-sweep-pilot (tooling=detector, conversion=judgment), id:415b (arguable-judgment → Guard not replace).

## Agenda
1. Re-lane POLICY: which `[HARD — hands][INTENSIVE]` items become `[HARD — pool][INTENSIVE]` vs stay hands.
2. Auto-build-script disposition: model "split a scriptable hands item into pool-author + hands-run, surface the run command."
3. `/relay human` verbosity for genuinely-human-only quick tasks.
4. Wire `scan-routed.sh --apply` into every `--all` flow.

## Discussion

### Item 1 — re-lane policy (INTENSIVE axis reused, no new lane)
🏗️ Archie: "Pool-safe" is a property of the done-check + side-effects, not compute weight. Five necessary conditions to lane an INTENSIVE item `pool` not `hands`: (a) automatable done-check (no human observation); (b) no irreversible destructive op without confirm; (c) no live secret/sudo/device/credential a worktree child can't reach; (d) `host-gate.sh` satisfiable; (e) no open judgment sub-step.
😈 Riku: Verdicts — 244b (drain script, idempotent `--resume`, dashboard done-check) passes → pool; c5e9 (`rm` GGUFs) fails (b) → hands; fd30 ("post-gate decisions") fails (e) → hands; 9321 (live GPU+sudo) fails (c) → hands. One re-lane today.
✂️ Petra: N=1 action, but the policy is the documented criterion the lane contract needs for future items.
🎛️ Orla: 244b is efc2-blocked for the residual, but re-laning is still correct — it buckets hard_pool and runs under `--intensive` (OOM handled by the opt-in + `resource:` claim).

### Item 2 — auto-build-script disposition
🏗️ Archie: (A) new `[HARD — author+hands]` lane + pool "emit child" machinery vs (B) split into two existing-lane items at handoff/human time — `[HARD — pool]` author + `[HARD — hands]` run `(DEP: author-id)`.
🎛️ Orla: (B) is far cheaper, inherits verify-before-merge. "Automatically build" is satisfied once the pool author-item exists. The only new question is who splits — authoring judgment, not a transform.
😈 Riku: Two guards — (1) "perform from /relay human" = PRINT the command; relay never auto-executes a device/sudo command (that's the gate). (2) Per id:415b + conformance-pilot, the split is arguable judgment → detector may FLAG, must not auto-split.
✂️ Petra: N=2 holds (36b7 units, 935e/6e27 gamemode, 560c caddy). zomAI f18f is a bad example (author-step is outside-repo/orchestrator-only) — wholly hands. Adopt as a documented practice; defer any detector (observe-first).

### Item 3 — `/relay human` verbosity
🏗️ Archie: Steps/commands already live in the item body; expand the "you run these" checklist. 😈 Riku: pull commands VERBATIM, never fabricate a sudo procedure; terse-fallback + `file:line` when none recorded. ✂️ Petra: verbose for the run-these list ONLY; ~5–8 line cap; `file:line` editor-jump ref when long.

### Item 4 — auto-file inbox dead-letters on every `--all`
🏗️ Archie: `--apply` belongs in the cross-repo front door, run once, before triage. 😈 Riku: safe — idempotent, class-A only, class-B prose still surfaced (id:678e gate); pass run's `--exclude` + always `truncocraft`; respect `paused`; include the bare autonomous pool. ✂️ Petra: one shared sub-step in SKILL.md invariant 1, not duplicated per reference doc.

## Decisions
1. **Re-lane policy (INTENSIVE axis reused — NO new lane).** 5-condition criterion (a–e) in `relay/references/hard-lanes.md`; re-lane `ai-codebench` id:244b → `[HARD — pool] [INTENSIVE — local-llm] [host:zomni]`; keep c5e9 (fails b) / fd30 (fails e) / 9321 (fails c) hands with the failing criterion annotated. *Out of scope:* a new lane; INTENSIVE scheduling; auto-confirming destructive ops.
2. **Auto-build-script = (B) split into two existing-lane items.** `[HARD — pool]` author + `[HARD — hands]` run, DEP-linked; pool auto-builds; human.md prints the run command (relay NEVER auto-executes). Split = authoring judgment (documented practice), not a transform; detector deferred. *Out of scope:* new lane; relay auto-executing device commands; auto-splitting.
3. **`/relay human` verbosity — "you run these" only, verbatim, clickable refs.** Expand `hard_hands` + `manual` verbatim; `<file>:<line>` editor-jump ref when long; ~5–8 line cap; meeting/pool tiers stay terse; no fabricated steps. *Out of scope:* verbose meeting/pool tiers.
4. **Auto-file inbox dead-letters on every `--all` — one front-door sub-step.** SKILL.md invariant 1 runs `scan-routed.sh --apply` with run's `--exclude` + always `truncocraft`, before triage; class-A only; class-B prose stays surfaced. *Out of scope:* per-repo runs; class-B auto-conversion; changing scan-routed's gates.

## Action items
- [x] AI1 — 5-criterion INTENSIVE re-lane policy in `relay/references/hard-lanes.md` (implemented this session; `make test` green, marker set unchanged). <!-- id:db39 -->
- [x] AI1b — re-lane `ai-codebench` ROADMAP id:244b hands→pool[INTENSIVE][host:zomni] (committed `678c752`). it-infra c5e9/fd30/9321 annotations DEFERRED — it-infra live-claimed by a parallel `/meeting` (routed to inbox). <!-- id:db39 -->
- [x] AI2 — author-then-run split practice documented in `relay/references/handoff.md` (C2) + `references/human.md` (§3). <!-- id:e175 -->
- [x] AI3 — verbose "you run these" with `<file>:<line>` editor-jump refs in `references/human.md` (§4 + return summary). <!-- id:45c6 -->
- [x] AI4 — `scan-routed.sh --apply` reconcile sub-step in `SKILL.md` invariant 1 for all `--all` flows. <!-- id:1d3f -->
- → routed to it-infra inbox: annotate ROADMAP c5e9/fd30/9321 with the failing re-lane criterion (deferred — repo live-claimed). <!-- routed:7ede -->
