#!/usr/bin/env bash
# roadmap:b890
#
# RED SPEC for id:b890: `verify-negative-cases.py` extracts only the FIRST LINE of a
# `# fails-against-mutation:` declaration (parse_directives iterates head.splitlines() and
# takes CASE_RE.match(line).group(2)). A declaration authored as a heredoc across several
# comment lines therefore executes the fragment `python3 - <<'EOF'` alone: bash warns
# `here-document ... delimited by end-of-file`, python reads an empty stdin, and the whole
# thing EXITS 0. The runner only treats a nonzero return as `mutation command failed`, so
# the no-op passes, the test runs against the UNMUTATED scratch tree, and the file is
# reported VACUOUS -- a correct verdict with a misleading cause, which sends the reader to
# rewrite a fixture that was never broken.
#
# Live instance, 2026-09-05: tests/test_owner_accepted_keep_date_9628.sh shipped that way
# and was reported VACUOUS while its assertion (A) demonstrably DOES fire against the
# pre-fix pattern. The declaration was rewritten to a one-liner in the same review; this
# spec pins the GENERATOR so the next one is refused instead of mis-diagnosed.
#
# WHAT THE FIX MUST NOT DO: exit code is not the discriminator. Measured on this tree,
# `bash -n -c "python3 - <<'EOF'"` also exits 0 -- it writes the here-document warning to
# STDERR. Any stderr output from `bash -n -c "$arg"` is the signal.
#
# The refusal must be a CONFIG ERROR (exit 2), the same class as a non-unique
# `-assertion:` substring, and must NOT report the file as VACUOUS: reporting VACUOUS is
# precisely the mis-diagnosis this item exists to remove.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

VERIFIER="tests/verify-negative-cases.py"
fails=0
FAIL() { echo "FAIL: $*"; fails=$((fails + 1)); }
pass() { echo "ok: $*"; }

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/tests" "$scratch/tools"

# The subject under mutation: a trivial file with a unique, greppable marker.
cat >"$scratch/tools/subject.py" <<'PY'
MARKER = "KEEP-ME"
PY

# (i) a test whose mutation declaration is a MULTI-LINE heredoc -- the b890 shape.
cat >"$scratch/tests/test_b890_heredoc_fixture.sh" <<'SH'
#!/usr/bin/env bash
# Fixture for id:b890. No roadmap header on purpose.
#
# fails-against-mutation: python3 - <<'EOF'
# import pathlib
# p = pathlib.Path("tools/subject.py")
# p.write_text(p.read_text().replace("KEEP-ME", "GONE"))
# EOF
# fails-against-assertion: (A) marker survived
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
if grep -q 'KEEP-ME' tools/subject.py; then
  echo "ok: marker present"
else
  echo "FAIL: (A) marker survived"
  exit 1
fi
SH

# (ii) NEGATIVE CONTROL -- a well-formed SINGLE-LINE declaration in the same run. It must
# still be executed and verified normally, or the fix has simply broken the tool.
cat >"$scratch/tests/test_b890_oneline_fixture.sh" <<'SH'
#!/usr/bin/env bash
# Negative control for id:b890. No roadmap header on purpose.
#
# fails-against-mutation: python3 -c 'import pathlib; p = pathlib.Path("tools/subject.py"); s = p.read_text(); n = s.replace("KEEP-ME", "GONE"); assert n != s; p.write_text(n)'
# fails-against-assertion: (A) marker survived
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
if grep -q 'KEEP-ME' tools/subject.py; then
  echo "ok: marker present"
else
  echo "FAIL: (A) marker survived"
  exit 1
fi
SH

chmod +x "$scratch"/tests/*.sh
cp "$VERIFIER" "$scratch/tests/verify-negative-cases.py"
# The verifier imports its header grammar from tests/lib/negative_case_syntax.py via a
# sys.path insert relative to its OWN location, so the sibling must travel with it.
mkdir -p "$scratch/tests/lib"
cp tests/lib/negative_case_syntax.py "$scratch/tests/lib/negative_case_syntax.py"

git -C "$scratch" init -q -b main
git -C "$scratch" -c user.email=t@e -c user.name=t add -A
git -C "$scratch" -c user.email=t@e -c user.name=t commit -qm fixture

# FIXTURE SANITY: the control must genuinely have killing power, or case (2) below would
# pass for the wrong reason on a tool that runs nothing at all.
ctl=$(cd "$scratch" && python3 tests/verify-negative-cases.py --root "$scratch" \
        tests/test_b890_oneline_fixture.sh 2>&1)
if ! grep -q 'red-there' <<<"$ctl"; then
  echo "FIXTURE-BROKEN: the single-line control did not reach red-there; assertions below"
  echo "would be vacuous. Verifier output was:"
  echo "$ctl"
  exit 1
fi

out=$(cd "$scratch" && python3 tests/verify-negative-cases.py --root "$scratch" \
        tests/test_b890_heredoc_fixture.sh 2>&1)
rc=$?

# (1) the truncated declaration is REFUSED as a config error, not executed.
if [[ $rc -eq 2 ]]; then
  pass "(1) multi-line mutation declaration is a CONFIG ERROR (exit 2)"
else
  FAIL "(1) multi-line mutation declaration was not refused -- exit $rc, expected 2"
fi

# (2) the refusal NAMES the cause. The whole point of the item is that the old message
# blamed the test; the new one must say the declaration is truncated / must be one line.
if grep -qiE 'one line|single line|multi-line|truncat' <<<"$out"; then
  pass "(2) the message names the one-line/truncation cause"
else
  FAIL "(2) the message does not name the one-line/truncation cause -- got: $out"
fi

# (3) it must NOT be reported VACUOUS. That verdict is the mis-diagnosis being removed.
if grep -q 'VACUOUS' <<<"$out"; then
  FAIL "(3) still reported VACUOUS -- the mis-diagnosis this item removes"
else
  pass "(3) not reported VACUOUS"
fi

if (( fails )); then
  echo "$fails assertion(s) failed"
  exit 1
fi
echo "PASS: truncated mutation declarations are refused, not mis-diagnosed (id:b890)"
