#!/usr/bin/env bash
# roadmap:9934 — quota-stop.sh: tier-aware quota threshold check

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/quota-stop.sh"
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

make_cache 50 50 50
touch -d "11 minutes ago" "$CACHE"
# USAGE_CREDS=/dev/null ⟹ no token ⟹ self-refresh is skipped. With the margin-aware
# staleness check (id:1d64, default MARGIN=30), util=50% < 90%*100-30=60 → stale-but-SAFE
# → exit 0 (falls through to the normal check_key loop). For a near-threshold stale cache
# that should still stop, see test_quota_stop_stale_margin.sh test-2.
USAGE_CREDS=/dev/null USAGE_CACHE="$CACHE" "$SCRIPT" --tier sonnet && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then pass "stale cache (>10 min) + no creds + low util → stale-but-safe exit 0 (id:1d64)"; else fail "stale+no-creds+low-util expected exit 0 (stale-but-safe), got $rc"; fi
# Restore fresh mtime for subsequent tests
touch "$CACHE"

# ── Absent per-model weekly sub-bucket (id:0175 / routed:82e3) ─────────────────
# As of 2026-06-30 the usage API stopped exposing per-model weekly sub-limits: seven_day_sonnet
# (and seven_day_opus, etc.) are null; only the consolidated weekly_all / seven_day bucket
# remains. An absent seven_day_sonnet therefore means "no such limit" — the general seven_day
# bucket governs — NOT a corrupt cache. The sonnet tier must skip the absent sub-bucket and
# gate on seven_day + five_hour, exactly as it did when both are low here.
echo '{ "five_hour": { "utilization": 50 }, "seven_day": { "utilization": 50 } }' > "$CACHE"
run_expect "absent seven_day_sonnet + low seven_day/five_hour (sonnet) → skip → exit 0" 0 --tier sonnet

# Fail-safe preserved: seven_day is a REQUIRED bucket, so its absence still stops (exit 2).
echo '{ "five_hour": { "utilization": 50 }, "seven_day_sonnet": { "utilization": 50 } }' > "$CACHE"
run_expect "absent seven_day (required) → still fail-safe exit 2" 2 --tier sonnet

# The general bucket still gates when the sub-bucket is absent: seven_day at/above threshold
# stops even though seven_day_sonnet is missing.
echo '{ "five_hour": { "utilization": 50 }, "seven_day": { "utilization": 95 } }' > "$CACHE"
run_expect "absent seven_day_sonnet but seven_day 95% ≥ 90% → exit 1" 1 --tier sonnet

echo '{ "five_hour": { "utilization": 50 }, "seven_day": { "utilization": 50 }, "seven_day_sonnet": { "utilization": 50 } }' > "$CACHE"

# ── Live-cache scale regression (utilization is 0-100 percent, NOT 0-1) ───────
# A real /tmp/claude-usage-cache.json at moderate usage (37%) must NOT trigger
# the default 0.90 (=90%) threshold. Guards against fraction/percent confusion.

make_cache 37.0 24.0 8.0
run_expect "live-shaped cache (37%/24%/8%) → exit 0 at default threshold" 0 --tier sonnet

# ── Sonnet tier: all at 85% (below default 90% threshold) ───────────────────

make_cache 85 85 85
run_expect "sonnet tier, all=85% → exit 0" 0 --tier sonnet

# ── Sonnet tier: each bucket at 90% (at threshold) ───────────────────────────

make_cache 90 85 85
run_expect "sonnet tier, five_hour=90% → exit 1" 1 --tier sonnet

make_cache 85 90 85
run_expect "sonnet tier, seven_day=90% → exit 1" 1 --tier sonnet

make_cache 85 85 90
run_expect "sonnet tier, seven_day_sonnet=90% → exit 1" 1 --tier sonnet

# ── Sonnet tier: all at 95% ───────────────────────────────────────────────────

make_cache 95 95 95
run_expect "sonnet tier, all=95% → exit 1" 1 --tier sonnet

# ── Strong tier: all at 85% ──────────────────────────────────────────────────

make_cache 85 85 85
run_expect "strong tier, all=85% → exit 0" 0 --tier strong

# ── Strong tier: each checked bucket at 90% ──────────────────────────────────

make_cache 90 85 85
run_expect "strong tier, five_hour=90% → exit 1" 1 --tier strong

make_cache 85 90 85
run_expect "strong tier, seven_day=90% → exit 1" 1 --tier strong

# ── Strong tier does NOT check seven_day_sonnet ───────────────────────────────

make_cache 85 85 95
run_expect "strong tier, seven_day_sonnet=95% (not checked) → exit 0" 0 --tier strong

# ── Custom threshold via env ───────────────────────────────────────────────────

make_cache 85 85 85
RELAY_QUOTA_THRESHOLD=0.85 USAGE_CACHE="$CACHE" "$SCRIPT" --tier sonnet && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]]; then
  pass "custom threshold 0.85, util=85% → exit 1"
else
  fail "custom threshold 0.85, util=85% → expected exit 1, got $rc"
fi

# ── Seatbelt: agent-count ≥ 200 ───────────────────────────────────────────────

make_cache 10 10 10
run_expect "seatbelt: agents=200 → exit 1 regardless of low usage" 1 --tier sonnet --agents 200

make_cache 10 10 10
run_expect "seatbelt: agents=199 → not triggered → exit 0" 0 --tier sonnet --agents 199

# ── Seatbelt: wall-clock ≥ 7200s ──────────────────────────────────────────────

make_cache 10 10 10
run_expect "seatbelt: wall=7200 → exit 1 regardless of low usage" 1 --tier sonnet --wall 7200

make_cache 10 10 10
run_expect "seatbelt: wall=7199 → not triggered → exit 0" 0 --tier sonnet --wall 7199

# ── Per-bucket threshold overrides (budget-campaign governor, 2026-06-13) ──────
# run_expect_env DESC EXPECTED_RC "ENV=val ..." [script args...]
run_expect_env() {
  local desc="$1"; local expected="$2"; local envs="$3"; shift 3
  local rc
  env $envs USAGE_CACHE="$CACHE" "$SCRIPT" "$@" && rc=0 || rc=$?
  if [[ "$rc" -eq "$expected" ]]; then pass "$desc"; else fail "$desc (expected $expected, got $rc)"; fi
}

# seven_day capped at 0.50 trips at 55% even though general THRESHOLD (0.90) wouldn't
make_cache 85 55 40
run_expect_env "per-bucket: SEVEN_DAY=0.50, seven_day=55% → exit 1" 1 "RELAY_QUOTA_THRESHOLD_SEVEN_DAY=0.50" --tier strong

# five_hour keeps the default 0.90 (85%<90 → ok) while 7d/sonnet capped 0.50 and both under
make_cache 85 40 40
run_expect_env "per-bucket: 5h stays 0.90 (85%<90) while 7d/sonnet capped 0.50, all under → exit 0" 0 \
  "RELAY_QUOTA_THRESHOLD_SEVEN_DAY=0.50 RELAY_QUOTA_THRESHOLD_SEVEN_DAY_SONNET=0.50" --tier sonnet

# seven_day_sonnet capped at 0.50 trips at 55% (sonnet tier checks it)
make_cache 85 40 55
run_expect_env "per-bucket: SEVEN_DAY_SONNET=0.50, sonnet=55% → exit 1" 1 "RELAY_QUOTA_THRESHOLD_SEVEN_DAY_SONNET=0.50" --tier sonnet

# additive/no-behaviour-change: without any override, 55% buckets pass under default 0.90
make_cache 85 55 55
run_expect "per-bucket: no override → default 0.90 unchanged (55% all pass) → exit 0" 0 --tier strong

# ── No pool-side credential/API access (id:0175 / routed:82e3) ─────────────────
# Regression guard (inverts the old "self-refresh present" assertion): this gate runs inside
# the auto-mode relay pool, where reading the OAuth token + curling /api/oauth/usage is a
# credential-egress shape the permission classifier denies → the agent dies → the pool
# false-stops on round 1. The pool-side gate must therefore NEVER touch the token or hit the
# API; the foreground statusline is the sole token owner. A stale cache is resolved by the
# stale-but-safe margin check + burn-rate extrapolation (no network, no credential).
grep -q 'api/oauth/usage'      "$SCRIPT" && fail "quota-stop.sh must not call /api/oauth/usage (credential egress; statusline owns refresh)"
grep -q 'accessToken'          "$SCRIPT" && fail "quota-stop.sh must not read the OAuth accessToken"
grep -q 'Authorization: Bearer' "$SCRIPT" && fail "quota-stop.sh must not send a Bearer token"
grep -q 'USAGE_CREDS'          "$SCRIPT" && fail "quota-stop.sh must not reference USAGE_CREDS (no pool-side credential path)"
pass "no pool-side credential/API access (statusline is sole token owner)"

# ── Time-decaying 7-day cap (RELAY_QUOTA_DECAY_7D, autonomous relay) ───────────
# Cache with a seven_day.resets_at; cap interpolates 0.70 (window open) → 0.10 (reset).
decay_cache() {  # $1=seven_day_util  $2=resets_in (date -d arg)
  local reset; reset=$(date -d "$2" -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$CACHE" <<JSON
{ "five_hour": {"utilization": 5, "resets_at": "$reset"},
  "seven_day": {"utilization": $1, "resets_at": "$reset"},
  "seven_day_sonnet": {"utilization": 5, "resets_at": "$reset"} }
JSON
}
# 5 days left of 7 ⟹ ~2/7 elapsed ⟹ cap ≈ 0.53; util 40% < cap → exit 0
decay_cache 40 "+5 days"
run_expect_env "decay 0.70:0.10, 5d-left, 7d=40%<~53% → exit 0" 0 "RELAY_QUOTA_DECAY_7D=0.70:0.10 USAGE_CREDS=/dev/null" --tier strong
# same window position, util 60% > ~53% cap → exit 1
decay_cache 60 "+5 days"
run_expect_env "decay 0.70:0.10, 5d-left, 7d=60%>~53% → exit 1" 1 "RELAY_QUOTA_DECAY_7D=0.70:0.10 USAGE_CREDS=/dev/null" --tier strong
# near window end (cap ≈ 0.10): util 40% > 10% → exit 1 (relay backs off late in window)
decay_cache 40 "+3 hours"
run_expect_env "decay near reset (cap≈0.10), 7d=40% → exit 1" 1 "RELAY_QUOTA_DECAY_7D=0.70:0.10 USAGE_CREDS=/dev/null" --tier strong
touch "$CACHE"

echo "ALL PASS"
