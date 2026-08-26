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
#   worktree-retire.sh <repo-path> <worktree-dir> <branch> [--expect-merged] [--commit-residue]
#
#   --expect-merged   The caller proved the branch is already merged (e.g. reconcile's reap:
#                     merge-base --is-ancestor). Then a `branch -d` refusal is an ANOMALY
#                     (main moved? race?) surfaced LOUDLY, NOT silently parked.
#
#   --commit-residue  OPT-IN (id:f272). Default behaviour (flag absent) is UNCHANGED: a dirty
#                     worktree is still surfaced-and-left, exit 3. With the flag, a DIRTY worktree
#                     on a relay-owned branch (refs/heads/relay/…), with --expect-merged NOT also
#                     passed, gets its residue committed onto that SAME branch first (a WIP/
#                     UNVERIFIED commit naming the worktree) so the normal remove+park path below
#                     can run and the branch ends up a reachable `relay/orphan/<bn>` ref instead of
#                     stranding on disk. Committing residue is NOT a force op — it discards
#                     nothing, unlike stash/clean/reset (id:373e bans discarding, not committing).
#                     A dirty worktree on a NON-relay branch, or when --expect-merged is also set,
#                     is untouched by this flag and still surfaces-and-leaves as before.
#
# THE THIRD BRANCH THIS SCRIPT DELIBERATELY DOES NOT HAVE (id:8d76) — owner-authorized DISCARD.
# Both dirty-tree paths above assume the residue might be worth keeping. When the owner has
# INSPECTED the residue and ruled it worthless-or-harmful, neither fits:
#   - the default (surface-and-leave, exit 3) parks known-bad content on disk indefinitely;
#   - --commit-residue makes it WORSE for harmful residue — it moves the content out of an
#     unreachable index into a reachable, pushable `relay/orphan/*` ref, and the pre-push
#     privacy gate is warn+LOG only (id:df87), so nothing would block a later publish.
# There is NO flag for this and that is intentional: discarding is the one act id:373e bans,
# so it stays a deliberate, supervised human step OUTSIDE this script. The exit is:
#   1. confirm the branch has 0 unmerged commits (`git log --oneline main..<branch>` empty),
#      so the residue really is the whole content and nothing of record is lost;
#   2. the human runs the force removal themselves, at a prompt they answer;
#   3. finish the branch half HERE or with plain `git branch -d` — a merged branch never
#      needs -D, and reaching for -D is the signal that step 1 was skipped.
# Recorded 2026-08-26 after a session reached for the raw force op because this header did not
# say the above. If you are about to do the same: you are in the supported case, not a gap.
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
commit_residue=0
repo="" wt="" branch=""
pos=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect-merged) expect_merged=1; shift ;;
    --commit-residue) commit_residue=1; shift ;;
    -*) echo "worktree-retire.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) pos+=("$1"); shift ;;
  esac
done
[[ ${#pos[@]} -eq 3 ]] || { echo "worktree-retire.sh: usage: <repo-path> <worktree-dir> <branch> [--expect-merged] [--commit-residue]" >&2; exit 2; }
repo="${pos[0]}"; wt="${pos[1]}"; branch="${pos[2]}"

if [[ ! -d "$repo" ]] || ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "worktree-retire.sh: '$repo' is not a git repository" >&2
  exit 2
fi

bn="$(basename "$wt")"
orphan_ref="relay/orphan/$bn"

# ---- 0. git-annex layout normalization (id:de4a) ----------------------------
# On a git-annex repo the smudge filter (filter.annex.process) rewrites a linked worktree's
# `.git` FILE into a SYMLINK to the admin dir (so annexed relative symlinks
# ../.git/annex/objects/... resolve inside the worktree). `git worktree remove` then fails
# validation PERMANENTLY — "'<wt>/.git' is not a .git file, error code 10" — and --force does
# NOT help, because validation precedes it. Result: on an annex repo every relay worktree
# leaked forever (zkWhale: the only annex repo among own repos, 3 dirs / 1.2G, all clean+merged).
#
# We restore the standard `gitdir: <admin>` pointer that git itself writes. This is NOT a force
# op and discards NOTHING: the admin dir, the index, and every file in the tree are untouched —
# we rewrite only the pointer, converting an unremovable layout back into git's own supported
# one. The dirty check below still runs afterwards and still wins, so this can never become a
# backdoor that removes uncommitted work.
#
# GUARDED: we normalize ONLY when the symlink resolves to THIS repo's own admin dir for THIS
# worktree. Anything else is surfaced untouched — we never rewrite a pointer we don't recognize.
if [[ -L "$wt/.git" ]]; then
  # --path-format=absolute: a bare --git-common-dir is repo-RELATIVE (".git"), which would
  # make the comparison below compare against a nonsense path and always defer.
  admin_expect="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/worktrees/$bn"
  admin_expect="$(readlink -f "$admin_expect" || printf '%s' "$admin_expect")"
  admin_actual="$(readlink -f "$wt/.git" || true)"
  if [[ -n "$admin_actual" && "$admin_actual" == "$admin_expect" && -d "$admin_actual" ]]; then
    rm -- "$wt/.git"
    printf 'gitdir: %s\n' "$admin_actual" > "$wt/.git"
    log "normalized annex .git symlink -> gitdir file repo=$repo wt=$wt admin=$admin_actual"
  else
    msg="retire-deferred $bn: '$wt/.git' is a SYMLINK that does not resolve to this repo's own admin dir (expected '$admin_expect', got '${admin_actual:-<unresolvable>}') — LEFT untouched for a human. Not normalizing a pointer we do not recognize."
    log "DEFER-UNRECOGNIZED-SYMLINK $msg"
    echo "$msg"
    exit 3
  fi
fi

# ---- 0c. optional dirty-residue commit (id:f272, opt-in via --commit-residue) --
# Runs BEFORE the removal attempt below so a dirty tree becomes clean and the normal
# remove+park path can proceed unmodified — commit-and-park reuses the existing park logic
# rather than adding a new disposal branch. Guards, all required: the flag was passed, the
# worktree still exists, the caller is NOT claiming the branch is already merged (a merged
# branch dirty on disk is a different anomaly, not this path), and the branch is relay-owned
# (`relay/…` — never touch a branch this helper doesn't own). Committing is never a force op:
# it discards nothing, it only moves untracked/modified content into a new commit on the
# worktree's OWN branch (id:373e bans discarding, not committing).
if [[ "$commit_residue" -eq 1 && -e "$wt" && "$expect_merged" -eq 0 && "$branch" == relay/* ]]; then
  if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
    git -C "$wt" add -A
    # --no-verify: this is an emergency preservation commit, not a reviewed change — a
    # repo-local pre-commit hook (e.g. a lint/lane-vocab gate) must never cause residue to be
    # lost. The commit is explicitly marked WIP/UNVERIFIED so nothing downstream mistakes it
    # for reviewed work; the reviewer's normal test-integrity checks (contract rule 3) still
    # apply once a human/relay picks the parked orphan back up.
    if git -C "$wt" commit -q --no-verify -m "chore(relay): WIP UNVERIFIED residue auto-commit for worktree $bn (id:f272 commit-and-park; do not treat as reviewed)"; then
      log "commit-residue committed dirty state branch=$branch wt=$wt"
    else
      log "commit-residue FAILED to commit dirty state branch=$branch wt=$wt — falling through to normal surface-and-leave"
    fi
  fi
fi

# ---- 1. worktree removal (never --force) -----------------------------------
if [[ ! -e "$wt" ]]; then
  # Directory already gone (crash / manual rm). Clear the stale admin ref — non-destructive,
  # discards nothing (there is nothing on disk to discard).
  git -C "$repo" worktree prune >/dev/null 2>&1 || true  # swallow-ok: prune is idempotent; a missing/already-pruned entry is fine
  log "prune repo=$repo wt=$wt (dir absent)"
else
  # Capture stderr: it is the ONLY thing that distinguishes a dirty tree (surface+leave is
  # correct) from a structural failure (a permanent leak no amount of committing fixes). It
  # was previously swallowed, so the annex case above masqueraded as "dirty" for weeks on a
  # provably CLEAN tree, and the advice we printed ("commit real work") could never work.
  if err="$(git -C "$repo" worktree remove "$wt" 2>&1)"; then
    log "removed repo=$repo wt=$wt"
  else
    # Dirty (non-ignored untracked or tracked-modified), locked, or otherwise unremovable.
    # Per the no-force policy: SURFACE and LEAVE. Do NOT touch the branch — worktree+branch
    # both stay on disk for a supervised reconcile. Nothing is discarded or forced.
    msg="retire-deferred $bn: worktree unremovable — LEFT on disk for supervised reconcile. git said: ${err//$'\n'/ } (inspect: git -C $wt status; then commit real work / gitignore throwaway, or remove by hand)"
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
