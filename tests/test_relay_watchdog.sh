#!/usr/bin/env bash
# roadmap:98f0 — outage watchdog: detect a dead relay loop via the shared run-heartbeat
# (id:e149) and NOTIFY + log to the evidence file ONCE per dead run (no claude -p, no spam).
# A clean run is silent; a reaped run drops out of the de-dup state. Hermetic: tmp heartbeat
# store + a stub notify command that records invocations; no systemd, no network, no ~.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WD="$SRC_DIR/tools/relay-watchdog.sh"
HB="$SRC_DIR/relay/scripts/heartbeat.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$WD" ]] || fail "relay-watchdog.sh not found/executable at $WD"
[[ -x "$HB" ]] || fail "heartbeat.sh not found/executable at $HB"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HEARTBEAT_BASE="$TMP/heartbeats"
export HEARTBEAT_LOG=/dev/null
export HEARTBEAT_TTL=3600
export RELAY_HEARTBEAT_SH="$HB"
export RELAY_WATCHDOG_STATE="$TMP/notified"
export RELAY_WATCHDOG_EVIDENCE="$TMP/outage.jsonl"
export RELAY_WATCHDOG_LOG=/dev/null
# Stub notifier: append its title arg to a file so the test can count notifications.
NOTIFS="$TMP/notifs"
STUB="$TMP/notify-stub.sh"; printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >> "%s"\n' "$NOTIFS" > "$STUB"
chmod +x "$STUB"
export RELAY_WATCHDOG_NOTIFY_CMD="$STUB"

age() { local f="$1" old; old="$(( $(date +%s) - 7200 ))"
  jq --argjson t "$old" '.heartbeat_ts=$t' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; touch -d '2 hours ago' "$f"; }

# ── a clean (no dead run) tick is silent ──────────────────────────────────────
bash "$WD" >/dev/null 2>&1
[[ ! -s "$NOTIFS" ]] || fail "watchdog notified with no dead run"
[[ ! -s "$RELAY_WATCHDOG_EVIDENCE" ]] || fail "watchdog logged evidence with no dead run"
pass "a tick with no dead run is silent (id:98f0)"

# ── a dead run is notified + logged ONCE ──────────────────────────────────────
"$HB" beat relay-DEADX >/dev/null
age "$HEARTBEAT_BASE/$(printf relay-DEADX | tr '/:' '__').json"
bash "$WD" >/dev/null 2>&1
[[ "$(wc -l < "$NOTIFS")" -eq 1 ]] || fail "expected exactly 1 notification for a new dead run (got $(wc -l < "$NOTIFS"))"
grep -q "relay-DEADX" "$RELAY_WATCHDOG_EVIDENCE" || fail "dead run not recorded in the evidence log"
jq -e '.runId=="relay-DEADX" and (.detected_at|type=="string")' "$RELAY_WATCHDOG_EVIDENCE" >/dev/null \
  || fail "evidence JSON missing runId/detected_at"
pass "a dead run is notified once and logged to the evidence file (id:98f0)"

# ── a second tick on the SAME dead run does NOT re-notify (de-dup) ────────────
bash "$WD" >/dev/null 2>&1
[[ "$(wc -l < "$NOTIFS")" -eq 1 ]] || fail "watchdog re-notified an already-known dead run (spam)"
[[ "$(wc -l < "$RELAY_WATCHDOG_EVIDENCE")" -eq 1 ]] || fail "watchdog re-logged an already-known dead run"
pass "a known dead run is not re-notified on later ticks (de-dup, id:98f0)"

# ── once the dead marker is reaped, the de-dup state clears ───────────────────
"$HB" reap 2>/dev/null
bash "$WD" >/dev/null 2>&1
[[ ! -s "$RELAY_WATCHDOG_STATE" ]] || fail "de-dup state not cleared after the dead run was reaped"
pass "reaping the dead marker clears the watchdog de-dup state (id:98f0)"

echo "ALL PASS: relay outage watchdog detect+notify+dedup (id:98f0)"
