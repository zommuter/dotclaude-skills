#!/usr/bin/env bash
# roadmap:b87b
#
# RED SPEC for id:b87b: the id:b54b hermeticity backstop treats the runner's OWN branch
# advancing as a fixture leak.
#
# `snapshot_repo_state()` (tests/run-tests.sh:113) emits
# `git for-each-ref --format='%(refname) %(objectname)' refs/heads/relay/` and the guard
# fails on ANY before/after difference. Every relay worktree branch is named
# `relay/<runId>-<verdict>-repo-N`, so it is always inside that watched namespace, and
# because the snapshot records the OBJECT NAME a single commit on it is a diff even though
# no ref was added or removed. The executor contract requires a child to commit in its
# worktree as it goes, so this fires structurally, not by bad luck -- and it is terminal
# (`exit 1`) regardless of every individual test's result.
#
# Tripped live 2026-09-05 during the chain-end review of relay-20260905-113859-5807: the
# only differing line was this worktree's own branch, acba57d9 -> 5d388655, and the message
# nonetheless reported "left new relay/* refs ... a fixture reached the real repo".
#
# THE FIX MUST STAY NARROW, which is why case (2) below is an ARMED CONTROL rather than a
# courtesy: dropping object names from the snapshot would make case (1) pass while blinding
# the guard to a fixture force-moving some other relay ref. Excluding only the ref that HEAD
# points at keeps that coverage.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

RUNNER="$(pwd)/tests/run-tests.sh"
fails=0
FAIL() { echo "FAIL: $*"; fails=$((fails + 1)); }
pass() { echo "ok: $*"; }

# Extract the guard from the runner and exercise it directly. Invoking the whole suite
# recursively would take minutes and drag in every unrelated test's outcome.
snapshot_src=$(sed -n '/^snapshot_repo_state() {$/,/^}$/p' "$RUNNER")
if [[ -z "$snapshot_src" ]]; then
  echo "FIXTURE-BROKEN: could not extract snapshot_repo_state() from $RUNNER"
  exit 1
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

git -C "$scratch" init -q -b "relay/fixture-run-review-repo-0"
echo seed > "$scratch/file.txt"
git -C "$scratch" -c user.email=t@e -c user.name=t add -A
git -C "$scratch" -c user.email=t@e -c user.name=t commit -qm seed

run_guard() {  # $1 = shell snippet run BETWEEN the two snapshots; echoes "BREACH" or "CLEAN"
  ( cd "$scratch" || exit 1
    eval "$snapshot_src"
    before="$(snapshot_repo_state)"
    eval "$1" >/dev/null 2>&1
    after="$(snapshot_repo_state)"
    if [[ "$before" != "$after" ]]; then
      echo "BREACH"
      diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
    else
      echo "CLEAN"
    fi
  )
}

# FIXTURE SANITY / ARMED CONTROL, checked FIRST. If a leaked ref does NOT trip the guard,
# the detector is not running at all and case (1) would pass for the wrong reason.
ctl=$(run_guard 'git update-ref refs/heads/relay/leaked HEAD')
if [[ "$ctl" != BREACH* ]]; then
  echo "FIXTURE-BROKEN: an added refs/heads/relay/leaked did not trip the guard, so the"
  echo "assertions below would be vacuous. Guard said: $ctl"
  exit 1
fi
git -C "$scratch" update-ref -d refs/heads/relay/leaked

# (1) THE DEFECT: a commit on the runner's own branch must NOT be a breach.
own=$(run_guard 'echo more >> file.txt; git -c user.email=t@e -c user.name=t commit -qam "work as the contract requires"')
if [[ "$own" == CLEAN ]]; then
  pass "(1) a commit on the runner's own relay branch is not a breach"
else
  FAIL "(1) a commit on the runner's own relay branch was reported a breach -- $own"
fi

# (2) coverage preserved: an unrelated relay ref appearing IS still a breach.
leak=$(run_guard 'git update-ref refs/heads/relay/leaked HEAD')
if [[ "$leak" == BREACH* ]]; then
  pass "(2) an added unrelated relay ref is still a breach"
else
  FAIL "(2) an added unrelated relay ref no longer trips the guard -- the over-correction"
fi
git -C "$scratch" update-ref -d refs/heads/relay/leaked

# (3) coverage preserved: another relay ref being force-MOVED is still a breach. This is
# what a snapshot that dropped object names entirely would stop seeing.
git -C "$scratch" update-ref refs/heads/relay/other HEAD
moved=$(run_guard 'echo x >> file.txt; git -c user.email=t@e -c user.name=t commit -qam other; git update-ref refs/heads/relay/other HEAD')
if [[ "$moved" == BREACH* ]]; then
  pass "(3) a force-moved unrelated relay ref is still a breach"
else
  FAIL "(3) a force-moved unrelated relay ref no longer trips the guard -- object-name coverage was dropped"
fi

if (( fails )); then
  echo "$fails assertion(s) failed"
  exit 1
fi
echo "PASS: own-branch commits are hermetic, other relay-ref drift still fires (id:b87b)"
