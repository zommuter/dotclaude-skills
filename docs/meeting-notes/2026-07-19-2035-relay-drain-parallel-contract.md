# `/relay . --drain [--parallel N]` — buildable contract (id:93fe)

**Started:** 2026-07-19 20:35
**Session:** 2344a12c-7d26-4457-9775-41f0e35debfe
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration), 🔩 Gil (git plumbing), 🛠️ Sven (systemd .timer semantics)
**Topic:** Lock the buildable contract for `id:93fe` — the single-repo drain-loop with optional parallel executors ([HARD — meeting], user 2026-07-19, mtg-1726 D4).

## Context

Base already live: `id:7633` single-repo pool (`/relay .`); `drain.mjs` (id:d58f) shipped as the stopping contract; `id:dc5b` one-unit-per-repo-per-round DECIDED C2. `id:93fe` carries `gated-on:0534` (mechanical-daemon lease hole) — 0534 was hard-executed in the background during this meeting and landed green (`154aa15`).

## Discussion

- **Archie / Orla — flag shape (D1).** `--drain`/`--parallel N` are flags on the *existing* 7633 pool, not a new verb: 7633 already bypasses universe-enumeration + the 40× discover fan-out, so `--drain` = loop `runRound()` on the one repo until the stop predicate; `--parallel N` widens the executor fan within a round. No new engine.
- **Orla — stop predicate (D2).** Reuse `drain.mjs`'s three-way distinction (substantive / confirmation-not-progress / fully-blocked) as "drained or human-blocked"; stop after **K=2 consecutive dry rounds** (no new ticks), mirroring the pool's two-empty-discoveries convergence, with `MAX_ROUNDS` as the hard seatbelt. The failure mode to design against is handoff→execute→review **ping-pong**.
- **Riku — anti-spam brief (D3).** c17c's review-agent brief is a **Phase 1** requirement, not Phase 2: even N=1 drain loops handoff→execute→review, and a review agent that re-litigates ratified design never converges. Bake into the loop's review prompt: verify against the RED spec, do NOT re-question decided design, do NOT open a REVIEW_ME box for anything already in a meeting note.
- **Gil — one-writer-to-main (D5).** `--parallel` safety rests on one-writer-to-main: executors produce **code + reports in their own worktrees only**; the single driver holds the lease, merges each `--no-ff` **serially**, and ticks checkboxes itself. `id:5a39` (meeting-as-relay-producer) is the *same pattern applied to /meeting writes* — a **sibling**, not a prereq; Phase 2 implements the executor one-writer model directly and cross-links 5a39.
- **Orla — disjoint-path greenlight (D4).** Concurrent executors greenlit **mechanically, fail-closed**: only if declared file-sets (RED spec `# roadmap:XXXX`, item Context/file list) are **disjoint AND non-empty**; re-enforce at merge (diff 2nd worktree touched-paths vs 1st merged diff; intersection → handback, never auto-resolve). Undeclarable file-set or unknown overlap → serial.
- **Sven / Petra — sequencing vs 0534 (D6).** A systemd `.timer` firing the mechanical daemon mid-drain dirties the tree the driver merges. Sequential `--drain` (N=1) only *stalls* (drain.mjs parks on dirty main — fails safe), but `--parallel` is a live collision. So phase it: **N=1 ships now (no 0534 dep); `--parallel` gates on 0534** (which landed this session).

## Decisions

- **D1 — flag shape:** `--drain` + `--parallel N` are flags on the `id:7633` single-repo pool, NOT a new subcommand.
- **D2 — stop predicate:** reuse `drain.mjs` (substantive / confirmation-not-progress / fully-blocked) + stop after **K=2** consecutive dry rounds (no new ticks) + `MAX_ROUNDS` seatbelt. No new detector.
- **D3 — anti-spam brief:** Phase-1 hard requirement; fold in `id:c17c` (verify-vs-RED-spec, no re-litigating ratified design, no REVIEW_ME for decided items) into the drain loop's review-agent prompt.
- **D4 — disjoint-path greenlight:** mechanical fail-closed on declared file-sets (disjoint + non-empty), re-enforced at merge; undeclarable/unknown-overlap → serial.
- **D5 — `--parallel` merge model:** Phase 2 implements one-writer-to-main directly (executors→worktrees, single driver merges `--no-ff` serially + ticks); `id:5a39` is a cross-linked sibling, NOT a hard prereq.
- **D6 — sequencing (phased):** **Phase 1 `--drain` (N=1)** ships now on 7633 + drain.mjs + the D3 brief (no 0534 dep). **Phase 2 `--parallel N`** gates on `id:0534` (landed `154aa15` this session) + implements D4 + D5.

Out of scope: implementing either phase now (both need handoff to author the RED spec — `relay-loop.js` is Workflow-sandbox-only, the id:2d20 RED-spec-from-worktree hazard).

## Action items

- [ ] `id:93fe` re-scoped to **Phase 1 — `/relay . --drain` (N=1)**: loop `runRound()` on the id:7633 pool until drain.mjs reports K=2 dry rounds (or MAX_ROUNDS); bake the c17c anti-spam brief into the loop's review-agent prompt. `[HARD — pool]`, DECIDED, ships now (route to handoff to author the RED spec, cf 2d20). <!-- id:93fe -->
- [ ] **Phase 2 — `/relay . --parallel N`**: fan out N executors within a drain round; one-writer-to-main (executors→worktrees, single driver merges `--no-ff` serially + ticks); mechanical fail-closed disjoint-path greenlight (D4). `[HARD — pool]`, gated-on `id:0534` (landed this session) + relates `id:5a39`, `id:93fe`, `id:dc5b`. Route to handoff to spec. <!-- id:ebbe -->
