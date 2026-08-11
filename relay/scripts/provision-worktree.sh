#!/usr/bin/env bash
# provision-worktree.sh — id:34b7 parts (1)+(2): the PARENT creates + provisions a
# relay child's worktree BEFORE dispatch, so the child is never handed the main-checkout
# path and has no reason or means to reach into it.
#
#   (1) `git worktree add` — moved here from the child prompt's "Create your worktree
#       first" instruction (relay-loop.js's unitPrompt()/provisionWorktree()).
#   (2) provision the gitignored build artifacts a child would otherwise have to reach
#       into main for — symlinked, best-effort. Children already did this by hand,
#       per-child, every time (loderite RELAY_LOG.md:2681, with :3022/:3422/:3486 showing
#       them removing the symlink again before commit) — this absorbs that manual step.
#       Deliberately NOT exhaustive of every artifact class a repo might have, just the
#       two named in id:34b7's own text (node_modules, .venv); a missing class is a
#       no-op, not a failure.
#
# Usage: provision-worktree.sh <repo-path> <worktree-dir> <branch>
#
# SCOPE: operates on exactly the one <repo-path>/<worktree-dir>/<branch> passed — no
# globbing, no discovery (same single-target discipline as worktree-retire.sh, id:6e02).
set -euo pipefail

repo_path="${1:?usage: provision-worktree.sh <repo-path> <worktree-dir> <branch>}"
wt="${2:?usage: provision-worktree.sh <repo-path> <worktree-dir> <branch>}"
branch="${3:?usage: provision-worktree.sh <repo-path> <worktree-dir> <branch>}"

git -C "$repo_path" worktree add "$wt" -b "$branch" HEAD

# Part (2), best-effort — a repo missing either artifact class is a no-op, never fatal.
[[ -d "$repo_path/node_modules" ]] && ln -s "$repo_path/node_modules" "$wt/node_modules" || true
[[ -d "$repo_path/.venv" ]] && ln -s "$repo_path/.venv" "$wt/.venv" || true

exit 0
