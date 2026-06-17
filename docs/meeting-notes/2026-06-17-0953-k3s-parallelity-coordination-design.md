# 2026-06-17 — k3s-inspired parallelity: coordination substrate decision

**Started:** 2026-06-17 09:53
**Session:** 468ab449-1bb2-441e-bd24-dc766d47e232
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, standing), 🎛️ Orla (multi-agent orchestration, re-onboard), 🔩 Gil (git plumbing / ref-CAS, re-onboard)
**Topic:** Ratify a coordination substrate for the multi-machine relay (id:de4e) seeded 2026-06-16; meeting pivoted to local `/relay` ↔ `/meeting` ↔ `/relay human` parallelism.

## Surfaced discoveries
- [2026-06-03 dotclaude-skills] Multi-writer shared-state coordination is shape-dependent: β flock+union, γ shard+fold-collapse, δ flock'd deterministic merge.
- [2026-06-12 dotclaude-skills] Workflow engine + thin front door is the right substrate for an unattended relay loop; concurrency cap gives refill-as-finished for free.
- [2026-06-04 dotclaude-skills] Shared working tree across parallel sessions = cross-session snapshot races; per-session worktrees eliminate the class.
- Inbox routed:da2f — relay claim friction: a ledger-only write is blocked for the full duration of a multi-repo pool run by the whole-repo hard lease; path-set/sub-repo granularity (id:ca87) already flagged.

## Agenda
1. Substrate — git-remote CAS vs shared-FS vs external datastore.
2. Local parallelism — `/relay` ↔ `/meeting` ↔ `/relay human` coordination.
3 & 4. MVP cut + claim-then-crash TTL airtightness (collapsed by reframe).

## Discussion

### Item 1 — Substrate

🏗️ Archie opened by naming why k3s/etcd is wrong for our constraint: etcd needs a quorum, and "any subset of machines may be offline, including all but one" is exactly the case a quorum stalls. The SEED's reframe — use the git remote as the control plane with ref CAS — was put to pressure-test.

🔩 Gil confirmed the CAS primitive: `git push --atomic --force-with-lease=refs/relay/lock/<repo>:<old>` gives server-arbitrated, true multi-ref mutual exclusion — no flock, no always-on node, server serializes atomically.

🎛️ Orla: dynamic membership falls out for free (one node makes full progress, N nodes give N× parallelism, dead node's stale claim is reaped).

😈 Riku named four risks: (1) GitHub now a hard dependency — even same-host sessions must round-trip GitHub; (2) multi-ref atomicity needs `push --atomic` (confirmed solvable); (3) claim-then-crash + TTL: a HARD unit can run 100+ min, so TTL > 100 min = stranded repo for 100+ min if node dies; (4) rate limits from N-machine polling.

⚙️ Sage: proposed self-describing two-backend model — presence of `refs/relay/*` on origin = CAS mode; absence = flock as today. No mode flag; the refs *are* the mode. Prevents silent double-claims from mixed-mode sessions.

✂️ Petra: N=2 check — has the cross-machine race *actually* happened, or is this speculative? Our "observe before preventing" heuristic says build a logger first. Counter from 🎛️ Orla: the warrant may be *throughput* (break per-box agent ceiling), not safety. Riku: the substrate is the irreversible choice — forward-compat cost now vs rewrite-later.

**User ruling (D1):** The whole premise was reframed:
- **GitHub-as-control-plane is a NO-GO.** Serverless is the point; GitHub coordination dependency violates it.
- **Peer topology if ever built:** zomni ↔ fievel try to talk directly; if unreachable → degrade-to-solo (assume alone). No quorum, no leader.
- **Split-brain backstop:** the rare "both online but couldn't talk" case (cloudflare tunnel off-LAN — low likelihood) is caught after the fact by `md-merge.py` line-scoped writes + `--ff-only` reject-on-divergence + `orphan-scan --cross-ledger`. Optimistic concurrency + merge backstop, NOT pessimistic CAS.
- **Multi-machine is over-engineered NOW:** zomni alone exhausted the 7-day→daily quota share 2026-06-16. Cross-machine throughput is moot. id:de4e stays a SEED.
- **Productive pivot:** the same coordination thinking applies to local `/relay` ↔ `/meeting` ↔ `/relay human` on zomni.

### Item 2 — Local parallelism: /relay ↔ /meeting ↔ /relay human

🏗️ Archie grounded the actors: the pool edits code in worktrees + integrates to main checkout; `/meeting` and `/relay human` write ledger files (TODO/ROADMAP/REVIEW_ME) directly in the main checkout. The `hard` lease guards *code integration* but incidentally blocks ledger writes.

🔩 Gil: per-file flock makes the ledger *write* atomic but leaves a modified-but-uncommitted window. If the integrator does `git add -A` during that window, it scoops the ledger edit into a pool checkpoint (id:3558 hazard class).

🎛️ Orla named the live incident (routed:da2f, 2026-06-16): `/meeting`'s single `md-merge.py` append to TODO.md was forced to DEFER for a full multi-repo pool run because the pool held the whole-repo `hard` lease. The lease over-blocks.

⚙️ Sage: "don't take a lock you don't need" — ledger-only writes should not acquire the hard lease; they already have per-file flock + `--cross-ledger` backstop.

😈 Riku: the lease removal re-introduces the scoop window. This is load-bearing: the exemption must ship *with* scoop-window closure, never without.

🔩 Gil: two closing mechanisms: (i) atomic write+commit in the ledger-write path (scoped `git add <ledger-file> && commit`); (ii) ban `git add -A` in the integrator — scoped adds of its own merge paths only.

✂️ Petra held scope: option (a) full path-set granularity (id:ca87) and option (b) coexisting `ledger` claim mode are both over-engineered for this pain. Option (c) is minimal and correct. N=2 consumers of "ledger write under live pool" = `/meeting` + `/relay human` — both real, today.

**User ratified: Exempt + close scoop window (option c).**

### Items 3 & 4 — collapsed
- MVP = item 2's local fix. Multi-machine MVP is moot.
- Claim-then-crash TTL: only bites multi-machine. Local case covered by worktree-liveness + TTL reap (id:7570, id:3ac8).

## Decisions

**D1 — id:de4e stays a SEED. Multi-machine relay orchestrator: do NOT build now.**
- GitHub-as-control-plane / ref-CAS rejected. Serverless is the point.
- If ever built: peer rendezvous + degrade-to-solo + merge-backstop. Optimistic concurrency, NOT pessimistic CAS.
- Reason to defer: quota ceiling (zomni alone saturates quota; multi-machine throughput is moot).
- fievel single-point-of-failure (sole bare-git + website): separate infra concern, not in scope here.

**D2 — Exempt ledger-only writes from the `hard` lease + close the scoop window.**
- `/meeting` step 2a + `/relay human` ledger write-backs skip `claim.sh acquire`.
- `/meeting` step 2a changes DEFER → peek-and-warn.
- Hard lease narrows to: code/worktree integration only.
- Load-bearing precondition (ships with, never after, the exemption): close the scoop window via (i) atomic write+commit in `md-merge.py` and (ii) ban `git add -A` in `relay-loop.js` integrator.
- Out of scope: id:ca87 path-set granularity (deferred durable design for *code* intra-repo parallelism), routed:da2f option (b) coexisting ledger claim mode.

## Action items
- [ ] Exempt ledger-only writes from the `hard` lease; `/meeting` step 2a + `/relay human` skip `claim.sh acquire`; change DEFER → peek-and-warn. Contract: `/meeting` ledger write-back completes while pool holds repo `hard` lease, without DEFER. <!-- id:c144 -->
- [ ] Close scoop window (i): `meeting/md-merge.py` commits just the edited ledger file under the same flock (scoped `git add <file> && commit`). Contract: no modified-but-uncommitted ledger file in main checkout after ledger write. <!-- id:148b -->
- [ ] Close scoop window (ii): `relay-loop.js` integrator uses scoped `git add` on its own merge paths, never `git add -A`. Contract: concurrent uncommitted ledger edit is never captured in a pool checkpoint commit. <!-- id:debf -->
- [ ] Narrow `hard` lease scope + document the invariant: `claim.sh` / dispatch-safety docs state the split (hard lease = code/worktree only; ledger writes = flock + `--cross-ledger`). Contract: doc change + `make test` green. <!-- id:179e -->
- [ ] Annotate id:de4e with D1 constraints (no-GitHub / peer-or-assume-solo / merge-backstop / quota-ceiling-moot) on ROADMAP item + SEED note. Contract: `orphan-scan` no longer classifies id:de4e as a misleadingly-premised item. <!-- id:0b11 -->
- → routed to fievel repo (or future infra repo) inbox: fievel single-point-of-failure (sole bare-git host + website); capture as IT-infra TODO.
