#!/usr/bin/env bash
# roadmap:6e9d — a freed dispatch lane pulls pending injections mid-round (poll-once-on-drain)
# so an injected unit runs as soon as a slot frees with the queue empty, instead of idling
# until the round boundary. Static-structural checks on relay-loop.js (live dispatch behaviour
# is too expensive to unit-test; mirrors test_relay_loop_structure.sh).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"

# (0) the change is JS-valid
node --check "$JS" || fail "relay-loop.js fails node --check"

# (1) a dedicated mid-round take function exists, distinct from the discovery-time take.
grep -q "function takeInjections" "$JS" || fail "no takeInjections() — lanes can't pull mid-round injections (id:6e9d)"
grep -q "INJECT_TAKE_SCHEMA" "$JS" || fail "no INJECT_TAKE_SCHEMA for the take-agent"

# (2) takeInjections runs inject.sh take inside an agent (the script can't shell directly).
grep -Eq "inject.sh take" "$JS" || fail "takeInjections does not invoke 'inject.sh take'"

# (3) the dispatch lane polls injections ONLY when the queue is drained (poll-once-on-drain,
#     not a busy-spin every iteration): a `if (!queue.length)` guard that calls takeInjections
#     and pushes onto the live queue before breaking.
grep -q "await takeInjections()" "$JS" || fail "the dispatch lane never calls takeInjections()"
grep -q "id:6e9d" "$JS" || fail "no id:6e9d marker tying the change to the roadmap item"

# (4) the freed lane pushes injected units onto the LIVE queue and continues (runs them now),
#     rather than waiting for the next round's discovery.
grep -Eq "queue.push\(\.\.\.injected\)" "$JS" || fail "injected units are not pushed onto the live queue"

# (5) no busy-spin: takeInjections short-circuits under the run-ending gates.
grep -Eq "quotaStopped \|\| roundCapHit \|\| unitsDispatched >= MAX_UNITS" "$JS" \
  || fail "takeInjections does not short-circuit on quota/cap/MAX_UNITS (busy-spin risk)"

pass "freed lane polls inject.sh take on drain, pushes onto live queue, gated against busy-spin (6e9d)"
