#!/usr/bin/env bash
# roadmap:1b11 — PID-anchored claim liveness for STANDALONE long jobs (no worktree).
# A multi-hour local-LLM drain adopted via `acquire-resource.sh --pid <PID>` (or a wrapped
# job anchoring on the wrapper's own $$) must keep its `resource:<name>` claim LIVE for as
# long as the process lives — past the mtime TTL — and auto-expire the instant the PID dies.
# Anchored on the DEDICATED live_pid field (NOT the incidental .pid = claim.sh's own $$), so
# a claim opts into PID-liveness ONLY when --pid was passed; existing callers are unaffected.
#
# Hermetic: CLAIM_BASE in a tmpdir; staleness forced via `touch -d '1 hour ago'` (never
# natural aging); CLAIM_TTL large so only the forced touch makes a claim stale. A "live" PID
# is a backgrounded `sleep`; a "dead" PID is that sleep after it is killed+reaped (reuse
# within the sub-second test window is vanishingly unlikely).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAIM="$SRC_DIR/relay/scripts/claim.sh"
ACQ="$SRC_DIR/relay/scripts/acquire-resource.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CLAIM" ]] || fail "claim.sh not found/executable at $CLAIM"
[[ -x "$ACQ"   ]] || fail "acquire-resource.sh not found/executable at $ACQ"

export CLAIM_BASE; CLAIM_BASE="$(mktemp -d)"
export CLAIM_LOG=/dev/null RESOURCE_CLAIM_LOG=/dev/null
export CLAIM_TTL=3600

# Background sleeps MUST reset the EXIT trap (subshell + `trap - EXIT`) — otherwise a
# killed background child runs the INHERITED EXIT trap and wipes $CLAIM_BASE / kills the
# live PID mid-test. cleanup() never kills LIVE_PID from the trap for the same reason.
cleanup() { kill "$LIVE_PID" 2>/dev/null || true; rm -rf "$CLAIM_BASE"; }
trap cleanup EXIT

# A genuinely-live PID to anchor on.
( trap - EXIT; exec sleep 600 ) & LIVE_PID=$!

# A dead PID: spawn, kill, reap.
( trap - EXIT; exec sleep 600 ) & DEAD_PID=$!
kill "$DEAD_PID" 2>/dev/null || true
wait "$DEAD_PID" 2>/dev/null || true

# ── 1. claim.sh: live --pid survives past TTL → a different run's acquire is REFUSED ──
sk="$("$CLAIM" acquire resource:gpu --run RUN-A --mode intensive --pid "$LIVE_PID")"
shard="$CLAIM_BASE/claims/$sk.json"
[[ -f "$shard" ]] || fail "acquire did not write a shard"
touch -d '1 hour ago' "$shard"                       # age past TTL → stale mtime, no worktree
if "$CLAIM" acquire resource:gpu --run RUN-B 2>/dev/null; then
  fail "a stale-mtime claim with a LIVE live_pid was stolen — PID-liveness not honored"
fi
pass "live --pid keeps a >TTL standalone claim live (steal refused)"

# peek must still emit it (live), reap must NOT drop it.
"$CLAIM" peek | grep -q '"key":"resource:gpu"' || fail "peek dropped a live-pid claim"
"$CLAIM" reap 2>/dev/null || true
[[ -f "$shard" ]] || fail "reap removed a live-pid claim"
pass "peek emits + reap keeps a live-pid claim past TTL"

# ── 2. claim.sh: dead --pid + stale mtime → DEAD (reapable + re-acquirable) ──
rm -f "$shard"
sk2="$("$CLAIM" acquire resource:local-llm --run RUN-C --mode intensive --pid "$DEAD_PID")"
shard2="$CLAIM_BASE/claims/$sk2.json"
touch -d '1 hour ago' "$shard2"
if ! "$CLAIM" acquire resource:local-llm --run RUN-D 2>/dev/null >/dev/null; then
  fail "a stale claim with a DEAD live_pid was NOT re-acquirable — dead PID must not extend life"
fi
pass "dead --pid does not keep a stale claim alive (re-acquired)"

# ── 3. claim.sh: NO --pid (existing behavior) → stale mtime + no worktree = DEAD ──
rm -f "$CLAIM_BASE/claims/"*.json 2>/dev/null || true
sk3="$("$CLAIM" acquire resource:cpu --run RUN-E --mode intensive)"
shard3="$CLAIM_BASE/claims/$sk3.json"
[[ "$(jq -r '.live_pid' "$shard3")" == "" ]] || fail "a no --pid claim should record an empty live_pid"
touch -d '1 hour ago' "$shard3"
if ! "$CLAIM" acquire resource:cpu --run RUN-F 2>/dev/null >/dev/null; then
  fail "no-pid claim must remain reapable on stale mtime (regression: incidental .pid leaked into liveness)"
fi
pass "no --pid → unchanged legacy behavior (stale = dead)"

# ── 4. acquire-resource.sh --acquire --pid adopts an already-running job ──
rm -f "$CLAIM_BASE/claims/"*.json 2>/dev/null || true
"$ACQ" gpu --acquire --pid "$LIVE_PID" --run drain-test >/dev/null || fail "acquire-resource --acquire --pid failed"
shardR="$CLAIM_BASE/claims/resource_gpu.json"
[[ -f "$shardR" ]] || fail "acquire-resource did not create the resource:gpu shard"
[[ "$(jq -r '.live_pid' "$shardR")" == "$LIVE_PID" ]] || fail "acquire-resource --pid did not record live_pid=$LIVE_PID"
touch -d '1 hour ago' "$shardR"
if "$ACQ" gpu --acquire --run other 2>/dev/null >/dev/null; then
  fail "acquire-resource adopted-PID claim stolen past TTL while PID alive"
fi
pass "acquire-resource.sh --acquire --pid adopts a running job (busy past TTL)"

echo "ALL PASS"
