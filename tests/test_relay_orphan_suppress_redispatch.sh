#!/usr/bin/env bash
# roadmap:1f53 — D3: suppress-redispatch of items with parked partial work (meeting
# 2026-06-16-0938). Once D1 parks an orphan into relay/orphan/*, discovery must bind that branch
# back to its ROADMAP item (via `git show --stat` on the parked commit) and, if the item is still
# OPEN, NOT dispatch a fresh expensive session for it — instead surface ONE line with a best-effort
# `relay-burn.sh --run <runId>` cost hint. A CLOSED-item orphan does NOT suppress. Ambiguous
# binding defaults to suppress (a glance is cheaper than repeating an expensive session). No new
# manifest — the relay/orphan/* refs ARE the registry. Static-structural checks on relay-loop.js.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"

# (1) the D3 marker is present.
grep -q "id:1f53" "$JS" || fail "no id:1f53 (D3 suppress-redispatch) marker in relay-loop.js"

# (2) discovery binds a parked orphan back to its ROADMAP item via git show --stat.
grep -Eq "show --stat" "$JS" \
  || fail "discovery does not bind a parked orphan to its ROADMAP item via 'git show --stat'"

# (3) a still-OPEN bound item suppresses fresh dispatch (don't repeat the expensive session).
grep -Eqi "suppress" "$JS" \
  || fail "discovery does not suppress fresh dispatch of an item with parked partial work"

# (4) the surfaced line carries a best-effort relay-burn cost hint.
grep -Eq "relay-burn" "$JS" \
  || fail "suppressed orphan is surfaced without a relay-burn cost hint"

pass "discovery binds parked orphan→item, suppresses re-dispatch of still-open items, surfaces relay-burn cost hint (1f53)"
