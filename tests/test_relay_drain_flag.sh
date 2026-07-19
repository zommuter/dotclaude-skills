#!/usr/bin/env bash
# Feature guard for id:93fe Phase 1 — the `--drain` single-repo alias.
# Headerless (93fe is TODO-tracked, not ROADMAP) — per tests/ conventions its
# failures ALWAYS count. Phase 1 is a FRONT-DOOR alias (the front door is SKILL.md
# prose the apex model follows), so the definition-of-done is that SKILL.md documents
# `--drain` as a single-repo drain alias with the "already drains / not a new engine"
# framing, and surfaces `--parallel N` (id:ebbe) as the not-yet-built Phase 2.
# There is deliberately NO relay-loop.js engine change (the drain loop already exists
# via id:7633 + the inlined drain.mjs id:d58f/4ca8) — this test guards against a future
# edit silently dropping the alias documentation, NOT a runtime behaviour (relay-loop.js
# runs only in the Workflow sandbox, id:2d20).
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
SKILL="$ROOT/relay/SKILL.md"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]] || fail "relay/SKILL.md not found"

# (1) the --drain flag row exists in the config table
grep -qE '^\| `--drain` \|' "$SKILL" || fail "relay/SKILL.md config table has no \`--drain\` flag row"
pass "--drain flag row present in the config table"

# (2) it is framed as an ALIAS that already-drains (not a new engine) — the honest hint
grep -qiE '[-][-]drain.*(alias|already drain|not strictly needed|sugar, not a new engine)' "$SKILL" \
  || grep -qiE '(alias|already drains|not strictly needed|sugar, not a new engine)' <(grep -iA2 '`--drain`' "$SKILL") \
  || fail "--drain is not framed as a discoverability alias / 'already drains' (the owner-required hint)"
pass "--drain framed as an alias with the 'already drains' hint"

# (3) a Drain mode section exists
grep -qE '^## Drain mode$' "$SKILL" || fail "relay/SKILL.md has no '## Drain mode' section"
pass "Drain mode section present"

# (4) --parallel N is surfaced as the not-yet-built Phase 2 (id:ebbe)
grep -qE '`--parallel N`' "$SKILL" || fail "relay/SKILL.md does not mention \`--parallel N\`"
grep -qiE '[-][-]parallel.*(not yet built|not yet implemented|Phase 2|ebbe)' "$SKILL" \
  || grep -qiE '(not yet built|not yet implemented|ebbe)' <(grep -iA2 '`--parallel N`' "$SKILL") \
  || fail "--parallel N is not surfaced as the not-yet-built Phase 2 (id:ebbe)"
pass "--parallel N surfaced as not-yet-built Phase 2 (id:ebbe)"

echo "ALL PASS: id:93fe Phase 1 --drain alias documentation guard"
