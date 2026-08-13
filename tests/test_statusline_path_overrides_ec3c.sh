#!/usr/bin/env bash
# roadmap:ec3c
#
# RED spec for ROADMAP id:ec3c — statusline-command.sh hardcodes its four usage-state paths
# under /tmp (USAGE_CACHE/USAGE_HISTORY/USAGE_BACKOFF/USAGE_LOCK), which `HOME` cannot
# redirect, so `make test` races the developer's own live-session statusline writing those
# same paths. The fix: give each path an env override (CLAUDE_USAGE_CACHE, CLAUDE_USAGE_HISTORY,
# CLAUDE_USAGE_BACKOFF, CLAUDE_USAGE_LOCK), defaulting to today's /tmp literal so live behaviour
# is unchanged, and let a test point them into its own mktemp -d.
#
# How this stays hermetic AND network-free: a cache file whose mtime is NOW has CACHE_AGE < 60,
# so statusline-command.sh's `if [ $CACHE_AGE -ge 60 ]` fetch block is skipped entirely — no
# curl, no shared-state write — and SESSION_PCT/WEEKLY_PCT are read straight from the cache via
# `jq .five_hour.utilization / .seven_day.utilization`. We seed the OVERRIDE cache with two
# distinctive utilizations and assert they render. If the overrides are IGNORED (the defect),
# the script reads /tmp/claude-usage-cache.json instead — which never carries our sentinels —
# so the assertion fails RED. Once the overrides are honoured it renders "63%"/"71%" GREEN.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SL="$ROOT/statusline/statusline-command.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$SL" ]] || fail "statusline-command.sh not executable at $SL"
command -v jq >/dev/null || fail "jq required"

tmp="$(mktemp -d)"
trap 'rm -r -- "$tmp"' EXIT

# A FRESH override cache (mtime = now) with two distinctive utilizations. resets_at far in the
# future so calc_window_stats produces a stable cooldown and never divides oddly.
cat > "$tmp/cache" <<'JSON'
{
  "five_hour":  {"utilization": 63, "resets_at": "2099-01-01T00:00:00Z"},
  "seven_day":  {"utilization": 71, "resets_at": "2099-01-01T00:00:00Z"}
}
JSON

# HOME into the sandbox so no real OAuth token is read (keeps even the RED-state run from
# authenticating against the live API); stdin is a minimal session JSON.
out="$(printf '%s' '{}' | \
  HOME="$tmp/home" \
  CLAUDE_USAGE_CACHE="$tmp/cache" \
  CLAUDE_USAGE_HISTORY="$tmp/history" \
  CLAUDE_USAGE_BACKOFF="$tmp/backoff" \
  CLAUDE_USAGE_LOCK="$tmp/lock" \
  bash "$SL" 2>/dev/null)"   # 2>/dev/null: statusline logs cosmetic warnings to stderr; only stdout render is asserted (id:4347)

[[ -n "$out" ]] || fail "statusline produced no stdout"

printf '%s' "$out" | grep -q '63%' \
  || fail "session utilization 63% from the OVERRIDE cache did not render — CLAUDE_USAGE_CACHE is not honoured (id:ec3c)"
pass "CLAUDE_USAGE_CACHE override is honoured (session 63% rendered)"

printf '%s' "$out" | grep -q '71%' \
  || fail "weekly utilization 71% from the OVERRIDE cache did not render — CLAUDE_USAGE_CACHE is not honoured (id:ec3c)"
pass "weekly 71% rendered from the override cache"

# Hermeticity proof: with a fresh override cache the run must not have created the DEFAULT
# /tmp state files on our behalf. We cannot assert on pre-existing live files, but the lock
# and backoff belong to the fetch path, which a fresh cache skips — so the OVERRIDE lock/backoff
# must stay absent (no fetch happened) and no default path was written by THIS invocation.
[[ ! -e "$tmp/lock" ]] || fail "override lock was created — the fresh-cache fast path was not taken"
pass "fresh override cache skipped the fetch path (no override lock written)"

echo "ALL PASS"
