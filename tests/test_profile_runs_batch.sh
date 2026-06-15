#!/usr/bin/env bash
# Batch driver over profile-run.sh (id:08a3). No roadmap item (TODO-filed, built on
# explicit request), so no `# roadmap:` header — failures always count.
#
# Hermetic: builds TWO synthetic relay wf_* dirs (journal mentions "verdict" so they
# qualify as relay runs) under mktemp, points the batch driver at them via
# RELAY_WF_SEARCH_ROOT, and asserts on the --json aggregate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BATCH="$ROOT/relay/scripts/profile-runs-batch.sh"
PROF="$ROOT/relay/scripts/profile-run.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$BATCH" ]] || fail "profile-runs-batch.sh not found/executable at $BATCH"
[[ -x "$PROF" ]]  || fail "profile-run.sh not found at $PROF"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOTS="$TMP/roots"

mk_agent() { # dir id prompt model start end assist
  local f="$1/agent-$2.jsonl"
  python3 - "$f" "$2" "$3" "$4" "$5" "$6" "$7" <<'PY'
import json,sys
f,aid,prompt,model,start,end,assist=sys.argv[1:8]
rows=[
 {"agentId":aid,"type":"user","timestamp":start,"message":{"role":"user","content":prompt}},
 {"agentId":aid,"type":"assistant","timestamp":assist,"message":{"role":"assistant","model":model,
   "usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}},
 {"agentId":aid,"type":"user","timestamp":end,"message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}},
]
open(f,"w").write("".join(json.dumps(r)+"\n" for r in rows))
PY
}

mk_run() { # wfdir base-iso-min  (two discovery preludes + one executor child)
  local wf="$1" b="$2"
  mkdir -p "$wf"
  mk_agent "$wf" d1 "discover-repos.sh classify the repos" claude-haiku-4-5-20251001 \
    "${b}:00.000Z" "${b}:10.000Z" "${b}:05.000Z"
  mk_agent "$wf" e1 "/relay executor work the routine item" claude-sonnet-4-6 \
    "${b}:05.000Z" "${b}:50.000Z" "${b}:30.000Z"
  mk_agent "$wf" d2 "discover-repos.sh classify the repos" claude-haiku-4-5-20251001 \
    "${b}:30.000Z" "${b}:40.000Z" "${b}:35.000Z"
  # journal MUST contain "verdict" to be recognised as a relay run
  {
    echo '{"type":"started","key":"kd1","agentId":"d1"}'
    echo '{"type":"result","key":"kd1","agentId":"d1","result":{"units":[{"repo":"x","verdict":"review"}]}}'
    for a in e1 d2; do
      echo "{\"type\":\"started\",\"key\":\"k$a\",\"agentId\":\"$a\"}"
      echo "{\"type\":\"result\",\"key\":\"k$a\",\"agentId\":\"$a\",\"result\":\"ok\"}"
    done
  } > "$wf/journal.jsonl"
}

mk_run "$ROOTS/proj/sess/subagents/workflows/wf_aaaa-001" "2026-06-13T12:00"
mk_run "$ROOTS/proj/sess/subagents/workflows/wf_bbbb-002" "2026-06-14T09:00"
# a NON-relay workflow (no "verdict") that must be ignored
mkdir -p "$ROOTS/proj/sess/subagents/workflows/wf_cccc-999"
mk_agent "$ROOTS/proj/sess/subagents/workflows/wf_cccc-999" z1 "code review diff" claude-opus-4-8 \
  "2026-06-12T08:00:00.000Z" "2026-06-12T08:01:00.000Z" "2026-06-12T08:00:30.000Z"
echo '{"type":"started","key":"kz1","agentId":"z1"}' > "$ROOTS/proj/sess/subagents/workflows/wf_cccc-999/journal.jsonl"

SR="$ROOTS/proj/sess/subagents/workflows"

# --- (1) JSON aggregate, relay-run filtering ---------------------------------
J="$(RELAY_WF_SEARCH_ROOT="$SR" "$BATCH" --json --cap 4)"
echo "$J" | python3 -c "import json,sys; json.load(sys.stdin)" || fail "non-JSON aggregate"
pass "batch driver emits valid JSON aggregate"

get() { echo "$J" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

[[ "$(get 'd["aggregate"]["runs_profiled"]')" == "2" ]] \
  || fail "expected 2 relay runs (non-relay wf ignored), got $(get 'd["aggregate"]["runs_profiled"]')"
pass "discovers exactly the 2 relay runs, ignores the non-relay workflow"

[[ "$(get 'd["aggregate"]["total_agents"]')" == "6" ]] \
  || fail "expected 6 agents total (3+3), got $(get 'd["aggregate"]["total_agents"]')"
pass "aggregates agent counts across runs (6 = 3+3)"

# 2 runs × 1 boundary each (round 1) = 2 boundaries; e1 live at d2.start, cap 4 → not blocked
[[ "$(get 'd["aggregate"]["round_boundaries"]')" == "2" ]] \
  || fail "expected 2 round boundaries, got $(get 'd["aggregate"]["round_boundaries"]')"
pass "counts round boundaries across runs (2)"

[[ "$(get 'd["aggregate"]["single_haiku_blocked"]')" == "0" ]] \
  || fail "no boundary should be cap-blocked under cap 4"
pass "single-Haiku-blocked = 0 under cap 4 (the claim-test metric)"

# --- (2) --limit honored -----------------------------------------------------
J1="$(RELAY_WF_SEARCH_ROOT="$SR" "$BATCH" --json --cap 4 --limit 1)"
[[ "$(echo "$J1" | python3 -c 'import json,sys;print(json.load(sys.stdin)["aggregate"]["runs_profiled"])')" == "1" ]] \
  || fail "--limit 1 should profile a single run"
pass "--limit N restricts to N most-recent runs"

# --- (3) human-readable mode ok ----------------------------------------------
RELAY_WF_SEARCH_ROOT="$SR" "$BATCH" --cap 4 >/dev/null || fail "human-readable batch mode exited non-zero"
pass "human-readable batch report renders without error"

# --- (4) no relay runs → non-zero --------------------------------------------
if RELAY_WF_SEARCH_ROOT="$TMP/empty" "$BATCH" --json >/dev/null 2>&1; then
  fail "expected non-zero when no relay runs found"
fi
pass "exits non-zero when no relay runs are found"

echo "ALL PASS: profile-runs-batch.sh"
