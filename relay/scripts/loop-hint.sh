#!/usr/bin/env bash
# loop-hint.sh — best-effort "wrap this in /loop for unattended resilience" reminder
# for the /relay front door (default autonomous pool mode).
#
# Prints a one-line tip to stdout ONLY when this run looks like a STANDALONE manual
# invocation; stays SILENT when a recent prior run suggests we are already inside a
# /loop (back-to-back ticks). Detection is purely time-since-last-run: a manual
# `/relay --afk` and a loop-driven one are otherwise indistinguishable (identical
# argv, no env marker, the built-in /loop sets nothing observable). So:
#   gap since last run <= GAP  → looks like a loop tick → SUPPRESS (print nothing)
#   gap > GAP (or first run)   → looks standalone        → print the tip
#
# Rationale for the tip: a single `/relay` invocation is resumable but NOT self-
# restarting — an API outage that trips a stop path (total discovery failure on
# round>=2, or a quota-gate agent death) ends the run early and it will NOT resume
# until re-invoked. A FIXED-INTERVAL `/loop` re-fires on independent ticks, so a
# missed tick during an outage is recovered by the next one (a self-chained wakeup
# would instead break permanently if the outage hit its reschedule moment).
#
# Never fails the caller: all state writes are best-effort, exit is always 0.
set -uo pipefail

STATE_DIR="${RELAY_STATE_DIR:-$HOME/.config/relay}"
STAMP="$STATE_DIR/.relay-last-run"
GAP="${RELAY_LOOP_HINT_GAP:-2700}"   # seconds; <= GAP looks loop-driven → suppress
                                     # default 2700s (45m) > a typical 20-30m loop tick

now="$(date +%s 2>/dev/null || echo 0)"
prev=""
[[ -f "$STAMP" ]] && prev="$(cat "$STAMP" 2>/dev/null || true)"

mkdir -p "$STATE_DIR" 2>/dev/null || true
printf '%s\n' "$now" > "$STAMP" 2>/dev/null || true

# Suppress when a recent prior run is within GAP (looks like a /loop tick).
if [[ -n "$prev" && "$prev" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]]; then
  delta=$(( now - prev ))
  if (( delta >= 0 && delta <= GAP )); then
    exit 0   # likely loop-driven → no reminder
  fi
fi

cat <<'TIP'
💡 Going to be away a while? A single /relay run is resumable but not self-restarting —
   an API outage can stop it early and it won't resume on its own. For unattended
   multi-hour resilience, wrap it in a fixed-interval loop:
       /loop 20m /relay --afk
   Independent ticks: each resumes from preserved worktrees/checkpoints, and a tick
   missed during an outage is recovered by the next one.
TIP
exit 0
