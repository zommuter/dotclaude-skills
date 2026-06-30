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

BUCKETING (id:e8ea): when f896's per-dispatch sig is present on the event, diverged rows are
automatically bucketed:
  RED      — same dispatch-sig AND same current-sig (input unchanged) but verdicts differ → real
             classifier disagreement, the only thing the gate cares about.
  EXPECTED — dispatch-sig absent OR dispatch-sig ≠ current-sig (state changed / pre-f896 event)
             → state-drift, auto-explained.
Fail-open: if current-sig cannot be computed → EXPECTED (never crash).

Usage:
    backtest-verdict.py [--json] [--append-log [<path>]]
Env overrides (for tests / non-default locations):
    RELAY_TOML         default ~/.config/relay/relay.toml
    RELAY_EVENTS       default ~/.config/relay/relay-events.jsonl
    SRC_DIR            default ~/src   (fallback repo root when a block has no '# path:')
    RELAY_SHADOW_LOG   default ~/.config/relay/shadow-log.jsonl  (for --append-log)
"""
import json, os, re, subprocess, sys, collections, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSIFY_REPO = os.path.join(HERE, "classify-repo.sh")
DISCOVER_SIG = os.path.join(HERE, "discover-sig.sh")
TOML = os.environ.get("RELAY_TOML", os.path.expanduser("~/.config/relay/relay.toml"))
EVENTS = os.environ.get("RELAY_EVENTS", os.path.expanduser("~/.config/relay/relay-events.jsonl"))
SRC_DIR = os.environ.get("SRC_DIR", os.path.expanduser("~/src"))
SHADOW_LOG = os.environ.get("RELAY_SHADOW_LOG", os.path.expanduser("~/.config/relay/shadow-log.jsonl"))


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
    """repo -> most-recent dispatch {mode, sig}. File is append-order; later wins."""
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
                last[o.get("repo")] = {"mode": o.get("mode"), "sig": o.get("sig", "")}
    return last


def current_sig(name, path):
    """Return the discover-sig.sh hash for (name, path). Empty string on any failure (fail-open)."""
    try:
        payload = json.dumps({"repos": [{"repo": name, "path": path}], "liveClaims": []})
        r = subprocess.run([DISCOVER_SIG], input=payload, capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            return ""
        for ln in r.stdout.splitlines():
            ln = ln.strip()
            if not ln:
                continue
            try:
                o = json.loads(ln)
                if o.get("repo") == name:
                    return o.get("sig", "")
            except Exception:
                continue
        return ""
    except Exception:
        return ""


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
    argv = sys.argv[1:]
    as_json = "--json" in argv
    do_append_log = "--append-log" in argv
    # --append-log [<path>]: optional path follows the flag; default is SHADOW_LOG env/default.
    log_path = SHADOW_LOG
    if do_append_log:
        idx = argv.index("--append-log")
        if idx + 1 < len(argv) and not argv[idx + 1].startswith("--"):
            log_path = argv[idx + 1]

    last = last_dispatch()
    rows, crashes = [], []
    dist = collections.Counter()
    agree = disagree = newrepo = red = expected = 0
    for name, path in own_repos():
        if not os.path.isdir(path):
            rows.append({"repo": name, "verdict": None, "last_mode": None, "note": "missing-path"})
            continue
        verdict, err = classify(name, path)
        if verdict is None:
            crashes.append((name, err))
            rows.append({"repo": name, "verdict": None, "last_mode": None, "note": err})
            continue
        dist[verdict] += 1
        prev_entry = last.get(name)
        if prev_entry is None:
            newrepo += 1; status = "new"; prev_mode = None
        else:
            prev_mode = prev_entry["mode"]
            if prev_mode == verdict:
                agree += 1; status = "agree"
            else:
                disagree += 1
                # e8ea bucketing: compare dispatch-sig to current-sig
                dispatch_sig = prev_entry.get("sig", "")
                if dispatch_sig:
                    cur_sig = current_sig(name, path)
                    if cur_sig and dispatch_sig == cur_sig:
                        # Input unchanged but verdicts differ → real disagreement
                        red += 1; status = "RED"
                    else:
                        # Input changed or current-sig unknown → state drift
                        expected += 1; status = "EXPECTED"
                else:
                    # Pre-f896 event (no sig recorded) → treat as state drift
                    expected += 1; status = "EXPECTED"
        rows.append({"repo": name, "verdict": verdict, "last_mode": prev_mode, "note": status})

    total = len(rows)
    summary = {
        "repos": total, "crashes": len(crashes),
        "agree": agree, "diverged": disagree, "red": red, "expected": expected, "new": newrepo,
        "distribution": dict(dist.most_common()),
    }

    if do_append_log:
        os.makedirs(os.path.dirname(os.path.abspath(log_path)), exist_ok=True)
        entry = dict(summary)
        entry["timestamp"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        with open(log_path, "a") as f:
            f.write(json.dumps(entry) + "\n")

    if as_json:
        print(json.dumps({"summary": summary, "rows": rows}, indent=2))
        return 0

    print(f"== backtest-verdict (id:5f93/e8ea) — classify-repo.sh vs last-dispatch over {total} own repos ==\n")
    print(f"{'repo':<26} {'live-verdict':<12} {'last-dispatch':<14} status")
    print("-" * 70)
    for r in sorted(rows, key=lambda x: x["repo"]):
        v = r["verdict"] or f"ERR({r['note']})"
        print(f"{r['repo']:<26} {v:<12} {str(r['last_mode'] or '-'):<14} {r['note']}")
    print(f"\nagree={agree}  diverged={disagree}  red={red}  expected={expected}  new={newrepo}  crashes={len(crashes)}")
    print(f"distribution: {dict(dist.most_common())}")
    if crashes:
        print("\nCRASHES (classifier must never crash — investigate before flip):")
        for n, e in crashes:
            print(f"  {n}: {e}")
    print("\nNOTE: RED=same-input-different-verdict (investigate); EXPECTED=state-drift/pre-f896 (auto-explained).")
    print("0 crashes is the hard gate; RED=0 is the quality gate (id:e8ea/a0b6).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
