#!/usr/bin/env bash
# roadmap:f8df — diary-append.sh -f consumes (deletes) the entry temp file BEFORE the
# commit+push succeeds, so a failed run (observed 2026-07-08: a concurrent commit made
# `git pull --rebase` die) silently LOSES the entry (id:4347 silent-swallow class).
# Contract: on a FAILED run the -f entry content SURVIVES (quarantined under a `.failed/`
# path announced loudly on stderr), and is not silently deleted.
#
# Hermetic: a file:// bare remote (no network, no real ssh transport) + a pre-created
# diverging local commit so `git pull --rebase` inside the lock CONFLICTS and fails.
# The ssh-agent setup block is skipped via DIARY_SKIP_SSH=1 (the seam the executor adds
# to make this testable); `timeout` bounds any un-skipped ssh path so the suite never hangs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/git-diary-workflow/diary-append.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

bare="$tmp/remote.git"
git init -q --bare "$bare"

# Origin clone → seed DIARY.md and push.
diary="$tmp/diary"
git clone -q "$bare" "$diary"
printf '# Diary\n\nbase line\n' > "$diary/DIARY.md"
git -C "$diary" add DIARY.md
git -C "$diary" commit -q -m "seed"
git -C "$diary" push -q origin HEAD:master 2>/dev/null || git -C "$diary" push -q origin HEAD:main
git -C "$diary" branch --set-upstream-to="origin/$(git -C "$diary" rev-parse --abbrev-ref HEAD)" >/dev/null 2>&1 || true

# A second clone advances the remote with a CONFLICTING change to the same region.
other="$tmp/other"
git clone -q "$bare" "$other"
printf '# Diary\n\nremote-diverged line\n' > "$other/DIARY.md"
git -C "$other" add DIARY.md
git -C "$other" commit -q -m "remote divergence"
git -C "$other" push -q origin HEAD

# In the diary clone, make a LOCAL commit that conflicts with the remote so the
# script's `git pull --rebase` will fail mid-rebase.
printf '# Diary\n\nlocal-diverged line\n' > "$diary/DIARY.md"
git -C "$diary" add DIARY.md
git -C "$diary" commit -q -m "local divergence"

# The -f entry temp file the run must NOT lose on failure.
entry_file="$tmp/entry.txt"
marker="ENTRY-SURVIVES-$$-$RANDOM"
printf 'diary entry body %s\n' "$marker" > "$entry_file"

set +e
DIARY_REPO_DIR="$diary" DIARY_SKIP_SSH=1 timeout 20 \
  bash "$SCRIPT" -m "diary: test" -p "/tmp/project" -f "$entry_file" >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e

# The run must have FAILED (the rebase conflict) — a passing run would mean the fixture
# did not actually exercise the failure path.
[[ $rc -ne 0 ]] \
  || { echo "fixture error: the run was expected to FAIL (rebase conflict) but exited 0"; cat "$tmp/out" "$tmp/err"; exit 1; }

# The entry content must SURVIVE somewhere under the diary repo (a .failed/ quarantine),
# NOT be silently deleted. Search the diary tree for the marker.
if grep -rq "$marker" "$diary" --exclude-dir=.git 2>/dev/null; then
  :
else
  echo "FAIL: entry content ($marker) was LOST on a failed run — the -f temp file was consumed before commit+push succeeded (id:f8df)"
  echo "--- stderr ---"; cat "$tmp/err"
  echo "--- entry_file still exists? ---"; [[ -e "$entry_file" ]] && echo yes || echo no
  exit 1
fi

echo ok
