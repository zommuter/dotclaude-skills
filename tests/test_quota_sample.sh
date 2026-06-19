#!/usr/bin/env bash
# Defect-class test (no roadmap item): the usage-quota sampler + reporter.
# Hermetic — fixture cache in a tmpdir, QUOTA_NO_COMMIT so git is never touched.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SAMPLER="$ROOT/tools/quota-sample.sh"
REPORT="$ROOT/tools/quota-report.py"

fail=0
check() { if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3 (got '$1' want '$2')"; fail=1; fi; }
contains() { if printf '%s' "$1" | grep -qF "$2"; then echo "  ok  $3"; else echo "  FAIL $3 (missing '$2')"; fail=1; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- fixture: a statusline-shaped cache, FRESH (so the sampler never hits the network) ---
CACHE="$TMP/cache.json"
cat > "$CACHE" <<'JSON'
{"five_hour":{"utilization":12.0,"resets_at":"2026-06-19T19:00:00+00:00"},
 "seven_day":{"utilization":60.0,"resets_at":"2026-06-23T12:00:00+00:00"},
 "seven_day_sonnet":{"utilization":40.0,"resets_at":"2026-06-23T12:00:00+00:00"},
 "extra_usage":{"used_credits":1.5,"utilization":7.0}}
JSON

DATA="$TMP/diary/quota/quota-samples.jsonl"
mkdir -p "$(dirname "$DATA")"

echo "== sampler appends one valid JSONL row from a fresh cache (no network, no git) =="
QUOTA_NO_COMMIT=1 QUOTA_FRESH_SECS=999999 \
  QUOTA_CACHE="$CACHE" QUOTA_DIARY_DIR="$TMP/diary" \
  bash "$SAMPLER"
n=$(wc -l < "$DATA" | tr -d ' ')
check "$n" "1" "exactly one row appended"
row=$(tail -1 "$DATA")
check "$(printf '%s' "$row" | jq -r '.seven_day')" "60.0" "seven_day captured"
check "$(printf '%s' "$row" | jq -r '.seven_day_sonnet')" "40.0" "sonnet captured"
check "$(printf '%s' "$row" | jq -r '.source')" "cache" "source=cache when reused"
check "$(printf '%s' "$row" | jq -r '.extra_credits_used')" "1.5" "extra credits captured"
check "$(printf '%s' "$row" | jq -r '.stale')" "false" "fresh cache not flagged stale"

echo "== reporter flags a >=15pp jump and ignores a reset drop =="
# Synthetic series: 60 -> 95 (a +35pp spike), then a reset drop 95 -> 2 (must NOT flag).
cat > "$DATA" <<'JSONL'
{"ts":"2026-06-18T20:00:00+02:00","epoch":1781812800,"source":"fetch","stale":false,"seven_day":60,"seven_day_resets_at":"2026-06-23T12:00:00+00:00"}
{"ts":"2026-06-18T20:15:00+02:00","epoch":1781813700,"source":"fetch","stale":false,"seven_day":95,"seven_day_resets_at":"2026-06-23T12:00:00+00:00"}
{"ts":"2026-06-19T13:00:00+02:00","epoch":1781874000,"source":"fetch","stale":false,"seven_day":2,"seven_day_resets_at":"2026-06-30T12:00:00+00:00"}
JSONL
out=$(python3 "$REPORT" "$DATA" --jump 15 2>&1)
contains "$out" "60%→95%" "spike reported"
contains "$out" "+35pp" "delta magnitude reported"
# the reset drop (95 -> 2) must not appear as a jump
if printf '%s' "$out" | grep -q "95%→2%"; then echo "  FAIL reset drop wrongly flagged"; fail=1; else echo "  ok  reset drop not flagged"; fi
# two reset dates => two windows
wins=$(printf '%s' "$out" | grep -c "window→reset")
check "$wins" "2" "segmented into two weekly windows"

echo
[ "$fail" -eq 0 ] && echo "test_quota_sample: PASS" || echo "test_quota_sample: FAIL"
exit "$fail"
