#!/usr/bin/env bash
# NO `# roadmap:` header ON PURPOSE — this is a defect-class LINT test (filed under id:05a2 /
# id:3a50, both TODO-only), not the spec of an open ROADMAP item, so its failures always count.
#
# Guards tests/lint-source-grep-assertions.py, the advisory scanner for
# source-grep-as-behavioural-assertion (`grep -q '<literal>' "$SCRIPT"` standing in for a
# behavioural claim, the shape that let id:b99f and id:315c stay green through their defects).
#
# Every assertion below RUNS the lint over purpose-built fixture test files — there is no
# assertion here about the lint's own source text (that would be the very defect being linted).
#
# fails-against: the lint and this test shipped in the SAME commit, so the ancestor tree has
#   no lint to overlay and an ancestor case would only die at the file-exists probe -- red for
#   the wrong reason. The negative case is therefore a MUTATION that neutralises exactly the
#   SHAPE-ONLY/MIXED classification the file exists to pin. Relative path only.
# fails-against-mutation: sed -i 's/kind = "MIXED" if var in executed else "SHAPE-ONLY"/kind = "MIXED"/' tests/lint-source-grep-assertions.py
# fails-against-assertion: a grep over never-executed shipped source was NOT flagged SHAPE-ONLY

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/tests/lint-source-grep-assertions.py"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$LINT" ]] || fail "lint-source-grep-assertions.py not found"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
fix="$tmpdir/tests"
mkdir -p "$fix"
printf '#!/usr/bin/env bash\necho hi\n' > "$tmpdir/impl.sh"
chmod +x "$tmpdir/impl.sh"

# (a) SHAPE-ONLY: greps the shipped source and never runs it.
cat > "$fix/test_shape.sh" <<'EOF'
#!/usr/bin/env bash
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/thing.sh"
grep -q 'live-runs' "$SCRIPT" || exit 1
EOF

# (b) BEHAVIOURAL: executes the shipped source and asserts on its OUTPUT only.
cat > "$fix/test_behaviour.sh" <<'EOF'
#!/usr/bin/env bash
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/thing.sh"
out="$("$SCRIPT" --list 2>&1)"
grep -q 'STRANDED' <<<"$out" || exit 1
EOF

# (c) MIXED: executes the source AND carries a supplementary source grep.
cat > "$fix/test_mixed.sh" <<'EOF'
#!/usr/bin/env bash
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR/relay/scripts/thing.sh"
out="$("$SCRIPT" 2>&1)"
grep -q 'ok' <<<"$out" || exit 1
grep -q 'set -euo pipefail' "$SCRIPT" || exit 1
EOF

# (d) DOC: a content contract over a markdown file is legitimate, not a behavioural claim.
cat > "$fix/test_doc.sh" <<'EOF'
#!/usr/bin/env bash
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$SRC_DIR/relay/SKILL.md"
grep -q 'validate-flags.sh' "$DOC" || exit 1
EOF

# (e) NOT the pattern: greps a FIXTURE the test itself built under $tmpdir.
cat > "$fix/test_fixture.sh" <<'EOF'
#!/usr/bin/env bash
tmpdir="$(mktemp -d)"
echo hello > "$tmpdir/f"
FIXTURE="$tmpdir/f"
grep -q hello "$FIXTURE" || exit 1
EOF

# `node --check "$JS"` / `bash -n "$SCRIPT"` are syntax gates and must NOT count as execution.
cat > "$fix/test_syntaxgate.sh" <<'EOF'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
[[ -f "$JS" ]] || exit 1
node --check "$JS" || exit 1
grep -q 'attemptSeq' "$JS" || exit 1
EOF

run() { python3 "$LINT" "$@"; }

out="$(run "$fix/test_shape.sh")"
grep -q 'SHAPE-ONLY .*:4' <<<"$out" \
  || { sed 's/^/    /' <<<"$out"; fail "a grep over never-executed shipped source was NOT flagged SHAPE-ONLY"; }
grep -qE 'TOTAL: 1 ' <<<"$out" || { sed 's/^/    /' <<<"$out"; fail "expected exactly 1 hit for the shape fixture"; }
pass "(a) a source grep in a test that never runs the source is flagged SHAPE-ONLY"

out="$(run "$fix/test_behaviour.sh")"
grep -qE 'TOTAL: 0 ' <<<"$out" \
  || { sed 's/^/    /' <<<"$out"; fail "a purely behavioural test (asserts on captured output) was flagged — false positive"; }
pass "(b) asserting on a script's OUTPUT is not flagged"

out="$(run "$fix/test_mixed.sh")"
grep -q 'MIXED' <<<"$out" \
  || { sed 's/^/    /' <<<"$out"; fail "a source grep beside a real execution was not classified MIXED"; }
grep -qE '^  SHAPE-ONLY ' <<<"$out" \
  && { sed 's/^/    /' <<<"$out"; fail "a file that DOES execute the source must not be SHAPE-ONLY"; }
pass "(c) a supplementary source grep beside real execution is MIXED, not SHAPE-ONLY"

out="$(run "$fix/test_doc.sh")"
grep -qE 'TOTAL: 0 .*\+1 over docs' <<<"$out" \
  || { sed 's/^/    /' <<<"$out"; fail "a grep over a .md contract must be counted separately as DOC, not as a code hit"; }
pass "(d) a content contract over a doc is separated out, not counted"

out="$(run "$fix/test_fixture.sh")"
grep -qE 'TOTAL: 0 ' <<<"$out" \
  || { sed 's/^/    /' <<<"$out"; fail "a grep over a self-built \$tmpdir fixture was flagged — false positive"; }
pass "(e) a grep over a test's own fixture is not flagged"

out="$(run "$fix/test_syntaxgate.sh")"
grep -q 'SHAPE-ONLY' <<<"$out" \
  || { sed 's/^/    /' <<<"$out"; fail "'node --check' / '[[ -f ]]' were mistaken for EXECUTION — this is the id:3a50 blind spot itself"; }
pass "(f) node --check / [[ -f ]] do not count as executing the source"

# Advisory by default, non-zero only under --strict.
run "$fix/test_shape.sh" >/dev/null || fail "the lint must be ADVISORY (exit 0) by default"
if python3 "$LINT" --strict "$fix/test_shape.sh" >/dev/null; then
  fail "--strict must exit non-zero when hits exist"
fi
python3 "$LINT" --strict --max 5 "$fix/test_shape.sh" >/dev/null \
  || fail "--strict --max N must tolerate a baseline of N hits"
pass "(g) advisory by default; --strict / --strict --max N gate as documented"

echo "ALL PASS: source-grep-as-behavioural-assertion lint"
