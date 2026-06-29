# 2026-06-29 — Dead-but-LIVE relay claim: gate the worktree anchor on the heartbeat

**Started:** 2026-06-29 17:50
**Session:** 1ba6c9c0-93b8-4020-bf54-87b35f6285b9
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🔩 Gil (git plumbing / process-liveness), 🎛️ Orla (relay orchestration / claim lifecycle)
**Topic:** A relay child can die while its `claim.sh` claim still reads LIVE — the id:7570 worktree-commit clause keeps a stale-mtime claim alive forever after the owning run dies, so a parallel `/meeting` or pool sees a held claim for abandoned work. Decide where liveness truth lives and how a dead-but-committed holder is detected + invalidated. (The unsolved remainder of id:9000, after id:672b shipped.)

## Surfaced discoveries
- [2026-05-08 zkm] `os.kill(pid, 0)` is a portable PID-liveness check (raises if dead); `claim.sh` already uses `kill -0` for the id:1b11 `--pid` anchor.

## Agenda
1. Root cause + where liveness truth lives (the fix direction).
2. Edges: no-heartbeat fallback, decoupling liveness from work-preservation, scope, deliverable shape.

## Grounding (read live, not from memory)
- `relay/scripts/claim.sh:124` `is_live` = mtime fresh **OR** (id:7570) `worktree_working` **OR** (id:1b11) `pid_alive`.
- `worktree_working():89` — true if the claim's `--worktree` exists and HEAD has commits beyond main. Extends a >TTL long child's lease **without a heartbeat** — but it never detects death: a worktree's commits persist after the owning process is gone.
- `pid_alive():116` (id:1b11) — `kill -0 live_pid`; self-expires the instant the process dies (correct), but only set for standalone `--pid` jobs.
- `heartbeat.sh` (id:e149) header LITERALLY documents this bug: claim.sh liveness "deliberately KEEPS a stale-mtime claim alive when its worktree still has commits beyond main (id:7570)… That is exactly WRONG for detecting a dead LOOP… which would read 'live' forever and mask the death. The run heartbeat is therefore PURE ts+TTL staleness." The authoritative run-liveness oracle already exists — `is_live` just doesn't consult it.

## Discussion

🏗️ **Archie:** `is_live`'s `worktree_working` clause never detects death — committed objects persist after the process dies, so a run that commits then dies before integration holds its claim forever (the truncocraft second-instance class). Fix: gate that clause on the run heartbeat (`heartbeat.sh status <runId>`); dead/stale run → worktree clause no longer keeps the claim alive → reclaimable. Reuses the existing lever; no new machinery.

🔩 **Gil:** Note the asymmetry with the id:1b11 `pid_alive` clause — `kill -0` self-expires on death; the id:7570 worktree clause has no death-detector. The worktree clause is being used as a *liveness* signal when it's really a *"has unmerged work"* signal. Different questions.

🎛️ **Orla:** The answer is already built. `heartbeat.sh` (id:e149) exists *specifically because* the worktree clause masks death — pure ts+TTL staleness, "regardless of any worktree it left behind." We just call it from `is_live`.

😈 **Riku:** Buy it, but: (1) heartbeat TTL must exceed the beat interval or a slow-but-live run is wrongly reclaimed — reuse `heartbeat.sh`'s own TTL, no second knob. (2) The real fork: what if a worktree-anchored claim's `runId` has **no** heartbeat marker? Absent→reclaim steals a live non-beating child; absent→live rebuilds the immortal claim. Pick a direction.

🔩 **Gil / 🎛️ Orla:** Fall back to **mtime-TTL**: the worktree anchor only *extends* liveness past TTL when a fresh heartbeat backs it; no heartbeat → the claim expires on the ordinary 30-min mtime-TTL (the safe pre-id:7570 behaviour). The pool already beats (id:98f0/e149 foundation); any directed path that doesn't is no worse than pre-id:7570, and that gap is a small follow-up, not a correctness hole.

✂️ **Petra:** And reclaiming a claim is **not** destroying the work — `is_live`/`reap` free only the *reservation*; the orphan worktree with its commits is left for the existing reconcile (id:a4e9 park-not-integrate / id:7809). Two concerns, two owners; fully reversible. Scope guard: NOT the bilateral coordination channel (rest of id:9000), NOT auto-integrating orphans, NOT pid-reuse hardening for id:1b11.

⚙️ **Sage:** Clean `[ROUTINE]` — a focused `is_live` edit + a hermetic test that stubs the heartbeat ts (else we manufacture the very id:16e9 flake we're fixing). Which means it must land *after* the id:16e9 de-flake so the new test extends a deterministic harness.

## Decisions
- **D1:** Gate the id:7570 `worktree_working` liveness clause on the run heartbeat (id:e149) — a worktree-anchored claim is live only if `heartbeat.sh` reports its run alive. Rejected: PID-probe (no stable pid for a Workflow/pool; pid-reuse), new TTL-extend-on-commit lease (bespoke; duplicates heartbeat). **Out of scope:** anything beyond this clause-gate + consult.
- **D2:** No-heartbeat fallback = mtime-TTL. The worktree anchor only extends liveness past TTL when a fresh heartbeat backs it; absent heartbeat → ordinary mtime-TTL expiry. Reuse `heartbeat.sh`'s TTL constant — no second knob. **Out of scope:** a new staleness knob.
- **D3:** Decouple liveness from work-preservation — reclaiming a dead-run claim never deletes the worktree; the orphan is disposed by the existing reconcile (id:a4e9/7809). Reversible. **Out of scope:** auto-integration of orphans.
- **D4 (scope):** Explicitly OUT — the bilateral coordination/notify channel (rest of id:9000), auto-integrating orphans, pid-reuse hardening for id:1b11, any new TTL knob.
- **D5 (sequencing):** Build gated on **id:16e9** (de-flake of `test_relay_claim_liveness.sh`) landing first, so the new heartbeat-gate test extends a deterministic harness. Deliverable = handoff → background execute → review, after the in-flight workflow integrates.

## Action items
- [ ] **AI1 — gate `claim.sh` `is_live` worktree clause on the heartbeat (id:e149); absent-heartbeat → mtime-TTL fallback (D2); reaper drops the dead-run claim, worktree untouched (D3).** File: `relay/scripts/claim.sh`. Test: extend/replace `tests/test_relay_claim_liveness.sh` with deterministic (stubbed-ts) cases — fresh-hb+worktree→live; stale-hb+worktree→reclaimable; absent-hb+worktree→mtime-TTL expiry; mtime-fresh→live regardless. **Gated on id:16e9.** (2026-06-29-1750-dead-but-live-claim-heartbeat-gate) <!-- id:33d3 -->
- [ ] **AI2 — verify the heartbeat invariant:** confirm runs holding worktree-anchored claims beat (the pool does — id:98f0/e149); if a directed `/relay <repo>` path holds a worktree claim without beating, note the gap (D2's fallback keeps it safe). Folds into AI1's verification. (2026-06-29-1750-dead-but-live-claim-heartbeat-gate) <!-- id:33d3 -->
