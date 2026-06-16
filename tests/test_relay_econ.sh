#!/usr/bin/env bash
# roadmap:08a3 — relay-econ.py: cost ($, cache-accurate) + time (standalone + parallelity-weighted).
# Static structure checks + a hermetic --json smoke test against a synthetic profile-run stub.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ECON="$SRC_DIR/relay/scripts/relay-econ.py"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$ECON" ]] || fail "relay-econ.py not found/executable at $ECON"
python3 -c "import ast; ast.parse(open('$ECON').read())" || fail "relay-econ.py has a syntax error"
pass "relay-econ.py exists, executable, parses"

# Three lenses present
grep -q "cache_create" "$ECON" || fail "cost is not cache-accurate (no cache_create term)"
grep -q "union_ms" "$ECON" || fail "no per-category union (parallelity-weighted time) computation"
grep -qE "tcr \* ir \* 0\.1" "$ECON" || fail "cache_read not priced at 0.1x input"
grep -qE "tcc \* ir \* 1\.25" "$ECON" || fail "cache_create not priced at 1.25x input"
pass "three lenses: cache-accurate cost (read 0.1x / create 1.25x) + union wall-clock time"

# Rates match the documented list prices
grep -q '"opus": (5.0, 25.0)' "$ECON" || fail "opus rate not 5/25"
grep -q '"sonnet": (3.0, 15.0)' "$ECON" || fail "sonnet rate not 3/15"
grep -q '"haiku": (1.0, 5.0)' "$ECON" || fail "haiku rate not 1/5"
pass "model rates match list pricing (opus 5/25, sonnet 3/15, haiku 1/5)"

# Hermetic --json smoke test: stub profile-run.sh with one synthetic relay run.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/roots/wf_test123"
cat > "$TMP/bin/profile-run.sh" <<'STUB'
#!/usr/bin/env bash
# emits a fixed relay-shaped profile for any wfdir arg
cat <<'JSON'
{"span_ms":10000,"by_phase":{"status":{"count":1},"hard":{"count":1}},
 "records":[
   {"agentId":"a1","phase":"hard","model":"claude-opus-4-8","start":1000.0,"end":1005.0,"duration_ms":5000,"tokens_in":1000,"tokens_out":2000,"tokens_cache_read":0,"tokens_cache_create":0},
   {"agentId":"a2","phase":"status","model":"claude-haiku-4-5","start":1002.0,"end":1004.0,"duration_ms":2000,"tokens_in":100,"tokens_out":200,"tokens_cache_read":10000,"tokens_cache_create":4000}
 ]}
JSON
STUB
chmod +x "$TMP/bin/profile-run.sh"
# point relay-econ at our stub by copying it beside a stub econ? Simpler: symlink a fake scripts dir.
mkdir -p "$TMP/scripts"
cp "$ECON" "$TMP/scripts/relay-econ.py"
cp "$TMP/bin/profile-run.sh" "$TMP/scripts/profile-run.sh"
out="$(RELAY_WF_SEARCH_ROOT="$TMP/roots/wf_*" python3 "$TMP/scripts/relay-econ.py" --json 2>/dev/null)"
[[ -n "$out" ]] || fail "relay-econ --json produced no output on the stub run"
runs="$(echo "$out" | python3 -c 'import json,sys;print(json.load(sys.stdin)["runs"])')"
[[ "$runs" == "1" ]] || fail "expected 1 relay run from the stub, got $runs"
# hard cost = opus: 1000*5e-6 + 2000*25e-6 = 0.005 + 0.05 = 0.055
workcost="$(echo "$out" | python3 -c 'import json,sys;print(round(json.load(sys.stdin)["cost"]["work"],3))')"
[[ "$workcost" == "0.055" ]] || fail "work (opus) cost wrong: expected 0.055, got $workcost"
# status cost = haiku: 100*1e-6 + 10000*1e-6*0.1 + 4000*1e-6*1.25 + 200*5e-6 = 0.0001+0.001+0.005+0.001 = 0.0071
statuscost="$(echo "$out" | python3 -c 'import json,sys;print(round(json.load(sys.stdin)["cost"]["status"],4))')"
[[ "$statuscost" == "0.0071" ]] || fail "status (haiku, cache-accurate) cost wrong: expected 0.0071, got $statuscost"
pass "hermetic --json: cache-accurate cost math correct (opus work 0.055, haiku status 0.0071)"

echo "ALL PASS: relay-econ (id:08a3)"
