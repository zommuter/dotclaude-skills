# 2026-06-15 — Relay dispatch safety + resource-awareness cluster

**Started:** 2026-06-15 12:16
**Session:** 695b4f37-7bc3-4bc0-a2d5-1ab43393398c
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity)
**Topic:** Reconcile and sequence cross-session relay safety (claim/lease), `[INTENSIVE]` resource gating, and `/meeting`↔pool hold into one coherent contract.

## Surfaced discoveries
- [2026-06-12 dotclaude-skills] Held worktree under `~/.cache/fables-turn/worktrees/` is the only durable in-flight signal after an OOM kill (`oom-local-model-session-kills`).
- [2026-06-12 dotclaude-skills] Parallel-session state coordination: shape-matched flock/union/shard patterns; worktrees scoped to same-repo edits.

## Context
Three design threads surfaced in one chat (2026-06-15): (a) "what happens if a 2nd relay session runs while the pool is live?" — today nothing prevents same-repo overlap; relay.toml/RELAY_STATUS are written with no flock; (b) local-LLM tasks (ai-codebench, zkm index) need explicit-permission gating after the OOM that killed 6 sessions; (c) `/meeting` writes the shared ledgers in the main checkout while the pool merges worktree branches into them. They share one dispatch gate + one lock-with-TTL machinery, so they were decided together. A live demonstration occurred mid-session: a parallel cleanup daemon's autostash race left a tangled `~/.claude` stash — a fresh recurrence of id:3558.

## Agenda
1. Claim model — storage surface + granularity (repo vs item).
2. Claim lifecycle — staleness/TTL, crash recovery, reconciliation against git truth.
3. `[INTENSIVE]` resource gating — relationship to the claim/lease machinery.
4. ID reconciliation — ROADMAP id:7b7a/id:8ac5 vs existing TODO id:ebfb/id:3558.
5. Build sequencing (cheapest-first) + the round-boundary dry-stall.

## Discussion

**DP1 — storage + granularity.** Archie: live claims are high-churn; they belong in a dedicated registry, not the contended ledger/relay.toml (the `~/.claude` autostash race this session is the cautionary tale). ROADMAP stays *what*; the registry is *who/now*; a read-only projection into RELAY_STATUS gives the PM-board view. Riku: a registry can drift from git truth — when a session is OOM-killed the worktree is the real signal, so the registry must be reconcilable, never authoritative; and a single `claims.toml` is a contention point — prefer per-shard files like `persona-events/<session>.json`. Petra: N=2 passes (pool, handoff/review, executor, /meeting). Repo is the honest unit because integration merges into one checkout per repo (id:bc9d); item-level claims promise parallelism the merge can't honor. Archie: claim keyed by item id for *display*, enforcement per-repo. Riku: then claiming item X in repo R must atomically acquire R's lease; a 2nd claimant for R is refused at claim time — item-granularity = display, not parallelism. Riku (pre-emption, empirical-pilot profile): the cheapest claim already exists — a held foreign-runId worktree is an implicit lock; teach discovery to honor it first.

**DP2 — lifecycle + `[INTENSIVE]`.** Archie: the pool is a Workflow with no `Date.now()`/timers, so a script-driven heartbeat is awkward. Riku: use filesystem truth — claim-file mtime (stamped by the acquiring agent via bash `date`) + a flock'd `claim.sh` that reaps stale claims (mtime > TTL), agent-invoked like `quota-stop.sh`. Petra: one staleness mechanism only. Archie: stale claim + live worktree with WIP = crashed mid-work → recoverable handback (reuse id:738c); stale + no worktree → drop. Archie: `[INTENSIVE — local-llm]` is just a claim on a *resource* key (`claims/resource:local-llm.json`), same registry/helper — no separate semaphore. Riku: OOM is severe — conservative default is exclusive resource claim + collapse POOL_WIDTH→1 (run alone), never auto-dispatched without `--allow-intensive`/`--afk`. Petra: that shrinks id:8d52 to three bolt-ons (tag parse, permission flag, exclusive-claim+width-collapse).

**DP3 — reconciliation + sequencing + dry-stall.** Archie: id:ebfb already IS cross-session reservation/WIP-marking → the claim primitive; id:3558 is flock'd-merge-to-canonical → the repo-lease enforcement; the freshly-minted id:7b7a/id:8ac5 are duplicates. Petra: retire 7b7a + 8ac5 (superseded by ebfb/3558, no new tokens); keep id:8d52 (rescoped) and id:d748 (thin consumer, but distinct actor). Dry-stall: Archie — the round barrier idles dispatch; Riku — pipelining risks double-dispatch before integration lands (the barrier is for correctness); Petra — separate risk, id:bc9d already sped integration, observe before building.

## Decisions
1. **Claim storage** — dedicated per-shard registry `~/.config/fables-turn/claims/<key>.json` (mirrors `persona-events` shards), reconcilable against worktree+git truth, read-only projection into `RELAY_STATUS.md`. *Out of scope:* web board, claim history, single `claims.toml`, in-ledger markers.
2. **Granularity** — claim keyed by item id (display) with **per-repo enforcement**: claiming an item atomically locks its repo; a 2nd claimant for the repo is refused at claim time. Item-level *enforcement* (intra-repo parallelism on disjoint paths) → **wishlist**. *Out of scope:* two sessions merging one repo concurrently.
3. **Lifecycle** — staleness = claim-file **mtime + TTL** via a flock'd `claim.sh` (acquire/release/reap-stale; agent-invoked, no JS timer). Stale + live-worktree-with-WIP → recoverable handback (reuse id:738c); stale + no-worktree → drop. *Out of scope:* self-reported heartbeat, reflog scanning.
4. **`[INTENSIVE — <resource>]`** — a claim on a resource key (`claims/resource:local-llm.json`), exclusive; while held collapse `POOL_WIDTH→1` (run alone); never auto-dispatched without `--allow-intensive` / `--afk`. Reuses claim machinery; no separate semaphore. *Out of scope:* light-API work concurrent with an intensive unit (conservative until measured).
5. **ID reconciliation** — retire id:7b7a + id:8ac5 (superseded by ebfb/3558); keep id:8d52 (`[INTENSIVE]`, rescoped to claim-on-resource) + id:d748 (`/meeting` hold). Restores single-id-two-views.
6. **Dry-stall** — defer + observe; do not pipeline rounds in this build. *Out of scope:* overlapping next-round discovery with integration drain (revisit if measured cost is real post-bc9d).

## Build sequence (cheapest-first)
1. Worktree-aware discovery — discovery skips a repo with a fresh foreign-runId worktree [id:ebfb]
2. flock'd single-writer for `relay.toml` (field-scoped) + `RELAY_STATUS.md` (per-runId sections) [id:ebfb]
3. `claim.sh` + per-shard registry + RELAY_STATUS projection [id:ebfb]
4. repo-lease wired into dispatch + `/relay executor` honoring it [id:ebfb / id:3558]
5. `[INTENSIVE]` tag parse + permission gate + width-collapse [id:8d52]
6. `/meeting` hold (registry consumer) [id:d748]

## Action items
- [ ] **Ledger write-back (DEFERRED until the running pool is quiescent):** in ROADMAP retire id:7b7a + id:8ac5 with a "superseded by id:ebfb/id:3558" tombstone; rescope id:8d52 to "claim-on-resource"; keep id:d748; in TODO append the ratified design to id:ebfb + id:3558 citing this note. Same `id:` checkbox state across TODO/ROADMAP. (session 695b4f37) <!-- id:ebfb -->
- [ ] **Build step 1 — worktree-aware discovery** (cheapest-first slice): relay-loop.js discovery prompt skips repos with a fresh foreign-runId worktree; bash test asserts it. (session 695b4f37) <!-- id:ebfb -->
- [ ] **Observe dry-stall**: measure round-boundary idle now that id:bc9d sped integration; only build pipelining if the cost is real. (session 695b4f37) <!-- id:d748 -->
