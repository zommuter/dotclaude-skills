#!/usr/bin/env bash
# roadmap:758e — purity-test-as-contract shared helper (RED spec, relay handoff 2026-07-07)
#
# Spec for the SHARED purity-assertion helper that generalizes the
# test_discovery_producer_readonly.sh pattern (id:758e): any component labeled
# read-only / snapshot / pure must ship a test that plants a repo (worktree +
# commits + dirty file), runs the component, and asserts the repo state is
# byte-identical afterwards — no commits, no ref moves, no worktree add/remove,
# HEAD/reflog unchanged, porcelain unchanged.
#
# Contract under test:
#   tests/lib/assert-repo-unchanged.sh  (sourceable bash library, no side effects
#                                        on source, `set -euo pipefail`-compatible)
# defines two functions:
#   repo_state_snapshot <repo-dir>
#       → prints a deterministic state blob for the repo to STDOUT (captures at
#         least: HEAD sha, all refs, HEAD reflog, `git status --porcelain`,
#         `git worktree list --porcelain`, stash list). Read-only itself.
#   assert_repo_unchanged <repo-dir> <saved-snapshot-file>
#       → exit 0 iff the repo's current snapshot is byte-identical to the saved
#         one; on drift exit NONZERO and print a diff/description to stderr
#         (loud, never silent).
#
# Also asserted: the convention is DOCUMENTED in relay/references/executor-contract.md
# (a "purity-test-as-contract" note), so the label-vs-behavior rule is discoverable
# by executors, not tribal knowledge.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/tests/lib/assert-repo-unchanged.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$HELPER" ]] || fail "helper missing (RED): $HELPER"

# Source in a hermetic subshell-friendly way; sourcing must not execute anything.
# shellcheck disable=SC1090
source "$HELPER"
declare -F repo_state_snapshot >/dev/null || fail "function repo_state_snapshot not defined by helper"
declare -F assert_repo_unchanged >/dev/null || fail "function assert_repo_unchanged not defined by helper"
pass "helper exists, sources cleanly, defines both functions"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

mkrepo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@e
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
}

# --- fixture: repo with a commit, a dirty file, and a live worktree ---------------
R="$tmp/repo"; mkrepo "$R"
echo one > "$R/a.txt"
git -C "$R" add -A; git -C "$R" commit -qm init
echo dirty > "$R/dirty.txt"                       # untracked churn, part of the state
git -C "$R" worktree add -q -b wt-branch "$tmp/wt"

snap="$tmp/snap"
repo_state_snapshot "$R" > "$snap"
[[ -s "$snap" ]] || fail "repo_state_snapshot produced an empty blob"

# 1. Determinism / no-op: a pure read must leave the snapshot identical.
git -C "$R" status >/dev/null
git -C "$R" log --oneline >/dev/null
assert_repo_unchanged "$R" "$snap" || fail "no-op reads flagged as mutation (false positive)"
pass "read-only operations leave the snapshot identical"

# 2. Snapshotting itself must be pure (snapshot twice, compare).
repo_state_snapshot "$R" > "$tmp/snap2"
cmp -s "$snap" "$tmp/snap2" || fail "repo_state_snapshot is not deterministic/pure across back-to-back calls"
pass "repo_state_snapshot is deterministic and side-effect-free"

# 3. A commit must be detected (HEAD/reflog/ref drift).
git -C "$R" add dirty.txt; git -C "$R" commit -qm mutate
if assert_repo_unchanged "$R" "$snap" 2>/dev/null; then
  fail "a new commit was NOT detected as drift"
fi
pass "commit detected as drift"

# --- fresh fixture per remaining case (state is cheap) ----------------------------
R2="$tmp/repo2"; mkrepo "$R2"
echo one > "$R2/a.txt"; git -C "$R2" add -A; git -C "$R2" commit -qm init
repo_state_snapshot "$R2" > "$tmp/snapB"

# 4. New untracked file (porcelain drift) must be detected.
echo x > "$R2/new-untracked.txt"
if assert_repo_unchanged "$R2" "$tmp/snapB" 2>/dev/null; then
  fail "new untracked file was NOT detected as drift"
fi
pass "untracked-file churn detected as drift"

R3="$tmp/repo3"; mkrepo "$R3"
echo one > "$R3/a.txt"; git -C "$R3" add -A; git -C "$R3" commit -qm init
repo_state_snapshot "$R3" > "$tmp/snapC"

# 5. Worktree add/remove must be detected.
git -C "$R3" worktree add -q -b wt2 "$tmp/wt2"
if assert_repo_unchanged "$R3" "$tmp/snapC" 2>/dev/null; then
  fail "worktree add was NOT detected as drift"
fi
pass "worktree churn detected as drift"

# 6. Drift failure must be LOUD (something on stderr, per no-silent-swallow id:4347).
errout="$(assert_repo_unchanged "$R3" "$tmp/snapC" 2>&1 >/dev/null || true)"
[[ -n "$errout" ]] || fail "assert_repo_unchanged failed silently — drift must be described on stderr"
pass "drift failure is loud (stderr diagnostic)"

# 7. The convention is documented for executors.
grep -qi 'purity-test' "$ROOT/relay/references/executor-contract.md" \
  || fail "purity-test-as-contract convention not documented in relay/references/executor-contract.md"
pass "convention documented in executor-contract.md"

echo "ALL PASS: purity-test-as-contract helper behaves per spec"
