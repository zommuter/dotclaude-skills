# 2026-06-17 — Relay integrator frequency: is batching viable? (id:c563 close)

**Started:** 2026-06-17 08:12
**Session:** 4b3ac39a-3aad-4382-a2d2-3946f944f354
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🎛️ Orla (multi-agent orchestration — relay-fleet lens), 🔩 Gil (git plumbing / merge-conflict isolation)
**Topic:** id:c563 narrowed to integrator *frequency* (not tier, which was closed by id:c3a6). The only remaining candidate lever was "batching." Decide whether any batchable window exists and dispose the item.

## Surfaced discoveries / prior decisions
- id:c3a6 (2026-06-17): tier audit SATURATED — integrator stays sonnet; "do NOT haiku-ify the integrator." id:c563 is scoped to *frequency, not tier*.
- id:c563 prior narrowing (2026-06-17-0721 session): "skip no-op integrates" lever does NOT exist — `integrate()` already early-returns to `state.blocked` BEFORE the Sonnet agent for `null`/`contract_met=false` (`relay-loop.js:940/953`; agent at `:979`). 168 dispatches → 119 merges + 8 conflict-handbacks + 41 silent early-returns. 100% of spawned integrators had genuine work.

## Evidence gathered this session
Source: `~/.config/fables-turn/relay-events.jsonl` (2026-06-16 data), `relay/scripts/relay-econ.py`

- 119 integrate events across 54 (run,repo) pairs; 29 pairs had >1 integration (up to 8 for `dotclaude-skills` in one run).
- **Temporal spread of multi-integrations:** for `dotclaude-skills`, the 8 integrations in one run landed at 11:57, 12:13, 12:38, 12:50, 13:02, 13:12, 13:52, 14:28 — one per round, each branch built on the prior round's checkpoint. Median span across all multi-integrate (run,repo) pairs: ~100 min; max 3.5 h.
- **Cost context:** work=$1133, status=$438, scaffold=$108. By model: opus=$1317 (76%), sonnet=$285, haiku=$93, fable=$1.6. The integrator is sonnet-pinned — a slice of the sonnet bucket, a rounding error vs Opus.

## Discussion

**🏗️ Archie:** Per-repo serialization at `enqueueIntegration` (`:472`) is a promise chain — same-repo merges never race. Cross-repo integration is already parallel (`:465`). The temporal data answers the "batch a repo's integrations" idea directly: later integrations physically descend from earlier checkpoints (round N's child built its branch on the checkpoint round N-1 pushed). You cannot collapse the 14:28 merge with the 11:57 one. Intra-repo batching has no co-ready target.

**🎛️ Orla:** The only co-ready window is cross-repo — in one dispatch wave, repos A/B/C/D finish around the same time. Collapsing four parallel integrator agents into one saves three agent spin-ups per wave. But this reverses the line-465 fix (serialized integrator made "the pool LOOK 1-wide"). Re-serializing trades a known latency win for sonnet token savings. Wrong side of the trade.

**✂️ Petra:** Warrantability bar: $1317 of ~$1737 is Opus. The integrator is part of the $285 sonnet bucket. Total elimination of the integrator saves low-single-digit percent. N=2 test: I can't name even one consumer with material payoff. This is optimizing a rounding error.

**😈 Riku:** Agreed, but record *why* cross-repo batching is unsafe so the rejection is on the record. The integrator is the single-owner-merge-to-canonical safety locus (D5/D6). One agent merging four repos means: (a) one conflict must not poison the other three — you'd need per-repo try/abort/continue in a place already pinned sonnet for logic-density; (b) a mid-batch divergence strands the rest of the batch; (c) it serializes conflict isolation that's currently free. Minimum evidence to change my vote: co-ready cross-repo integrations dominating AND integrator tokens showing as a named cost bucket. Neither holds.

**🔩 Gil:** Plumbing agrees. Each integration is `merge --no-ff` + `ckpt-tag` + `git-lock-push --ff-only`. The flock in `git-lock-push.sh` already serializes the push per-repo for the same-remote case. Batching cross-repo into one agent doesn't remove contention — it moves N independent, individually-abortable merge transactions into one agent's sequential loop where a failure at step k strands k+1..N's worktrees. Failure atom: wave not repo. Strictly worse recovery, zero plumbing gain.

**🏗️ Archie:** Both axes fail. The frequency is *intrinsic* — one integration per repo per round IS the productive-progress signal (`produced` at `:1234`). Cutting it cuts throughput.

**🎛️ Orla:** Forward note: the only thing that would create a real batching target is a future change making multiple same-repo units co-ready in one wave (e.g. injections `id:fb75/6e9d` dispatching several same-repo executes simultaneously). Today discovery picks one verdict per repo per round — it cannot occur. Re-open as a consequence of *that* change, not as standalone work.

**✂️ Petra:** Dispose the same way as the "skip no-op" half: close as "lever does not exist," record why, lock the reasoning.

**😈 Riku:** Sign off — with Orla's falsifiable re-open trigger recorded so "closed" ≠ "impossible forever."

## Decisions
- **Close id:c563 — no viable batching lever exists.** Both sub-levers exhausted:
  1. "Skip no-op integrates" — lever does not exist (already closed by the `:940/953` early-return guards in the prior session; 100% of spawned integrators had genuine work).
  2. "Batching" — intra-repo infeasible (sequential cross-round dependency); cross-repo infeasible (reverses line-465 parallel latency fix, worsens conflict recovery, saves rounding-error sonnet tokens vs Opus-dominated spend).
- **Falsifiable re-open trigger:** re-open *only* if a future change makes multiple same-repo units co-ready in one dispatch wave (e.g. `id:fb75/6e9d` multi-same-repo-execute dispatch). Today's one-verdict-per-repo-per-round invariant makes this impossible.
- **Out of scope:** the parallel cross-repo integration design (`integrationChains` Map, `:465–471`), the sonnet pin (id:c3a6, saturated), integrator throughput / `produced` signal, integrate() early-return guards (already locked by the guard test).
- **Regression guard extended:** `tests/test_relay_integrator_noop_guard.sh` checks 7+8 now assert (7) no `batchIntegrate*` function present and (8) `integrationChains` per-repo Map and per-repo keying still intact — a future cross-repo batch collapser would trip both.

## Action items
- [x] Tick id:c563 `[x]` in `TODO.md` with close rationale + re-open trigger (flock'd `md-merge.py update-ids`). <!-- id:c563 -->
- [x] Tick id:c563 `[x]` in `ROADMAP.md` to same checkbox state (single-id-two-views D2; `md-merge.py update-ids`). <!-- id:c563 -->
- [x] Extend `tests/test_relay_integrator_noop_guard.sh`: updated header comment with batching-infeasibility evidence; added check (8) asserting cross-repo parallel-per-repo design intact (`integrationChains` keyed per repo; no global queue). `make test` 63/63 green. <!-- id:c563 -->
- [x] Write meeting note to `docs/meeting-notes/2026-06-17-0812-relay-integrator-batching-close.md`. <!-- id:c563 -->
