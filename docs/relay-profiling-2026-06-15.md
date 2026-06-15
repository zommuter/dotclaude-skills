# Relay run profiling — findings (2026-06-15)

Produced by `relay/scripts/profile-runs-batch.sh` (id:08a3), which batch-runs
`relay/scripts/profile-run.sh` (id:a59e) over every retained relay Workflow run and
folds the per-agent journals into cross-run statistics. Re-run any time:

```bash
relay/scripts/profile-runs-batch.sh            # human report over all retained runs
relay/scripts/profile-runs-batch.sh --json     # machine-readable aggregate
relay/scripts/profile-run.sh <runId|wf-id|dir> # drill into one run
```

**Corpus:** 31 relay runs, 1935 agents, spans 7.5m … 141.5m (mean 31.8m). This is the
full retained window (transcripts older than ~30 d had already been pruned at the time
of writing; `cleanupPeriodDays` has since been raised so future history accrues).

## 1. The "again, just one Haiku" suspicion is observation bias — settled

The recurring worry: *discovery seems to wait for a single Haiku to finish before the
next round.* Across **41 round boundaries in 31 runs**:

| measure | value |
|---|---|
| boundaries truly cap-blocked (`queued-behind-cap`) | **0** |
| boundaries with a gap > 5 s before the prelude | **0** |
| max gap before *any* discovery prelude | **4.1 s** |
| median / mean gap | **0.1 s / 0.8 s** |
| verdicts | 25 `clean-start`, 16 `overlapped-not-capped`, 0 blocked |
| boundaries with exactly 1 live Haiku occupant | 15 |
| …of those, actually blocking | **0** (all 15 had free slots → `overlapped-not-capped`) |

So the thing the eye catches — a lone Haiku still spinning when the next discovery
starts — happens (15×), but in **every** case there were free concurrency slots, so the
prelude was **not** waiting on it. The prelude launched within 0.1 s (median). There is
no logical await and no cap contention at round boundaries. **The suspicion does not
reproduce in the data.** (This is exactly the "looks like waiting, isn't" case the
profiler was built to disambiguate.)

## 2. Highest-impact (80-20) findings

**(a) The pool is under-saturated, not cap-bound.** Mean peak concurrency is **4.8**
against a ~6 cap; mean **time-at-cap is only 14.7%** (max 51.7%). For ~85% of wall-clock
there are idle slots. → The lever for faster runs is **more dispatchable work in
parallel, not a bigger cap.** This is direct, data-backed motivation for **id:ca87
(intra-repo parallelism)**: when only a few repos are needy (e.g. a meta `/relay` on the
relay repo alone) the pool starves. Raising `POOL_WIDTH` would do nothing here — there
aren't enough units to fill the existing slots.

**(b) Haiku overhead agents dominate the *count* (and the visual noise).** Haiku is
**46% of all agents (887/1935)**; `status` (732) + `quota` (288) = **1020 agents**, more
than half of everything. They're cheap per-token and off the critical path (cb50), but
they're the little agents that pop in and out of `/workflows` and *create* the "a Haiku
is always running" impression. → Two cheap consolidations worth a look: **one status
write per round** instead of several, and **longer quota-cache reuse** so fewer
quota-stop probes spawn. Neither changes wall-clock much (they don't block), but both
cut agent churn and the slot-flicker that feeds the illusion in §1.

**(c) Where wall-clock actually goes (agent-time, summed):** `status` 707m, `review`
579m, `hard` 470m, `execute` 326m, `integrate` 214m, `discover` 160m, `quota` 100m. By
model: Opus 1382m (apex review/hard — expected), Sonnet 724m, Haiku 539m. The big
*token* spend is Opus (6.0M in / 2.8M out) — inherent to the apex tier, not waste.
`integrate` at 214m over 265 agents is the serialized-merge tax; if intra-repo
parallelism (ca87) lands, keep integration single-owner so this stays bounded.

## Bottom line

- The Haiku-wait concern is **not real** — stop worrying about it; the profiler is the
  receipt. Re-run `profile-runs-batch.sh` after loop changes to confirm it stays that way.
- The real efficiency ceiling is **pool starvation** (idle slots), which **id:ca87**
  targets. That's the 80-20 next step.
- Optional cheap wins: consolidate status writes (1/round) and stretch the quota cache —
  fewer Haiku agents, less `/workflows` flicker.
