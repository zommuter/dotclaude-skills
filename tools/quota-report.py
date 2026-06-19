#!/usr/bin/env python3
"""quota-report.py — read the git-versioned quota JSONL and surface anomalies.

The companion reader for quota-sample.sh. Reports the 7-day (and Sonnet/Opus) usage
time series, segments at weekly resets, and FLAGS sudden jumps between consecutive
fresh samples — the signature of the 2026-06-18 accounting bug (60%→100% with no
active session). Stdlib only (repo convention: no deps).

Usage:
  quota-report.py [DATA.jsonl] [--jump PP] [--since ISO] [--bucket NAME] [--spark]
    DATA.jsonl   default ~/src/claude-diary/quota/quota-samples.jsonl
    --jump PP    flag deltas >= PP percentage points between consecutive samples (default 15)
    --since ISO  only consider samples at/after this ISO timestamp (e.g. 2026-06-18)
    --bucket     which utilization field to track (default seven_day)
    --spark      append a unicode sparkline of the tracked bucket per reset-window
"""
import argparse
import json
import os
import sys

SPARK = "▁▂▃▄▅▆▇█"


def load(path, since):
    rows = []
    with open(path) as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                d = json.loads(ln)
            except json.JSONDecodeError:
                continue
            if since and d.get("ts", "") < since:
                continue
            rows.append(d)
    rows.sort(key=lambda d: d.get("epoch", 0))
    return rows


def spark(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return ""
    lo, hi = min(vals), max(vals)
    rng = (hi - lo) or 1
    return "".join(SPARK[min(7, int((v - lo) / rng * 7))] for v in vals)


def main():
    ap = argparse.ArgumentParser()
    default = os.path.expanduser("~/src/claude-diary/quota/quota-samples.jsonl")
    ap.add_argument("data", nargs="?", default=default)
    ap.add_argument("--jump", type=float, default=15.0)
    ap.add_argument("--since", default="")
    ap.add_argument("--bucket", default="seven_day")
    ap.add_argument("--spark", action="store_true")
    a = ap.parse_args()

    if not os.path.exists(a.data):
        print(f"no data file at {a.data} (sampler hasn't run yet?)", file=sys.stderr)
        return 1
    rows = load(a.data, a.since)
    if not rows:
        print("no samples in range", file=sys.stderr)
        return 1

    b = a.bucket
    n = len(rows)
    first, last = rows[0]["ts"], rows[-1]["ts"]
    fresh = sum(1 for r in rows if r.get("source") == "fetch")
    print(f"{n} samples  {first} → {last}  ({fresh} fresh fetch / {n - fresh} cached)")

    # Segment at reset boundaries (resets_at change ⇒ a new weekly window opened).
    # The API jitters resets_at by sub-second amounts (…12:00:00.41 vs …11:59:59.43),
    # so key on the reset DATE only — real windows are 7 days apart, jitter is seconds.
    def reset_key(r):
        v = r.get("seven_day_resets_at")
        return v[:10] if v else None

    segs, cur, prev_reset = [], [], None
    for r in rows:
        rk = reset_key(r)
        if prev_reset is not None and rk != prev_reset:
            segs.append(cur); cur = []
        cur.append(r); prev_reset = rk
    if cur:
        segs.append(cur)

    print(f"\n== {b} per weekly window ==")
    for seg in segs:
        vals = [s.get(b) for s in seg if s.get(b) is not None]
        if not vals:
            continue
        reset = seg[-1].get("seven_day_resets_at") or "?"
        line = f"  window→reset {reset}: min={min(vals):.0f}% max={max(vals):.0f}% last={vals[-1]:.0f}% (n={len(seg)})"
        if a.spark:
            line += "  " + spark([s.get(b) for s in seg])
        print(line)

    # Jump detection between consecutive samples (only between fresh-or-known readings).
    print(f"\n== jumps ≥ {a.jump:g}pp in {b} ==")
    flagged = 0
    for p, c in zip(rows, rows[1:]):
        pv, cv = p.get(b), c.get(b)
        if pv is None or cv is None:
            continue
        # A reset (counter drops to ~0) is expected, not an anomaly.
        if cv + a.jump <= pv:
            continue
        d = cv - pv
        if d >= a.jump:
            mins = (c.get("epoch", 0) - p.get("epoch", 0)) / 60.0
            tag = "" if c.get("source") == "fetch" else "  [cached/stale — verify]"
            print(f"  {p['ts']} → {c['ts']}  {pv:.0f}%→{cv:.0f}%  (+{d:.0f}pp in {mins:.0f} min){tag}")
            flagged += 1
    if not flagged:
        print("  none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
