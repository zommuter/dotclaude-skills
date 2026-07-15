#!/usr/bin/env bash
# stop-sentinel.sh (id:482d) — deterministic STOP-sentinel check/countdown/consume,
# collapsing discover-prelude step 8 (relay-loop.js) into ONE atomic script call.
#
# WHY (TODO id:482d, observed 2026-07-01 ~23:27): the check/countdown/consume logic
# lived as prose instruction 8 of the prelude prompt, so the `rm` of a fired STOP
# landed at whatever point the agent reached it — a fired user-stop was observed
# still on disk minutes after the workflow returned, a hazard window for a next pool
# launched in that lag to be false-stopped. Collapsing the whole step into one
# script call structurally dissolves the timing-variance class; the consume log is
# the observe-instrumentation the item's OBSERVE downgrade asked for.
#
# Usage:
#   stop-sentinel.sh check [--path <file>]
#
# Semantics (VERBATIM prelude step 8):
#   file absent                          -> {"stopRequested":false}
#   trimmed content a positive integer N>=1 -> write N-1 back, {"stopRequested":false}
#   anything else (empty/non-numeric/"0"/negative) -> remove the file, {"stopRequested":true}
#     and append ONE ISO-8601-timestamped line to the consume log.
#
# Env:
#   RELAY_STOP_SENTINEL_LOG   override the consume-log path
#                             (default ~/.claude/logs/relay-stop-sentinel.log)
#
# This is the ONLY actor that writes/removes the sentinel; callers must invoke it
# at most once per round (prelude step 8 contract, unchanged).
set -euo pipefail

cmd="${1:-}"
[[ "$cmd" == "check" ]] || { echo "stop-sentinel.sh: usage: stop-sentinel.sh check [--path <file>]" >&2; exit 2; }
shift

path="${HOME}/.config/relay/STOP"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) path="$2"; shift 2 ;;
    *) echo "stop-sentinel.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

log_path="${RELAY_STOP_SENTINEL_LOG:-$HOME/.claude/logs/relay-stop-sentinel.log}"

if [[ ! -e "$path" ]]; then
  echo '{"stopRequested":false}'
  exit 0
fi

content="$(cat "$path" 2>/dev/null || true)"
trimmed="$(printf '%s' "$content" | tr -d '[:space:]')"

# Positive integer N>=1 -> countdown: decrement and keep the file, no stop this round.
if [[ "$trimmed" =~ ^[0-9]+$ ]] && [[ "$trimmed" =~ ^[1-9] ]]; then
  n=$((10#$trimmed))
  printf '%s' "$((n - 1))" > "$path"
  echo '{"stopRequested":false}'
  exit 0
fi

# Anything else (empty / non-numeric / "0" / negative) -> consume + stop.
# ($path exists here: the file-absent case returned {stopRequested:false} earlier.)
rm -- "$path"
mkdir -p "$(dirname "$log_path")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "$ts consumed STOP sentinel path=$path content=\"$content\"" >> "$log_path"
echo '{"stopRequested":true}'
