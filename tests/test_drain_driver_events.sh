#!/usr/bin/env bash
# roadmap:dd1e — drain-driver RELAY event-line emission (id:93fe child; guard-parity with the
# pool's pushEvent → relay-events.jsonl feed, id:c8b6). An off-Workflow drain that emits no
# events is invisible to `tail -f ~/.config/relay/relay-events.jsonl` and to every downstream
# status consumer. The driver must APPEND (never truncate) JSONL events to $RELAY_EVENTS_PATH:
#   - one `round-start` event per round,
#   - a final `drain-stop` event carrying the stop reason (drained/blocked/max-rounds/quota-*),
#   - every line valid JSON bearing `ts` and `runId` fields (runId in the relay-* namespace).
# Hermetic: RELAY_EVENTS_PATH + stubs under mktemp; no network/agents.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER="$SRC_DIR/relay/scripts/drain-driver.mjs"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "FAIL: jq not found"; exit 1; }

[[ -f "$DRIVER" ]] || { echo "FAIL: relay/scripts/drain-driver.mjs does not exist yet (RED spec)"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HEARTBEAT_BASE="$TMP/hb"
export RELAY_EVENTS_PATH="$TMP/events.jsonl"

# Pre-existing content must be APPENDED to, never clobbered (the pool's file truly appends).
printf '{"event":"pre-existing","ts":"x","runId":"relay-prior"}\n' > "$RELAY_EVENTS_PATH"

cat > "$TMP/round.sh" <<EOF
#!/usr/bin/env bash
set -eu
echo '{"actionable":0,"produced":0,"substantive":0,"surfaced":0}'
EOF
chmod +x "$TMP/round.sh"
export DRAIN_ROUND_CMD="$TMP/round.sh"

# Fixed always-'ok' quota stub: this spec exercises event-line emission, not the live quota
# gate — pin DRAIN_QUOTA_CMD so the test is deterministic regardless of the machine's real
# /tmp/claude-usage-cache.json (id:5eb8 hermeticity fix).
cat > "$TMP/quota.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/quota.sh"
export DRAIN_QUOTA_CMD="$TMP/quota.sh"

out="$(node "$DRIVER" --repo "$TMP" --max-rounds 5 2>"$TMP/err")"; rc=$?
[[ $rc -eq 0 ]] || bad "driver should drain cleanly on dry rounds (rc=$rc, err: $(cat "$TMP/err"))"

[[ -f "$RELAY_EVENTS_PATH" ]] || { echo "FAIL: no events file written"; exit 1; }

# --- append-only: the pre-existing line survives ------------------------------
head -1 "$RELAY_EVENTS_PATH" | grep -qF '"pre-existing"' \
  && ok "events file appended to (pre-existing line intact)" \
  || bad "events file was truncated — must append, never clobber"

# --- every line is valid JSON with ts + runId ---------------------------------
badlines=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line" | jq -e '.ts and .runId' >/dev/null 2>&1 || badlines=$((badlines+1))
done < "$RELAY_EVENTS_PATH"
[[ "$badlines" -eq 0 ]] \
  && ok "every event line is valid JSON with ts + runId" \
  || bad "$badlines event line(s) invalid or missing ts/runId"

# --- round-start per round (2 dry rounds ran) ---------------------------------
n_rounds="$(grep -c 'round-start' "$RELAY_EVENTS_PATH")"
[[ "$n_rounds" -ge 2 ]] \
  && ok "round-start emitted per round ($n_rounds seen)" \
  || bad "expected >=2 round-start events (got $n_rounds)"

# --- final drain-stop event with the reason -----------------------------------
last_stop="$(grep 'drain-stop' "$RELAY_EVENTS_PATH" | tail -1)"
if [[ -n "$last_stop" ]]; then
  echo "$last_stop" | jq -e '.reason == "drained"' >/dev/null 2>&1 \
    && ok "drain-stop event carries reason=drained" \
    || bad "drain-stop event lacks reason=drained (line: $last_stop)"
  echo "$last_stop" | jq -r '.runId' | grep -qE '^relay-' \
    && ok "stop event runId is in the relay-* namespace" \
    || bad "stop event runId not relay-* (line: $last_stop)"
else
  bad "no drain-stop event emitted"
fi

echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
