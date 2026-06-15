#!/usr/bin/env bash
# profile-run.sh — workflow profiler for the /relay loop (id:a59e).
#
# Parses a Workflow run's on-disk journal + per-agent transcript/meta files into
# per-agent records and emits real, observation-bias-free numbers:
#   (a) concurrency-over-time — how many agents are live at each instant, against
#       the harness cap min(16, cores-2);
#   (b) round-boundary analysis — the gap before each discovery prelude and which
#       agents (and models) occupy it, distinguishing a *logical block* from being
#       merely *queued behind the concurrency cap*;
#   (c) per-label / per-phase aggregates (count, total/avg duration, total tokens).
#
# This settles the recurring "I think a single Haiku was waited for before the
# next discovery round" suspicion with data instead of eyeballing /workflows.
#
# Usage:
#   profile-run.sh <runId | wf-id | wf-dir> [--json] [--cap N] [--samples N]
#
# Arg resolution (first match wins):
#   • a directory containing journal.jsonl                       → used directly
#   • a "wf_*" id                                                → found under search roots
#   • any other string treated as a runId substring             → journals grepped for it
#
# Search roots: $RELAY_WF_SEARCH_ROOT (colon-separated, for tests) else
#   ~/.claude/projects/*/subagents/workflows
#
# Stdlib-only (bash + python3); no deps, no network. Logs nothing — pure read.
set -euo pipefail

JSON=0
CAP=""
SAMPLES=24
ARG=""
for a in "$@"; do
  case "$a" in
    --json)        JSON=1 ;;
    --cap)         CAP="__NEXT__" ;;
    --samples)     SAMPLES="__NEXT__" ;;
    --cap=*)       CAP="${a#--cap=}" ;;
    --samples=*)   SAMPLES="${a#--samples=}" ;;
    *)
      if [[ "$CAP" == "__NEXT__" ]]; then CAP="$a"
      elif [[ "$SAMPLES" == "__NEXT__" ]]; then SAMPLES="$a"
      else ARG="$a"; fi
      ;;
  esac
done

[[ -n "$ARG" ]] || { echo "usage: profile-run.sh <runId|wf-id|wf-dir> [--json] [--cap N] [--samples N]" >&2; exit 2; }

# --- resolve the workflow directory ------------------------------------------
search_roots() {
  if [[ -n "${RELAY_WF_SEARCH_ROOT:-}" ]]; then
    printf '%s\n' "${RELAY_WF_SEARCH_ROOT//:/$'\n'}"
  else
    printf '%s\n' "$HOME"/.claude/projects/*/subagents/workflows
  fi
}

WFDIR=""
if [[ -d "$ARG" && -f "$ARG/journal.jsonl" ]]; then
  WFDIR="$ARG"
elif [[ "$ARG" == wf_* ]]; then
  while IFS= read -r root; do
    [[ -d "$root/$ARG" ]] && { WFDIR="$root/$ARG"; break; }
  done < <(search_roots)
fi
if [[ -z "$WFDIR" ]]; then
  # treat ARG as a runId substring: pick the most-recently-modified journal that mentions it
  newest=""; newest_mtime=0
  while IFS= read -r root; do
    [[ -d "$root" ]] || continue
    while IFS= read -r j; do
      [[ -f "$j" ]] || continue
      if grep -ql -- "$ARG" "$j" 2>/dev/null; then
        m=$(stat -c %Y "$j" 2>/dev/null || echo 0)
        if (( m > newest_mtime )); then newest_mtime=$m; newest="$(dirname "$j")"; fi
      fi
    done < <(find "$root" -maxdepth 2 -name journal.jsonl 2>/dev/null)
  done < <(search_roots)
  WFDIR="$newest"
fi

[[ -n "$WFDIR" && -f "$WFDIR/journal.jsonl" ]] || {
  echo "profile-run.sh: could not resolve a workflow dir for '$ARG'" >&2; exit 1; }

# --- concurrency cap ----------------------------------------------------------
if [[ -z "$CAP" ]]; then
  cores=$(nproc 2>/dev/null || echo 4)
  c=$(( cores - 2 )); (( c < 1 )) && c=1
  CAP=$(( c < 16 ? c : 16 ))
fi

export PROFILE_WFDIR="$WFDIR" PROFILE_JSON="$JSON" PROFILE_CAP="$CAP" PROFILE_SAMPLES="$SAMPLES"

python3 - <<'PY'
import os, sys, json, glob, datetime, collections

WFDIR   = os.environ["PROFILE_WFDIR"]
AS_JSON = os.environ["PROFILE_JSON"] == "1"
CAP     = int(os.environ["PROFILE_CAP"])
SAMPLES = max(2, int(os.environ["PROFILE_SAMPLES"]))

def parse_ts(s):
    if not s:
        return None
    s = s.strip()
    # normalise trailing Z and +hh:mm offsets for fromisoformat
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.datetime.fromisoformat(s)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt.timestamp()

# --- journal: agentId universe ------------------------------------------------
journal_agents = set()
with open(os.path.join(WFDIR, "journal.jsonl"), encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        aid = d.get("agentId")
        if aid:
            journal_agents.add(aid)

# --- phase classification from the agent's first user prompt ------------------
# The journal stores no label/phase, so this is a best-effort heuristic on the
# prompt text. Order matters: most-specific first.
PHASE_RULES = [
    ("quota",    ("quota-stop", "quota_stop", "--tier strong", "--tier sonnet")),
    ("status",   ("relay_status", "relay status.md", "write_status", "cross-repo rollup", "rollup")),
    ("discover", ("discover-prelude", "discover-repos", "discover_repos", "classify the", "classification =", "discovery shard", "verdict for each repo")),
    ("integrate",("--no-ff merge", "integrate", "ckpt-tag", "git-lock-push")),
    ("hard",     ("[hard", "hard — strong", "hard execute", "strong-execute")),
    ("review",   ("/relay review", "review.md", "audit", "test-integrity", "re-derive roadmap", "diff since last")),
    ("handoff",  ("handoff.md", "/relay handoff", "failing-test spec", "write docs")),
    ("execute",  ("/relay executor", "executor-contract", "[routine]", "routine item", "work the routine")),
]

def classify(prompt):
    p = (prompt or "").lower()
    for phase, needles in PHASE_RULES:
        for n in needles:
            if n in p:
                return phase
    return "other"

def first_line_label(prompt):
    if not prompt:
        return "(no prompt)"
    line = prompt.strip().splitlines()[0].strip()
    return (line[:70] + "…") if len(line) > 70 else line

def extract_prompt(first_obj):
    msg = first_obj.get("message", {}) if isinstance(first_obj, dict) else {}
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        parts = []
        for p in c:
            if isinstance(p, dict):
                if isinstance(p.get("text"), str):
                    parts.append(p["text"])
                elif isinstance(p.get("content"), str):
                    parts.append(p["content"])
            elif isinstance(p, str):
                parts.append(p)
        return "\n".join(parts)
    return ""

# --- per-agent records from agent-*.jsonl ------------------------------------
records = []
for path in sorted(glob.glob(os.path.join(WFDIR, "agent-*.jsonl"))):
    base = os.path.basename(path)
    aid = base[len("agent-"):-len(".jsonl")]
    first_obj = None
    last_ts = None
    first_ts = None
    model = None
    tok_in = tok_out = tok_cache_read = tok_cache_create = 0
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except json.JSONDecodeError:
                continue
            if first_obj is None:
                first_obj = o
            ts = parse_ts(o.get("timestamp"))
            if ts is not None:
                if first_ts is None:
                    first_ts = ts
                last_ts = ts
            if o.get("type") == "assistant":
                m = o.get("message", {})
                if model is None and m.get("model"):
                    model = m["model"]
                u = m.get("usage") or {}
                tok_in        += int(u.get("input_tokens", 0) or 0)
                tok_out       += int(u.get("output_tokens", 0) or 0)
                tok_cache_read   += int(u.get("cache_read_input_tokens", 0) or 0)
                tok_cache_create += int(u.get("cache_creation_input_tokens", 0) or 0)
    if first_ts is None:
        continue
    prompt = extract_prompt(first_obj)
    dur_ms = int(round((last_ts - first_ts) * 1000)) if last_ts is not None else 0
    records.append({
        "agentId": aid,
        "label": first_line_label(prompt),
        "phase": classify(prompt),
        "model": model or "unknown",
        "start": first_ts,
        "end": last_ts,
        "duration_ms": dur_ms,
        "tokens_in": tok_in,
        "tokens_out": tok_out,
        "tokens_cache_read": tok_cache_read,
        "tokens_cache_create": tok_cache_create,
        "in_journal": aid in journal_agents,
    })

records.sort(key=lambda r: r["start"])

if not records:
    msg = {"error": "no agent records found", "wfdir": WFDIR}
    print(json.dumps(msg) if AS_JSON else f"profile-run.sh: no parseable agent transcripts in {WFDIR}", file=sys.stderr)
    sys.exit(1)

t0 = records[0]["start"]
t_end = max(r["end"] for r in records)
span = t_end - t0

def rel(t):
    return round(t - t0, 3)

# --- (a) concurrency-over-time ------------------------------------------------
# Sweep start(+1)/end(-1) events. Also build a sampled curve for display.
events = []
for r in records:
    events.append((r["start"], 1))
    events.append((r["end"], -1))
events.sort(key=lambda e: (e[0], -e[1]))   # starts before ends at equal ts
cur = 0
peak = 0
curve_pts = []   # (rel_time, concurrency) right after each event
for t, delta in events:
    cur += delta
    peak = max(peak, cur)
    curve_pts.append((rel(t), cur))

def concurrency_at(t):
    """live agents strictly during instant t (started <= t < end)."""
    return sum(1 for r in records if r["start"] <= t < r["end"])

# sampled curve over the run span
samples = []
if span <= 0:
    samples = [(0.0, len(records))]
else:
    for i in range(SAMPLES + 1):
        t = t0 + span * i / SAMPLES
        samples.append((round(t - t0, 1), concurrency_at(t if i < SAMPLES else t_end - 1e-6)))

# fraction of the run spent at the cap
at_cap_intervals = 0.0
prev_t = None
prev_c = 0
for t, c in [(e[0], None) for e in []]:
    pass
# integrate time-at-cap from the event sweep
cur = 0
prev = t0
time_at_cap = 0.0
for t, delta in events:
    if cur >= CAP:
        time_at_cap += (t - prev)
    prev = t
    cur += delta

# --- (b) round-boundary analysis ----------------------------------------------
preludes = [r for r in records if r["phase"] == "discover"]
preludes.sort(key=lambda r: r["start"])
rounds = []
for idx, p in enumerate(preludes):
    # agents live the instant the prelude starts (excluding the prelude itself)
    occupants = [r for r in records
                 if r["agentId"] != p["agentId"]
                 and r["start"] <= p["start"] < r["end"]]
    occ_conc = len(occupants)
    # gap = time from the previous round's last *completion before this prelude*
    prev_ends = [r["end"] for r in records
                 if r["agentId"] != p["agentId"] and r["end"] <= p["start"]]
    last_completion = max(prev_ends) if prev_ends else None
    gap_ms = int(round((p["start"] - last_completion) * 1000)) if last_completion is not None else 0
    # classify: was the prelude blocked, or just queued behind the cap?
    if idx == 0:
        verdict = "first-round (no boundary)"
    elif occ_conc >= CAP:
        verdict = "queued-behind-cap"      # all slots full → scheduler delay, not logic
    elif occ_conc == 0:
        verdict = "clean-start"            # nothing live; gap (if any) is pure scheduling latency
    else:
        verdict = "overlapped-not-capped"  # some agents live but slots free → NOT blocked-on
    rounds.append({
        "round": idx,
        "prelude_agent": p["agentId"],
        "prelude_label": p["label"],
        "prelude_start_rel": rel(p["start"]),
        "gap_ms": gap_ms,
        "occupants_at_start": occ_conc,
        "cap": CAP,
        "verdict": verdict,
        "occupants": [
            {"agentId": o["agentId"], "model": o["model"], "phase": o["phase"], "label": o["label"]}
            for o in sorted(occupants, key=lambda r: r["start"])
        ],
    })

# --- (c) per-label / per-phase aggregates ------------------------------------
def aggregate(key):
    agg = collections.OrderedDict()
    for r in records:
        k = r[key]
        a = agg.setdefault(k, {"count": 0, "total_ms": 0, "tokens_in": 0, "tokens_out": 0})
        a["count"] += 1
        a["total_ms"] += r["duration_ms"]
        a["tokens_in"] += r["tokens_in"]
        a["tokens_out"] += r["tokens_out"]
    for k, a in agg.items():
        a["avg_ms"] = int(round(a["total_ms"] / a["count"])) if a["count"] else 0
    return agg

by_phase = aggregate("phase")
by_model = aggregate("model")

result = {
    "wfdir": WFDIR,
    "agents": len(records),
    "agents_in_journal": sum(1 for r in records if r["in_journal"]),
    "span_ms": int(round(span * 1000)),
    "cap": CAP,
    "peak_concurrency": peak,
    "time_at_cap_ms": int(round(time_at_cap * 1000)),
    "time_at_cap_pct": round(100 * time_at_cap / span, 1) if span > 0 else 0.0,
    "concurrency_curve": samples,
    "rounds": rounds,
    "by_phase": by_phase,
    "by_model": by_model,
    "records": records,
}

if AS_JSON:
    print(json.dumps(result, indent=2))
    sys.exit(0)

# --- human-readable report ----------------------------------------------------
def ms(v):
    return f"{v/1000:.1f}s" if v < 60000 else f"{v/60000:.1f}m"

print(f"Workflow profile — {os.path.basename(WFDIR)}")
print(f"  dir         : {WFDIR}")
print(f"  agents      : {result['agents']} ({result['agents_in_journal']} in journal)")
print(f"  span        : {ms(result['span_ms'])}")
print(f"  cap         : {CAP}  (harness min(16, cores-2))")
print(f"  peak concur : {peak}")
print(f"  time at cap : {ms(result['time_at_cap_ms'])} ({result['time_at_cap_pct']}% of span)")

print("\nConcurrency over time (rel-seconds → live agents):")
maxc = max((c for _, c in samples), default=1) or 1
for t, c in samples:
    bar = "█" * int(round(20 * c / max(maxc, CAP)))
    flag = "  <-- AT CAP" if c >= CAP else ""
    print(f"  +{t:>7.1f}s | {c:>2} {bar}{flag}")

print("\nRound-boundary analysis (gap before each discovery prelude):")
if not rounds:
    print("  (no discovery-prelude agents detected — phase heuristic found none)")
for rd in rounds:
    print(f"  round {rd['round']}: prelude {rd['prelude_agent']} @ +{rd['prelude_start_rel']}s")
    print(f"    gap before prelude : {ms(rd['gap_ms'])}")
    print(f"    live at start      : {rd['occupants_at_start']}/{rd['cap']}  → {rd['verdict']}")
    if rd["occupants"]:
        from collections import Counter
        mc = Counter(o["model"] for o in rd["occupants"])
        models = ", ".join(f"{m}×{n}" for m, n in mc.items())
        print(f"    occupant models    : {models}")

print("\nPer-phase aggregates:")
print(f"  {'phase':<11} {'count':>5} {'total':>8} {'avg':>8} {'tok_in':>10} {'tok_out':>9}")
for k, a in by_phase.items():
    print(f"  {k:<11} {a['count']:>5} {ms(a['total_ms']):>8} {ms(a['avg_ms']):>8} {a['tokens_in']:>10} {a['tokens_out']:>9}")

print("\nPer-model aggregates:")
print(f"  {'model':<28} {'count':>5} {'total':>8} {'tok_in':>10} {'tok_out':>9}")
for k, a in by_model.items():
    print(f"  {k:<28} {a['count']:>5} {ms(a['total_ms']):>8} {a['tokens_in']:>10} {a['tokens_out']:>9}")
PY
