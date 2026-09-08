#!/usr/bin/env bash
# capped-run.sh — run a command under a HARD memory cap in its own cgroup scope, so a
# runaway mechanical recipe cannot take the machine down.  id:c057
#
# ADAPTED, with attribution, from ~/src/toesnail/docs/dreamed/capped.sh, which solved this
# first for capped "dreamed" Lean/search sessions. The reasoning below is carried over from
# there rather than re-derived, because it is the part that is easy to get wrong:
#
# Why not `nice`:      nice is CPU priority ONLY. It does nothing about memory, and a
#                      process that eats all RAM makes the machine unusable no matter how
#                      politely it is scheduled. `mechanical-daemon.service` sets `Nice=10`
#                      and that is why it was never protection.
# Why not `ulimit -v`: that caps ADDRESS SPACE. Anything that mmaps large read-only files
#                      (Mathlib .olean, a GGUF model weight file) needs a virtual-memory
#                      allowance far larger than its real usage, so a cap loose enough to
#                      let the process start is too loose to bound it, and one tight enough
#                      to bound it makes the process fail spuriously.
# What this does:      a systemd user scope with MemoryMax (a cgroup v2 RSS limit) and
#                      MemorySwapMax=0. On breach the kernel OOM-kills the processes INSIDE
#                      the scope and nothing else — the system stays responsive. CPUQuota
#                      bounds CPU too, and nice keeps it out of interactive work's way.
#
# WHY MemorySwapMax=0 IS THE LOAD-BEARING HALF, not MemoryMax:
#   Measured on zomni 2026-09-08 while planning this: 30 GB RAM, and 22.6 of 32 GB swap
#   ALREADY in use, load average ~16. A memory cap alone still lets a runaway thrash swap,
#   which is what actually makes the machine unusable — the OOM killer never fires because
#   the kernel keeps finding pages to evict. Denying swap to the scope converts a slow
#   machine-wide death into a fast, contained, local kill.
#
# SLICE: relay-mech.slice, deliberately NOT toesnail's dreamed.slice. A shared slice would
# put a dreaming Lean session and a 30B benchmark under ONE combined limit, so whichever
# started second would be killed for the first one's usage.
#
# FAILS CLOSED: if systemd-run is unavailable this REFUSES (exit 3) rather than falling back
# to a bare `bash -c`. A silent uncapped fallback would restore exactly the bug this exists
# to fix, and it would do so invisibly.
#
# EXIT 137 (or a "Killed" message) MEANS THE CAP FIRED. That is the guard working, not a bug
# in the command. A caller must report it as a cap kill, never as a flaky command.
# Exit 124 is the wall-clock timeout firing (GNU coreutils `timeout` convention).
#
# Usage:  capped-run.sh [-m MEM] [-c CPU%] [-t SECONDS] -- <command> [args...]
#   -m  memory cap, systemd syntax   (default $RELAY_MECH_MEM,  else 24G)
#   -c  CPU quota percent, 100=1core (default $RELAY_MECH_CPU,  else 200)
#   -t  wall-clock timeout seconds   (default $RELAY_MECH_TIMEOUT, else 3600)
set -euo pipefail

MEM="${RELAY_MECH_MEM:-24G}"
CPU="${RELAY_MECH_CPU:-200}"
TIMEOUT="${RELAY_MECH_TIMEOUT:-3600}"
SLICE="${RELAY_MECH_SLICE:-relay-mech.slice}"

usage() {
  echo "usage: $0 [-m MEM] [-c CPU%] [-t SECONDS] -- <command> [args...]" >&2
}

while getopts "m:c:t:h" opt; do
  case "$opt" in
    m) MEM=$OPTARG ;;
    c) CPU=$OPTARG ;;
    t) TIMEOUT=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ "${1:-}" = "--" ] && shift
[ $# -eq 0 ] && { echo "$0: no command given" >&2; usage; exit 2; }

case "$TIMEOUT" in
  ''|*[!0-9]*) echo "$0: -t must be a positive integer of seconds (got '$TIMEOUT')" >&2; exit 2 ;;
esac
[ "$TIMEOUT" -gt 0 ] || { echo "$0: -t must be > 0 (got '$TIMEOUT')" >&2; exit 2; }

if ! command -v systemd-run >/dev/null 2>&1; then
  echo "$0: systemd-run not available; REFUSING to run uncapped." >&2
  echo "$0: (a silent uncapped fallback is the bug this script exists to prevent)" >&2
  exit 3
fi

exec systemd-run --user --scope -q \
  --slice="$SLICE" \
  -p MemoryMax="$MEM" \
  -p MemorySwapMax=0 \
  -p CPUQuota="${CPU}%" \
  -- nice -n 19 timeout "$TIMEOUT" "$@"
