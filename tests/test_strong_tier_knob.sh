#!/usr/bin/env bash
# roadmap:aeaf — STRONG_TIER config knob: static grep checks for relay-loop.js and SKILL.md

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/fables-turn/scripts/relay-loop.js"
SKILL="$SRC_DIR/fables-turn/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# relay-loop.js must exist and reference STRONG_TIER
[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
pass "relay-loop.js exists"

grep -q "STRONG_TIER" "$JS" || fail "relay-loop.js does not reference STRONG_TIER"
pass "relay-loop.js references STRONG_TIER"

grep -q "'fable'" "$JS" || fail "relay-loop.js has no 'fable' default"
pass "relay-loop.js has fable default"

grep -q "'opus'" "$JS" || fail "relay-loop.js does not reference opus tier"
pass "relay-loop.js references opus tier"

# Execute agents must not receive the STRONG_TIER model override
# (the stub's inline comment makes this statically verifiable)
grep -q "no model override" "$JS" || fail "relay-loop.js does not document Sonnet execute-agent exclusion"
pass "relay-loop.js documents execute agent exclusion from STRONG_TIER"

# SKILL.md must document the knob
[[ -f "$SKILL" ]] || fail "SKILL.md not found at $SKILL"
grep -q "STRONG_TIER" "$SKILL" || fail "SKILL.md does not document STRONG_TIER"
pass "SKILL.md documents STRONG_TIER"

grep -q "STRONG_TIER=opus" "$SKILL" || fail "SKILL.md does not show STRONG_TIER=opus usage example"
pass "SKILL.md shows opus usage example"

grep -q "fable.*claude-fable-5\|claude-fable-5.*fable" "$SKILL" || fail "SKILL.md does not map fable to claude-fable-5"
pass "SKILL.md maps fable to claude-fable-5"

grep -q "opus.*claude-opus-4-8\|claude-opus-4-8.*opus" "$SKILL" || fail "SKILL.md does not map opus to claude-opus-4-8"
pass "SKILL.md maps opus to claude-opus-4-8"
