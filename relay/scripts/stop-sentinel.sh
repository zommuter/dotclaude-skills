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
#   stop-sentinel.sh check [--path <file>] [--run <runId>]
#
# Scoping (id:cd94): with --run, `<path>.<runId>` (TARGETED, this run only) is checked first
# and the shared `<path>` (BROADCAST, any run) only if no targeted file exists. Without --run
# only the broadcast file is seen — unchanged legacy behaviour. A targeted sentinel for another
# run is a different filename and so can never be consumed here.
#
# Countdown UNIT (id:a615, 2026-08-26): N counts DISPATCH DECISIONS, not rounds. A round is
# unbounded in work — the id:8123 chain-end re-ask dispatches follow-on units without returning
# to the prelude — so a per-round countdown could be arbitrarily long or never reached at all
# (run relay-20260822-154630-17003: 14 dispatches, all round=1, sentinel never consumed).
# relay-loop.js therefore calls this script at the round prelude AND at every subsequent
# dispatch decision within the round, so each dispatch decision counts exactly one tick.
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
# at most once per STOP-CHECK POINT — the round prelude (step 8) and each subsequent
# dispatch decision inside the round (id:a615). Concurrent lanes must collapse onto ONE
# call (relay-loop.js's `stopCheckInFlight` memo does this) so a countdown is not
# double-decremented by a parallel wave.
set -euo pipefail

cmd="${1:-}"
[[ "$cmd" == "check" ]] || { echo "stop-sentinel.sh: usage: stop-sentinel.sh check [--path <file>] [--run <runId>]" >&2; exit 2; }
shift

path="${HOME}/.config/relay/STOP"
run=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) run="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    *) echo "stop-sentinel.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

log_path="${RELAY_STOP_SENTINEL_LOG:-$HOME/.claude/logs/relay-stop-sentinel.log}"

# --- id:cd94: TARGETED vs BROADCAST sentinel resolution ---------------------------------------
# A run passing --run <runId> looks for its OWN sentinel `<path>.<runId>` FIRST; only if that
# is absent does it consider the shared broadcast `<path>`. A targeted sentinel addressed to a
# DIFFERENT run is invisible here by construction (different filename), which is the whole
# point: before this, one global un-scoped file meant the first pool to reach a round boundary
# consumed the operator's stop and stopped ITSELF, while the pool the operator was aiming at
# ran on. Observed live 2026-07-31 (id:31ce): a killed lodelore run ate the stop at 17:54:39
# and retired at 17:55; the intended pool read stopRequested:false for all 8 of its rounds and
# kept working — including re-dispatching the very repo the operator was trying to protect.
scope="broadcast"
if [[ -n "$run" && -e "${path}.${run}" ]]; then
  path="${path}.${run}"
  scope="targeted"
fi

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
#
# ORDER MATTERS (id:cd94, second defect found while diagnosing id:31ce): the decision is
# LOGGED and EMITTED before the file is removed, and the removal is the LAST act and
# non-fatal. Previously the `rm` came FIRST, so any nonzero exit after it — while the
# caller `discover-prelude.sh:136` maps a nonzero exit to `{"stopRequested":false}` as a
# "fail-safe" — consumed the sentinel and reported no-stop: fail-safe in name, fail-OPEN
# for the stop, and undetectable afterwards because the sentinel is gone. Failing the
# other way round (sentinel survives, stop re-fires next round) is the safe direction:
# stopping twice is harmless, silently not stopping is what this whole item is about.
mkdir -p "$(dirname "$log_path")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "$ts consumed STOP sentinel path=$path scope=$scope run=${run:-<unscoped>} content=\"$content\"" >> "$log_path"
echo '{"stopRequested":true}'
rm -- "$path" || echo "stop-sentinel.sh: WARNING failed to remove $path — it will re-fire next round" >&2
exit 0
