#!/usr/bin/env bash
# roadmap:c14d — relay-reconcile.sh --auto-restart wraps the 3-step id:7809
# auto-reconcile-on-restart flow (dead-runs detect -> --all --auto -> per-runId reap-run
# -> TTL backstop reap) into ONE mechanical hop, so relay-loop.js can dispatch it as
# model:"bash" instead of a haiku-interpreted 3-step prompt. Hermetic: temp HOME,
# temp HEARTBEAT_BASE, temp RELAY_TOML/SRC_DIR, no network, no ~/.claude writes.
set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR_REPO/relay/scripts/relay-reconcile.sh"
HEARTBEAT="$SRC_DIR_REPO/relay/scripts/heartbeat.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "relay-reconcile.sh not found/executable at $SCRIPT"
[[ -x "$HEARTBEAT" ]] || fail "heartbeat.sh not found/executable at $HEARTBEAT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export RECONCILE_LOG=/dev/null
export HEARTBEAT_LOG=/dev/null
export HEARTBEAT_BASE="$TMP/heartbeats"
export RELAY_TOML="$TMP/relay.toml"   # no [repos.*] entries -> --all --auto is a benign no-op
export SRC_DIR="$TMP/src"
printf '' > "$RELAY_TOML"
mkdir -p "$SRC_DIR"

# ── (1) no dead run -> benign "no dead run, skipped", exits 0, no reap side effects ──
out1="$(bash "$SCRIPT" --auto-restart)"
echo "$out1" | grep -q "no dead run, skipped" || fail "(1) expected no-dead-run summary, got: $out1"
pass "(1) no dead run -> benign no-op summary"

# ── (2) a genuinely dead run (heartbeat_ts far in the past, matching relay-* prefix) is
#     detected, --all --auto runs without error, its marker is reaped BY RUNID, and the
#     final TTL backstop reap finds nothing left over ──
DEAD_RUN="relay-20260101-000000-1234"
mkdir -p "$HEARTBEAT_BASE"
# Write a stale marker directly (avoid depending on `date` math inside heartbeat.sh beat;
# heartbeat_ts of 1 (1970) is unambiguously outside any TTL).
printf '{"runId":"%s","pid":"","host":"","started_at":1,"started_iso":"","heartbeat_ts":1,"heartbeat_iso":""}\n' \
  "$DEAD_RUN" > "$HEARTBEAT_BASE/$(printf '%s' "$DEAD_RUN" | tr '/:' '__').json"

# Sanity: heartbeat.sh itself sees this as dead before we invoke the wrapper.
dead_check="$("$HEARTBEAT" dead-runs --prefix 'relay-*')"
echo "$dead_check" | grep -q "$DEAD_RUN" || fail "(2) fixture setup: heartbeat.sh dead-runs did not see $DEAD_RUN: $dead_check"

out2="$(bash "$SCRIPT" --auto-restart)"
echo "$out2" | grep -qE "1 dead run\(s\) observed-reaped" || fail "(2) expected 1 observed-reaped in summary, got: $out2"
pass "(2) auto-restart summary reports the one dead run reaped: $out2"

# The marker must have moved OUT of the live heartbeats dir (reap-run archived it) —
# a second dead-runs scan must no longer see it.
still_dead="$("$HEARTBEAT" dead-runs --prefix 'relay-*')"
[[ -z "$still_dead" ]] || fail "(2) dead run marker was not reaped — still visible: $still_dead"
pass "(2) the dead run's marker was archived (reap-run), not left as a live/dead marker"

# The DONE dir must now contain the archived marker (moved, not deleted — recoverable).
DONE_DIR="$(dirname "$HEARTBEAT_BASE")/heartbeats.done"
[[ -f "$DONE_DIR/$(printf '%s' "$DEAD_RUN" | tr '/:' '__').json" ]] \
  || fail "(2) archived marker not found in DONE dir $DONE_DIR"
pass "(2) archived marker preserved (moved to heartbeats.done, not destroyed)"

# ── (3) idempotent: running --auto-restart again finds nothing to reap ──
out3="$(bash "$SCRIPT" --auto-restart)"
echo "$out3" | grep -q "no dead run, skipped" || fail "(3) expected a clean re-run to be a no-op, got: $out3"
pass "(3) a second --auto-restart run is a clean no-op (idempotent)"

echo "ALL PASS: relay-reconcile.sh --auto-restart wraps id:7809's 3-step flow into one mechanical hop (id:c14d)"
