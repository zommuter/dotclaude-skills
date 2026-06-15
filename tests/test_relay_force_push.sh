#!/usr/bin/env bash
# roadmap:de51
# STATIC safety checks for relay/scripts/force-push.sh — the controlled, deliberate-human
# force-push wrapper. The actual ssh/push path can't be exercised hermetically (no fievel),
# so this asserts the SAFETY INVARIANTS: confirm gate, --force-with-lease (never bare --force),
# guard re-arm in an EXIT trap, and strict-mode bash.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/relay/scripts/force-push.sh"

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

# 1. exists + executable
[ -f "$SCRIPT" ] || fail "force-push.sh not found at $SCRIPT"
[ -x "$SCRIPT" ] || fail "force-push.sh is not executable"
pass "force-push.sh exists and is executable"

# 2. refuses without the confirm gate — run against a bogus path WITHOUT FORCE_PUSH_CONFIRM.
#    The gate is checked first, so it must exit non-zero and never reach ssh/git.
out="$(FORCE_PUSH_CONFIRM= "$SCRIPT" /nonexistent/bogus/repo 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "ran without FORCE_PUSH_CONFIRM (expected non-zero exit, got 0)"
printf '%s' "$out" | grep -qi "REFUSED" || fail "refusal message missing when confirm gate unset"
printf '%s' "$out" | grep -qi "ssh" && fail "refusal output mentions ssh — gate not checked first"
pass "refuses without FORCE_PUSH_CONFIRM (exit $rc, no ssh attempted)"

# 2b. exit code is specifically 2 (clear refusal, distinct from runtime error)
[ "$rc" -eq 2 ] || fail "expected exit 2 on missing confirm, got $rc"
pass "refusal exits 2"

# 3. uses --force-with-lease and NOT a bare --force / push -f
grep -q -- '--force-with-lease' "$SCRIPT" || fail "does not use --force-with-lease"
pass "uses --force-with-lease"

# Disallow a bare --force or push -f on a real command line (the comment that explains
# 'NOT bare --force' is fine; assert no actual git push uses them).
if grep -E 'git .*push' "$SCRIPT" | grep -Eq -- '(--force([^-]|$)|push +-f|-f +)'; then
  fail "found a bare --force / push -f on a git push line (must be --force-with-lease only)"
fi
pass "no bare --force / push -f on any git push line"

# 4. re-arms the guard: restores denyNonFastForwards true, in a trap/EXIT
grep -Eq 'denyNonFastForwards (true|"true")' "$SCRIPT" || fail "never restores denyNonFastForwards true"
grep -Eq 'trap .*(EXIT|restore)' "$SCRIPT" || fail "no trap on EXIT to restore the guard"
pass "re-arms guard (denyNonFastForwards true) via an EXIT trap"

# 5. strict-mode bash
grep -q 'set -euo pipefail' "$SCRIPT" || fail "missing 'set -euo pipefail'"
pass "has set -euo pipefail"

echo "ALL PASS"
