#!/usr/bin/env python3
# relay-econ.py — relay-loop ECONOMICS: cost ($, cache-accurate) and TIME (standalone +
# parallelity-weighted) per work category, by model, and bucketed daily / hourly-of-day.
# Built on top of profile-run.sh --json (id:08a3) — reuses its per-agent `records`
# (phase, model, start/end, tokens_in/out, tokens_cache_read/tokens_cache_create).
#
# Three lenses on the same runs:
#   • COST   — USD at list rates, cache-accurate: in @full, cache_read @0.1x, cache_create
#              @1.25x, out @rate. Uses each agent's ACTUAL model (no phase→model guessing).
#   • TIME standalone        — Σ agent duration per category (raw agent-time share).
#   • TIME parallelity-weighted — per-category UNION of [start,end] intervals = the wall-clock
#              the category was actually active. A category that ran N-wide in parallel has a
#              footprint ≈ duration/N; a serial category (integrator, status tail) ≈ its full
#              duration. footprint/standalone = 1/mean-concurrency for that category.
#
# Usage: relay-econ.py [--limit N] [--json] [search-root ...]
#   --limit N   only the N most-recent relay runs (default: all retained)
#   --json      emit the aggregate object instead of the human report
# Stdlib-only (python3); pure read. RELAY_WF_SEARCH_ROOT honored (colon-separated globs).
import json, subprocess, glob, os, sys, datetime, collections

HERE = os.path.dirname(os.path.abspath(__file__))
PROFILE = os.path.join(HERE, "profile-run.sh")

# per-1M (input, output) USD list rates. Cache read = 0.1x input, cache create = 1.25x input.
RATE_PER_M = {"haiku": (1.0, 5.0), "sonnet": (3.0, 15.0), "opus": (5.0, 25.0),
              "fable": (10.0, 50.0), "mythos": (10.0, 50.0)}
def model_key(m):
    m = (m or "").lower()
    for k in RATE_PER_M:
        if k in m:
            return k
    return "sonnet"  # safe default

PHASE_CAT = {"execute": "work", "review": "work", "hard": "work", "integrate": "work",
             "handoff": "work", "discover": "scaffold", "quota": "scaffold",
             "status": "status", "other": "poll/other"}
CATS = ["work", "status", "scaffold", "poll/other"]

def agent_cost(r):
    ir, orr = RATE_PER_M[model_key(r.get("model"))]
    tin = r.get("tokens_in", 0) or 0
    tcr = r.get("tokens_cache_read", 0) or 0
    tcc = r.get("tokens_cache_create", 0) or 0
    tout = r.get("tokens_out", 0) or 0
    return (tin * ir + tcr * ir * 0.1 + tcc * ir * 1.25 + tout * orr) / 1e6

def union_ms(intervals):
    # intervals: list of (start_s, end_s) floats; return merged-union length in ms.
    if not intervals:
        return 0.0
    ivs = sorted(intervals)
    tot = 0.0
    cs, ce = ivs[0]
    for s, e in ivs[1:]:
        if s <= ce:
            ce = max(ce, e)
        else:
            tot += ce - cs
            cs, ce = s, e
    tot += ce - cs
    return tot * 1000.0

def discover_runs():
    roots = os.environ.get("RELAY_WF_SEARCH_ROOT")
    globs = roots.split(":") if roots else [os.path.expanduser("~/.claude/projects/*/*/subagents/workflows/wf_*")]
    out = []
    for g in globs:
        out.extend(glob.glob(g))
    return sorted(set(out))

def main():
    args = sys.argv[1:]
    limit = None
    as_json = False
    extra_roots = []
    i = 0
    while i < len(args):
        if args[i] == "--limit":
            limit = int(args[i + 1]); i += 2
        elif args[i] == "--json":
            as_json = True; i += 1
        else:
            extra_roots.append(args[i]); i += 1
    if extra_roots:
        os.environ["RELAY_WF_SEARCH_ROOT"] = ":".join(extra_roots)

    wfdirs = discover_runs()
    # sort newest-first by mtime, apply limit
    wfdirs.sort(key=lambda d: os.path.getmtime(d), reverse=True)
    if limit:
        wfdirs = wfdirs[:limit]

    cost = collections.defaultdict(collections.Counter)   # bucket -> cat -> $
    tstd = collections.defaultdict(collections.Counter)   # bucket -> cat -> ms (standalone)
    twall = collections.defaultdict(collections.Counter)  # bucket -> cat -> ms (union)
    cost_model = collections.Counter()
    tot_cost, tot_std, tot_wall = collections.Counter(), collections.Counter(), collections.Counter()
    span_total = 0.0
    nruns = 0

    for wf in wfdirs:
        try:
            d = json.loads(subprocess.run([PROFILE, "--json", wf], capture_output=True,
                                          text=True, timeout=120).stdout)
        except Exception:
            continue
        recs = d.get("records") or []
        bp = d.get("by_phase") or {}
        if not any(p in bp for p in ("discover", "status", "review", "hard", "execute", "integrate")):
            continue  # not a relay run
        nruns += 1
        span_total += d.get("span_ms", 0) or 0
        starts = [r["start"] for r in recs if r.get("start")]
        run_start = min(starts) if starts else os.path.getmtime(wf)
        dt = datetime.datetime.fromtimestamp(run_start)
        day, hod = dt.strftime("%Y-%m-%d"), f"{dt.hour:02d}"

        cat_intervals = collections.defaultdict(list)
        for r in recs:
            cat = PHASE_CAT.get(r.get("phase"), "poll/other")
            c = agent_cost(r)
            dur = r.get("duration_ms", 0) or 0
            for bkt in (("DAY", day), ("HOD", hod)):
                cost[bkt][cat] += c; tstd[bkt][cat] += dur
            tot_cost[cat] += c; tot_std[cat] += dur
            cost_model[model_key(r.get("model"))] += c
            if r.get("start") and r.get("end"):
                cat_intervals[cat].append((r["start"], r["end"]))
        # per-run union per category → wall-clock footprint
        for cat, ivs in cat_intervals.items():
            u = union_ms(ivs)
            twall[("DAY", day)][cat] += u; twall[("HOD", hod)][cat] += u; tot_wall[cat] += u

    agg = {
        "runs": nruns, "span_total_ms": span_total,
        "cost": {k: round(tot_cost[k], 4) for k in CATS},
        "cost_by_model": {m: round(cost_model[m], 4) for m in sorted(cost_model)},
        "time_standalone_ms": {k: round(tot_std[k]) for k in CATS},
        "time_wallclock_ms": {k: round(tot_wall[k]) for k in CATS},
        "daily": {}, "hourly": {},
    }
    days = sorted({b[1] for b in cost if b[0] == "DAY"})
    hods = sorted({b[1] for b in cost if b[0] == "HOD"})
    for day in days:
        agg["daily"][day] = {"cost": {k: round(cost[("DAY", day)][k], 2) for k in CATS},
                             "wall_ms": {k: round(twall[("DAY", day)][k]) for k in CATS}}
    for h in hods:
        agg["hourly"][h] = {"cost": {k: round(cost[("HOD", h)][k], 2) for k in CATS},
                            "wall_ms": {k: round(twall[("HOD", h)][k]) for k in CATS}}

    if as_json:
        print(json.dumps(agg)); return

    gc = sum(tot_cost.values()) or 1
    gs = sum(tot_std.values()) or 1
    gw = sum(tot_wall.values()) or 1
    def pct(v, g): return f"{100*v/g:5.1f}%"
    print(f"=== RELAY-LOOP ECONOMICS — {nruns} runs (cache-accurate list rates) ===\n")
    print(f"{'category':<11} {'COST $':>9} {'cost%':>6}   {'time(Σdur)':>11} {'t%':>6}   {'wall(par)':>10} {'w%':>6}  {'~conc':>6}")
    for k in CATS:
        std_s, wall_s = tot_std[k]/1000, tot_wall[k]/1000
        conc = (std_s / wall_s) if wall_s else 0
        print(f"{k:<11} ${tot_cost[k]:8.2f} {pct(tot_cost[k],gc)}   {std_s:9.0f}s {pct(tot_std[k],gs)}   {wall_s:8.0f}s {pct(tot_wall[k],gw)}  {conc:5.1f}x")
    print(f"{'TOTAL':<11} ${gc:8.2f}          {gs/1000:9.0f}s          {gw/1000:8.0f}s")
    print(f"\n  COST = USD (cache-accurate). time(Σdur) = summed agent durations (raw share).")
    print(f"  wall(par) = per-category union of intervals = wall-clock the category was active;")
    print(f"  ~conc = Σdur/wall = mean concurrency that category ran at (1x = serial).")
    print(f"\nCost by model: " + "  ".join(f"{m}=${cost_model[m]:.2f}({pct(cost_model[m],gc).strip()})" for m in ('opus','sonnet','haiku','fable') if cost_model.get(m)))
    print(f"\n=== DAILY (cost $ | wall-clock s, cols: {' '.join(CATS)}) ===")
    for day in days:
        c = cost[("DAY", day)]; w = twall[("DAY", day)]
        print(f"  {day}  $" + " $".join(f"{c[k]:6.2f}" for k in CATS) + f"   | " + " ".join(f"{w[k]/1000:5.0f}s" for k in CATS))
    print(f"\n=== BY HOUR-OF-DAY (cost $, cols: {' '.join(CATS)}) ===")
    for h in hods:
        c = cost[("HOD", h)]
        print(f"  {h}:00  $" + " $".join(f"{c[k]:6.2f}" for k in CATS) + f"   tot ${sum(c.values()):6.2f}")

if __name__ == "__main__":
    main()
