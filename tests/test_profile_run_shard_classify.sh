#!/usr/bin/env bash
# Defect-fix regression (no roadmap item — failures always count).
#
# Found 2026-06-18 while resolving id:9cb1: profile-run.sh's PHASE_RULES had a
# bare "rollup" needle in the `status` rule that matched the discover-shard
# prompt's "SKIPPED ROLLUP" instruction (id:be62), checked BEFORE the `discover`
# rule. Effect: ~94% of discovery cost was misfiled into the `status` bucket,
# corrupting relay-econ.py category attribution (and id:9cb1's own verification
# command). This test pins shards to `discover` and the real status-writer to
# `status`. Hermetic: synthetic wf_* dir under mktemp; never touches ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROF="$ROOT/relay/scripts/profile-run.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
[[ -x "$PROF" ]] || fail "profile-run.sh not found/executable at $PROF"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
WF="$TMP/roots/wf_deadbeef-shard"; mkdir -p "$WF"

mk_agent() {
  local id="$1" prompt="$2" model="$3"
  python3 - "$WF/agent-$id.jsonl" "$id" "$prompt" "$model" <<'PY'
import json, sys
f,aid,prompt,model = sys.argv[1:5]
lines = [
  {"agentId":aid,"type":"user","timestamp":"2026-06-17T12:00:00.000Z",
   "message":{"role":"user","content":prompt}},
  {"agentId":aid,"type":"assistant","timestamp":"2026-06-17T12:00:05.000Z",
   "message":{"role":"assistant","model":model,
              "usage":{"input_tokens":100,"output_tokens":200,
                       "cache_read_input_tokens":0,"cache_creation_input_tokens":0}}},
  {"agentId":aid,"type":"user","timestamp":"2026-06-17T12:00:10.000Z",
   "message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}},
]
with open(f,"w") as fh:
    for l in lines: fh.write(json.dumps(l)+"\n")
PY
}

# A real discover-shard prompt fragment, including the "SKIPPED ROLLUP" line.
mk_agent s1 "You are a discovery SHARD classifier for the relay autonomous pool. Classify EXACTLY the own repos in this list. SKIPPED ROLLUP (id:be62): populate skipped with every repo you classified idle." claude-sonnet-4-6
# The real status-writer (must still classify as status via "relay_status").
mk_agent w1 "Write the following content verbatim to RELAY_STATUS.md via relay-state-write.sh status-write." claude-haiku-4-5-20251001

{
  for a in s1 w1; do
    echo "{\"type\":\"started\",\"key\":\"k$a\",\"agentId\":\"$a\"}"
    echo "{\"type\":\"result\",\"key\":\"k$a\",\"agentId\":\"$a\",\"result\":\"runId=relay-20260617-1200\"}"
  done
} > "$WF/journal.jsonl"

J="$("$PROF" "$WF" --json)"
get() { echo "$J" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

[[ "$(get 'd["by_phase"].get("discover",{}).get("count",0)')" == "1" ]] \
  || fail "shard prompt with SKIPPED ROLLUP must classify as discover (got phases: $(get 'list(d["by_phase"].keys())'))"
pass "discover-shard prompt (SKIPPED ROLLUP) classifies as discover, not status"

[[ "$(get 'd["by_phase"].get("status",{}).get("count",0)')" == "1" ]] \
  || fail "status-writer (relay_status) must still classify as status"
pass "writeRelayStatus prompt still classifies as status"
