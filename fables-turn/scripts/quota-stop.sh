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
    echo "quota-stop: cache stale (${AGE}s > ${STALE_SECS}s limit) and self-refresh unavailable/failed" >&2
    exit 2
  fi
  echo "quota-stop: self-refreshed stale cache" >&2
fi

# Per-bucket threshold override: RELAY_QUOTA_THRESHOLD_<BUCKET_UPPER> (e.g.
# RELAY_QUOTA_THRESHOLD_SEVEN_DAY=0.50) takes precedence over the general THRESHOLD
# for that bucket only. Lets a caller cap the long-window buckets tighter than the
# 5h bucket — e.g. "use most of the 5h window but never exceed 50% of 7d/Sonnet"
# (budget-campaign governor, 2026-06-13). Default = general THRESHOLD, so behaviour is
# unchanged unless an override is set.
bucket_threshold() {
  local key="$1" envname val
  envname="RELAY_QUOTA_THRESHOLD_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  val="${!envname:-}"
  if [[ -n "$val" ]]; then printf '%s' "$val"; else printf '%s' "$THRESHOLD"; fi
}

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
