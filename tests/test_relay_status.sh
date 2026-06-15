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

# Default path includes ~/.config/fables-turn
grep -q "\.config/fables-turn" "$JS" || fail "relay-loop.js missing default ~/.config/fables-turn path"
pass "relay-loop.js references default ~/.config/fables-turn path"
