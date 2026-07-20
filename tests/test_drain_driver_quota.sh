#!/usr/bin/env bash
# roadmap:838d — drain-driver quota gate + agent seatbelt (id:93fe child; guard-parity).
# An off-Workflow drain that skips the quota gate is exactly the unattended auto-spend the
# unattended-default rule forbids. The driver must:
#   (1) run the quota gate BEFORE EVERY round, including the first (env seam DRAIN_QUOTA_CMD;
#       default is relay/scripts/quota-stop.sh — asserted statically below),
#   (2) map the gate's exit codes to DISTINCT stop reasons (quota-stop.sh contract:
#       1=threshold → quota-stop, 2=cache-unreadable fail-safe → quota-cache-unreadable,
#       3=extrapolated → quota-extrapolated-stop), exiting 4 in all three cases,
#   (3) stop BEFORE dispatching the round (a gated round must never run), and
#   (4) feed the seatbelt: pass cumulative `--agents <total>` and `--wall <elapsed-s>` to the
#       gate so quota-stop.sh's hard caps (200 agents / 7200 s) engage on a long drain.
#       The per-round agent count rides the round-result JSON's optional `agents` field.
# Hermetic: stub quota + round cmds in mktemp; no network, no real usage cache.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER="$SRC_DIR/relay/scripts/drain-driver.mjs"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }

[[ -f "$DRIVER" ]] || { echo "FAIL: relay/scripts/drain-driver.mjs does not exist yet (RED spec)"; exit 1; }

# --- static: the default gate is quota-stop.sh (never an unguarded loop) ------
grep -q 'quota-stop.sh' "$DRIVER" \
  && ok "driver defaults its quota gate to quota-stop.sh" \
  || bad "driver source never references quota-stop.sh — no default quota gate"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HEARTBEAT_BASE="$TMP/hb"
export RELAY_EVENTS_PATH="$TMP/events.jsonl"

# Round stub: 1 substantive round consuming 5 agents, then dry rounds; records invocations.
cat > "$TMP/round.sh" <<EOF
#!/usr/bin/env bash
set -eu
N=\$(cat "$TMP/rounds" 2>/dev/null || echo 0); N=\$((N+1)); echo "\$N" > "$TMP/rounds"
if [ "\$N" -eq 1 ]; then
  echo '{"actionable":1,"produced":1,"substantive":1,"surfaced":0,"agents":5}'
else
  echo '{"actionable":0,"produced":0,"substantive":0,"surfaced":0,"agents":0}'
fi
EOF
chmod +x "$TMP/round.sh"
export DRAIN_ROUND_CMD="$TMP/round.sh"

# Quota stub: records argv per call, exits per a scripted code file.
cat > "$TMP/quota.sh" <<EOF
#!/usr/bin/env bash
set -eu
echo "\$@" >> "$TMP/quota_argv"
exit "\$(cat "$TMP/quota_rc")"
EOF
chmod +x "$TMP/quota.sh"
export DRAIN_QUOTA_CMD="$TMP/quota.sh"

run_case() { # $1=quota-exit-code  $2=expected-reason
  rm -rf -- "$TMP/hb"; : > "$TMP/quota_argv"
  [ -e "$TMP/rounds" ] && rm -- "$TMP/rounds"
  echo "$1" > "$TMP/quota_rc"
  out="$(node "$DRIVER" --repo "$TMP" --max-rounds 10 2>"$TMP/err")"; rc=$?
  if [[ $rc -eq 4 ]] && echo "$out" | grep -qE "DRAIN_STOP reason=$2"; then
    ok "quota exit $1 → reason=$2, driver exit 4"
  else
    bad "quota exit $1: expected exit 4 + reason=$2 (rc=$rc, out: $out)"
  fi
  if [[ -f "$TMP/rounds" ]]; then
    bad "quota exit $1: gate refused but the round STILL ran (gate must precede dispatch)"
  else
    ok "quota exit $1: no round dispatched after refusal"
  fi
}

# --- cases (2): distinct reasons for the three quota-stop exit codes ----------
run_case 1 "quota-stop"
run_case 2 "quota-cache-unreadable"
run_case 3 "quota-extrapolated-stop"

# --- case (1)+(4): gate green → called before EVERY round, with cumulative agents ---
rm -rf -- "$TMP/hb"; : > "$TMP/quota_argv"
[ -e "$TMP/rounds" ] && rm -- "$TMP/rounds"
echo 0 > "$TMP/quota_rc"
out="$(node "$DRIVER" --repo "$TMP" --max-rounds 10 2>"$TMP/err")"; rc=$?
[[ $rc -eq 0 ]] || bad "green gate: driver should drain cleanly (rc=$rc, err: $(cat "$TMP/err"))"
rounds="$(cat "$TMP/rounds" 2>/dev/null || echo 0)"
gates="$(wc -l < "$TMP/quota_argv")"
if [[ "$gates" -ge "$rounds" && "$rounds" -ge 3 ]]; then
  ok "quota gate ran before every round ($gates gate calls for $rounds rounds)"
else
  bad "expected >=1 gate call per round (gates=$gates rounds=$rounds)"
fi
if tail -n +2 "$TMP/quota_argv" | grep -qE -- '--agents 5'; then
  ok "cumulative --agents 5 passed to the gate after the 5-agent round (seatbelt feed)"
else
  bad "gate never saw cumulative --agents 5 (argv log: $(cat "$TMP/quota_argv"))"
fi
grep -qE -- '--wall [0-9]+' "$TMP/quota_argv" \
  && ok "--wall <elapsed> passed to the gate" \
  || bad "gate never saw --wall (argv log: $(cat "$TMP/quota_argv"))"

echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
