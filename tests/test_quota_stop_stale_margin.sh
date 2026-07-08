#!/usr/bin/env bash
# roadmap:1d64 — quota-stop.sh must not false-stop a healthy pool on a stale cache it
# cannot refresh. Margin-aware staleness: proceed on a stale-but-SAFE last-known reading.
#
# WHY (incident 2026-06-23, run relay-20260623-070136): the pool stopped with
# stopReason=quota-stale-cache at five_hour=7% / seven_day=38% / seven_day_sonnet=25%
# against a 90% threshold — enormous headroom. Root cause: the staleness fail-safe is
# MARGIN-BLIND. When the cache is older than STALE_SECS and the self-refresh fails (the
# /api/oauth/usage endpoint 429s aggressively — a documented statusline gotcha), the gate
# does an UNCONDITIONAL `exit 2` (stop) regardless of what the last reading said. But a
# stale reading is only dangerous if we might have CROSSED the threshold since it was
# taken; at 7/38/25% vs 90% no plausible burn over the stale window crosses 90%.
#
# Fix: when stale AND self-refresh fails, consult the last-known per-bucket utilization.
# If EVERY checked bucket for this tier is below (its threshold − MARGIN), PROCEED on the
# stale-but-safe reading (exit 0). Only when a bucket is within MARGIN of its threshold
# (or missing) keep the conservative `exit 2`. MARGIN = RELAY_QUOTA_STALE_MARGIN points
# (default 30). A genuinely MISSING cache (no reading at all) still exits 2 — blind.
#
# Hermetic: temp cache + tokenless USAGE_CREDS (so self-refresh is skipped, exercising the
# refresh-unavailable branch); no network.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QS="$SRC_DIR/relay/scripts/quota-stop.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$QS" ]] || fail "quota-stop.sh not found/executable at $QS"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
CREDS="$tmp/creds.json"; printf '{}' >"$CREDS"   # tokenless ⟹ self-refresh skipped

# write a cache with given utils, then age its mtime past STALE_SECS (600s)
mk_stale_cache() {
  local five="$1" sevd="$2" sevs="$3" f="$tmp/cache.json"
  jq -n --argjson f "$five" --argjson d "$sevd" --argjson s "$sevs" \
    '{five_hour:{utilization:$f}, seven_day:{utilization:$d}, seven_day_sonnet:{utilization:$s}}' >"$f"
  touch -d '1 hour ago' "$f"
  printf '%s' "$f"
}

run() { USAGE_CACHE="$1" USAGE_CREDS="$CREDS" "$QS" --tier sonnet >/dev/null 2>&1; echo $?; }

# 1. The incident reading: stale + unrefreshable + low util → PROCEED (exit 0).
c="$(mk_stale_cache 7 38 25)"
rc="$(run "$c")"
[[ "$rc" == "0" ]] || fail "stale + low util (7/38/25, thr 90, margin 30) must PROCEED (exit 0), got $rc"
pass "stale-but-safe low-utilization cache proceeds (the incident no longer false-stops)"

# 2. Stale + unrefreshable + a bucket WITHIN margin of threshold → conservative stop (exit 2).
c="$(mk_stale_cache 7 88 25)"   # seven_day=88, thr 90, margin 30 ⟹ 88 > 60 ⟹ unsafe
rc="$(run "$c")"
[[ "$rc" == "2" ]] || fail "stale + near-threshold bucket (seven_day=88) must stop uncertain (exit 2), got $rc"
pass "stale cache near a threshold keeps the conservative exit 2"

# 3. Missing cache (no reading at all) still exits 2 (genuinely blind).
rc="$(USAGE_CACHE="$tmp/nope.json" USAGE_CREDS="$CREDS" "$QS" --tier sonnet >/dev/null 2>&1; echo $?)"
[[ "$rc" == "2" ]] || fail "missing cache must exit 2, got $rc"
pass "missing cache still exits 2 (blind)"

# 4. A FRESH low-util cache still exits 0 (margin logic must not regress the happy path).
f="$tmp/fresh.json"
jq -n '{five_hour:{utilization:7}, seven_day:{utilization:38}, seven_day_sonnet:{utilization:25}}' >"$f"
rc="$(USAGE_CACHE="$f" USAGE_CREDS="$CREDS" "$QS" --tier sonnet >/dev/null 2>&1; echo $?)"
[[ "$rc" == "0" ]] || fail "fresh low-util cache must exit 0, got $rc"
pass "fresh low-utilization cache exits 0 (happy path intact)"

# 5. id:c5ba follow-up — TIGHT cap (0.35) must not INVERT the margin. A fixed 30-pt margin
#    under a 0.35 cap demanded util<5% to proceed on a stale cache (35−30), so any real
#    utilization false-stopped. effective_margin = min(30, 0.35*50=17.5) → safe if util<17.5.
#    Stale cache at five=7 / seven_day=10 / sonnet=10 (all well under 17.5) → PROCEED (exit 0).
c="$(mk_stale_cache 7 10 10)"
rc="$(RELAY_QUOTA_THRESHOLD_SEVEN_DAY=0.35 RELAY_QUOTA_THRESHOLD_SEVEN_DAY_SONNET=0.35 \
      USAGE_CACHE="$c" USAGE_CREDS="$CREDS" "$QS" --tier sonnet >/dev/null 2>&1; echo $?)"
[[ "$rc" == "0" ]] || fail "(5) tight cap 0.35 + stale low util (10%) must PROCEED with capped margin (exit 0), got $rc"
pass "(5) id:c5ba — tight 0.35 cap: capped effective margin (min(30,17.5)) lets stale low-util proceed (no inversion)"

# 6. id:c5ba follow-up — the cap must stay conservative NEAR the threshold: tight 0.35 cap +
#    stale seven_day=30% (within 17.5 of 35) → still uncertain STOP (exit 2). Proves the
#    recalibration only removes the pathological inversion, it doesn't blanket-proceed.
c="$(mk_stale_cache 7 30 10)"
rc="$(RELAY_QUOTA_THRESHOLD_SEVEN_DAY=0.35 RELAY_QUOTA_THRESHOLD_SEVEN_DAY_SONNET=0.35 \
      USAGE_CACHE="$c" USAGE_CREDS="$CREDS" "$QS" --tier sonnet >/dev/null 2>&1; echo $?)"
[[ "$rc" == "2" ]] || fail "(6) tight cap 0.35 + stale near-cap util (30% vs 35) must stay conservative (exit 2), got $rc"
pass "(6) id:c5ba — tight cap stays conservative near the threshold (30% vs 35% → exit 2)"

echo "ALL PASS: quota-stop margin-aware staleness (roadmap:1d64 + id:c5ba margin recalibration)"
