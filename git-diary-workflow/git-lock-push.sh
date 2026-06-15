#!/usr/bin/env bash
# git-lock-push.sh — flock-serialized (stage+commit +) pull + push
#
# Two modes:
#   Legacy mode (no -f/-m): Run AFTER git commit — the commit is local and safe;
#     only the pull+push needs serialization.
#   Manifest mode (-f <file> -m <msg>): stage+commit+pull+push inside flock
#     Only the listed paths are staged (never git add -A).
#
# Usage: git-lock-push.sh [REPO_PATH] [-b branch] [-f manifest-file] [-m msg] [--ff-only]
#   -b          Branch to rebase against (default: detected from tracking branch)
#   -f          Manifest file (one path per line) — requires -m
#   -m          Commit message — requires -f
#   --ff-only   Use fast-forward-only reconcile instead of rebase; fails loud on divergence.
#               Use this when the local branch has annotated tags or --no-ff merges that must
#               not be rewritten (e.g. the relay integration branch).

set -euo pipefail

branch=""
manifest_file=""
commit_msg=""
ff_only=0
# getopts does not handle long opts; strip --ff-only before the getopts loop
args=()
for arg in "$@"; do
  if [[ "$arg" == "--ff-only" ]]; then
    ff_only=1
  else
    args+=("$arg")
  fi
done
set -- "${args[@]+"${args[@]}"}"

while getopts "b:f:m:" opt; do
  case "$opt" in
    b) branch="$OPTARG" ;;
    f) manifest_file="$OPTARG" ;;
    m) commit_msg="$OPTARG" ;;
    *) echo "Usage: $0 [REPO_PATH] [-b branch] [-f manifest-file] [-m msg] [--ff-only]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [[ -n "$manifest_file" && -z "$commit_msg" ]]; then
  echo "ERROR: -f requires -m (commit message)" >&2; exit 1
fi
if [[ -n "$commit_msg" && -z "$manifest_file" ]]; then
  echo "ERROR: -m requires -f (manifest file)" >&2; exit 1
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
    git pull --rebase --autostash $target
  fi
fi

# push to all remotes (skip guard pushurls); set upstream on first push
# --follow-tags: push annotated, reachable tags alongside the branch (checkpoint + version tags)
current_branch="$(git rev-parse --abbrev-ref HEAD)"
for remote in $(git remote); do
  pushurl=$(git remote get-url --push "$remote")
  [ "$pushurl" = "no_push" ] && continue
  if git ls-remote --exit-code "$remote" "refs/heads/$current_branch" >/dev/null 2>&1; then
    git push --follow-tags "$remote"
  else
    git push --follow-tags --set-upstream "$remote" "$current_branch"
  fi
done

exec 8>&-
