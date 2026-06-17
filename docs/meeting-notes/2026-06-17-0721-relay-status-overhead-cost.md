# 2026-06-17 — Cut relay status/overhead cost (id:c3a6)

**Started:** 2026-06-17 07:21
**Session:** a047caa4-9d89-46a3-a73b-15c2ffde21d0
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing), 🎛️ Orla (multi-agent orchestration / model-tier economics, new), 🗄️ Cassi (build-cache / derived-data invalidation, new)
**Topic:** A third of relay spend ($220.90 / 34.9% over 5 runs / $633) is overhead, not repo work — where can model tiers be downgraded, and re-discovery redundancy be cut, without losing throughput or review quality?
**Dispatch:** no-arg `/meeting` → Class 3 (user redirected from the audit recommendation to `id:c3a6`, the HIGH-PRIORITY relay cost item).

## Surfaced discoveries
- `d6-builder-tier-decision` (memory): **Haiku fails LOGIC-HEAVY script/classification tasks** — critical bug on the 3e35 pilot; Sonnet-default confirmed for the D6 dispatcher. Load-bearing for the tier choice.
- Cross-ref `id:dba3` (sibling ROADMAP item, today): suspected Opus quality degradation 2026-06-16 eve — creates a "don't lean harder on cheap models for load-bearing logic this week" tension.

## Agenda
1. The quick-win: `discover-shard` (relay-loop.js:593) inherits Opus; sibling `discover-prelude` (526) is pinned sonnet.
2. Attribution first? — shards are phase `Discover`, not necessarily the econ `status` bucket.
3. The real [HARD] question: what else can downgrade safely?
4. Integrator (957, sonnet, 109 serialized/day) — model or frequency?

## Discussion

**Tier leak (items 1–2).** 🏗️ Archie: line 593 omits `model:` → inherits the session model (Opus); its identical-purpose sibling (526) is `model:'sonnet'`. Up to `6 shards × 30 rounds = 180` Opus classification agents/run. An omission, not a decision. ✂️ Petra: that half is a one-key fix, executor-sized — bank it, don't spend a meeting ratifying a typo-class change. 😈 Riku: two objections — (a) why sonnet not haiku? (b) "zero quality loss" only holds if sonnet classifies as accurately. 🎛️ Orla resolved both: the prelude is *already* sonnet doing the load-bearing global work, so sonnet is the internally-consistent tier; the shard prompt is logic-dense (EXECUTABLE-HARD test, orphan-park precedence) and Haiku is known to misclassify such tasks → haiku off the table. This restores an *intended* invariant (shard tier == prelude tier), not a quality gamble. ⚙️ Sage: `model:` is per-`agent()` call, so the pin is local, no blast radius. 😈 Riku (item 2): do not claim a dollar saving without re-profiling — the item warns shards are phase `Discover`, maybe not the `status` bucket; before/after `relay-econ.py` is the minimum evidence.

**Tier audit (item 3).** 🏗️ Archie corrected an earlier misread: the work-unit path (1059–1060) **already** pins `execute`→sonnet, review/handoff/hard→`STRONG_MODEL` — the 60.7% "work / 78% opus" is *legitimate* strong-reviewer work, not a leak. 🎛️ Orla: so the tier dimension is **saturated** after the shard fix — integrator/prelude are logic-dense (Haiku-fail risk), status/quota/release/gaming are already haiku (the floor). Pulling harder manufactures correctness risk for diminishing dollars, especially with `id:dba3` in play. 😈 Riku: the real money isn't tier, it's **redundancy** — line 1200 re-runs fresh discovery every round (≤30), re-classifying unchanged repos. ✂️ Petra: that's a *different item* with its own staleness surface — but the user chose to tackle it now.

**Re-discovery cache (item 3, D3).** 🗄️ Cassi: this is a build cache — the shards are a pure function of each repo's observable state; key the cached verdict on a hash of every input the function reads, err toward over-invalidation. 😈 Riku demanded the superset be *enumerated and proven* and produced an audit table mapping every classifier input to a signature component — catching the **liveClaims** trap (a repo's own files can be unchanged while another session *claims* it mid-run; the in-liveClaims flag must be in the key). 🏗️ Archie: the workflow JS sandbox has no bash, so a tested shell helper `discover-sig.sh` computes the superset hash and the **prelude** (already sonnet) just *runs* it. ⚙️ Sage: logic in the script, not the prompt — and **fail-open** (any git error → empty sentinel → re-classify). 😈 Riku: content-addressed, never time-addressed (no "every K rounds" cadence). The signature subsumes "was dispatched" (a dispatched repo's HEAD/tag/worktree all change), and review→execute chaining already handles the in-pool case — so no special-casing.

## Decisions
- **D1 — Pin `discover-shard` (relay-loop.js:593) to `model:'sonnet'`.** Sonnet not haiku (logic-density + `d6-builder-tier-decision`). Out of scope: any other agent's tier (all already deliberately pinned). Verification is a before/after `relay-econ.py` on a real pool run — report the actual bucket that moved (`id:9cb1`).
- **D2 — Tier audit is SATURATED.** No agent other than the shard can drop a tier without correctness risk: work-units already correctly tiered (execute→sonnet, review/hard→STRONG_MODEL); integrator/prelude stay sonnet (Haiku-fail risk); haiku is the floor for status/quota/release/gaming. This conclusion is the durable artifact — recorded so a future `/relay review` doesn't re-open `c3a6` to haiku-ify the integrator. Out of scope: downgrading the integrator.
- **D3 — Content-addressed discovery cache.** `discover-sig.sh` hashes a SUPERSET of all classifier inputs (HEAD, ckpt tags + latest message, porcelain, upstream ahead/behind, worktree dirs, orphan refs, relay.toml block, ROADMAP content, **in-liveClaims flag**); the prelude returns per-repo `signatures`; `runRound` reuses a cached verdict for unchanged repos, spawning an LLM shard only for changed/new/fail-open repos. **Fail-open** (empty sig or cache miss → re-classify; never a stale verdict). Out of scope: time-based cadence; changing the shard classification logic; the prelude's per-round inject/claim duties (uncached).
- **Out of scope (forward items):** integrator *frequency* (109 serialized, count not tier) → `id:c563`; structural discover *speed* (per-round `fetch`) → cross-ref existing `id:22ef` + discover-speedup track.

## Action items
- [x] Pin `discover-shard` to sonnet (relay-loop.js:593); shard test green. (D1) <!-- id:c3a6 -->
- [x] Build `relay/scripts/discover-sig.sh` (superset sig, fail-open) + `tests/test_discover_sig.sh`; Makefile allowlist (8 entries); `make test` green. (D3) <!-- id:c3a6 -->
- [x] Wire `signatures` into PRELUDE_SCHEMA + prelude prompt, `state.discoverCache` reuse in `runRound` + `tests/test_discover_cache.sh`. (D3) <!-- id:c3a6 -->
- [x] CLAUDE.md §Gotchas: discovery-is-signature-cached note (add-new-signal-to-sig warning). <!-- id:c3a6 -->
- [ ] Confirm D1 attribution on a real pool run: before/after `relay-econ.py`; report which cost bucket actually moved. <!-- id:9cb1 -->
- [ ] Integrator frequency (not tier): investigate batching / skipping no-op integrates (109 serialized/day, `relay-loop.js:455`). <!-- id:c563 -->

## Follow-up 2026-06-17 — forward items worked via worktree executor agents

Dispatched two isolated-worktree Sonnet executors against the forward items; both work integrated single-owner after fact-checking.

### id:9cb1 — attribution RESOLVED (live $ confirmation still pending)
The `discover-shard`/`discover-prelude` agents carry `phase: 'Discover'` (relay-loop.js:537,627); `profile-run.sh:140` maps that to `"discover"`; `relay-econ.py` `PHASE_CAT` (line 36) maps `"discover"` → **`scaffold`**, NOT `status`. So the headline 34.9% `status` overhead was the `RELAY_STATUS`/rollup write agents (a separate lever — cf. id:1a75), not the shards. The shard pin's saving will show as a collapsed Opus share in the **`scaffold`** column. Post-run check: `python3 relay/scripts/relay-econ.py --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print("scaffold $",d["cost"]["scaffold"],"| by_model:",d["cost_by_model"])'`. No post-fix pool-run data exists yet — id:9cb1 stays open for the live before/after.

### id:c563 — "skip no-op integrates" lever DOES NOT EXIST; only batching remains
`integrate()` already early-returns to `state.blocked` BEFORE the Sonnet agent (relay-loop.js:940 `!report`, 953 `!report.contract_met`; agent at 979), so the integrator agent spawns ONLY when `contract_met===true`. Event-log evidence (relay-events.jsonl, 2026-06-16): **168 dispatches → 119 genuine merges + 8 conflict-handbacks (Sonnet ran, merge conflicted) + 41 silent early-returns (no Sonnet)** — 100% of spawned integrators had real work; none wasteful. Conflict detection requires attempting the merge, so there is no safe pre-merge skip. Locked in by `tests/test_relay_integrator_noop_guard.sh` (`roadmap:c563`, structural). **Batching design (NOT implemented — high blast-radius):** the only remaining lever is collapsing N per-repo serialized `--no-ff` merges into fewer integrator invocations. Risks: the merge-to-canonical path is the single-owner-merge safety locus (D5/D6 "never two children pushing the same remote"); batching must preserve per-repo serialization and conflict isolation (one repo's conflict must not poison a batch). Stays a deferred design session — id:c563 open, narrowed to batching only.
