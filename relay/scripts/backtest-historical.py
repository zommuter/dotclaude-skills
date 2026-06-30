#!/usr/bin/env python3
"""backtest-historical.py (id:0e57) — HISTORICAL replay mode for the relay shadow gate.

Iterates past dispatch events in relay-events.jsonl and, for each event,
reconstructs the repo's ledger state AT THE EVENT TIMESTAMP via `git show`
(read-only — NEVER checkout, switch, worktree-add, or write to any target repo),
runs classify-verdict.sh on the reconstructed state, and compares the verdict to
what the relay actually dispatched (the event's `mode` field).

PARTIAL-FIDELITY BOUNDARIES (per meeting 2026-06-30-1523 DP7):
  1. dirty=false, diverged=false always assumed:  a committed snapshot is clean by
     definition, and every row is a DISPATCH event — the relay demonstrably did NOT
     block these repos, so assuming not-dirty/not-diverged is SELF-CONSISTENT for
     this corpus. The `blocked` parity verdict (id:e424) is validated separately
     by its own unit test (test_classify_verdict_parity.sh), not by this backtest.
  2. uv.lock-only exemption (id:bae5) is NOT applied for substantive_unaudited:
     checking each commit's changed-file list at scale is prohibitive; a repo whose
     only unaudited commits are pure relocks may show substantive_unaudited=true
     here vs false live — a known false-diverge.
  3. The recurring-audit gate for open_hard_pool (id:9973) is NOT applied: it
     depends on substantive_unaudited in a loop and requires the relay.toml
     last_strong_ckpt field which is not part of the historical ledger snapshot.
  4. Historical diverges are CANDIDATE disagreements labelled "diverge", NOT
     confirmed RED (no dispatch-time input sig exists for most events). Contrast
     with the live backtest (id:5f93/e8ea) which buckets same-sig rows as RED.
  5. `git show C:<file>` is the ONLY access pattern used on target repos.

Usage:
    backtest-historical.py [--since YYYY-MM-DD] [--limit N] [--json] [--append-log [<path>]]

Env overrides (for tests / non-default locations):
    RELAY_TOML         default ~/.config/relay/relay.toml
    RELAY_EVENTS       default ~/.config/relay/relay-events.jsonl
    SRC_DIR            default ~/src   (fallback repo root when a block has no '# path:')
    RELAY_SHADOW_LOG   default ~/.config/relay/shadow-log.jsonl  (for --append-log)
"""
import json, os, re, subprocess, sys, collections, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSIFY_VERDICT = os.path.join(HERE, "classify-verdict.sh")
TOML   = os.environ.get("RELAY_TOML",     os.path.expanduser("~/.config/relay/relay.toml"))
EVENTS = os.environ.get("RELAY_EVENTS",   os.path.expanduser("~/.config/relay/relay-events.jsonl"))
SRC_DIR = os.environ.get("SRC_DIR",       os.path.expanduser("~/src"))
SHADOW_LOG = os.environ.get("RELAY_SHADOW_LOG",
                             os.path.expanduser("~/.config/relay/shadow-log.jsonl"))


# ---------------------------------------------------------------------------
# relay.toml parser — mirrors backtest-verdict.py's own_repos() exactly
# ---------------------------------------------------------------------------

def own_repos():
    """[(name, path)] for every classification='own' block, honoring '# path:'."""
    out, name, path, cls = [], None, None, None

    def flush():
        if name and cls == "own":
            resolved = os.path.expanduser(path) if path else os.path.join(SRC_DIR, name)
            out.append((name, resolved))

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


# ---------------------------------------------------------------------------
# Event reader
# ---------------------------------------------------------------------------

def dispatch_events(since_date=None, limit=None):
    """Return chronological dispatch events from EVENTS file.

    Filters by since_date (YYYY-MM-DD prefix match on ts) if given.
    Applies limit after filtering.
    """
    events = []
    if not os.path.isfile(EVENTS):
        return events
    with open(EVENTS) as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                o = json.loads(ln)
            except Exception:
                continue
            if o.get("kind") != "dispatch":
                continue
            ts = o.get("ts", "")
            if since_date and ts and ts[:10] < since_date:
                continue
            events.append(o)
    # relay-events.jsonl is append-order but may not be perfectly sorted across runs
    events.sort(key=lambda x: x.get("ts", ""))
    if limit:
        events = events[:limit]
    return events


# ---------------------------------------------------------------------------
# Git read-only helpers (ALL use `git -C <path>` — NEVER checkout/switch/worktree-add)
# ---------------------------------------------------------------------------

def git_show_file(repo_path, commit, filepath):
    """Read file content at a specific commit via `git show`. Returns str or None.

    This is the ONLY file-access pattern used on target repos. Zero working-tree impact.
    """
    try:
        r = subprocess.run(
            ["git", "-C", repo_path, "show", f"{commit}:{filepath}"],
            capture_output=True, text=True, timeout=30
        )
        return r.stdout if r.returncode == 0 else None
    except Exception:
        return None


def find_commit_before(repo_path, ts):
    """Latest first-parent commit strictly before the given ISO8601 timestamp.

    Returns commit SHA or None (repo younger than ts, or empty repo).
    """
    try:
        r = subprocess.run(
            ["git", "-C", repo_path, "rev-list", "-1", "--first-parent",
             f"--before={ts}", "HEAD"],
            capture_output=True, text=True, timeout=30
        )
        sha = r.stdout.strip()
        return sha if r.returncode == 0 and sha else None
    except Exception:
        return None


def get_ckpt_tags(repo_path):
    """Return list of relay-ckpt-* and fable-ckpt-* tag names in the repo."""
    try:
        r = subprocess.run(
            ["git", "-C", repo_path, "tag", "-l", "relay-ckpt-*", "fable-ckpt-*"],
            capture_output=True, text=True, timeout=30
        )
        return [t for t in r.stdout.splitlines() if t.strip()] if r.returncode == 0 else []
    except Exception:
        return []


def latest_ancestor_tag(repo_path, commit, tags):
    """Return the latest ckpt tag that is an ancestor of commit, or None.

    'Latest' = last in sorted order; ckpt tag names encode timestamps so sort = chronological.
    Uses `git merge-base --is-ancestor` (read-only).
    """
    if not tags:
        return None
    latest = None
    for tag in sorted(tags):
        try:
            r = subprocess.run(
                ["git", "-C", repo_path, "merge-base", "--is-ancestor", tag, commit],
                capture_output=True, timeout=30
            )
            if r.returncode == 0:
                latest = tag   # keep iterating to find the latest
        except Exception:
            continue
    return latest


def compute_substantive_unaudited(repo_path, commit, tags):
    """True iff there are non-checkpoint commits between the latest ancestor ckpt tag and commit.

    PARTIAL FIDELITY: uv.lock-only exemption (id:bae5) is NOT applied — a pure
    relock-only commit window may produce a false-true here. Fail-open: any error → true.

    Uses only: git tag, git merge-base --is-ancestor, git rev-list --count, git log.
    NEVER checkout, switch, or write anything.
    """
    ancestor_tag = latest_ancestor_tag(repo_path, commit, tags)
    if ancestor_tag is None:
        # No ckpt tag is an ancestor: treat ALL commits up to C as unaudited.
        try:
            r = subprocess.run(
                ["git", "-C", repo_path, "rev-list", "--count", commit],
                capture_output=True, text=True, timeout=30
            )
            return int(r.stdout.strip()) > 0 if r.returncode == 0 else True
        except Exception:
            return True  # fail-open

    # List commit subjects between ancestor_tag and commit
    try:
        r = subprocess.run(
            ["git", "-C", repo_path, "log", f"{ancestor_tag}..{commit}", "--pretty=%s"],
            capture_output=True, text=True, timeout=30
        )
        if r.returncode != 0:
            return True  # fail-open
        subjects = [l.strip() for l in r.stdout.splitlines() if l.strip()]
        # Exclude relay/fable checkpoint commits by subject (mirrors gather-repo-state.sh)
        non_ckpt = [s for s in subjects
                    if not re.match(r"(relay|fable): checkpoint", s)]
        return len(non_ckpt) > 0
    except Exception:
        return True  # fail-open


# ---------------------------------------------------------------------------
# Ledger-field derivation — mirrors classify-repo.sh Python inline exactly
# ---------------------------------------------------------------------------

HUMAN_GATES = ("[HARD — hands]", "[HARD — meeting]", "[HARD — decision gate]")


def roadmap_fields(content):
    """Derive (hasRoutine, roadmap_actionable_open, open_hard_pool, no_open_items) from
    ROADMAP content at a historical commit.

    Mirrors the classify-repo.sh derivation exactly.
    PARTIAL FIDELITY: the recurring-audit gate (id:9973) is NOT applied for open_hard_pool.
    """
    has_routine = False
    roadmap_actionable_open = 0
    open_hard_pool = 0
    any_open = False

    for ln in content.splitlines():
        if not re.match(r"\s*- \[ \] ", ln):
            continue
        any_open = True
        is_routine = "[ROUTINE]" in ln
        is_pool    = "[HARD — pool]" in ln
        is_human   = any(h in ln for h in HUMAN_GATES) or "@manual" in ln
        if is_routine:
            has_routine = True
        if (is_routine or is_pool) and not is_human:
            roadmap_actionable_open += 1
        if is_pool and not is_human:
            open_hard_pool += 1

    return has_routine, roadmap_actionable_open, open_hard_pool, not any_open


def unpromoted_counts(todo_content, roadmap_content):
    """Derive (promote, surface) by mirroring unpromoted-scan.sh's correlation logic.

    For each open `- [ ]` line in TODO with a `<!-- id:XXXX -->` token:
      - skip if the token appears anywhere in ROADMAP (twin exists)
      - skip lint-ok lines and <!-- ref:XXXX --> lines (matching unpromoted-scan.sh exemptions)
      - promote if line carries [ROUTINE] or [HARD — pool]
      - surface otherwise

    Lines with no id token are `untracked` in unpromoted-scan — omitted here
    (partial fidelity: cannot correlate without a token).
    """
    promote = surface = 0
    roadmap_text = roadmap_content or ""

    for ln in (todo_content or "").splitlines():
        if not re.match(r"- \[ \] ", ln):
            continue
        if "<!-- lint-ok:" in ln:
            continue
        if re.search(r"<!-- ref:[0-9a-f]{4} -->", ln):
            continue
        m = re.search(r"<!-- id:([0-9a-f]{4}) -->", ln)
        if not m:
            continue   # untracked — skip for historical fidelity
        token = m.group(1)
        if f"id:{token}" in roadmap_text:
            continue   # twin present in ROADMAP
        if re.search(r"\[ROUTINE\]|\[HARD — pool\]", ln):
            promote += 1
        else:
            surface += 1

    return promote, surface


# ---------------------------------------------------------------------------
# classify-verdict.sh runner
# ---------------------------------------------------------------------------

def run_classify_verdict(state_dict):
    """Pipe state JSON to classify-verdict.sh → (verdict_str, None) or (None, error_str)."""
    try:
        r = subprocess.run(
            [CLASSIFY_VERDICT],
            input=json.dumps(state_dict),
            capture_output=True, text=True, timeout=60
        )
        if r.returncode != 0:
            return None, f"exit{r.returncode}:{(r.stderr or '').strip()[:70]}"
        result = json.loads(r.stdout.strip())
        return result.get("verdict"), None
    except Exception as e:
        return None, f"run-fail:{e}"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    argv = sys.argv[1:]

    as_json      = "--json"       in argv
    do_append_log = "--append-log" in argv

    log_path = SHADOW_LOG
    if do_append_log:
        idx = argv.index("--append-log")
        if idx + 1 < len(argv) and not argv[idx + 1].startswith("--"):
            log_path = argv[idx + 1]

    since_date = None
    if "--since" in argv:
        idx = argv.index("--since")
        if idx + 1 < len(argv):
            since_date = argv[idx + 1]

    limit = None
    if "--limit" in argv:
        idx = argv.index("--limit")
        if idx + 1 < len(argv):
            try:
                limit = int(argv[idx + 1])
            except ValueError:
                pass

    # Build name→path index for own repos
    repo_paths = dict(own_repos())

    # Read events
    events = dispatch_events(since_date=since_date, limit=limit)

    rows    = []
    crashes = []
    dist_v  = collections.Counter()   # by reconstructed verdict V'
    dist_m  = collections.Counter()   # by event mode V
    agree_by_mode = collections.defaultdict(int)
    total_by_mode = collections.defaultdict(int)
    agree = diverge = new_count = 0

    skipped_repos  = set()
    skipped_count  = 0

    for event in events:
        repo = event.get("repo", "")
        ts   = event.get("ts",   "")
        mode = event.get("mode", "")

        # Skip non-own or missing repos (surface on stderr — never silently swallow)
        if repo not in repo_paths or not os.path.isdir(repo_paths[repo]):
            skipped_count += 1
            skipped_repos.add(repo)
            continue

        path = repo_paths[repo]

        # --- Step 2: find commit as-of the event timestamp --------------------
        commit = find_commit_before(path, ts)
        if commit is None:
            # Repo younger than event timestamp (or empty) — skip silently as 'new'
            new_count += 1
            rows.append({"repo": repo, "ts": ts, "event_mode": mode,
                         "verdict": None, "note": "new"})
            continue

        # --- Step 3: reconstruct classifier input at commit C ----------------
        roadmap_content = git_show_file(path, commit, "ROADMAP.md") or ""
        todo_content    = git_show_file(path, commit, "TODO.md")    or ""

        has_routine, roadmap_actionable_open, open_hard_pool, no_open_items = \
            roadmap_fields(roadmap_content)

        tags           = get_ckpt_tags(path)
        sub_unaudited  = compute_substantive_unaudited(path, commit, tags)

        # is_finished: ROADMAP present + no open items + nothing unaudited + clean (assumed)
        is_finished = bool(roadmap_content) and no_open_items and not sub_unaudited

        promote, surface = unpromoted_counts(todo_content, roadmap_content)

        # Build state dict.
        # PARTIAL FIDELITY (documented in module header):
        #   dirty=False, dirty_lock_only=False — committed snapshot is clean by definition.
        #   has_upstream=False, upstream_ahead_behind="" — diverged is always False.
        #   This is SELF-CONSISTENT: every row is a dispatch event, meaning the relay
        #   DID dispatch it, so the repo was demonstrably NOT blocked at that time.
        state = {
            "hasRoutine":            has_routine,
            "substantive_unaudited": sub_unaudited,
            "open_hard_pool":        open_hard_pool,
            "roadmap_actionable_open": roadmap_actionable_open,
            "unpromoted":            {"promote": promote, "surface": surface},
            "is_finished":           is_finished,
            "dirty":                 False,
            "dirty_lock_only":       False,
            "has_upstream":          False,
            "upstream_ahead_behind": "",
        }

        # --- Step 4: pipe to classify-verdict.sh → V' -----------------------
        verdict, err = run_classify_verdict(state)
        if verdict is None:
            crashes.append((repo, ts, err))
            rows.append({"repo": repo, "ts": ts, "event_mode": mode,
                         "verdict": None, "note": err})
            continue

        dist_v[verdict] += 1
        dist_m[mode]    += 1
        total_by_mode[mode] += 1

        # --- Step 5: compare V' to V (event mode) ----------------------------
        # Historical diverges are CANDIDATE disagreements ("diverge"), not confirmed RED,
        # because no dispatch-time input sig exists for most historical events.
        if verdict == mode:
            agree += 1
            agree_by_mode[mode] += 1
            note = "agree"
        else:
            diverge += 1
            note = "diverge"

        rows.append({"repo": repo, "ts": ts, "event_mode": mode,
                     "verdict": verdict, "note": note})

    # Surface skipped repos on stderr (never silently swallow — id:4e14)
    if skipped_count:
        listed = ", ".join(sorted(skipped_repos)[:8])
        suffix = ", ..." if len(skipped_repos) > 8 else ""
        print(f"NOTE: {skipped_count} event(s) skipped (non-own or missing repos: "
              f"{listed}{suffix})", file=sys.stderr)

    # Per-mode agreement rates
    per_mode = {}
    for m, cnt in total_by_mode.items():
        per_mode[m] = {
            "agree": agree_by_mode[m],
            "total": cnt,
            "rate":  round(agree_by_mode[m] / cnt, 3) if cnt > 0 else None,
        }

    summary = {
        "events":                   len(rows),
        "crashes":                  len(crashes),
        "agree":                    agree,
        "diverge":                  diverge,
        "new":                      new_count,
        "skipped":                  skipped_count,
        "mode":                     "historical",
        "distribution_verdict":     dict(dist_v.most_common()),
        "distribution_event_mode":  dict(dist_m.most_common()),
        "per_mode_agreement":       per_mode,
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

    total = len(rows)
    print(f"== backtest-historical (id:0e57) — historical verdict replay over {total} events ==\n")
    print("PARTIAL FIDELITY: dirty/diverged=false assumed; uv.lock + recurring-audit exemptions")
    print("omitted. Historical diverges = CANDIDATE disagreements (investigate), not confirmed RED.\n")
    print(f"{'repo':<26} {'ts':<22} {'reconstructed':<14} {'event-mode':<12} status")
    print("-" * 82)
    for r in rows:
        v = r["verdict"] or f"ERR({r['note'][:20]})"
        print(f"{r['repo']:<26} {r['ts']:<22} {v:<14} {str(r['event_mode'] or '-'):<12} {r['note']}")

    print(f"\nagree={agree}  diverge={diverge}  new={new_count}  "
          f"crashes={len(crashes)}  skipped={skipped_count}")
    print("per-mode agreement rates:")
    for m, s in sorted(per_mode.items()):
        pct = f"{s['rate']*100:.1f}%" if s["rate"] is not None else "N/A"
        print(f"  {m}: {s['agree']}/{s['total']} ({pct})")
    print(f"distribution (reconstructed verdicts): {dict(dist_v.most_common())}")
    print(f"distribution (event modes):            {dict(dist_m.most_common())}")
    if crashes:
        print(f"\nCRASHES (0 is the hard gate — investigate before trusting results):")
        for repo, ts, err in crashes:
            print(f"  {repo} @ {ts}: {err}")
    print("\nNOTE: 0 crashes is the hard gate. Candidate diverges are partial-fidelity gaps, "
          "not confirmed bugs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
