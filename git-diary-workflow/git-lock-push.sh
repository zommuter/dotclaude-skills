#!/usr/bin/env bash
# git-lock-push.sh — flock-serialized (stage+commit / merge +) pull + push
#
# Three modes:
#   Legacy mode (no -f/-m/--merge-branch): Run AFTER git commit — the commit is
#     local and safe; only the pull+push needs serialization.
#   Manifest mode (-f <file> -m <msg>): stage+commit+pull+push inside flock
#     Only the listed paths are staged (never git add -A).
#   Merge-branch mode (--merge-branch <branch> [-m msg]): id:3558 — flock'd
#     merge-to-canonical for an INDEPENDENT session that did its work in its own
#     git worktree (own working tree, own commits on <branch>, sharing this
#     repo's object store/refs). Under the same per-repo flock as the other
#     modes: `git merge --no-ff <branch>` into the canonical checkout's current
#     branch, then pull+push as usual. A real conflict ABORTS the merge and
#     exits non-zero — NOT merged, NOT pushed, work stays on <branch> untouched
#     (fail-loud, never silent-lose a side per D5.2's plumbing-CAS rejection).
#     This is D5.6 (deferred until a 2nd cross-session race recurred — it did,
#     see TODO id:3558): worktree-per-session isolates EDITING; this is the
#     "merging back into shared canonical" half, kept small by reusing the
#     existing flock + pull/push machinery rather than a bespoke merge daemon.
#
# Usage: git-lock-push.sh [REPO_PATH] [-b branch] [-f manifest-file] [-m msg]
#                          [--merge-branch branch] [--ff-only]
#   -b          Branch to rebase against (default: detected from tracking branch)
#   -f          Manifest file (one path per line) — requires -m
#   -m          Commit message — requires -f, OR the commit message for --merge-branch
#   --merge-branch  Branch to `--no-ff` merge into HEAD before pull+push (id:3558).
#                   Mutually exclusive with -f/manifest mode.
#   --ff-only   Use fast-forward-only reconcile instead of rebase; fails loud on divergence.
#               Use this when the local branch has annotated tags or --no-ff merges that must
#               not be rewritten (e.g. the relay integration branch).

set -euo pipefail

# Never let git or ssh open an interactive prompt (askpass / browser / credential helper).
# Automated callers (systemd timers) rely on this; interactive callers have a loaded
# agent already. GIT_SSH_COMMAND is set again per-push below for BatchMode.
export GIT_TERMINAL_PROMPT=0

branch=""
manifest_file=""
commit_msg=""
merge_branch=""
ff_only=0
# getopts does not handle long opts; strip --ff-only and --merge-branch <val>
# before the getopts loop (the latter consumes the following arg as its value).
args=()
take_next_as_merge_branch=0
for arg in "$@"; do
  if [[ "$take_next_as_merge_branch" -eq 1 ]]; then
    merge_branch="$arg"
    take_next_as_merge_branch=0
  elif [[ "$arg" == "--ff-only" ]]; then
    ff_only=1
  elif [[ "$arg" == "--merge-branch" ]]; then
    take_next_as_merge_branch=1
  else
    args+=("$arg")
  fi
done
# id:c79e-sibling (Fable-review finding 4) — `--merge-branch` as the LAST arg leaves
# take_next_as_merge_branch stuck at 1 and merge_branch empty; without this check that
# silently degrades to legacy mode (no merge performed, no error) instead of failing loud
# on a missing branch name.
if [[ "$take_next_as_merge_branch" -eq 1 ]]; then
  echo "ERROR: --merge-branch requires a branch name argument" >&2
  exit 1
fi
set -- "${args[@]+"${args[@]}"}"

while getopts "b:f:m:" opt; do
  case "$opt" in
    b) branch="$OPTARG" ;;
    f) manifest_file="$OPTARG" ;;
    m) commit_msg="$OPTARG" ;;
    *) echo "Usage: $0 [REPO_PATH] [-b branch] [-f manifest-file] [-m msg] [--merge-branch branch] [--ff-only]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [[ -n "$manifest_file" && -n "$merge_branch" ]]; then
  echo "ERROR: -f (manifest mode) and --merge-branch are mutually exclusive" >&2; exit 1
fi

# Fable-review finding 4: --merge-branch mode IMPLIES --ff-only. A --no-ff merge commit
# just created above is exactly the kind of topology `git pull --rebase` flattens (it
# replays commits linearly, dropping the merge commit and its message, and re-plays any
# conflicts the merge already resolved). --merge-branch mode always wants the
# committed-locally-not-pushed-loud fallback on remote divergence, never a silent
# rebase-flatten — so force ff_only regardless of whether the caller also passed --ff-only.
if [[ -n "$merge_branch" ]]; then
  ff_only=1
fi
if [[ -n "$manifest_file" && -z "$commit_msg" ]]; then
  echo "ERROR: -f requires -m (commit message)" >&2; exit 1
fi
if [[ -n "$commit_msg" && -z "$manifest_file" && -z "$merge_branch" ]]; then
  echo "ERROR: -m requires -f (manifest file) or --merge-branch" >&2; exit 1
fi

if [[ -n "${1:-}" ]]; then
  cd "$1"
fi

repo_root="$(git rev-parse --show-toplevel)"

# Lock file in repo root — except ~/.claude, where we use /tmp to avoid
# needing blanket write permissions on the settings directory.
if [[ "$repo_root" == "$HOME/.claude" ]]; then
  lock_file="/tmp/claude-git-dotclaude.lock"
else
  lock_file="$repo_root/.git-lock-push.lock"
fi

exec 8>"$lock_file"
if ! flock -x -w 30 8; then
  echo "WARNING: Could not acquire git lock after 30s. Commit saved locally, not pushed." >&2
  echo "Run 'git push' manually or it will push next session." >&2
  exec 8>&-
  exit 0  # non-fatal — work is committed
fi

# Merge-branch mode (id:3558): --no-ff merge an independent session's worktree
# branch into HEAD inside the lock. Fail-loud on conflict — abort the merge,
# leave <branch> untouched, exit non-zero WITHOUT pulling/pushing (D5.2: a
# real same-path conflict must be surfaced, never silently last-writer-wins).
if [[ -n "$merge_branch" ]]; then
  merge_msg="${commit_msg:-merge: $merge_branch (flock-serialized merge-to-canonical, id:3558)}"
  if ! git merge --no-ff -q -m "$merge_msg" "$merge_branch"; then
    git merge --abort >/dev/null 2>&1 || true
    echo "ERROR: --no-ff merge of '$merge_branch' into $(git rev-parse --abbrev-ref HEAD) conflicted — NOT merged, NOT pushed (id:3558)." >&2
    echo "Resolve manually: git merge --no-ff $merge_branch" >&2
    exec 8>&-
    exit 1
  fi
fi

# Manifest mode: stage from manifest and commit inside the lock
if [[ -n "$manifest_file" ]]; then
  if [[ ! -f "$manifest_file" ]]; then
    echo "ERROR: manifest file not found: $manifest_file" >&2
    exec 8>&-
    exit 1
  fi
  while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -z "$path" ]] && continue
    git add -- "$path"
  done < "$manifest_file"
  git commit -m "$commit_msg"
fi

# Detect tracking branch, fall back to origin main.
# Split remote/branch at the FIRST slash only — branch names may themselves
# contain slashes (e.g. origin/relay/review-x → remote=origin branch=relay/review-x);
# the old `tr '/' ' '` split broke those and silently skipped the pull.
if [[ -n "$branch" ]]; then
  target="$branch"
else
  if upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"; then
    target="${upstream%%/*} ${upstream#*/}"
  else
    target="origin main"
  fi
fi

# Only pull if the remote branch exists (first-push scenario: skip, just push)
remote_name="${target%% *}"
remote_branch="${target#* }"
if git ls-remote --exit-code "$remote_name" "refs/heads/$remote_branch" >/dev/null 2>&1; then
  if [[ "$ff_only" -eq 1 ]]; then
    # --ff-only: no SHA rewrite — annotated tags and --no-ff merge topology survive.
    # On divergence, fail loud; work stays committed locally (non-fatal, same as flock-timeout).
    if ! git pull --ff-only $target; then
      echo "WARNING: ff-only pull failed (remote diverged). Commit saved locally, not pushed." >&2
      echo "Resolve the divergence manually and run 'git push' to publish." >&2
      exec 8>&-
      exit 0  # non-fatal — work is committed
    fi
  else
    # id:aa93 — rebasing over a foreign-dirty tree (a human / parallel session's uncommitted
    # edit, made outside any lock the editor respects) risks silent data loss. In legacy mode
    # (no manifest) the caller has NOT committed anything here, so any TRACKED dirty entry is
    # foreign: refuse and leave the work committed-locally-not-pushed (non-fatal, same as a
    # flock timeout). Manifest mode just committed the listed paths, so a residual
    # tracked-dirty tree there is also foreign — same refusal.
    #
    # id:dff8 — untracked-only churn (porcelain lines all `?? `) carries none of that risk:
    # a rebase never touches untracked paths, and one that would clobber an untracked file
    # aborts loudly on its own (safe-and-loud). Repos with perpetual untracked runtime churn
    # (e.g. `~/.claude`'s `plans/`, `session-env/`, `sessions/`, `tasks/`) would otherwise
    # refuse every push. So: untracked-only → proceed with the rebase; any tracked
    # modified/staged/renamed entry → still refuse (the id:aa93 data-loss guard is unchanged
    # for tracked dirt).
    porcelain="$(git status --porcelain)"
    if [[ -n "$porcelain" ]] && grep -qv '^?? ' <<<"$porcelain"; then
      echo "WARNING: working tree has uncommitted tracked changes; not rebasing (id:aa93)." >&2
      echo "Commit or move the changes, then run 'git push' manually." >&2
      exec 8>&-
      exit 0  # non-fatal — work is committed
    fi
    # `--autostash` DROPPED (2026-07-08, user-ratified constraint archaeology): after the
    # id:aa93 guard + id:dff8 carve-out it was dead code — every state the guard admits has
    # no tracked dirt, and --autostash stashes only TRACKED changes. The single place it
    # could still act is the check→pull race window (this flock serializes other
    # git-lock-push callers, NOT a parallel session's editor dirtying a tracked file right
    # here), and there it did the wrong thing silently: stash the foreign edit, rebase, pop
    # over a rewritten tree — the id:aa93 hazard in miniature. Plain --rebase makes that
    # race REFUSE loudly instead. Two failure modes, handled separately below:
    #   refused-to-start (dirty tree, no rebase state) → warn + exit 0, same
    #     committed-locally-not-pushed contract as the guard;
    #   mid-rebase CONFLICT (rebase state left in the repo) → exit 1 LOUD, never exit-0
    #     over a wedged tree — the caller's merge-conflict procedure owns it.
    if ! git pull --rebase $target; then
      if [[ -d "$(git rev-parse --git-path rebase-merge)" || -d "$(git rev-parse --git-path rebase-apply)" ]]; then
        echo "ERROR: rebase conflicted mid-flight — repo left in rebase state; resolve or 'git rebase --abort', then push manually." >&2
        exec 8>&-
        exit 1
      fi
      echo "WARNING: rebase refused to start (tracked changes appeared between the dirty-check and the pull). Commit saved locally, not pushed (id:aa93 race backstop)." >&2
      echo "Run 'git push' manually once the tree settles." >&2
      exec 8>&-
      exit 0  # non-fatal — work is committed
    fi
  fi
fi

# Never invoke askpass or open a browser for SSH auth — if the agent has no key
# loaded, commit stays local and retries on the next tick (same as flock timeout).
if ! ssh-add -l >/dev/null 2>&1; then
  echo "WARNING: no SSH key loaded in agent; commit is local, will push on next run." >&2
  exec 8>&-
  exit 0
fi

# push to all remotes (skip guard pushurls); set upstream on first push
# --follow-tags: push annotated, reachable tags alongside the branch (checkpoint + version tags)
# GIT_SSH_COMMAND: BatchMode=yes prevents any interactive auth prompt; ConnectTimeout avoids
# hanging on a tunnelled fallback (cloudflared access ssh) when the LAN detection misfires.
current_branch="$(git rev-parse --abbrev-ref HEAD)"
for remote in $(git remote); do
  pushurl=$(git remote get-url --push "$remote")
  [ "$pushurl" = "no_push" ] && continue
  if git ls-remote --exit-code "$remote" "refs/heads/$current_branch" >/dev/null 2>&1; then
    GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" git push --follow-tags "$remote"
  else
    GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" git push --follow-tags --set-upstream "$remote" "$current_branch"
  fi
done

exec 8>&-
