#!/usr/bin/env bash
# NO `# roadmap:` header ON PURPOSE — id:b54b is a TODO item, not a ROADMAP item, so per
# tests/run-tests.sh's own convention this file's failures are NEVER expected-red.
#
# id:b54b part (b), regression lock: the two test files named as the prime suspect for
# the 2026-08-22 `relay/ok` leak (tests/test_integrate_post_push_handback_5fe2.sh,
# tests/test_integrate_failed_push_ratification_5155.sh) must FAIL CLOSED — refuse to
# create a `relay/*` branch — if their fixture path variable ever points somewhere other
# than inside their own `$TMP` sandbox, instead of silently operating on whatever repo
# happens to be the caller's cwd (`git -C ""` falls back to cwd — confirmed live in this
# git version; see id:b54b's investigation notes).
#
# Direct empirical repro of the ORIGINAL leak was RULED OUT for both named files' current
# logic (integrate.sh itself hard-requires --path non-empty; both files already avoid the
# `local a="$1" b="$a"` same-statement gotcha; a broken $TMPDIR fails LOUDLY under
# unwritable-root paths rather than silently falling back to cwd — all reproduced and
# ruled out in a throwaway mktemp sandbox). This test instead locks in the STRUCTURAL
# fail-closed fix added regardless of whether the exact original mechanism is known: an
# `in_tmp()` guard immediately before every `git worktree add -q -b relay/...` call site
# that actually creates a branch. It is a static/regression check (grep-based, mirroring
# case (E) in test_integrate_post_push_handback_5fe2.sh itself), not a re-exercise of the
# fixtures — those are already exercised at length by the two files' own test suites.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
F1="$SRC_DIR/tests/test_integrate_post_push_handback_5fe2.sh"
F2="$SRC_DIR/tests/test_integrate_failed_push_ratification_5155.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$F1" ]] || fail "fixture missing: $F1"
[[ -f "$F2" ]] || fail "fixture missing: $F2"

for f in "$F1" "$F2"; do
  name="$(basename "$f")"

  grep -qE '^\s*in_tmp\(\)\s*\{' "$f" \
    || fail "$name: no in_tmp() guard function defined"
  pass "$name: defines an in_tmp() guard"

  grep -qE '\[\[\s*-n\s*"\$TMP"\s*&&\s*-d\s*"\$TMP"\s*\]\]' "$f" \
    || fail "$name: does not assert \$TMP is a real, non-empty directory right after mktemp"
  pass "$name: asserts \$TMP is non-empty and a real directory before using it"

  # Every `git -C "$X" worktree add ... -b relay/...` call site (the ones that actually
  # CREATE a relay/* branch) must be preceded, in the same or an earlier line, by an
  # `in_tmp "$X"` check on that same variable within a short lookback window — cheap
  # enough as a line-proximity check without a full shell parser.
  worktree_lines="$(grep -noE 'git -C "\$[A-Za-z_]+" worktree add -q -b (relay/|"relay/)' "$f" || true)"
  [[ -n "$worktree_lines" ]] || fail "$name: expected at least one 'git -C ... worktree add -q -b relay/...' call site — did the fixture shape change?"
  count_sites=0
  count_guarded=0
  while IFS=: read -r lineno rest; do
    [[ -n "$lineno" ]] || continue
    (( ++count_sites ))
    var="$(sed -nE 's/.*git -C "\$([A-Za-z_]+)".*/\1/p' <<<"$rest")"
    [[ -n "$var" ]] || fail "$name:$lineno: could not extract the -C variable from: $rest"
    # look back up to 5 lines for an in_tmp guard mentioning the same variable
    window_start=$(( lineno > 5 ? lineno - 5 : 1 ))
    window="$(sed -n "${window_start},${lineno}p" "$f")"
    if grep -qE "in_tmp \"\\\$${var}\"" <<<"$window"; then
      (( ++count_guarded ))
    fi
  done <<<"$worktree_lines"
  [[ "$count_guarded" -eq "$count_sites" ]] \
    || fail "$name: $count_guarded/$count_sites relay/*-creating worktree-add call sites are guarded by in_tmp() — every one must be"
  pass "$name: all $count_sites relay/*-creating worktree-add call site(s) are guarded by in_tmp()"
done

echo "ALL PASS: id:b54b fail-closed guard is present at every relay/*-creating call site"
