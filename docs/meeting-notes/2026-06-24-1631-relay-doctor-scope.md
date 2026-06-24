# 2026-06-24 — id:0907 relay-health aggregator: scope decisions

**Started:** 2026-06-24 16:31
**Session:** cdf958f5-60a3-476d-9f5f-997426fb39e6
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime), 🎛️ Orla (orchestration)
**Topic:** Resolve id:0907's `[HARD — meeting]` scope — home / cadence / fail-loud-vs-report / which-checks — with the cheap-first-slice (`relay-doctor.sh`, id:9bec) being built in parallel.

## Grounding
- id:9bec (built in parallel this turn) = `relay/scripts/relay-doctor.sh`, a REPORT-ONLY aggregator that CALLS the already-built checks (orphan-scan --cross-ledger, roadmap-lint, refs-install id:69ef, relay-reconcile --all), scope cwd/`<dir>`/`--all`. Gate (id:09a3/69ef/000d) met.
- Entry points to mirror: `/relay review` (already per-repo, re-derives roadmap), `/relay health` (new), quota-sample.timer (systemd --user precedent).

## Discussion
### (a) Home
⚙️ Sage: the script is the ENGINE; entry points layer over it — standalone + a thin `/relay health` alias + a `/relay review` sub-step. No logic duplication.
🏗️ Archie: review is where it pays off (per-repo, drift-prone); `/relay health` is the on-demand door. Both wrap the one script.
### (b) Cadence
✂️ Petra: no systemd timer (observe-first; checks are cheap). On-demand + at-review covers it; add a timer later only if review-time proves too sparse.
😈 Riku: a timer is unattended machinery with its own failure modes (cf. the watchdog saga). Per-review + on-demand is the minimal honest cadence.
### (c) Strictness
😈 Riku: fail-loud-by-default would let cosmetic drift BLOCK the pool/review — bad. Must SURFACE (RELAY_STATUS/REVIEW_ME), not hard-fail.
🏗️ Archie: report-only default (matches 9bec) + opt-in `--strict` nonzero for a deliberate gate; review findings → REVIEW_ME boxes, never a block.
✂️ Petra: roadmap-lint's existing LOUD untagged-lane reject (id:09a3) is collated, not softened.
### (d) Which checks
🎛️ Orla: cheap-now = 9bec's set; gated = claim/lease staleness (id:e149 heartbeat), discover-sig health (id:c3a6); quota-config sanity is cheap-ish, fold soon.
😈 Riku: the report must LIST not-yet-wired checks so coverage is honest, not falsely-green.

## Decisions
- **D1 — Home: three layers over one script.** relay-doctor.sh (engine, id:9bec) + `/relay health` alias + `/relay review` sub-step (findings → REVIEW_ME). Out of scope: GUI/dashboard.
- **D2 — Cadence: on-demand + at-review, NO timer** (observe-first; revisit only if review-time too sparse).
- **D3 — Report-only default + `--strict` opt-in** (surface, never hard-block; roadmap-lint LOUD reject preserved). Out of scope: fail-loud-by-default.
- **D4 — Ship cheap-now set + LIST gated checks** (claim-staleness id:e149, discover-sig id:c3a6) for honest coverage; fold quota-config sanity soon. Out of scope: blocking the cheap slice on gated checks.

## Action items
- [x] relay-doctor.sh report-only engine + D4 gated-checks honesty list — DONE this turn (started by the id:9bec background executor, finished + tested + landed by the strong turn after the executor paused for go-ahead). <!-- id:9bec -->
- [ ] relay-doctor front-door wiring: `/relay health` mode + `/relay review` sub-step (findings → REVIEW_ME, never a hard block) [ROUTINE] (DEP id:9bec). (this note) <!-- id:3eb5 -->
- [ ] relay-doctor `--strict` opt-in (nonzero gate) + quota-config sanity check [ROUTINE] (DEP id:9bec). (this note) <!-- id:a883 -->
