#!/usr/bin/env bash
# roadmap:f9d2 — drain-driver run-heartbeat wiring (id:93fe child; guard-parity id:e149).
# An off-Workflow drain that does not write the run-heartbeat is INVISIBLE to the outage
# watchdog (id:98f0) and to auto-reconcile-on-restart (id:7809): a crashed drain would leave
# its worktrees orphaned with no alarm. The driver must therefore:
#   (1) mint a runId matching the dispatch-loop namespace glob `relay-*` (the watchdog and
#       reap consumers scope with --prefix 'relay-*'; a non-matching runId is never alarmed),
#   (2) `heartbeat.sh beat <runId>` BEFORE the first round and once per round thereafter,
#   (3) `heartbeat.sh stop <runId>` on every clean exit (drained/blocked/max-rounds), so only
#       a genuinely-dead run leaves a stale marker (crash detection itself is heartbeat.sh's
#       already-tested TTL contract — deliberately NOT re-tested here).
# Hermetic: HEARTBEAT_BASE + all paths under mktemp; stub round cmd; no git/agents/network.
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
export HEARTBEAT_BASE="$TMP/heartbeats"
export RELAY_EVENTS_PATH="$TMP/events.jsonl"

# Round stub emits one dry round per call AND records whether a live heartbeat marker was
# present DURING the round (proving beat-precedes-round, not just beat-at-some-point).
cat > "$TMP/round.sh" <<EOF
#!/usr/bin/env bash
set -eu
if ls "$TMP/heartbeats"/*.json >/dev/null 2>&1; then
  echo present >> "$TMP/probe"
else
  echo absent >> "$TMP/probe"
fi
echo '{"actionable":0,"produced":0,"substantive":0,"surfaced":0}'
EOF
chmod +x "$TMP/round.sh"
export DRAIN_ROUND_CMD="$TMP/round.sh"

out="$(node "$DRIVER" --repo "$TMP" --max-rounds 5 2>"$TMP/err")"; rc=$?
[[ $rc -eq 0 ]] || bad "driver should drain cleanly on dry rounds (rc=$rc, err: $(cat "$TMP/err"))"

# --- beat precedes every round -------------------------------------------------
if [[ -f "$TMP/probe" ]] && ! grep -q absent "$TMP/probe"; then
  ok "a live heartbeat marker was present during every round (beat precedes dispatch)"
else
  bad "heartbeat marker missing during at least one round (probe: $(cat "$TMP/probe" 2>/dev/null))"
fi

# --- clean exit stops the heartbeat: live dir empty, marker ARCHIVED -----------
if ls "$TMP/heartbeats"/*.json >/dev/null 2>&1; then
  bad "clean exit must 'heartbeat.sh stop' — a marker is still live (would false-alarm the watchdog)"
else
  ok "no live marker after clean exit"
fi
done_dir="$TMP/heartbeats.done"
archived="$(ls "$done_dir"/*.json 2>/dev/null | head -1)"
if [[ -n "$archived" ]]; then
  ok "marker archived to heartbeats.done (clean stop, id:e149 contract)"
  runid="$(jq -r '.runId // .run_id // empty' "$archived")"
  case "$runid" in
    relay-*) ok "runId '$runid' matches the watchdog's relay-* namespace glob" ;;
    *)       bad "runId '$runid' does NOT match relay-* — invisible to relay-watchdog.sh --prefix 'relay-*'" ;;
  esac
else
  bad "no archived heartbeat marker found in heartbeats.done (driver never beat, or stop deleted it)"
fi

echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
