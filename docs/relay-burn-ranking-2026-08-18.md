# Burn measurement + per-phase ranking — id:4438 (measurement half of id:87f5)

Published 2026-08-18. Answers the pre-registered question (id:87f5, ticked 2026-08-18):
**rank `id:a955` vs `id:3ca7` by their target phase's share of parallelity-weighted
wall-clock** (`relay-econ.py`'s third lens), n = all retained runs, promote a lever iff
its phase clears ≥25% of that share, order = descending share.

## Instrumentation check (done before writing anything new)

- `relay/scripts/relay-burn.sh` emits **no per-phase attribution at all** — it is a
  whole-run **quota-utilization burnup** tool (%/h toward the 5h/7d/monthly caps,
  segmented at resets). It has no `phase`/`category` dimension to query. Confirmed by
  reading the script; not usable for this ranking.
- `relay/scripts/relay-econ.py` **does** emit per-phase attribution, but only at its
  4-bucket `CATEGORY` rollup (`work` = execute+review+hard+integrate+handoff,
  `status`, `scaffold` = discover+quota, `poll/other`) — see `PHASE_CAT` in the script.
  `id:a955`'s target (the **integrate** phase specifically) and `id:3ca7`'s target (the
  **round-tail wait**, which is not an agent phase at all) both sit *inside* or *outside*
  that rollup at a finer grain than `work`/`scaffold` distinguish. Per-phase attribution
  at the *raw*-phase grain (`execute`/`review`/`hard`/`integrate`/`handoff`/`discover`/
  `quota`/`status`/`other`, i.e. `profile-run.sh`'s own `PHASE_RULES` labels, one level
  below `relay-econ.py`'s `CATEGORY`) is what's needed to isolate `integrate`, so a small
  read-only analysis script was written reusing `relay-econ.py`'s own discovery +
  `profile-run.sh` plumbing (same union-of-intervals wall-clock method, same
  cache-accurate cost formula) — no relay script was modified, this is additive
  measurement only.

## Category-level (relay-econ.py --json, unmodified, n = 272 retained runs)

```
runs: 272   span_total: 892,319,950 ms (247.9 h)
category      cost $     cost%    wall_ms         wall%   ~conc
work        9,671.71     78.0%    670,915,167     64.2%    1.7x
status        369.03      3.0%    162,167,935     15.5%    1.0x
scaffold    1,795.47     14.5%    155,892,976     14.9%    1.9x
poll/other    561.92      4.5%     56,098,847      5.4%    1.8x
TOTAL      12,398.13              1,045,074,925
```

## Raw-phase breakdown (one level finer than relay-econ.py's CATEGORY; n = same 272 runs)

Percentages use relay-econ.py's own convention: each phase's share of the SUM across all
phases (the same denominator its `pct()` helper and the 06-16 economics report use).

```
phase         wall_h    wall%    cost $     cost%
execute        9.76      3.1%      201.98     1.6%
review        12.03      3.8%      521.38     4.2%
hard         145.76     46.0%    7,365.89    59.4%
integrate     44.64     14.1%    1,511.23    12.2%   <- id:a955's target
handoff        0.86      0.3%       72.21     0.6%
discover      38.94     12.3%    1,723.04    13.9%
quota          4.41      1.4%       72.43     0.6%
status        45.05     14.2%      369.03     3.0%
other         15.58      4.9%      561.92     4.5%
TOTAL        317.04             12,399.10
```

`integrate` (id:a955's target) is also 21.0% of the `work` category alone
(44.64h / 213.05h), for reference — still under 25% either denominator.

## Round-tail proxy (id:3ca7's target — not an agent phase, so not in the table above)

`id:3ca7` targets the wait between `await parallel(lanes)` finishing and the next
dispatch (plus the `[INTENSIVE]` serial tail) — time when **no agent is running at
all**. `relay-econ.py`/`profile-run.sh` have no instrumentation for this (there is no
agent record to attribute it to), so it was measured as an **idle-floor proxy**: per run,
`run_span (min-start to max-end of all agent intervals) − union(all agent intervals,
any phase)`. This is a lower bound on round-tail-and-similar dead time (it also picks up
any other unattributed wait, e.g. quota-cache misses between agents), reported as such.

```
run_span_total: 892,444,342 ms (247.9 h)
covered (any-agent union): 869,440,704 ms
idle floor: 23,003,638 ms = 6.39 h = 2.6% of total run span (2.0% of the raw-phase sum denominator above)
```

## Ranking: id:a955 vs id:3ca7

| Lever | Target phase | Share (raw-phase sum denom) | Clears ≥25%? |
|---|---|---|---|
| `id:a955` (mechanize the integrator) | `integrate` | **14.1%** | No |
| `id:3ca7` (shorten the round tail) | idle-floor proxy | **~2.0–2.6%** | No |

**Order (descending share): `id:a955` > `id:3ca7`.** `id:a955`'s target phase carries
roughly 5-7x `id:3ca7`'s idle-floor share, so if only one gets picked up next, it is
`id:a955`. **Neither clears the pre-registered ≥25% promote threshold** on this
measurement — the rule says promote iff ≥25%, so this measurement does not itself
promote either lever into dispatch; it only orders them per the gate's stated purpose
(id:a955/id:3ca7 stay `gated-on:4438`, now published, for the owner/reviewer to act on).
For context, `hard`-tier work generically (not a lever, just the biggest bucket) is
46.0% of wall-clock / 59.4% of cost — by far the largest single phase, but outside this
item's ordering question.

## Reconciliation against the banked 47.6% discover baseline (REQUIRED, not ignored)

The banked baseline (`id:9cb1`, 2026-06-18, `TODO.archive.md:192`): right after the
`c3a6` Opus-leak fix, discover-shard cost = **$86.12 = 47.6% of that session's run cost**
(n≈60 discover-shard agent invocations, cost-only, no wall-clock lens reported at the
time).

Current aggregate (n = 272 retained runs, 2026-06-12 through today):
- discover cost = **$1,723.04 = 13.9%** of total cost (vs banked 47.6%)
- discover wall-clock = **12.3%** of total wall-clock (no banked wall-clock comparator exists)

**Disagreement, in numbers: 47.6% → 13.9% cost share, a ~3.4x drop.** These are not
apples-to-apples runs (the banked figure is a narrow post-fix window; this one is the
full 272-run retained history spanning two months), but the direction and rough
magnitude are explained by levers that landed *after* 2026-06-18 and specifically target
discover cost: `id:c855` (push-seed discoverCache from work-agent returns) and the
signature-cache reuse (`id:c3a6`, discover fires only on repo-state churn instead of
every round). Both reduce how often the expensive discover-shard prompt actually runs.
The reconciliation is: **the two measurements do not contradict each other** — 47.6%
was correct for its (pre-lever) window, and the levers built on top of that finding
appear to have worked, cutting discover's share by roughly 3-4x in the aggregate since.
This is descriptive, not re-litigating `id:9cb1`'s finding or reopening `id:c855`.

## Method notes

- All figures use `relay-econ.py`'s cache-accurate cost formula (in @full rate,
  cache_read @0.1x, cache_create @1.25x, out @rate) and its parallelity-weighted
  wall-clock method (per-category/phase union of `[start,end]` intervals — a phase
  running N-wide in parallel counts its wall-clock footprint as ≈ duration/N, not
  duration).
- n = 272 is `relay-econ.py`'s own retained-run discovery (`~/.claude/projects/*/*/
  subagents/workflows/wf_*`, filtered to workflows with a recognizable relay
  `by_phase` — i.e. every wf-run the tool can identify as a relay run, no `--limit`
  applied), matching "all retained runs" from the pre-registration.
- Reproduce category-level: `relay/scripts/relay-econ.py --json`.
- Reproduce raw-phase + idle-floor: the one-off analysis script used for this report is
  not committed (read-only ad-hoc reuse of `relay-econ.py`'s own discovery +
  `profile-run.sh` plumbing at the raw-phase grain); anyone re-running this measurement
  should regenerate it from `profile-run.sh --json <wf>`'s `records[].phase` field
  the same way, or extend `relay-econ.py`'s `PHASE_CAT` if a permanent raw-phase report
  becomes worth maintaining.
