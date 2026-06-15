#!/usr/bin/env bash
# roadmap:fa05 — gaming-scan.sh mechanical gaming detector.
# Tests: (a) deleted test file → flag; (b) added @pytest.mark.skip → flag;
# (c) removed assert line → flag; (d) clean diff → SILENT (negative control,
# modelled on id:3b02 resurrection case: only input line changed, assertions intact).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SH="$SRC_DIR/relay/scripts/gaming-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "gaming-scan.sh not found/executable at $SH"

# ── Helper: create a minimal hermetic git repo ──
make_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@test"
  git -C "$dir" config user.name "Test"
  echo "$dir"
}

make_commit() {
  local repo="$1"; shift
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "$*"
}

# ──────────────────────────────────────────────────────────────────────────────
# (a) Deleted test file → DELETED_TEST flag
# ──────────────────────────────────────────────────────────────────────────────
repo="$(make_repo)"
mkdir -p "$repo/tests"
cat >"$repo/tests/test_foo.sh" <<'EOF'
#!/usr/bin/env bash
assert_ok() { [[ "$1" == "ok" ]] || exit 1; }
assert_ok "ok"
EOF
make_commit "$repo" "initial: add test file"
BASE_TAG="base-tag-a"
git -C "$repo" tag "$BASE_TAG"

# Now delete the test file
rm "$repo/tests/test_foo.sh"
make_commit "$repo" "GAMED: delete test"

out="$("$SH" "$repo" "$BASE_TAG" 2>&1)"
if printf '%s' "$out" | grep -q "DELETED_TEST:tests/test_foo.sh"; then
  pass "(a) DELETED_TEST flag emitted for deleted test file"
else
  fail "(a) expected DELETED_TEST:tests/test_foo.sh but got: $out"
fi
rm -rf "$repo"

# ──────────────────────────────────────────────────────────────────────────────
# (b) Added @pytest.mark.skip → ADDED_SKIP flag
# ──────────────────────────────────────────────────────────────────────────────
repo="$(make_repo)"
mkdir -p "$repo/tests"
cat >"$repo/tests/test_bar.py" <<'EOF'
def test_something():
    assert 1 + 1 == 2
EOF
make_commit "$repo" "initial: add python test"
BASE_TAG="base-tag-b"
git -C "$repo" tag "$BASE_TAG"

# Add @pytest.mark.skip
cat >"$repo/tests/test_bar.py" <<'EOF'
import pytest

@pytest.mark.skip(reason="gamed")
def test_something():
    assert 1 + 1 == 2
EOF
make_commit "$repo" "GAMED: skip test"

out="$("$SH" "$repo" "$BASE_TAG" 2>&1)"
if printf '%s' "$out" | grep -q "ADDED_SKIP:tests/test_bar.py"; then
  pass "(b) ADDED_SKIP flag emitted for @pytest.mark.skip"
else
  fail "(b) expected ADDED_SKIP:tests/test_bar.py but got: $out"
fi
rm -rf "$repo"

# ──────────────────────────────────────────────────────────────────────────────
# (c) Removed assert line without equivalent addition → REMOVED_ASSERT flag
# ──────────────────────────────────────────────────────────────────────────────
repo="$(make_repo)"
mkdir -p "$repo/tests"
cat >"$repo/tests/test_baz.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$(echo hello)" == "hello" ]] || exit 1
assert_result() { [[ "$1" == "$2" ]] || exit 1; }
assert_result "$(cat /dev/null)" ""
EOF
make_commit "$repo" "initial: test with asserts"
BASE_TAG="base-tag-c"
git -C "$repo" tag "$BASE_TAG"

# Remove one of the assert-style lines (net removal)
cat >"$repo/tests/test_baz.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$(echo hello)" == "hello" ]] || exit 1
EOF
make_commit "$repo" "GAMED: remove assertion"

out="$("$SH" "$repo" "$BASE_TAG" 2>&1)"
if printf '%s' "$out" | grep -q "REMOVED_ASSERT:tests/test_baz.sh"; then
  pass "(c) REMOVED_ASSERT flag emitted for removed assert line"
else
  fail "(c) expected REMOVED_ASSERT:tests/test_baz.sh but got: $out"
fi
rm -rf "$repo"

# ──────────────────────────────────────────────────────────────────────────────
# (d) NEGATIVE CONTROL — clean diff: only input line changed, assertions intact
# Modelled on the real id:3b02 resurrection case from RELAY_LOG: the executor
# changed only the failing INPUT to match the corrected implementation; all
# assertion lines (the 'assert' checks) stayed intact. Must NOT flag.
# ──────────────────────────────────────────────────────────────────────────────
repo="$(make_repo)"
mkdir -p "$repo/tests"
cat >"$repo/tests/test_broker.sh" <<'EOF'
#!/usr/bin/env bash
# Test broker say command with a multi-line stdin input
output="$(printf 'line1\nold-input\nline3' | broker-say mock)"
[[ "$output" == "3 lines sent" ]] || { echo "FAIL: wrong output"; exit 1; }
assert_count() { [[ "$1" -eq "$2" ]] || { echo "FAIL: count"; exit 1; }; }
assert_count 3 3
EOF
make_commit "$repo" "initial: broker test"
BASE_TAG="base-tag-d"
git -C "$repo" tag "$BASE_TAG"

# Legitimate fix: only the input line changed (old-input → new-input), assertions intact
cat >"$repo/tests/test_broker.sh" <<'EOF'
#!/usr/bin/env bash
# Test broker say command with a multi-line stdin input
output="$(printf 'line1\nnew-input\nline3' | broker-say mock)"
[[ "$output" == "3 lines sent" ]] || { echo "FAIL: wrong output"; exit 1; }
assert_count() { [[ "$1" -eq "$2" ]] || { echo "FAIL: count"; exit 1; }; }
assert_count 3 3
EOF
make_commit "$repo" "fix: update test input to match corrected implementation"

out="$("$SH" "$repo" "$BASE_TAG" 2>&1)"
if [ -z "$out" ]; then
  pass "(d) NEGATIVE CONTROL: clean diff with only input change emits no flags"
else
  fail "(d) negative control: unexpected flag(s) emitted for clean diff: $out"
fi
rm -rf "$repo"

# ──────────────────────────────────────────────────────────────────────────────
# (e) Usage error → non-zero exit
# ──────────────────────────────────────────────────────────────────────────────
if "$SH" 2>/dev/null; then
  fail "(e) no-args should exit non-zero"
fi
pass "(e) no-args exits non-zero (usage error)"

# ──────────────────────────────────────────────────────────────────────────────
# id:dfaf — review.md §2 delegate rewrite: static-grep checks
# review.md must reference gaming-scan.sh and must NOT contain the old inlined
# one-liners (--diff-filter=D as a shell command, inlined xfail/skip grep).
# ──────────────────────────────────────────────────────────────────────────────
REVIEW_MD="$SRC_DIR/relay/references/review.md"
[[ -f "$REVIEW_MD" ]] || fail "dfaf: relay/references/review.md not found"

grep -q "gaming-scan.sh" "$REVIEW_MD" \
  || fail "dfaf: review.md §2 does not reference gaming-scan.sh (single source of truth)"
pass "dfaf: review.md §2 references gaming-scan.sh"

# The old inlined --diff-filter=D bash command must be gone from §2.
# The review.md §1 uses git log (fine), but §2 must no longer inline the
# git diff --diff-filter=D shell snippet — that command now lives only in gaming-scan.sh.
if grep -n -- "--diff-filter=D" "$REVIEW_MD" | grep -v "gaming-scan.sh"; then
  fail "dfaf: review.md still contains inlined --diff-filter=D one-liner (move it to gaming-scan.sh)"
fi
pass "dfaf: review.md §2 does not inline --diff-filter=D (delegated to gaming-scan.sh)"

echo "ALL PASS"
