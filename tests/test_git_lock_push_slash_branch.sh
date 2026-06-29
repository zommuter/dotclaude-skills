#!/usr/bin/env bash
# Tests git-lock-push.sh upstream parsing for slash-containing branch names.
# No roadmap item — defect fix from the 2026-06-12 strong-model audit (id:401c):
# the old `tr '/' ' '` split turned origin/relay/review-x into three words,
# the ls-remote gate then failed and the pull was silently skipped.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK_PUSH="$REPO_ROOT/git-diary-workflow/git-lock-push.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Structural fix for id:05e8 flakiness: git-lock-push.sh guards the push with
# `ssh-add -l` — if the SSH agent has no key loaded (CI, expired agent, parallel
# suite run), it exits 0 without pushing and the push assertion fails.
# The remote here is a local file:// bare repo that needs NO SSH.  Inject a fake
# ssh-add that always exits 0 ("agent has keys") so the test never depends on the
# real SSH agent state.
fakebin="$tmpdir/bin"
mkdir -p "$fakebin"
printf '#!/bin/sh\nexec true\n' > "$fakebin/ssh-add"
chmod +x "$fakebin/ssh-add"
export PATH="$fakebin:$PATH"

bare="$tmpdir/remote.git"
work="$tmpdir/work"
other="$tmpdir/other"
git init --bare -q "$bare"
git init -q -b "relay/review-x" "$work"
git -C "$work" config user.email "test@test"
git -C "$work" config user.name "Test"
git -C "$work" remote add origin "$bare"

echo "init" > "$work/README"
git -C "$work" add README
git -C "$work" commit -q -m "init"
git -C "$work" push -q --set-upstream origin "relay/review-x" >/dev/null 2>&1

# Remote moves ahead by one commit (second clone pushes to the same branch)
git clone -q -b "relay/review-x" "$bare" "$other"
git -C "$other" config user.email "other@test"
git -C "$other" config user.name "Other"
echo "remote-side" > "$other/remote.txt"
git -C "$other" add remote.txt
git -C "$other" commit -q -m "remote-side commit"
git -C "$other" push -q origin "relay/review-x" >/dev/null 2>&1

# Local commit on the slash branch — lock-push must PULL (rebase) then push.
echo "local-side" > "$work/local.txt"
git -C "$work" add local.txt
git -C "$work" commit -q -m "local-side commit"

# Capture output instead of discarding it — id:456a flake diagnosis: on the
# intermittent failure we need to see WHICH skip path fired (flock timeout,
# ls-remote gate, upstream fallback), so dump everything when a check fails.
lockpush_out="$tmpdir/lockpush.out"
diagnose() {
  echo "--- git-lock-push output ---"
  cat "$lockpush_out"
  echo "--- branch -vv ---"
  git -C "$work" branch -vv
  echo "--- log --all ---"
  git -C "$work" log --oneline --all
}

"$LOCK_PUSH" "$work" >"$lockpush_out" 2>&1 \
  || { echo "git-lock-push failed on slash-named branch"; diagnose; exit 1; }

# Pull must have happened: the remote-side commit is now in local history.
git -C "$work" log --format=%s | grep -q "remote-side commit" \
  || { echo "pull was skipped: remote-side commit missing locally (slash-branch parse bug)"; diagnose; exit 1; }

# Push must have happened: the local-side commit reached the remote.
git -C "$bare" log --format=%s "relay/review-x" | grep -q "local-side commit" \
  || { echo "push did not reach remote on slash-named branch"; exit 1; }

echo ok
