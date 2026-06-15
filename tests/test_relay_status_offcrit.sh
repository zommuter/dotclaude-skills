#!/usr/bin/env bash
# roadmap:cb50 — the Haiku RELAY_STATUS write is OFF the pool's critical path. It used to be
# `await`ed between discover→dispatch and at round end, so the next discover/dispatch blocked
# on a pure visibility side-effect. Now it is snapshotted + queued on a serialized tail; the
# pool proceeds immediately and the run flushes the tail once at the end. Static-structural.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found"
node --check "$JS" || fail "relay-loop.js fails node --check"

# (1) the non-blocking machinery exists: a serialized tail + a scheduler.
grep -q "let statusTail" "$JS" || fail "no statusTail serializer for status writes"
grep -q "function scheduleStatusWrite" "$JS" || fail "no scheduleStatusWrite() scheduler"
grep -q "statusTail = statusTail" "$JS" || fail "scheduleStatusWrite does not chain onto the serialized tail"

# (2) the content is SNAPSHOTTED at schedule time (state is mutated across rounds, so a queued
#     write must not read it later).
grep -q "function snapshotState" "$JS" || fail "no snapshotState — a queued write could read drifted state"

# (3) NO status write is awaited on the critical path anymore (the whole point).
[ "$(grep -c 'await writeRelayStatus' "$JS")" -eq 0 ] || fail "a status write is still awaited on the critical path"

# (4) the run flushes the queued writes before returning (durability).
grep -q "await statusTail" "$JS" || fail "the run never flushes statusTail before returning"

# (5) every former write site now schedules instead of awaits.
grep -q "scheduleStatusWrite(state)" "$JS" || fail "call sites do not use scheduleStatusWrite"
grep -q "id:cb50" "$JS" || fail "no id:cb50 marker"

pass "RELAY_STATUS write is snapshotted + queued off the critical path, flushed at run end (cb50)"
