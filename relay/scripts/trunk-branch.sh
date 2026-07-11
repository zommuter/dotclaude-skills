#!/usr/bin/env bash
# trunk-branch.sh <repo> — echo a repo's INTEGRATION/trunk branch NAME.
#
# THE integration branch is whatever the repo's MAIN checkout actually has checked out —
# which is *exactly* what relay children branch from (`git -C <repo> worktree add <wt> -b
# <branch> HEAD`, relay-loop.js) and what the supervisor merges back into. Resolving it
# from HEAD keeps the reap/park ancestry test (reconcile-repo.sh) and the orphan-classifier
# merge-base (relay-reconcile.sh) consistent with the base children forked from.
#
# WHY (the recurring-orphan bug this fixes): the reap/park decision used to test
# `merge-base --is-ancestor <worktree-branch> main` with `main` HARDCODED. A repo whose
# trunk is NOT literally `main` — e.g. ai-codebench works on `claude/opusplan` while `main`
# is frozen at an old checkpoint — has every leftover worktree fail that ancestry test
# (its commits live on the real trunk, never on frozen `main`), so a perfectly-integrated
# run's worktree gets PARKED as a `relay/orphan/*` branch every single round. Same latent
# bug for any `master`-trunk repo. Resolving the trunk from HEAD dissolves it structurally.
#
# Resolution order:
#   1. The checked-out branch of the main checkout (`symbolic-ref --short HEAD`) — the one
#      children branch from. This is the answer in the normal, attached-HEAD case.
#   2. Only if HEAD is DETACHED: conventional fallback `main` → `master` → `main`.
#
# Usage: trunk-branch.sh <repo-path>
set -euo pipefail

r="${1:?trunk-branch.sh: <repo-path> required}"

# 1. The branch the main checkout is on — definitionally the base children fork from.
if b="$(git -C "$r" symbolic-ref --quiet --short HEAD 2>/dev/null)" && [ -n "$b" ]; then
  echo "$b"
  exit 0
fi

# 2. Detached HEAD → conventional trunk fallback.
git -C "$r" rev-parse --verify -q main   >/dev/null 2>&1 && { echo main;   exit 0; }
git -C "$r" rev-parse --verify -q master >/dev/null 2>&1 && { echo master; exit 0; }
echo main
