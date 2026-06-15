#!/usr/bin/env bash
# Workflow profiler for the /relay loop (id:a59e). No roadmap item (filed in
# TODO.md, built on explicit /relay executor a59e invocation), so no
# `# roadmap:` header — this test's failures always count.
#
# Hermetic: builds a synthetic wf_* dir (journal.jsonl + agent-*.jsonl with
# crafted timestamps/usage) under mktemp, runs profile-run.sh against it, and
# asserts on the --json output. Never touches ~/.claude or the network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROF="$ROOT/relay/scripts/profile-run.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$PROF" ]] || fail "profile-run.sh not found/executable at $PROF"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
WF="$TMP/roots/wf_deadbeef-000"
mkdir -p "$WF"

# --- helper: write one agent-*.jsonl with start/end + one assistant usage line
# args: id phase-prompt model start-iso end-iso assist-iso in-tok out-tok
mk_agent() {
  local id="$1" prompt="$2" model="$3" start="$4" end="$5" assist="$6" tin="$7" tout="$8"
  local f="$WF/agent-$id.jsonl"
  python3 - "$f" "$id" "$prompt" "$model" "$start" "$end" "$assist" "$tin" "$tout" <<'PY'
import json, sys
f,aid,prompt,model,start,end,assist,tin,tout = sys.argv[1:10]
lines = [
  {"agentId":aid,"type":"user","timestamp":start,
   "message":{"role":"user","content":prompt}},
  {"agentId":aid,"type":"assistant","timestamp":assist,
   "message":{"role":"assistant","model":model,
              "usage":{"input_tokens":int(tin),"output_tokens":int(tout),
                       "cache_read_input_tokens":0,"cache_creation_input_tokens":0}}},
  {"agentId":aid,"type":"user","timestamp":end,
   "message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}},
]
with open(f,"w") as fh:
    for l in lines: fh.write(json.dumps(l)+"\n")
PY
}

# round 0 prelude: t0..t10
mk_agent d1 "Run discover-repos.sh and classify the repos by verdict" claude-haiku-4-5-20251001 \
  "2026-06-13T12:00:00.000Z" "2026-06-13T12:00:10.000Z" "2026-06-13T12:00:05.000Z" 100 200
# executor child: t5..t60 (lives across the round boundary)
mk_agent e1 "/relay executor — work the routine item from ROADMAP" claude-sonnet-4-6 \
  "2026-06-13T12:00:05.000Z" "2026-06-13T12:01:00.000Z" "2026-06-13T12:00:30.000Z" 5000 9000
# round 1 prelude: t30..t40 (at its start, e1 is still live)
mk_agent d2 "Run discover-repos.sh and classify the repos by verdict" claude-haiku-4-5-20251001 \
  "2026-06-13T12:00:30.000Z" "2026-06-13T12:00:40.000Z" "2026-06-13T12:00:35.000Z" 120 220

# journal.jsonl: started/result per agent (no timestamps — like the real one)
{
  for a in d1 e1 d2; do
    echo "{\"type\":\"started\",\"key\":\"k$a\",\"agentId\":\"$a\"}"
    echo "{\"type\":\"result\",\"key\":\"k$a\",\"agentId\":\"$a\",\"result\":\"runId=relay-20260613-1200\"}"
  done
} > "$WF/journal.jsonl"

ROOTS="$TMP/roots"

# --- (1) directory arg + JSON shape ------------------------------------------
J="$("$PROF" "$WF" --json --cap 4)"
echo "$J" | python3 -c "import json,sys; json.load(sys.stdin)" || fail "non-JSON output for --json"
pass "profile-run.sh emits valid JSON for a directory arg"

get() { echo "$J" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

[[ "$(get 'd["agents"]')" == "3" ]]            || fail "expected 3 agents, got $(get 'd["agents"]')"
pass "counts all 3 agent transcripts"

[[ "$(get 'd["peak_concurrency"]')" == "2" ]]  || fail "expected peak concurrency 2, got $(get 'd["peak_concurrency"]')"
pass "peak concurrency = 2 (d1+e1 overlap)"

[[ "$(get 'd["cap"]')" == "4" ]]               || fail "--cap override not honored"
pass "--cap override honored"

# --- (2) round-boundary analysis ---------------------------------------------
[[ "$(get 'len(d["rounds"])')" == "2" ]]       || fail "expected 2 rounds, got $(get 'len(d["rounds"])')"
pass "detects 2 discovery preludes → 2 rounds"

# round 1: gap = d2.start(30s) - d1.end(10s) = 20000ms; e1 live at start → occupants 1
[[ "$(get 'd["rounds"][1]["gap_ms"]')" == "20000" ]] \
  || fail "round-1 gap_ms expected 20000, got $(get 'd["rounds"][1]["gap_ms"]')"
pass "round-1 gap_ms = 20000 (prelude2.start - prelude1.end)"

[[ "$(get 'd["rounds"][1]["occupants_at_start"]')" == "1" ]] \
  || fail "round-1 occupants expected 1 (e1 live), got $(get 'd["rounds"][1]["occupants_at_start"]')"
pass "round-1 sees 1 live occupant at prelude start"

# with cap 4, 1 occupant < cap → overlapped-not-capped (NOT blocked-on)
[[ "$(get 'd["rounds"][1]["verdict"]')" == "overlapped-not-capped" ]] \
  || fail "round-1 verdict expected overlapped-not-capped, got $(get 'd["rounds"][1]["verdict"]')"
pass "round-1 verdict = overlapped-not-capped under cap 4 (distinguishes from blocked)"

# --- (3) cap contention reclassifies the SAME boundary as queued-behind-cap --
J2="$("$PROF" "$WF" --json --cap 1)"
v2="$(echo "$J2" | python3 -c "import json,sys; print(json.load(sys.stdin)['rounds'][1]['verdict'])")"
[[ "$v2" == "queued-behind-cap" ]] \
  || fail "with cap 1 the same boundary should read queued-behind-cap, got $v2"
pass "same boundary under cap 1 → queued-behind-cap (the Haiku-question distinction)"

# --- (4) per-phase + per-model aggregates ------------------------------------
[[ "$(get 'd["by_phase"]["discover"]["count"]')" == "2" ]] || fail "discover phase count != 2"
[[ "$(get 'd["by_phase"]["execute"]["count"]')" == "1" ]]  || fail "execute phase count != 1"
pass "per-phase aggregates classify 2 discover + 1 execute"

[[ "$(get 'd["by_model"]["claude-sonnet-4-6"]["tokens_out"]')" == "9000" ]] \
  || fail "sonnet tokens_out aggregate wrong"
pass "per-model token aggregates sum usage correctly"

# --- (5) runId substring + wf-id resolution against search root --------------
J3="$(RELAY_WF_SEARCH_ROOT="$ROOTS" "$PROF" relay-20260613-1200 --json --cap 4)"
[[ "$(echo "$J3" | python3 -c 'import json,sys;print(json.load(sys.stdin)["agents"])')" == "3" ]] \
  || fail "runId substring resolution failed"
pass "resolves a run by runId substring via RELAY_WF_SEARCH_ROOT"

J4="$(RELAY_WF_SEARCH_ROOT="$ROOTS" "$PROF" wf_deadbeef-000 --json --cap 4)"
[[ "$(echo "$J4" | python3 -c 'import json,sys;print(json.load(sys.stdin)["agents"])')" == "3" ]] \
  || fail "wf-id resolution failed"
pass "resolves a run by wf-id via RELAY_WF_SEARCH_ROOT"

# --- (6) human-readable mode runs without error ------------------------------
"$PROF" "$WF" --cap 4 >/dev/null || fail "human-readable mode exited non-zero"
pass "human-readable report renders without error"

# --- (7) bad arg exits non-zero ----------------------------------------------
if "$PROF" /no/such/run --json >/dev/null 2>&1; then
  fail "expected non-zero exit for an unresolvable arg"
fi
pass "unresolvable arg exits non-zero"

echo "ALL PASS: profile-run.sh"
