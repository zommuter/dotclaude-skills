#!/usr/bin/env bash
# roadmap:7725 — reap a KNOWN-DEAD run's heartbeat marker on OBSERVED failure, not just TTL
# expiry. The bug (observed 2026-07-07): a `-c`-crash run (relay-...-174626) was detected and
# handled synchronously within minutes, but its heartbeat marker was only ~25 min stale at
# relaunch — UNDER the 3600s TTL — so `reap` (stale-only) skipped it and auto-reconcile-on-restart
# (id:7809) did not archive it; it aged past the TTL ~1h later and tripped the outage watchdog
# (id:98f0) for a crash already resolved.
#
# Fix contract: a new `heartbeat.sh reap-run <runId>` subcommand archives THAT SPECIFIC run's
# marker to heartbeats.done REGARDLESS of staleness (the run is KNOWN dead by direct observation,
# so we must not wait for the conservative TTL). It is the observed-death counterpart of the
# stale-only `reap`: `reap` sweeps present-but-stale markers; `reap-run` archives one named marker
# even while fresh. Distinct from `stop` (clean shutdown) only in log semantics; both archive.
#
# Hermetic: HEARTBEAT_BASE in a tmpdir, no network/~, no forced aging (the whole point is that
# reap-run archives a FRESH marker).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/heartbeat.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "heartbeat.sh not found/executable at $SH"

export HEARTBEAT_BASE; HEARTBEAT_BASE="$(mktemp -d)/heartbeats"
export HEARTBEAT_LOG=/dev/null
export HEARTBEAT_TTL=3600   # large TTL: the marker stays FRESH — reap-run must archive it anyway
trap 'rm -rf "$(dirname "$HEARTBEAT_BASE")"' EXIT

# ── reap-run archives a FRESH (non-stale) known-dead marker ───────────────────
"$SH" beat relay-CRASH --pid 9191 >/dev/null
[[ "$("$SH" status relay-CRASH)" == alive ]] || fail "precondition: the crashed run's marker should read alive (fresh, under TTL)"
"$SH" reap-run relay-CRASH
[[ "$("$SH" status relay-CRASH || true)" == absent ]] \
  || fail "reap-run did not archive a FRESH known-dead marker (this is the id:7725 bug: only TTL-stale markers were reaped)"
[[ -z "$("$SH" dead-runs | jq -rc 'select(.runId=="relay-CRASH")')" ]] \
  || fail "a reap-run'd marker still appears in dead-runs (would re-trip the watchdog ~1h later)"
pass "reap-run archives a fresh, observed-dead marker so the watchdog cannot re-alarm (id:7725)"

# ── reap-run touches ONLY the named run ───────────────────────────────────────
"$SH" beat relay-CRASH2 >/dev/null
"$SH" beat relay-HEALTHY >/dev/null
"$SH" reap-run relay-CRASH2
[[ "$("$SH" status relay-CRASH2 || true)" == absent ]] || fail "reap-run did not archive the named run"
[[ "$("$SH" status relay-HEALTHY)" == alive ]] \
  || fail "reap-run wrongly archived a DIFFERENT run's marker (must be scoped to the named runId)"
pass "reap-run is scoped to the named run and leaves other runs alive (id:7725)"

# ── reap-run is idempotent on an absent marker (exit 0) ───────────────────────
"$SH" reap-run relay-NEVER-EXISTED \
  || fail "reap-run on an absent marker must be idempotent (exit 0), not an error"
pass "reap-run is idempotent when the marker is already gone (id:7725)"

echo "ALL PASS: heartbeat reap-run — observed-death immediate reap (id:7725)"
