#!/usr/bin/env bash
# roadmap:f9ad — /relay next: a quick auto-router that inspects the cwd repo's state
# and acts (executor / review / human), minimizing the human-or-not decision.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$SRC_DIR/relay/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# 0. The skill exists.
[[ -f "$SKILL" ]] || fail "relay/SKILL.md missing"
pass "relay/SKILL.md exists"

# 1. /relay next appears in the invocation block.
grep -q '/relay next' "$SKILL" || fail "SKILL.md does not document '/relay next'"
pass "SKILL.md documents '/relay next'"

# 2. A Next mode section exists.
grep -qiE '^##[[:space:]]+Next mode' "$SKILL" \
  || fail "SKILL.md has no '## Next mode' section"
pass "'## Next mode' section exists"

# 3. It decides among executor / review / human.
grep -qi 'executor' "$SKILL" || fail "Next mode does not mention executor route"
grep -qi 'review' "$SKILL"   || fail "Next mode does not mention review route"
grep -qi 'human' "$SKILL"    || fail "Next mode does not mention human route"
pass "Next mode routes among executor / review / human"

# 4. It operates on the cwd repo by default.
grep -qiE 'cwd repo by default|operates on the .*cwd' "$SKILL" \
  || fail "Next mode does not state it operates on the cwd repo by default"
pass "Next mode operates on the cwd repo by default"

# 5. It minimizes the human-or-not decision / prefers acting over asking.
grep -qiE 'human-or-not' "$SKILL" \
  || fail "Next mode does not reference the human-or-not decision"
grep -qiE 'without asking|prefer acting over asking|do NOT ask' "$SKILL" \
  || fail "Next mode does not say it acts without asking when it can"
pass "Next mode minimizes the human-or-not decision (acts without asking)"

echo "ALL PASS"
