#!/usr/bin/env bash
# NO `# roadmap:` header ON PURPOSE — id:b54b is a TODO item (a defect found during a
# pool pre-flight), not a ROADMAP item, so per tests/run-tests.sh's own convention this
# file's failures are NEVER expected-red.
#
# id:b54b part (b) — a test fixture leaked a real `relay/ok` branch (1 commit, "child
# work ok") into THIS repo on 2026-08-22. tests/run-tests.sh now snapshots the cwd
# repo's relay/* branches + worktree list before and after the whole run and fails
# LOUDLY on any drift, independent of every individual test's own exit code — a
# structural backstop for the whole class ("a test fixture reached real repo state"),
# not just the two originally-suspected test files.
#
# This test drives the REAL tests/run-tests.sh (never a reimplementation) against a
# throwaway `mktemp -d` git repo standing in for "the real repo run-tests.sh lives in",
# with tiny fixture test files that either leak a relay/* branch into that scratch repo
# or don't. Hermetic: everything happens inside $TMP; the real dotclaude-skills repo is
# read-only (only $RUN_TESTS is invoked from it) and is never written to.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_TESTS="$SRC_DIR/tests/run-tests.sh"
[[ -x "$RUN_TESTS" ]] || { echo "FAIL: run-tests.sh not found/executable at $RUN_TESTS"; exit 1; }

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# ── scratch repo standing in for "the real repo run-tests.sh lives in" ──
REPO="$TMP/scratch-repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.email t@e.st
git -C "$REPO" config user.name t
echo base >"$REPO/f"
git -C "$REPO" add -A
git -C "$REPO" commit -qm base

mkdir -p "$REPO/tests"

LEAKY="$REPO/tests/test_leaky_fixture.sh"
cat >"$LEAKY" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# A well-behaved-LOOKING test: it passes on its own terms while leaving a real branch
# behind in whatever repo it happens to run in — exactly the id:b54b defect shape.
git branch relay/leaked-by-fixture
echo "ALL PASS: leaky fixture (intentional, for the backstop's own test)"
EOF
chmod +x "$LEAKY"

CLEAN="$REPO/tests/test_clean_fixture.sh"
cat >"$CLEAN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "ALL PASS: clean fixture (intentional, for the backstop's own test)"
EOF
chmod +x "$CLEAN"

# =====================================================================================
# (A) a leaking test file is caught: run-tests.sh itself exits non-zero and names the
#     breach, even though the leaky test's OWN exit code was 0 ("PASS").
# =====================================================================================
rc=0
out="$(cd "$REPO" && bash "$RUN_TESTS" "$LEAKY" 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || fail "(A) run-tests.sh exited 0 despite a fixture leaking a real relay/* branch: $out"
grep -q 'HERMETICITY BREACH' <<<"$out" || fail "(A) no HERMETICITY BREACH line in output: $out"
grep -q 'refs/heads/relay/leaked-by-fixture' <<<"$out" || fail "(A) breach report did not name the leaked ref: $out"
grep -q '^PASS   test_leaky_fixture.sh$' <<<"$out" || fail "(A) the leaky test's own PASS line should still be reported (the backstop is additive, not a replacement): $out"
pass "(A) a leaked relay/* branch fails the WHOLE run, even though the leaking test itself reported PASS"

# clean up the branch the leaky fixture left behind before the next sub-case, so (B)
# starts from a known-clean scratch repo (mirrors run-tests.sh's own before/after diff).
git -C "$REPO" branch -D relay/leaked-by-fixture >/dev/null

# =====================================================================================
# (B) a clean run is unaffected: no false positive when nothing leaks.
# =====================================================================================
rc=0
out="$(cd "$REPO" && bash "$RUN_TESTS" "$CLEAN" 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || fail "(B) a clean run exited $rc: $out"
grep -q 'HERMETICITY BREACH' <<<"$out" && fail "(B) false positive: HERMETICITY BREACH reported though nothing leaked: $out" || true
pass "(B) a clean run (no relay/* leak) is unaffected — no false positive"

# =====================================================================================
# (C) a leaked WORKTREE (not just a branch) is caught too.
# =====================================================================================
WTLEAK="$REPO/tests/test_worktree_leaky_fixture.sh"
cat >"$WTLEAK" <<EOF
#!/usr/bin/env bash
set -euo pipefail
git branch relay/wt-leak
git worktree add -q "$TMP/leaked-worktree" relay/wt-leak
echo "ALL PASS: worktree-leaky fixture (intentional, for the backstop's own test)"
EOF
chmod +x "$WTLEAK"
rc=0
out="$(cd "$REPO" && bash "$RUN_TESTS" "$WTLEAK" 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || fail "(C) run-tests.sh exited 0 despite a fixture leaking a real worktree: $out"
grep -q 'HERMETICITY BREACH' <<<"$out" || fail "(C) no HERMETICITY BREACH line for a leaked worktree: $out"
pass "(C) a leaked worktree is caught too (not just a bare branch)"

echo "ALL PASS: id:b54b run-tests.sh hermeticity backstop"
