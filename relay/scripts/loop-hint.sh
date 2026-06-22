#!/usr/bin/env bash
# loop-hint.sh — best-effort "/loop for early-exit retry" reminder for the /relay
# front door (default autonomous pool mode).
#
# Prints a tip to stdout ONLY when this run looks like a STANDALONE manual
# invocation; stays SILENT when a recent prior run suggests we are already inside a
# /loop (back-to-back ticks). Detection is purely time-since-last-run: a manual
# `/relay --afk` and a loop-driven one are otherwise indistinguishable (identical
# argv, no env marker, the built-in /loop sets nothing observable). So:
#   gap since last run <= GAP  → looks like a loop tick → SUPPRESS (print nothing)
#   gap > GAP (or first run)   → looks standalone        → print the tip
#
# IMPORTANT — what /loop does and does NOT do:
#   /loop (and an in-session cron) runs within the SAME Claude session. It dies with
#   the session if the session is killed, the process crashes, or an API outage ends
#   the process. It is NOT a watchdog and does NOT give outage/session-kill resilience.
#
#   What /loop IS good for: relay's own early-exit paths (quota/seatbelt) that stop
#   the relay script but leave the Claude session alive. Within a live session, a
#   fixed-interval /loop re-fires on each tick and resumes from the preserved
#   worktrees/checkpoints — useful for catching quota-stop early exits.
#
#   For true outage-resilience (session kill / process death), a separate watchdog is
#   needed (id:98f0); see docs/meeting-notes/2026-06-22-1546-relay-outage-resilience.md.
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
💡 A single /relay run stops on an early-exit (quota/seatbelt) and won't resume on its
   own. Within a live session, a fixed-interval loop retries those early exits:
       /loop 20m /relay --afk
   Each tick resumes from preserved worktrees/checkpoints.
   Scope: /loop stays within the same session — if the session is killed (API outage,
   process death), /loop dies with it. Watchdog for that case: id:98f0.
TIP
exit 0
