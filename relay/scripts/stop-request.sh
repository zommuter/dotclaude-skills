#!/usr/bin/env bash
# stop-request.sh (id:cd94) — the WRITE side of the graceful-stop sentinel: pick WHICH live
# pool to stop, and write a sentinel addressed to it.
#
# WHY: `/relay stop` used to be `: > ~/.config/relay/STOP` — one global un-scoped file. With
# more than one pool live (the NORMAL case: id:11c6's singleton guard exempts --afk and every
# directed/scoped mode), whichever pool reached a round boundary first consumed the operator's
# stop and stopped ITSELF, while the pool the operator was aiming at ran on. Observed live
# 2026-07-31 (id:31ce): a killed lodelore run ate the stop at 17:54:39 and retired at 17:55;
# the intended pool logged stopRequested:false for all 8 of its rounds and kept dispatching for
# another 4 hours, re-working the very repo the operator was protecting.
#
# The read side is stop-sentinel.sh --run (targeted `<path>.<runId>` beats broadcast `<path>`).
# Live runs come from the EXISTING heartbeat registry (heartbeat.sh live-runs) — no new liveness
# mechanism, no ~/src glob, no pid guessing ([[claim-pid-is-not-liveness]]).
#
# Usage:
#   stop-request.sh [--after N] [--run <runId>] [--all] [--path <file>] [--list]
#
#   (no args)      exactly one live pool  -> write its targeted sentinel, print the runId
#                  zero live pools        -> LOUD notice, exit 3, write NOTHING
#                  two or more live pools -> LOUD list, exit 4, write NOTHING (ambiguous:
#                                            re-run with --run <runId> or --all)
#   --run <runId>  address that run explicitly (must be live, else exit 3)
#   --all          write the BROADCAST sentinel (stop whichever pool sees it first) — the
#                  legacy behaviour, now opt-in and named rather than the silent default
#   --after N      sentinel content N (countdown: stop after N more rounds) instead of empty
#   --list         print live pools, write nothing (exit 0)
#
# Refusing on ambiguity is the point: a stop that silently picks a pool is what id:31ce was.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEARTBEAT_SH="$SCRIPT_DIR/heartbeat.sh"

path="${RELAY_STOP_PATH:-$HOME/.config/relay/STOP}"
after=""
want_run=""
broadcast=0
list_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --after) after="$2"; shift 2 ;;
    --run)   want_run="$2"; shift 2 ;;
    --all)   broadcast=1; shift ;;
    --path)  path="$2"; shift 2 ;;
    --list)  list_only=1; shift ;;
    *) echo "stop-request.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "$after" ]] && ! [[ "$after" =~ ^[1-9][0-9]*$ ]]; then
  echo "stop-request.sh: --after expects a positive integer, got '$after'" >&2
  exit 2
fi

# --- live pools (excluding the non-pool discovery-producer daemon) ---------------------------
# heartbeat.sh live-runs emits one JSON object per live marker. discovery-producer is a systemd
# timer unit (discover-repos-mechanical.sh), NOT a pool — it never reads the sentinel, so
# offering it as a stop target would be a lie.
live_runs() {
  [[ -x "$HEARTBEAT_SH" ]] || return 0
  "$HEARTBEAT_SH" live-runs 2>/dev/null \
    | python3 -c '
import json,sys
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: o=json.loads(line)
    except ValueError: continue
    r=o.get("runId","")
    if r and r!="discovery-producer": print(r)
'
}

mapfile -t RUNS < <(live_runs)

if [[ $list_only -eq 1 ]]; then
  if [[ ${#RUNS[@]} -eq 0 ]]; then echo "no live relay pools"; else printf '%s\n' "${RUNS[@]}"; fi
  exit 0
fi

write_sentinel() {  # write_sentinel <target-file>
  local f="$1"
  mkdir -p "$(dirname "$f")"
  if [[ -n "$after" ]]; then printf '%s' "$after" > "$f"; else : > "$f"; fi
}

if [[ $broadcast -eq 1 ]]; then
  write_sentinel "$path"
  echo "wrote BROADCAST stop sentinel: $path${after:+ (after $after rounds)}"
  echo "  NOTE: a broadcast stop is consumed by the FIRST pool to reach a round boundary —" >&2
  echo "  with ${#RUNS[@]} pool(s) live it is not aimable. Use --run <runId> to target one." >&2
  exit 0
fi

if [[ -n "$want_run" ]]; then
  hit=0
  for r in "${RUNS[@]:-}"; do [[ "$r" == "$want_run" ]] && hit=1; done
  if [[ $hit -eq 0 ]]; then
    echo "stop-request.sh: '$want_run' is not a live pool. Live pools:" >&2
    if [[ ${#RUNS[@]} -eq 0 ]]; then echo "  (none)" >&2; else printf '  %s\n' "${RUNS[@]}" >&2; fi
    exit 3
  fi
  write_sentinel "${path}.${want_run}"
  echo "wrote TARGETED stop sentinel for $want_run: ${path}.${want_run}${after:+ (after $after rounds)}"
  exit 0
fi

case ${#RUNS[@]} in
  0)
    echo "stop-request.sh: no live relay pool — nothing to stop; wrote NOTHING." >&2
    echo "  (A sentinel left on disk with no pool running would be consumed by the NEXT" >&2
    echo "   pool launched, false-stopping it.)" >&2
    exit 3
    ;;
  1)
    write_sentinel "${path}.${RUNS[0]}"
    echo "wrote TARGETED stop sentinel for ${RUNS[0]}: ${path}.${RUNS[0]}${after:+ (after $after rounds)}"
    exit 0
    ;;
  *)
    echo "stop-request.sh: ${#RUNS[@]} live pools — REFUSING to guess which one to stop:" >&2
    printf '  %s\n' "${RUNS[@]}" >&2
    echo "  Re-run with --run <runId> to target one, or --all to broadcast." >&2
    exit 4
    ;;
esac
