# 2026-06-23 — Ledger drift: dissolve the duplicated checkbox via a derived index

**Started:** 2026-06-23 08:03
**Session:** 4f4a57bf-029e-4d1e-90c7-7828adc3a3bd
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity)
**Topic:** Root-cause fix for the TODO↔ROADMAP checkbox drift (truncocraft 2026-06-23) — direction across A/B/C/D and whether id:2840's deferral gate opens.

## Context

`/relay --afk` audit surfaced a TODO↔ROADMAP drift in truncocraft: id:6b94/8f21/3d56 were closed `[x]` in ROADMAP by an executor at the 07:19 merge but left `[ ]` in TODO. **Forensics:** the 07:11 review had them consistent; the 07:19 executor closed them in ROADMAP only (executor contract = ROADMAP/RELAY_LOG writes, never TODO); the compensating TODO-twin close lives in the *trailing* review's step-5 — which is LLM-judgment and **quota-gated**, and that review never ran (the pool quota-stopped after 07:33). **Root cause = a duplicated MUTABLE checkbox + an async, skippable, un-mechanized reconciler.**

## Surfaced discoveries
- [2026-05-21 dotclaude-skills] A note↔tracker correlation key must be a STORED OPAQUE TOKEN, not a re-derived hash → any derived view keeps `id:` stored; only the checkbox STATE is a derive candidate.
- [2026-05-21 zkm] A skipped bookkeeping item is a LEDGER miss, not an impl miss — the exact truncocraft shape.
- [2026-06-01 dotclaude-skills] meeting/relay tooling must stay publishable (stdlib-only) — a derived index can't couple dotclaude-skills to project_manager's `scan.py` via `import`.

## Discussion

🏗️ **Archie:** Root cause is duplicated mutable state. The serialized integrator is the one place that runs on every executor merge under the per-repo flock — so **D** (integrator diffs ROADMAP for `[ ]→[x]` ids and mirrors them into TODO via flock'd `md-merge.py`) is the natural deterministic, non-quota/LLM-gated fix for the dominant path.

😈 **Riku:** D adds the integrator as a NEW writer of TODO.md (the id:ca87 non-unionable-checkbox contention, relocated) and only covers the integrator path — `/meeting`/human direct ticks bypass it, so `orphan-scan --cross-ledger` stays as backstop. D fixes ~90%, not 100%.

🏗️ **Archie:** **C-lite** removes the duplication instead of syncing it: TODO twin drops its checkbox, ROADMAP becomes sole status authority, TODO shows a derived badge — nothing to drift.

✂️ **Petra:** C-lite splits the grammar — twin lines lose the checkbox, TODO-only lines (the majority) keep it; a stateful per-line distinction every parser tracks. Worse than D's uniform grammar. And id:2840 (full index) is n=1 evidence — pilot-sample-size + lever-first say extend the integrator, log evidence-point-1, open id:2840 only if drift persists after D.

😈 **Riku:** Confirmed D covers this incident (truncocraft ran under the serialized integrator). id:1de1 count line folds in — cheapest is **drop** it, point at `proj relay`.

**Personas converged on D + backstop + drop-count + keep-2840-deferred.**

## User override (decision point)

The user **overrode the persona consensus** (the documented lever-first / challenge-the-deferral-gate pattern): judged the seam-pain sufficiently measured and chose the structural lever over the integrator patch. Ratified: **build id:2840 now**, **substrate in project_manager**, **full index up front**, **drop the count line**.

## Decisions
- **Reject A (status-quo) and B (single ledger).** B re-creates executor-prompt bloat (id:93cc) + non-unionable-checkbox contention (id:ca87) — trades silent drift for loud conflicts + bloat. Out of scope: merging the files.
- **Reject D (integrator mirror) and C-lite as the end-state.** D is a sync-patch on a duplication the index dissolves; C-lite splits the grammar. Not built.
- **Build id:2840 (unified derived index) NOW — gate opened.** This incident is the measured seam-pain. **Markdown stays SSOT; the index is a CACHE** (md wins, rebuild from md, writes only ever touch md). **ROADMAP is the execution-status authority**; the TODO-twin checkbox state becomes a DERIVED query. The opaque `id:` stays STORED in both ledgers (2026-05-21) — only the STATE is derived.
- **Substrate: the index lives in project_manager** (extend `scan.py`, already a md→ScanResult cache). dotclaude-skills relay/meeting read a GENERATED ARTIFACT (file or `proj` CLI) via a stable contract — never `import project_manager` (2026-06-01 publishability). Out of scope: a second md-parser in dotclaude-skills.
- **Scope: full index up front** — cross-ledger consistency + count line + promotion-tracking (id:d9b0) + cross-project (id:69f4) as one substrate, before retiring the point-solutions.
- **Drop the hand-maintained count line (id:1de1)** — point at `proj relay`/the index. Ungated.
- **Interim backstop:** `orphan-scan --cross-ledger` stays the drift catch until the index ships; the truncocraft drift (6b94/8f21/3d56) stays as live evidence until closed by the first index reconcile.
- Rebuild trigger / sqlite-vs-JSON deferred to the project_manager build's plan (reversible; personas steer: reuse `discover-sig` content-hash id:c3a6 for on-read staleness).

## Action items
- [ ] id:2840 — mark DECIDED 2026-06-23 (un-defer): substrate=project_manager, md-SSOT/index-as-cache, ROADMAP=status authority, full-index scope, artifact-contract for dotclaude-skills consumers. (this note) <!-- id:2840 -->
- [ ] Build the unified derived index in project_manager `scan.py` (md→cache) + a stable artifact/CLI the relay reads; answer cross-ledger / count / promotion (id:d9b0) / cross-project (id:69f4). → routed to project_manager inbox
- [ ] Consumer side (dotclaude-skills): relay `review`/`human` + count read the id:2840 artifact instead of hand-grepping; retire the per-review twin-close + `orphan-scan --cross-ledger` hand-check once the index ships. Gated on the project_manager index landing. (this note)
- [ ] id:1de1 — mark DECIDED: drop the prose count line, point at `proj relay`/the index. (this note) <!-- id:1de1 -->
