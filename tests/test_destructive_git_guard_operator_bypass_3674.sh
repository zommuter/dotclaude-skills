#!/usr/bin/env bash
# No roadmap header -- defect-fix spec for TODO id:3674, filed directly into TODO.md.
# Failures always count.
#
# id:3674 -- `hooks/destructive-git-guard.py` ALLOWED `git reset --hard` whenever it was
# preceded by a safe `git` subcommand and a NEWLINE or an unspaced `;`.
#
# MEASURED before the fix (both reproduced independently by two sessions):
#   git reset --hard X                  -> DENY
#   git status\ngit reset --hard X      -> ALLOWED   <-- bypass
#   git status; git reset --hard X      -> ALLOWED   <-- bypass
#   git status && git reset --hard X    -> DENY      (spaces made `&&` a standalone token)
#   echo hi\ngit reset --hard X         -> DENY      (no leading `git` to swallow it)
#
# ROOT CAUSE, and the reason the obvious fix is wrong: `_OPERATORS` ALREADY contains `;`
# and `\n`. They were erased one layer earlier. `_find_violation_tokenised` tokenised with
# `shlex.split()`, which eats a newline as whitespace and GLUES a `;` to the preceding
# token ('git status; git reset' -> [..., 'status;', 'git', ...]). `_split_git_commands`
# therefore saw no boundary, opened its accumulator at the FIRST `git`, and swallowed the
# second command into one argv whose subcommand read `status`; `classify_git_argv`
# returned safe and the `reset --hard` was never classified at all. Adding `\n` to
# `_OPERATORS` would have changed nothing.
#
# WHY THIS MATTERED: `git status` before a destructive operation is the single most
# natural thing an agent writes, so the bypass sat on the DEFAULT path, not an
# adversarial edge. It was found because a relay execute child ran verbatim
# `git status --porcelain` + newline + `git reset --hard <sha>` against a repo's main
# checkout. The owner had been told this guard denied unconditionally; it did not.
#
# Contract asserted here:
#   a. A destructive form preceded by a safe `git` subcommand + NEWLINE is DENIED.
#   b. Same with an unspaced `;` separator.
#   c. Forms that already worked still work (`&&`, bare, non-git prefix) -- no regression.
#   d. No false positives: the destructive phrase QUOTED inside a commit message, and
#      the non-tree-wide `reset --soft`, stay ALLOWED. Quoting awareness must survive
#      the tokeniser change.
#
# fails-against: the defect and its fix land in the same commit as this spec, so there is
# no ancestor tree to check out; the negative case is the mutation below, which restores
# the original `shlex.split()` tokenisation that erased the operators.
# fails-against-mutation: sed -i 's/command\.replace("\\n", ";")/command/' hooks/destructive-git-guard.py
# fails-against-assertion: newline-separated destructive form must be DENIED
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/hooks/destructive-git-guard.py"

[ -f "$GUARD" ] || { echo "FAIL: guard not found at $GUARD"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

# verdict <command> -> prints DENY or ALLOW.
# The hook signals a refusal by EMITTING output; silence means the command is permitted.
verdict() {
  printf '%s' "$1" > "$tmp/cmd"
  python3 - "$tmp/cmd" > "$tmp/payload" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Bash",
                  "tool_input": {"command": open(sys.argv[1]).read()}}))
PY
  if [ -s "$tmp/payload" ] && python3 "$GUARD" < "$tmp/payload" > "$tmp/out" 2>&1; then :; fi
  if [ -s "$tmp/out" ]; then echo DENY; else echo ALLOW; fi
}

# ── (c) FIRST: the forms that already worked. Asserted before the bypass cases so a
#        guard that simply denies EVERYTHING cannot vacuously satisfy (a) and (b).
[ "$(verdict 'git reset --hard abc')" = DENY ] \
  || report "regression: a bare destructive form must be DENIED"
[ "$(verdict 'git status && git reset --hard abc')" = DENY ] \
  || report "regression: an && separated destructive form must be DENIED"
[ "$(verdict 'git clean -fd')" = DENY ] \
  || report "regression: git clean -fd must be DENIED"

# ── (d) no false positives -- quoting awareness must survive the tokeniser change.
[ "$(verdict 'git status --porcelain')" = ALLOW ] \
  || report "false positive: a plain status must be ALLOWED"
[ "$(verdict 'git reset --soft HEAD~1')" = ALLOW ] \
  || report "false positive: reset --soft is not tree-wide and must be ALLOWED"
[ "$(verdict 'git commit -m "git reset --hard is banned"')" = ALLOW ] \
  || report "false positive: the phrase QUOTED in a commit message must be ALLOWED"

# ── (a) THE DEFECT: newline separator. This is the shape a real execute child ran.
[ "$(verdict 'git status --porcelain
git reset --hard abc')" = DENY ] \
  || report "newline-separated destructive form must be DENIED"

# ── (b) THE DEFECT: unspaced semicolon separator.
[ "$(verdict 'git status; git reset --hard abc')" = DENY ] \
  || report "semicolon-separated destructive form must be DENIED (unspaced ; is glued by shlex)"

if (( fail )); then
  exit 1
fi
echo "PASS: destructive-git-guard denies across newline and unspaced-semicolon separators (id:3674)"
