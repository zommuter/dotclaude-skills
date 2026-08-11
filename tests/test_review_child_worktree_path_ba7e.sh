#!/usr/bin/env bash
# roadmap:ba7e — id:34b7 part (3) is incomplete: review children still get the MAIN checkout path.
#
# RED SPEC authored at handoff 2026-08-11. relay-loop.js:2176 still interpolates `unit.path` into
# the REVIEW child's prompt (`append.sh new-ids N ' + unit.path`). tests/test_parent_creates_worktree_34b7.sh
# assertion 1 greps only the literal `main checkout: ${unit.path}`, so it never covered this path.
# id:34b7 is [x] in ROADMAP.archive.md — this is the uncovered remainder, filed separately rather
# than reopening an archived item.
#
# DELIBERATELY PERMISSIVE ON DIRECTION, STRICT ON SILENCE. The review child may legitimately need
# a canonical-checkout path for a ledger-write helper. This spec does NOT force removal — it
# forces the choice to be EXPLICIT. Either no review prompt interpolates unit.path, or the one
# that does carries a comment naming why. What it refuses to allow is a bare unit.path with no
# stated reason, which is indistinguishable from the bug.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]] || fail "relay-loop.js not found at $JS"
node --check "$JS" || fail "relay-loop.js fails node --check"

# Every line that splices unit.path into a prompt string (the review-child site is one of them).
mapfile -t hits < <(grep -n "unit\.path" "$JS" | grep -vE "worktreePathFor|provision-worktree|^\s*//" || true)

# Lines that are part of a prompt: they concatenate into a template/string literal.
prompt_hits=()
for h in "${hits[@]}"; do
  ln="${h%%:*}"
  txt="${h#*:}"
  # A prompt splice looks like  ' + unit.path  or  ${unit.path}  inside a quoted string.
  if grep -qE "(\+ *unit\.path|\\$\{unit\.path\})" <<<"$txt"; then
    prompt_hits+=("$ln:$txt")
  fi
done

if [[ ${#prompt_hits[@]} -eq 0 ]]; then
  pass "no prompt interpolates unit.path — the review child never sees the main checkout"
else
  # Each surviving splice must carry an explicit justification within the 5 lines above it.
  for ph in "${prompt_hits[@]}"; do
    ln="${ph%%:*}"
    ctx="$(awk -v n="$ln" 'NR>=n-5 && NR<n' "$JS")"
    grep -qiE "main.checkout|canonical|deliberate|intentional|EXCEPTION|why" <<<"$ctx" \
      || fail "relay-loop.js:$ln splices unit.path into a prompt with NO comment justifying it (id:34b7 part 3) — remove it or state explicitly why the canonical checkout is needed here:
    ${ph#*:}"
  done
  pass "every surviving unit.path prompt splice carries an explicit justification (${#prompt_hits[@]} site(s))"
fi

# ── ADDED at ba7e's fix (strengthening only — nothing above was relaxed) ─────────────────
# The resolution was NOT "documented exception": the review child's only use of the path was
# `append.sh new-ids N <root>`, whose root is a READ-ONLY collision scan over
# docs/meeting-notes + TODO.md + TODO.archive.md + ROADMAP.md (meeting/append.sh scan_ids).
# Every one of those files exists in the provisioned worktree, and the worktree additionally
# sees ids the child itself just minted — so it is a strict SUPERSET of the main checkout's
# collision set, not a compromise. Pin that the instruction now points at the worktree.
grep -q "append.sh new-ids N ' + wt + '" "$JS" \
  || fail "the review child's new-ids root is no longer the provisioned worktree — id:34b7 part 3 regressed"
pass "the review child mints ids against its own worktree, never the main checkout"

# The execute-side guarantee id:34b7 established must NOT regress while fixing the review side.
grep -q 'main checkout: ${unit.path}' "$JS" \
  && fail "the 'main checkout: \${unit.path}' literal is back in a prompt — id:34b7's core guarantee regressed"
pass "the execute-side 'main checkout' literal is still absent"

# The existing 34b7 spec must still pass — do not weaken it while extending coverage (rule 3).
SIB="$SRC_DIR/tests/test_parent_creates_worktree_34b7.sh"
if [[ -f "$SIB" ]]; then
  bash "$SIB" >/dev/null 2>&1 || fail "tests/test_parent_creates_worktree_34b7.sh now fails — the sibling spec was broken by this work"
  pass "the existing id:34b7 spec still passes"
fi

echo "ALL PASS: review children are not handed the main checkout (ba7e)"
