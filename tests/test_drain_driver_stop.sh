#!/usr/bin/env bash
# roadmap:cd7a — off-Workflow drain-driver CORE loop (id:93fe child). The driver is a HOST
# node script (not Workflow-sandbox JS), so it can — and per the guard-parity requirement
# (TODO id:93fe, Fable review 2026-07-19) MUST — `import` drain.mjs (id:d58f) directly
# instead of re-deriving the isDryRound/isBlockedRound semantics that were learned from the
# 2026-06-29 spin-forever and 2026-07-17 drained-while-blocked incidents.
#
# Interface under test (the spec): relay/scripts/drain-driver.mjs, run via node.
#   node drain-driver.mjs --repo <dir> [--max-rounds N]
#   Env seam for hermetic tests: DRAIN_ROUND_CMD — a command the driver runs ONCE PER ROUND
#   in place of the real classify→dispatch→integrate round; it prints a round-result JSON
#   {actionable, produced, substantive, surfaced} on stdout (the same shape relay-loop.js's
#   runRound() returns and drain.mjs classifies).
#   Stop contract (meeting 2026-07-19-2035 D2 on the off-Workflow substrate):
#     - 2 consecutive non-substantive rounds, all dry (isDryRound)     → exit 0, reason=drained
#     - 2 consecutive non-substantive rounds, any blocked (isBlocked)  → exit 2, reason=blocked
#     - --max-rounds seatbelt reached                                  → exit 3, reason=max-rounds
#   The final stdout line is machine-readable: "DRAIN_STOP reason=<r> rounds=<n>".
# Hermetic: node + bash stubs in mktemp; no git/agents/network.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER="$SRC_DIR/relay/scripts/drain-driver.mjs"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }

[[ -f "$DRIVER" ]] || { echo "FAIL: relay/scripts/drain-driver.mjs does not exist yet (RED spec)"; exit 1; }

# Guard-parity: the driver must IMPORT drain.mjs, not inline-copy it (host node CAN import;
# only the Workflow sandbox cannot — the inline-copy exception does not apply here).
grep -qE "import .*drain\.mjs" "$DRIVER" \
  && ok "driver imports drain.mjs directly (guard-parity, id:d58f)" \
  || bad "driver must 'import ... drain.mjs' — re-deriving the stop semantics is the forbidden guard-shed"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HEARTBEAT_BASE="$TMP/hb"   # keep heartbeat side effects (id:f9d2) inside the sandbox
export RELAY_EVENTS_PATH="$TMP/events.jsonl"

# Fixed always-'ok' quota stub: this spec exercises stop semantics (drained/blocked/max-rounds),
# NOT the live quota gate — pin DRAIN_QUOTA_CMD so the id:838d quota gate does not fire the real
# quota-stop.sh at round 0 against the machine's /tmp/claude-usage-cache.json (id:5eb8 hermeticity
# fix; mirrors tests/test_drain_driver_heartbeat.sh:44-52).
cat > "$TMP/quota.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/quota.sh"
export DRAIN_QUOTA_CMD="$TMP/quota.sh"

# Round stub: emits scripted per-round JSON from a sequence file, one line per round.
mk_round_stub() { # $1 = sequence file
  cat > "$TMP/round.sh" <<EOF
#!/usr/bin/env bash
set -eu
SEQ="$1"
N=\$(cat "$TMP/count" 2>/dev/null || echo 0)
N=\$((N+1)); echo "\$N" > "$TMP/count"
sed -n "\${N}p" "\$SEQ"
EOF
  chmod +x "$TMP/round.sh"
  [ -e "$TMP/count" ] && rm -- "$TMP/count"
  export DRAIN_ROUND_CMD="$TMP/round.sh"
}

DRY='{"actionable":0,"produced":0,"substantive":0,"surfaced":0}'
SUB='{"actionable":1,"produced":1,"substantive":1,"surfaced":0}'
BLK='{"actionable":0,"produced":0,"substantive":0,"surfaced":2}'

# --- case a: substantive round, then 2 dry rounds → drained, exit 0, exactly 3 rounds ---
printf '%s\n%s\n%s\n' "$SUB" "$DRY" "$DRY" > "$TMP/seq_a"
mk_round_stub "$TMP/seq_a"
out="$(node "$DRIVER" --repo "$TMP" --max-rounds 10 2>"$TMP/err_a")"; rc=$?
if [[ $rc -eq 0 ]] && echo "$out" | grep -qE 'DRAIN_STOP reason=drained rounds=3'; then
  ok "K=2 dry rounds after progress → drained (exit 0, 3 rounds)"
else
  bad "expected exit 0 + 'DRAIN_STOP reason=drained rounds=3' (rc=$rc, out: $out)"
fi
[[ "$(cat "$TMP/count" 2>/dev/null)" == "3" ]] \
  && ok "round cmd invoked exactly 3 times (no extra spin)" \
  || bad "round cmd should run exactly 3 times (ran: $(cat "$TMP/count" 2>/dev/null))"

# --- case b: 2 consecutive BLOCKED rounds → blocked, exit 2 (never reported drained) ----
printf '%s\n%s\n' "$BLK" "$BLK" > "$TMP/seq_b"
mk_round_stub "$TMP/seq_b"
out="$(node "$DRIVER" --repo "$TMP" --max-rounds 10 2>"$TMP/err_b")"; rc=$?
if [[ $rc -eq 2 ]] && echo "$out" | grep -qE 'DRAIN_STOP reason=blocked'; then
  ok "blocked rounds → reason=blocked, exit 2 (2026-07-17 drained-while-blocked guard)"
else
  bad "expected exit 2 + reason=blocked (rc=$rc, out: $out)"
fi

# --- case c: endless substantive rounds → MAX_ROUNDS seatbelt, exit 3 -------------------
printf '%s\n%s\n%s\n%s\n%s\n' "$SUB" "$SUB" "$SUB" "$SUB" "$SUB" > "$TMP/seq_c"
mk_round_stub "$TMP/seq_c"
out="$(node "$DRIVER" --repo "$TMP" --max-rounds 3 2>"$TMP/err_c")"; rc=$?
if [[ $rc -eq 3 ]] && echo "$out" | grep -qE 'DRAIN_STOP reason=max-rounds rounds=3'; then
  ok "--max-rounds seatbelt → reason=max-rounds, exit 3"
else
  bad "expected exit 3 + reason=max-rounds at 3 rounds (rc=$rc, out: $out)"
fi
[[ "$(cat "$TMP/count" 2>/dev/null)" == "3" ]] \
  && ok "seatbelt stopped the loop at exactly 3 rounds" \
  || bad "seatbelt should cap at 3 rounds (ran: $(cat "$TMP/count" 2>/dev/null))"

echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
