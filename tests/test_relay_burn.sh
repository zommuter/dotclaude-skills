#!/usr/bin/env bash
# roadmap:219b — relay-burn.sh: quota burnup time-series sampler + reporter.
# Hermetic: all paths point at a tempdir; never touches ~/.config or the real usage cache.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/relay-burn.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export RELAY_QUOTA_SAMPLES="$T/samples.jsonl"
export USAGE_CACHE="$T/cache.json"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

make_cache() {  # $1=five_hour $2=seven_day $3=sonnet $4=used_credits
  cat > "$USAGE_CACHE" <<JSON
{ "five_hour":        {"utilization": $1, "resets_at": "2026-06-16T09:29:59+00:00"},
  "seven_day":        {"utilization": $2, "resets_at": "2026-06-16T11:59:59+00:00"},
  "seven_day_sonnet": {"utilization": $3, "resets_at": "2026-06-16T11:59:59+00:00"},
  "extra_usage":      {"used_credits": $4, "monthly_limit": 3500} }
JSON
}

# ── sample: missing cache is non-fatal (exit 0, no file) ──────────────────────
rm -f "$USAGE_CACHE" "$RELAY_QUOTA_SAMPLES"
"$SCRIPT" sample && rc=0 || rc=$?
[[ "$rc" -eq 0 ]] || fail "sample with missing cache should exit 0 (got $rc)"
[[ ! -f "$RELAY_QUOTA_SAMPLES" ]] || fail "sample with missing cache must not create the samples file"
pass "sample: missing cache → exit 0, no file written"

# ── sample: writes one well-formed JSON line with the expected fields ─────────
make_cache 10.0 68.0 26.0 228.0
RELAY_RUN_ID="relay-test" "$SCRIPT" sample
[[ -f "$RELAY_QUOTA_SAMPLES" ]] || fail "sample did not write the samples file"
n=$(wc -l < "$RELAY_QUOTA_SAMPLES")
[[ "$n" -eq 1 ]] || fail "expected 1 sample line, got $n"
runid=$(jq -r '.runId' "$RELAY_QUOTA_SAMPLES")
[[ "$runid" == "relay-test" ]] || fail "sample runId not captured from RELAY_RUN_ID (got '$runid')"
uc=$(jq -r '.used_credits' "$RELAY_QUOTA_SAMPLES")
awk -v u="$uc" 'BEGIN{exit !(u==228)}' || fail "sample used_credits wrong (got '$uc')"
for k in ts epoch five_hour seven_day seven_day_sonnet monthly_limit seven_day_reset; do
  v=$(jq -r ".$k" "$RELAY_QUOTA_SAMPLES")
  [[ -n "$v" && "$v" != "null" ]] || fail "sample missing field $k"
done
pass "sample: writes one JSON line with all expected fields"

# ── sample: cache missing extra_usage → used_credits null, still writes line ──
echo '{"five_hour":{"utilization":5},"seven_day":{"utilization":5},"seven_day_sonnet":{"utilization":5}}' > "$USAGE_CACHE"
: > "$RELAY_QUOTA_SAMPLES"
"$SCRIPT" sample
[[ "$(jq -r '.used_credits' "$RELAY_QUOTA_SAMPLES")" == "null" ]] || fail "absent extra_usage should yield used_credits=null"
pass "sample: absent extra_usage → used_credits null, line still written"

# ── report: needs ≥2 samples ──────────────────────────────────────────────────
: > "$RELAY_QUOTA_SAMPLES"
make_cache 10 50 20 100
RELAY_RUN_ID="r" "$SCRIPT" sample
"$SCRIPT" report && rc=0 || rc=$?
[[ "$rc" -eq 1 ]] || fail "report with 1 sample should exit 1 (got $rc)"
pass "report: <2 samples → exit 1"

# ── report: two samples → correct $/h and bucket deltas (--json) ──────────────
# Hand-author two samples 2h apart: +$8.40 over 2h = $4.20/h; 7d 60→68 = +4%/h.
base=$(date +%s)
cat > "$RELAY_QUOTA_SAMPLES" <<JSON
{"ts":"a","epoch":$((base-7200)),"runId":"run1","five_hour":4.0,"seven_day":60.0,"seven_day_sonnet":18.0,"used_credits":222.0,"monthly_limit":3500,"five_hour_reset":"x","seven_day_reset":"R1"}
{"ts":"b","epoch":$base,"runId":"run1","five_hour":10.0,"seven_day":68.0,"seven_day_sonnet":26.0,"used_credits":230.40,"monthly_limit":3500,"five_hour_reset":"x","seven_day_reset":"R1"}
JSON
j=$("$SCRIPT" report --json)
ok=$(jq -r '.ok' <<<"$j");          [[ "$ok" == "true" ]] || fail "report --json ok!=true"
dc=$(jq -r '.d_credits' <<<"$j")
awk -v d="$dc" 'BEGIN{exit !(d>8.39 && d<8.41)}' || fail "d_credits expected ~8.40, got $dc"
eh=$(jq -r '.elapsed_h' <<<"$j");   [[ "$eh" == "2" ]] || fail "elapsed_h expected 2, got $eh"
sd_delta=$(jq -r '.buckets[] | select(.name=="seven_day") | .delta' <<<"$j")
[[ "$sd_delta" == "8" ]] || fail "seven_day delta expected 8, got $sd_delta"
pass "report: two-sample rate math correct (\$8.40/2h, 7d +8%)"

# ── report: resets segment the series (credit drop starts a fresh segment) ────
cat > "$RELAY_QUOTA_SAMPLES" <<JSON
{"ts":"old","epoch":$((base-100000)),"runId":"r0","five_hour":4.0,"seven_day":90.0,"seven_day_sonnet":80.0,"used_credits":300.0,"monthly_limit":3500,"five_hour_reset":"x","seven_day_reset":"OLD"}
{"ts":"new-a","epoch":$((base-7200)),"runId":"r1","five_hour":4.0,"seven_day":60.0,"seven_day_sonnet":18.0,"used_credits":10.0,"monthly_limit":3500,"five_hour_reset":"x","seven_day_reset":"NEW"}
{"ts":"new-b","epoch":$base,"runId":"r1","five_hour":10.0,"seven_day":68.0,"seven_day_sonnet":26.0,"used_credits":18.40,"monthly_limit":3500,"five_hour_reset":"x","seven_day_reset":"NEW"}
JSON
j=$("$SCRIPT" report --json)
segs=$(jq -r '.segments' <<<"$j");  [[ "$segs" == "2" ]] || fail "expected 2 segments, got $segs"
segn=$(jq -r '.seg_n' <<<"$j");     [[ "$segn" == "2" ]] || fail "latest segment should have 2 samples, got $segn"
dc=$(jq -r '.d_credits' <<<"$j")
awk -v d="$dc" 'BEGIN{exit !(d>8.39 && d<8.41)}' || fail "post-reset d_credits should be ~8.40 (segment-isolated), got $dc"
pass "report: credit-drop reset starts a fresh segment; rate uses latest segment only"

# ── report: --run filter narrows to one run ───────────────────────────────────
runs=$("$SCRIPT" report --run r1 --json | jq -r '.runId')
[[ "$runs" == "r1" ]] || fail "--run filter did not isolate run r1 (got '$runs')"
pass "report: --run filter isolates a single run"

echo "ALL PASS: relay-burn (id:219b)"
