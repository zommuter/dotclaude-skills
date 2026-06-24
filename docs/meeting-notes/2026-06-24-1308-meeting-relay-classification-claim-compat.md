# 2026-06-24 — /meeting vs /relay: shared classification, visualization, claim compatibility

**Started:** 2026-06-24 13:08
**Session:** cdf958f5-60a3-476d-9f5f-997426fb39e6
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, new), 🎛️ Orla (multi-agent orchestration, new), 🔩 Gil (git plumbing/worktree, new), 🎨 Vera (frontend/visualization, new)
**Topic:** Could /meeting and /relay share a task-classification model, would better visualization help, and should /meeting become worktree/claim-compatible with the pool?

## Surfaced discoveries / prior art
- [[meeting-pool-claim-asymmetry-incident]] — /meeting acquires NO claim at start → pool re-derives off stale base (2 instances: trAIdBTC, truncocraft). id:9000 build-warranted.
- [[ledger-derived-index-decision-2840]] — id:2840 unified derived index (md=SSOT, index=cache) is the decided substrate for TODO↔ROADMAP visualization.
- `hard-lanes.md` — pool/meeting/hands lane vocabulary ALREADY shared between gather-human-backlog.sh + project_manager scan.py (id:78ff/b466).
- [[meeting-worktree-rejected-af04]] — literal worktree-per-/meeting REJECTED (non-unionable checkboxes; /meeting = same-dir + flock; worktrees are code-only).

## Agenda
1. Is there a genuinely shareable task-classification model across /meeting and /relay, or only a shared sub-axis?
2. Would better visualization help — new view or existing surface?
3. Should /meeting become worktree/claim-compatible to close the pool-collision asymmetry?

## Discussion

### Item 1 — shared classification model
🏗️ Archie: Different OBJECTS. `classify.sh`: TODO items → C1/C2/C3 (design-readiness). `discover-shard`: repos → execute/review/hard/handoff (next-action). `gather-human-backlog.sh`: `[HARD]` items → pool/meeting/hands (disposition). Only disposition is shared — already extracted as `hard-lanes.md`, read by relay + project_manager, cross-checked by test_hard_lane_buckets.sh.

✂️ Petra (N=2): A unified classifier needs ≥2 consumers using the SAME enum. C1/C2/C3 vs execute/review/hard/handoff are not the same enum (different objects/lifecycles). The shared sub-model (lanes) already has its N=2. A grand-unified classifier has no second consumer.

😈 Riku: Unifying couples two independently-evolving skills — a relay verdict change ripples into /meeting. The only contact point (`[HARD — meeting]` ↔ classify.sh `[HARD]`→C3 floor) is coherent. No inconsistent-classification case exists to justify more.

⚙️ Sage: Keep the shared artifact a DATA contract, not shared CODE (bash/TSV vs LLM prompt). Cheap win: classify.sh surfaces the lane tag on C3 `[HARD]` items so /meeting shows disposition.

### Item 2 — visualization
🎨 Vera: Three disjoint views — RELAY_STATUS.md, /meeting bucket summary, `proj relay` cockpit. Can't see pool + meeting at once.

🎛️ Orla: Pool observability is already rich; the gap is /meeting↔relay CROSS-visibility — the claim-asymmetry, visualized.

✂️ Petra: Don't invent a dashboard. project_manager scan.py already aggregates via the same lane vocab; id:2840 is the decided substrate. Payoff is downstream of making the /meeting claim VISIBLE (item 3).

😈 Riku: Bound it — the concrete need is "see the pool while I meet" = statusline relay segment (exists) + surfacing the meeting's claim.

### Item 3 — worktree / claim compatibility
🔩 Gil: id:aa93 already prevents CORRUPTION; residual = wasted stale-base work + a half-committed orphan branch (truncocraft 2nd instance — worse class, uncovered by aa93).

🎛️ Orla: Asymmetry: pool claims at dispatch; /meeting claims only at step-2a write-back. Fix: /meeting acquires an advisory claim at SETUP; pool already honors claims → skips that repo for the meeting's duration; released at end. id:9000's cheapest half.

😈 Riku: Tradeoff — a long meeting blocks the pool from that ONE repo. Acceptable: one repo, TTL auto-expiry, only the repo under discussion. Beats wasted work + orphan branches.

🏗️ Archie: Manual version (used this session): launch the pool with `--exclude <meeting-repo>`. The build automates it.

✂️ Petra: Scope guard — output is the setup-claim decision; id:9000's notify-channel/message-bus half stays deferred (observe-first).

## Decisions

**D1 — No unified classifier; affirm lanes + ADD a disposition-routing surface to /meeting.**
- Keep `hard-lanes.md` (pool/meeting/hands) as the ONLY shared sub-model — no merge of C1/C2/C3 with execute/review/hard/handoff (different objects/enums/runtimes; no second consumer — Petra N=2).
- NEW (user): /meeting's classification output (classify.sh + bucket summary) surfaces per-item **disposition routing** — each open item flagged **human-interaction** (→ `/relay human`; lanes `meeting`/`hands`, or `@manual`) or **pool-autonomous** (→ `/relay executor` for `[ROUTINE]`, `/relay review` for unaudited commits, or `[HARD — pool]`). Read-only; reuses lane vocab + ROADMAP state.
- /meeting respects the worktree+claim mechanism in relay-managed repos (ties to D3).
- **Out of scope:** merging the two enums; shared classifier code.

**D2 — Visualization: extend the existing cockpit now; backlog a unified dashboard.**
- Route cross-visibility through `project_manager`'s `proj relay` cockpit + the id:2840 derived index (md=SSOT). Concretely: surface the /meeting advisory claim (D3) there.
- **Backlog (deferred, "potential later improvement" — user):** a unified live dashboard spanning pool + meeting + ledgers. `[HARD — meeting]`, gated; revisit after D3.

**D3 — /meeting becomes claim-compatible: advisory claim at SETUP + claim-aware offer.**
- /meeting acquires an **advisory repo claim at SETUP** (not just step-2a write-back); pool honors claims (`claim.sh peek`) → skips the repo for the meeting's duration; released at end (TTL backstop). Closes the one-sided-lease asymmetry — id:9000's cheapest half. Manual equivalent (this session): `--exclude <meeting-repo>`.
- **Claim-aware offer (user):** when the target repo is ALREADY claimed by a live pool at setup, /meeting **informs** the user and **offers a non-conflicting session** — the read/think/**decide** phase needs no claim, so design decisions proceed in parallel; only the ledger **write-back** respects the claim and is **deferred + replayed** (id:2c42).
- **Resolved tension (af04):** "using worktrees?" — worktree-per-/meeting for ledger writes was REJECTED (non-unionable checkboxes; /meeting = same-dir + flock; worktrees are code-only — [[meeting-worktree-rejected-af04]]). The non-conflicting session is achieved via **defer-the-write-back**, NOT a worktree. Decisions live in this note regardless; id:2c42 replays the write under a fresh claim once the pool frees the repo.
- **Out of scope (deferred, observe-first):** id:9000's richer ACTIVE notify-channel / message-bus half.

## Action items
- [ ] /meeting disposition-routing surface: classify.sh + bucket summary tag each open item human-interaction (`/relay human`) vs pool-autonomous (`/relay executor`/`review`/`[HARD — pool]`), reusing hard-lanes.md + ROADMAP state. Red test: a fixture item per lane/state maps to the right disposition label. (2026-06-24-1308 note) <!-- id:3bf3 -->
- [ ] /meeting claim-compatibility: acquire advisory claim at SETUP + release at end; on an EXISTING pool claim, inform + offer a non-conflicting (decide-now, defer-write-back via id:2c42) session — explicitly NOT worktree-per-meeting (af04). References id:9000 (cheap half), id:2c42 (defer/replay), id:0902/ebfb (claim). (2026-06-24-1308 note) <!-- id:672b -->
- [ ] Surface the /meeting advisory claim in the project_manager `proj relay` cockpit / id:2840 derived index (cross-visibility). References id:2840. (2026-06-24-1308 note) <!-- id:3536 -->
- [ ] [HARD — meeting] BACKLOG (deferred): unified live dashboard spanning pool + meeting + ledgers. Gated; revisit after id:672b. (2026-06-24-1308 note) <!-- id:36f1 -->
