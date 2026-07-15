#!/usr/bin/env bash
# worktree-retire.sh — FORCE-FREE retirement of ONE relay worktree + its branch (id:373e).
#
# Motivation: the pool's integrator + reconcile used to run `git worktree remove --force`
# and `git branch -D`. Under a strict destructive-op guardrail (docs/destructive-op-
# guardrail.md) those ops are DENIED, so worktrees never got removed and orphan debris
# accumulated every run. This helper retires a worktree WITHOUT any force op and WITHOUT
# ever discarding un-inspected work:
#
#   1. worktree gone from disk        → `git worktree prune` (non-destructive admin cleanup)
#   2. `git worktree remove` (NO -f)  → succeeds only on a CLEAN tree (executor committed
#                                       per contract; gitignored build residue does NOT block).
#      dirty / locked / unremovable   → SURFACE it and LEAVE it on disk for a supervised
#                                       reconcile / human. Never stash, clean, reset, or force.
#   3. `git branch -d` (NO -D)        → deletes only a provably-merged branch.
#      refused (unmerged commits)     → PARK: rename to relay/orphan/<bn>, KEEP the ref
#                                       (the refs ARE the registry, id:a4e9). Never -D.
#
# The branch step runs ONLY after the worktree is successfully removed (you cannot rename a
# branch checked out in a live worktree, and a dirty worktree we refuse to touch keeps BOTH
# its worktree and its branch — nothing is lost).
#
# SCOPE (id:6e02): operates on EXACTLY the one <worktree-dir> + <branch> passed. NO globbing,
# NO discovery, NO "tidy other relay/*". The 2026-07-01 incident (an integrator swept a live
# parallel child's worktree) is exactly what this single-target contract prevents. Discovery/
# selection stays in the callers (reconcile-repo.sh / the relay-loop integrator recipe).
#
# Usage:
#   worktree-retire.sh <repo-path> <worktree-dir> <branch> [--expect-merged]
#
#   --expect-merged   The caller proved the branch is already merged (e.g. reconcile's reap:
#                     merge-base --is-ancestor). Then a `branch -d` refusal is an ANOMALY
#                     (main moved? race?) surfaced LOUDLY, NOT silently parked.
#
# Exit codes:
#   0  retired cleanly (worktree removed, branch deleted or parked as designed)
#   2  usage / not-a-git-repo error
#   3  surfaced-and-left: worktree dirty/unremovable, or orphan ref collision — NOTHING forced
#   4  anomaly: --expect-merged but branch -d refused (worktree already removed; branch kept)
#
# Env overrides (hermetic tests):
#   WORKTREE_RETIRE_LOG   default ~/.claude/logs/relay-worktree-retire.log
set -euo pipefail

LOG="${WORKTREE_RETIRE_LOG:-$HOME/.claude/logs/relay-worktree-retire.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true  # swallow-ok: log dir best-effort; a missing log must never abort a retire
log() { printf '%s worktree-retire.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }  # swallow-ok: logging is advisory, never fatal

expect_merged=0
repo="" wt="" branch=""
pos=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect-merged) expect_merged=1; shift ;;
    -*) echo "worktree-retire.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) pos+=("$1"); shift ;;
  esac
done
[[ ${#pos[@]} -eq 3 ]] || { echo "worktree-retire.sh: usage: <repo-path> <worktree-dir> <branch> [--expect-merged]" >&2; exit 2; }
repo="${pos[0]}"; wt="${pos[1]}"; branch="${pos[2]}"

if [[ ! -d "$repo" ]] || ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "worktree-retire.sh: '$repo' is not a git repository" >&2
  exit 2
fi

bn="$(basename "$wt")"
orphan_ref="relay/orphan/$bn"

# ---- 1. worktree removal (never --force) -----------------------------------
if [[ ! -e "$wt" ]]; then
  # Directory already gone (crash / manual rm). Clear the stale admin ref — non-destructive,
  # discards nothing (there is nothing on disk to discard).
  git -C "$repo" worktree prune >/dev/null 2>&1 || true  # swallow-ok: prune is idempotent; a missing/already-pruned entry is fine
  log "prune repo=$repo wt=$wt (dir absent)"
else
  if git -C "$repo" worktree remove "$wt" >/dev/null 2>&1; then
    log "removed repo=$repo wt=$wt"
  else
    # Dirty (non-ignored untracked or tracked-modified), locked, or otherwise unremovable.
    # Per the no-force policy: SURFACE and LEAVE. Do NOT touch the branch — worktree+branch
    # both stay on disk for a supervised reconcile. Nothing is discarded or forced.
    msg="retire-deferred $bn: worktree dirty/unremovable — LEFT on disk for supervised reconcile (inspect: git -C $repo -C $wt status; then commit real work / gitignore throwaway, or remove by hand)"
    log "DEFER $msg"
    echo "$msg"
    exit 3
  fi
fi

# ---- 2. branch disposition (never -D) --------------------------------------
if git -C "$repo" branch -d "$branch" >/dev/null 2>&1; then
  log "deleted branch=$branch repo=$repo (merged)"
  echo "retired $bn: worktree removed, merged branch $branch deleted"
  exit 0
fi

# `branch -d` refused ⇒ the branch carries unmerged commits.
if [[ "$expect_merged" -eq 1 ]]; then
  msg="retire-anomaly $bn: caller expected $branch merged but 'git branch -d' refused (unmerged commits — main moved or a race?). Worktree already removed; branch KEPT as $branch. Investigate; do NOT -D."
  log "ANOMALY $msg"
  echo "$msg"
  exit 4
fi

# Park: keep the unmerged work as an orphan ref (id:a4e9 — refs ARE the registry). Never -D.
if git -C "$repo" show-ref --verify --quiet "refs/heads/$orphan_ref"; then
  msg="retire-deferred $bn: orphan ref $orphan_ref already exists — branch KEPT as $branch (worktree removed). Reconcile the older orphan by hand."
  log "ORPHAN-COLLISION $msg"
  echo "$msg"
  exit 3
fi
if git -C "$repo" branch -m "$branch" "$orphan_ref" >/dev/null 2>&1; then
  log "parked branch=$branch -> $orphan_ref repo=$repo (unmerged)"
  echo "retired $bn: worktree removed, unmerged branch parked as $orphan_ref (ref kept)"
  exit 0
fi

# Rename itself failed (unexpected) — surface, leave the branch untouched.
msg="retire-deferred $bn: worktree removed but 'git branch -m $branch $orphan_ref' failed — branch KEPT as $branch. Investigate."
log "PARK-FAILED $msg"
echo "$msg"
exit 3
