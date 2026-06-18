#!/usr/bin/env bash
# roadmap:80e2 — RELAY_STATUS.md cross-repo rollup writer: static checks on relay-loop.js

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
pass "relay-loop.js exists"

# RELAY_STATUS_PATH env var support
grep -q "RELAY_STATUS_PATH" "$JS" || fail "relay-loop.js does not reference RELAY_STATUS_PATH"
pass "relay-loop.js references RELAY_STATUS_PATH"

# Header format
grep -q "# RELAY_STATUS" "$JS" || fail "relay-loop.js missing '# RELAY_STATUS' header"
pass "relay-loop.js has RELAY_STATUS header"

# Required template sections
grep -q "## In-flight" "$JS" || fail "relay-loop.js missing '## In-flight' section"
pass "relay-loop.js has In-flight section"

grep -q "## Completed this run" "$JS" || fail "relay-loop.js missing '## Completed this run' section"
pass "relay-loop.js has Completed this run section"

# id:c8b6 — Run progress section (round/dispatched/in-flight/completed/blocked counters)
grep -q "## Run progress" "$JS" || fail "relay-loop.js missing '## Run progress' section"
pass "relay-loop.js has Run progress section"

# id:c8b6 + id:0d31 — the Burnup section + Claims + atomic write + event-append are now produced
# by the deterministic relay-status-publish.sh (skeleton L1 thin-glue); relay-loop.js's status
# writer just delegates to it (short, drift-free haiku prompt). Assert the delegation in the JS
# and that the SCRIPT owns the Burnup/Claims/event-append logic that moved out of the prompt.
PUB="$SRC_DIR/relay/scripts/relay-status-publish.sh"
[[ -f "$PUB" ]] || fail "relay-status-publish.sh not found"
grep -q "relay-status-publish.sh" "$JS" || fail "relay-loop.js status writer does not delegate to relay-status-publish.sh"
grep -q "## Burnup this run" "$PUB" || fail "relay-status-publish.sh missing '## Burnup this run' section"
grep -q "relay-burn.sh" "$PUB"      || fail "relay-status-publish.sh does not invoke relay-burn.sh report"
grep -q "## Claims (live)" "$PUB"   || fail "relay-status-publish.sh missing '## Claims (live)' section"
pass "status writer delegates to relay-status-publish.sh, which renders Burnup + Claims (c8b6/0d31)"

# id:c8b6 — append-only event log: path const in the JS + the publisher flushes via event-append;
# pushEvent emit sites stay in relay-loop.js.
grep -q "RELAY_EVENTS_PATH" "$JS" || fail "relay-loop.js missing RELAY_EVENTS_PATH"
grep -q "event-append" "$PUB" || fail "relay-status-publish.sh does not flush events via event-append"
grep -q "pushEvent('dispatch'" "$JS" || fail "relay-loop.js missing pushEvent('dispatch') at dispatch site"
grep -q "pushEvent('integrate'" "$JS" || fail "relay-loop.js missing pushEvent('integrate') at integrate site"
pass "relay-loop.js emits append-only events (dispatch/integrate) flushed via event-append"

grep -q "## Queued" "$JS" || fail "relay-loop.js missing '## Queued' section"
pass "relay-loop.js has Queued section"

grep -q "## Blocked" "$JS" || fail "relay-loop.js missing '## Blocked' section"
pass "relay-loop.js has Blocked/HANDBACKs section"

grep -q "## Quota remaining" "$JS" || fail "relay-loop.js missing '## Quota remaining' section"
pass "relay-loop.js has Quota remaining section"

grep -q "## REVIEW_ME" "$JS" || fail "relay-loop.js missing '## REVIEW_ME open items' section"
pass "relay-loop.js has REVIEW_ME open items section"

# log() condensed one-liner must mention RELAY_STATUS
grep -q "log.*RELAY_STATUS" "$JS" || fail "relay-loop.js missing log() call referencing RELAY_STATUS"
pass "relay-loop.js has log() condensed status line"

# writeRelayStatus function must exist
grep -q "writeRelayStatus" "$JS" || fail "relay-loop.js missing writeRelayStatus function"
pass "relay-loop.js defines writeRelayStatus"

# buildRelayStatus function must exist (generates content — no fs, agent does the write)
grep -q "buildRelayStatus" "$JS" || fail "relay-loop.js missing buildRelayStatus function"
pass "relay-loop.js defines buildRelayStatus"

# File is written via agent (Workflow JS has no fs access)
grep -q "write-relay-status\|write.*relay.*status\|relay.*status.*write" "$JS" \
  || fail "relay-loop.js missing agent call for writing RELAY_STATUS.md"
pass "relay-loop.js uses agent call to write RELAY_STATUS.md"

# Default path includes the canonical ~/.config/relay (renamed from fables-turn, id:10c0)
grep -q "\.config/relay" "$JS" || fail "relay-loop.js missing default ~/.config/relay path"
pass "relay-loop.js references default ~/.config/relay path"
