#!/usr/bin/env bash
# roadmap:43b9 — relay host-awareness gate (host-gate.sh).
#
# Spec: a ROADMAP item may carry an optional [host:<name>] tag. The host-bound
# verification step (executor definition-of-done, reviewer re-derivation) runs
# host-gate.sh against the item line; it PROCEEDS when the tag is absent / host:any /
# matches the current host, and DEFERS (exit 3) when it names a different host. Editing
# is never gated — only verification consults this gate.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$SRC_DIR/relay/scripts/host-gate.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$GATE" ]] || fail "host-gate.sh not found/executable at $GATE"

# Run the gate with a forced hostname; capture stdout + exit code.
# usage: run <RELAY_HOSTNAME> <item-text-or-empty-for-stdin> [stdin-text]
run_arg() {
  local host="$1" text="$2"
  set +e
  OUT="$(RELAY_HOSTNAME="$host" "$GATE" "$text" 2>&1)"
  RC=$?
  set -e
}
run_stdin() {
  local host="$1" text="$2"
  set +e
  OUT="$(printf '%s' "$text" | RELAY_HOSTNAME="$host" "$GATE" 2>&1)"
  RC=$?
  set -e
}

ITEM_ZOMNI='- [ ] [ROUTINE] [host:zomni] map ELAN touchscreen to eDP-1 <!-- id:1234 -->'
ITEM_FIEVEL='- [ ] [ROUTINE] [host:fievel] sunrise-monitor apt install <!-- id:5678 -->'
ITEM_ANY='- [ ] [ROUTINE] [host:any] shared bashrc snippet <!-- id:9abc -->'
ITEM_UNTAGGED='- [ ] [ROUTINE] shared git config <!-- id:def0 -->'

# (a) Matching host → PROCEED (exit 0).
run_arg zomni "$ITEM_ZOMNI"
[[ "$RC" -eq 0 ]] || fail "matching host should proceed (exit 0), got $RC: $OUT"
[[ "$OUT" == proceed:* ]] || fail "matching host should print 'proceed:', got: $OUT"
pass "matching host proceeds (exit 0)"

# (b) Mismatched host → DEFER (exit 3) with a 'needs host:<X>' note naming both hosts.
run_arg zomni "$ITEM_FIEVEL"
[[ "$RC" -eq 3 ]] || fail "mismatched host should defer (exit 3), got $RC: $OUT"
[[ "$OUT" == *"needs host:fievel"* ]] || fail "defer note should name the required host, got: $OUT"
[[ "$OUT" == *"zomni"* ]] || fail "defer note should name the current host, got: $OUT"
pass "mismatched host defers (exit 3) with 'needs host:fievel (current: zomni)'"

# (c) [host:any] → PROCEED on any host.
run_arg fievel "$ITEM_ANY"
[[ "$RC" -eq 0 ]] || fail "[host:any] should proceed on any host, got $RC: $OUT"
pass "[host:any] proceeds regardless of host"

# (d) No host tag → PROCEED (default host:any).
run_arg fievel "$ITEM_UNTAGGED"
[[ "$RC" -eq 0 ]] || fail "untagged item should proceed (default any), got $RC: $OUT"
pass "untagged item proceeds (default host:any)"

# (e) Case-insensitive tag + host comparison.
run_arg ZOMNI '- [ ] [ROUTINE] [HOST:Zomni] x <!-- id:1111 -->'
[[ "$RC" -eq 0 ]] || fail "case-insensitive match should proceed, got $RC: $OUT"
pass "case-insensitive host/tag comparison proceeds"

# (f) Item text on stdin (the wiring path used by review/executor pipelines).
run_stdin cartmanjaro "$ITEM_FIEVEL"
[[ "$RC" -eq 3 ]] || fail "stdin mismatch should defer (exit 3), got $RC: $OUT"
pass "reads item text from stdin"

# (g) Misuse — no text at all (closed stdin) → exit 2.
set +e
OUT="$(RELAY_HOSTNAME=zomni "$GATE" < /dev/null 2>&1)"
RC=$?
set -e
[[ "$RC" -eq 2 ]] || fail "no item text should be misuse (exit 2), got $RC: $OUT"
pass "no item text is misuse (exit 2)"

echo "ALL PASS: host-gate.sh host-awareness gate (id:43b9)"
