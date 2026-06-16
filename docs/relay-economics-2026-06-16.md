# Relay-loop economics & optimization roadmap — 2026-06-16

Session handover for the relay cost/time analysis. Tool: `relay/scripts/relay-econ.py`
(re-run anytime: `relay-econ.py` for all retained runs, `--limit N`, or `--json`).

## The three lenses (36 runs, cache-accurate list rates)

`relay-econ.py` decomposes every retained relay run by **work category** under three lenses.
They disagree — that is the whole point: each points at a different optimization target.

| Category | Cost $ | cost% | Time Σdur | t% | Wall-clock (parallelity-wtd) | w% | ~conc |
|---|---|---|---|---|---|---|---|
| work (execute/review/hard/integrate) | $772.57 | **70.9%** | 114,285s | 60.2% | 40,143s | **45.2%** | 2.8× |
| status (RELAY_STATUS writes) | $217.69 | 20.0% | 57,540s | 30.3% | 32,988s | **37.2%** | 1.7× |
| scaffold (discovery prelude + quota gate) | $93.37 | 8.6% | 16,841s | 8.9% | 14,556s | **16.4%** | 1.2× |
| poll/other (inject-take + misc) | $6.63 | 0.6% | 1,176s | 0.6% | 1,071s | 1.2% | 1.1× |
| **TOTAL** | **$1090** | | ~53 h | | ~24.7 h | | |

By model: Opus $821 (75%) · Sonnet $201 (18%) · Haiku $66 (6%) · Fable $1.63 (0.1%).

Definitions: **cost** = USD, cache-accurate — `tokens_in` @full, `cache_read` @0.1×,
`cache_create` @1.25×, `out` @rate, per each agent's *actual* model. **Time Σdur** = summed
agent durations. **Wall-clock (parallelity-weighted)** = per-category UNION of `[start,end]`
= the wall-clock that category was actually active; `~conc = Σdur/wall` = the mean concurrency
it ran at (1× = serial).

## What the lenses say

- **Dollars → cut Opus *work*** (71%). It's the actual work, so the lever is *don't dispatch
  un-doable HARD* (id:2d20, fixed) and *don't re-review needlessly* — not Haiku tuning.
- **Wall-clock (latency) → the serial-ish overhead.** status ran at only **1.7×** concurrency
  and scaffold at **1.2×** (near-serial), so they sit on the critical path: status is **20% of
  cost but 37% of wall-clock**; scaffold is **8.6% of cost but 16.4% of wall-clock**. Together
  the serial overhead is ~54% of wall-clock vs ~29% of cost.
- **Two corrections the cache-accurate tool surfaced:** (1) status is *pricier* than the naive
  token estimate because `cache_create` (1.25×, the per-write cache premium) is its biggest
  component — the writer re-sends the full status content per write. (2) The old **id:2d20
  spinning runs** inflated status badly (06-15 alone was $133 of status from hundreds of
  writes/run); post-id:2d20 this should fall — needs a re-measure.

## Optimization roadmap (prioritized; the "takeaways to act on")

1. **Coalesce RELAY_STATUS writes** (inbox `routed:3e5a`). Now justified on *two* axes: 20% of
   cost AND 37% of wall-clock (low-concurrency, on the critical path). Debounce/coalesce to ~1
   write/round; shrink the agent prompt (write via `relay-state-write.sh status-write` from a
   path, not by re-embedding full content each time). Est. ~10× token cut + a latency win.
2. **Speed the discovery prelude** (scaffold, conc 1.2× ≈ serial, 16% of wall-clock vs 8.6% of
   cost). The shards already parallelize (id:9ed4) but the once-per-round prelude is serial;
   investigate trimming its work or overlapping it with the prior round's drain.
3. **Gate the inject-take poll + drop to Haiku** (inbox `routed:26f0`). Negligible cost (0.6%)
   but agent-slot/visual noise (id:6e9d fires per lane-drain, mostly no-op Sonnet agents).
4. **Re-measure after a few post-id:2d20 runs** to confirm status cost/time share drops once
   the busy-loop is gone (the 36-run aggregate is contaminated by old spinning runs).

## Sharpen the analysis next session (improve the takeaways themselves)

- **Reconcile list-rate cost vs ACTUAL spend.** `relay-econ.py` uses list rates; `relay-burn.sh`
  tracks real `extra_usage.used_credits`. Cross-check: are we on a Max plan (sunk) or paying
  overage? The list-rate $ is an *upper bound* and the right lens for *relative* category share,
  not absolute billing.
- **Per-run trend, not just aggregate.** Add a `--trend` mode: status share over time, to *show*
  the id:2d20 effect rather than infer it.
- **Cost/latency Pareto + a one-line summary into RELAY_STATUS / statusline** (extends id:15bd /
  id:c8b6): surface "$X spent · Yh wall · Z% overhead" live.
- **Validate the parallelity model** against the profiler's `concurrency_curve` /
  `time_at_cap_pct` (independent check that union-of-intervals ≈ the curve's integral).

## Tracked as

dotclaude-skills TODO **id:1a75** (this roadmap) + inbox items `3e5a` (status-coalesce),
`26f0` (inject-gate), `01ac` (statusline ratios/runway). Tool: id:08a3 lineage
(`profile-run.sh` → `profile-runs-batch.sh` → `relay-econ.py`).
