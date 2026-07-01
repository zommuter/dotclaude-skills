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
  3. The recurring-audit gate for open_hard_pool (id:9973) IS applied when the
     ROADMAP item carries '<!-- relay:recurring-audit -->' and substantive_unaudited
     is false. This relies on our (imperfect, bae5-gap) sub_unaudited value; rows
     where the gate fires are flagged 'reconstruction-gap:9973' if the verdict
     diverges toward the 'worse' direction.
  4. Historical diverges are CANDIDATE disagreements labelled "diverge", NOT
     confirmed RED (no dispatch-time input sig exists for most events). Contrast
     with the live backtest (id:5f93/e8ea) which buckets same-sig rows as RED.
  5. `git show C:<file>` is the ONLY access pattern used on target repos.
  6. Tag-time filter: ckpt tags created AFTER the event timestamp are excluded
     from the ancestor search (a future tag must not retroactively suppress
     substantive_unaudited for past events).
  7. Legacy lane vocabulary (pre-id:78ff): items tagged '[HARD — strong model]'
     or any HARD spelling that is NOT '[HARD — pool|meeting|hands]' are NOT counted
     in open_hard_pool (the classifier only recognises the post-id:78ff lanes).
     Rows where shard=hard but open_hard_pool=0 AND legacy HARD items exist are
     categorised 'reconstruction-gap:legacy-lane-vocab'. DO NOT remap legacy tags
     to current lanes to raise agreement — whether the classifier should recognise
     retired tags is an open design question for the human.

GUARDRAIL (id:0e57 fidelity pass): agreement-with-shard is NOT a quality target.
The backtest measures how faithfully we reconstruct the INPUT the shard saw, and
whether the classifier diverges from the shard. Divergence where the shard was
WRONG is the CORRECT outcome (classifier-better). The headline quality signal is
'candidate-classifier-worse' count (target: 0).

FOUR DIVERGE BUCKETS (non-agree rows):
  1. reconstruction-gap     — a signal we provably failed to reconstruct
                              (legacy-lane-vocab, tag-date unavailable, etc.)
  2. expected-policy-delta  — the classifier's LOWER-priority verdict is the correct
                              deterministic output of a decided mechanical policy rule
                              (id:4d8e cluster) the LLM shard never implemented; keyed to
                              the reconstructed precondition, so a script bug that emits a
                              verdict WITHOUT its precondition stays candidate-worse. See
                              match_policy_delta(). Triaged 2026-07-01 (DP7 flip gate).
  3. classifier-better      — classifier found higher-priority work than the shard
                              (shard missed it; divergence is correct behaviour)
  4. candidate-classifier-worse — classifier missed higher-priority work;
                              LOUDLY flagged — these are the only rows that matter

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

# Priority ranks mirror classify-verdict.sh's D3 cascade
VERDICT_RANK = {
    "blocked": 0,
    "execute": 1,
    "review":  2,
    "hard":    3,
    "handoff": 4,
    "human":   5,
    "idle":    6,
}

# Post-id:78ff pool-dispatchable HARD lane tags (the ONLY ones counted in open_hard_pool)
HARD_POOL_LANE = "[HARD — pool]"   # [HARD — pool] (em-dash)

# Human-gated lane markers (excluded from actionable counts)
HUMAN_GATES = ("[HARD — hands]", "[HARD — meeting]", "[HARD — decision gate]")


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
    """Return chronological dispatch events from EVENTS file."""
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
    events.sort(key=lambda x: x.get("ts", ""))
    if limit:
        events = events[:limit]
    return events


# ---------------------------------------------------------------------------
# Datetime helpers
# ---------------------------------------------------------------------------

def parse_iso(s):
    """Parse ISO8601 string to aware datetime. Returns None on failure."""
    if not s:
        return None
    try:
        s2 = s.strip()
        if s2.endswith("Z"):
            s2 = s2[:-1] + "+00:00"
        return datetime.datetime.fromisoformat(s2)
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Git read-only helpers (ALL use `git -C <path>` — NEVER checkout/switch/worktree-add)
# ---------------------------------------------------------------------------

def git_show_file(repo_path, commit, filepath):
    """Read file content at a specific commit via `git show`. Returns str or None."""
    try:
        r = subprocess.run(
            ["git", "-C", repo_path, "show", f"{commit}:{filepath}"],
            capture_output=True, text=True, timeout=30
        )
        return r.stdout if r.returncode == 0 else None
    except Exception:
        return None


def find_commit_before(repo_path, ts):
    """Latest first-parent commit strictly before the given ISO8601 timestamp."""
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


def get_ckpt_tags_with_dates(repo_path):
    """Return list of (tag_name, creation_iso_str) for relay/fable ckpt tags.

    Uses 'git tag --format=%(creatordate:iso-strict)' — works for both annotated
    (tagger date) and lightweight (commit date) tags.
    Returns [] on any error.
    """
    try:
        r = subprocess.run(
            ["git", "-C", repo_path, "tag", "-l",
             "--format=%(creatordate:iso-strict) %(refname:short)",
             "relay-ckpt-*", "fable-ckpt-*"],
            capture_output=True, text=True, timeout=30
        )
        if r.returncode != 0:
            return []
        result = []
        for line in r.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            # Format: "2026-06-12T18:17:40+02:00 tag-name"
            parts = line.split(" ", 1)
            if len(parts) == 2:
                result.append((parts[1].strip(), parts[0].strip()))
            else:
                # Fallback: no date available (lightweight tag with no date info)
                result.append((line, ""))
        return result
    except Exception:
        return []


def latest_ancestor_tag(repo_path, commit, tags_with_dates, event_ts_str):
    """Return the latest ckpt tag that (a) is an ancestor of commit AND
    (b) was created at or before event_ts_str.

    'Latest' = last in sorted order by tag name (names encode timestamps).
    Tags created AFTER event_ts_str are excluded (future tags must not retroactively
    suppress substantive_unaudited for past events — fidelity fix, id:0e57).

    tags_with_dates: [(name, creation_iso)] from get_ckpt_tags_with_dates().
    Returns (tag_name, had_date_filter_gap) where had_date_filter_gap=True if any
    tag's creation date was unavailable (and could not be time-filtered).
    """
    if not tags_with_dates:
        return None, False

    event_dt = parse_iso(event_ts_str)
    had_date_gap = False
    eligible = []
    for tag_name, tag_date_str in sorted(tags_with_dates):
        if not tag_date_str:
            # No date available: conservatively exclude (fail-safe: don't suppress
            # sub_unaudited with an unverifiable tag) but note the gap.
            had_date_gap = True
            continue
        tag_dt = parse_iso(tag_date_str)
        if tag_dt is None:
            had_date_gap = True
            continue
        if event_dt is not None and tag_dt > event_dt:
            # Tag created AFTER event — exclude (fidelity fix)
            continue
        eligible.append(tag_name)

    latest = None
    for tag in eligible:
        try:
            r = subprocess.run(
                ["git", "-C", repo_path, "merge-base", "--is-ancestor", tag, commit],
                capture_output=True, timeout=30
            )
            if r.returncode == 0:
                latest = tag
        except Exception:
            continue
    return latest, had_date_gap


def compute_substantive_unaudited(repo_path, commit, tags_with_dates, event_ts_str):
    """True iff there are non-checkpoint commits between the latest ancestor ckpt tag and commit.

    PARTIAL FIDELITY: uv.lock-only exemption (id:bae5) is NOT applied — a pure
    relock-only commit window may produce a false-true here.
    Tag-time filter IS applied: tags created after event_ts_str are excluded.
    Fail-open: any error → true.

    Returns (sub_unaudited: bool, had_date_filter_gap: bool)
    """
    ancestor_tag, had_date_gap = latest_ancestor_tag(
        repo_path, commit, tags_with_dates, event_ts_str
    )
    if ancestor_tag is None:
        try:
            r = subprocess.run(
                ["git", "-C", repo_path, "rev-list", "--count", commit],
                capture_output=True, text=True, timeout=30
            )
            count = int(r.stdout.strip()) if r.returncode == 0 else 1
            return count > 0, had_date_gap
        except Exception:
            return True, had_date_gap

    try:
        r = subprocess.run(
            ["git", "-C", repo_path, "log", f"{ancestor_tag}..{commit}", "--pretty=%s"],
            capture_output=True, text=True, timeout=30
        )
        if r.returncode != 0:
            return True, had_date_gap
        subjects = [l.strip() for l in r.stdout.splitlines() if l.strip()]
        non_ckpt = [s for s in subjects
                    if not re.match(r"(relay|fable): checkpoint", s)]
        return len(non_ckpt) > 0, had_date_gap
    except Exception:
        return True, had_date_gap


# ---------------------------------------------------------------------------
# Ledger-field derivation
# ---------------------------------------------------------------------------

def has_legacy_hard_items(content):
    """Return True if ROADMAP has open '- [ ]' items with a HARD marker that is NOT
    a post-id:78ff lane tag ([HARD — pool|meeting|hands]).

    Detects the pre-id:78ff vocabulary like '[HARD — strong model]', '[HARD]', etc.
    Used to classify 'reconstruction-gap:legacy-lane-vocab' rows.
    """
    for ln in content.splitlines():
        if not re.match(r"\s*- \[ \] ", ln):
            continue
        # Must have some [HARD ...] marker
        if not re.search(r"\[HARD", ln):
            continue
        # Exclude the current post-id:78ff lanes
        has_pool     = "[HARD — pool]" in ln
        has_meeting  = "[HARD — meeting]" in ln
        has_hands    = "[HARD — hands]" in ln
        has_decision = "[HARD — decision gate]" in ln
        if not (has_pool or has_meeting or has_hands or has_decision):
            return True
    return False


def roadmap_fields(content, sub_unaudited):
    """Derive (hasRoutine, roadmap_actionable_open, open_hard_pool, no_open_items,
              applied_9973_gate) from ROADMAP content at a historical commit.

    Mirrors the classify-repo.sh + gather-repo-state.sh derivation.
    id:9973 gate IS applied: a [HARD — pool] item with '<!-- relay:recurring-audit -->'
    is excluded from open_hard_pool when sub_unaudited is False.
    applied_9973_gate: True if any item was excluded by the id:9973 gate.
    """
    has_routine = False
    roadmap_actionable_open = 0
    open_hard_pool = 0
    any_open = False
    applied_9973_gate = False

    for ln in content.splitlines():
        if not re.match(r"\s*- \[ \] ", ln):
            continue
        any_open = True
        is_routine = "[ROUTINE]" in ln
        is_pool    = HARD_POOL_LANE in ln
        is_human   = any(h in ln for h in HUMAN_GATES) or "@manual" in ln

        if is_routine:
            has_routine = True
        if (is_routine or is_pool) and not is_human:
            roadmap_actionable_open += 1
        if is_pool and not is_human:
            # id:9973 gate: exclude recurring-audit items when nothing new to audit
            is_recurring = "relay:recurring-audit" in ln
            if is_recurring and not sub_unaudited:
                applied_9973_gate = True
                continue   # excluded this round
            open_hard_pool += 1

    return has_routine, roadmap_actionable_open, open_hard_pool, not any_open, applied_9973_gate


def unpromoted_counts(todo_content, roadmap_content):
    """Derive (promote, surface) by mirroring unpromoted-scan.sh's correlation logic."""
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
            continue
        token = m.group(1)
        if f"id:{token}" in roadmap_text:
            continue
        if re.search(r"\[ROUTINE\]|\[HARD — pool\]", ln):
            promote += 1
        else:
            surface += 1

    return promote, surface


# ---------------------------------------------------------------------------
# classify-verdict.sh runner
# ---------------------------------------------------------------------------

def run_classify_verdict(state_dict):
    """Pipe state JSON to classify-verdict.sh → (verdict, reason, evidence, None) or
    (None, None, None, error_str).
    """
    try:
        r = subprocess.run(
            [CLASSIFY_VERDICT],
            input=json.dumps(state_dict),
            capture_output=True, text=True, timeout=60
        )
        if r.returncode != 0:
            err = f"exit{r.returncode}:{(r.stderr or '').strip()[:70]}"
            return None, None, None, err
        result = json.loads(r.stdout.strip())
        return (result.get("verdict"),
                result.get("reason", ""),
                result.get("evidence", []),
                None)
    except Exception as e:
        return None, None, None, f"run-fail:{e}"


# ---------------------------------------------------------------------------
# Category derivation — 3 buckets
# ---------------------------------------------------------------------------

# Decided mechanical policy rules the LLM shard never implemented (id:4d8e cluster). When the
# classifier's LOWER-priority verdict is the CORRECT deterministic output of one of these rules
# for the reconstructed PRECONDITION, the divergence from the shard is an intended policy delta
# — not a regression. Triaged 2026-07-01 over the 109 candidate-worse rows: all resolved to one
# of these four (docs/meeting-notes/2026-06-30-1523 DP7 flip gate). Keyed to the precondition on
# purpose: a script bug that emits the verdict WITHOUT its precondition (e.g. 'human' while
# promote>0) does NOT match here and stays candidate-classifier-worse (LOUD) — the quality
# signal is preserved for genuine bugs; only "the mechanical rule fired correctly" is whitelisted.
def match_policy_delta(verdict, st):
    """Name the decided policy rule that explains this diverge, or None. `st` is the row's
    reconstructed state dict."""
    up = st.get("unpromoted", {})
    promote = up.get("promote", 0)
    surface = up.get("surface", 0)
    if verdict == "human" and promote == 0 and surface > 0:
        return "id:5eb3 surface-only→human"          # promote==0 ∧ surface>0: mechanical file, no apex dispatch
    if verdict == "handoff" and promote > 0:
        return "promote>0→handoff"                    # drained ROADMAP + promotable TODO backlog → populate via handoff
    if verdict == "review" and st.get("substantive_unaudited"):
        return "D3 substantive-unaudited→review"      # audit unaudited commits before fresh execution
    if verdict == "hard" and st.get("open_hard_pool", 0) > 0:
        return "open_hard_pool→hard"                  # open [HARD — pool] work, nothing higher pending
    return None


def derive_category(verdict, event_mode, reconstruction_gap_flags, reconstructed):
    """Derive diverge category from verdict, event_mode, gap flags, and reconstructed state.

    Returns one of:
      'reconstruction-gap'         — a provable reconstruction failure explains the diverge
      'expected-policy-delta'      — classifier's lower-priority verdict is the correct output
                                     of a decided mechanical policy rule the shard never had
      'classifier-better'          — classifier found higher-priority work (shard was wrong)
      'candidate-classifier-worse' — classifier may have missed higher-priority work (LOUD)
      'unknown'                    — equal rank or unmapped mode/verdict

    GUARDRAIL: gaps take precedence over 'classifier-better' when the shard's high-priority
    verdict (e.g. 'hard') is based on a signal we provably failed to reconstruct
    (legacy-lane-vocab). In that direction (shard=hard, classifier=review/handoff/idle)
    the classifier is NOT definitively better — the shard might have been right about a
    HARD item that uses a legacy tag we don't count. So if reconstruction_gap_flags
    includes 'legacy-lane-vocab' AND event_mode='hard', it's a gap, not classifier-better.
    """
    v_rank = VERDICT_RANK.get(verdict)
    m_rank = VERDICT_RANK.get(event_mode)

    if v_rank is None or m_rank is None:
        return "unknown"

    if v_rank > m_rank:
        # Classifier gave lower-priority verdict — shard found higher-priority work.
        # If reconstruction gaps could explain the miss → gap
        if reconstruction_gap_flags:
            return "reconstruction-gap"
        # If a decided mechanical policy rule (that the shard predated) explains the
        # lower-priority verdict for this reconstructed precondition → intended delta
        if match_policy_delta(verdict, reconstructed):
            return "expected-policy-delta"
        return "candidate-classifier-worse"

    if v_rank < m_rank:
        # Classifier found higher-priority work. Check if the shard's verdict was based
        # on a signal we provably couldn't reconstruct — in that case, we can't claim
        # the shard was WRONG (it might have had a legitimate reason we missed).
        if "legacy-lane-vocab" in reconstruction_gap_flags and event_mode == "hard":
            # Shard said 'hard' for a legacy HARD item we can't count — gap, not better
            return "reconstruction-gap"
        return "classifier-better"

    # Same rank but different verdict (shouldn't happen in current schema)
    return "unknown"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    argv = sys.argv[1:]

    as_json       = "--json"       in argv
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

    repo_paths = dict(own_repos())
    events = dispatch_events(since_date=since_date, limit=limit)

    rows    = []
    crashes = []
    dist_v  = collections.Counter()
    dist_m  = collections.Counter()
    agree_by_mode = collections.defaultdict(int)
    total_by_mode = collections.defaultdict(int)
    agree = diverge = new_count = 0
    cat_counts = collections.Counter()   # by diverge category

    skipped_repos  = set()
    skipped_count  = 0

    for event in events:
        repo = event.get("repo", "")
        ts   = event.get("ts",   "")
        mode = event.get("mode", "")

        if repo not in repo_paths or not os.path.isdir(repo_paths[repo]):
            skipped_count += 1
            skipped_repos.add(repo)
            continue

        path = repo_paths[repo]

        commit = find_commit_before(path, ts)
        if commit is None:
            new_count += 1
            rows.append({"repo": repo, "ts": ts, "event_mode": mode,
                         "verdict": None, "note": "new",
                         "classifier_reason": None, "classifier_evidence": [],
                         "reconstructed": {}, "category": None,
                         "reconstruction_gap_flags": []})
            continue

        # Reconstruct ledger state at commit C
        roadmap_content = git_show_file(path, commit, "ROADMAP.md") or ""
        todo_content    = git_show_file(path, commit, "TODO.md")    or ""

        tags_with_dates = get_ckpt_tags_with_dates(path)
        sub_unaudited, date_gap = compute_substantive_unaudited(path, commit, tags_with_dates, ts)

        has_routine, roadmap_actionable_open, open_hard_pool, no_open_items, applied_9973 = \
            roadmap_fields(roadmap_content, sub_unaudited)

        is_finished = bool(roadmap_content) and no_open_items and not sub_unaudited

        promote, surface = unpromoted_counts(todo_content, roadmap_content)

        state = {
            "hasRoutine":              has_routine,
            "substantive_unaudited":   sub_unaudited,
            "open_hard_pool":          open_hard_pool,
            "roadmap_actionable_open": roadmap_actionable_open,
            "unpromoted":              {"promote": promote, "surface": surface},
            "is_finished":             is_finished,
            "dirty":                   False,
            "dirty_lock_only":         False,
            "has_upstream":            False,
            "upstream_ahead_behind":   "",
        }

        verdict, reason, evidence, err = run_classify_verdict(state)
        if verdict is None:
            crashes.append((repo, ts, err))
            rows.append({"repo": repo, "ts": ts, "event_mode": mode,
                         "verdict": None, "note": err,
                         "classifier_reason": None, "classifier_evidence": [],
                         "reconstructed": state, "category": None,
                         "reconstruction_gap_flags": []})
            continue

        dist_v[verdict] += 1
        dist_m[mode]    += 1
        total_by_mode[mode] += 1

        # Determine gap flags before categorizing
        gap_flags = []
        if date_gap:
            gap_flags.append("tag-date-unavailable")
        # Legacy lane vocabulary: shard said 'hard' but open_hard_pool=0 AND
        # there ARE open [HARD — <non-lane>] items → legacy-vocab gap
        if (mode == "hard" and open_hard_pool == 0
                and has_legacy_hard_items(roadmap_content)):
            gap_flags.append("legacy-lane-vocab")
        # id:9973 gate was applied: our sub_unaudited drove an exclusion; sub_unaudited
        # itself has the bae5 gap (lock-only not applied) so the gate might be wrong
        if applied_9973:
            gap_flags.append("9973")
        # All-fields-empty reconstruction gap: if ALL classifier inputs are zero/false
        # AND the shard dispatched at a higher priority, our reconstruction is
        # suspiciously empty — likely the dispatch-time ckpt commit was missed by the
        # strict `--before` filter (the relay creates a ckpt commit at dispatch time
        # which may have the SAME timestamp as the event and be excluded). This is
        # a known commit-timestamp-boundary partial-fidelity gap.
        all_empty = (
            not has_routine
            and not sub_unaudited
            and open_hard_pool == 0
            and roadmap_actionable_open == 0
            and promote == 0
            and surface == 0
        )
        if all_empty and VERDICT_RANK.get(mode, 99) < VERDICT_RANK.get("idle", 6):
            gap_flags.append("all-fields-empty")

        recon = {
            "hasRoutine":              has_routine,
            "substantive_unaudited":   sub_unaudited,
            "open_hard_pool":          open_hard_pool,
            "roadmap_actionable_open": roadmap_actionable_open,
            "unpromoted":              {"promote": promote, "surface": surface},
        }

        policy_delta_rule = None
        if verdict == mode:
            agree += 1
            agree_by_mode[mode] += 1
            note = "agree"
            category = None
        else:
            diverge += 1
            note = "diverge"
            category = derive_category(verdict, mode, gap_flags, recon)
            if category == "expected-policy-delta":
                policy_delta_rule = match_policy_delta(verdict, recon)
            cat_counts[category] += 1

        rows.append({
            "repo":                   repo,
            "ts":                     ts,
            "event_mode":             mode,
            "verdict":                verdict,
            "note":                   note,
            "classifier_reason":      reason,
            "classifier_evidence":    evidence,
            "reconstructed":            recon,
            "category":                 category,
            "policy_delta_rule":        policy_delta_rule,
            "reconstruction_gap_flags": gap_flags,
        })

    if skipped_count:
        listed = ", ".join(sorted(skipped_repos)[:8])
        suffix = ", ..." if len(skipped_repos) > 8 else ""
        print(f"NOTE: {skipped_count} event(s) skipped (non-own or missing repos: "
              f"{listed}{suffix})", file=sys.stderr)

    per_mode = {}
    for m, cnt in total_by_mode.items():
        per_mode[m] = {
            "agree": agree_by_mode[m],
            "total": cnt,
            "rate":  round(agree_by_mode[m] / cnt, 3) if cnt > 0 else None,
        }

    # Candidate-classifier-worse rows for inline report (the rows that matter)
    ccw_rows = [r for r in rows if r.get("category") == "candidate-classifier-worse"]

    summary = {
        "events":                    len(rows),
        "crashes":                   len(crashes),
        "agree":                     agree,
        "diverge":                   diverge,
        "new":                       new_count,
        "skipped":                   skipped_count,
        "mode":                      "historical",
        "diverge_categories": {
            "candidate_classifier_worse": cat_counts.get("candidate-classifier-worse", 0),
            "expected_policy_delta":      cat_counts.get("expected-policy-delta", 0),
            "reconstruction_gap":         cat_counts.get("reconstruction-gap", 0),
            "classifier_better":          cat_counts.get("classifier-better", 0),
            "unknown":                    cat_counts.get("unknown", 0),
        },
        "policy_delta_rules": dict(collections.Counter(
            r["policy_delta_rule"] for r in rows if r.get("policy_delta_rule")
        ).most_common()),
        "matches_shard_NOT_a_goal":  agree,
        "distribution_verdict":      dict(dist_v.most_common()),
        "distribution_event_mode":   dict(dist_m.most_common()),
        "per_mode_agreement":        per_mode,
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
    dc = summary["diverge_categories"]
    ccw = dc["candidate_classifier_worse"]
    epd = dc["expected_policy_delta"]
    gap = dc["reconstruction_gap"]
    better = dc["classifier_better"]
    unk = dc["unknown"]

    print(f"== backtest-historical (id:0e57) — historical verdict replay over {total} events ==\n")
    print("GUARDRAIL: agreement-with-shard is NOT a quality target.")
    print("           The headline signal is candidate-classifier-worse (target: 0).\n")

    print("── DIVERGE CATEGORIES ─────────────────────────────────────────────────────")
    print(f"  candidate-classifier-worse : {ccw:4d}  ← QUALITY SIGNAL (target: 0)")
    print(f"  expected-policy-delta      : {epd:4d}  (decided rule the shard predated; intended)")
    print(f"  reconstruction-gap         : {gap:4d}  (provable reconstruction failure)")
    print(f"  classifier-better          : {better:4d}  (shard was wrong; correct outcome)")
    print(f"  unknown                    : {unk:4d}")
    print(f"  matches-shard (NOT a goal) : {agree:4d}  [of {total} processed events]\n")
    if summary["policy_delta_rules"]:
        print("── EXPECTED-POLICY-DELTA by rule ──────────────────────────────────────────")
        for rule, cnt in summary["policy_delta_rules"].items():
            print(f"  {cnt:4d}  {rule}")
        print()

    if ccw_rows:
        print("── CANDIDATE-CLASSIFIER-WORSE ROWS (investigate these) ────────────────────")
        for r in ccw_rows:
            print(f"  {r['repo']:<26} {r['ts']:<22} shard={r['event_mode']:<10} "
                  f"classifier={r['verdict']}")
            if r.get("classifier_reason"):
                print(f"    reason: {r['classifier_reason'][:100]}")
        print()

    print("PARTIAL FIDELITY: dirty/diverged=false assumed; uv.lock (bae5) + tag-time filter applied;")
    print("id:9973 gate applied (depends on bae5-imperfect sub_unaudited).")
    print("Legacy-lane-vocab: [HARD — strong model] etc. not mapped to [HARD — pool].\n")

    print(f"{'repo':<26} {'ts':<22} {'reconstructed':<14} {'event-mode':<12} status     category")
    print("-" * 100)
    for r in rows:
        v = r["verdict"] or f"ERR({str(r.get('note',''))[:18]})"
        cat = r.get("category") or "-"
        print(f"{r['repo']:<26} {r['ts']:<22} {v:<14} {str(r['event_mode'] or '-'):<12} "
              f"{r.get('note',''):<10} {cat}")

    print(f"\nagree={agree}  diverge={diverge}  new={new_count}  "
          f"crashes={len(crashes)}  skipped={skipped_count}")
    print("per-mode agreement rates (informational — NOT a quality target):")
    for m, s in sorted(per_mode.items()):
        pct = f"{s['rate']*100:.1f}%" if s["rate"] is not None else "N/A"
        print(f"  {m}: {s['agree']}/{s['total']} ({pct})")
    print(f"distribution (reconstructed verdicts): {dict(dist_v.most_common())}")
    print(f"distribution (event modes):            {dict(dist_m.most_common())}")
    if crashes:
        print(f"\nCRASHES (0 is the hard gate — investigate before trusting results):")
        for repo, ts, err in crashes:
            print(f"  {repo} @ {ts}: {err}")
    print("\nNOTE: 0 crashes is the hard gate. Candidate diverges are partial-fidelity gaps.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
