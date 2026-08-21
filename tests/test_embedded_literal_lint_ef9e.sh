#!/usr/bin/env bash
# roadmap:ef9e — embedded Python/awk literal quoting-hazard lint.
#
# Guards relay/scripts/lint-embedded-literals.mjs, which extracts a Python or awk program
# embedded in a bash single-quoted CLI argument (`python3 -c '…'` / `awk '…'`) and runs the
# GUEST language's own syntax checker against it. `discover-repo.sh` once embedded a ~90-line
# Python program in a single-quoted `python3 -c '...'`; a comment containing an apostrophe
# closed the bash single-quote early (bash single-quotes have NO escaping — the FIRST `'`
# after the opening one ends the string). `bash -n` stayed clean (the truncated remainder was
# still syntactically valid bash), and the corruption surfaced only at runtime as a Python
# `IndentationError`. This suite proves the linter (a) REJECTS a corrupted embedded body,
# naming the file and language, (b) PASSES a syntactically valid one, (c) REJECTS a corrupted
# embedded awk body too, (d) reports an un-isolable body (concatenation/interpolation) as
# UNCHECKED rather than silently treating it as clean, and (e) the real tree lints clean.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/lint-embedded-literals.mjs"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LINT" ]] || fail "lint-embedded-literals.mjs not found at $LINT"
node --check "$LINT" || fail "lint-embedded-literals.mjs fails node --check"
pass "linter exists and parses"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# (1) A fixture with an apostrophe-corrupted embedded Python body → nonzero, names the file
#     and the guest language. The apostrophe inside the comment closes the bash single-quote
#     early (bash single-quotes have NO escaping — the FIRST `'` ends the string), truncating
#     the body right after an "if True:" with nothing but a comment as its body — exactly the
#     discover-repo.sh incident's failure shape (IndentationError: expected an indented block).
cat > "$TMP/bad_py.sh" <<'EOF'
#!/usr/bin/env bash
result="$(python3 -c '
import sys
if True:
    # the other scripts' quoting habits are handled elsewhere, not here
    x = 1
')"
EOF
if out="$(node "$LINT" "$TMP/bad_py.sh" 2>&1)"; then
  fail "linter did NOT flag an apostrophe-truncated embedded python body:
$out"
fi
grep -qE 'bad_py\.sh:2:' < <(echo "$out") \
  || fail "linter flagged but did not name the offending file:line (expected bad_py.sh:2:…):
$out"
grep -qi 'python' < <(echo "$out") \
  || fail "linter flagged but did not name the guest language:
$out"
pass "(1) apostrophe-truncated embedded python body → nonzero, names file:line and language"

# (2) A fixture with a syntactically VALID embedded python body → exit zero.
cat > "$TMP/good_py.sh" <<'EOF'
#!/usr/bin/env bash
result="$(python3 -c '
import sys, json
data = json.load(sys.stdin)
print(data.get("x"))
')"
EOF
if ! out="$(node "$LINT" "$TMP/good_py.sh" 2>&1)"; then
  fail "linter false-positived on a syntactically valid embedded python body:
$out"
fi
pass "(2) syntactically valid embedded python body → exit zero"

# (3) A fixture with a corrupted embedded awk body → nonzero, names the file.
cat > "$TMP/bad_awk.sh" <<'EOF'
#!/usr/bin/env bash
out="$(printf '%s\n' "$x" | awk 'BEGIN{ if ( }')"
EOF
if out="$(node "$LINT" "$TMP/bad_awk.sh" 2>&1)"; then
  fail "linter did NOT flag a corrupted embedded awk body:
$out"
fi
grep -qE 'bad_awk\.sh:2:' < <(echo "$out") \
  || fail "linter flagged but did not name the offending file:line:
$out"
pass "(3) corrupted embedded awk body → nonzero, names the file"

# (3b) A fixture with a syntactically valid embedded awk body → exit zero.
cat > "$TMP/good_awk.sh" <<'EOF'
#!/usr/bin/env bash
out="$(printf '%s\n' "$x" | awk '/^MemAvailable:/{print $2}')"
EOF
if ! out="$(node "$LINT" "$TMP/good_awk.sh" 2>&1)"; then
  fail "linter false-positived on a syntactically valid embedded awk body:
$out"
fi
pass "(3b) syntactically valid embedded awk body → exit zero"

# (4) A body the extractor cannot isolate (double-quoted with shell interpolation) is
#     reported UNCHECKED with a count, and the run does NOT read as clean silence — it must
#     still print the unchecked count, distinguishing "verified clean" from "not verified".
cat > "$TMP/unchecked.sh" <<'EOF'
#!/usr/bin/env bash
VAR="hello"
result="$(python3 -c "print('$VAR')")"
EOF
out="$(node "$LINT" "$TMP/unchecked.sh" 2>&1)"
rc=$?
[[ $rc -eq 0 ]] || fail "linter should exit 0 on an unchecked-only fixture (nothing REJECTED), got rc=$rc:
$out"
grep -qi 'unchecked' < <(echo "$out") \
  || fail "linter did not report the un-isolable (interpolated) body as UNCHECKED:
$out"
pass "(4) un-isolable (interpolated) embedded body → UNCHECKED, reported not silently skipped"

# (4b) A glued flag-value quote (e.g. \`awk -F'\\t' 'prog'\`) must NOT be misread as the
#      awk program itself — the REAL program quote that follows must still be recognized
#      and checked. Regression fixture for the false-positive/false-negative pair this class
#      produced during development (\`-F'\\t'\` mistaken for the program; the real program
#      quote losing its \`awk\` command context afterward).
cat > "$TMP/glued_flag.sh" <<'EOF'
#!/usr/bin/env bash
out="$(printf '%s\n' "$x" | awk -F'\t' -v n="$y" '$1==n{print $2; exit}')"
EOF
if ! out="$(node "$LINT" "$TMP/glued_flag.sh" 2>&1)"; then
  fail "linter false-positived on a glued -F flag value ahead of a valid awk program:
$out"
fi
pass "(4b) glued -F flag value does not desync recognition of the real awk program"

# (5) The real tree is CLEAN — no REJECTED (syntactically invalid) embedded bodies. The
#     id:0cf5 apostrophe instance in discover-repo.sh was already repaired; any UNCHECKED
#     count is expected (concatenation/interpolation honestly reported) and does not fail.
if ! out="$(node "$LINT" "$ROOT" 2>&1)"; then
  fail "the live tree has a REJECTED embedded-literal violation (run the linter to see it):
$out"
fi
pass "(5) live relay/scripts tree lints clean (no REJECTED violations)"

# (6) Directory scan discovers *.sh scripts under relay/scripts and reports nothing for a
#     script with no python3/awk invocation at all.
mkdir -p "$TMP/repo/relay/scripts"
cp "$TMP/good_py.sh" "$TMP/repo/relay/scripts/x.sh"
cat > "$TMP/repo/relay/scripts/plain.sh" <<'EOF'
#!/usr/bin/env bash
echo "no embedded literals here"
EOF
if ! out="$(node "$LINT" "$TMP/repo" 2>&1)"; then
  fail "directory scan reported a violation on an all-clean repo:
$out"
fi
pass "(6) directory scan finds *.sh under relay/scripts and stays clean when nothing is embedded"

# (7) THE MOTIVATING INCIDENT'S OWN SHAPE — `sh's` inside the embedded comment, with a
#     LATER apostrophe re-balancing the quotes so the file stays `bash -n` CLEAN and the
#     corruption surfaces only at runtime as an IndentationError. The closing quote here is
#     glued to a bareword (`s`), which the extractor's generic concatenation rule would file
#     as UNCHECKED — i.e. the lint would have reported "clean" on the exact bug it exists to
#     catch. That shape is escalated: the isolated prefix is syntax-checked and a FAILING
#     prefix is REJECTED. Regression fixture for that gap (found reviewing the recovered
#     id:ef9e work, 2026-08-10).
cat > "$TMP/truncated_word.sh" <<'EOF'
#!/usr/bin/env bash
result="$(python3 -c '
import sys
if True:
    # lib-state-claim.sh's quoting habits aren't handled here
    x = 1
')"
echo "$result"
EOF
bash -n "$TMP/truncated_word.sh" \
  || fail "fixture invalid: it must be bash -n CLEAN (that is the whole point — bash sees nothing wrong)"
if out="$(node "$LINT" "$TMP/truncated_word.sh" 2>&1)"; then
  fail "linter reported CLEAN on the motivating incident's own shape (apostrophe truncation glued to a bareword):
$out"
fi
grep -qE 'truncated_word\.sh:2:' < <(echo "$out") \
  || fail "linter flagged but did not name the offending file:line:
$out"
grep -qi 'truncated' < <(echo "$out") \
  || fail "linter flagged but did not name apostrophe truncation as the likely cause:
$out"
pass "(7) bash -n-clean apostrophe truncation glued to a bareword → REJECTED, not hidden as UNCHECKED"

# (7b) The escalation must NOT swallow deliberate concatenation: a body glued to a
#      double-quoted expansion (`'…'"$VAR"'…'`) is still UNCHECKED, never a false REJECT,
#      even though its isolated prefix is not valid Python on its own.
cat > "$TMP/concat_ok.sh" <<'EOF'
#!/usr/bin/env bash
VAR=x
result="$(python3 -c 'print("'"$VAR"'")')"
EOF
if ! out="$(node "$LINT" "$TMP/concat_ok.sh" 2>&1)"; then
  fail "escalation false-positived on deliberate quote-concatenation (prefix is not standalone-valid, but this is not truncation):
$out"
fi
grep -qi 'unchecked' < <(echo "$out") \
  || fail "deliberate concatenation should still be reported UNCHECKED:
$out"
pass "(7b) deliberate quote-concatenation stays UNCHECKED (escalation does not false-positive)"

echo "ALL PASS"
