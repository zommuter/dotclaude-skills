#!/usr/bin/env bash
# roadmap:1b18 — diary-append.sh's replay loop appends every `.diary-pending-*` /
# `.failed/entry-*` file into DIARY.md and `rm`s it BEFORE `git pull --rebase`.
# That append DIRTIES the working tree, so the very next `git pull --rebase` refuses
# ("cannot pull with rebase: You have unstaged changes") and calls on_failure — which
# quarantines only the CURRENT entry, NOT the already-appended-and-unlinked replayed
# text. The replayed content strands as an uncommitted DIARY.md change, and because the
# tree stays dirty EVERY subsequent run's pull refuses too → deadlock until a human
# commits by hand (observed live 2026-07-12 09:51 across two parallel sessions plus a
# stranded quota-sample line).
#
# Contract: pull FIRST, replay AFTER (or commit replays as their own commit before the
# pull) — preserving exactly-once + the no-entry-loss quarantine. A pre-existing
# quarantined entry must NOT strand, and a later run must CONVERGE: all entries land in
# committed+pushed history exactly once and the working tree ends CLEAN with no pending
# files.
#
# Hermetic: file:// bare remote, DIARY_SKIP_SSH=1. No divergence — the deadlock is
# triggered purely by the replay-before-pull ordering dirtying the tree.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/git-diary-workflow/diary-append.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

bare="$tmp/remote.git"
git init -q --bare "$bare"

diary="$tmp/diary"
git clone -q "$bare" "$diary"
printf '# Diary\n\nbase line\n' > "$diary/DIARY.md"
git -C "$diary" add DIARY.md
git -C "$diary" commit -q -m seed
git -C "$diary" push -q origin HEAD:master 2>/dev/null || git -C "$diary" push -q origin HEAD:main
git -C "$diary" branch --set-upstream-to="origin/$(git -C "$diary" rev-parse --abbrev-ref HEAD)" >/dev/null 2>&1 || true

# A pre-existing quarantined entry (as a previous failed/lock-timeout run would leave).
mkdir -p "$diary/.failed"
q_marker="QUARANTINED-$$-$RANDOM"
printf '\n## 20260712-000000 host:sid /tmp/proj\nquarantined body %s\n' "$q_marker" \
  > "$diary/.failed/entry-20260712-000000-1"

run() {
  # $1 = marker for this run's current entry
  local m="$1"
  set +e
  DIARY_REPO_DIR="$diary" DIARY_SKIP_SSH=1 timeout 30 \
    bash "$SCRIPT" -m "diary: $m" -p "/tmp/proj" -e "current body $m" >"$tmp/out" 2>"$tmp/err"
  set -e
}

a_marker="CURRENT-A-$$-$RANDOM"
b_marker="CURRENT-B-$$-$RANDOM"
run "$a_marker"     # run 1: drains the quarantine + appends A
run "$b_marker"     # run 2: a later run appends B

fails=0

# Convergence: every marker committed exactly once (in git HEAD, not just the dirty tree).
committed="$(git -C "$diary" show HEAD:DIARY.md 2>/dev/null || echo)"
for mk in "$q_marker" "$a_marker" "$b_marker"; do
  n="$(grep -c "$mk" <<<"$committed" || true)"
  if [[ "$n" != "1" ]]; then
    echo "FAIL: marker $mk appears $n time(s) in committed DIARY.md (want exactly 1) — replayed/strayed entry (roadmap:1b18)"
    fails=1
  fi
done

# Working tree must end CLEAN (the deadlock symptom is a permanently-dirty DIARY.md).
if [[ -n "$(git -C "$diary" status --porcelain)" ]]; then
  echo "FAIL: working tree is DIRTY after convergence — replayed text stranded uncommitted (roadmap:1b18)"
  git -C "$diary" status --porcelain
  fails=1
fi

# No quarantine/pending files may linger once drained.
if compgen -G "$diary/.failed/entry-*" >/dev/null || compgen -G "$diary/.diary-pending-*" >/dev/null; then
  echo "FAIL: quarantine/pending files remain after convergence (roadmap:1b18)"
  ls -la "$diary/.failed" 2>/dev/null
  fails=1
fi

# The converged commit must be PUSHED (bare remote tip == local HEAD).
branch="$(git -C "$diary" symbolic-ref --short HEAD)"
local_head="$(git -C "$diary" rev-parse HEAD)"
remote_head="$(git --git-dir="$bare" rev-parse "refs/heads/$branch" 2>/dev/null || echo none)"
if [[ "$local_head" != "$remote_head" ]]; then
  echo "FAIL: converged entries not pushed (local HEAD $local_head != bare refs/heads/$branch $remote_head) (roadmap:1b18)"
  fails=1
fi

[[ $fails -eq 0 ]] && echo ok
exit $fails
