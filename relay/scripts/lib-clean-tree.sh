#!/usr/bin/env bash
# relay/scripts/lib-clean-tree.sh -- THE single "is this work tree CLEAN?" predicate
# (id:68e2). ONE definition, sourced by every caller.
#
# WHY THIS FILE EXISTS
#   The correct answer lived INLINE in verify-isolation.sh as the id:3016 filter-aware
#   predicate. worktree-retire.sh asked the SAME question in three places with a BARE
#   `git status --porcelain` non-empty test, and so answered it differently: on a git-annex
#   repo the two scripts disagreed about the very same worktree, one calling it clean and the
#   other refusing to retire it. Measured 2026-09-11 on zomni (pool run
#   relay-20260910-234645-16942, four worktrees under code.lawless): three of four reported
#   204 porcelain entries, ALL of them ` M`, with `git diff --stat` and `git diff --cached
#   --stat` both empty and zero commits ahead of main. The fourth was a genuinely empty
#   control from the same run, so the probe reached and discriminated.
#   N divergent copies of one predicate is a failure class this fleet keeps paying for, so
#   the predicate is extracted HERE and every caller sources this one copy.
#
# WHAT MAKES IT CORRECT (the id:3016 reasoning, preserved)
#   A BARE `status --porcelain` non-empty test false-trips on git-annex. Unlocked annex
#   pointer files report ` M` while `git diff` is EMPTY: the index holds the pointer blob and
#   the worktree holds the real content, and annex could not update the index during checkout.
#   git-annex's own message calls it "only a cosmetic problem affecting git status" and names
#   `git-annex restage` as the remedy.
#
#   WHY NOT `git update-index --refresh` FIRST: measured under id:3016 (2026-09-09) -- it did
#   NOT clear the reported paths. It is the obvious cheap fix and it does not work here; do
#   not re-add it.
#
#   WHY NOT "just require a non-empty `git diff`": `status --porcelain` also reports UNTRACKED
#   files, which `git diff` NEVER shows. Relaxing on an empty diff alone would blind these
#   gates to genuine untracked residue -- which is most of what they exist to catch, since a
#   child that writes into a checkout leaves exactly that. So the relaxation is narrowed to
#   ONE case: EVERY porcelain entry is worktree-modified-only (` M`, index column blank) AND
#   `git diff` reports no unstaged change. Anything staged, untracked, added, deleted or
#   conflicted keeps a non-` M` entry and stays DIRTY.
#
# FAIL DIRECTION -- UNKNOWN IS NOT CLEAN
#   `$(git status ... 2>/dev/null)` yields EMPTY when git FAILS, and empty read as CLEAN is
#   how worktree-retire.sh's submodule hatch once destroyed uncommitted work (id:a290 round-3,
#   finding 1). So the status exit is captured SEPARATELY and a failure is its own return code
#   2, never folded into "clean". A `git diff` that errors (exit > 1) is likewise DIRTY, since
#   only a clean exit 0 is evidence of no unstaged change. Callers MUST treat 2 as dirty; the
#   one caller that deliberately does not (verify-isolation.sh, preserving its pre-id:68e2
#   behaviour verbatim) says so at its call site.
#
# USAGE
#   source .../relay/scripts/lib-clean-tree.sh
#   if tree_clean_probe "$wt"; then ...clean...; fi          # rc 0 clean, 1 dirty, 2 unknown
#   tree_clean_probe "$wt" --ignore-submodules=none          # extra args go to status AND diff
#
#   After the call these globals are set (and reset on every call):
#     TREE_PORCELAIN       the raw `status --porcelain` output (empty when rc is 2)
#     TREE_STATUS_RC       the exit status of `git status` itself
#     TREE_COSMETIC        1 when rc 0 was reached THROUGH the annex relaxation, else 0
#     TREE_COSMETIC_COUNT  how many entries that relaxation forgave (0 unless TREE_COSMETIC=1)
#
#   tree_cosmetic_remedy "$wt"  echoes the operator-facing remedy sentence for a cosmetic
#   tree. The remedy is CONDITIONAL on `.git` already being a gitdir FILE, see below.
#
# Safe under `set -euo pipefail`: no bare `cmd && return` tails.

# shellcheck shell=bash

# These four are the function's OUT-parameters, read by the sourcing script, so shellcheck's
# "appears unused" is expected here.
# shellcheck disable=SC2034
TREE_PORCELAIN=""
# shellcheck disable=SC2034
TREE_STATUS_RC=0
# shellcheck disable=SC2034
TREE_COSMETIC=0
# shellcheck disable=SC2034
TREE_COSMETIC_COUNT=0

# tree_clean_probe <worktree> [extra args for git status/diff]
#   rc 0 = CLEAN (porcelain empty, OR every entry ' M' with an empty unstaged diff)
#   rc 1 = DIRTY (real residue)
#   rc 2 = UNKNOWN (`git status` failed; its empty output is NOT evidence of cleanliness)
tree_clean_probe() {
  local wt="${1:-}"
  shift || true

  TREE_PORCELAIN=""
  TREE_STATUS_RC=0
  TREE_COSMETIC=0
  TREE_COSMETIC_COUNT=0

  local out rc=0
  out="$(git -C "$wt" status --porcelain "$@" 2>/dev/null)" || rc=$?
  TREE_STATUS_RC="$rc"
  if [ "$rc" -ne 0 ]; then
    return 2
  fi

  TREE_PORCELAIN="$out"
  if [ -z "$out" ]; then
    return 0
  fi

  # Residue = every entry that is NOT plain worktree-modified. `${entry:0:2}` is the XY status
  # pair; only the exact pair ' M' qualifies for the annex relaxation.
  local entry residue=""
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    [ "${entry:0:2}" = " M" ] && continue
    residue="${residue}${entry}"$'\n'
  done <<< "$out"
  if [ -n "$residue" ]; then
    return 1
  fi

  # Only a clean exit 0 from `git diff --quiet` proves there is no unstaged change; exit 1 is
  # "differences found" and anything higher is an error, and both stay DIRTY.
  if git -C "$wt" diff --quiet "$@" 2>/dev/null; then
    TREE_COSMETIC=1
    TREE_COSMETIC_COUNT="$(printf '%s\n' "$out" | grep -c . || true)"
    return 0
  fi
  return 1
}

# tree_cosmetic_remedy <worktree> -- the operator-facing remedy for a cosmetic-dirty tree.
#
# Measured 2026-09-09 on code.lawless: with `.git` still a SYMLINK (the normal state of a
# fresh relay worktree), `git annex restage` prints `restage ok` and changes NOTHING -- annex
# warns it is "unable to convert .git file to symlink that will work with git-annex" and
# cannot update the index through the symlinked admin dir. It only works once `.git` has been
# normalised to a gitdir FILE, which is what worktree-retire.sh's id:de4a fix does. So de4a is
# a PREREQUISITE of this remedy, not an adjacent fix -- name the right step for the shape
# actually present, or the reader wastes time on a no-op that looks like the fix failing.
tree_cosmetic_remedy() {
  local wt="${1:-}"
  if [ -L "$wt/.git" ]; then
    printf '%s' "normalise the worktree's \`.git\` symlink to a gitdir file FIRST (worktree-retire.sh does this, id:de4a) and THEN run 'git annex restage' -- restage through a symlinked .git prints 'restage ok' and silently no-ops"
  else
    printf '%s' "run 'git annex restage' in the worktree to clear the display"
  fi
}
