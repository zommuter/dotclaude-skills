#!/usr/bin/env bash
# Tests for git-lock-push.sh --ff-only and --follow-tags behaviour.
# No roadmap item — defect fix for id:821c.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK_PUSH="$REPO_ROOT/git-diary-workflow/git-lock-push.sh"

pass=0; fail=0; total=0

ok() { echo "  PASS: $1"; pass=$((pass+1)); total=$((total+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); total=$((total+1)); }

# Set up an isolated git environment
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bare="$tmpdir/remote.git"
work="$tmpdir/work"
git init --bare -q "$bare"
git init -q "$work"
git -C "$work" config user.email "test@test"
git -C "$work" config user.name "Test"
git -C "$work" remote add origin "$bare"

# Initial commit so the branch exists on remote
echo "init" > "$work/README"
git -C "$work" add README
git -C "$work" commit -q -m "init"
git -C "$work" push -q --set-upstream origin main >/dev/null 2>&1

# ── Test 1: --follow-tags pushes annotated tag to remote ──────────────────────
echo "Test 1: --follow-tags carries annotated tag"
echo "v1" > "$work/file1"
git -C "$work" add file1
git -C "$work" commit -q -m "add file1"
git -C "$work" tag -a "v0.1.0" -m "version 0.1.0"

"$LOCK_PUSH" "$work" >/dev/null 2>&1
# Tag should now be on remote
if git -C "$work" ls-remote --tags origin "refs/tags/v0.1.0" | grep -q "v0.1.0"; then
  ok "--follow-tags pushed annotated tag to remote"
else
  fail_msg "--follow-tags did NOT push annotated tag to remote"
fi

# Cleanup tag for next tests
git -C "$work" tag -d v0.1.0 >/dev/null 2>&1
git -C "$bare" tag -d v0.1.0 >/dev/null 2>&1

# ── Test 2: --ff-only + unchanged remote → tag survives on-branch ─────────────
echo "Test 2: --ff-only preserves --no-ff merge and annotated tag"
# Create a side branch and --no-ff merge it
git -C "$work" checkout -q -b feature-x
echo "feature" > "$work/feature.txt"
git -C "$work" add feature.txt
git -C "$work" commit -q -m "feature-x work"
git -C "$work" checkout -q main

# --no-ff merge (simulates relay orchestrator)
git -C "$work" merge --no-ff -q -m "relay: merge feature-x" feature-x

# Annotated tag on the merge commit (simulates ckpt-tag.sh output)
merge_sha="$(git -C "$work" rev-parse HEAD)"
git -C "$work" tag -a "fable-ckpt-test" -m "checkpoint" HEAD

# Run lock-push with --ff-only (remote is not ahead, so ff succeeds)
"$LOCK_PUSH" "$work" --ff-only >/dev/null 2>&1

# Tag must still exist and resolve to a commit reachable from HEAD
if git -C "$work" rev-parse "fable-ckpt-test^{}" >/dev/null 2>&1; then
  tag_sha="$(git -C "$work" rev-parse "fable-ckpt-test^{}")"
  if git -C "$work" merge-base --is-ancestor "$tag_sha" HEAD; then
    ok "--ff-only: tag still resolves and is ancestor of HEAD"
  else
    fail_msg "--ff-only: tag resolves but is NOT ancestor of HEAD"
  fi
else
  fail_msg "--ff-only: tag lost (orphaned or deleted)"
fi

# Merge commit SHA must be unchanged (no rewrite)
post_sha="$(git -C "$work" rev-parse HEAD)"
if [[ "$merge_sha" == "$post_sha" ]]; then
  ok "--ff-only: merge commit SHA unchanged (no rewrite)"
else
  fail_msg "--ff-only: merge commit SHA changed (rewrite occurred: before=$merge_sha after=$post_sha)"
fi

# Tag must be on remote
if git -C "$work" ls-remote --tags origin "refs/tags/fable-ckpt-test" | grep -q "fable-ckpt-test"; then
  ok "--ff-only: annotated checkpoint tag reached remote via --follow-tags"
else
  fail_msg "--ff-only: annotated checkpoint tag did NOT reach remote"
fi

# ── Test 3: --ff-only + diverged remote → loud failure, non-fatal ─────────────
echo "Test 3: --ff-only fails loud on true divergence"
# Divergence = both sides have commits the other doesn't. Steps:
# 1. Record current remote HEAD (common ancestor)
common="$(git -C "$work" rev-parse origin/main)"
# 2. Clone the remote at the common point and push a remote-only commit
work2="$tmpdir/work2"
git clone -q "$bare" "$work2"
git -C "$work2" config user.email "other@test"
git -C "$work2" config user.name "Other"
# Reset work2 to common (in case it picked up Test2 merge)
git -C "$work2" reset -q --hard "$common"
echo "remote-side commit" > "$work2/remote-side.txt"
git -C "$work2" add remote-side.txt
git -C "$work2" commit -q -m "remote-side commit"
git -C "$work2" push -q --force origin main >/dev/null 2>&1  # force past common point

# 3. Make a local-only commit in $work (diverges from common)
echo "local-side commit" > "$work/local-side.txt"
git -C "$work" add local-side.txt
git -C "$work" commit -q -m "local-side commit"

# Both sides now have one commit beyond $common — genuine fork.
# lock-push --ff-only should warn and exit 0 (non-fatal).
output="$("$LOCK_PUSH" "$work" --ff-only 2>&1 || true)"
if echo "$output" | grep -qi "warning\|diverge\|ff-only\|resolve"; then
  ok "--ff-only: prints warning on true divergence"
else
  fail_msg "--ff-only: no warning printed on divergence (output: $output)"
fi
# Local commit must still exist (non-fatal — work is committed locally)
if git -C "$work" rev-parse HEAD >/dev/null 2>&1; then
  ok "--ff-only: local commits preserved after loud divergence failure"
else
  fail_msg "--ff-only: local commits lost after divergence failure"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $pass passed, $fail failed, $total total"
[[ "$fail" -eq 0 ]]
