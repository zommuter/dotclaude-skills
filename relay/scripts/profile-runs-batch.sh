#!/usr/bin/env bash
# profile-runs-batch.sh — batch driver over profile-run.sh (id:08a3).
#
# Discovers relay Workflow runs on disk, profiles each via `profile-run.sh --json`,
# and folds them into cross-run statistics + a round-boundary findings section that
# directly tests the recurring "discovery was waiting on a single Haiku" claim.
#
# A "relay run" is a wf_* dir whose journal.jsonl mentions a relay discovery result
# (the `"verdict"` key) — this filters out unrelated workflows (code-review, etc.).
#
# Usage:
#   profile-runs-batch.sh [--limit N] [--json] [--cap N] [search-root ...]
#
#   --limit N   profile only the N most-recent relay runs (default: all retained)
#   --json      emit the aggregate as JSON (default: human-readable report)
#   --cap N     concurrency cap passed through to profile-run.sh (default: auto)
#   search-root override search roots (default: ~/.claude/projects/*/subagents/workflows)
#
# Stdlib-only (bash + python3), pure read. RELAY_WF_SEARCH_ROOT also honored.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="$HERE/profile-run.sh"
[[ -x "$PROFILE" ]] || { echo "profile-runs-batch.sh: profile-run.sh not found at $PROFILE" >&2; exit 1; }

LIMIT=0
JSON=0
CAP=""
ROOTS=()
want=""
for a in "$@"; do
  case "$a" in
    --json)      JSON=1 ;;
    --limit)     want="limit" ;;
    --limit=*)   LIMIT="${a#--limit=}" ;;
    --cap)       want="cap" ;;
    --cap=*)     CAP="${a#--cap=}" ;;
    *)
      if [[ "$want" == "limit" ]]; then LIMIT="$a"; want=""
      elif [[ "$want" == "cap" ]]; then CAP="$a"; want=""
      else ROOTS+=("$a"); fi
      ;;
  esac
done

if [[ ${#ROOTS[@]} -eq 0 ]]; then
  if [[ -n "${RELAY_WF_SEARCH_ROOT:-}" ]]; then
    IFS=':' read -r -a ROOTS <<< "$RELAY_WF_SEARCH_ROOT"
  else
    ROOTS=( "$HOME"/.claude/projects/*/*/subagents/workflows )
  fi
fi

# Discover relay wf dirs (journal mentions a discovery "verdict"), newest first by mtime.
mapfile -t RUNS < <(
  for root in "${ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    find "$root" -maxdepth 2 -name journal.jsonl 2>/dev/null
  done | while IFS= read -r j; do
    if grep -ql '"verdict"' "$j" 2>/dev/null; then
      printf '%s\t%s\n' "$(stat -c %Y "$j" 2>/dev/null || echo 0)" "$(dirname "$j")"
    fi
  done | sort -rn | cut -f2-
)

if [[ ${#RUNS[@]} -eq 0 ]]; then
  echo "profile-runs-batch.sh: no relay runs found under: ${ROOTS[*]}" >&2
  exit 1
fi
if [[ "$LIMIT" -gt 0 && "$LIMIT" -lt "${#RUNS[@]}" ]]; then
  RUNS=( "${RUNS[@]:0:$LIMIT}" )
fi

# Profile each run; collect its JSON (skip ones that fail to parse).
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
i=0
for d in "${RUNS[@]}"; do
  i=$((i+1))
  args=( "$d" --json )
  [[ -n "$CAP" ]] && args+=( --cap "$CAP" )
  if "$PROFILE" "${args[@]}" > "$TMP/run-$i.json" 2>/dev/null; then :; else rm -f "$TMP/run-$i.json"; fi
done

export BATCH_TMP="$TMP" BATCH_JSON="$JSON"
python3 - <<'PY'
import os, json, glob, collections, statistics

TMP = os.environ["BATCH_TMP"]
AS_JSON = os.environ["BATCH_JSON"] == "1"

runs = []
for f in sorted(glob.glob(os.path.join(TMP, "run-*.json")), key=lambda p: int(p.split("-")[-1].split(".")[0])):
    try:
        runs.append(json.load(open(f, encoding="utf-8")))
    except Exception:
        pass

if not runs:
    print("profile-runs-batch.sh: every run failed to profile", flush=True)
    raise SystemExit(1)

# --- cross-run aggregates -----------------------------------------------------
n_runs = len(runs)
tot_agents = sum(r["agents"] for r in runs)
spans = [r["span_ms"] for r in runs]
peaks = [r["peak_concurrency"] for r in runs]
atcap = [r["time_at_cap_pct"] for r in runs]

# round boundaries across ALL runs (the Haiku claim lives here)
boundaries = []
for r in runs:
    for rd in r["rounds"]:
        if rd["round"] == 0:
            continue  # first-round, no boundary
        boundaries.append(rd)

verdict_counts = collections.Counter(b["verdict"] for b in boundaries)

# the specific "single Haiku" signature: a boundary delayed with exactly ONE live
# occupant that is a Haiku. Distinguish "blocked" (>=cap, truly waiting) from
# "overlapped-not-capped" (slots free → NOT a logic block, just temporal overlap).
def is_haiku(m): return "haiku" in (m or "").lower()

single_haiku_blocked = []        # 1 occupant, haiku, queued-behind-cap (cap==1 edge)
single_haiku_overlap = []        # 1 occupant, haiku, slots free (NOT blocked)
single_occ_any = []              # exactly 1 occupant of any model
gappy = []                       # boundaries with a gap > 5s
for b in boundaries:
    occ = b["occupants"]
    if b["gap_ms"] > 5000:
        gappy.append(b)
    if b["occupants_at_start"] == 1:
        single_occ_any.append(b)
        m = occ[0]["model"] if occ else ""
        if is_haiku(m):
            (single_haiku_blocked if b["verdict"] == "queued-behind-cap" else single_haiku_overlap).append(b)

# token + duration by model across all runs
model_tok = collections.defaultdict(lambda: {"count": 0, "total_ms": 0, "tokens_in": 0, "tokens_out": 0})
phase_tok = collections.defaultdict(lambda: {"count": 0, "total_ms": 0, "tokens_in": 0, "tokens_out": 0})
for r in runs:
    for k, a in r["by_model"].items():
        t = model_tok[k]
        t["count"] += a["count"]; t["total_ms"] += a["total_ms"]
        t["tokens_in"] += a["tokens_in"]; t["tokens_out"] += a["tokens_out"]
    for k, a in r["by_phase"].items():
        t = phase_tok[k]
        t["count"] += a["count"]; t["total_ms"] += a["total_ms"]
        t["tokens_in"] += a["tokens_in"]; t["tokens_out"] += a["tokens_out"]

gap_ms = [b["gap_ms"] for b in boundaries]

agg = {
    "runs_profiled": n_runs,
    "total_agents": tot_agents,
    "span_ms": {"min": min(spans), "max": max(spans), "mean": int(statistics.mean(spans))},
    "peak_concurrency": {"min": min(peaks), "max": max(peaks), "mean": round(statistics.mean(peaks), 1)},
    "time_at_cap_pct": {"min": min(atcap), "max": max(atcap), "mean": round(statistics.mean(atcap), 1)},
    "round_boundaries": len(boundaries),
    "verdict_counts": dict(verdict_counts),
    "gap_ms": ({"min": min(gap_ms), "max": max(gap_ms), "mean": int(statistics.mean(gap_ms)),
                "median": int(statistics.median(gap_ms))} if gap_ms else {}),
    "single_occupant_boundaries": len(single_occ_any),
    "single_haiku_blocked": len(single_haiku_blocked),
    "single_haiku_overlap_not_blocked": len(single_haiku_overlap),
    "gappy_boundaries_over_5s": len(gappy),
    "by_model": dict(model_tok),
    "by_phase": dict(phase_tok),
}

if AS_JSON:
    print(json.dumps({"aggregate": agg, "runs": [
        {"wfdir": r["wfdir"], "agents": r["agents"], "span_ms": r["span_ms"],
         "peak": r["peak_concurrency"], "at_cap_pct": r["time_at_cap_pct"],
         "rounds": len(r["rounds"])} for r in runs]}, indent=2))
    raise SystemExit(0)

def ms(v): return f"{v/1000:.1f}s" if v < 60000 else f"{v/60000:.1f}m"

print(f"Relay batch profile — {n_runs} run(s), {tot_agents} agents total\n")
print(f"  span        : {ms(agg['span_ms']['min'])} … {ms(agg['span_ms']['max'])} (mean {ms(agg['span_ms']['mean'])})")
print(f"  peak concur : {peaks and min(peaks)} … {max(peaks)} (mean {agg['peak_concurrency']['mean']})")
print(f"  time at cap : {agg['time_at_cap_pct']['min']}% … {agg['time_at_cap_pct']['max']}% (mean {agg['time_at_cap_pct']['mean']}%)")

print(f"\nRound boundaries analysed: {len(boundaries)}")
for v, c in verdict_counts.most_common():
    print(f"  {v:<22} {c}")
if gap_ms:
    print(f"  gap before prelude: median {ms(agg['gap_ms']['median'])}, mean {ms(agg['gap_ms']['mean'])}, max {ms(agg['gap_ms']['max'])}")

print(f"\n>>> 'Single Haiku' claim test:")
print(f"  boundaries with exactly 1 live occupant : {len(single_occ_any)}")
print(f"  ...of those, a Haiku AND truly cap-blocked: {len(single_haiku_blocked)}   <-- the claimed failure")
print(f"  ...a Haiku but slots free (NOT a block)   : {len(single_haiku_overlap)}   <-- looks like waiting, isn't")
print(f"  boundaries with a real gap (>5s)          : {len(gappy)}")

print(f"\nPer-model totals (all runs):")
print(f"  {'model':<28} {'count':>6} {'total':>9} {'tok_in':>12} {'tok_out':>11}")
for k, a in sorted(model_tok.items(), key=lambda kv: -kv[1]["total_ms"]):
    print(f"  {k:<28} {a['count']:>6} {ms(a['total_ms']):>9} {a['tokens_in']:>12} {a['tokens_out']:>11}")

print(f"\nPer-phase totals (all runs):")
print(f"  {'phase':<12} {'count':>6} {'total':>9} {'tok_in':>12} {'tok_out':>11}")
for k, a in sorted(phase_tok.items(), key=lambda kv: -kv[1]["total_ms"]):
    print(f"  {k:<12} {a['count']:>6} {ms(a['total_ms']):>9} {a['tokens_in']:>12} {a['tokens_out']:>11}")
PY
