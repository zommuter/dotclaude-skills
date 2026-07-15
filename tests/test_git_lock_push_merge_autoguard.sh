#!/usr/bin/env bash
# roadmap:e4f5 — legacy mode auto-detects merge topology in local-ahead and falls
# back to an --ff-only reconcile on its own, instead of letting `git pull --rebase`
# silently flatten --no-ff merge commits (loderite incident, 2026-07-15: a relay
# reviewer's deliberate --no-ff integration merges were flattened because legacy
# mode was invoked instead of --ff-only/--merge-branch).
#
# Mechanism under test: a rebase against an UN-MOVED remote is a no-op for a
# purely linear local-ahead, but REWRITES (drops merge commits, replays their
# contents linearly) whenever local-ahead contains merge commits. So the guard
# fetches the remote tip, counts merges in FETCH_HEAD..HEAD, and if any exist,
# takes the same code path as --ff-only.
#
# Hermetic: local bare remote, mktemp, no network (idiom: test_git_lock_push_ff_only.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK_PUSH="$REPO_ROOT/git-diary-workflow/git-lock-push.sh"

pass=0; fail=0

ok() { echo "  PASS: $1"; pass=$((pass+1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Fake ssh-add so the push guard never depends on a real SSH agent
# (idiom: test_git_lock_push_slash_branch.sh) — the remote here is a local
# file:// bare repo that needs no SSH.
fakebin="$tmpdir/bin"
mkdir -p "$fakebin"
printf '#!/bin/sh\nexec true\n' > "$fakebin/ssh-add"
chmod +x "$fakebin/ssh-add"
export PATH="$fakebin:$PATH"

new_repo() {
  local name="$1"
  local bare="$tmpdir/$name-remote.git"
  local work="$tmpdir/$name-work"
  git init --bare -q "$bare"
  git init -q "$work"
  git -C "$work" config user.email "test@test"
  git -C "$work" config user.name "Test"
  git -C "$work" remote add origin "$bare"
  echo "init" > "$work/README"
  git -C "$work" add README
  git -C "$work" commit -q -m "init"
  git -C "$work" push -q --set-upstream origin main >/dev/null 2>&1
  echo "$work"
}

# ── Scenario (a): un-moved remote + local --no-ff merge ahead ─────────────────
echo "Test (a): un-moved remote + local merge-ahead — topology survives, guard fires"
work_a="$(new_repo a)"

git -C "$work_a" checkout -q -b feature-a
echo "feature" > "$work_a/feature.txt"
git -C "$work_a" add feature.txt
git -C "$work_a" commit -q -m "feature-a work"
git -C "$work_a" checkout -q main
git -C "$work_a" merge --no-ff -q -m "merge feature-a" feature-a
merge_sha_a="$(git -C "$work_a" rev-parse HEAD)"

out_a="$("$LOCK_PUSH" "$work_a" 2>&1)"
rc_a=$?

if [[ "$rc_a" -eq 0 ]]; then
  ok "(a) exits 0"
else
  fail_msg "(a) exited $rc_a, expected 0"
fi

if echo "$out_a" | grep -qi "local-ahead contains.*merge commit"; then
  ok "(a) NOTE line printed on stderr"
else
  fail_msg "(a) NOTE line missing (output: $out_a)"
fi

remote_a_merges="$(git --git-dir="$tmpdir/a-remote.git" rev-list --merges --count main)"
if [[ "$remote_a_merges" -gt 0 ]]; then
  ok "(a) origin's branch still contains the merge commit (topology survived)"
else
  fail_msg "(a) origin's branch has NO merge commits — flattened!"
fi

remote_a_sha="$(git --git-dir="$tmpdir/a-remote.git" rev-parse main)"
if [[ "$remote_a_sha" == "$merge_sha_a" ]]; then
  ok "(a) origin's branch SHA matches the local merge commit exactly (no rewrite)"
else
  fail_msg "(a) origin's branch SHA differs from local merge (before=$merge_sha_a after=$remote_a_sha)"
fi

# ── Scenario (b): diverged remote + local merge ahead ─────────────────────────
echo "Test (b): diverged remote + local merge-ahead — non-fatal warn, not pushed"
work_b="$(new_repo b)"
bare_b="$tmpdir/b-remote.git"

# Remote-side commit from a second clone (creates true divergence)
other_b="$tmpdir/b-other"
git clone -q "$bare_b" "$other_b"
git -C "$other_b" config user.email "other@test"
git -C "$other_b" config user.name "Other"
echo "remote-side" > "$other_b/remote-side.txt"
git -C "$other_b" add remote-side.txt
git -C "$other_b" commit -q -m "remote-side commit"
git -C "$other_b" push -q origin main >/dev/null 2>&1

# Local-side --no-ff merge, diverging from the (now-moved) remote
git -C "$work_b" checkout -q -b feature-b
echo "feature" > "$work_b/feature.txt"
git -C "$work_b" add feature.txt
git -C "$work_b" commit -q -m "feature-b work"
git -C "$work_b" checkout -q main
git -C "$work_b" merge --no-ff -q -m "merge feature-b" feature-b
local_sha_b="$(git -C "$work_b" rev-parse HEAD)"
local_b_merges_before="$(git -C "$work_b" rev-list --merges --count HEAD)"

out_b="$("$LOCK_PUSH" "$work_b" 2>&1)"
rc_b=$?

if [[ "$rc_b" -eq 0 ]]; then
  ok "(b) exits 0 (non-fatal)"
else
  fail_msg "(b) exited $rc_b, expected 0"
fi

if echo "$out_b" | grep -qi "warning\|diverge"; then
  ok "(b) warning emitted"
else
  fail_msg "(b) no warning printed (output: $out_b)"
fi

remote_b_sha="$(git -C "$bare_b" rev-parse main)"
if [[ "$remote_b_sha" != "$local_sha_b" ]]; then
  ok "(b) local merge NOT pushed (remote unchanged by this run)"
else
  fail_msg "(b) local merge was pushed despite divergence"
fi

post_sha_b="$(git -C "$work_b" rev-parse HEAD)"
local_b_merges_after="$(git -C "$work_b" rev-list --merges --count HEAD)"
if [[ "$post_sha_b" == "$local_sha_b" && "$local_b_merges_after" -eq "$local_b_merges_before" ]]; then
  ok "(b) local history unchanged (merge commit still present locally)"
else
  fail_msg "(b) local history changed (before=$local_sha_b/$local_b_merges_before after=$post_sha_b/$local_b_merges_after)"
fi

# ── Scenario (c) regression: un-moved remote + purely linear local-ahead ──────
echo "Test (c): linear local-ahead — guard does not fire, legacy rebase still works"
work_c="$(new_repo c)"

echo "linear change" > "$work_c/linear.txt"
git -C "$work_c" add linear.txt
git -C "$work_c" commit -q -m "linear local commit"
local_sha_c="$(git -C "$work_c" rev-parse HEAD)"

out_c="$("$LOCK_PUSH" "$work_c" 2>&1)"
rc_c=$?

if [[ "$rc_c" -eq 0 ]]; then
  ok "(c) exits 0"
else
  fail_msg "(c) exited $rc_c, expected 0"
fi

if echo "$out_c" | grep -qi "local-ahead contains.*merge commit"; then
  fail_msg "(c) guard fired on a purely linear local-ahead (should not)"
else
  ok "(c) guard did not fire (no merge commits present)"
fi

remote_c_sha="$(git --git-dir="$tmpdir/c-remote.git" rev-parse main)"
if [[ "$remote_c_sha" == "$local_sha_c" ]]; then
  ok "(c) linear commit reached the remote (legacy rebase path still pushes)"
else
  fail_msg "(c) linear commit did NOT reach the remote (remote=$remote_c_sha local=$local_sha_c)"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
