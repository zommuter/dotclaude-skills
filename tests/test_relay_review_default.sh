#!/usr/bin/env bash
# roadmap:d53c — /relay review defaults to the cwd repo; --all (or a repo-list)
# opts into the cross-repo sweep (consistency with /relay executor, least-surprise).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$SRC_DIR/relay/SKILL.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# 0. The skill exists.
[[ -f "$SKILL" ]] || fail "relay/SKILL.md missing"
pass "relay/SKILL.md exists"

# 1. The invocation block still documents /relay review.
grep -q '/relay review' "$SKILL" || fail "SKILL.md no longer documents '/relay review'"
pass "SKILL.md documents '/relay review'"

# 2. The default scope is the cwd / current repo (not --all).
grep -qiE 'review.*(cwd|current) repo' "$SKILL" \
  || grep -qiE 'default scope is the cwd repo' "$SKILL" \
  || fail "SKILL.md does not state '/relay review' defaults to the cwd/current repo"
pass "'/relay review' default scope is the cwd/current repo"

# 3. The default is anchored to git rev-parse --show-toplevel.
grep -q 'git rev-parse --show-toplevel' "$SKILL" \
  || fail "SKILL.md review default does not reference git rev-parse --show-toplevel"
pass "review default anchored to git rev-parse --show-toplevel"

# 4. --all (or a repo-list) is the opt-in for the cross-repo sweep.
grep -qiE '[-][-]all.*(cross-repo )?sweep' "$SKILL" \
  || grep -qiE 'sweep.*--all' "$SKILL" \
  || fail "SKILL.md does not state --all opts into the cross-repo sweep"
pass "--all (or a repo-list) opts into the cross-repo sweep"

# 5. The flip away from the old default is explicit.
grep -qiE 'flips? the historical default|no longer mean' "$SKILL" \
  || fail "SKILL.md does not make the default flip explicit"
pass "the default flip is explicit (bare review no longer means --all)"

echo "ALL PASS"
