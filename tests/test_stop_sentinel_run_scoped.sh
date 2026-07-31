#!/usr/bin/env bash
# Defect-fix test (no roadmap: header — failures always count).
#
# id:cd94 — a `/relay stop` must be AIMABLE at one pool. Before this, the sentinel was a
# single un-scoped global file, so with >1 live pool (the NORMAL case: id:11c6's singleton
# guard exempts --afk and every directed/scoped mode) whichever pool reached a round boundary
# first consumed the operator's stop and stopped ITSELF, while the intended pool ran on.
#
# Observed live 2026-07-31 (id:31ce): a killed lodelore run consumed the stop at 17:54:39 and
# retired at 17:55; the intended pool logged stopRequested:false for all 8 of its rounds and
# kept dispatching for another 4 hours — re-working the very repo the operator was protecting.
#
# Also covers the second, independent defect found in the same diagnosis: the consume used to
# `rm` BEFORE logging/emitting, so any later nonzero exit consumed the sentinel while
# discover-prelude.sh's `|| stopRequested:false` fallback reported no-stop.
#
# Hermetic: mktemp sentinel + log paths, no ~/.config touch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SENTINEL_SH="$REPO_ROOT/relay/scripts/stop-sentinel.sh"

pass=0; fail=0
ok() { echo "  PASS: $1"; pass=$((pass+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
stopfile="$tmpdir/STOP"
logfile="$tmpdir/consume.log"

[[ -x "$SENTINEL_SH" ]] || { echo "FAIL: $SENTINEL_SH missing or not executable"; exit 1; }

check() {  # check <runId|""> → stdout JSON
  local r="$1"; shift || true
  if [[ -n "$r" ]]; then
    RELAY_STOP_SENTINEL_LOG="$logfile" "$SENTINEL_SH" check --path "$stopfile" --run "$r"
  else
    RELAY_STOP_SENTINEL_LOG="$logfile" "$SENTINEL_SH" check --path "$stopfile"
  fi
}
field() { python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2]))' "$1" "$2"; }

RUN_A="relay-20260731-174550-21952"
RUN_B="relay-20260731-164158-16320"

# ── Test 1: a TARGETED sentinel is invisible to a different run ───────────────
echo "Test 1: targeted sentinel is not stealable"
: > "${stopfile}.${RUN_A}"
out="$(check "$RUN_B")"
if [[ "$(field "$out" stopRequested)" == "False" ]]; then
  ok "run B does not see run A's targeted sentinel"
else
  fail_msg "run B consumed run A's targeted sentinel (the id:31ce steal)"
fi
if [[ -e "${stopfile}.${RUN_A}" ]]; then
  ok "run A's sentinel survives run B's check"
else
  fail_msg "run B DELETED run A's sentinel"
fi

# ── Test 2: the addressed run does consume its own ───────────────────────────
echo "Test 2: targeted sentinel fires for its own run"
out="$(check "$RUN_A")"
if [[ "$(field "$out" stopRequested)" == "True" ]]; then
  ok "run A consumes its own targeted sentinel"
else
  fail_msg "run A did not fire on its own targeted sentinel"
fi
[[ -e "${stopfile}.${RUN_A}" ]] && fail_msg "targeted sentinel not consumed" || ok "targeted sentinel consumed"

# ── Test 3: the consume log records WHO consumed it ──────────────────────────
echo "Test 3: consume log identifies the consumer"
if grep -q "run=${RUN_A}" "$logfile"; then
  ok "consume line carries run=<runId>"
else
  fail_msg "consume line lacks run=<runId> — the log cannot say which pool stopped"
fi
if grep -q 'scope=targeted' "$logfile"; then
  ok "consume line carries scope=targeted"
else
  fail_msg "consume line lacks scope="
fi

# ── Test 4: broadcast still works, for any run and for no run ────────────────
echo "Test 4: broadcast sentinel retained"
: > "$stopfile"
out="$(check "$RUN_B")"
if [[ "$(field "$out" stopRequested)" == "True" ]]; then
  ok "broadcast sentinel fires for an arbitrary run"
else
  fail_msg "broadcast sentinel did not fire"
fi
: > "$stopfile"
out="$(check "")"
if [[ "$(field "$out" stopRequested)" == "True" ]]; then
  ok "broadcast fires with no --run (legacy callers unchanged)"
else
  fail_msg "legacy no---run path regressed"
fi

# ── Test 5: targeted takes precedence over broadcast ─────────────────────────
echo "Test 5: targeted wins over broadcast"
: > "$stopfile"
: > "${stopfile}.${RUN_A}"
out="$(check "$RUN_A")"
if [[ "$(field "$out" stopRequested)" == "True" ]] && [[ ! -e "${stopfile}.${RUN_A}" ]] && [[ -e "$stopfile" ]]; then
  ok "targeted consumed, broadcast left for the other pools"
else
  fail_msg "targeted/broadcast precedence wrong (broadcast must survive)"
fi
rm -f -- "$stopfile"

# ── Test 6: consume is the LAST act — log+emit precede the rm ────────────────
# Assert on source order rather than simulating a mid-script failure: the invariant is
# structural, and a reordering regression is exactly what this guards.
echo "Test 6: rm ordered after the log/emit"
rm_line="$(grep -n '^rm -- "\$path"' "$SENTINEL_SH" | tail -1 | cut -d: -f1)"
log_line="$(grep -n 'consumed STOP sentinel' "$SENTINEL_SH" | tail -1 | cut -d: -f1)"
emit_line="$(grep -n "stopRequested\":true" "$SENTINEL_SH" | tail -1 | cut -d: -f1)"
if [[ -n "$rm_line" && -n "$log_line" && -n "$emit_line" ]] \
   && (( rm_line > log_line )) && (( rm_line > emit_line )); then
  ok "sentinel removal happens after the decision is logged and emitted"
else
  fail_msg "rm precedes log/emit — a later nonzero exit consumes without stopping (fail-open)"
fi

echo
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
