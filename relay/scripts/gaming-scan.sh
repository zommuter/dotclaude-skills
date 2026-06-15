#!/usr/bin/env bash
# gaming-scan.sh — mechanical gaming-detector extracted from review.md §2 (id:fa05).
#
# Usage: gaming-scan.sh <repo-root> <since-tag>
#   <repo-root>  — absolute path to the git repo root being reviewed
#   <since-tag>  — git ref (tag or commit) marking the start of the review window
#
# Emits one parseable flag line per mechanical detection to STDOUT:
#   DELETED_TEST:<path>          — test file deleted since <since-tag>
#   ADDED_SKIP:<path>:<line>     — skip/xfail/.only/@pytest.mark.skip added to a test file
#   REMOVED_ASSERT:<path>:<line> — assert/expectation line removed without net addition
#
# Exit codes:
#   0 — ran successfully (flags may or may not have been emitted)
#   1 — usage error or git failure
#
# The caller (review.md §2) runs this first for the cheap deterministic pass;
# the judgment residue (resurrection-check, fixture-special-casing) stays in prose.
#
# Patterns intentionally NOT handled here (model judgment required):
#   - resurrection-check (run original test against new code)
#   - fixture special-casing (code branching on test-literal inputs)
#
# Hermetically testable — all git operations are constrained to <repo-root>.
set -euo pipefail

usage() {
  echo "usage: gaming-scan.sh <repo-root> <since-tag>" >&2
  exit 1
}

[ $# -ge 2 ] || usage
REPO_ROOT="$1"
SINCE="$2"

[ -d "$REPO_ROOT/.git" ] || [ -f "$REPO_ROOT/.git" ] || {
  echo "gaming-scan.sh: $REPO_ROOT does not look like a git repo" >&2; exit 1; }

cd "$REPO_ROOT"

# Verify the since-tag/ref exists
git rev-parse --verify "$SINCE^{}" >/dev/null 2>&1 || {
  echo "gaming-scan.sh: since-ref '$SINCE' not found in repo" >&2; exit 1; }

# ── Test directory heuristics ──
# Standard locations for test files. We match any file under these directories
# whose name looks like a test (test_*, *_test.*, *.spec.*, *_spec.*).
TEST_DIRS=(tests test spec __tests__)

# Build a pathspec for git diff — include any directory that exists.
test_pathspecs=()
for d in "${TEST_DIRS[@]}"; do
  [ -d "$d" ] && test_pathspecs+=("$d")
done
# Also match files at repo root with test-naming conventions.
test_pathspecs+=("*.sh" "*.py" "*.js" "*.ts")

# ──────────────────────────────────────────────────────────────────────────────
# Check 1: Deleted test files (automatic flag — any test file removed is suspect)
# ──────────────────────────────────────────────────────────────────────────────
while IFS= read -r path; do
  [ -z "$path" ] && continue
  # Only flag files in test directories or with test-naming convention
  basename="$(basename "$path")"
  if printf '%s' "$path" | grep -qE '(^|/)(tests?|spec|__tests__)/|test_|_test\.|\.spec\.|_spec\.'; then
    echo "DELETED_TEST:$path"
  fi
done < <(git diff "$SINCE"..HEAD --diff-filter=D --name-only 2>/dev/null || true)

# ──────────────────────────────────────────────────────────────────────────────
# Check 2: Added skip/xfail/.only/@pytest.mark.skip in test files
# Patterns that were ADDED (context lines with +) in the diff of test files.
# ──────────────────────────────────────────────────────────────────────────────
SKIP_PATTERN='(\.skip\b|\.only\b|xfail|@pytest\.mark\.skip|# skip|# SKIP|\bskip\(|it\.skip|describe\.skip|test\.skip)'

while IFS= read -r path; do
  [ -z "$path" ] && continue
  # Is this a test file?
  if printf '%s' "$path" | grep -qE '(^|/)(tests?|spec|__tests__)/|test_|_test\.|\.spec\.|_spec\.'; then
    # Look for added lines matching skip patterns
    lineno=0
    while IFS= read -r diff_line; do
      # Count line number from diff header @@ -a,b +c,d @@ ... extract c
      if [[ "$diff_line" =~ ^@@.*\+([0-9]+) ]]; then
        lineno="${BASH_REMATCH[1]}"
        continue
      fi
      # Added lines start with +, not ++
      if [[ "$diff_line" =~ ^\+[^+] ]]; then
        content="${diff_line:1}"
        if printf '%s' "$content" | grep -qEi "$SKIP_PATTERN"; then
          echo "ADDED_SKIP:$path:$lineno"
        fi
        (( lineno++ )) || true
      elif [[ "$diff_line" =~ ^[^-] ]]; then
        (( lineno++ )) || true
      fi
    done < <(git diff "$SINCE"..HEAD -- "$path" 2>/dev/null || true)
  fi
done < <(git diff "$SINCE"..HEAD --name-only -- "${test_pathspecs[@]}" 2>/dev/null || true)

# ──────────────────────────────────────────────────────────────────────────────
# Check 3: Removed assert/expectation lines without net addition
# A test file that lost more assertion lines than it gained is flagged.
# "Assertion lines" = lines containing assert/expect/assertEqual/assertTrue/
#   assertRaises/should/must/verify keywords in test context.
# ──────────────────────────────────────────────────────────────────────────────
# Match lines containing assert/expect/should/must/verify keywords.
# \bassert (without trailing \b) matches assert, assert_eq, assertTrue, etc.
# \bexpect( with paren matches expect( calls (avoids matching "expected").
ASSERT_PATTERN='(\bassert|\bexpect\(|\bshould\b|\bmust\b|\bverify\b)'

while IFS= read -r path; do
  [ -z "$path" ] && continue
  if printf '%s' "$path" | grep -qE '(^|/)(tests?|spec|__tests__)/|test_|_test\.|\.spec\.|_spec\.'; then
    removed=0
    added=0
    while IFS= read -r diff_line; do
      # Removed lines (start with -)
      if [[ "$diff_line" =~ ^-[^-] ]]; then
        content="${diff_line:1}"
        if printf '%s' "$content" | grep -qEi "$ASSERT_PATTERN"; then
          (( removed++ )) || true
        fi
      # Added lines (start with +)
      elif [[ "$diff_line" =~ ^\+[^+] ]]; then
        content="${diff_line:1}"
        if printf '%s' "$content" | grep -qEi "$ASSERT_PATTERN"; then
          (( added++ )) || true
        fi
      fi
    done < <(git diff "$SINCE"..HEAD -- "$path" 2>/dev/null || true)
    if [ "$removed" -gt "$added" ]; then
      echo "REMOVED_ASSERT:$path:removed=${removed},added=${added}"
    fi
  fi
done < <(git diff "$SINCE"..HEAD --name-only -- "${test_pathspecs[@]}" 2>/dev/null || true)

exit 0
