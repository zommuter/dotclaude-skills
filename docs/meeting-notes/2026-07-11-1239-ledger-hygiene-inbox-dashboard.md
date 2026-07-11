# 2026-07-11 — Ledger drift, cleanup ordering, inbox rehaul, human-action dashboard

**Started:** 2026-07-11 12:39
**Session:** 20f3dcd1-e80a-41bd-9181-b72decb7f116
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🗺️ Flora (info-flow/routing), 🧮 Reni (multi-writer ledger merge/provenance)
**Topic:** Post-migration cleanup — cross-ledger drift detection, integrator destructive-cleanup ordering (6613), inbox-rehaul umbrella (9fdb), the LLM-free human-action dashboard (51d8 + auto-archive wiring 046a), and urgent residue from today's fleet-wide archive + tag-first migration.

## Agenda
1. Cross-ledger drift — 6 items ROADMAP `[x]` / TODO `[ ]`; archiver's id-keyed twin-check caught them, `orphan-scan --cross-ledger` missed them (indent-blind, id:431f class).
2. 6613 — integrator destructive-cleanup: hold-the-lease vs release-first + own-runId scoping.
3. 9fdb — inbox-rehaul umbrella remaining design after 411d.
4. Dashboard (51d8) + auto-archive wiring (046a).
5. Urgent residue — 45 unpushed repos; md-merge silent append (id:1b1a).

## Discussion

### Item 1 — Cross-ledger drift
🏗️ **Archie:** Six ids are closed in ROADMAP but open in TODO (zkWhale `dfcd`, dotclaude `78ff`, linguistic `fbcc`/`9828`/`e0e8`, toesnail `b7e5`). `archive-closed.sh` held them back via an id-keyed, indent-agnostic twin-check; `orphan-scan.sh --cross-ledger` reported ZERO for dotclaude because `78ff`'s TODO entry is an **indented sub-item** and the scan anchors `^- \[` at column 0 — the exact id:431f blindspot, now proven to blind the drift detector too.
🧮 **Reni:** Two ledgers = two writers of one bit ("is this id done?"). Two detectors with different coverage IS the defect; the id-keyed read is the correct oracle. Unify `--cross-ledger` onto it.
😈 **Riku:** Don't blind-tick the 6 to done — we hit `5e0f` today (one id, two scopes); ROADMAP `[x]` may discharge only a sub-scope. Verify each first.
✂️ **Petra:** No third tool — fold the twin-check into `--cross-ledger` (rides id:431f's `^\s*- \[` anchor-widening, N=2 satisfied). Reconcile the 6 as a one-time pass.

### Item 2 — 6613 integrator destructive-cleanup ordering
🏗️ **Archie:** Cleanup releases the lease first (id:ebfb, shorter contention); the 6e02 fix scoped it to own-runId artifacts. 6613 asks: hold the lease during destructive steps, or keep release-first?
🧮 **Reni:** Own-runId scoping makes cleanups commute (disjoint target sets) — idempotence-by-construction. A lease-hold guards a collision that can't happen; the guarantee lives in the scoping, not the lock.
😈 **Riku:** A lease-hold catches nothing the scoping-invariant check wouldn't (it'd still delete a mis-identified ref, just under a lock) — it only adds contention.
✂️ **Petra (pre-emption, profile — identity-resolution conservatism):** you'd want the report-only-with-opt-in-strict shape (as on id:4da4 pt2), not a work-halting lease-hold. Keep release-first + own-runId scoping; add a report-only relay-doctor invariant flagging foreign-runId cleanup.

### Item 3 — 9fdb inbox rehaul
🗺️ **Flora:** The inbox is a transient routing queue; the durable record is the target-repo `routed:` breadcrumb. Correct invariant = write-before-delete, which the automatic path (`scan-routed.sh --apply`) already enforces (drained 9 items live this session). Residual = one code path.
🏗️ **Archie:** Only unsafe path left is manual `inbox-done` — deletes with no twin-check on a gitignored/untracked store (no diff, no restore). Two composing fixes: (b) relocate the store into git-tracked `~/.claude/projects` (private, hourly auto-commits → free history/recovery) — dissolves "UNVERSIONED" + "no recovery path"; (a-guard) make manual `inbox-done` refuse unless the target twin exists.
🧮 **Reni:** git-backing subsumes (c) archive-move (history IS the archive); (e) conformance guards a symptom. (b)+(a-guard) dominate.
😈 **Riku:** Relocating changes only the default path — injection contract + flock intact, store stays private. Refuse-unless-twin correctly forces the 3 non-conforming prose lines to be made conforming rather than silently deleted.
✂️ **Petra:** (b) first (biggest leverage, `git mv` + default-path change), then (a-guard). Don't delete the manual verb — dead-letter/non-conforming cases still need a safe hand-disposition.

### Item 4 — Dashboard (51d8) + auto-archive wiring (046a)
🗺️ **Flora:** The dashboard is a pure projection of committed relay artifacts (`gather-human-backlog.sh` TSV, `RELAY_STATUS.md`, `relay-events.jsonl`). Splits into a mechanical precompute of the verbose steps + an LLM-free renderer (works with no session running).
🏗️ **Archie:** `RELAY_STATUS.md` is a per-run pool snapshot; the dashboard is cross-run/always-available → separate artifact, same generator. Nearest prior art: the `projects` dashboard skill.
✂️ **Petra:** MVP = precompute + read-only view; TUI + run-now is phase 2 (framework + shell-exec safety). [User overrode: build the FULL thing, but deliver it via the relay loop.]
😈 **Riku:** Run-now safety (profile pre-emption): never-auto-fire, always-confirm, only idempotent/safe classes one-click, `host-gate.sh` for host-bound, irreversible/hands = show-steps-only. Decide now; precompute tags each item's class.
🗺️ **Flora:** Refresh trigger shared with 046a — one `systemd --user` timer (relay-gap-sample pattern) regenerates the dashboard + runs `archive-closed`; NOT per-prompt; survives with no session.
🧮 **Reni:** 046a "less conservative" = drop age-gate + trailing-date, both ledgers, keep only the twin-safe rule (safe at any cadence).

### Item 5 — Urgent residue
🏗️ **Archie:** (1) 45 repos carry unpushed archive+migration commits (disk-only). (2) id:1b1a — `md-merge.py update-ids` silently APPENDS an unmatched id; I leaned on it for ~24 ticks today.
😈 **Riku:** (1) durability gap — push them (clean commits). (2) fail-open-substring family (411d/0d58); queued HIGH; scan now for dup-ids created this session.
🧮 **Reni (pool-interference, user-raised):** timer/bulk writers must be good citizens: `claim.sh peek` + clean-tree gate, skip pool-held/dirty repos; push-45 reads pool state and pushes only clean+un-claimed.
😈 **Riku (anti-starvation, user amendment):** peek-and-skip alone STARVES a persistently-claimed repo (commits pile up forever). Add **bounded-deferral escalation**: after K consecutive skips, `claim.sh acquire` to force the write through. Bounds any recurring peek-and-skip writer.

## Decisions
- **D1** — Unify `orphan-scan.sh --cross-ledger` on an id-keyed, indent-agnostic twin-check shared with `archive-closed.sh` (rides id:431f anchor-widening). One oracle, two consumers. *Out:* a third detector.
- **D2** — Reconcile the 6 drift items verify-then-tick (confirm ROADMAP-done covers the TODO twin's scope; else re-id/keep-open, the 5e0f pattern). *Out:* blind-ticking all 6.
- **D3** — 6613: keep release-first + own-runId scoping; add a report-only relay-doctor invariant flagging foreign-runId cleanup. *Out:* a work-halting lease-hold.
- **D4** — 9fdb: relocate the inbox store into git-tracked `~/.claude/projects` FIRST, then make manual `inbox-done` refuse-unless-target-twin-exists. *Out:* (c) archive-move, (e) conformance, deleting the manual verb; (d)/411d shipped. Injection + flock unchanged; never hardcode the path in a public script.
- **D5** — Dashboard 51d8: full build (precompute → LLM-free renderer/separate-artifact → TUI+run-now → timer) decomposed into ROADMAP items and handed to the relay pool. Run-now = never-auto/always-confirm/idempotent-only-one-click/host-gated/irreversible-show-steps-only. *Out:* pilot-gating phase 2; coupling to RELAY_STATUS.md's lifecycle.
- **D6** — 046a: one `systemd --user` timer regenerates the dashboard + runs less-conservative twin-safe `archive-closed` (no age-gate, no trailing-date, both ledgers). Pool-safe with **bounded-deferral escalation**: peek+skip pool-held/dirty repos, but after K consecutive skips `claim.sh acquire` to prevent starvation. *Out:* review-sub-step as primary trigger; unbounded peek-and-skip.
- **D7** — Push the 45 unpushed repos (pool-safe: skip claimed/dirty); dup-id scan for md-merge silent appends; id:1b1a stays queued HIGH with that scan as acceptance.

## Action items
- [ ] Unify `orphan-scan.sh --cross-ledger` on an id-keyed indent-agnostic twin-check shared with `archive-closed.sh` (coordinate with id:431f). Contract: drift where the TODO twin is indented IS flagged. (D1) <!-- id:34c7 -->
- [ ] Reconcile the 6 cross-ledger drift items verify-then-tick: zkWhale dfcd, dotclaude 78ff, linguistic fbcc/9828/e0e8, toesnail b7e5. (D2) <!-- id:7ff6 -->
- [ ] 6613: add a report-only relay-doctor invariant flagging integrator cleanup touching a foreign runId's artifacts; keep release-first. (D3, updates id:6613)
- [ ] 9fdb: relocate inbox store into git-tracked `~/.claude/projects` (default path, injection-preserved), then make manual `inbox-done` refuse-unless-target-twin-exists. (D4, updates id:9fdb)
- [ ] 51d8: decompose the full dashboard into ROADMAP build items for the relay pool; run-now = never-auto/confirm/host-gated/show-steps-for-irreversible. (D5, updates id:51d8)
- [ ] 046a: one systemd --user timer regenerating the dashboard + running less-conservative twin-safe `archive-closed`, pool-safe via peek+clean-tree gate WITH bounded-deferral escalation (acquire after K skips). (D6, updates id:046a)
- [ ] Push the 45 unpushed repos (pool-safe: skip claimed/dirty) + dup-id scan for md-merge silent appends. (D7) <!-- id:50af -->

## Amendment session — "claim means claim" for ledger writes

Arose mid-meeting (user: "peek+warn ... claim means claim, not 'if you please'").

🏗️ **Archie:** id:c144 took ledger writes OFF the long `hard` code lease to avoid deadlocking a meeting's box-tick on a pool's worktree integration; "peek-and-warn" was the escape. The fix can't re-gate ledger writes on the code lease.
🧮 **Reni:** One word "claim" covers two locks of different lifetime — a long **repo-owner** claim ("don't start new work here") and a short **ledger-write mutex** (the flock). Make both enforced; the short one never deadlocks.
😈 **Riku:** The concrete hazard is a pool unit already integrating when the meeting acquires. Fix: the non-holder DEFERS its ledger write (via the existing id:2c42 drop-file) rather than writing anyway — which is exactly the pre-planned **id:9000** bilateral honored-claim ("today peek is read-only").
✂️ **Petra:** Minimal enforceable: forbid raw-`Edit` ledger writes (route all through flock'd `md-merge`), and defer via the id:2c42 drop-file when the other side owns the claim. mtime-TTL still auto-expires a crashed holder.
🗺️ **Flora:** Make it bilateral/symmetric — pool defers to meeting the same way the meeting already defers to the pool on flock-timeout.

**User steer:** build id:9000 (option 1) as the enforcement fix — BUT also consider making `/meeting` a **relay PRODUCER**: the meeting commits its ledger edits + note to a **worktree branch** that the serialized integrator merges (one writer to main), so the claim is only needed for the meeting's own end-merge if it self-integrates; otherwise a live pool's reviewer picks up the meeting worktree like any other unit. Plan-mode hurdle dissolves (plan file is out-of-repo; move the note/TODO/ROADMAP/REVIEW_ME writes to the worktree on ExitPlanMode).

**Assessment:** the worktree-producer is the *dissolve-vs-guard* version — it removes the second writer entirely, so there's nothing for a claim to enforce. It **reopens af04** (worktree-per-meeting was rejected — but for concurrency-isolation with non-unionable checkbox merges + same-dir flock as the alternative; reframed as producer-routing through the existing `--no-ff` integrator that already surfaces conflicts, the af04 objection is much weaker — a legitimate re-justification). It would **retire the need for id:9000's ledger-write enforcement**.

## Amendment decisions
- **A1** — Build **id:9000** (bilateral honored-claim) as the near-term enforcement: the non-holder DEFERS its ledger write via the id:2c42 drop-file (replayed on release), forbid raw-`Edit` ledger writes (flock'd `md-merge` only). Interim guard.
- **A2** — Design **meeting-as-relay-producer** (id:5a39): `/meeting` writes its note + ledger edits to a worktree branch merged by the serialized integrator (one writer to main); self-merge under a claim only if no pool is live, else park for the reviewer. This DISSOLVES the contention and would SUPERSEDE A1's enforcement. **Evaluate A2 before sinking heavy work into A1** (dissolve-before-guard) — reopens af04 with new reasoning; record the reversal explicitly if adopted.

## Amendment action items
- [ ] Build id:9000 bilateral honored-claim: non-holder defers its ledger write via the id:2c42 drop-file (replay on release); forbid raw-Edit ledger writes (flock'd md-merge only); bilateral/symmetric meeting↔pool. Interim guard — gate heavy investment on the id:5a39 evaluation. (A1, updates id:9000)
- [ ] Design meeting-as-relay-producer: `/meeting` commits note + ledger edits to a worktree branch merged by the serialized integrator (one writer to main); self-merge under claim iff no pool live, else park for the reviewer; move plan-mode-era in-repo writes to the worktree on ExitPlanMode. Reopens af04 (record reversal). May supersede id:9000/A1. (A2) <!-- id:5a39 -->
