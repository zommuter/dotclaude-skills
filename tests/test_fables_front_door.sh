#!/usr/bin/env bash
# roadmap:230f — autonomous relay front door: /fables-turn no-keyword default mode
#
# The front door is a prose skill (SKILL.md drives the orchestrator turn), so —
# like tests/test_fables_executor.sh — this is a static contract check on the
# skill spec plus the Workflow-args pass-through in relay-loop.js. Behavioral
# verification of the live loop is gated to the id:1ad7 pilot.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$SRC_DIR/fables-turn/SKILL.md"
JS="$SRC_DIR/fables-turn/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]] || fail "SKILL.md not found at $SKILL"
pass "SKILL.md exists"

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
pass "relay-loop.js exists"

# (1) No-keyword invocation is documented as the autonomous default mode.
grep -qE '^/fables-turn[[:space:]]*(#.*)?$' "$SKILL" \
  || fail "SKILL.md invocation block has no bare no-keyword /fables-turn line"
pass "SKILL.md documents bare /fables-turn invocation"

grep -qi "autonomous" "$SKILL" || fail "SKILL.md does not describe the autonomous default mode"
pass "SKILL.md describes autonomous default mode"

# Default mode invokes the relay-loop.js Workflow script.
grep -q "relay-loop.js" "$SKILL" || fail "SKILL.md does not reference relay-loop.js"
pass "SKILL.md references relay-loop.js"

# Non-interactive by default; operates only on confirmed own repos.
grep -qi "non-interactive" "$SKILL" || fail "SKILL.md does not state the non-interactive default"
pass "SKILL.md states non-interactive default"

# New/dirty/needs_review repos are surfaced in RELAY_STATUS.md, never asked about.
grep -q "RELAY_STATUS.md" "$SKILL" || fail "SKILL.md does not mention RELAY_STATUS.md surfacing"
pass "SKILL.md mentions RELAY_STATUS.md"

# No confirmed repos → notice + clean exit (no Workflow launch, no error).
grep -qi "exits\? cleanly" "$SKILL" \
  || fail "SKILL.md does not document the no-confirmed-repos clean-exit behavior"
pass "SKILL.md documents no-confirmed-repos clean exit"

# After the Workflow completes: print RELAY_STATUS.md path + HANDBACK count.
grep -qi "HANDBACK count" "$SKILL" || fail "SKILL.md does not document printing the HANDBACK count"
pass "SKILL.md documents HANDBACK-count summary"

# (2) --interactive flag: documented, re-enables AskUserQuestion, passed to Workflow args.
grep -q -- "--interactive" "$SKILL" || fail "SKILL.md does not document the --interactive flag"
pass "SKILL.md documents --interactive flag"

grep -q "AskUserQuestion" "$SKILL" || fail "SKILL.md does not tie --interactive to AskUserQuestion"
pass "SKILL.md ties --interactive to AskUserQuestion"

grep -q "args.interactive\|args\.interactive" "$JS" \
  || fail "relay-loop.js does not receive the interactive flag via Workflow args"
pass "relay-loop.js receives args.interactive"

# The Workflow script itself never prompts (unattended-by-default invariant, D2).
if grep -q "AskUserQuestion" "$JS"; then
  fail "relay-loop.js must never call AskUserQuestion (unattended Workflow)"
fi
pass "relay-loop.js contains no AskUserQuestion call"

# (3) Existing keyword modes remain documented and unchanged.
grep -q "/fables-turn handoff" "$SKILL" || fail "SKILL.md lost the handoff keyword mode"
pass "SKILL.md keeps handoff keyword mode"

grep -q "/fables-turn review" "$SKILL" || fail "SKILL.md lost the review keyword mode"
pass "SKILL.md keeps review keyword mode"
