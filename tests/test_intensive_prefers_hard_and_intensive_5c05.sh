#!/usr/bin/env bash
# id:5c05 — `--intensive` must PREFER [INTENSIVE] and [HARD] units over routine [ROUTINE]
# execute work (owner-ruled 2026-09-01), not merely permit them.
#
# NO `# roadmap:` header on purpose: id:5c05 lives in TODO.md only — `grep -n 'id:5c05'
# ROADMAP.md` finds no twin — so there is no ROADMAP checkbox for the expected-red machinery
# to key on. Failures here always count.
#
# Behavioural, not source-text: tests/fixtures/loop-schedule-order-harness.mjs actually EXECUTES
# one relay-loop.js round in the stub-globals sandbox (same technique as the id:aec5 exec-smoke
# harness) with POOL_WIDTH forced to 1, and prints the ORDER in which units were dispatched.
# The two runs differ in exactly one argument: allowIntensive.
#
# Seeded wave (emitted by the stub in an order matching NEITHER expectation):
#   execute:alpha (routine)  hard:gamma  execute:delta (intensive=localllm)  review:beta
#
# Pinned:
#   (a) with --intensive, hard:gamma is dispatched BEFORE routine execute:alpha
#   (b) with --intensive, the [INTENSIVE] serial phase (execute:delta) runs BEFORE the wave
#   (c) WITHOUT --intensive, the order is today's: execute,review,hard (intensive not run)
#   (d) the D3 anti-gaming rung holds in BOTH modes: review:beta before hard:gamma
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
HARNESS="$ROOT/tests/fixtures/loop-schedule-order-harness.mjs"

pass=0; fail=0
ok()   { echo "ok: $*"; pass=$((pass+1)); }
bad()  { echo "FAIL: $*"; fail=$((fail+1)); }

[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found"; exit 1; }
[[ -f "$HARNESS" ]] || { echo "FAIL: loop-schedule-order-harness.mjs not found"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

node --check "$JS" || { echo "FAIL: relay-loop.js fails node --check"; exit 1; }

run_order() {  # $1 = intensive|default
  local out
  out="$(node "$HARNESS" "$JS" "$1" 2>&1)" || { echo "HARNESS-ERROR: $out"; return 1; }
  grep -m1 '^ORDER: ' <<<"$out" | sed 's/^ORDER: //'
}

DEFAULT_ORDER="$(run_order default)"   || { echo "FAIL: harness errored in default mode: $DEFAULT_ORDER"; exit 1; }
INTENSIVE_ORDER="$(run_order intensive)" || { echo "FAIL: harness errored in intensive mode: $INTENSIVE_ORDER"; exit 1; }

echo "default   dispatch order: $DEFAULT_ORDER"
echo "intensive dispatch order: $INTENSIVE_ORDER"

# Positive control: the harness must actually have dispatched the seeded units in BOTH modes.
# Without this a scheduling assertion could pass vacuously on an empty/short order string.
for u in execute:alpha review:beta hard:gamma; do
  grep -q "$u" <<<"$DEFAULT_ORDER"   || bad "positive control: default mode never dispatched $u (order='$DEFAULT_ORDER')"
  grep -q "$u" <<<"$INTENSIVE_ORDER" || bad "positive control: intensive mode never dispatched $u (order='$INTENSIVE_ORDER')"
done
grep -q 'execute:delta' <<<"$INTENSIVE_ORDER" \
  || bad "positive control: intensive mode never ran the [INTENSIVE] unit execute:delta (order='$INTENSIVE_ORDER')"

# idx <order> <token> -> 0-based position, or -1
idx() { awk -v s="$1" -v t="$2" 'BEGIN{n=split(s,a,","); for(i=1;i<=n;i++) if(a[i]==t){print i-1; exit} print -1}'; }

# (c) default mode is EXACTLY today's behaviour: routine execute first, then review, then hard,
#     and the [INTENSIVE] unit is NOT dispatched at all (it needs --intensive, id:052c/5ac6).
[[ "$DEFAULT_ORDER" == "execute:alpha,review:beta,hard:gamma" ]] \
  && ok "(c) default mode ordering unchanged: $DEFAULT_ORDER" \
  || bad "(c) default mode ordering changed — expected 'execute:alpha,review:beta,hard:gamma', got '$DEFAULT_ORDER'"
grep -q 'execute:delta' <<<"$DEFAULT_ORDER" \
  && bad "(c) default mode dispatched the [INTENSIVE] unit without --intensive (order='$DEFAULT_ORDER')" \
  || ok "(c) default mode did not dispatch the [INTENSIVE] unit"

# (a) --intensive: [HARD] outranks routine execute.
i_hard="$(idx "$INTENSIVE_ORDER" hard:gamma)"
i_exec="$(idx "$INTENSIVE_ORDER" execute:alpha)"
if [[ "$i_hard" -ge 0 && "$i_exec" -ge 0 && "$i_hard" -lt "$i_exec" ]]; then
  ok "(a) --intensive schedules hard:gamma (pos $i_hard) before routine execute:alpha (pos $i_exec)"
else
  bad "(a) --intensive did NOT prefer [HARD] over [ROUTINE] execute — hard:gamma at $i_hard, execute:alpha at $i_exec (order='$INTENSIVE_ORDER')"
fi

# (b) --intensive: the serial [INTENSIVE] phase runs BEFORE the parallel wave.
i_int="$(idx "$INTENSIVE_ORDER" execute:delta)"
if [[ "$i_int" -eq 0 ]]; then
  ok "(b) --intensive runs the [INTENSIVE] serial phase first (execute:delta at pos 0)"
else
  bad "(b) --intensive ran the [INTENSIVE] serial phase at pos $i_int, not before the wave (order='$INTENSIVE_ORDER')"
fi

# (d) D3 anti-gaming rung: review outranks fresh strong (hard) work — in BOTH modes.
for mode in default intensive; do
  o="$DEFAULT_ORDER"; [[ "$mode" == intensive ]] && o="$INTENSIVE_ORDER"
  r="$(idx "$o" review:beta)"; h="$(idx "$o" hard:gamma)"
  if [[ "$r" -ge 0 && "$h" -ge 0 && "$r" -lt "$h" ]]; then
    ok "(d) D3 rung holds in $mode mode: review:beta (pos $r) before hard:gamma (pos $h)"
  else
    bad "(d) D3 anti-gaming rung BROKEN in $mode mode — review:beta at $r, hard:gamma at $h (order='$o')"
  fi
done

echo "---"
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
echo "ALL PASS: --intensive prefers [INTENSIVE] + [HARD] over [ROUTINE] (id:5c05)"
