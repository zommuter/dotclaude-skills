#!/usr/bin/env bash
# roadmap:9934 — quota-stop.sh: tier-aware quota threshold check

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/fables-turn/scripts/quota-stop.sh"
TMPDIR_T="$(mktemp -d)"
CACHE="$TMPDIR_T/cache.json"
trap 'rm -rf "$TMPDIR_T"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# run_expect DESC EXPECTED_RC [script args...]
# Sets USAGE_CACHE to $CACHE before running.
run_expect() {
  local desc="$1"; local expected="$2"; shift 2
  local rc
  USAGE_CACHE="$CACHE" "$SCRIPT" "$@" && rc=0 || rc=$?
  if [[ "$rc" -eq "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc (expected exit $expected, got $rc)"
  fi
}

# Helper: write cache JSON with given utilization values
make_cache() {
  local fh="$1" sd="$2" sds="$3"
  cat > "$CACHE" <<JSON
{
  "five_hour":        { "utilization": $fh,  "resets_at": "" },
  "seven_day":        { "utilization": $sd,  "resets_at": "" },
  "seven_day_sonnet": { "utilization": $sds, "resets_at": "" }
}
JSON
}

# ── Missing / stale cache ──────────────────────────────────────────────────────

rm -f "$CACHE"
run_expect "missing cache → exit 2" 2 --tier sonnet

make_cache 0.50 0.50 0.50
touch -d "11 minutes ago" "$CACHE"
run_expect "stale cache (>10 min) → exit 2" 2 --tier sonnet
# Restore fresh mtime for subsequent tests
touch "$CACHE"

# ── Missing key in JSON ────────────────────────────────────────────────────────

echo '{ "five_hour": { "utilization": 0.50 }, "seven_day": { "utilization": 0.50 } }' > "$CACHE"
run_expect "missing seven_day_sonnet key (sonnet tier) → exit 2" 2 --tier sonnet

echo '{ "five_hour": { "utilization": 0.50 }, "seven_day": { "utilization": 0.50 }, "seven_day_sonnet": { "utilization": 0.50 } }' > "$CACHE"

# ── Sonnet tier: all at 0.85 (below default 0.90 threshold) ───────────────────

make_cache 0.85 0.85 0.85
run_expect "sonnet tier, all=0.85 → exit 0" 0 --tier sonnet

# ── Sonnet tier: each bucket at 0.90 (at threshold) ───────────────────────────

make_cache 0.90 0.85 0.85
run_expect "sonnet tier, five_hour=0.90 → exit 1" 1 --tier sonnet

make_cache 0.85 0.90 0.85
run_expect "sonnet tier, seven_day=0.90 → exit 1" 1 --tier sonnet

make_cache 0.85 0.85 0.90
run_expect "sonnet tier, seven_day_sonnet=0.90 → exit 1" 1 --tier sonnet

# ── Sonnet tier: all at 0.95 ───────────────────────────────────────────────────

make_cache 0.95 0.95 0.95
run_expect "sonnet tier, all=0.95 → exit 1" 1 --tier sonnet

# ── Strong tier: all at 0.85 ──────────────────────────────────────────────────

make_cache 0.85 0.85 0.85
run_expect "strong tier, all=0.85 → exit 0" 0 --tier strong

# ── Strong tier: each checked bucket at 0.90 ──────────────────────────────────

make_cache 0.90 0.85 0.85
run_expect "strong tier, five_hour=0.90 → exit 1" 1 --tier strong

make_cache 0.85 0.90 0.85
run_expect "strong tier, seven_day=0.90 → exit 1" 1 --tier strong

# ── Strong tier does NOT check seven_day_sonnet ───────────────────────────────

make_cache 0.85 0.85 0.95
run_expect "strong tier, seven_day_sonnet=0.95 (not checked) → exit 0" 0 --tier strong

# ── Custom threshold via env ───────────────────────────────────────────────────

make_cache 0.85 0.85 0.85
RELAY_QUOTA_THRESHOLD=0.85 USAGE_CACHE="$CACHE" "$SCRIPT" --tier sonnet && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]]; then
  pass "custom threshold 0.85, util=0.85 → exit 1"
else
  fail "custom threshold 0.85, util=0.85 → expected exit 1, got $rc"
fi

# ── Seatbelt: agent-count ≥ 200 ───────────────────────────────────────────────

make_cache 0.10 0.10 0.10
run_expect "seatbelt: agents=200 → exit 1 regardless of low usage" 1 --tier sonnet --agents 200

make_cache 0.10 0.10 0.10
run_expect "seatbelt: agents=199 → not triggered → exit 0" 0 --tier sonnet --agents 199

# ── Seatbelt: wall-clock ≥ 7200s ──────────────────────────────────────────────

make_cache 0.10 0.10 0.10
run_expect "seatbelt: wall=7200 → exit 1 regardless of low usage" 1 --tier sonnet --wall 7200

make_cache 0.10 0.10 0.10
run_expect "seatbelt: wall=7199 → not triggered → exit 0" 0 --tier sonnet --wall 7199

echo "ALL PASS"
