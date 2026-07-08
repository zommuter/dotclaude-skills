#!/usr/bin/env bash
# Defect-fix test (no roadmap item — id:0175 / routed:82e3 lives in TODO.md, not ROADMAP.md,
# so this file has NO `# roadmap:` header and its failures always count).
#
# id:0175 / routed:82e3 — the relay pool quota gate is non-functional for BACKGROUND/Workflow
# runs: launched as a sandboxed Workflow, the default USAGE_CACHE under /tmp is invisible
# (separate /tmp namespace) → quota-stop.sh read it as missing → blind `exit 2` (fail-safe
# STOP) on round 1, BEFORE any threshold compare → 0 units dispatched, the whole unattended
# pool dead. Fix: on an unreadable cache (and only inside a live run, RELAY_RUN_ID set),
# extrapolate current utilization from relay-burn.sh's recent burn-rate series and compare
# THAT to the same per-bucket thresholds, with conservative guards:
#   - recency guard: only extrapolate from a recent-enough last sample, else fail-safe STOP;
#   - safety margin: bias the estimate UPWARD so noise errs toward stopping;
#   - distinct reasons: exit 3 / REASON=quota-extrapolated-stop when the estimate crosses,
#     exit 2 / REASON=quota-cache-unreadable when there is no usable sample (infra failure
#     must never masquerade as a genuine quota event);
#   - loud stderr logging of the inputs (last sample, rate, elapsed, estimate).
#
# Hermetic: temp samples JSONL + a deliberately MISSING cache + tokenless creds (no network);
# RELAY_QUOTA_SAMPLES is always pointed at the temp file so the real ~/.config is never read.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QS="$SRC_DIR/relay/scripts/quota-stop.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$QS" ]] || fail "quota-stop.sh not found/executable at $QS"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
CREDS="$tmp/creds.json"; printf '{}' >"$CREDS"   # tokenless ⟹ self-refresh skipped
MISSING_CACHE="$tmp/nope-cache.json"             # never created ⟹ cache unreadable path
SAMPLES="$tmp/samples.jsonl"

NOW=$(date +%s)

# Emit one burn sample line (matching relay-burn.sh's `sample` schema) for a given epoch +
# per-bucket utilizations. used_credits/reset kept constant-ish so report() treats the rows
# as one contiguous segment.
emit() {
  local epoch="$1" five="$2" sevd="$3" sevs="$4" credits="$5"
  local ts; ts=$(date -d "@$epoch" '+%Y-%m-%dT%H:%M:%S%z')
  jq -nc --arg ts "$ts" --argjson epoch "$epoch" --arg run "test-run" \
        --argjson f "$five" --argjson d "$sevd" --argjson s "$sevs" --argjson c "$credits" \
    '{ts:$ts, epoch:$epoch, runId:$run, five_hour:$f, seven_day:$d, seven_day_sonnet:$s,
      used_credits:$c, monthly_limit:100,
      five_hour_reset:"2030-01-01T00:00:00+0000", seven_day_reset:"2030-01-07T00:00:00+0000"}' \
    >>"$SAMPLES"
}

# run: cache MISSING, samples from $SAMPLES, live run (RELAY_RUN_ID set). Captures rc + stderr.
ERRFILE="$tmp/err.txt"
run_extrap() {
  RELAY_RUN_ID="test-run" RELAY_QUOTA_SAMPLES="$SAMPLES" \
    USAGE_CACHE="$MISSING_CACHE" USAGE_CREDS="$CREDS" \
    "$QS" --tier sonnet >/dev/null 2>"$ERRFILE"
  echo $?
}

# ── (a) recent sample + LOW burn → extrapolation PROCEEDS (exit 0) ────────────────
: >"$SAMPLES"
emit $((NOW-3900)) 10 30 40 1.0     # 65 min ago
emit $((NOW-300))  11 31 41 1.1     # 5 min ago — rate ~1%/h, all far under 90%
rc="$(run_extrap)"
[[ "$rc" == "0" ]] || { cat "$ERRFILE"; fail "recent + low burn must PROCEED (exit 0), got $rc"; }
grep -q "REASON=quota-extrapolated-proceed" "$ERRFILE" \
  || fail "proceed path must log REASON=quota-extrapolated-proceed; got: $(cat "$ERRFILE")"
pass "(a) recent sample + low burn extrapolates UNDER threshold → proceeds (exit 0)"

# ── (b) recent sample + HIGH burn → EXTRAPOLATED STOP (exit 3, distinct reason) ───
: >"$SAMPLES"
emit $((NOW-3900)) 12 33 70 2.0     # 65 min ago
emit $((NOW-300))  13 34 88 2.5     # 5 min ago — seven_day_sonnet 70→88, ~18%/h → est ~89.5%+margin ≥ 90
rc="$(run_extrap)"
[[ "$rc" == "3" ]] || { cat "$ERRFILE"; fail "recent + high burn must EXTRAPOLATE-STOP (exit 3), got $rc"; }
grep -q "REASON=quota-extrapolated-stop bucket=seven_day_sonnet" "$ERRFILE" \
  || fail "extrapolated stop must log distinct REASON=quota-extrapolated-stop with crossing bucket; got: $(cat "$ERRFILE")"
grep -qi "est=" "$ERRFILE" || fail "extrapolated stop must log the estimate inputs (loud logging)"
pass "(b) recent sample + high burn extrapolates OVER threshold → exit 3, REASON=quota-extrapolated-stop"

# ── (c1) only ONE sample (no derivable rate) → fail-safe STOP (exit 2) ────────────
: >"$SAMPLES"
emit $((NOW-300)) 11 31 41 1.1
rc="$(run_extrap)"
[[ "$rc" == "2" ]] || { cat "$ERRFILE"; fail "single sample (no rate) must fail-safe STOP (exit 2), got $rc"; }
grep -q "REASON=quota-cache-unreadable" "$ERRFILE" \
  || fail "no-usable-sample stop must log REASON=quota-cache-unreadable (never masquerade as quota event); got: $(cat "$ERRFILE")"
pass "(c1) no usable burn series (1 sample) → fail-safe exit 2, REASON=quota-cache-unreadable"

# ── (c2) recency guard: last sample older than the 2h bound → fail-safe STOP (exit 2) ─
: >"$SAMPLES"
emit $((NOW-14400)) 10 30 40 1.0    # 4h ago
emit $((NOW-12600)) 11 31 41 1.1    # 3.5h ago — last sample > 2h old ⟹ untrustworthy
rc="$(run_extrap)"
[[ "$rc" == "2" ]] || { cat "$ERRFILE"; fail "stale last sample (>2h) must fail-safe STOP (exit 2), got $rc"; }
grep -q "REASON=quota-cache-unreadable" "$ERRFILE" \
  || fail "recency-guard stop must log REASON=quota-cache-unreadable; got: $(cat "$ERRFILE")"
grep -qi "recency bound" "$ERRFILE" || fail "recency-guard stop must name the recency bound in its log"
pass "(c2) recency guard: last sample older than 2h → fail-safe exit 2 (never extrapolate stale data)"

# ── (d) extrapolation is gated on RELAY_RUN_ID — outside a live run the blind exit 2 stands ─
: >"$SAMPLES"
emit $((NOW-3900)) 10 30 40 1.0
emit $((NOW-300))  11 31 41 1.1     # would PROCEED if extrapolation ran
rc="$(RELAY_QUOTA_SAMPLES="$SAMPLES" USAGE_CACHE="$MISSING_CACHE" USAGE_CREDS="$CREDS" \
      "$QS" --tier sonnet >/dev/null 2>"$ERRFILE"; echo $?)"
[[ "$rc" == "2" ]] || { cat "$ERRFILE"; fail "no RELAY_RUN_ID must keep the blind fail-safe exit 2, got $rc"; }
pass "(d) extrapolation gated on RELAY_RUN_ID — no live run keeps the conservative exit 2 (hermetic)"

# ── (e) id:c5ba — seven_day_sonnet NULL in samples (API dropped per-model weekly sub-limits,
#        routed:82e3): the extrapolation path must SKIP the absent sonnet bucket (not treat it
#        as a corrupt cache) and let seven_day govern → recent + low burn PROCEEDS (exit 0).
#        Before the fix this false-STOPped exit 2 ("bucket 'seven_day_sonnet' absent"). ──────
: >"$SAMPLES"
emit $((NOW-3900)) 10 30 null 1.0   # 65 min ago, no sonnet sub-limit
emit $((NOW-300))  11 31 null 1.1   # 5 min ago — five_hour/seven_day low, far under 90%
rc="$(run_extrap)"
[[ "$rc" == "0" ]] || { cat "$ERRFILE"; fail "(e) null seven_day_sonnet + low burn must PROCEED (exit 0), got $rc"; }
grep -q "bucket 'seven_day_sonnet' absent (no such limit) → skipping" "$ERRFILE" \
  || fail "(e) must log the seven_day_sonnet skip, not a fail-safe stop; got: $(cat "$ERRFILE")"
grep -q "REASON=quota-extrapolated-proceed" "$ERRFILE" \
  || fail "(e) with sonnet skipped, seven_day governs → must proceed; got: $(cat "$ERRFILE")"
pass "(e) id:c5ba — null seven_day_sonnet is SKIPPED in extrapolation, seven_day governs → proceeds (exit 0)"

# ── (e2) id:c5ba — skipping the null sonnet bucket must NOT disable the real gate: null
#        seven_day_sonnet but HIGH seven_day burn → still EXTRAPOLATED STOP (exit 3) on
#        seven_day. Proves the skip is bucket-scoped, not a blanket "ignore weekly". ────────
: >"$SAMPLES"
emit $((NOW-3900)) 12 70 null 2.0   # 65 min ago
emit $((NOW-300))  13 88 null 2.5   # 5 min ago — seven_day 70→88, ~18%/h → est ~89.5%+margin ≥ 90
rc="$(run_extrap)"
[[ "$rc" == "3" ]] || { cat "$ERRFILE"; fail "(e2) null sonnet + high seven_day must EXTRAPOLATE-STOP (exit 3), got $rc"; }
grep -q "REASON=quota-extrapolated-stop bucket=seven_day" "$ERRFILE" \
  || fail "(e2) real gate must still fire on seven_day when sonnet is skipped; got: $(cat "$ERRFILE")"
pass "(e2) id:c5ba — sonnet-skip is bucket-scoped: high seven_day still triggers exit 3"

echo "ALL PASS: quota-stop extrapolation fallback (id:0175 / routed:82e3 / id:c5ba)"
