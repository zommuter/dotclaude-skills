#!/usr/bin/env bash
# statusline/check-deps.sh — verify the statusbar's external CLI dependencies, classified by
# functional severity. Run by `make install-statusline` (and thus `make install`).
#   CRITICAL  → exit 1 (the statusbar is non-functional without it; install then re-run)
#   OPTIONAL  → WARN to stderr, exit 0 (each only degrades ONE feature; the bar still renders)
# Pure check, no side effects. Robust under a stripped PATH (uses only builtins + command -v).

set -uo pipefail

# CRITICAL: jq parses every stdin JSON field (model/cost/context) + the usage cache — without
# it the statusbar produces essentially nothing.
crit_missing=()
for t in jq; do command -v "$t" >/dev/null 2>&1 || crit_missing+=("$t"); done

# OPTIONAL: each degrades exactly one feature, gracefully (no crash; raw values still show).
declare -A why=(
  [bc]="usage %% gradient colors + stale-cache extrapolation"
  [curl]="live usage fetch (falls back to cached/stale numbers)"
  [sha1sum]="host/user/dir hash colors"
)
opt_missing=()
for t in bc curl sha1sum; do command -v "$t" >/dev/null 2>&1 || opt_missing+=("$t"); done
# GNU coreutils: the script uses `stat -c %Y` and `date +%s`. date +%s is universal; BSD stat
# lacks -c (cache-age detection degrades → always-refresh).
if ! command -v stat >/dev/null 2>&1; then
  opt_missing+=("stat"); why[stat]="cache-age detection (no stat at all)"
elif ! stat -c %Y . >/dev/null 2>&1; then
  opt_missing+=("stat(GNU -c)"); why["stat(GNU -c)"]="cache-age detection (BSD stat lacks -c)"
fi

rc=0
if ((${#crit_missing[@]})); then
  echo "statusline: ERROR — missing CRITICAL dependency: ${crit_missing[*]}. The statusbar will not function until it is installed (e.g. 'pamac install jq')." >&2
  rc=1
fi
for t in "${opt_missing[@]}"; do
  echo "statusline: WARN — '$t' missing → degrades ${why[$t]:-a feature}; the statusbar still renders without it." >&2
done
[ $rc -eq 0 ] && [ ${#opt_missing[@]} -eq 0 ] && echo "statusline: all dependencies present."
exit $rc
