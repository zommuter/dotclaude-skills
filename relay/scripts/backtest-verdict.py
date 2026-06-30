#!/usr/bin/env python3
"""backtest-verdict.py (id:5f93) — pre-flip validation gate for the deterministic classifier.

Replays `classify-repo.sh` over every relay.toml own repo's CURRENT state and compares each
verdict to that repo's MOST-RECENT logged dispatch verdict in relay-events.jsonl. Report-only
(exit 0), like relay-doctor.sh — it is the human-read gate before flipping discovery authority
from the LLM shard to the mechanical classifier (meeting 2026-06-30-1523, DP7).

FIDELITY NOTE (meeting DP7): a fully faithful HISTORICAL backtest would replay over the exact
git-reconstructed ledger state at each past dispatch, but the classifier's input also depends on
EPHEMERAL state that is NOT git-recoverable (substantive_unaudited / is_finished depend on the
working tree + live ckpt tags + worktrees + claims at that instant). So this tool does the
practical LIVE-state comparison: it answers "does the deterministic classifier agree with what
the loop actually dispatched most recently?" A disagreement may be a genuine divergence OR simply
mean the repo's state changed since that dispatch (work got done) — the report flags both and the
human triages. Pairs with the forward-shadow run (id:9d2b) which covers the other direction.

Usage:
    backtest-verdict.py [--json]
Env overrides (for tests / non-default locations):
    RELAY_TOML      default ~/.config/relay/relay.toml
    RELAY_EVENTS    default ~/.config/relay/relay-events.jsonl
    SRC_DIR         default ~/src   (fallback repo root when a block has no '# path:')
"""
import json, os, re, subprocess, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSIFY_REPO = os.path.join(HERE, "classify-repo.sh")
TOML = os.environ.get("RELAY_TOML", os.path.expanduser("~/.config/relay/relay.toml"))
EVENTS = os.environ.get("RELAY_EVENTS", os.path.expanduser("~/.config/relay/relay-events.jsonl"))
SRC_DIR = os.environ.get("SRC_DIR", os.path.expanduser("~/src"))


def own_repos():
    """[(name, path)] for every classification='own' block, honoring '# path:'."""
    out, name, path, cls = [], None, None, None
    def flush():
        if name and cls == "own":
            out.append((name, os.path.expanduser(path) if path else os.path.join(SRC_DIR, name)))
    if not os.path.isfile(TOML):
        return out
    with open(TOML) as f:
        for ln in f:
            s = ln.strip()
            m = re.match(r"\[repos\.([^\]]+)\]", s)
            if m:
                flush(); name, path, cls = m.group(1), None, None; continue
            if s.startswith("# path:"):
                path = s.split("# path:", 1)[1].strip()
            elif s.startswith("classification"):
                cls = s.split("=", 1)[1].strip().strip('"')
    flush()
    return out


def last_dispatch():
    """repo -> most-recent dispatch 'mode' (verdict). File is append-order; later wins."""
    last = {}
    if not os.path.isfile(EVENTS):
        return last
    with open(EVENTS) as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                o = json.loads(ln)
            except Exception:
                continue
            if o.get("kind") == "dispatch":
                last[o.get("repo")] = o.get("mode")
    return last


def classify(name, path):
    try:
        r = subprocess.run([CLASSIFY_REPO, "--repo", name, "--path", path],
                           capture_output=True, text=True, timeout=90)
    except Exception as e:
        return None, f"run-fail:{e}"
    if r.returncode != 0:
        return None, f"exit{r.returncode}:{(r.stderr or '').strip()[:70]}"
    try:
        return json.loads(r.stdout).get("verdict"), None
    except Exception as e:
        return None, f"bad-json:{e}"


def main():
    as_json = "--json" in sys.argv[1:]
    last = last_dispatch()
    rows, crashes = [], []
    dist = collections.Counter()
    agree = disagree = newrepo = 0
    for name, path in own_repos():
        if not os.path.isdir(path):
            rows.append({"repo": name, "verdict": None, "last": last.get(name), "note": "missing-path"})
            continue
        verdict, err = classify(name, path)
        if verdict is None:
            crashes.append((name, err))
            rows.append({"repo": name, "verdict": None, "last": last.get(name), "note": err})
            continue
        dist[verdict] += 1
        prev = last.get(name)
        if prev is None:
            newrepo += 1; status = "new"
        elif prev == verdict:
            agree += 1; status = "agree"
        else:
            disagree += 1; status = "diverged"
        rows.append({"repo": name, "verdict": verdict, "last": prev, "note": status})

    total = len(rows)
    summary = {
        "repos": total, "crashes": len(crashes),
        "agree": agree, "diverged": disagree, "new": newrepo,
        "distribution": dict(dist.most_common()),
    }
    if as_json:
        print(json.dumps({"summary": summary, "rows": rows}, indent=2))
        return 0

    print(f"== backtest-verdict (id:5f93) — classify-repo.sh vs last-dispatch over {total} own repos ==\n")
    print(f"{'repo':<26} {'live-verdict':<12} {'last-dispatch':<14} status")
    print("-" * 70)
    for r in sorted(rows, key=lambda x: x["repo"]):
        v = r["verdict"] or f"ERR({r['note']})"
        print(f"{r['repo']:<26} {v:<12} {str(r['last'] or '-'):<14} {r['note']}")
    print(f"\nagree={agree}  diverged={disagree}  new={newrepo}  crashes={len(crashes)}")
    print(f"distribution: {dict(dist.most_common())}")
    if crashes:
        print("\nCRASHES (classifier must never crash — investigate before flip):")
        for n, e in crashes:
            print(f"  {n}: {e}")
    print("\nNOTE: 'diverged' may be a genuine classifier divergence OR the repo's state changed "
          "since that dispatch — triage each before the flip (id:a0b6). 0 crashes is the hard gate.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
