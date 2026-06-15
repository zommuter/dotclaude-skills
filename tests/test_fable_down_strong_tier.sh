#!/usr/bin/env bash
# roadmap:5902 — separate Fable-availability (-d) from fallback policy (STRONG_TIER).
# Static structure checks: the FABLE_DOWN defer/demote block is gated on the strong model
# being the UNAVAILABLE Fable, so -d + STRONG_TIER=opus substitutes Opus instead of deferring.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
SKILL="$SRC_DIR/relay/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
[[ -f "$SKILL" ]] || fail "SKILL.md not found at $SKILL"

# relay-loop.js: the defer/demote block is gated so it ONLY fires when the strong model is
# the unavailable Fable (claude-fable-5), not under the Opus-substitute path.
grep -qE "FABLE_DOWN && STRONG_MODEL === 'claude-fable-5'" "$JS" \
  || fail "relay-loop.js does not gate the FABLE_DOWN defer block on STRONG_MODEL === 'claude-fable-5'"
pass "FABLE_DOWN defer/demote block gated on STRONG_MODEL === 'claude-fable-5'"

# relay-loop.js: bare `if (FABLE_DOWN) {` (ungated) defer block must NOT exist — that would
# wrongly defer strong work even under STRONG_TIER=opus.
if grep -qE '^\s*if \(FABLE_DOWN\) \{' "$JS"; then
  fail "relay-loop.js still has an ungated 'if (FABLE_DOWN) {' defer block — -d + opus would wrongly defer"
fi
pass "no ungated 'if (FABLE_DOWN) {' defer block remains"

# relay-loop.js: the comment documents the substitute (Opus) path as NOT deferring.
grep -qi "substitute" "$JS" \
  || fail "relay-loop.js does not document the Opus substitute path for -d + STRONG_TIER=opus"
pass "relay-loop.js documents the Opus substitute path"

# SKILL.md: knobs row documents the two-axis compose (defer vs substitute).
grep -qi "substitute" "$SKILL" \
  || fail "SKILL.md --fable-down row does not document the substitute (opus) composition"
pass "SKILL.md documents -d × STRONG_TIER substitute composition"

# SKILL.md: usage example for the combined -d --strong-tier opus invocation.
grep -qE '/relay -d --strong-tier opus' "$SKILL" \
  || fail "SKILL.md missing '/relay -d --strong-tier opus' usage example"
pass "SKILL.md shows '/relay -d --strong-tier opus' usage example"
