# 2026-06-12 — Fables relay autonomous worker-pool design

**Started:** 2026-06-12 20:45
**Session:** 04183819-6cbb-49c1-a029-d0d1d30d3e41
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration), 🔩 Gil (git plumbing), ⚙️ Sage (skill-runtime)
**Topic:** Design a single autonomous orchestrator entry point for the fables relay — continuous priority-mixed worker-pool replacing the manual handoff/review/execute split.

## Surfaced discoveries

- [2026-06-12 dotclaude-skills] /batch is a built-in Claude Code command (differs from fables-turn relay — serial review→exec→verify, no PR per item) — see docs/meeting-notes/2026-06-12-1404-fables-executor-skill.md
- [2026-06-12 dotclaude-skills] git-lock-push.sh --ff-only flag scopes relay-specific push — see docs/meeting-notes/2026-06-12-1342-fables-turn-integration-defects.md

## Agenda

1. Skill-merge shape — true merge vs alias-preservation of the dual executor audience.
2. Orchestration substrate — Workflow script vs. main-loop Agent dispatch.
3. Scheduler — per-repo tier classification, priority mixing, and config knobs.
4. Stop signal, push policy, and async surfacing.

## Discussion

### Item 1 — merge shape → RESOLVED

⚙️ Sage opened with a key context fact: the executor contract was split *out* of fables-turn into `fables-executor` the same day (2026-06-12, per 1404-fables-executor-skill.md). "Merge" would partly reverse that decision. The contract has two audiences — orchestrator-spawned children (doc handed directly) and standalone executor sessions loading `/fables-executor` from the repo's `CLAUDE.md`. Eight repos carry byte-identical pointer text; test id:7691 enforces version-match.

🏗️ Archie proposed two shapes: (A) alias-preserving merge — one new entry point, keep `fables-executor` addressable; (B) full collapse — embed contract, migrate 8 repos, retire id:7691. ✂️ Petra applied the N=2 rule: only one concrete improvement from physical merging (single entry point), not two.

**User clarification:** the goal is not a file merge. The goal is *one simple command* that autonomously dispatches per repo — execute / review / handoff "if adequate" — without any keyword. Keep `fables-executor` and the 8 CLAUDE.md pointers exactly as-is.

### Item 2 — orchestration substrate → RESOLVED

🎛️ Orla presented two substrates. Option A (Workflow script): 5-wide pool + refill-as-finished built into the concurrency model; serialized integrator structural not model-trusted; quota guard via `budget`; async surfacing to files; runs in background. Option B (main-loop dispatch): strong-model context accumulates child payloads; max interactive flexibility; but pays Fable/Opus rates to babysit a pool dispatcher.

✂️ Petra: B burns the expensive tier on dispatcher overhead. 🔩 Gil: the Workflow JS can't run `git` — integration (merge → ckpt-tag → push) must be done by an agent funnelled through a coordinator, expressible but must be designed explicitly.

🏗️ Archie's recommendation: Option A (front-door skill + Workflow engine). **User confirmed, adding a hard constraint: unattended by default — no `AskUserQuestion` unless the call explicitly permits it via opt-in flag.** Front door operates only on already-confirmed "own" repos; surfaces (never asks about) new/dirty/needs_review repos.

### Item 3 — scheduler → RESOLVED

🎛️ Orla proposed the per-repo classifier (reusing discover-repos.sh + review diff-window primitives):
- **execute (Sonnet):** ≥1 open [ROUTINE] item with red tests.
- **review (strong):** commits since last `fable-ckpt-*` unaudited, OR `status=handed-off` awaiting first review.
- **handoff (strong):** no roadmap-v1 marker, or roadmap exhausted + new untracked work ("if adequate").
- **idle:** nothing actionable.

😈 Riku named the strict-phased vs. priority-mixed fork: strict phased (drain all executor work everywhere, *then* review) delays the anti-gaming audit and starves roadmap-regeneration. Priority-mixed (prefer Sonnet execute to fill a slot; backfill idle slots with strong review) keeps audit current and the loop self-feeding.

✂️ Petra: strict phased = cheapest/most predictable; priority-mixed = faster convergence + audit sooner. 🎛️ Orla/😈 Riku: priority-mixed is cost-discipline-compatible (Sonnet-first) while converging rather than stalling.

**User chose priority-mixed.** Tiers confirmed: Execute=Sonnet, Review+Handoff=strong. **Strong tier = config knob `STRONG_TIER ∈ {fable, opus}`, default fable.** User: "would opus be an option for handoff as well? We need to consider Opus for the post-fable-in-subscription phase anyway, so we might pilot that soon" — Opus pilotable via flag.

Unreviewed-executor review ranks above fresh handoff (ensuring the anti-gaming window stays short).

### Item 4 — stop signal / push policy / surfacing → RESOLVED

😈 Riku on quota: no callable API (statusline 429s after ~5 total requests). But `/tmp/claude-usage-cache.json` (statusline-maintained) has all three relevant buckets: `seven_day_sonnet`, `five_hour`, `seven_day`.

**User clarified quota mechanics:** "Sonnet uses _all_ three quotas and stops working when the first one is used up, whether that's the Sonnet one, the 5h or the weekly one." → Sonnet-dispatch gate = first-exhausted of all three; strong-dispatch gate = first of {five_hour, seven_day}. Graceful: stop dispatching new, let in-flight finish, drain all integration debt. Seatbelt: hard agent-count + wall-clock cap.

😈 Riku raised push-policy risk: unattended, gamed work sits on main until retrospective review catches it. ✂️ Petra: push-to-main + retrospective review has worked without incident so far; priority-mixed keeps the review window short; staging-branch is a meaningful build for an unrealized risk. Riku accepted on one condition: unreviewed-executor work is guaranteed to be the top-priority strong unit (now a policy invariant).

**User chose push-to-main + retrospective review.** Surfacing (settled without vote): per-repo `REVIEW_ME.md` (existing judgment-call channel); cross-repo `RELAY_STATUS.md` rollup written on every integration + phase transition, plus `log()` to /workflows live view. Async, non-blocking.

## Decisions

**Decision provenance (Opus harness):** all four agenda items ratified via AskUserQuestion picks quoted verbatim in the transcript above.

- **D1 — No physical file-merge.** Build one new autonomous orchestrator entry point; keep `fables-executor`, the 8 CLAUDE.md `/fables-executor` pointers, and test id:7691 exactly as-is. Out of scope: collapsing the contract or migrating any repo's CLAUDE.md.
- **D2 — Workflow engine + thin front door.** Front door = non-interactive setup (confirmed "own" repos only; surface new/dirty/needs_review, never ask). Workflow script owns pool + serialized integrator + quota guards. **Unattended by default; `AskUserQuestion` only if `--interactive` flag is passed.** Out of scope: interactive mid-flight prompting by default.
- **D3 — Priority-mixed pool, ≤5 distinct repos.** Prefer Sonnet execute; backfill idle slots with strong review/handoff; unreviewed-executor review ranks above fresh handoff. Classifier reuses discover-repos.sh + review diff-window primitives. Out of scope: strict-phased scheduling; >1 unit/repo concurrently.
- **D4 — Tiers + STRONG_TIER knob.** Execute=Sonnet; Review+Handoff=`STRONG_TIER ∈ {fable, opus}`, default fable. Out of scope: Sonnet-authored handoff roadmaps/red-tests.
- **D5 — Tier-aware quota stop.** Read `/tmp/claude-usage-cache.json`; Sonnet = first-exhausted of all three buckets; strong = first of {five_hour, seven_day}; graceful drain; agent-count/wall-clock seatbelt. Out of scope: calling the usage API directly.
- **D6 — Push-to-main + retrospective review.** Keep current push semantics; loud RELAY_STATUS.md surfacing. Out of scope: staging-branch/review-gated-main (deferred, reopen if gaming appears at scale).

## Action items

- [x] A1: New orchestrator front-door skill (default mode of `/fables-turn` no-arg, or new `/fables`): non-interactive discovery + classification + safe-set selection; invokes Workflow engine; `--interactive` opt-in flag. Contract: no-arg invocation on a clean confirmed fleet dispatches without any prompt. — SHIPPED as `/relay` no-arg default mode (autonomous pool, no AskUserQuestion, launches the relay-loop.js Workflow; fables-turn→relay migration); verified 2026-07-18. <!-- id:230f -->
- [x] A2: Workflow script `fables-turn/scripts/relay-loop.js` — priority-mixed 5-wide pool; per-repo classifier; tier dispatch (Sonnet execute, STRONG_TIER review+handoff); SERIALIZED integrator (single-threaded merge→ckpt-tag→`git-lock-push.sh --ff-only`, one push per repo); graceful drain; quota-stop integration. Contract test: never two concurrent pushes to the same remote; threshold-cross drains in-flight before exit. — SHIPPED as `relay/scripts/relay-loop.js` (per-repo serialized integrator, tier dispatch, graceful drain; test_relay_loop_structure.sh); verified 2026-07-18. <!-- id:83c9 -->
- [x] A3: Tier-aware quota-stop helper reading `/tmp/claude-usage-cache.json`: Sonnet stop = first-exhausted of {seven_day_sonnet, five_hour, seven_day}; strong stop = first of {five_hour, seven_day}; stale-cache + missing-file fallback to seatbelt caps. Contract test: synthetic cache JSON at various utilizations gates each tier correctly. — SHIPPED as `relay/scripts/quota-stop.sh` (tier-aware, seatbelt fallback; test_relay_quota_*); verified 2026-07-18. <!-- id:9934 -->
- [x] A4: `STRONG_TIER` config knob (env var + CLI flag, default fable; `opus` pilotable) threaded into agent() model overrides in relay-loop.js. — SHIPPED (STRONG_TIER knob in relay-loop.js + SKILL.md; test_strong_tier_knob.sh); verified 2026-07-18. <!-- id:aeaf -->
- [x] A5: `RELAY_STATUS.md` rollup writer + template (repos in-flight, units done/queued/blocked, quota remaining per bucket, HANDBACKs, REVIEW_ME pointers); rewrite on every integration + phase transition. — SHIPPED as the writeRelayStatus/scheduleStatusWrite path (off-critical-path since id:cb50; relay-state-write.sh + relay-status-publish.sh; test_relay_status*.sh); verified 2026-07-18. <!-- id:80e2 -->
- [ ] A6: Pilot on 1–2 income repos (trAIdBTC or zkWhale) before any fleet-wide unattended run; first-contact revision expected; consider an Opus-handoff pilot in the same window. <!-- id:1ad7 -->
