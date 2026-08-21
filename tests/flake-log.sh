#!/usr/bin/env bash
# flake-log.sh — OBSERVE-FIRST instrument for ROADMAP id:7518 (parallel-suite flakiness).
#
# Runs the FULL suite once at a given parallel width and appends ONE JSONL row
# recording everything needed to diagnose the next flake from the record instead
# of from someone's memory:
#
#   ts, width, nproc, wall_s, pass, fail, xred,
#   failed[]           — the SET of tests that failed TOGETHER (not just the first)
#   load_before/after  — 1/5/15-min load averages (banked rule: never characterise a
#                        run as slow/flaky without recording load alongside it)
#   procs_before/after, fd_before/after, tmp_avail_kb, ulimit_n
#   log_path           — where the raw run output was kept for the failing runs
#
# Usage:
#   tests/flake-log.sh            # width = nproc
#   tests/flake-log.sh -j 1       # explicit width
#   tests/flake-log.sh -n 5 -j 8  # 5 consecutive runs at width 8
#
# The log lives OUTSIDE any repo: $FLAKE_LOG_DIR, default ~/.cache/dotclaude-flake.
# Raw output of FAILING runs is kept there too (passing runs' output is discarded —
# it is ~460 uninformative PASS lines).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGDIR="${FLAKE_LOG_DIR:-$HOME/.cache/dotclaude-flake}"
LOG="$LOGDIR/runs.jsonl"
mkdir -p -- "$LOGDIR"

runs=1
width=""
standalone=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -j)  width="${2-}"; shift 2 ;;
    -j*) width="${1#-j}"; shift ;;
    -n)  runs="${2-}"; shift 2 ;;
    -n*) runs="${1#-n}"; shift ;;
    -s)  standalone="${2-}"; shift 2 ;;   # re-run ONE test standalone, same row format
    *)   echo "flake-log.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
# stderr suppressed deliberately: a missing nproc is a benign "unknown core count".
ncpu="$(nproc 2>/dev/null || echo 1)"
[[ -n "$width" ]] || width="$ncpu"
mode="suite"
if [[ -n "$standalone" ]]; then mode="standalone"; width=1; fi

snap_load() { awk '{printf "%s,%s,%s", $1, $2, $3}' /proc/loadavg; }
snap_procs() { ls /proc | grep -c '^[0-9]\+$'; }
# System-wide open file descriptors (allocated), field 1 of file-nr.
snap_fd() { awk '{print $1}' /proc/sys/fs/file-nr; }

for ((r = 1; r <= runs; r++)); do
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  raw="$LOGDIR/run-$stamp-$mode-j$width.log"

  lb="$(snap_load)"; pb="$(snap_procs)"; fb="$(snap_fd)"
  t0="$EPOCHREALTIME"
  if [[ -n "$standalone" ]]; then
    ( cd "$ROOT" && bash tests/run-tests.sh -j 1 "$standalone" ) >"$raw" 2>&1
  else
    ( cd "$ROOT" && bash tests/run-tests.sh -j "$width" ) >"$raw" 2>&1
  fi
  rc=$?
  t1="$EPOCHREALTIME"
  la="$(snap_load)"; pa="$(snap_procs)"; fa="$(snap_fd)"

  wall="$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.1f", b-a}')"
  summary="$(grep -m1 '^summary: ' "$raw" || true)"
  pass="$(sed -n 's/^summary: \([0-9]*\) passed.*/\1/p' <<<"$summary")"
  fail="$(sed -n 's/^summary: .* \([0-9]*\) failed.*/\1/p' <<<"$summary")"
  xred="$(sed -n 's/^summary: .* \([0-9]*\) expected-red.*/\1/p' <<<"$summary")"
  # The runner prints every failing test on one "failed: a b c" line — that IS the
  # co-failure SET this instrument exists to capture.
  failed_line="$(head -1 < <(sed -n 's/^failed: //p' "$raw") )"
  tmp_kb="$(df -Pk "${TMPDIR:-/tmp}" | awk 'NR==2{print $4}')"

  # Keep the raw output for anything that failed, and for every standalone re-run
  # (that IS the evidence for acceptance clause 5). A passing full-suite run's output
  # is ~460 uninformative PASS lines — discard it.
  if [[ -z "$failed_line" && "$mode" == "suite" ]]; then
    rm -- "$raw"
    raw=""
  fi

  FAILED_LINE="$failed_line" LB="$lb" LA="$la" MODE="$mode" python3 - \
      "$LOG" "$stamp" "$width" "$ncpu" "$wall" "${pass:-}" "${fail:-}" "${xred:-}" \
      "$rc" "$pb" "$pa" "$fb" "$fa" "$tmp_kb" "$(ulimit -n)" "$raw" <<'PY'
import json, os, sys
(log, ts, width, ncpu, wall, p, f, x, rc,
 pb, pa, fb, fa, tmp_kb, ulimit_n, raw) = sys.argv[1:]
num = lambda v: int(v) if v.isdigit() else None
la = lambda e: [float(v) for v in os.environ[e].split(",")]
row = {
    "ts": ts, "mode": os.environ["MODE"],
    "width": int(width), "nproc": int(ncpu), "wall_s": float(wall),
    "pass": num(p), "fail": num(f), "xred": num(x), "rc": int(rc),
    "failed": os.environ["FAILED_LINE"].split(),
    "load_before": la("LB"), "load_after": la("LA"),
    "procs_before": int(pb), "procs_after": int(pa),
    "fd_before": int(fb), "fd_after": int(fa),
    "tmp_avail_kb": int(tmp_kb), "ulimit_n": ulimit_n,
    "raw_log": raw or None,
}
with open(log, "a") as fh:
    fh.write(json.dumps(row) + "\n")
print(json.dumps({k: row[k] for k in
                  ("ts", "mode", "width", "wall_s", "pass", "fail", "failed",
                   "load_before", "load_after")}))
PY
done

echo "flake-log: appended to $LOG"
