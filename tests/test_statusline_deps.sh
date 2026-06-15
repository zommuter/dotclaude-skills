#!/usr/bin/env bash
# Defect-fix test (no roadmap item): the statusbar's external CLI deps must be checked at
# install time, classified by functional severity — ERROR (non-zero) on a missing CRITICAL dep
# (jq), WARN (zero exit) on a missing optional dep that only degrades a feature. Hermetic.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/statusline/check-deps.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$CHECK" ]] || fail "statusline/check-deps.sh not found"
bash -n "$CHECK" || fail "check-deps.sh is not valid bash"

# (1) all deps present on this host → exit 0
bash "$CHECK" >/dev/null 2>&1 || fail "check-deps errored with all deps present"
pass "all-deps-present → exit 0"

# Build a PATH that has bash + coreutils + the optional tools, so we can drop ONE tool at a time.
mkbin() { # $@ = tools to include
  local d; d=$(mktemp -d)
  local t p
  for t in "$@"; do p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$d/"; done
  echo "$d"
}
ALL=(bash sh stat date jq bc curl sha1sum)

# (2) jq missing → CRITICAL → exit 1 + a CRITICAL message
d=$(mkbin bash sh stat date bc curl sha1sum)   # everything except jq
out=$(PATH="$d" bash "$CHECK" 2>&1); rc=$?
rm -rf "$d"
[ "$rc" -eq 1 ] || fail "missing jq did not exit 1 (got $rc)"
echo "$out" | grep -qi 'CRITICAL' || fail "missing jq produced no CRITICAL message"
pass "missing critical dep (jq) → exit 1 + CRITICAL warning"

# (3) optional missing (bc) → WARN → exit 0 + a WARN message
d=$(mkbin bash sh stat date jq curl sha1sum)   # everything except bc
out=$(PATH="$d" bash "$CHECK" 2>&1); rc=$?
rm -rf "$d"
[ "$rc" -eq 0 ] || fail "missing optional bc must NOT fail install (got exit $rc)"
echo "$out" | grep -qi 'WARN' || fail "missing bc produced no WARN message"
pass "missing optional dep (bc) → exit 0 + WARN"

# (4) install-statusline actually runs the check
grep -q 'statusline/check-deps.sh' "$ROOT/Makefile" || fail "Makefile install-statusline does not run check-deps.sh"
grep -qE '^check-statusline-deps:' "$ROOT/Makefile" || fail "no standalone check-statusline-deps target"
pass "make install-statusline runs the dep check + standalone target exists"

echo "ALL PASS: statusline dependency check (critical=error, optional=warn)"
