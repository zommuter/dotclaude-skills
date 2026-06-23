#!/usr/bin/env bash
# quota-stop.sh — tier-aware quota threshold check for relay-loop.js
#
# Usage:
#   quota-stop.sh [--tier sonnet|strong] [--agents N] [--wall S]
#
# Exit codes:
#   0 = below threshold (safe to continue)
#   1 = at/above threshold, or seatbelt triggered (stop)
#   2 = stale/missing cache or missing/invalid key (uncertain, stop)
#
# Env:
#   RELAY_QUOTA_THRESHOLD  threshold fraction, default 0.90 (= 90%)
#   USAGE_CACHE            path to cache JSON, default /tmp/claude-usage-cache.json
#
# Scale note: the live cache (written by statusline/statusline-command.sh from
# /api/oauth/usage) stores `.utilization` as a 0-100 PERCENT (e.g. 37.0 = 37%).
# RELAY_QUOTA_THRESHOLD stays a 0-1 fraction for ergonomic overrides; the
# comparison converts internally (val >= threshold*100).
set -euo pipefail

TIER="sonnet"
AGENTS=0
WALL=0
THRESHOLD="${RELAY_QUOTA_THRESHOLD:-0.90}"
USAGE_CACHE="${USAGE_CACHE:-/tmp/claude-usage-cache.json}"
# Credentials for the self-refresh below. Tests point this at a tokenless path to keep
# the stale-cache path hermetic (no network).
USAGE_CREDS="${USAGE_CREDS:-$HOME/.claude/.credentials.json}"
STALE_SECS=600
# Margin for stale-but-safe check (points on 0-100 scale): if every checked bucket's
# last-known util is below (bucket_threshold × 100 − MARGIN), proceed on the stale cache.
MARGIN="${RELAY_QUOTA_STALE_MARGIN:-30}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)   TIER="$2";   shift 2 ;;
    --agents) AGENTS="$2"; shift 2 ;;
    --wall)   WALL="$2";   shift 2 ;;
    *) echo "quota-stop: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# Seatbelt: hard limits regardless of cache
if [[ "$AGENTS" -ge 200 || "$WALL" -ge 7200 ]]; then
  echo "quota-stop: seatbelt triggered (agents=$AGENTS wall=${WALL}s)" >&2
  exit 1
fi

# Time-decaying cap for the 7-day buckets (autonomous relay, user directive 2026-06-13):
# when RELAY_QUOTA_DECAY_7D is set as "START:END" fractions, the seven_day and
# seven_day_sonnet thresholds linearly interpolate from START (at the rolling 7-day
# window's open) to END (at its reset), tracking how far into the window we are via
# seven_day.resets_at. Recomputed each call, so a long self-looping run TIGHTENS as its
# window ages (e.g. 0.70 day-1 → 0.10 last-day; ~0.53 at 2/7 elapsed). 5h bucket is never
# decayed. Falls back to THRESHOLD if resets_at is missing/unparseable.
decay_threshold() {
  local start end reset now
  IFS=: read -r start end <<< "${RELAY_QUOTA_DECAY_7D}"
  reset=$(jq -r '.seven_day.resets_at // empty' "$USAGE_CACHE" 2>/dev/null)
  [[ -z "$reset" ]] && { printf '%s' "$THRESHOLD"; return; }
  reset=$(date -d "$reset" +%s 2>/dev/null) || { printf '%s' "$THRESHOLD"; return; }
  now=$(date +%s)
  awk -v s="$start" -v e="$end" -v r="$reset" -v n="$now" \
    'BEGIN { w=7*86400; d=1-(r-n)/w; if(d<0)d=0; if(d>1)d=1; printf "%.4f", s+(e-s)*d }'
}

# Per-bucket threshold: explicit RELAY_QUOTA_THRESHOLD_<BUCKET> wins; else for the two
# 7-day buckets a RELAY_QUOTA_DECAY_7D time-decay (if set); else the general THRESHOLD.
# Default (no env) = THRESHOLD, so behaviour is unchanged unless a caller opts in.
bucket_threshold() {
  local key="$1" envname val
  envname="RELAY_QUOTA_THRESHOLD_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  val="${!envname:-}"
  if [[ -n "$val" ]]; then printf '%s' "$val"; return; fi
  if [[ -n "${RELAY_QUOTA_DECAY_7D:-}" && ( "$key" == "seven_day" || "$key" == "seven_day_sonnet" ) ]]; then
    decay_threshold; return
  fi
  printf '%s' "$THRESHOLD"
}

# Cache presence
if [[ ! -f "$USAGE_CACHE" ]]; then
  echo "quota-stop: cache missing: $USAGE_CACHE" >&2
  exit 2
fi

# Cache freshness (mtime > 10 min → uncertain)
NOW=$(date +%s)
MTIME=$(stat -c %Y "$USAGE_CACHE" 2>/dev/null) || { echo "quota-stop: cannot stat $USAGE_CACHE" >&2; exit 2; }
AGE=$(( NOW - MTIME ))
if [[ "$AGE" -gt "$STALE_SECS" ]]; then
  # Self-refresh: in unattended background pool runs there's no statusline render to keep
  # the cache fresh, so it goes stale mid-run and we'd false-stop a healthy pool. Refresh
  # it ourselves from the same /api/oauth/usage endpoint the statusline uses, under a flock
  # so concurrent quota-gates don't stampede the token's ~5-req limit. If refresh fails,
  # stay conservative and stop (exit 2). USAGE_CREDS tokenless ⟹ skip (hermetic in tests).
  TOK=$(jq -r '.claudeAiOauth.accessToken // empty' "$USAGE_CREDS" 2>/dev/null || true)
  if [[ -n "$TOK" ]]; then
    (
      flock -x -w 10 8 || exit 1
      M2=$(stat -c %Y "$USAGE_CACHE" 2>/dev/null || echo 0)
      if [[ $(( $(date +%s) - M2 )) -gt 60 ]]; then   # someone else may have just refreshed
        if curl -sf --max-time 8 -o "$USAGE_CACHE.qs.tmp" \
             -H "Authorization: Bearer $TOK" -H "anthropic-beta: oauth-2025-04-20" \
             "https://api.anthropic.com/api/oauth/usage" 2>/dev/null && [[ -s "$USAGE_CACHE.qs.tmp" ]]; then
          mv "$USAGE_CACHE.qs.tmp" "$USAGE_CACHE"
        else
          rm -f "$USAGE_CACHE.qs.tmp"
        fi
      fi
    ) 8>"${USAGE_CACHE}.qs.lock"
    MTIME=$(stat -c %Y "$USAGE_CACHE" 2>/dev/null || echo 0)
    AGE=$(( $(date +%s) - MTIME ))
  fi
  if [[ "$AGE" -gt "$STALE_SECS" ]]; then
    # Margin-aware staleness (id:1d64): a stale reading is only dangerous if we might have
    # CROSSED the threshold since it was taken. Check every bucket for this tier: if each one
    # is below (bucket_threshold × 100 − MARGIN), the headroom is large enough that we
    # proceed on the stale-but-safe last known values and let check_key do the real gate.
    # A MISSING bucket → treat as unsafe → keep exit 2.
    case "$TIER" in
      sonnet) _stale_buckets="seven_day_sonnet five_hour seven_day" ;;
      strong) _stale_buckets="five_hour seven_day" ;;
      *)      _stale_buckets="" ;;
    esac
    _stale_safe=1  # assume safe until proven otherwise
    for _b in $_stale_buckets; do
      _u=$(jq -r ".${_b}.utilization // empty" "$USAGE_CACHE" 2>/dev/null)
      if [[ -z "$_u" ]]; then
        _stale_safe=0; break  # missing bucket → unsafe
      fi
      _t="$(bucket_threshold "$_b")"
      # safe if util < threshold*100 − MARGIN
      if ! awk -v u="$_u" -v t="$_t" -v m="$MARGIN" 'BEGIN { exit (u < t*100 - m) ? 0 : 1 }'; then
        _stale_safe=0; break  # within margin of threshold → unsafe
      fi
    done
    if [[ "$_stale_safe" -eq 1 ]]; then
      echo "quota-stop: proceeding on stale-but-safe cache (margin ${MARGIN})" >&2
      # fall through to the normal check_key loop below
    else
      echo "quota-stop: cache stale (${AGE}s > ${STALE_SECS}s limit) and self-refresh unavailable/failed" >&2
      exit 2
    fi
  else
    echo "quota-stop: self-refreshed stale cache" >&2
  fi
fi

# Burnup sampling (id:cd19): persist a time-series sample to the quota-samples JSONL so
# relay-burn.sh report can answer "$/hour, %/hour, how much did this run burn?" — the data
# for evaluating Max x20/x5/Pro tiers. quota-stop already reads+refreshes the cache on every
# gate check, so this is the natural emit point. Best-effort & non-fatal: a sampling failure
# must NEVER change the quota decision. Gated on RELAY_RUN_ID so it fires only inside a real
# relay run (ties each sample to its run for per-run attribution, and keeps quota-stop's own
# tests hermetic — they never set RELAY_RUN_ID, so nothing is written under ~/.config).
if [[ -n "${RELAY_RUN_ID:-}" ]]; then
  USAGE_CACHE="$USAGE_CACHE" "$(dirname "$0")/relay-burn.sh" sample 2>/dev/null || true
fi

# check_key KEY — exit 1 if at/above that bucket's threshold; exit 2 if key missing; else returns
check_key() {
  local key="$1"
  local val t
  val=$(jq -r ".${key}.utilization // empty" "$USAGE_CACHE" 2>/dev/null)
  if [[ -z "$val" ]]; then
    echo "quota-stop: key '$key' missing in cache" >&2
    exit 2
  fi
  t="$(bucket_threshold "$key")"
  # Cache utilization is 0-100 percent; threshold is a 0-1 fraction.
  if awk -v v="$val" -v t="$t" 'BEGIN { exit (v >= t * 100) ? 0 : 1 }'; then
    echo "quota-stop: $key=$val% >= threshold $t (tier=$TIER)" >&2
    exit 1
  fi
}

case "$TIER" in
  sonnet)
    check_key seven_day_sonnet
    check_key five_hour
    check_key seven_day
    ;;
  strong)
    check_key five_hour
    check_key seven_day
    ;;
  *)
    echo "quota-stop: unknown tier '$TIER' (expected sonnet|strong)" >&2
    exit 2
    ;;
esac

exit 0
