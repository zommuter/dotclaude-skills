#!/usr/bin/env bash
# relay-spawn-bench.sh — speedtest harness: host `claude -p` spawn vs the
# Workflow `agent()` spawn (id:dfb9).
#
# Three subcommands, each emitting ONE JSON line to stdout:
#   claude-p     [--n N] [--prompt TEXT]
#       Time N host `claude -p "<prompt>"` spawns. Emits:
#       {"mode":"claude-p","n":N,"median_ms":<num>,"p90_ms":<num>,"samples_ms":[...]}
#   agent-record [--from FILE]
#       Read profile-run.sh --json records (from FILE, or the newest workflow run
#       found via profile-run.sh's own search roots when FILE is omitted) and emit
#       the median agent() dispatch cost:
#       {"mode":"agent","n":<count>,"median_ms":<num>,"p90_ms":<num>,"samples_ms":[...]}
#       The agent() side is NEVER re-spawned here — only a Workflow can dispatch
#       agent(); its durations are already instrumented by profile-run.sh.
#   compare      [--from FILE] [--n N] [--prompt TEXT]
#       Emit both sides plus a ratio:
#       {"mode":"compare","claude_p_median_ms":..,"agent_median_ms":..,"ratio":..}
#
# Env: CLAUDE_BIN overrides the `claude` binary (default: claude). A missing or
# unrunnable claude binary MUST fail LOUDLY (nonzero exit) — never a silent 0
# (a silent-zero benchmark is worse than none).
#
# The REAL measurement is a live run (documented, not hermetic); this script's
# own test only proves the harness plumbing + output shape.
#
# Stdlib-only (bash + python3); details logged to ~/.claude/logs/relay-spawn-bench.log.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HOME/.claude/logs/relay-spawn-bench.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >>"$LOG" 2>/dev/null || true; }

CLAUDE_BIN="${CLAUDE_BIN:-claude}"

SUB="${1:-}"
if [[ -z "$SUB" ]]; then
  echo "usage: relay-spawn-bench.sh {claude-p|agent-record|compare} [--n N] [--prompt TEXT] [--from FILE]" >&2
  exit 2
fi
shift

N=5
PROMPT="ping"
FROM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --n)         N="${2:-}"; shift 2 ;;
    --n=*)       N="${1#--n=}"; shift ;;
    --prompt)    PROMPT="${2:-}"; shift 2 ;;
    --prompt=*)  PROMPT="${1#--prompt=}"; shift ;;
    --from)      FROM="${2:-}"; shift 2 ;;
    --from=*)    FROM="${1#--from=}"; shift ;;
    *) echo "relay-spawn-bench.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# stats_json: reads newline-separated ms samples on stdin, emits
# {"median_ms":..,"p90_ms":..,"samples_ms":[...]}
stats_json() {
  python3 -c '
import sys, json
vals = [float(l) for l in sys.stdin if l.strip()]
vals.sort()
n = len(vals)
def median():
    if n == 0: return None
    if n % 2: return vals[n // 2]
    return (vals[n // 2 - 1] + vals[n // 2]) / 2
def pct(p):
    if n == 0: return None
    idx = min(n - 1, int(round(p * (n - 1))))
    return vals[idx]
print(json.dumps({"median_ms": median(), "p90_ms": pct(0.9), "samples_ms": vals}))
'
}

# find_newest_wfdir: mirrors profile-run.sh's search-root convention to locate
# the most recently modified workflow run directory (contains journal.jsonl).
find_newest_wfdir() {
  local -a roots
  if [[ -n "${RELAY_WF_SEARCH_ROOT:-}" ]]; then
    IFS=':' read -r -a roots <<< "${RELAY_WF_SEARCH_ROOT}"
  else
    roots=( "$HOME"/.claude/projects/*/*/subagents/workflows )
  fi
  local newest="" newest_mtime=0 root j m
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r j; do
      [[ -f "$j" ]] || continue
      m=$(stat -c %Y "$j" 2>/dev/null || echo 0)
      if (( m > newest_mtime )); then newest_mtime=$m; newest="$(dirname "$j")"; fi
    done < <(find "$root" -maxdepth 2 -name journal.jsonl 2>/dev/null)
  done
  printf '%s' "$newest"
}

run_claude_p() {
  local n="$1" prompt="$2"
  if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
    echo "relay-spawn-bench.sh: claude binary not found/runnable: $CLAUDE_BIN" >&2
    log "claude-p FAIL: binary not found/runnable: $CLAUDE_BIN"
    return 1
  fi
  local -a samples=()
  local i t0 t1
  for (( i = 0; i < n; i++ )); do
    t0=$(date +%s%N)
    if ! "$CLAUDE_BIN" -p "$prompt" >/dev/null 2>>"$LOG"; then
      echo "relay-spawn-bench.sh: claude spawn failed (i=$i)" >&2
      log "claude-p FAIL: spawn failed at i=$i"
      return 1
    fi
    t1=$(date +%s%N)
    samples+=( "$(( (t1 - t0) / 1000000 ))" )
  done
  local stats
  stats="$(printf '%s\n' "${samples[@]}" | stats_json)"
  python3 -c '
import json, sys
s = json.loads(sys.argv[1])
n = int(sys.argv[2])
print(json.dumps({"mode": "claude-p", "n": n, "median_ms": s["median_ms"],
                   "p90_ms": s["p90_ms"], "samples_ms": s["samples_ms"]}))
' "$stats" "$n"
}

run_agent_record() {
  local from="$1"
  local records_json=""
  if [[ -n "$from" ]]; then
    if [[ ! -f "$from" ]]; then
      echo "relay-spawn-bench.sh: --from file not found: $from" >&2
      log "agent-record FAIL: --from file not found: $from"
      return 1
    fi
    records_json="$(cat "$from")"
  else
    local wfdir
    wfdir="$(find_newest_wfdir)"
    if [[ -z "$wfdir" ]]; then
      echo "relay-spawn-bench.sh: no profile-run.sh workflow runs found; pass --from FILE" >&2
      log "agent-record FAIL: no workflow runs found"
      return 1
    fi
    local profile_script="$HERE/profile-run.sh"
    if [[ ! -x "$profile_script" ]]; then
      echo "relay-spawn-bench.sh: profile-run.sh not found at $profile_script" >&2
      log "agent-record FAIL: profile-run.sh missing"
      return 1
    fi
    if ! records_json="$("$profile_script" "$wfdir" --json)"; then
      echo "relay-spawn-bench.sh: profile-run.sh failed for $wfdir" >&2
      log "agent-record FAIL: profile-run.sh failed for $wfdir"
      return 1
    fi
  fi

  local out
  out="$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
except Exception:
    print("ERR: invalid JSON", file=sys.stderr)
    sys.exit(1)
recs = data.get("records", [])
vals = []
for r in recs:
    v = r.get("dur_ms", r.get("duration_ms"))
    if v is not None:
        vals.append(float(v))
vals.sort()
n = len(vals)
if n == 0:
    print("ERR: no usable dur_ms/duration_ms records", file=sys.stderr)
    sys.exit(1)
def median():
    if n % 2: return vals[n // 2]
    return (vals[n // 2 - 1] + vals[n // 2]) / 2
def pct(p):
    idx = min(n - 1, int(round(p * (n - 1))))
    return vals[idx]
print(json.dumps({"mode": "agent", "n": n, "median_ms": median(),
                   "p90_ms": pct(0.9), "samples_ms": vals}))
' <<<"$records_json")"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "relay-spawn-bench.sh: agent-record: $out" >&2
    log "agent-record FAIL: $out"
    return 1
  fi
  printf '%s\n' "$out"
}

run_compare() {
  local n="$1" from="$2" prompt="$3"
  local cp aj
  cp="$(run_claude_p "$n" "$prompt")" || return 1
  aj="$(run_agent_record "$from")" || return 1
  python3 -c '
import json, sys
cp = json.loads(sys.argv[1])
aj = json.loads(sys.argv[2])
cpm = cp.get("median_ms")
am = aj.get("median_ms")
ratio = (cpm / am) if (am not in (None, 0)) else None
print(json.dumps({"mode": "compare", "claude_p_median_ms": cpm,
                   "agent_median_ms": am, "ratio": ratio}))
' "$cp" "$aj"
}

case "$SUB" in
  claude-p)     run_claude_p "$N" "$PROMPT" ;;
  agent-record) run_agent_record "$FROM" ;;
  compare)      run_compare "$N" "$FROM" "$PROMPT" ;;
  *)
    echo "relay-spawn-bench.sh: unknown subcommand: $SUB (want claude-p|agent-record|compare)" >&2
    exit 2
    ;;
esac
