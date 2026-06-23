#!/usr/bin/env bash
# roadmap:ad74 — discover-shard must treat an open [INTENSIVE — <res>] item as WORK,
# never classify the repo idle (symmetric PROMOTE counterpart to the id:000d DEMOTE guard).
#
# Static, hermetic, zero-token guard (no model judgment exercised). Asserts the two-part
# mechanize-the-judgment fix is present:
#   1. the discover-shard prompt in relay-loop.js instructs that an open [INTENSIVE] item
#      is never idle (it must emit a unit with `intensive` set);
#   2. relay-loop.js carries the deterministic intensive field through the schema AND has a
#      JS-side promote backstop (so a shard ignoring the instruction is self-corrected);
#   3. gather-repo-state.sh emits the top_intensive field.
# Modeled on tests/test_relay_loop_structure.sh §id:000d/401c.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
GATHER="$SRC_DIR/relay/scripts/gather-repo-state.sh"
pass=0 fail=0
ok()   { echo "ok: $*"; pass=$((pass+1)); return 0; }
fail() { echo "FAIL: $*"; fail=$((fail+1)); return 0; }

[[ -f "$JS" ]]     || { echo "FAIL: relay-loop.js missing"; exit 1; }
[[ -f "$GATHER" ]] || { echo "FAIL: gather-repo-state.sh missing"; exit 1; }

# (1) Shard-prompt instruction: an open [INTENSIVE] item is WORK, never idle.
grep -q "id:ad74" "$JS" \
  || fail "id:ad74: no id:ad74 marker in relay-loop.js (INTENSIVE-emit rule rationale missing)"

# (2a) DISCOVER_SCHEMA carries the deterministic intensive field through to the unit, so the
#      JS-side backstop's value is never undefined (the same dead-guard hazard as id:401c).
grep -q "top_intensive: { type: 'string' }" "$JS" \
  || fail "id:ad74: DISCOVER_SCHEMA does not declare unit.top_intensive — the JS-side promote guard's value is always undefined (dead guard)"

# (2b) JS-side promote backstop block.
grep -qiE "INTENSIVE.*promote|promote.*intensive" "$JS" \
  || fail "id:ad74: no JS-side [INTENSIVE] promote backstop block in relay-loop.js"

# (3) gather-repo-state.sh emits top_intensive (resource of the top open [INTENSIVE — <res>]
#     item, "" when none) — the deterministic source the schema carries.
grep -q "top_intensive" "$GATHER" \
  || fail "id:ad74: gather-repo-state.sh does not emit top_intensive"

echo "---"
echo "pass=$pass fail=$fail"
[[ $fail -eq 0 ]] && { echo "PASS: id:ad74 INTENSIVE-emit guard present (shard rule + schema + JS backstop + gather field)"; exit 0; }
exit 1
